import SwiftUI
import UIKit
import AudioToolbox

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

    var incoming: CallInfo?
    var current: CallInfo?
    var showScreen = false
    var error: String?

    @ObservationIgnored private weak var voice: VoiceEngine?
    @ObservationIgnored private var me: UserProfile?
    @ObservationIgnored private var ringTask: Task<Void, Never>?
    @ObservationIgnored private var dismissed = Set<String>()

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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showScreen = true }
            await voice.join(room(call), me: me)
            ringback(call.id)
        } catch {
            self.error = "Couldn't start the call — \(error.localizedDescription)"
        }
    }

    func accept(_ call: CallInfo, me: UserProfile) async {
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
        await voice.join(room(next), me: me)
    }

    func decline(_ call: CallInfo, me: UserProfile) {
        stopRinging()
        dismissed.insert(call.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { incoming = nil }
        var fields: Doc = ["declined_by": Array(Set(call.declinedBy + [me.email])), "updated_date": FS.nowISO()]
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
        ringTask?.cancel()
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

    // MARK: watching for calls

    // Checks every few seconds for calls ringing you, and keeps the call
    // you're in up to date (answered, declined, ended by the other side).
    func watch(me: UserProfile) async {
        self.me = me
        while !Task.isCancelled {
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
                && c.id != current?.id && !dismissed.contains(c.id)
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
                AudioServicesPlaySystemSound(1151)
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
                AudioServicesPlaySystemSound(1106)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopRinging() { ringTask?.cancel() }
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
    @State private var breathe = false
    @State private var drift = false

    private var me: String { model.me?.email ?? "" }
    private var call: CallInfo? { calls.current }
    private var alone: Bool { voice.participants.filter { !$0.isSelf }.isEmpty }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 18) {
                HStack {
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { calls.showScreen = false } } label: {
                        Image(systemName: "chevron.down").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Minimise")
                    Spacer()
                    Label("End-to-end voice", systemImage: "lock.fill").font(.jakarta(11, .bold)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 10)
                if alone { ringingHero } else { people }
                Spacer(minLength: 10)
                controls
            }
            .padding(.bottom, 30)
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private var background: some View {
        ZStack {
            Color(hex: 0x1A0E15)
            Circle().fill(Theme.main.opacity(0.45)).frame(width: 420).blur(radius: 120)
                .offset(x: drift ? 120 : -120, y: drift ? -260 : -180)
            Circle().fill(Theme.lavender.opacity(0.3)).frame(width: 380).blur(radius: 120)
                .offset(x: drift ? -140 : 100, y: drift ? 300 : 220)
        }
        .ignoresSafeArea()
    }

    private var title: String { call?.title(for: me) ?? voice.room?.name ?? "Call" }

    private var statusText: String {
        if voice.connecting { return "Connecting…" }
        if alone {
            if call?.callerEmail == me || call == nil { return call?.status == "ended" ? "Call ended" : "Calling…" }
            return "Connecting…"
        }
        return ""
    }

    // Big picture with rings while it rings (like WhatsApp).
    private var ringingHero: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle().stroke(Theme.light.opacity(0.4), lineWidth: 2)
                        .frame(width: 150, height: 150)
                        .scaleEffect(breathe ? 1.25 + Double(i) * 0.22 : 1)
                        .opacity(breathe ? 0.05 : 0.6)
                }
                Avatar(url: call?.picture(for: me) ?? "", name: title, size: 140)
                    .shadow(color: Theme.main.opacity(0.5), radius: 30)
                    .scaleEffect(breathe ? 1.03 : 0.98)
            }
            Text(title).font(.display(34)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 20)
            Text(statusText).font(.jakarta(16, .semibold)).foregroundStyle(.white.opacity(0.75))
                .contentTransition(.opacity)
        }
    }

    // Everyone in the call, with the green ring when they talk.
    private var people: some View {
        VStack(spacing: 14) {
            Text(title).font(.display(28)).foregroundStyle(.white).lineLimit(1)
            if let since = voice.joinedAt {
                TimelineView(.periodic(from: since, by: 1)) { t in
                    Text(Self.clock(t.date.timeIntervalSince(since))).font(.jakarta(15, .bold)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                }
            }
            let list = voice.participants
            let columns = list.count <= 2 ? 1 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                ForEach(list) { p in
                    let size: CGFloat = list.count <= 2 ? 120 : 84
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Palette.success.opacity(0.25))
                                .frame(width: size + 16, height: size + 16)
                                .scaleEffect(p.speaking ? 1 + p.level * 0.3 : 0.9)
                                .opacity(p.speaking ? 1 : 0)
                            Circle().strokeBorder(Palette.success, lineWidth: 3.5)
                                .frame(width: size + 10, height: size + 10)
                                .opacity(p.speaking ? 1 : 0)
                            Avatar(url: model.person(p.email)?.picture ?? p.picture, name: p.name, size: size)
                                .opacity(p.connected || p.isSelf ? 1 : 0.5)
                        }
                        .animation(.easeOut(duration: 0.14), value: p.level)
                        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: p.speaking)
                        HStack(spacing: 4) {
                            if p.muted { Image(systemName: "mic.slash.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.danger) }
                            Text(p.isSelf ? "You" : p.name).font(.jakarta(14, .bold)).foregroundStyle(.white).lineLimit(1)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 30)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: list.map(\.id))
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            control(voice.speaker ? "speaker.wave.3.fill" : "speaker.fill", on: voice.speaker, label: "Speaker") { voice.toggleSpeaker() }
            control(voice.muted ? "mic.slash.fill" : "mic.fill", on: voice.muted, label: voice.muted ? "Unmute" : "Mute") { voice.toggleMute() }
            Button { Task { await calls.hangUp() } } label: {
                Image(systemName: "phone.down.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 74, height: 74).background(Palette.danger, in: Circle())
                    .shadow(color: Palette.danger.opacity(0.55), radius: 16, y: 6)
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .accessibilityLabel("End call")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func control(_ icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 22, weight: .bold))
                .foregroundStyle(on ? Color(hex: 0x1A0E15) : .white)
                .frame(width: 60, height: 60)
                .background(on ? Color.white : Color.white.opacity(0.16), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: on)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
