import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import ReplayKit
import WebRTC

// Voice channels, compatible with the website: a WebRTC mesh between everyone
// in the channel, signalled through the same two collections —
//   VoicePresence  one doc per connected person (room, user, mute state)
//   VoiceSignal    offers / answers / ICE candidates addressed to one person
// The app checks for new signals every ~0.7 s (the website listens live).
@MainActor
@Observable
final class VoiceEngine: NSObject {
    struct Room: Equatable {
        var id: String
        var name: String
        var serverId: String
        var serverName: String
        var kind = "channel"   // "channel" (server voice) or "call" (DM / group call)
        var isCall: Bool { kind == "call" }
    }

    // Told when you leave a room (calls use it to end / log the call).
    @ObservationIgnored var onLeft: ((Room) -> Void)?
    struct Participant: Identifiable, Equatable {
        var id: String // peer id
        var email: String
        var name: String
        var picture: String
        var muted: Bool
        var deafened: Bool
        var speaking: Bool
        var isSelf: Bool
        var connected: Bool
        var level: Double = 0 // 0…1, how loud they are right now
        var video = ""        // "", "camera" or "screen"
    }

    var room: Room?
    var connecting = false
    var muted = false
    var deafened = false
    var speakingSelf = false
    var participants: [Participant] = []
    var error: String?
    var joinedAt: Date?
    var speaker = true
    var ping: Int?
    var systemCall = false

    // Video: your camera or your screen, and everyone else's picture.
    var cameraOn = false
    var sharingScreen = false
    var frontCamera = true
    var remoteVideo: [String: RTCVideoTrack] = [:]   // by peer id
    private(set) var localVideo: RTCVideoTrack?
    @ObservationIgnored private var videoSource: RTCVideoSource?
    @ObservationIgnored private var cameraCapturer: RTCCameraVideoCapturer?
    @ObservationIgnored private var screenCapturer: RTCVideoCapturer?
    private var videoState: String { sharingScreen ? "screen" : cameraOn ? "camera" : "" }

    private var selfId = ""
    private var email = ""
    private var name = ""
    private var picture = ""
    private var presenceId: String?
    private var loop: Task<Void, Never>?
    private let factory: RTCPeerConnectionFactory
    private var localTrack: RTCAudioTrack?
    private let call = CallBridge()
    private var levelLoop: Task<Void, Never>?
    private var selfLevel = 0.0

    private final class Peer {
        let id: String
        var email: String
        var name = ""
        var picture = ""
        var muted = false
        var deafened = false
        var speaking = false
        var pc: RTCPeerConnection?
        var initiator = false
        var pendingIce: [RTCIceCandidate] = []
        var lastSeen = Date()
        var remoteTrack: RTCAudioTrack?
        var level = 0.0
        var video: RTCRtpTransceiver?   // the lane pictures travel on
        var videoKind = ""              // what they're showing ("", "camera", "screen")
        init(id: String, email: String) { self.id = id; self.email = email }
    }
    private var peers: [String: Peer] = [:]
    private var byConnection: [ObjectIdentifier: String] = [:]
    // Signals already used (a signal can come back once more before it's deleted).
    private var handled = Set<String>()
    private var restartedAt: [String: Date] = [:]

    override init() {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
        // Audio starts when iOS hands us the call's audio (CallKit), not before.
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        super.init()
        call.onMute = { [weak self] muted in self?.setMuted(muted) }
        call.onEnd = { [weak self] in Task { await self?.leave() } }
    }

    var isConnected: Bool { room != nil && !connecting }

    // True while you're in a call or voice channel: music, reels and voice
    // notes then leave the audio setup alone (switching it to plain playback
    // turned the microphone and the other person's voice off).
    nonisolated(unsafe) static var live = false

    // Where to connect through. Direct first (STUN); relay servers (TURN)
    // carry the audio when two phones can't reach each other directly, e.g.
    // one on mobile data. Fetched from our server, kept for a few hours.
    private static var relays: [RTCIceServer] = []
    private static var relaysFetched = Date.distantPast
    private static let direct = RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478"])

    private var relaysLoading = false

    private func loadRelays() async {
        relaysLoading = true
        defer { relaysLoading = false }
        guard Date().timeIntervalSince(Self.relaysFetched) > 4 * 3600 || Self.relays.isEmpty else { return }
        guard let json = try? await Payments.call("turn-credentials", [:]),
              let list = json["iceServers"] as? [[String: Any]] else { return }
        let servers: [RTCIceServer] = list.compactMap { entry in
            let urls = (entry["urls"] as? [String]) ?? ((entry["urls"] as? String).map { [$0] } ?? [])
            let turn = urls.filter { $0.hasPrefix("turn") }
            guard !turn.isEmpty else { return nil }
            return RTCIceServer(urlStrings: turn, username: entry["username"] as? String, credential: entry["credential"] as? String)
        }
        if !servers.isEmpty {
            Self.relays = servers
            Self.relaysFetched = Date()
        }
    }

    // MARK: join / leave

    func join(_ room: Room, me: UserProfile, canSpeak: Bool = true) async {
        if self.room != nil { await leave() }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            error = "Microphone access is off — turn it on in Settings → Sugerly."
            return
        }
        error = nil
        self.room = room
        connecting = true
        muted = !canSpeak
        deafened = false
        selfId = "p_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
        email = me.email
        name = me.displayName
        picture = me.picture

        speaker = true
        ping = nil
        handled = []
        Self.live = true
        Task { await self.loadRelays() }
        systemCall = await call.start(title: room.isCall ? room.name : "\(room.name) · \(room.serverName)")
        if !systemCall {
            // No CallKit: run the audio ourselves.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try? session.setActive(true)
            RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
            RTCAudioSession.sharedInstance().isAudioEnabled = true
        }

        let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = factory.audioTrack(with: source, trackId: "mic-\(selfId)")
        track.isEnabled = !muted
        localTrack = track

        do {
            let doc = try await FS.create("VoicePresence", presenceDoc())
            presenceId = doc.str("id")
        } catch {
            self.error = "Couldn't join: \(error.localizedDescription)"
            await leave(silent: true)
            return
        }
        connecting = false
        joinedAt = Date()
        call.connected()
        Chime.play(.join)
        refreshParticipants()
        loop = Task { [weak self] in await self?.run() }
        levelLoop = Task { [weak self] in await self?.levelsLoop() }
    }

    func leave(silent: Bool = false) async {
        loop?.cancel()
        loop = nil
        levelLoop?.cancel()
        levelLoop = nil
        call.end()
        if cameraOn { await cameraCapturer?.stopCapture() }
        if sharingScreen { RPScreenRecorder.shared().stopCapture { _ in } }
        cameraCapturer = nil
        screenCapturer = nil
        cameraOn = false
        sharingScreen = false
        localVideo = nil
        videoSource = nil
        remoteVideo = [:]
        selfLevel = 0
        speakingSelf = false
        for peer in peers.values { peer.pc?.close() }
        peers = [:]
        byConnection = [:]
        localTrack = nil
        if let presenceId { try? await FS.delete("VoicePresence", presenceId) }
        presenceId = nil
        let was = room != nil
        let left = room
        room = nil
        Self.live = false
        handled = []
        connecting = false
        participants = []
        joinedAt = nil
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        systemCall = false
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        if was && !silent { Chime.play(.leave) }
        if let left { onLeft?(left) }
    }

    func setMuted(_ value: Bool) {
        guard value != muted else { return }
        toggleMute()
    }

    // Speaker ↔ earpiece (or headphones).
    func toggleSpeaker() {
        let next = !speaker
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(next ? .speaker : .none)
            speaker = next
        } catch {
            self.error = "Couldn't change the audio output. Try again."
        }
    }

    func toggleMute() {
        muted.toggle()
        localTrack?.isEnabled = !muted
        call.setMuted(muted)
        Chime.play(muted ? .mute : .unmute)
        pushPresence()
        refreshParticipants()
    }

    func toggleDeafen() {
        deafened.toggle()
        if deafened && !muted {
            muted = true
            localTrack?.isEnabled = false
        }
        for peer in peers.values { peer.remoteTrack?.isEnabled = !deafened }
        Chime.play(deafened ? .mute : .unmute)
        pushPresence()
        refreshParticipants()
    }

    private func presenceDoc() -> Doc {
        [
            "channel_id": room?.id ?? "", "community_id": room?.serverId ?? "", "room_type": room?.kind ?? "channel",
            "peer_id": selfId, "user_email": email,
            "user": ["display_name": name, "profile_picture": picture, "email": email] as [String: Any],
            "muted": muted, "deafened": deafened, "video": videoState.isEmpty ? NSNull() as Any : videoState as Any,
            "last_active": Int(Date().timeIntervalSince1970 * 1000),
        ]
    }

    private func pushPresence() {
        guard let presenceId else { return }
        let fields: Doc = ["muted": muted, "deafened": deafened, "video": videoState.isEmpty ? NSNull() as Any : videoState as Any,
                           "last_active": Int(Date().timeIntervalSince1970 * 1000)]
        Task { try? await FS.update("VoicePresence", presenceId, fields) }
    }

    // MARK: the loop: signals often, presence and heartbeat less often

    private func run() async {
        // Give the relay list a moment to arrive before connecting to anyone.
        let deadline = Date().addingTimeInterval(3)
        while relaysLoading && Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        var tick = 0
        while !Task.isCancelled, room != nil {
            await pollSignals()
            if tick % 4 == 0 { await pollPresence() }
            if tick % 14 == 0 { pushPresence() }
            tick += 1
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    private func pollPresence() async {
        guard let room else { return }
        guard let docs = try? await FS.query("VoicePresence", [.equals("channel_id", room.id)]) else { return }
        let now = Date().timeIntervalSince1970 * 1000
        var seen = Set<String>()
        for d in docs {
            let info = VoicePresenceInfo(d)
            guard info.peerId != selfId, !info.peerId.isEmpty else { continue }
            guard now - info.lastActive < 35_000 else { continue }
            seen.insert(info.peerId)
            let isNew = peers[info.peerId] == nil
            let peer = peers[info.peerId] ?? Peer(id: info.peerId, email: info.email)
            peer.name = info.name
            peer.picture = info.picture
            peer.muted = info.muted
            peer.deafened = info.deafened
            peer.videoKind = info.video
            peer.lastSeen = Date()
            peers[info.peerId] = peer
            // The lower id starts the connection (same rule as the website).
            if peer.pc == nil && selfId < info.peerId {
                peer.initiator = true
                connect(peer)
            }
            if isNew { Chime.play(.join) }
        }
        for (id, peer) in peers where !seen.contains(id) {
            peer.pc?.close()
            if let pc = peer.pc { byConnection[ObjectIdentifier(pc)] = nil }
            peers[id] = nil
            remoteVideo[id] = nil
            Chime.play(.leave)
        }
        refreshParticipants()
    }

    private func pollSignals() async {
        guard room != nil, !selfId.isEmpty else { return }
        guard let docs = try? await FS.query("VoiceSignal", [.equals("to_peer", selfId), .equals("to_email", email)]) else { return }
        for d in docs.sorted(by: { $0.str("created_date") < $1.str("created_date") }) {
            let id = d.str("id")
            guard !handled.contains(id) else { continue }
            handled.insert(id)
            Task { try? await FS.delete("VoiceSignal", id) }
            guard d.str("channel_id") == room?.id else { continue }
            let from = d.str("from_peer")
            let peer = peers[from] ?? Peer(id: from, email: d.str("user_email").lowercased())
            peers[from] = peer
            guard let data = d.str("payload").data(using: .utf8),
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if peer.pc == nil { connect(peer) }
            guard let pc = peer.pc else { continue }
            if d.str("kind") == "description" {
                let typeString = payload["type"] as? String ?? ""
                let sdp = payload["sdp"] as? String ?? ""
                let type = RTCSessionDescription.type(for: typeString)
                if type == .offer && pc.signalingState != .stable && peer.initiator {
                    continue // offer collision: we're the impolite side, keep ours
                }
                await setRemote(pc, RTCSessionDescription(type: type, sdp: sdp))
                for c in peer.pendingIce { await addIce(pc, c) }
                peer.pendingIce = []
                if type == .offer { adoptVideoLane(peer, pc) }
                if let picture = peer.video?.receiver.track as? RTCVideoTrack { remoteVideo[peer.id] = picture }
                if type == .offer {
                    if let answer = await makeAnswer(pc) {
                        await setLocal(pc, answer)
                        send(peer, "description", ["type": "answer", "sdp": answer.sdp])
                    }
                }
            } else if d.str("kind") == "ice" {
                let candidate = RTCIceCandidate(sdp: payload["candidate"] as? String ?? "",
                                                sdpMLineIndex: Int32((payload["sdpMLineIndex"] as? Int) ?? 0),
                                                sdpMid: payload["sdpMid"] as? String)
                if pc.remoteDescription != nil { await addIce(pc, candidate) } else { peer.pendingIce.append(candidate) }
            }
        }
    }

    private func send(_ peer: Peer, _ kind: String, _ payload: [String: Any]) {
        guard let room, let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        let doc: Doc = [
            "channel_id": room.id, "community_id": room.serverId, "from_peer": selfId, "to_peer": peer.id,
            "to_email": peer.email, "user_email": email, "kind": kind, "payload": json,
        ]
        Task { _ = try? await FS.create("VoiceSignal", doc) }
    }

    // MARK: WebRTC plumbing

    private func connect(_ peer: Peer) {
        let config = RTCConfiguration()
        config.iceServers = [Self.direct] + Self.relays
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        peer.pc = pc
        byConnection[ObjectIdentifier(pc)] = peer.id
        if let localTrack { pc.add(localTrack, streamIds: ["mic"]) }
        if peer.initiator {
            // A picture lane from the start, so turning the camera or screen
            // on later needs no new handshake.
            let setup = RTCRtpTransceiverInit()
            setup.direction = .sendRecv
            setup.streamIds = ["video"]
            peer.video = pc.addTransceiver(of: .video, init: setup)
            peer.video?.sender.track = videoState.isEmpty ? nil : localVideo
            Task { await self.offer(peer) }
        }
    }

    // The other side offered a picture lane: send ours back on it too.
    private func adoptVideoLane(_ peer: Peer, _ pc: RTCPeerConnection) {
        guard peer.video == nil, let lane = pc.transceivers.first(where: { $0.mediaType == .video }) else { return }
        lane.setDirection(.sendRecv, error: nil)
        lane.sender.track = videoState.isEmpty ? nil : localVideo
        peer.video = lane
    }

    // MARK: camera and screen

    private func ensureVideo() -> RTCVideoSource {
        if let videoSource { return videoSource }
        let source = factory.videoSource()
        videoSource = source
        localVideo = factory.videoTrack(with: source, trackId: "video-\(selfId)")
        return source
    }

    private func sendVideo(_ on: Bool) {
        for peer in peers.values { peer.video?.sender.track = on ? localVideo : nil }
    }

    func toggleCamera() async {
        if cameraOn { stopCamera(); return }
        guard room != nil else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            error = "Camera access is off — turn it on in Settings → Sugerly."
            return
        }
        if sharingScreen { stopScreenShare() }
        let source = ensureVideo()
        source.adaptOutputFormat(toWidth: 640, height: 480, fps: 24)
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == (frontCamera ? .front : .back) }) ?? devices.first else {
            error = "No camera found."
            return
        }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        func width(_ f: AVCaptureDevice.Format) -> Int { Int(CMVideoFormatDescriptionGetDimensions(f.formatDescription).width) }
        guard let format = formats.min(by: { abs(width($0) - 640) < abs(width($1) - 640) }) else { return }
        let fps = Int(min(24, format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 24))
        let capturer = cameraCapturer ?? RTCCameraVideoCapturer(delegate: source)
        try? await capturer.startCapture(with: device, format: format, fps: fps)
        cameraCapturer = capturer
        cameraOn = true
        sendVideo(true)
        pushPresence()
        refreshParticipants()
    }

    func stopCamera() {
        cameraCapturer?.stopCapture()
        cameraOn = false
        if !sharingScreen { sendVideo(false) }
        pushPresence()
        refreshParticipants()
    }

    func flipCamera() async {
        frontCamera.toggle()
        guard cameraOn else { return }
        cameraOn = false
        await toggleCamera()
    }

    // Shares what's on your screen in Sugerly (iOS asks first).
    func toggleScreenShare() {
        if sharingScreen { stopScreenShare(); return }
        guard room != nil else { return }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            error = "Screen sharing isn't available right now."
            return
        }
        if cameraOn { stopCamera() }
        let source = ensureVideo()
        source.adaptOutputFormat(toWidth: 720, height: 1280, fps: 15)
        let capturer = RTCVideoCapturer(delegate: source)
        screenCapturer = capturer
        recorder.isMicrophoneEnabled = false
        recorder.startCapture(handler: { @Sendable buffer, type, failure in
            guard failure == nil, type == .video, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
            let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels), rotation: ._0, timeStampNs: Int64(time * 1_000_000_000))
            source.capturer(capturer, didCapture: frame)
        }, completionHandler: { [weak self] failure in
            Task { @MainActor in
                guard let self else { return }
                if let failure {
                    self.error = "Couldn't share your screen: \(failure.localizedDescription)"
                    self.screenCapturer = nil
                    return
                }
                self.sharingScreen = true
                self.sendVideo(true)
                self.pushPresence()
                self.refreshParticipants()
            }
        })
    }

    func stopScreenShare() {
        RPScreenRecorder.shared().stopCapture { _ in }
        screenCapturer = nil
        sharingScreen = false
        if !cameraOn { sendVideo(false) }
        pushPresence()
        refreshParticipants()
    }

    private func offer(_ peer: Peer, restart: Bool = false) async {
        guard let pc = peer.pc else { return }
        var mandatory = ["OfferToReceiveAudio": "true"]
        if restart { mandatory["IceRestart"] = "true" }
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatory, optionalConstraints: nil)
        let sdp: RTCSessionDescription? = await Wait.upTo(5, nil) { done in
            pc.offer(for: constraints) { sdp, _ in done(sdp) }
        }
        guard let sdp else { return }
        await setLocal(pc, sdp)
        send(peer, "description", ["type": "offer", "sdp": sdp.sdp])
    }

    private func makeAnswer(_ pc: RTCPeerConnection) async -> RTCSessionDescription? {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        return await Wait.upTo(5, nil) { done in
            pc.answer(for: constraints) { sdp, _ in done(sdp) }
        }
    }

    private func setLocal(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async {
        await Wait.upTo(5, ()) { done in
            pc.setLocalDescription(sdp) { _ in done(()) }
        }
    }

    private func setRemote(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async {
        await Wait.upTo(5, ()) { done in
            pc.setRemoteDescription(sdp) { _ in done(()) }
        }
    }

    private func addIce(_ pc: RTCPeerConnection, _ c: RTCIceCandidate) async {
        await Wait.upTo(3, ()) { done in
            pc.add(c) { _ in done(()) }
        }
    }

    fileprivate func candidate(_ pcId: ObjectIdentifier, _ c: RTCIceCandidate) {
        guard let id = byConnection[pcId], let peer = peers[id] else { return }
        send(peer, "ice", ["candidate": c.sdp, "sdpMid": c.sdpMid ?? "0", "sdpMLineIndex": Int(c.sdpMLineIndex)])
    }

    fileprivate func gotTrack(_ pcId: ObjectIdentifier, _ track: RTCAudioTrack) {
        guard let id = byConnection[pcId], let peer = peers[id] else { return }
        peer.remoteTrack = track
        track.isEnabled = !deafened
        refreshParticipants()
    }

    fileprivate func gotVideo(_ pcId: ObjectIdentifier, _ track: RTCVideoTrack) {
        guard let id = byConnection[pcId] else { return }
        remoteVideo[id] = track
        refreshParticipants()
    }

    fileprivate func stateChanged(_ pcId: ObjectIdentifier) {
        refreshParticipants()
        // The line dropped (e.g. Wi-Fi to mobile data): the side that started
        // the connection tries again on the new network.
        guard let id = byConnection[pcId], let peer = peers[id], let pc = peer.pc, peer.initiator,
              pc.iceConnectionState == .failed || pc.iceConnectionState == .disconnected else { return }
        if let last = restartedAt[id], Date().timeIntervalSince(last) < 6 { return }
        restartedAt[id] = Date()
        Task {
            if pc.iceConnectionState == .disconnected { try? await Task.sleep(for: .seconds(2)) }
            guard pc.iceConnectionState == .failed || pc.iceConnectionState == .disconnected else { return }
            await self.offer(peer, restart: true)
        }
    }

    // Who's talking and how loud (for the growing green ring), several
    // times a second, plus the ping now and then — all from connection stats.
    private func levelsLoop() async {
        var n = 0
        while !Task.isCancelled, room != nil {
            await measureLevels(withPing: n % 14 == 0)
            n += 1
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func measureLevels(withPing: Bool) async {
        var mine = 0.0
        var rtts: [Double] = []
        for peer in peers.values {
            guard let pc = peer.pc else { continue }
            let result: (Double, Double, Double) = await Wait.upTo(1, (0, 0, -1)) { done in
                pc.statistics { report in
                    var inbound = 0.0, outbound = 0.0, rtt = -1.0
                    for stat in report.statistics.values {
                        switch stat.type {
                        case "inbound-rtp":
                            if let v = stat.values["audioLevel"] as? NSNumber { inbound = max(inbound, v.doubleValue) }
                        case "media-source":
                            if let v = stat.values["audioLevel"] as? NSNumber { outbound = max(outbound, v.doubleValue) }
                        case "candidate-pair":
                            if (stat.values["nominated"] as? NSNumber)?.boolValue == true, let v = stat.values["currentRoundTripTime"] as? NSNumber { rtt = v.doubleValue }
                        default: break
                        }
                    }
                    done((inbound, outbound, rtt))
                }
            }
            let heard = peer.muted || deafened ? 0 : result.0
            peer.level = max(heard, peer.level * 0.4)
            peer.speaking = peer.level > 0.015
            mine = max(mine, result.1)
            if result.2 >= 0 { rtts.append(result.2) }
        }
        selfLevel = muted ? 0 : max(mine, selfLevel * 0.4)
        speakingSelf = selfLevel > 0.015
        if withPing { ping = rtts.isEmpty ? nil : Int(rtts.reduce(0, +) / Double(rtts.count) * 1000) }
        refreshParticipants()
    }

    private static func shown(_ level: Double) -> Double {
        (min(1, level.squareRoot() * 1.7) * 20).rounded() / 20
    }

    private func refreshParticipants() {
        guard room != nil else { participants = []; return }
        var list = [Participant(id: selfId, email: email, name: name, picture: picture, muted: muted, deafened: deafened, speaking: speakingSelf, isSelf: true, connected: true, level: Self.shown(selfLevel), video: videoState)]
        for peer in peers.values.sorted(by: { $0.name < $1.name }) where !peer.email.isEmpty {
            let connected = peer.pc.map { $0.iceConnectionState == .connected || $0.iceConnectionState == .completed } ?? false
            list.append(Participant(id: peer.id, email: peer.email, name: peer.name.isEmpty ? String(peer.email.split(separator: "@").first ?? "") : peer.name,
                                    picture: peer.picture, muted: peer.muted, deafened: peer.deafened, speaking: peer.speaking, isSelf: false, connected: connected, level: Self.shown(peer.level), video: peer.videoKind))
        }
        if list != participants { participants = list }
    }
}

extension VoiceEngine: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let id = ObjectIdentifier(peerConnection)
        guard let track = stream.audioTracks.first else { return }
        Task { @MainActor in self.gotTrack(id, track) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let id = ObjectIdentifier(peerConnection)
        Task { @MainActor in self.stateChanged(id) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let id = ObjectIdentifier(peerConnection)
        Task { @MainActor in self.candidate(id, candidate) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        let id = ObjectIdentifier(peerConnection)
        if let video = rtpReceiver.track as? RTCVideoTrack {
            Task { @MainActor in self.gotVideo(id, video) }
            return
        }
        guard let track = rtpReceiver.track as? RTCAudioTrack else { return }
        Task { @MainActor in self.gotTrack(id, track) }
    }
}

// Little join / leave / mute sounds (like the website's tones).
@MainActor
enum Chime {
    enum Kind { case join, leave, mute, unmute }
    static func play(_ kind: Kind) {
        let generator = UIImpactFeedbackGenerator(style: kind == .join ? .medium : .light)
        generator.impactOccurred()
        let id: SystemSoundID
        switch kind {
        case .join: id = 1113
        case .leave: id = 1114
        case .mute: id = 1104
        case .unmute: id = 1105
        }
        AudioServicesPlaySystemSound(id)
    }
}

// Waits for a WebRTC answer, but never forever: if the reply doesn't come
// (a closed or restarting connection), the call carries on with the fallback
// instead of freezing.
enum Wait {
    static func upTo<T>(_ seconds: Double, _ fallback: T, _ body: (@escaping @Sendable (T) -> Void) -> Void) async -> T {
        await withCheckedContinuation { (done: CheckedContinuation<T, Never>) in
            let once = Once(done)
            body { once.resume($0) }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(fallback)
            }
        }
    }

    private final class Once<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        init(_ c: CheckedContinuation<T, Never>) { continuation = c }
        func resume(_ value: T) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
