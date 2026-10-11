import Foundation
import WebRTC

// Sugar World multiplayer: everyone in a room is linked phone-to-phone
// (WebRTC data channels, like voice channels but carrying positions instead
// of sound), introduced to each other through two collections —
//   WorldPresence  one doc per player in a room (who, which room, their look)
//   WorldSignal    connection offers / answers addressed to one player
// Positions go ~12 times a second on a fast lane that may drop old ones;
// chat and outfit changes go on a lane that always arrives.
@MainActor
@Observable
final class WorldNet: NSObject {
    struct Pose {
        var pos: SIMD3<Float>
        var yaw: Float
        var speed: Float
        var air: Bool
    }

    struct Player: Identifiable, Equatable {
        var id: String          // peer id
        var email: String
        var name: String
        var picture: String
        var look: AvatarLook
        var connected = false
    }

    static let world = "plaza"
    static let roomSize = 10

    private(set) var room = ""
    private(set) var players: [String: Player] = [:]
    private(set) var online = false      // others can reach you
    var problem: String?

    @ObservationIgnored var onPose: ((String, Pose) -> Void)?
    @ObservationIgnored var onChat: ((String, String) -> Void)?
    @ObservationIgnored var onLook: ((String, AvatarLook) -> Void)?
    @ObservationIgnored var onLeave: ((String) -> Void)?
    @ObservationIgnored var onJoin: ((Player) -> Void)?
    @ObservationIgnored var onEmote: ((String, String) -> Void)?

    @ObservationIgnored private var selfId = ""
    @ObservationIgnored private var email = ""
    @ObservationIgnored private var name = ""
    @ObservationIgnored private var picture = ""
    @ObservationIgnored private var look = AvatarLook()
    @ObservationIgnored private var blocked: Set<String> = []
    @ObservationIgnored private var presenceId: String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var handled = Set<String>()
    @ObservationIgnored private var busyUntil = Date.distantPast

    private final class Link {
        let id: String
        var email: String
        var pc: RTCPeerConnection?
        var fast: RTCDataChannel?
        var sure: RTCDataChannel?
        var initiator = false
        var pendingIce: [RTCIceCandidate] = []
        var restartedAt = Date.distantPast
        init(id: String, email: String) { self.id = id; self.email = email }
    }
    @ObservationIgnored private var links: [String: Link] = [:]
    @ObservationIgnored private var byConnection: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var byChannel: [ObjectIdentifier: String] = [:]

    // Made when you join (not before). Voice's engine sets up the shared
    // audio first (hands off until a call), so joining never interrupts music.
    @ObservationIgnored private var factory: RTCPeerConnectionFactory?
    private static var relays: [RTCIceServer] = []
    private static var relaysFetched = Date.distantPast
    private static let direct = RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478"])

    var count: Int { players.count + 1 }
    var roomNumber: String { room.split(separator: "-").last.map(String.init) ?? "1" }

    // MARK: join / leave

    // `prefer`: a friend's room to join, if it still has space.
    func join(me: UserProfile, look: AvatarLook, prefer: String? = nil) async {
        guard room.isEmpty else { return }
        selfId = "w_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
        email = me.email
        name = me.displayName
        picture = me.picture
        self.look = look
        blocked = Set(me.blocked)
        problem = nil
        if factory == nil {
            _ = VoiceEngine.shared
            factory = RTCPeerConnectionFactory()
        }
        await loadRelays()
        room = await pickRoom(prefer: prefer)
        do {
            let doc = try await FS.create("WorldPresence", presenceDoc())
            presenceId = doc.str("id")
            online = true
        } catch {
            problem = "Playing solo for now — couldn't reach other players."
            online = false
            return
        }
        loop = Task { [weak self] in await self?.run() }
    }

    func leave() async {
        loop?.cancel()
        loop = nil
        for link in links.values { close(link) }
        links = [:]
        players = [:]
        byConnection = [:]
        byChannel = [:]
        if let presenceId { try? await FS.delete("WorldPresence", presenceId) }
        presenceId = nil
        room = ""
        online = false
    }

    // The first room with space; a new one when they're all full.
    private func pickRoom(prefer: String?) async -> String {
        let now = Date().timeIntervalSince1970 * 1000
        let docs = (try? await FS.query("WorldPresence", [.equals("world", Self.world)], limit: 400)) ?? []
        var counts: [Int: Int] = [:]
        for d in docs where now - (ReelText.num(d["last_active"]) ?? 0) < 35_000 {
            let number = Int(d.str("room").split(separator: "-").last ?? "") ?? 1
            counts[number, default: 0] += 1
        }
        if let prefer, let number = Int(prefer.split(separator: "-").last ?? ""), (counts[number] ?? 0) < Self.roomSize {
            return "\(Self.world)-\(number)"
        }
        var n = 1
        while (counts[n] ?? 0) >= Self.roomSize { n += 1 }
        return "\(Self.world)-\(n)"
    }

    private func presenceDoc() -> Doc {
        [
            "world": Self.world, "room": room, "peer_id": selfId, "user_email": email,
            "name": name, "picture": picture, "look": look.json,
            "last_active": Date().timeIntervalSince1970 * 1000,
        ]
    }

    // Your outfit changed while playing: everyone sees it straight away.
    func updateLook(_ next: AvatarLook) {
        look = next
        broadcast(["t": "look", "l": next.json], fast: false)
        guard let presenceId else { return }
        Task { try? await FS.update("WorldPresence", presenceId, ["look": next.json, "last_active": Date().timeIntervalSince1970 * 1000]) }
    }

    // Someone you just blocked disappears from your world.
    func hide(_ who: String) {
        let e = who.lowercased()
        blocked.insert(e)
        for (id, player) in players where player.email == e { drop(id) }
    }

    // MARK: sending

    func send(_ pose: Pose) {
        let msg: [String: Any] = [
            "p": [round(pose.pos.x * 100) / 100, round(pose.pos.y * 100) / 100, round(pose.pos.z * 100) / 100],
            "r": round(pose.yaw * 100) / 100, "s": round(pose.speed * 100) / 100, "a": pose.air ? 1 : 0,
        ]
        broadcast(msg, fast: true)
    }

    func chat(_ text: String) {
        broadcast(["t": "chat", "m": String(text.prefix(140))], fast: false)
    }

    func emote(_ name: String) {
        broadcast(["t": "emote", "e": name], fast: false)
    }

    private func broadcast(_ msg: [String: Any], fast: Bool) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        for link in links.values {
            guard let channel = fast ? link.fast : link.sure, channel.readyState == .open else { continue }
            channel.sendData(buffer)
        }
    }

    private func hello(_ link: Link) {
        guard let channel = link.sure, channel.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: ["t": "hi", "l": look.json, "n": name]) else { return }
        channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    // MARK: the loop

    private func run() async {
        var tick = 0
        while !Task.isCancelled, !room.isEmpty {
            // Quick checks while someone is connecting, slower once settled.
            let busy = Date() < busyUntil
            if busy || tick % 3 == 0 { await pollSignals() }
            if tick % 4 == 0 { await pollPresence() }
            if tick % 12 == 0 { heartbeat() }
            tick += 1
            try? await Task.sleep(for: .milliseconds(busy ? 800 : 1200))
        }
    }

    private func heartbeat() {
        guard let presenceId else { return }
        Task { try? await FS.update("WorldPresence", presenceId, ["last_active": Date().timeIntervalSince1970 * 1000]) }
    }

    private func pollPresence() async {
        guard !room.isEmpty else { return }
        guard let docs = try? await FS.query("WorldPresence", [.equals("room", room)]) else { return }
        let now = Date().timeIntervalSince1970 * 1000
        var seen = Set<String>()
        for d in docs {
            let peer = d.str("peer_id")
            let who = d.str("user_email").lowercased()
            guard !peer.isEmpty, peer != selfId else { continue }
            guard now - (ReelText.num(d["last_active"]) ?? 0) < 35_000 else {
                // Gone for a while: tidy it away (anyone may remove stale ones).
                if now - (ReelText.num(d["last_active"]) ?? 0) > 90_000 { Task { try? await FS.delete("WorldPresence", d.str("id")) } }
                continue
            }
            // Someone you blocked (or the same account on another phone) isn't shown.
            guard !blocked.contains(who), who != email else { continue }
            seen.insert(peer)
            let isNew = players[peer] == nil
            var player = players[peer] ?? Player(id: peer, email: who, name: d.str("name"), picture: d.str("picture"), look: AvatarLook(json: d.str("look")))
            let newLook = AvatarLook(json: d.str("look"))
            if player.look != newLook {
                player.look = newLook
                onLook?(peer, newLook)
            }
            player.name = d.str("name")
            player.picture = d.str("picture")
            players[peer] = player
            if isNew { onJoin?(player) }
            let link = links[peer] ?? Link(id: peer, email: who)
            links[peer] = link
            // The lower id starts the connection.
            if link.pc == nil && selfId < peer {
                link.initiator = true
                connect(link)
                busyUntil = Date().addingTimeInterval(20)
            }
        }
        for id in Array(players.keys) where !seen.contains(id) { drop(id) }
    }

    private func drop(_ id: String) {
        if let link = links[id] { close(link) }
        links[id] = nil
        players[id] = nil
        onLeave?(id)
    }

    private func close(_ link: Link) {
        link.fast?.close()
        link.sure?.close()
        link.pc?.close()
        if let pc = link.pc { byConnection[ObjectIdentifier(pc)] = nil }
        if let c = link.fast { byChannel[ObjectIdentifier(c)] = nil }
        if let c = link.sure { byChannel[ObjectIdentifier(c)] = nil }
        link.pc = nil
        link.fast = nil
        link.sure = nil
    }

    private func pollSignals() async {
        guard !room.isEmpty else { return }
        guard let docs = try? await FS.query("WorldSignal", [.equals("to_peer", selfId), .equals("to_email", email)]) else { return }
        for d in docs.sorted(by: { $0.str("created_date") < $1.str("created_date") }) {
            let id = d.str("id")
            guard !handled.contains(id) else { continue }
            handled.insert(id)
            Task { try? await FS.delete("WorldSignal", id) }
            guard d.str("room") == room else { continue }
            let from = d.str("from_peer")
            let who = d.str("user_email").lowercased()
            guard !from.isEmpty, !blocked.contains(who) else { continue }
            let link = links[from] ?? Link(id: from, email: who)
            links[from] = link
            busyUntil = Date().addingTimeInterval(20)
            guard let data = d.str("payload").data(using: .utf8),
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if link.pc == nil { connect(link) }
            guard let pc = link.pc else { continue }
            if d.str("kind") == "description" {
                let type = RTCSessionDescription.type(for: payload["type"] as? String ?? "")
                if type == .offer && pc.signalingState != .stable && link.initiator { continue }
                await setRemote(pc, RTCSessionDescription(type: type, sdp: payload["sdp"] as? String ?? ""))
                for c in link.pendingIce { await addIce(pc, c) }
                link.pendingIce = []
                if type == .offer, let answer = await makeAnswer(pc) {
                    await setLocal(pc, answer)
                    signal(link, "description", ["type": "answer", "sdp": answer.sdp])
                }
            } else if d.str("kind") == "ice" {
                let candidate = RTCIceCandidate(sdp: payload["candidate"] as? String ?? "",
                                                sdpMLineIndex: Int32((payload["sdpMLineIndex"] as? Int) ?? 0),
                                                sdpMid: payload["sdpMid"] as? String)
                if pc.remoteDescription != nil { await addIce(pc, candidate) } else { link.pendingIce.append(candidate) }
            }
        }
        if handled.count > 600 { handled = Set(handled.suffix(200)) }
    }

    private func signal(_ link: Link, _ kind: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        let doc: Doc = [
            "room": room, "from_peer": selfId, "to_peer": link.id, "to_email": link.email,
            "user_email": email, "kind": kind, "payload": json,
        ]
        Task { _ = try? await FS.create("WorldSignal", doc) }
    }

    // MARK: WebRTC plumbing

    private func loadRelays() async {
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

    private func connect(_ link: Link) {
        let config = RTCConfiguration()
        config.iceServers = [Self.direct] + Self.relays
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
        guard let pc = factory?.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        link.pc = pc
        byConnection[ObjectIdentifier(pc)] = link.id
        // Both sides make the same two lanes up front (agreed ids), so no
        // extra handshake is needed for them.
        let fast = RTCDataChannelConfiguration()
        fast.isNegotiated = true
        fast.channelId = 1
        fast.isOrdered = false
        fast.maxRetransmits = 0
        let sure = RTCDataChannelConfiguration()
        sure.isNegotiated = true
        sure.channelId = 2
        sure.isOrdered = true
        link.fast = pc.dataChannel(forLabel: "pose", configuration: fast)
        link.sure = pc.dataChannel(forLabel: "talk", configuration: sure)
        for channel in [link.fast, link.sure].compactMap({ $0 }) {
            channel.delegate = self
            byChannel[ObjectIdentifier(channel)] = link.id
        }
        if link.initiator { Task { await self.offer(link) } }
    }

    private func offer(_ link: Link, restart: Bool = false) async {
        guard let pc = link.pc else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: restart ? ["IceRestart": "true"] : nil, optionalConstraints: nil)
        let sdp: RTCSessionDescription? = await Wait.upTo(5, nil) { done in
            pc.offer(for: constraints) { sdp, _ in done(sdp) }
        }
        guard let sdp else { return }
        await setLocal(pc, sdp)
        signal(link, "description", ["type": "offer", "sdp": sdp.sdp])
    }

    private func makeAnswer(_ pc: RTCPeerConnection) async -> RTCSessionDescription? {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return await Wait.upTo(5, nil) { done in
            pc.answer(for: constraints) { sdp, _ in done(sdp) }
        }
    }

    private func setLocal(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async {
        await Wait.upTo(5, ()) { done in pc.setLocalDescription(sdp) { _ in done(()) } }
    }

    private func setRemote(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async {
        await Wait.upTo(5, ()) { done in pc.setRemoteDescription(sdp) { _ in done(()) } }
    }

    private func addIce(_ pc: RTCPeerConnection, _ c: RTCIceCandidate) async {
        await Wait.upTo(3, ()) { done in pc.add(c) { _ in done(()) } }
    }

    fileprivate func candidate(_ pcId: ObjectIdentifier, _ c: RTCIceCandidate) {
        guard let id = byConnection[pcId], let link = links[id] else { return }
        signal(link, "ice", ["candidate": c.sdp, "sdpMid": c.sdpMid ?? "0", "sdpMLineIndex": Int(c.sdpMLineIndex)])
    }

    fileprivate func iceChanged(_ pcId: ObjectIdentifier) {
        guard let id = byConnection[pcId], let link = links[id], let pc = link.pc else { return }
        let state = pc.iceConnectionState
        players[id]?.connected = state == .connected || state == .completed
        // The line dropped (e.g. Wi-Fi to mobile data): the side that started
        // tries again.
        guard link.initiator, state == .failed || state == .disconnected,
              Date().timeIntervalSince(link.restartedAt) > 6 else { return }
        link.restartedAt = Date()
        Task {
            if pc.iceConnectionState == .disconnected { try? await Task.sleep(for: .seconds(2)) }
            guard pc.iceConnectionState == .failed || pc.iceConnectionState == .disconnected else { return }
            await self.offer(link, restart: true)
        }
    }

    fileprivate func channelOpened(_ chId: ObjectIdentifier) {
        guard let id = byChannel[chId], let link = links[id], let sure = link.sure, ObjectIdentifier(sure) == chId,
              sure.readyState == .open else { return }
        players[id]?.connected = true
        hello(link)
    }

    fileprivate func received(_ chId: ObjectIdentifier, _ data: Data) {
        guard let id = byChannel[chId], players[id] != nil,
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let p = msg["p"] as? [Double], p.count == 3 {
            let pose = Pose(pos: SIMD3(Float(p[0]), Float(p[1]), Float(p[2])),
                            yaw: Float(msg["r"] as? Double ?? 0),
                            speed: Float(msg["s"] as? Double ?? 0),
                            air: (msg["a"] as? Int ?? 0) == 1)
            onPose?(id, pose)
            return
        }
        switch msg["t"] as? String ?? "" {
        case "chat":
            let text = (msg["m"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { onChat?(id, String(text.prefix(140))) }
        case "emote":
            if let name = msg["e"] as? String { onEmote?(id, name) }
        case "look", "hi":
            if let json = msg["l"] as? String {
                let next = AvatarLook(json: json)
                if players[id]?.look != next {
                    players[id]?.look = next
                    onLook?(id, next)
                }
            }
        default:
            break
        }
    }
}

extension WorldNet: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let id = ObjectIdentifier(peerConnection)
        Task { @MainActor in self.iceChanged(id) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let id = ObjectIdentifier(peerConnection)
        Task { @MainActor in self.candidate(id, candidate) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

extension WorldNet: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let id = ObjectIdentifier(dataChannel)
        let open = dataChannel.readyState == .open
        Task { @MainActor in if open { self.channelOpened(id) } }
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let id = ObjectIdentifier(dataChannel)
        let data = buffer.data
        Task { @MainActor in self.received(id, data) }
    }
}
