import SwiftUI
import PhotosUI

// The welcome setup a brand-new account sees once, before the app: name and
// bio, a photo, interests, colours, a few people to follow, then a little
// party with the 50-coin gift. Everything can be changed later in Settings.
struct WelcomeSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var outerScheme

    enum Step: Int, CaseIterable { case hello, you, photo, interests, style, friends }

    @State private var step: Step = .hello
    @State private var forward = true
    @State private var name = ""
    @State private var bio = ""
    @State private var picture: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropping: CropJob?
    @State private var interests: [String] = []
    @State private var theme = "light"
    @State private var accent: Accent = .rose
    @State private var follows: Set<String> = []
    @State private var saving = false
    @State private var error: String?
    @State private var done = false
    @State private var coins = 0
    @State private var appeared = false

    static let topics: [(String, String)] = [
        ("Painting", "paintpalette.fill"), ("Digital art", "paintbrush.pointed.fill"), ("Drawing", "pencil.and.scribble"),
        ("Photography", "camera.fill"), ("3D", "cube.fill"), ("Pixel art", "square.grid.3x3.fill"),
        ("Animation", "film.fill"), ("Comics", "text.bubble.fill"), ("Music", "music.note"),
        ("Lo-fi", "headphones"), ("Writing", "book.closed.fill"), ("Crafts", "scissors"),
        ("Fashion", "tshirt.fill"), ("Games", "gamecontroller.fill"),
    ]

    private var scheme: ColorScheme { theme == "dark" ? .dark : theme == "light" ? .light : outerScheme }

    var body: some View {
        ZStack {
            background
            if done {
                celebration
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        page
                            .id(step)
                            .transition(.asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                            .frame(maxWidth: 520)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 22)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    buttons
                }
            }
        }
        .environment(\.colorScheme, scheme)
        .onAppear(perform: fill)
        .photosPicker(isPresented: $pickingPhoto, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                cropping = CropJob(image: image, gif: nil, avatar: true)
            }
        }
        .fullScreenCover(item: $cropping) { job in
            ImageCropper(image: job.image, circle: true, aspect: 1, onDone: { rect in
                cropping = nil
                Task {
                    let image = job.image
                    let cropped = await Task.detached(priority: .userInitiated) { Cropping.crop(image, rect, maxSide: 800) }.value
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { picture = cropped }
                }
            }, onCancel: { cropping = nil })
        }
    }

    @State private var pickingPhoto = false

    // MARK: pieces

    // A plain background: the steps are the focus.
    private var background: some View {
        Palette.bg.ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border))
                        .frame(height: 6)
                        .frame(maxWidth: s == step ? 34 : 18)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: step)
            Spacer(minLength: 0)
            if step != .hello {
                Button("Skip") { Task { await skip() } }
                    .font(.jakarta(14, .bold)).foregroundStyle(Palette.muted)
                    .disabled(saving)
                    .transition(.opacity)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .hello: hello
        case .you: you
        case .photo: photo
        case .interests: interestsPage
        case .style: stylePage
        case .friends: friends
        }
    }

    private func title(_ text: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.display(34)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            Text(sub).font(.jakarta(15)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stagger(appeared, 0)
    }

    private var hello: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)
            BrandLogo(height: 58)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1), value: appeared)
            MimiBuddy(icon: "heart.fill", mood: .happy, size: 150)
            VStack(spacing: 8) {
                Text("Welcome, \(name.isEmpty ? "friend" : name)!")
                    .font(.display(36)).foregroundStyle(Theme.gradient).multilineTextAlignment(.center)
                Text("Let's set up your space. It takes about a minute, and you can change everything later.")
                    .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
            }
            .stagger(appeared, 2)
            HStack(spacing: 8) {
                CoinIcon(size: 22)
                Text("Finish to get 50 coins").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.45), value: appeared)
        }
        .frame(maxWidth: .infinity)
    }

    private var you: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("What should we call you?", "This is the name people see on your art, posts and chats.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Display name").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                SugarField(placeholder: "Your name", text: $name)
                    .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
            }
            .stagger(appeared, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Bio").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                SugarField(placeholder: "A line or two about you and your art", text: $bio, lines: 3...5)
                    .onChange(of: bio) { _, v in if v.count > 200 { bio = String(v.prefix(200)) } }
                Text("\(bio.count)/200").font(.jakarta(11)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .stagger(appeared, 2)
        }
    }

    @State private var pulse = false

    private var photo: some View {
        VStack(spacing: 22) {
            title("Add a photo", "So your friends recognise you. You can skip this for now.")
            Button { pickingPhoto = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Circle().stroke(Theme.gradient, lineWidth: 3)
                        .frame(width: 176, height: 176)
                        .scaleEffect(pulse ? 1.08 : 1)
                        .opacity(pulse ? 0.2 : 0.8)
                    Group {
                        if let picture {
                            Image(uiImage: picture).resizable().scaledToFill()
                        } else {
                            ZStack {
                                Circle().fill(Theme.soft)
                                Image(systemName: "person.fill").font(.system(size: 64)).foregroundStyle(Theme.gradient)
                            }
                        }
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .frame(width: 176, height: 176)
                    Image(systemName: "camera.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.gradient, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 3))
                        .offset(x: -8, y: -8)
                }
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel("Choose a photo")
            .stagger(appeared, 1)

            Button(picture == nil ? "Choose a photo" : "Choose another") { pickingPhoto = true }
                .buttonStyle(OutlineButtonStyle(height: 46))
                .stagger(appeared, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var interestsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("What are you into?", "Pick as many as you like. We use it to fill your feed with things you'll love.")
            FlowLayout(spacing: 8) {
                ForEach(Array(Self.topics.enumerated()), id: \.element.0) { i, topic in
                    let on = interests.contains(topic.0)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            if on { interests.removeAll { $0 == topic.0 } } else { interests.append(topic.0) }
                        }
                    } label: {
                        Label(topic.0, systemImage: on ? "checkmark" : topic.1)
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(on ? .white : Palette.text)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background {
                                if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface) }
                            }
                            .overlay(Capsule().strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                            .scaleEffect(on ? 1.04 : 1)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.9))
                    .sensoryFeedback(.selection, trigger: on)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05 + Double(i) * 0.03), value: appeared)
                }
            }
        }
    }

    private var stylePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Make it yours", "Pick how Sugerly looks. You'll see it change right away.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                HStack(spacing: 10) {
                    ForEach([("light", "Light", "sun.max.fill"), ("dark", "Dark", "moon.fill"), ("system", "Auto", "circle.lefthalf.filled")], id: \.0) { id, label, icon in
                        let on = theme == id
                        Button { withAnimation(.easeInOut(duration: 0.35)) { theme = id } } label: {
                            VStack(spacing: 8) {
                                Image(systemName: icon).font(.system(size: 20, weight: .bold))
                                Text(label).font(.jakarta(13, .bold))
                            }
                            .foregroundStyle(on ? Theme.main : Palette.text2)
                            .frame(maxWidth: .infinity).frame(height: 84)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Theme.main : Palette.border, lineWidth: on ? 2 : 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.94))
                    }
                }
            }
            .stagger(appeared, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Colour").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                HStack(spacing: 8) {
                    ForEach(Accent.allCases) { a in
                        let on = accent == a
                        Button { pick(a) } label: {
                            AccentCard(accent: a, picked: on, height: 80)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.94))
                        .sensoryFeedback(.selection, trigger: on)
                        .accessibilityLabel(a.label)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .stagger(appeared, 2)
            // A little preview card in the chosen look.
            HStack(spacing: 12) {
                Avatar(url: "", name: name.isEmpty ? "You" : name, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? "You" : name).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                    Text("Just posted a new drawing").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(Theme.gradient)
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .stagger(appeared, 3)
        }
    }

    // People to follow: ones who share your interests first, then the most active.
    private var suggestions: [UserProfile] {
        let mine = Set(interests.map { $0.lowercased() })
        let me = model.me?.email ?? ""
        return model.people.values
            .filter { $0.email != me && !$0.isBanned }
            .sorted { a, b in
                let sa = Set(a.interests.map { $0.lowercased() }).intersection(mine).count
                let sb = Set(b.interests.map { $0.lowercased() }).intersection(mine).count
                if sa != sb { return sa > sb }
                if a.xp != b.xp { return a.xp > b.xp }
                return a.displayName < b.displayName
            }
            .prefix(8)
            .map { $0 }
    }

    private var friends: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Find your people", "Follow a few artists to fill your feed. You can always find more in People.")
            let list = suggestions
            if list.isEmpty {
                VStack(spacing: 8) {
                    MimiBuddy(icon: "person.2.fill", mood: .happy, size: 110)
                    Text("You'll find friends in People once you're in.").font(.jakarta(14)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, person in
                let on = follows.contains(person.email)
                HStack(spacing: 12) {
                    Avatar(url: person.picture, name: person.displayName, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(person.interests.prefix(3).joined(separator: " · ").isEmpty ? "Lv. \(person.level) artist" : person.interests.prefix(3).joined(separator: " · "))
                            .font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    MorphPill(on: on, offTitle: "Follow", onTitle: "Following") {
                        withMotion(.spring(response: 0.34, dampingFraction: 0.78)) {
                            if on { follows.remove(person.email) } else { follows.insert(person.email) }
                        }
                    }
                }
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Theme.main.opacity(0.35) : Palette.border, lineWidth: 1))
                .stagger(appeared, i + 1)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            if let error {
                Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center).transition(.opacity)
            }
            HStack(spacing: 10) {
                if step != .hello {
                    Button { go(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(OutlineButtonStyle(height: 54))
                    .accessibilityLabel("Back")
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Button {
                    if step == .friends { Task { await finish() } }
                    else if step == .you { Task { await nextFromYou() } }
                    else { go(1) }
                } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(.white) }
                        Text(nextTitle)
                        if !saving && step != .friends { Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)) }
                    }
                }
                .buttonStyle(GradientButtonStyle(height: 54))
                .disabled(saving || (step == .you && name.trimmingCharacters(in: .whitespaces).isEmpty))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step == .hello)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private var nextTitle: String {
        switch step {
        case .hello: return "Let's go"
        case .photo: return picture == nil ? "Maybe later" : "Looks great"
        case .interests: return interests.isEmpty ? "Skip for now" : "Continue"
        case .friends: return saving ? "Saving…" : "Finish"
        default: return "Continue"
        }
    }

    private var celebration: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 150, height: 150).blur(radius: 40).opacity(0.55)
                Group {
                    if let picture {
                        Image(uiImage: picture).resizable().scaledToFill()
                    } else {
                        Avatar(url: model.me?.picture ?? "", name: name, size: 130)
                    }
                }
                .frame(width: 130, height: 130)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 4))
            }
            .overlay { SparkleBurst(radius: 100) }
            Text("You're all set!").font(.display(40)).foregroundStyle(Theme.main)
            Text("Welcome to Sugerly, \(name). Here's a little gift to get you started.")
                .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).padding(.horizontal, 30)
            HStack(spacing: 10) {
                CoinIcon(size: 34)
                Text("+\(coins)").font(.display(40)).foregroundStyle(Palette.text)
                    .contentTransition(.numericText(value: Double(coins)))
            }
            .padding(.horizontal, 22).frame(height: 64)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            .sensoryFeedback(.success, trigger: coins == 50)
            Spacer()
            Button("Start exploring") {
                Task { await model.finishSetup() }
            }
            .buttonStyle(GradientButtonStyle(height: 56))
            .frame(maxWidth: 520)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            RewardSound.play()
            for n in stride(from: 5, through: 50, by: 5) {
                withAnimation(.snappy(duration: 0.12)) { coins = n }
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }

    // MARK: actions

    private func fill() {
        guard let me = model.me else { return }
        if name.isEmpty { name = me.displayName }
        bio = me.bio
        interests = me.interests
        theme = me.theme.isEmpty ? "light" : me.theme
        accent = Accent(rawValue: me.accent) ?? .rose
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            appeared = true
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        error = nil
        forward = delta > 0
        appeared = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            appeared = true
        }
    }

    private func pick(_ a: Accent) {
        withAnimation(.easeInOut(duration: 0.45)) {
            accent = a
            // Show the colour everywhere straight away.
            Theme.accent = a
            Theme.custom = nil
        }
    }

    // The name and bio are checked before moving on, so a blocked name
    // shows up here and not as a dead Finish button at the end.
    private func nextFromYou() async {
        saving = true
        defer { saving = false }
        if await checkYou() { go(1) }
    }

    private func checkYou() async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let about = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Moderation.hasLink(about) else {
            withMotion { error = "Links aren't allowed in your bio." }
            return false
        }
        guard await TextGuard.clear([trimmed], kind: .name, model: model, cooldown: false),
              await TextGuard.clear([about], kind: .profile, model: model, cooldown: false) else {
            let reason = guardReason()
            withMotion { error = reason }
            return false
        }
        return true
    }

    // The word filter explains itself in a toast, but toasts sit behind this
    // screen, so the reason is shown above the buttons instead.
    private func guardReason() -> String {
        let reason = model.toast.flatMap { $0.error ? $0.text : nil }
        model.toast = nil
        return reason ?? "That name or bio can't be used. Try something else."
    }

    private func finish() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Pick a display name."; return }
        let about = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        defer { saving = false }
        guard await checkYou() else {
            // Back to the name page so it can be changed there.
            let reason = error
            go(Step.you.rawValue - step.rawValue)
            error = reason
            return
        }
        do {
            var fields: Doc = [
                "display_name": trimmed, "full_name": trimmed, "search_name": trimmed.lowercased(),
                "bio": String(about.prefix(200)), "interests": interests, "theme": theme, "accent": accent.rawValue,
                "onboarding_completed": true,
            ]
            if let picture, let data = ImageTools.jpeg(picture, maxSide: 800) {
                fields["profile_picture"] = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
            let before = model.me
            if !follows.isEmpty { fields["following"] = Array(Set((before?.following ?? []) + follows)) }
            try await model.addToMe(["coins": 50, "xp": 10], set: fields)
            UserDefaults.standard.set(trimmed, forKey: "sugerly.name")
            if let me = model.me {
                for email in follows {
                    Notify.send(to: email, from: me, type: "follow", message: "\(me.displayName) started following you", link: "/Profile?email=\(me.email)")
                }
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { done = true }
        } catch {
            withMotion { self.error = "Couldn't save that. Check your connection and try again." }
        }
    }

    // Straight into the app with the name you signed up with.
    private func skip() async {
        saving = true
        try? await model.updateMe(["onboarding_completed": true])
        saving = false
        Theme.accent = model.accent
        await model.finishSetup()
    }
}
