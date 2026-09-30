import SwiftUI
import UIKit
import AudioToolbox
import AVKit
import WebRTC

// MARK: - DM and group calls

// Same as the website: a `Call` doc rings everyone in the chat and tracks
// ringing → active → ended; the audio runs through a voice room whose id is
// the call id. When a call finishes a small "call" message goes into the chat.
struct CallInfo: Identifiable, Equatable {
    var id: String
    var conversationId: String
    var isGroup: Bool
    var groupName: String
    var callerEmail: String
    var callerName: String
    var callerPicture: String
    var members: [String]
    var names: [String: String]
    var pictures: [String: String]
    var status: String
    var declinedBy: [String]
    var joined: [String]
    var startedAt: Double
    var answeredAt: Double?

    init(_ d: Doc) {
        id = d.str("id")
        conversationId = d.str("conversation_id")
        isGroup = d.str("conversation_type") == "group"
        groupName = d.str("group_name")
        callerEmail = d.str("caller_email").lowercased()
        callerName = d.str("caller_name")
        callerPicture = d.str("caller_picture")
        members = d.strs("member_emails").map { $0.lowercased() }
        names = (d["member_names"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        pictures = (d["member_pictures"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        status = d.str("status")
        declinedBy = d.strs("declined_by").map { $0.lowercased() }
        joined = d.strs("joined_emails").map { $0.lowercased() }
        startedAt = ReelText.num(d["started_at"]) ?? 0
        answeredAt = ReelText.num(d["answered_at"])
    }

    func title(for me: String) -> String {
        if isGroup { return groupName.isEmpty ? "Group call" : groupName }
        let other = members.first { $0 != me } ?? me
        return names[other] ?? String(other.split(separator: "@").first ?? "Call")
    }

    func picture(for me: String) -> String {
        if isGroup { return callerPicture }
        let other = members.first { $0 != me } ?? me
        return pictures[other] ?? ""
    }

    var ringing: Bool {
        status != "ended" && Date().timeIntervalSince1970 * 1000 - startedAt < CallCenter.ringMs
    }
}

@MainActor
@Observable
final class CallCenter {
    static let ringMs: Double = 45_000
    // One for the whole app (calls can be answered from iPhone's call
    // screen while the app's pages aren't open).
    static let shared = CallCenter()

    var incoming: CallInfo?
    var current: CallInfo?
    var showScreen = false
    var error: String?
    // While your call rings: why their phone can't ring if Sugerly is
    // closed there (nil when it could, or while that's being checked).
    var ringNote: String?

    @ObservationIgnored private weak var voice: VoiceEngine?
    @ObservationIgnored private var me: UserProfile?
    @ObservationIgnored private var ringTask: Task<Void, Never>?
    @ObservationIgnored private var dismissed = Set<String>()
    // Your own calls given up because the other person called you at the
    // same moment (both of you end up in their call instead).
    @ObservationIgnored private var merged = Set<String>()
    @ObservationIgnored private var watchToken: UUID?

    init() {
        attach(voice: VoiceEngine.shared)
        let bridge = VoiceEngine.shared.bridge
        bridge.onAnswer = { [weak self] id in Task { await self?.answerFromSystem(id) } }
        bridge.onDecline = { [weak self] id in Task { await self?.declineFromSystem(id) } }
    }

    // Logging out: forget everything about the last account's calls.
    func reset() {
        stopRinging()
        incoming = nil
        current = nil
        showScreen = false
        error = nil
        ringNote = nil
        me = nil
        dismissed = []
        merged = []
        watchToken = nil
    }

    func attach(voice: VoiceEngine) {
        self.voice = voice
        voice.onLeft = { [weak self] room in
            guard room.isCall else { return }
            Task { await self?.left(room.id) }
        }
    }

    // MARK: start / answer / decline

    func start(_ conversation: Conversation, model: AppModel) async {
        guard let me = model.me, let voice else { return }
        self.me = me
        // They're already calling you from this chat: calling back answers it.
        if let ringing = incoming, ringing.conversationId == conversation.id, ringing.ringing {
            await accept(ringing, me: me)
            return
        }
        if voice.room != nil { await voice.leave() }
        let members = Array(Set(conversation.members.isEmpty ? [me.email] : conversation.members + [me.email])).sorted()
        var names: [String: String] = [:]
        var pictures: [String: String] = [:]
        for email in members {
            if let p = model.person(email) { names[email] = p.displayName; if email != me.email { pictures[email] = p.picture } }
            else if email != me.email { names[email] = String(email.split(separator: "@").first ?? "") }
        }
        names[me.email] = me.displayName
        let now = Date().timeIntervalSince1970 * 1000
        let doc: Doc = [
            "conversation_id": conversation.id,
            "conversation_type": conversation.isGroup ? "group" : "dm",
            "group_name": conversation.isGroup ? conversation.groupName : "",
            "caller_email": me.email, "caller_name": me.displayName, "caller_picture": me.picture,
            "member_emails": members, "member_names": names, "member_pictures": pictures,
            "status": "ringing", "video": false, "declined_by": [String](), "joined_emails": [me.email],
            "started_at": Int(now), "answered_at": NSNull(), "ended_at": NSNull(),
        ]
        do {
            let created = try await FS.create("Call", doc)
            let call = CallInfo(created)
            current = call
            // Rings their phone even when Sugerly is closed there (iPhone's
            // own call screen). Without the server set up it still rings in
            // the app, and the call screen says what's missing.
            ringNote = nil
            let ringing = call.id
            Task { [weak self] in
                let note = await Self.ringPhones(ringing)
                if self?.current?.id == ringing { self?.ringNote = note }
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showScreen = true }
            await voice.join(room(call), me: me)
            ringback(call.id)
        } catch {
            self.error = "Couldn't start the call — \(error.localizedDescription)"
        }
    }

    func accept(_ call: CallInfo, me: UserProfile, fromSystem: Bool = false) async {
        guard let voice else { return }
        self.me = me
        stopRinging()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { incoming = nil }
        if voice.room != nil { await voice.leave() }
        let joined = Array(Set(call.joined + [me.email]))
        let fields: Doc = ["status": "active", "joined_emails": joined, "answered_at": Int(call.answeredAt ?? Date().timeIntervalSince1970 * 1000), "updated_date": FS.nowISO()]
        try? await FS.update("Call", call.id, fields)
        var next = call
        next.status = "active"
        next.joined = joined
        next.answeredAt = call.answeredAt ?? Date().timeIntervalSince1970 * 1000
        current = next
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showScreen = true }
        await voice.join(room(next), me: me, adoptSystemCall: fromSystem)
    }

    func decline(_ call: CallInfo, me: UserProfile) {
        decline(call, email: me.email)
    }

    private func decline(_ call: CallInfo, email: String) {
        stopRinging()
        dismissed.insert(call.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { incoming = nil }
        var fields: Doc = ["declined_by": Array(Set(call.declinedBy + [email])), "updated_date": FS.nowISO()]
        if !call.isGroup && call.status == "ringing" {
            fields["status"] = "ended"
            fields["ended_at"] = Int(Date().timeIntervalSince1970 * 1000)
        }
        Task { try? await FS.update("Call", call.id, fields) }
    }

    func hangUp() async {
        await voice?.leave()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showScreen = false }
    }

    private func room(_ call: CallInfo) -> VoiceEngine.Room {
        VoiceEngine.Room(id: call.id, name: call.title(for: me?.email ?? ""), serverId: "", serverName: call.isGroup ? "Group call" : "Call", kind: "call")
    }

    // Leaving: end the call when nobody else is left (always for 1:1 calls)
    // and post the summary message once.
    private func left(_ callId: String) async {
        // A call given up for theirs: nothing to end or report here.
        if merged.contains(callId) { return }
        ringTask?.cancel()
        ringNote = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showScreen = false }
        defer { current = nil }
        guard let me, let doc = try? await FS.get("Call", callId) else { return }
        let call = CallInfo(doc)
        let nowMs = Date().timeIntervalSince1970 * 1000
        let answered = call.answeredAt != nil || call.status == "active"
        if call.isGroup && call.status != "ended" {
            let docs = (try? await FS.query("VoicePresence", [.equals("channel_id", call.id)])) ?? []
            let others = docs.filter { $0.str("user_email").lowercased() != me.email && nowMs - (ReelText.num($0["last_active"]) ?? 0) < 35_000 }
            if !others.isEmpty { return }
        }
        let alreadyEnded = call.status == "ended"
        if !alreadyEnded { try? await FS.update("Call", call.id, ["status": "ended", "ended_at": Int(nowMs), "updated_date": FS.nowISO()]) }
        if answered {
            if !alreadyEnded { await postSummary(call, me: me, outcome: "ended", duration: nowMs - (call.answeredAt ?? nowMs)) }
        } else if call.callerEmail == me.email {
            await postSummary(call, me: me, outcome: call.declinedBy.isEmpty ? "missed" : "declined", duration: 0)
        }
    }

    private func postSummary(_ call: CallInfo, me: UserProfile, outcome: String, duration: Double) async {
        let now = FS.nowISO()
        let doc: Doc = [
            "conversation_id": call.conversationId, "conversation_type": call.isGroup ? "group" : "dm",
            "group_name": call.groupName, "type": "call", "call_outcome": outcome, "call_duration": Int(max(0, duration)),
            "call_video": false, "content": "", "image_url": "",
            "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
            "member_emails": call.members, "read_by": [me.email], "reactions": [String: Any](), "is_edited": false,
            "created_by": me.email, "created_date": now, "updated_date": now,
        ]
        _ = try? await FS.create("DirectMessage", doc)
    }

    // MARK: iPhone's call screen

    // A call push is ringing on iPhone's call screen: the in-app banner and
    // ringtone step aside so it doesn't ring twice.
    func systemRinging(_ callId: String) {
        guard incoming?.id == callId else { return }
        stopRinging()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { incoming = nil }
    }

    // Answered on iPhone's call screen (maybe with the app closed): load who
    // you are and the call, then join it on that same system call.
    func answerFromSystem(_ callId: String) async {
        dismissed.insert(callId)
        let profile: UserProfile?
        if let me { profile = me } else if let uid = AuthClient.shared.uid, let doc = try? await FS.get("User", uid) { profile = UserProfile(doc) } else { profile = nil }
        guard let profile, let doc = try? await FS.get("Call", callId) else {
            // Couldn't load it: hang up the answered system call.
            if voice?.bridge.adoptAnswered() == true { voice?.bridge.end() }
            return
        }
        let call = CallInfo(doc)
        guard call.status != "ended" else {
            if voice?.bridge.adoptAnswered() == true { voice?.bridge.end() }
            return
        }
        self.me = profile
        await accept(call, me: profile, fromSystem: true)
        // The app's pages may not be open: keep an eye on the call anyway.
        if watchToken == nil { Task { await watch(me: profile) } }
    }

    // Declined on iPhone's call screen.
    func declineFromSystem(_ callId: String) async {
        dismissed.insert(callId)
        guard let email = AuthClient.shared.email, let doc = try? await FS.get("Call", callId) else { return }
        decline(CallInfo(doc), email: email)
    }

    // MARK: watching for calls

    // Checks every few seconds for calls ringing you, and keeps the call
    // you're in up to date (answered, declined, ended by the other side).
    func watch(me: UserProfile) async {
        self.me = me
        // Only the newest watcher keeps going (one started after answering
        // from iPhone's call screen hands over to the app's own).
        let token = UUID()
        watchToken = token
        defer { if watchToken == token { watchToken = nil } }
        while !Task.isCancelled && watchToken == token {
            await check(me)
            try? await Task.sleep(for: .seconds(current != nil || incoming != nil ? 2 : 3.5))
        }
    }

    private func check(_ me: UserProfile) async {
        if let current {
            if let doc = try? await FS.get("Call", current.id) {
                let fresh = CallInfo(doc)
                if fresh != current { self.current = fresh }
                if fresh.status == "ended" && !fresh.isGroup && voice?.room?.id == fresh.id {
                    await voice?.leave()
                } else if fresh.status == "ringing" && !fresh.ringing && fresh.callerEmail == me.email && (voice?.participants.count ?? 0) <= 1 {
                    await voice?.leave() // nobody picked up
                }
            }
        }
        guard let docs = try? await FS.query("Call", [.contains("member_emails", me.email)], orderBy: "created_date", limit: 8) else { return }
        let calls = docs.map(CallInfo.init)
        let ringingMe = calls.first { c in
            c.callerEmail != me.email && c.ringing && !c.declinedBy.contains(me.email) && !c.joined.contains(me.email)
                && c.id != current?.id && !dismissed.contains(c.id) && !(voice?.bridge.isRinging(c.id) ?? false)
        }
        // You both called each other at the same moment: the call started
        // first wins and both of you end up in it, connected straight away,
        // instead of two calls ringing past each other.
        if let theirs = ringingMe, let mine = current, mine.callerEmail == me.email, mine.status == "ringing",
           Self.sameChat(mine, theirs) {
            if (mine.startedAt, mine.id) < (theirs.startedAt, theirs.id) {
                dismissed.insert(theirs.id)   // they'll join this one
            } else {
                merged.insert(mine.id)
                dismissed.insert(mine.id)
                try? await FS.update("Call", mine.id, ["status": "ended", "ended_at": Int(Date().timeIntervalSince1970 * 1000),
                                                     "merged_into": theirs.id, "updated_date": FS.nowISO()])
                await accept(theirs, me: me)
            }
            return
        }
        if let ringingMe {
            if incoming?.id != ringingMe.id {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { incoming = ringingMe }
                ring()
            }
        } else if incoming != nil {
            stopRinging()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { incoming = nil }
        }
    }

    // MARK: sounds

    private func ring() {
        ringTask?.cancel()
        ringTask = Task {
            while !Task.isCancelled, incoming != nil {
                CallTones.play(.ringtone)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(2.2))
            }
        }
    }

    private func ringback(_ id: String) {
        ringTask?.cancel()
        ringTask = Task {
            try? await Task.sleep(for: .seconds(1))
            while !Task.isCancelled, current?.id == id, current?.status == "ringing", (voice?.participants.count ?? 0) <= 1 {
                CallTones.play(.ringback)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopRinging() { ringTask?.cancel() }

    // Asks the server to ring the others' phones. Returns a short reason
    // when a closed Sugerly can't be rung, nil when it went through.
    private static func ringPhones(_ callId: String) async -> String? {
        let result: [String: Any]
        do {
            result = try await Payments.call("call-ring", ["call_id": callId])
        } catch {
            return "Their phone only rings while Sugerly is open (the call server isn't reachable yet)."
        }
        if (result["setup"] as? Bool) == false {
            return "Their phone only rings while Sugerly is open (the Apple call key isn't set up on the website)."
        }
        let sent = (result["sent"] as? Int) ?? (result["sent"] as? Double).map(Int.init) ?? 0
        if sent > 0 { return nil }
        let failures = (result["failures"] as? [String]) ?? []
        if let reason = failures.first {
            return "Apple couldn't ring their phone (\(reason))."
        }
        return "Their phone only rings while Sugerly is open until they open the new Sugerly once."
    }

    private static func sameChat(_ a: CallInfo, _ b: CallInfo) -> Bool {
        if !a.conversationId.isEmpty && a.conversationId == b.conversationId { return true }
        return !a.isGroup && !b.isGroup && Set(a.members) == Set(b.members)
    }
}

// MARK: - Incoming call banner

struct IncomingCallBanner: View {
    let call: CallInfo
    @Environment(AppModel.self) private var model
    @Environment(CallCenter.self) private var calls
    @State private var pulse = false

    var body: some View {
        let me = model.me?.email ?? ""
        HStack(spacing: 14) {
            ZStack {
                ForEach(0..<2) { i in
                    Circle().stroke(Palette.success.opacity(0.5), lineWidth: 2)
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: pulse)
                }
                Avatar(url: call.isGroup ? call.callerPicture : call.picture(for: me), name: call.title(for: me), size: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(call.title(for: me)).font(.jakarta(16, .heavy)).foregroundStyle(.white).lineLimit(1)
                Text(call.isGroup ? "\(call.callerName) started a group call" : "Incoming voice call…")
                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                if let meProfile = model.me { calls.decline(call, me: meProfile) }
            } label: {
                Image(systemName: "phone.down.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Palette.danger, in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .accessibilityLabel("Decline")
            Button {
                guard let meProfile = model.me else { return }
                Task { await calls.accept(call, me: meProfile) }
            } label: {
                Image(systemName: "phone.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Palette.success, in: Circle())
                    .rotationEffect(.degrees(pulse ? -12 : 12))
                    .animation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true), value: pulse)
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .accessibilityLabel("Answer")
        }
        .padding(14)
        .background(Color(hex: 0x2A1620), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: 520)
        .onAppear { pulse = true }
    }
}

// MARK: - Call screen

struct CallScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(CallCenter.self) private var calls
    @Environment(VoiceEngine.self) private var voice
    @State private var ringing = false
    @State private var ending = false
    // The big picture shows all of it by default; double-tap to fill.
    @State private var stageFill = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var me: String { model.me?.email ?? "" }
    private var call: CallInfo? { calls.current }
    private var others: [VoiceEngine.Participant] { voice.participants.filter { !$0.isSelf } }
    private var alone: Bool { others.isEmpty }

    // Someone showing their camera or screen gets the big stage (screens first).
    private var stage: (VoiceEngine.Participant, RTCVideoTrack)? {
        let showing = others.filter { !$0.video.isEmpty }.sorted { $0.video == "screen" && $1.video != "screen" }
        for p in showing { if let track = voice.remoteVideo[p.id] { return (p, track) } }
        return nil
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                if let shown = stage {
                    // Their camera or screen sits between the top bar and the
                    // buttons, whole and uncovered (it used to fill the screen
                    // behind the buttons, which hid most of them).
                    stageView(shown.0, shown.1)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if alone {
                                ringingHero.transition(.opacity.combined(with: .scale(scale: 0.95)))
                            } else if others.count == 1, let other = others.first {
                                oneToOne(other).transition(.opacity.combined(with: .scale(scale: 0.95)))
                            } else {
                                group.transition(.opacity)
                            }
                        }
                        .padding(.vertical, 24).frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                notices
                if stage != nil { compactControls } else { controls }
            }
            .padding(.bottom, 20)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: alone)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: others.count)
            if voice.cameraOn, let mine = voice.localVideo {
                selfPreview(mine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 70).padding(.trailing, 18)
                    .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: stage?.0.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: voice.cameraOn)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: voice.sharingScreen)
        .onChange(of: voice.sharingScreen) { _, sharing in
            // Sharing shows the rest of the app, so step out of the way.
            if sharing { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { calls.showScreen = false } }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    // A still background (moving blurred lights redrew the whole screen on
    // every frame and made the call stutter when anything else happened).
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A1320), Color(hex: 0x12080E)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.main.opacity(0.35), .clear], center: .init(x: 0.5, y: 0.32), startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { calls.showScreen = false } } label: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial.opacity(0.8), in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .accessibilityLabel("Minimise")
            Spacer()
            VStack(spacing: 2) {
                if stage != nil {
                    Text(title).font(.jakarta(15, .heavy)).foregroundStyle(.white).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                    if !alone, voice.joinedAt != nil { timer } else { Text("Encrypted") }
                }
                .font(.jakarta(12, .bold)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            quality.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // Signal bars from the ping: green, yellow, or red when the line is poor.
    @ViewBuilder
    private var quality: some View {
        if let ping = voice.ping, !alone {
            let color = ping < 180 ? Palette.success : ping < 400 ? Color(hex: 0xFFD166) : Palette.danger
            Image(systemName: "cellularbars", variableValue: ping < 180 ? 1 : ping < 400 ? 0.66 : 0.33)
                .font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                .accessibilityLabel(ping < 180 ? "Good connection" : ping < 400 ? "OK connection" : "Poor connection")
        }
    }

    private var title: String { call?.title(for: me) ?? voice.room?.name ?? "Call" }

    private var statusText: String {
        if voice.connecting { return "Connecting…" }
        if call?.status == "ended" { return "Call ended" }
        if call?.callerEmail == me || call == nil { return "Ringing…" }
        return "Connecting…"
    }

    private func name(_ p: VoiceEngine.Participant) -> String {
        p.isSelf ? "You" : (model.person(p.email)?.displayName ?? p.name)
    }

    // Big picture with soft rings while it rings (only then do they move).
    private var ringingHero: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle().stroke(Theme.light.opacity(0.35), lineWidth: 2)
                        .frame(width: 160, height: 160)
                        .scaleEffect(ringing ? 1.5 + Double(i) * 0.25 : 1)
                        .opacity(ringing ? 0 : 0.7)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i) * 0.6), value: ringing)
                }
                Avatar(url: call?.picture(for: me) ?? "", name: title, size: 150)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2))
            }
            .frame(height: 260)
            VStack(spacing: 6) {
                Text(title).font(.display(34)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2)
                Text(statusText).font(.jakarta(16, .semibold)).foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 24)
        }
        .onAppear { ringing = !reduceMotion }
        .onDisappear { ringing = false }
    }

    private var timer: some View {
        Group {
            if let since = voice.joinedAt {
                TimelineView(.periodic(from: since, by: 1)) { t in
                    Text(Self.clock(t.date.timeIntervalSince(since))).monospacedDigit()
                }
            }
        }
    }

    // Two people: their picture big in the middle, glowing green as they talk.
    private func oneToOne(_ other: VoiceEngine.Participant) -> some View {
        VStack(spacing: 18) {
            speakingAvatar(other, size: 170)
            VStack(spacing: 8) {
                Text(name(other)).font(.display(32)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 8) {
                    if !other.connected {
                        Label("Connecting audio…", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.jakarta(13, .bold)).foregroundStyle(Color(hex: 0xFFD166))
                    } else {
                        tag(other.speaking ? "Talking" : "In call", icon: other.speaking ? "waveform" : "phone.fill", tint: Palette.success)
                    }
                    if other.muted { tag("Muted", icon: "mic.slash.fill", tint: Palette.danger) }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func tag(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.jakarta(12, .bold)).foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.16), in: Capsule())
            .contentTransition(.opacity)
    }

    // Groups: a tile for everyone.
    private var group: some View {
        VStack(spacing: 14) {
            Text(title).font(.display(28)).foregroundStyle(.white).lineLimit(1)
            let list = voice.participants
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(list) { p in
                    VStack(spacing: 8) {
                        speakingAvatar(p, size: 76)
                        HStack(spacing: 4) {
                            if p.muted { Image(systemName: "mic.slash.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.danger) }
                            if !p.video.isEmpty { Image(systemName: p.video == "screen" ? "rectangle.on.rectangle" : "video.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.light) }
                            Text(name(p)).font(.jakarta(13, .bold)).foregroundStyle(.white).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white.opacity(p.speaking ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(p.speaking ? Palette.success.opacity(0.8) : .white.opacity(0.08), lineWidth: p.speaking ? 2 : 1))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: list.map(\.id))
        }
    }

    private func speakingAvatar(_ p: VoiceEngine.Participant, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Palette.success.opacity(0.22))
                .frame(width: size + 22, height: size + 22)
                .scaleEffect(p.speaking ? 1 + p.level * 0.22 : 0.9)
                .opacity(p.speaking ? 1 : 0)
            Circle().strokeBorder(Palette.success, lineWidth: 3)
                .frame(width: size + 10, height: size + 10)
                .opacity(p.speaking ? 1 : 0)
            Avatar(url: model.person(p.email)?.picture ?? p.picture, name: p.name, size: size)
                .opacity(p.connected || p.isSelf ? 1 : 0.55)
        }
        .animation(.easeOut(duration: 0.12), value: p.level)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: p.speaking)
    }

    // Their camera or screen, with their name at the bottom. Double-tap (or
    // the corner button) to switch between the whole picture and filling.
    private func stageView(_ p: VoiceEngine.Participant, _ track: RTCVideoTrack) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            VideoTrackView(track: track, fill: stageFill && p.video == "camera")
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(spacing: 8) {
                Avatar(url: model.person(p.email)?.picture ?? p.picture, name: p.name, size: 26)
                Text(p.video == "screen" ? "\(name(p))'s screen" : name(p)).font(.jakarta(13, .bold)).lineLimit(1)
                if p.muted { Image(systemName: "mic.slash.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.danger) }
                if p.speaking { Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.success).symbolEffect(.variableColor.iterative) }
            }
            .foregroundStyle(.white)
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            if p.video == "camera" {
                Button { withAnimation(.snappy) { stageFill.toggle() } } label: {
                    Image(systemName: stageFill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(BouncyStyle(scale: 0.85))
                .accessibilityLabel(stageFill ? "Show the whole picture" : "Fill the screen")
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(count: 2) { if p.video == "camera" { withAnimation(.snappy) { stageFill.toggle() } } }
    }

    // One slim row of buttons while a picture is showing, so it gets the room.
    private var compactControls: some View {
        HStack(spacing: 10) {
            roundControl(voice.muted ? "mic.slash.fill" : "mic.fill", on: voice.muted, label: voice.muted ? "Unmute" : "Mute") { voice.toggleMute() }
            roundControl(voice.cameraOn ? "video.fill" : "video.slash.fill", on: voice.cameraOn, label: "Camera") { Task { await voice.toggleCamera() } }
            roundControl("rectangle.on.rectangle", on: voice.sharingScreen, label: voice.sharingScreen ? "Stop share" : "Share screen") { voice.toggleScreenShare() }
            roundControl(voice.speaker ? "speaker.wave.3.fill" : "speaker.fill", on: voice.speaker, label: "Speaker") { voice.toggleSpeaker() }
            Button {
                guard !ending else { return }
                ending = true
                Task { await calls.hangUp(); ending = false }
            } label: {
                Image(systemName: "phone.down.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Palette.danger, in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .disabled(ending)
            .accessibilityLabel("End call")
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func roundControl(_ icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .bold))
                .foregroundStyle(on ? Color(hex: 0x1A0E15) : .white)
                .frame(width: 54, height: 54)
                .background(on ? Color.white : Color.white.opacity(0.14), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: on)
    }

    // Your own camera in a small corner card; tap the arrows to flip it.
    private func selfPreview(_ track: RTCVideoTrack) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VideoTrackView(track: track, fill: true, mirror: voice.frontCamera)
                .frame(width: 104, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            Button { Task { await voice.flipCamera() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .accessibilityLabel("Flip camera")
            .padding(6)
        }
    }

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 10) {
            if voice.sharingScreen {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.light)
                    Text("You're sharing your screen").font(.jakarta(13, .bold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button("Stop") { voice.stopScreenShare() }
                        .font(.jakarta(13, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Palette.danger, in: Capsule())
                        .buttonStyle(BouncyStyle(scale: 0.9))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if alone, call?.status == "ringing", let note = calls.ringNote {
                Label(note, systemImage: "bell.slash.fill")
                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            }
            if let error = voice.error ?? calls.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Color(hex: 0xFFD166))
                    .padding(14).frame(maxWidth: .infinity)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            }
            if voice.muted {
                Label("Your microphone is off", systemImage: "mic.slash.fill")
                    .font(.jakarta(13, .bold)).foregroundStyle(Theme.light)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.3), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                control(voice.muted ? "mic.slash.fill" : "mic.fill", on: voice.muted, label: voice.muted ? "Unmute" : "Mute") { voice.toggleMute() }
                control(voice.cameraOn ? "video.fill" : "video.slash.fill", on: voice.cameraOn, label: voice.cameraOn ? "Camera on" : "Camera") {
                    Task { await voice.toggleCamera() }
                }
                control("rectangle.on.rectangle", on: voice.sharingScreen, label: voice.sharingScreen ? "Stop share" : "Share screen") { voice.toggleScreenShare() }
                control(voice.speaker ? "speaker.wave.3.fill" : "speaker.fill", on: voice.speaker, label: "Speaker") { voice.toggleSpeaker() }
                VStack(spacing: 8) {
                    RoutePicker()
                        .frame(width: 62, height: 62)
                        .background(Color.white.opacity(0.14), in: Circle())
                        .accessibilityLabel("Audio output")
                    Text("Audio").font(.jakarta(12, .bold)).foregroundStyle(.white.opacity(0.75))
                }
                control("bubble.left.and.bubble.right.fill", on: false, label: "Chat") { openChat() }
            }
            Button {
                guard !ending else { return }
                ending = true
                Task { await calls.hangUp(); ending = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "phone.down.fill").font(.system(size: 20, weight: .bold))
                    Text("End call").font(.jakarta(16, .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 58)
                .background(Palette.danger, in: Capsule())
                .shadow(color: Palette.danger.opacity(0.45), radius: 14, y: 6)
            }
            .buttonStyle(BouncyStyle(scale: 0.95))
            .disabled(ending)
            .accessibilityLabel("End call")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func control(_ icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(on ? Color(hex: 0x1A0E15) : .white)
                    .frame(width: 62, height: 62)
                    .background(on ? Color.white : Color.white.opacity(0.14), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .accessibilityLabel(label)
            .sensoryFeedback(.impact(weight: .light), trigger: on)
            Text(label).font(.jakarta(12, .bold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // Opens this call's chat and keeps the call going in the little bar.
    private func openChat() {
        guard let id = call?.conversationId, !id.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { calls.showScreen = false }
        Alerts.shared.destination = Alerts.Destination(kind: "dm", target: id)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// Shows a live camera or screen picture from the call.
struct VideoTrackView: UIViewRepresentable {
    let track: RTCVideoTrack
    var fill = true
    var mirror = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = fill ? .scaleAspectFill : .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .black
        VideoRelay.relay(for: track).attach(view)
        context.coordinator.track = track
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = fill ? .scaleAspectFill : .scaleAspectFit
        view.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if context.coordinator.track !== track {
            if let old = context.coordinator.track { VideoRelay.existing(for: old)?.detach(view) }
            VideoRelay.relay(for: track).attach(view)
            context.coordinator.track = track
        }
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        if let track = coordinator.track { VideoRelay.existing(for: track)?.detach(view) }
    }

    final class Coordinator { var track: RTCVideoTrack? }
}

// Passes a call's live picture to whichever views show it and keeps the
// last frame. A shared screen only sends a new frame when something on it
// changes, so a view opened later (reopening the call screen) stayed black
// until then; now it shows the last picture straight away.
final class VideoRelay: NSObject, RTCVideoRenderer {
    private static let registry = NSLock()
    private static var relays: [ObjectIdentifier: VideoRelay] = [:]

    static func relay(for track: RTCVideoTrack) -> VideoRelay {
        registry.lock()
        defer { registry.unlock() }
        if let known = relays[ObjectIdentifier(track)] { return known }
        let made = VideoRelay(track)
        relays[ObjectIdentifier(track)] = made
        track.add(made)
        return made
    }

    static func existing(for track: RTCVideoTrack) -> VideoRelay? {
        registry.lock()
        defer { registry.unlock() }
        return relays[ObjectIdentifier(track)]
    }

    // Leaving a call: let go of every picture.
    static func forgetAll() {
        registry.lock()
        let all = Array(relays.values)
        relays = [:]
        registry.unlock()
        for relay in all { relay.track.remove(relay) }
    }

    // Held so its address is never reused by another track while listed.
    private let track: RTCVideoTrack
    private let lock = NSLock()
    private var views: [RTCVideoRenderer] = []
    private var lastFrame: RTCVideoFrame?
    private var size = CGSize.zero

    private init(_ track: RTCVideoTrack) {
        self.track = track
        super.init()
    }

    func attach(_ view: RTCVideoRenderer) {
        lock.lock()
        views.append(view)
        let frame = lastFrame, known = size
        lock.unlock()
        if known != .zero { view.setSize(known) }
        if let frame { view.renderFrame(frame) }
    }

    func detach(_ view: RTCVideoRenderer) {
        lock.lock()
        views.removeAll { $0 === view }
        lock.unlock()
    }

    func setSize(_ size: CGSize) {
        lock.lock()
        self.size = size
        let list = views
        lock.unlock()
        for view in list { view.setSize(size) }
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        lock.lock()
        if let frame { lastFrame = frame }
        let list = views
        lock.unlock()
        for view in list { view.renderFrame(frame) }
    }
}

// Apple's picker for AirPods, Bluetooth and the phone speaker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(Theme.light)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
