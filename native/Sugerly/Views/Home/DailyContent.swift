import SwiftUI

// The weekly challenge and the daily art prompt. Admins can add, remove and
// pin them (saved in SiteConfig, shared with everyone); until an admin edits
// a list, the built-in ones rotate.

struct Challenge: Hashable, Identifiable {
    var title: String
    var tag: String
    var icon: String
    var id: String { tag }

    init(title: String, tag: String, icon: String) {
        self.title = title
        self.tag = tag
        self.icon = icon
    }

    init?(_ doc: Doc) {
        let title = doc.str("title")
        guard !title.isEmpty else { return nil }
        self.title = title
        self.tag = doc.str("tag").isEmpty ? Challenge.tag(for: title) : doc.str("tag")
        self.icon = doc.str("icon").isEmpty ? "trophy.fill" : doc.str("icon")
    }

    var doc: Doc { ["title": title, "tag": tag, "icon": icon] }

    // "Dreamy skies!" → "dreamyskies"
    static func tag(for title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24))
    }
}

struct ArtPrompt: Hashable, Identifiable {
    var text: String
    var icon: String
    var id: String { text }

    init(text: String, icon: String) {
        self.text = text
        self.icon = icon
    }

    init?(_ doc: Doc) {
        let text = doc.str("text")
        guard !text.isEmpty else { return nil }
        self.text = text
        self.icon = doc.str("icon").isEmpty ? "paintbrush.pointed.fill" : doc.str("icon")
    }

    var doc: Doc { ["text": text, "icon": icon] }
}

@MainActor
enum DailyContent {
    static let builtInChallenges: [Challenge] = [
        Challenge(title: "Cosy corners", tag: "cosycorners", icon: "cup.and.saucer.fill"),
        Challenge(title: "Pastel monsters", tag: "pastelmonsters", icon: "pawprint.fill"),
        Challenge(title: "Dreamy skies", tag: "dreamyskies", icon: "cloud.sun.fill"),
        Challenge(title: "Sweet treats", tag: "sweettreats", icon: "birthday.cake.fill"),
        Challenge(title: "Magic school", tag: "magicschool", icon: "wand.and.stars"),
        Challenge(title: "Tiny worlds", tag: "tinyworlds", icon: "globe.europe.africa.fill"),
        Challenge(title: "Ocean friends", tag: "oceanfriends", icon: "fish.fill"),
        Challenge(title: "Flower power", tag: "flowerpower", icon: "camera.macro"),
        Challenge(title: "Space cadets", tag: "spacecadets", icon: "moon.stars.fill"),
        Challenge(title: "Redraw your old art", tag: "redrawit", icon: "arrow.triangle.2.circlepath"),
    ]

    static let builtInPrompts: [ArtPrompt] = [
        ArtPrompt(text: "A cat café on the moon", icon: "moon.stars.fill"), ArtPrompt(text: "Your favourite snack as a monster", icon: "fork.knife"),
        ArtPrompt(text: "A tiny house inside a teacup", icon: "cup.and.saucer.fill"), ArtPrompt(text: "Clouds that look like animals", icon: "cloud.fill"),
        ArtPrompt(text: "A dragon who loves flowers", icon: "leaf.fill"), ArtPrompt(text: "Your room, but underwater", icon: "drop.fill"),
        ArtPrompt(text: "A robot's first birthday", icon: "gift.fill"), ArtPrompt(text: "Pastel city at night", icon: "building.2.fill"),
        ArtPrompt(text: "A strawberry knight", icon: "shield.fill"), ArtPrompt(text: "Draw your mood as weather", icon: "cloud.sun.fill"),
        ArtPrompt(text: "A secret garden door", icon: "door.left.hand.open"), ArtPrompt(text: "Your OC on holiday", icon: "sun.max.fill"),
        ArtPrompt(text: "A bakery run by bunnies", icon: "birthday.cake.fill"), ArtPrompt(text: "Stars falling like snow", icon: "sparkles"),
        ArtPrompt(text: "A ghost who is scared of people", icon: "moon.fill"), ArtPrompt(text: "Magical girl transformation", icon: "wand.and.stars"),
        ArtPrompt(text: "A bus stop in a forest", icon: "tree.fill"), ArtPrompt(text: "Your favourite song as a picture", icon: "music.note"),
        ArtPrompt(text: "A frog prince, but make it cute", icon: "crown.fill"), ArtPrompt(text: "Rainy day window", icon: "cloud.rain.fill"),
        ArtPrompt(text: "A shop that sells dreams", icon: "bag.fill"), ArtPrompt(text: "A sleepy fox in autumn", icon: "leaf.fill"),
        ArtPrompt(text: "Candy planet", icon: "globe.europe.africa.fill"), ArtPrompt(text: "Sketch someone you admire", icon: "heart.fill"),
        ArtPrompt(text: "An island shaped like a heart", icon: "heart.circle.fill"), ArtPrompt(text: "A witch's messy desk", icon: "book.fill"),
        ArtPrompt(text: "A penguin astronaut", icon: "airplane"), ArtPrompt(text: "Butterflies made of glass", icon: "sparkle"),
        ArtPrompt(text: "A cosy reading nook", icon: "books.vertical.fill"), ArtPrompt(text: "Redraw an old drawing of yours", icon: "arrow.triangle.2.circlepath"),
    ]

    // Icons admins can pick from.
    static let icons = ["trophy.fill", "paintbrush.pointed.fill", "paintpalette.fill", "sparkles", "heart.fill", "star.fill", "moon.stars.fill",
                        "cloud.sun.fill", "leaf.fill", "pawprint.fill", "fish.fill", "birthday.cake.fill", "cup.and.saucer.fill",
                        "wand.and.stars", "crown.fill", "music.note", "camera.macro", "globe.europe.africa.fill", "gift.fill", "snowflake"]

    static var challenges: [Challenge] { SiteTheme.shared.challenges ?? builtInChallenges }
    static var prompts: [ArtPrompt] { SiteTheme.shared.prompts ?? builtInPrompts }

    static var challengePinned: Bool { challenges.contains { $0.tag == SiteTheme.shared.challengePinned } }
    static var promptPinned: Bool { prompts.contains { $0.text == SiteTheme.shared.promptPinned } }

    // This week's challenge: the pinned one, or the next in turn.
    static var challenge: Challenge? {
        let list = challenges
        guard !list.isEmpty else { return nil }
        if let pinned = list.first(where: { $0.tag == SiteTheme.shared.challengePinned }) { return pinned }
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date()) + cal.component(.yearForWeekOfYear, from: Date()) * 53
        return list[week % list.count]
    }

    // Today's prompt: the pinned one, or the next in turn.
    static var prompt: ArtPrompt? {
        let list = prompts
        guard !list.isEmpty else { return nil }
        if let pinned = list.first(where: { $0.text == SiteTheme.shared.promptPinned }) { return pinned }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return list[day % list.count]
    }
}

// A tiny "Edit" pill admins see on the cards.
struct AdminEditChip: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Edit", systemImage: "pencil").font(.jakarta(10, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 8).frame(height: 22)
                .background(.white.opacity(0.25), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
        .accessibilityLabel("Edit (admin)")
    }
}

// Admins add, remove and pin weekly challenges or daily prompts.
struct DailyContentEditor: View {
    enum Kind { case challenges, prompts }
    let kind: Kind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var challenges: [Challenge] = []
    @State private var prompts: [ArtPrompt] = []
    @State private var pinned = ""
    @State private var title = ""
    @State private var tag = ""
    @State private var icon = "trophy.fill"
    @State private var saving = false
    @State private var confirmReset = false

    private var isChallenges: Bool { kind == .challenges }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addCard
                    HStack {
                        Text(isChallenges ? "Weekly challenges" : "Daily prompts").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("\(isChallenges ? challenges.count : prompts.count)").font(.jakarta(13, .heavy)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 4)
                    Text(isChallenges ? "One shows each week, in turn. Pin one to show it until you unpin it." : "One shows each day, in turn. Pin one to show it until you unpin it.")
                        .font(.jakarta(12)).foregroundStyle(Palette.muted).padding(.horizontal, 4)
                    VStack(spacing: 8) {
                        if isChallenges {
                            ForEach(challenges) { c in row(title: c.title, subtitle: "#" + c.tag, icon: c.icon, key: c.tag) { remove(c.tag) } }
                        } else {
                            ForEach(prompts) { p in row(title: p.text, subtitle: nil, icon: p.icon, key: p.text) { remove(p.text) } }
                        }
                        if (isChallenges ? challenges.isEmpty : prompts.isEmpty) {
                            Text(isChallenges ? "No challenges — the card is hidden for everyone." : "No prompts — the card is hidden for everyone.")
                                .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                                .frame(maxWidth: .infinity).padding(20)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: challenges)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: prompts)
                    Button("Reset to the built-in list") { confirmReset = true }
                        .font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                        .frame(maxWidth: .infinity).padding(.top, 4)
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle(isChallenges ? "Weekly challenges" : "Daily art prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if saving { ProgressView() } else { Button("Done") { dismiss() }.font(.jakarta(15, .bold)) }
                }
            }
            .confirmationDialog("Reset to the built-in list?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    if isChallenges { challenges = DailyContent.builtInChallenges } else { prompts = DailyContent.builtInPrompts }
                    pinned = ""
                    Task { await save() }
                }
            }
        }
        .onAppear {
            challenges = DailyContent.challenges
            prompts = DailyContent.prompts
            pinned = isChallenges ? SiteTheme.shared.challengePinned : SiteTheme.shared.promptPinned
            icon = isChallenges ? "trophy.fill" : "paintbrush.pointed.fill"
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isChallenges ? "New challenge" : "New prompt", systemImage: "plus.circle.fill")
                .font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
            SugarField(placeholder: isChallenges ? "Title, e.g. Dreamy skies" : "Prompt, e.g. A cat café on the moon", text: $title)
            if isChallenges {
                SugarField(placeholder: "Hashtag (optional) — #\(Challenge.tag(for: title).isEmpty ? "dreamyskies" : Challenge.tag(for: title))", text: $tag)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DailyContent.icons, id: \.self) { name in
                        let on = icon == name
                        Button { withMotion(Motion.standard) { icon = name } } label: {
                            Image(systemName: name).font(.system(size: 16, weight: .bold))
                                .foregroundStyle(on ? .white : Palette.text2)
                                .frame(width: 40, height: 40)
                                .background(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.surface2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.9))
                    }
                }
            }
            Button { add() } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(GradientButtonStyle(height: 44))
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .sugarCard(radius: 22, padding: 14)
    }

    private func row(title: String, subtitle: String?, icon: String, key: String, delete: @escaping () -> Void) -> some View {
        let isPinned = pinned == key
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(2)
                if let subtitle { Text(subtitle).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 0)
            Button {
                pinned = isPinned ? "" : key
                Task { await save() }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isPinned ? Theme.main : Palette.muted)
                    .frame(width: 36, height: 36)
                    .background(isPinned ? Theme.soft : Palette.surface2, in: Circle())
            }
            .accessibilityLabel(isPinned ? "Unpin" : "Pin")
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0xE5484D))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xE5484D).opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Remove")
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
        .padding(10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isPinned ? Theme.main.opacity(0.5) : Palette.border, lineWidth: 1))
        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
    }

    private func add() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if isChallenges {
            var t = Challenge.tag(for: tag.isEmpty ? text : tag)
            if t.isEmpty { t = "challenge\(challenges.count + 1)" }
            guard !challenges.contains(where: { $0.tag == t }) else { model.showToast("#\(t) is already in the list", error: true); return }
            challenges.insert(Challenge(title: String(text.prefix(40)), tag: t, icon: icon), at: 0)
        } else {
            guard !prompts.contains(where: { $0.text == text }) else { model.showToast("That prompt is already in the list", error: true); return }
            prompts.insert(ArtPrompt(text: String(text.prefix(80)), icon: icon), at: 0)
        }
        title = ""
        tag = ""
        Task { await save() }
    }

    private func remove(_ key: String) {
        if isChallenges { challenges.removeAll { $0.tag == key } } else { prompts.removeAll { $0.text == key } }
        if pinned == key { pinned = "" }
        Task { await save() }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let fields: Doc = isChallenges
            ? ["challenges": challenges.map(\.doc), "challenge_pinned": pinned]
            : ["prompts": prompts.map(\.doc), "prompt_pinned": pinned]
        do {
            try await SiteTheme.shared.save(fields)
            if isChallenges {
                SiteTheme.shared.challenges = challenges
                SiteTheme.shared.challengePinned = pinned
            } else {
                SiteTheme.shared.prompts = prompts
                SiteTheme.shared.promptPinned = pinned
            }
            model.showToast("Saved for everyone", icon: "checkmark.seal.fill")
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }
}
