import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import WebRTC

// Voice channels, compatible with the website: a WebRTC mesh between everyone
// in the channel, signalled through the same two collections —
//   VoicePresence  one doc per connected person (room, user, mute state)
//   VoiceSignal    offers / answers / ICE candidates addressed to one person
// The app checks for new signals every ~0.7 s (the website listens live).
@MainActor
@Observable
final class VoiceEngine: NSObject {
    struct Room: Equatable { var id: String; var name: String; var serverId: String; var serverName: String }
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
        init(id: String, email: String) { self.id = id; self.email = email }
    }
    private var peers: [String: Peer] = [:]
    private var byConnection: [ObjectIdentifier: String] = [:]

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
        systemCall = await call.start(title: "\(room.name) · \(room.serverName)")
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
        selfLevel = 0
        speakingSelf = false
        for peer in peers.values { peer.pc?.close() }
        peers = [:]
        byConnection = [:]
        localTrack = nil
        if let presenceId { try? await FS.delete("VoicePresence", presenceId) }
        presenceId = nil
        let was = room != nil
        room = nil
        connecting = false
        participants = []
        joinedAt = nil
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        systemCall = false
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        if was && !silent { Chime.play(.leave) }
    }

    func setMuted(_ value: Bool) {
        guard value != muted else { return }
        toggleMute()
    }

    // Speaker ↔ earpiece (or headphones).
    func toggleSpeaker() {
        speaker.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speaker ? .speaker : .none)
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
            "channel_id": room?.id ?? "", "community_id": room?.serverId ?? "", "room_type": "channel",
            "peer_id": selfId, "user_email": email,
            "user": ["display_name": name, "profile_picture": picture, "email": email] as [String: Any],
            "muted": muted, "deafened": deafened, "video": NSNull(),
            "last_active": Int(Date().timeIntervalSince1970 * 1000),
        ]
    }

    private func pushPresence() {
        guard let presenceId else { return }
        let fields: Doc = ["muted": muted, "deafened": deafened, "last_active": Int(Date().timeIntervalSince1970 * 1000)]
        Task { try? await FS.update("VoicePresence", presenceId, fields) }
    }

    // MARK: the loop: signals often, presence and heartbeat less often

    private func run() async {
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
            Chime.play(.leave)
        }
        refreshParticipants()
    }

    private func pollSignals() async {
        guard room != nil, !selfId.isEmpty else { return }
        guard let docs = try? await FS.query("VoiceSignal", [.equals("to_peer", selfId), .equals("to_email", email)]) else { return }
        for d in docs.sorted(by: { $0.str("created_date") < $1.str("created_date") }) {
            let id = d.str("id")
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
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        peer.pc = pc
        byConnection[ObjectIdentifier(pc)] = peer.id
        if let localTrack { pc.add(localTrack, streamIds: ["mic"]) }
        if peer.initiator {
            Task { await self.offer(peer) }
        }
    }

    private func offer(_ peer: Peer) async {
        guard let pc = peer.pc else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        let sdp: RTCSessionDescription? = await withCheckedContinuation { done in
            pc.offer(for: constraints) { sdp, _ in done.resume(returning: sdp) }
        }
        guard let sdp else { return }
        await setLocal(pc, sdp)
        send(peer, "description", ["type": "offer", "sdp": sdp.sdp])
    }

    private func makeAnswer(_ pc: RTCPeerConnection) async -> RTCSessionDescription? {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        return await withCheckedContinuation { done in
            pc.answer(for: constraints) { sdp, _ in done.resume(returning: sdp) }
        }
    }

    private func setLocal(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            pc.setLocalDescription(sdp) { _ in done.resume() }
        }
    }

    private func setRemote(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            pc.setRemoteDescription(sdp) { _ in done.resume() }
        }
    }

    private func addIce(_ pc: RTCPeerConnection, _ c: RTCIceCandidate) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            pc.add(c) { _ in done.resume() }
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

    fileprivate func stateChanged(_ pcId: ObjectIdentifier) {
        refreshParticipants()
    }

    // Who's talking and how loud (for the growing green ring), several
    // times a second, plus the ping now and then — all from connection stats.
    private func levelsLoop() async {
        var n = 0
        while !Task.isCancelled, room != nil {
            await measureLevels(withPing: n % 8 == 0)
            n += 1
            try? await Task.sleep(for: .milliseconds(160))
        }
    }

    private func measureLevels(withPing: Bool) async {
        var mine = 0.0
        var rtts: [Double] = []
        for peer in peers.values {
            guard let pc = peer.pc else { continue }
            let result: (Double, Double, Double) = await withCheckedContinuation { done in
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
                    done.resume(returning: (inbound, outbound, rtt))
                }
            }
            let heard = peer.muted || deafened ? 0 : result.0
            peer.level = max(heard, peer.level * 0.55)
            peer.speaking = peer.level > 0.015
            mine = max(mine, result.1)
            if result.2 >= 0 { rtts.append(result.2) }
        }
        selfLevel = muted ? 0 : max(mine, selfLevel * 0.55)
        speakingSelf = selfLevel > 0.015
        if withPing { ping = rtts.isEmpty ? nil : Int(rtts.reduce(0, +) / Double(rtts.count) * 1000) }
        refreshParticipants()
    }

    private static func shown(_ level: Double) -> Double {
        (min(1, level.squareRoot() * 1.7) * 20).rounded() / 20
    }

    private func refreshParticipants() {
        guard room != nil else { participants = []; return }
        var list = [Participant(id: selfId, email: email, name: name, picture: picture, muted: muted, deafened: deafened, speaking: speakingSelf, isSelf: true, connected: true, level: Self.shown(selfLevel))]
        for peer in peers.values.sorted(by: { $0.name < $1.name }) where !peer.email.isEmpty {
            let connected = peer.pc.map { $0.iceConnectionState == .connected || $0.iceConnectionState == .completed } ?? false
            list.append(Participant(id: peer.id, email: peer.email, name: peer.name.isEmpty ? String(peer.email.split(separator: "@").first ?? "") : peer.name,
                                    picture: peer.picture, muted: peer.muted, deafened: peer.deafened, speaking: peer.speaking, isSelf: false, connected: connected, level: Self.shown(peer.level)))
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
