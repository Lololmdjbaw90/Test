import SwiftUI

// Block, ignore, message requests and your status (like Discord).
@MainActor
enum Privacy {
    static func setBlocked(_ email: String, _ on: Bool, model: AppModel) async {
        guard let me = model.me else { return }
        let e = email.lowercased()
        var blocked = me.blocked.filter { $0 != e }
        var following = me.following
        if on {
            blocked.append(e)
            following.removeAll { $0 == e }
        }
        await save(["blocked": blocked, "following": following], model: model,
                   done: on ? "Blocked. They can't message you or see you around." : "Unblocked", icon: "hand.raised.fill")
    }

    // Ignored people can still see you, but they never ping you: no
    // notifications, their chats tucked away and their posts hidden.
    static func setIgnored(_ email: String, _ on: Bool, model: AppModel) async {
        guard let me = model.me else { return }
        let e = email.lowercased()
        var ignored = me.ignored.filter { $0 != e }
        if on { ignored.append(e) }
        await save(["ignored": ignored], model: model, done: on ? "Ignored. You won't hear from them." : "No longer ignored", icon: on ? "bell.slash.fill" : "bell.fill")
    }

    static func accept(_ email: String, model: AppModel) async {
        guard let me = model.me else { return }
        let e = email.lowercased()
        guard !me.acceptedChats.contains(e) else { return }
        await save(["accepted_chats": me.acceptedChats + [e]], model: model, done: "Request accepted. Say hi!", icon: "checkmark.bubble.fill")
    }

    static func setPresence(_ presence: Presence, model: AppModel) async {
        await save(["presence": presence.rawValue], model: model, done: nil, icon: presence.icon)
    }

    static func setStatus(_ text: String, until: Date?, model: AppModel) async {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard await TextGuard.clear([clean], kind: .profile, model: model) else { return }
        await save(["custom_status": clean, "custom_status_until": until.map(Dates.iso) ?? ""], model: model,
                   done: clean.isEmpty ? "Status cleared" : "Status set", icon: "bubble.left.fill")
    }

    private static func save(_ fields: Doc, model: AppModel, done: String?, icon: String) async {
        do {
            try await model.updateMe(fields)
            if let done { model.showToast(done, icon: icon) }
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }
}

// The little status badge on a picture: green online, yellow moon idle,
// red do-not-disturb.
struct PresenceDot: View {
    let presence: Presence
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(Palette.surface)
            switch presence {
            case .online:
                Circle().fill(Color(hex: presence.color)).padding(size * 0.16)
            case .idle:
                Image(systemName: "moon.fill").font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(Color(hex: presence.color)).rotationEffect(.degrees(-20))
            case .dnd:
                Circle().fill(Color(hex: presence.color)).padding(size * 0.16)
                Capsule().fill(.white).frame(width: size * 0.4, height: size * 0.14)
            case .invisible, .offline:
                Circle().strokeBorder(Color(hex: presence.color), lineWidth: size * 0.16).padding(size * 0.16)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(presence.label)
    }
}

// Set your presence and a custom status (with when it clears).
struct StatusSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var presence: Presence = .online
    @State private var text = ""
    @State private var clearAfter = 0
    @State private var saving = false

    private let clearOptions: [(String, Double?)] = [("Don't clear", nil), ("30 min", 1800), ("1 hour", 3600), ("4 hours", 14_400), ("Today", -1)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom status").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2)
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left.fill").foregroundStyle(Theme.main)
                            TextField("What's up? e.g. drawing all day", text: $text).font(.jakarta(15))
                            if !text.isEmpty {
                                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                                    .accessibilityLabel("Clear")
                            }
                        }
                        .padding(.horizontal, 14).frame(height: 50)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                        Text("Clear after").font(.jakarta(12, .bold)).foregroundStyle(Palette.muted).padding(.top, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(clearOptions.enumerated()), id: \.offset) { i, option in
                                    Chip(title: option.0, active: clearAfter == i) { withMotion(Motion.standard) { clearAfter = i } }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Online status").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2)
                        VStack(spacing: 0) {
                            ForEach([Presence.online, .idle, .dnd, .invisible]) { p in
                                Button { withMotion(Motion.standard) { presence = p } } label: {
                                    HStack(spacing: 12) {
                                        PresenceDot(presence: p, size: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(p.label).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                                            Text(p.hint).font(.jakarta(12)).foregroundStyle(Palette.muted)
                                        }
                                        Spacer()
                                        if presence == p {
                                            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.main)
                                                .transition(.pop)
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(SoftPressStyle())
                                if p != .invisible { Divider().padding(.leading, 46) }
                            }
                        }
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    }
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().tint(.white) } else { Text("Save") }
                    }
                    .buttonStyle(GradientButtonStyle(height: 50))
                    .disabled(saving)
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("Your status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            guard let me = model.me else { return }
            presence = Presence(rawValue: me.presence) ?? .online
            if presence == .offline { presence = .online }
            text = me.activeStatus
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let option = clearOptions[clearAfter].1
        let until: Date? = {
            guard let option else { return nil }
            if option < 0 { return Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400) }
            return Date().addingTimeInterval(option)
        }()
        if presence.rawValue != (model.me?.presence ?? "") { await Privacy.setPresence(presence, model: model) }
        if text != (model.me?.activeStatus ?? "") || clearAfter != 0 {
            await Privacy.setStatus(text, until: text.isEmpty ? nil : until, model: model)
        } else {
            model.showToast("Status saved", icon: presence.icon)
        }
        dismiss()
    }
}

// Settings → Privacy: who you've blocked or ignored, with a way back.
struct PeopleListSheet: View {
    enum Kind { case blocked, ignored }
    let kind: Kind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var emails: [String] { kind == .blocked ? (model.me?.blocked ?? []) : (model.me?.ignored ?? []) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if emails.isEmpty {
                        EmptyCard(icon: kind == .blocked ? "hand.raised.fill" : "bell.slash.fill",
                                  title: kind == .blocked ? "No one blocked" : "No one ignored",
                                  text: kind == .blocked ? "Blocked people can't message you and you won't see their posts." : "Ignored people can't ping you, and their chats and posts are tucked away.")
                    }
                    ForEach(emails, id: \.self) { email in
                        let person = model.person(email)
                        HStack(spacing: 12) {
                            Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person?.displayName ?? email).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                Text(email).font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer()
                            Button(kind == .blocked ? "Unblock" : "Stop ignoring") {
                                Task {
                                    if kind == .blocked { await Privacy.setBlocked(email, false, model: model) }
                                    else { await Privacy.setIgnored(email, false, model: model) }
                                }
                            }
                            .buttonStyle(OutlineButtonStyle(height: 34))
                        }
                        .sugarCard(radius: 20, padding: 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(16)
                .motion(Motion.standard, value: emails)
            }
            .background(Palette.bg)
            .navigationTitle(kind == .blocked ? "Blocked" : "Ignored")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

extension PeopleListSheet.Kind: Identifiable {
    var id: Self { self }
}
