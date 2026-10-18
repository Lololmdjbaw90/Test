import SwiftUI

// Daily login reward (same rules as the website): 20 coins + 5 per streak day
// (up to 7), +10 XP, once a day.
enum DailyReward {
    static func todayKey() -> String { String(Dates.iso(Date()).prefix(10)) }
    static func yesterdayKey() -> String { String(Dates.iso(Date().addingTimeInterval(-86400)).prefix(10)) }

    @MainActor
    static func status(_ me: UserProfile?) -> (claimed: Bool, streak: Int) {
        guard let me else { return (false, 0) }
        let claimed = me.lastDailyClaim == todayKey()
        let alive = claimed || me.lastDailyClaim == yesterdayKey()
        return (claimed, alive ? max(1, me.dailyStreak) : 0)
    }

    static func amount(_ day: Int) -> Int { 20 + min(day, 7) * 5 }

    // nil = it was already collected today.
    @MainActor
    static func claim(_ model: AppModel) async throws -> Int? {
        try await model.claimDaily()
    }

    static let failed = "Couldn't collect it right now. Check your connection and try again."
}

struct DailyRewardButton: View {
    @Environment(AppModel.self) private var model
    @State private var claiming = false
    @State private var ripple = 0
    @State private var got: Int?

    var body: some View {
        let status = DailyReward.status(model.me)
        let next = DailyReward.amount(min(7, status.streak + 1))
        HStack(spacing: 12) {
            Image(systemName: status.claimed ? "checkmark" : "gift.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(status.claimed ? Palette.success : .white)
                .frame(width: 42, height: 42)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
                    if status.claimed {
                        shape.fill(Palette.success.opacity(0.12))
                    } else {
                        shape.fill(Candy.lemon.gradient).shadow(color: Candy.lemon.color.softGlow(0.35), radius: 6, y: 3)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: ripple)
                .modifier(GiftWiggle(active: !status.claimed))
                .overlay { RewardBurst(trigger: ripple).frame(width: 150, height: 150) }
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText(status.claimed))
                    .font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Palette.warning)
                    Text(streakText(status))
                        .font(.jakarta(12)).foregroundStyle(Palette.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            if !status.claimed {
                Button { claim() } label: {
                    HStack(spacing: 5) {
                        if claiming { ProgressView().tint(.white).controlSize(.small) } else {
                            Text("+\(next)")
                            CoinIcon(size: 15)
                        }
                    }
                    .font(.jakarta(14, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background {
                        Capsule().fill(Theme.candy)
                            .shadow(color: Theme.glow(0.3), radius: 6, y: 3)
                    }
                }
                .buttonStyle(BouncyStyle(scale: 0.9))
                .disabled(claiming)
                .transition(.pop)
                .accessibilityLabel("Collect \(next) coins")
            }
        }
        .padding(12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            if status.claimed {
                shape.fill(Palette.surface).shadow(color: Palette.shadow, radius: 10, y: 4)
            } else {
                // A reward is waiting: warm cream, like a little present.
                shape.fill(LinearGradient(colors: [Palette.cream, Palette.ivory], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Palette.gold.opacity(0.18), radius: 10, y: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(status.claimed ? Palette.border : Palette.gold.opacity(0.25), lineWidth: 1))
        .motion(Motion.playful, value: status.claimed)
        .sensoryFeedback(.success, trigger: ripple)
    }

    private func titleText(_ claimed: Bool) -> String {
        guard claimed else { return "Daily reward" }
        if let got { return "+\(got) coins today" }
        return "Collected today"
    }

    private func streakText(_ status: (claimed: Bool, streak: Int)) -> String {
        guard status.streak > 0 else { return "Start a streak today" }
        let base = "\(status.streak)-day streak"
        return status.claimed ? base + " · back tomorrow" : base
    }

    private func claim() {
        guard !claiming else { return }
        claiming = true
        Task {
            defer { claiming = false }
            do {
                let amount = try await DailyReward.claim(model)
                if let amount {
                    RewardSound.play()
                    got = amount
                    ripple += 1
                }
            } catch {
                model.showToast(DailyReward.failed, error: true)
            }
        }
    }
}

// Pops up once a day when you open the app.
struct DailyRewardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reward: Int?
    @State private var bounce = false
    @State private var claiming = false
    @State private var failed = false

    var body: some View {
        let status = DailyReward.status(model.me)
        VStack(spacing: 18) {
            ZStack {
                Image(systemName: reward == nil ? "gift.fill" : "checkmark")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.main)
                    .frame(width: 104, height: 104)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .symbolEffect(.bounce, value: reward)
                    .scaleEffect(bounce || reduceMotion ? 1 : 0.86)
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), value: bounce)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.top, 34)
            .overlay { RewardBurst(trigger: reward == nil ? 0 : 1).frame(width: 280, height: 280) }

            Text(reward == nil ? "Daily reward" : "+\(reward ?? 0) coins").font(.display(34)).foregroundStyle(Palette.text)
                .contentTransition(.numericText())
            Text(reward == nil ? "Log in every day to grow your streak and earn more coins." : "See you tomorrow — your streak is \(max(1, DailyReward.status(model.me).streak)) days!")
                .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).padding(.horizontal, 30)

            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    let done = day <= status.streak
                    VStack(spacing: 4) {
                        Text("\(DailyReward.amount(day))").font(.jakarta(11, .bold))
                        Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted").font(.system(size: 18))
                        Text("D\(day)").font(.jakarta(10, .semibold))
                    }
                    .foregroundStyle(done ? Theme.main : Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(done ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(done ? Theme.main.opacity(0.4) : Palette.border, lineWidth: 1))
                    .scaleEffect(bounce || reduceMotion ? 1 : 0.8)
                    .opacity(bounce || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : Motion.playful.delay(0.15 + Double(day) * 0.04), value: bounce)
                }
            }
            .padding(.horizontal, 20)

            if failed {
                Label(DailyReward.failed, systemImage: "wifi.exclamationmark")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button {
                if reward != nil || status.claimed { dismiss(); return }
                guard !claiming else { return }
                claiming = true
                Task {
                    defer { claiming = false }
                    do {
                        let got = try await DailyReward.claim(model)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                            failed = false
                            if let got { reward = got }
                        }
                        if got != nil { RewardSound.play() }
                    } catch {
                        withMotion(Motion.standard) { failed = true }
                    }
                }
            } label: {
                if claiming {
                    ProgressView().tint(.white)
                } else {
                    Text(reward != nil || status.claimed ? "Done" : failed ? "Try again" : "Collect")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 54))
            .padding(.horizontal, 24)
            .sensoryFeedback(.success, trigger: reward)
            Spacer(minLength: 0)
        }
        .sugarBackground()
        .onAppear { bounce = true }
    }
}

// MARK: - Home

// Home: a hello with your level and daily reward, then what's new around
// Sugerly, one tidy section after another. The top bar is iPhone's own:
// your account on the left, the logo in the middle, search, the bell and
// the + on the right.
struct HomeView: View {
    @Binding var path: [Route]
    var compose: (Composer) -> Void
    var loadContent = true
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var posts
    @State private var artworks: [Artwork] = []
    @State private var tracks: [Track] = []
    @State private var servers: [Server] = []
    @State private var reels: [Reel] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var appeared = false
    @State private var searching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var lastLoad = Date.distantPast
    @State private var wallet = false
    @State private var bunny = BunnyStore.shared
    @AppStorage("sugerly.dismissedAnnouncement") private var dismissedAnnouncement = ""

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                announcementBanner
                hero.homeSection(appeared, 0)
                HomeComposerBar(compose: compose).homeSection(appeared, 1)
                shortcuts.homeSection(appeared, 2)
                if !bunny.made { bunnyInvite.homeSection(appeared, 3).transition(.pop) }
                StoriesRow(reels: reels, path: $path, compose: compose).homeSection(appeared, 3)
                community.homeSection(appeared, 4)
                if !reels.isEmpty { reelStrip.homeSection(appeared, 5).transition(.rise) }
                featured.homeSection(appeared, 6)
                ArtPromptCard(compose: compose).scrollFade()
                friendsRow.scrollFade()
                SuggestedPeople(path: $path)
                freshTracks.scrollFade()
                TrendingTags(posts: posts.posts, reels: reels) { tag in path.append(.hashtag(String(tag.drop { $0 == "#" }))) }
                yourServers.scrollFade()
            }
            .padding(.horizontal, sizeClass == .regular ? 24 : 16)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .sideRails(760)
        }
        .scrollIndicators(.hidden)
        .appearFade()
        // Your moving pattern (Settings → Background) at the top of Home,
        // fading into the page.
        .background(alignment: .top) {
            HeaderWallpaper().frame(height: 440).ignoresSafeArea(edges: .top)
        }
        .sugarBackground()
        .accessibilityIdentifier("home-feed")
        .onAppear { bunny.use(model.me?.email ?? "") }
        .onChange(of: model.me?.email) { _, email in bunny.use(email ?? "") }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BrandLogo(height: 30)
                    .accessibilityLabel("Sugerly")
            }
        }
        .rootBar(search: { searching = true })
        .refreshable { if loadContent { await load() } }
        .task {
            guard loadContent else { appeared = true; loaded = true; return }
            if !appeared {
                // Home is ready: the "Setting things up" screen can go. Once
                // it has faded, the first sections rise in one after another.
                model.shellReady = true
                async let first: Void = load()
                while model.settingUp && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(80)) }
                appeared = true
                await first
            } else if Date().timeIntervalSince(lastLoad) > 60 {
                // Coming back later: freshen up quietly, no replay.
                await load()
            }
        }
        .dropRemoved($artworks)
        .dropRemoved($reels)
        .sheet(isPresented: $wallet) { WalletView() }
        .sheet(isPresented: $searching) {
            SearchView { route in path.append(route) }
                .presentationCornerRadius(34)
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let art = try? FS.query("Artwork", orderBy: "created_date", limit: 40)
        async let music = try? FS.query("MusicReview", orderBy: "created_date", limit: 8)
        async let serverDocs = try? FS.query("Community", [.contains("member_emails", model.me?.email ?? "")], limit: 12)
        async let reelDocs = try? FS.query("Reel", orderBy: "created_date", limit: 30)
        if posts.posts.isEmpty { await posts.load() }
        let nextArt = await art
        let nextTracks = await music
        let nextServers = await serverDocs
        let nextReels = await reelDocs
        guard !Task.isCancelled else { return }
        // Keep what's showing if a refresh fails. New things fade in softly
        // instead of popping.
        withAnimation(Motion.pick(.smooth(duration: 0.4))) {
            if let nextArt { artworks = nextArt.map(Artwork.init) }
            if let nextTracks { tracks = nextTracks.map(Track.init) }
            if let nextServers { servers = nextServers.map(Server.init) }
            if let nextReels { reels = nextReels.map(Reel.init) }
            loaded = true
        }
        lastLoad = Date()
        if model.people.isEmpty { await model.loadPeople() }
    }

    // The admin's announcement (Admin → Site), until you close it.
    @ViewBuilder
    private var announcementBanner: some View {
        let site = SiteTheme.shared
        if site.announcementActive && !site.announcement.isEmpty && dismissedAnnouncement != site.announcement {
            HStack(spacing: 10) {
                Image(systemName: "megaphone.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .repeat(2), value: appeared)
                Text(site.announcement).font(.jakarta(14, .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                Button { withMotion(Motion.standard) { dismissedAnnouncement = site.announcement } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.85)).frame(width: 30, height: 30)
                }
                .accessibilityLabel("Close announcement")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(hex: site.announcementColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(hex: site.announcementColor).softGlow(0.25), radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: hello

    private var hero: some View {
        let me = model.me
        let name = me?.displayName ?? ""
        let info = LevelInfo(xp: me?.xp ?? 0)
        let friends = mutualFriends
        let online = friends.filter { model.person($0)?.isOnline == true }.count
        return VStack(alignment: .leading, spacing: 14) {
            // Hello, in the palette: cream into blush into rose, with Mimi.
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting).font(.jakarta(15, .medium)).foregroundStyle(Palette.text2)
                        Text(name.isEmpty ? "Hi there" : name)
                            .font(.display(32)).foregroundStyle(Palette.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    // Your bunny (tap her!). Long press to dress her up.
                    BunnyOnScene(look: bunny.look, height: 100)
                        .onLongPressGesture { path.append(.bunny) }
                }
                // Three even tiles (number on top, a short word under it), so
                // nothing gets cut off whatever the text size.
                HStack(spacing: 8) {
                    chip(value: Self.compact(me?.coins ?? 0), label: "Coins", coin: true) { wallet = true }
                        .heroPop(appeared, 0)
                    chip(value: "Lv \(info.level)", label: info.title, dot: info.color) {
                        if let email = me?.email { path.append(.person(email)) }
                    }
                    .heroPop(appeared, 1)
                    chip(value: "\(online)", label: "Online", dot: online > 0 ? Palette.success : Palette.muted.opacity(0.5)) {
                        path.append(.people)
                    }
                    .heroPop(appeared, 2)
                }
                XPBar(info: info)
            }
            .pastelCard(radius: 24, padding: 16)
            .overlay {
                // Sparkles rising through the hello, and a shine sweeping by.
                TwinkleField(colors: [UIColor(hex: 0xFFC53D), .white, UIColor(Theme.main)])
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .opacity(0.85)
                    .allowsHitTesting(false)
            }
            .overlay {
                ShineSweep(every: 5.5, strength: 0.32)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            DailyRewardButton()
        }
    }

    // A small tappable fact: coins, level, friends online. The number on
    // top, a short word under it, each tile the same width.
    private func chip(value: String, label: String, coin: Bool = false, dot: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if coin { CoinIcon(size: 15) }
                    if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                    Text(value).font(.jakarta(16, .bold)).foregroundStyle(Palette.text).monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(label).font(.jakarta(12, .medium)).foregroundStyle(Palette.text2)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Palette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rim(0.7), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.94))
    }

    // MARK: shortcuts to the places that aren't tabs

    // Six juicy candy tiles in two rows of three: each place in its own
    // colour, with room for its whole name. Now and then one of the icons
    // gives a little hop.
    private var shortcuts: some View {
        CandyShortcutGrid(items: [
            .init(title: "Music", icon: "music.note", candy: .sky, route: .music),
            .init(title: "Servers", icon: "bubble.left.and.bubble.right.fill", candy: .mint, route: .servers),
            .init(title: "People", icon: "person.2.fill", candy: .grape, route: .people),
            .init(title: "Top artists", icon: "crown.fill", candy: .lemon, route: .topArtists),
            .init(title: "Commissions", icon: "paintbrush.pointed.fill", candy: .peach, route: .commissions),
            .init(title: "Bunny", icon: "hare.fill", candy: .berry, route: .bunny),
        ], shown: appeared) { route in path.append(route) }
    }

    // Until you've made your own bunny: an invite to the bunny maker.
    private var bunnyInvite: some View {
        Button { path.append(.bunny) } label: {
            HStack(spacing: 12) {
                BunnyBuddy(look: Self.inviteLook, height: 104, tappable: false)
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEW").font(.jakarta(10, .heavy)).tracking(0.6).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.25), in: Capsule())
                    Text("Make your bunny").font(.display(23)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text("Pick her fur, bow, outfit and face.").font(.jakarta(13, .medium)).foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Text("Start")
                        Image(systemName: "arrow.right")
                    }
                    .font(.jakarta(14, .bold)).foregroundStyle(Theme.main)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(.white, in: Capsule())
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background {
                let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
                shape.fill(Theme.candy)
                    .overlay {
                        // Soft bubbles in the corner.
                        GeometryReader { geo in
                            Circle().fill(.white.opacity(0.14)).frame(width: geo.size.width * 0.5)
                                .offset(x: geo.size.width * 0.68, y: -geo.size.width * 0.18)
                            Circle().fill(.white.opacity(0.1)).frame(width: geo.size.width * 0.28)
                                .offset(x: geo.size.width * 0.55, y: geo.size.height * 0.6)
                        }
                        .clipShape(shape)
                    }
                    .overlay { TwinkleField(colors: [.white, UIColor(hex: 0xFFF1A8)]).clipShape(shape) }
                    .overlay { ShineSweep(every: 4.8, strength: 0.3).clipShape(shape) }
                    .shadow(color: Theme.glow(0.32), radius: 14, y: 6)
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
        .accessibilityLabel("Make your bunny")
    }

    private static let inviteLook = BunnyLook(bow: 4, face: .happy)

    // MARK: community

    private var communityPicks: [Post] {
        let blocked = Set(model.me?.blocked ?? [])
        let me = model.me?.email ?? ""
        return posts.posts.filter { !blocked.contains($0.authorEmail) && $0.authorEmail != me && (!$0.imageURL.isEmpty || !$0.text.isEmpty) }
            .sorted { Self.pickScore($0) > Self.pickScore($1) }
            .prefix(sizeClass == .regular ? 6 : 4).map { $0 }
    }

    private var community: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "flame.fill", title: "For you") { model.tabRequest = .community }
            if communityPicks.isEmpty {
                if loaded {
                    EmptyCard(icon: "photo.on.rectangle.angled", title: "Nothing new yet", text: "Be the first to share something today.", actionTitle: "Share a post", action: { compose(.post) }, compact: true)
                } else {
                    SkeletonBlock(height: 160, radius: 24)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: sizeClass == .regular ? 3 : 2), spacing: 12) {
                ForEach(communityPicks) { post in
                    Button { path.append(.post(post)) } label: { pickCard(post) }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                        .scrollFade()
                }
            }
        }
    }

    private func pickCard(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(post.imageURL.isEmpty ? AnyShapeStyle(LinearGradient(colors: [Theme.light.opacity(0.35), Palette.surface2], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Palette.surface2))
                .aspectRatio(0.85, contentMode: .fit)
                .overlay {
                    if post.imageURL.isEmpty {
                        Text("“\(String(post.text.prefix(90)))”")
                            .font(.display(18)).foregroundStyle(Palette.text2)
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    } else {
                        RemoteImage(url: post.imageURL)
                    }
                }
                .clipped()
            HStack(spacing: 8) {
                Avatar(url: model.person(post.authorEmail)?.picture ?? post.authorPicture, name: model.name(post.authorEmail, post.authorName), size: 24)
                Text(model.name(post.authorEmail, post.authorName)).font(.jakarta(12, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.main)
                Text("\(post.likeTotal)").font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
            }
            .padding(10)
        }
        .sugarCard(radius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .zoomSource("post-" + post.id)
    }

    // MARK: reels strip

    private var reelStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "play.rectangle.fill", title: "Fresh reels") { model.tabRequest = .reels }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(reels) { reel in
                        Button { path.append(.reel(reel)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: reel.coverURL.isEmpty ? (reel.pictures.first ?? "") : reel.coverURL)
                                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                    Text("\(reel.views)")
                                }
                                .font(.jakarta(12, .semibold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 8).frame(height: 24)
                                .background(.black.opacity(0.3), in: Capsule())
                                .padding(8)
                            }
                            .frame(width: 120, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .zoomSource("reel-" + reel.id)
                            .shadow(color: Palette.shadow, radius: 8, y: 4)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.95))
                        .swipeFade()
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: featured art

    private var featured: some View {
        let list = artworks.sorted { a, b in
            if a.featured != b.featured { return a.featured }
            return a.likeTotal > b.likeTotal
        }.prefix(10)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "star.fill", title: "Featured art") { model.tabRequest = .gallery }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if !loaded && list.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonBlock(height: 260, radius: 26).frame(width: 200)
                        }
                    }
                    ForEach(Array(list)) { art in
                        Button { path.append(.artwork(art)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: art.imageURL).frame(width: 200, height: 260)
                                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(art.title).font(.display(20)).foregroundStyle(.white).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                        Text("\(art.likeTotal)")
                                        if !art.medium.isEmpty { Text("· \(art.medium.capitalized)").lineLimit(1) }
                                    }
                                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.9))
                                }
                                .padding(14)
                            }
                            .frame(width: 200, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .zoomSource("art-" + art.id)
                            .shadow(color: Palette.shadow, radius: 10, y: 5)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                        .swipeFade()
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: music

    private var freshTracks: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "music.note", title: "Fresh tracks") { path.append(.music) }
            VStack(spacing: 4) {
                ForEach(tracks.prefix(5)) { track in
                    TrackRow(track: track, list: tracks)
                }
                if tracks.isEmpty {
                    Text(loaded ? "No tracks yet." : "Loading…").font(.jakarta(14)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity).padding(20)
                }
            }
            .sugarCard(radius: 26, padding: 8)
        }
    }

    // MARK: friends & servers

    private var friendsRow: some View {
        // Online first, then by name, so the row doesn't reshuffle on refresh.
        let friends = mutualFriends.sorted { a, b in
            let oa = model.person(a)?.isOnline == true, ob = model.person(b)?.isOnline == true
            return oa != ob ? oa : model.name(a, a).lowercased() < model.name(b, b).lowercased()
        }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "person.2.fill", title: "Friends") { path.append(.people) }
            if friends.isEmpty {
                EmptyCard(icon: "person.2.fill", title: "No friends yet", text: "When you and someone follow each other, you become friends and they show up here.", actionTitle: "Find people", action: { path.append(.people) }, compact: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(friends, id: \.self) { email in
                            let person = model.person(email)
                            Button { path.append(.person(email)) } label: {
                                VStack(spacing: 6) {
                                    Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 60, online: person?.isOnline ?? false)
                                    Text(person?.displayName ?? "").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(BouncyStyle())
                            .swipeFade()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var yourServers: some View {
        let me = model.me?.email ?? ""
        let mine = servers.filter { $0.members.contains(me) }.prefix(6)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "server.rack", title: "Your servers") { path.append(.servers) }
            if mine.isEmpty {
                EmptyCard(icon: "bubble.left.and.bubble.right.fill", title: "No servers yet", text: "Servers are group chats with channels and voice rooms. Join one to hang out.", actionTitle: "Explore servers", action: { path.append(.servers) }, compact: true)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: sizeClass == .regular ? 3 : 2), spacing: 12) {
                    ForEach(Array(mine)) { server in
                        Button { path.append(.server(server)) } label: {
                            HStack(spacing: 10) {
                                ServerIcon(server: server, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                    Text("\(server.members.count) members").font(.jakarta(11)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .sugarCard(radius: 20, padding: 10)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                        .scrollFade()
                    }
                }
            }
        }
    }

    private var mutualFriends: [String] {
        guard let me = model.me else { return [] }
        return me.following.filter { model.person($0)?.following.contains(me.email) == true }
    }

    static func pickScore(_ p: Post) -> Int {
        let bonus: Int = p.imageURL.isEmpty ? 0 : 3
        return bonus + p.likeTotal
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return "\(n / 1000)k" }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

// A song row (cover with play button, title, artist) used on Home and Music.
struct TrackRow: View {
    let track: Track
    let list: [Track]
    var rank: Int? = nil
    var onFull: (() -> Void)? = nil
    @Environment(Player.self) private var player
    @Environment(AppModel.self) private var model
    @State private var reporting: ReportSheet.Target?

    // Songs people uploaded (not chart previews) can be reported.
    private var reportable: Bool {
        !track.authorEmail.isEmpty && track.authorEmail != model.me?.email && !track.id.hasPrefix("deezer_")
    }

    var body: some View {
        let current = player.isCurrent(track)
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)").font(.jakarta(13, .bold)).foregroundStyle(rank <= 3 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted)).frame(width: 22)
            }
            Button { player.play(track, in: list) } label: {
                ZStack {
                    RemoteImage(url: track.coverURL)
                    if track.coverURL.isEmpty { Theme.gradient }
                    Color.black.opacity(0.25)
                    Image(systemName: player.isPlaying(track) ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: current ? Theme.pink.opacity(0.4) : .clear, radius: 8, y: 4)
            }
            .buttonStyle(BouncyStyle())
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.jakarta(15, .bold)).foregroundStyle(current ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text)).lineLimit(1)
                Text([track.artist, track.genre].filter { !$0.isEmpty }.joined(separator: " · ")).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.isPlaying(track) {
                Image(systemName: "waveform").foregroundStyle(Theme.pink).symbolEffect(.variableColor.iterative, isActive: true)
            }
            if let onFull {
                Button(action: onFull) {
                    Text("Full").font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 12).frame(height: 30)
                        .background(Theme.pink.opacity(0.12), in: Capsule())
                }
                .buttonStyle(BouncyStyle())
            }
            if reportable {
                Menu {
                    Button {
                        reporting = ReportSheet.Target(id: track.id, type: "music", ownerEmail: track.authorEmail, preview: track.title, link: "/Music", collection: "MusicReview")
                    } label: { Label("Report", systemImage: "flag") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.muted)
                        .frame(width: 32, height: 40).contentShape(Rectangle())
                }
                .accessibilityLabel("More: report")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(current ? Theme.pink.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
    }
}


private extension View {
    // The first time Home opens, its sections rise and fade in one after
    // another. Only once: sections rebuilt while you scroll simply show.
    func homeSection(_ shown: Bool, _ index: Int) -> some View {
        modifier(HomeSectionEntrance(shown: shown, index: index))
    }
}

private struct HomeSectionEntrance: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .scaleEffect(visible ? 1 : 0.97, anchor: .top)
            .animation(reduceMotion ? nil : Motion.settle.delay(Double(min(index, 7)) * 0.06), value: shown)
    }
}

private extension View {
    // Little things in the hello card pop in one by one after the card.
    func heroPop(_ shown: Bool, _ index: Int) -> some View {
        modifier(HeroPop(shown: shown, index: index))
    }
}

private struct HeroPop: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.7)
            .animation(reduceMotion ? nil : Motion.playful.delay(0.18 + Double(min(index, 8)) * 0.05), value: shown)
    }
}

// A present waiting to be opened gives a little wiggle every few seconds.
private struct GiftWiggle: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), active, Motion.ambient, !Motion.reduced {
            content.symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 2.5)), isActive: true)
        } else {
            content
        }
    }
}
