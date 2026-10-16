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

    // "1-day", "4-day" (the old text said "1 days").
    static func days(_ n: Int) -> String { "\(n)-day" }
}

// The daily reward row inside the Home card. Before you collect it, it's a
// solid row in your colour that says how many coins you'll get; afterwards
// it turns into a quiet grey line until tomorrow.
struct DailyRewardButton: View {
    @Environment(AppModel.self) private var model
    @State private var claiming = false

    var body: some View {
        let status = DailyReward.status(model.me)
        let next = DailyReward.amount(status.streak + 1)
        Button {
            guard !status.claimed, !claiming else { return }
            claiming = true
            Task {
                defer { claiming = false }
                do {
                    if let got = try await DailyReward.claim(model) {
                        RewardSound.play()
                        model.showToast("+\(got) coins collected", icon: "checkmark.circle")
                    }
                } catch {
                    model.showToast(DailyReward.failed, error: true)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: status.claimed ? "checkmark" : "gift")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(status.claimed ? Palette.text2 : Color.white)
                    .frame(width: 38, height: 38)
                    .background(status.claimed ? Palette.surface : Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.claimed ? "Today's coins collected" : "Collect today's coins").font(.jakarta(15, .semibold))
                    Text(status.claimed
                         ? (status.streak > 0 ? "\(DailyReward.days(status.streak)) streak · back tomorrow" : "Come back tomorrow")
                         : "+\(next) coins and 10 XP" + (status.streak > 0 ? " · \(DailyReward.days(status.streak)) streak" : ""))
                        .font(.jakarta(13))
                        .opacity(status.claimed ? 1 : 0.85)
                }
                .foregroundStyle(status.claimed ? Palette.text2 : .white)
                Spacer(minLength: 0)
                if claiming {
                    ProgressView().tint(status.claimed ? Palette.text2 : .white)
                } else if !status.claimed {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(status.claimed ? Palette.surface2 : Theme.main, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(Motion.fade, value: status.claimed)
        }
        .buttonStyle(SoftPressStyle())
        .disabled(status.claimed)
        .sensoryFeedback(.success, trigger: status.claimed)
        .accessibilityHint(status.claimed ? "" : "Adds \(next) coins to your balance")
    }
}

// Pops up once a day when you open the app.
struct DailyRewardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reward: Int?
    @State private var claiming = false
    @State private var failed = false

    var body: some View {
        let status = DailyReward.status(model.me)
        let done = reward != nil || status.claimed
        VStack(spacing: 16) {
            Image(systemName: done ? "checkmark" : "gift")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.main)
                .frame(width: 72, height: 72)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentTransition(.symbolEffect(.replace))
                .padding(.top, 36)

            Text(reward.map { "+\($0) coins" } ?? (status.claimed ? "Already collected" : "Daily reward"))
                .font(.display(30)).foregroundStyle(Palette.text)
                .contentTransition(.numericText())
            Text(done
                 ? "Come back tomorrow to keep your \(DailyReward.days(max(1, status.streak))) streak going."
                 : "Open Sugerly every day to collect coins. The longer your streak, the more you get.")
                .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).padding(.horizontal, 30)

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let got = day <= status.streak
                    VStack(spacing: 4) {
                        Text("Day \(day)").font(.jakarta(10, .medium)).foregroundStyle(Palette.muted)
                        Image(systemName: got ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(got ? Theme.main : Palette.borderStrong)
                        Text("\(DailyReward.amount(day))").font(.jakarta(12, .semibold))
                            .foregroundStyle(got ? Palette.text : Palette.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(got ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(got ? Color.clear : Palette.border, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Day \(day), \(DailyReward.amount(day)) coins\(got ? ", collected" : "")")
                }
            }
            .padding(.horizontal, 20)

            Text("Coins can't be bought. Spend them on MimiPlus and boosts in the menu.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).padding(.horizontal, 30)

            if failed {
                Label(DailyReward.failed, systemImage: "wifi.exclamationmark")
                    .font(.jakarta(13, .medium)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
                    .transition(.opacity)
            }

            Button {
                if done { dismiss(); return }
                guard !claiming else { return }
                claiming = true
                Task {
                    defer { claiming = false }
                    do {
                        let got = try await DailyReward.claim(model)
                        withMotion(Motion.standard) {
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
                    Text(done ? "Done" : failed ? "Try again" : "Collect \(DailyReward.amount(status.streak + 1)) coins")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 52))
            .padding(.horizontal, 24)
            .sensoryFeedback(.success, trigger: reward)
            Spacer(minLength: 0)
        }
        .sugarBackground()
    }
}

// MARK: - Home

// Home: a plain hello card (your level, coins, friends and today's reward),
// then what's new around Sugerly, one tidy section after another. The top bar is iPhone's own:
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
    @State private var tagSearch: String?
    @State private var shop = false
    @AppStorage("sugerly.dismissedAnnouncement") private var dismissedAnnouncement = ""

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                announcementBanner
                hero.scrollFade().homeSection(appeared, 0)
                HomeComposerBar(compose: compose).scrollFade().homeSection(appeared, 1)
                StoriesRow(reels: reels, path: $path, compose: compose).homeSection(appeared, 2)
                shortcuts.scrollFade().homeSection(appeared, 3)
                community.homeSection(appeared, 4)
                if !reels.isEmpty { reelStrip.homeSection(appeared, 5) }
                featured.homeSection(appeared, 6)
                ArtPromptCard(compose: compose).scrollFade().homeSection(appeared, 7)
                SuggestedPeople(path: $path)
                TrendingTags(posts: posts.posts, reels: reels) { tagSearch = $0 }
                freshTracks
                friendsRow
                yourServers
            }
            .padding(.horizontal, sizeClass == .regular ? 24 : 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .sideRails(760)
        }
        .scrollIndicators(.hidden)
        .appearFade()
        .sugarBackground()
        .accessibilityIdentifier("home-feed")
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
        .sheet(isPresented: $searching) {
            SearchView { route in path.append(route) }
                .presentationCornerRadius(24)
        }
        .sheet(item: Binding(get: { tagSearch.map { TagQuery(id: $0) } }, set: { tagSearch = $0?.id })) { tag in
            SearchView(go: { route in
                tagSearch = nil
                path.append(route)
            }, initial: tag.id)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $shop) { NitroShopView() }
    }

    struct TagQuery: Identifiable { var id: String }

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
        // Keep what's showing if a refresh fails.
        if let nextArt { artworks = nextArt.map(Artwork.init) }
        if let nextTracks { tracks = nextTracks.map(Track.init) }
        if let nextServers { servers = nextServers.map(Server.init) }
        if let nextReels { reels = nextReels.map(Reel.init) }
        lastLoad = Date()
        loaded = true
        if model.people.isEmpty { await model.loadPeople() }
    }

    // The admin's announcement (Admin → Site), until you close it.
    @ViewBuilder
    private var announcementBanner: some View {
        let site = SiteTheme.shared
        if site.announcementActive && !site.announcement.isEmpty && dismissedAnnouncement != site.announcement {
            HStack(spacing: 10) {
                Image(systemName: "megaphone").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(site.announcement).font(.jakarta(14, .medium)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                Button { withMotion(Motion.standard) { dismissedAnnouncement = site.announcement } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).frame(width: 30, height: 30)
                }
                .accessibilityLabel("Close announcement")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(hex: site.announcementColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity)
        }
    }

    // MARK: hello

    private var hero: some View {
        let me = model.me
        let name = me?.displayName ?? ""
        let info = LevelInfo(xp: me?.xp ?? 0)
        let friends = mutualFriends
        let online = friends.filter { model.person($0)?.isOnline == true }.count
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.jakarta(13, .medium))
                    .foregroundStyle(Palette.muted)
                Text(name.isEmpty ? greeting : "\(greeting), \(name)")
                    .font(.display(26)).foregroundStyle(Palette.text)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                stat("\(info.level)", "Level", info.title)
                Divider().frame(height: 34)
                Button { shop = true } label: {
                    stat(Self.compact(me?.coins ?? 0), "Coins", "Earn & spend", chevron: true)
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityHint("Shows how coins work and what you can get with them")
                Divider().frame(height: 34)
                stat("\(friends.count)", "Friends", "\(online) online")
            }
            .padding(.vertical, 10)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            XPBar(info: info)
            DailyRewardButton()
        }
        .padding(16)
        .sugarCard(radius: 16)
    }

    private func stat(_ value: String, _ label: String, _ sub: String, chevron: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.jakarta(20, .semibold)).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            HStack(spacing: 2) {
                Text(label).font(.jakarta(12, .medium)).foregroundStyle(Palette.text2)
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted)
                }
            }
            Text(sub).font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-\(label.lowercased())")
    }

    // MARK: shortcuts to the places that aren't tabs

    private var shortcuts: some View {
        let items: [(String, String, Route)] = [
            ("Music", "music.note", .music),
            ("Servers", "person.3", .servers),
            ("People", "person.crop.circle.badge.plus", .people),
            ("Top artists", "crown", .topArtists),
        ]
        return HStack(spacing: 6) {
            ForEach(items, id: \.0) { item in
                Button { path.append(item.2) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.1)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Palette.text)
                            .frame(width: 46, height: 46)
                            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(item.0).font(.jakarta(12, .medium)).foregroundStyle(Palette.text2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .sugarCard(radius: 16)
    }

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
            SectionHeader(icon: "flame.fill", title: "For you in the community") { model.tabRequest = .community }
            if communityPicks.isEmpty {
                if loaded {
                    EmptyCard(icon: "photo.on.rectangle.angled", title: "Nothing new yet", text: "Be the first to share something today.", actionTitle: "Share a post", action: { compose(.post) }, compact: true)
                } else {
                    SkeletonBlock(height: 160, radius: 14)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: sizeClass == .regular ? 3 : 2), spacing: 12) {
                ForEach(communityPicks) { post in
                    Button { path.append(.post(post)) } label: { pickCard(post) }
                        .buttonStyle(SoftPressStyle())
                        .scrollFade()
                }
            }
        }
    }

    private func pickCard(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.surface2)
                .aspectRatio(0.85, contentMode: .fit)
                .overlay {
                    if post.imageURL.isEmpty {
                        Text("“\(String(post.text.prefix(90)))”")
                            .font(.jakarta(15, .medium)).foregroundStyle(Palette.text)
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
                Image(systemName: "heart").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text("\(post.likeTotal)").font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
            }
            .padding(10)
        }
        .sugarCard(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                .padding(10)
                            }
                            .frame(width: 120, height: 200)
                            .background(Palette.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(SoftPressStyle())
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
                            SkeletonBlock(height: 260, radius: 14).frame(width: 200)
                        }
                    }
                    ForEach(Array(list)) { art in
                        Button { path.append(.artwork(art)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: art.imageURL).frame(width: 200, height: 260)
                                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(art.title).font(.jakarta(16, .semibold)).foregroundStyle(.white).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                        Text("\(art.likeTotal)")
                                        if !art.medium.isEmpty { Text("· \(art.medium.capitalized)").lineLimit(1) }
                                    }
                                    .font(.jakarta(12, .medium)).foregroundStyle(.white.opacity(0.85))
                                }
                                .padding(14)
                            }
                            .frame(width: 200, height: 260)
                            .background(Palette.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(SoftPressStyle())
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
            .sugarCard(radius: 16, padding: 8)
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
                            .buttonStyle(SoftPressStyle())
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
                                    Text(server.name).font(.jakarta(14, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                    Text("\(server.members.count) members").font(.jakarta(11)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .sugarCard(radius: 14, padding: 10)
                        }
                        .buttonStyle(SoftPressStyle())
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
                Text("\(rank)").font(.jakarta(13, rank <= 3 ? .semibold : .regular)).foregroundStyle(rank <= 3 ? Palette.text : Palette.muted).frame(width: 22)
            }
            Button { player.play(track, in: list) } label: {
                ZStack {
                    RemoteImage(url: track.coverURL)
                    if track.coverURL.isEmpty { Palette.borderStrong }
                    Color.black.opacity(0.25)
                    Image(systemName: player.isPlaying(track) ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(SoftPressStyle())
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.jakarta(15, .semibold)).foregroundStyle(current ? Theme.main : Palette.text).lineLimit(1)
                Text([track.artist, track.genre].filter { !$0.isEmpty }.joined(separator: " · ")).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.isPlaying(track) {
                Image(systemName: "waveform").foregroundStyle(Theme.main).symbolEffect(.variableColor.iterative, isActive: true)
            }
            if let onFull {
                Button(action: onFull) {
                    Text("Full").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Palette.surface2, in: Capsule())
                }
                .buttonStyle(SoftPressStyle())
            }
            if reportable {
                Menu {
                    Button {
                        reporting = ReportSheet.Target(id: track.id, type: "music", ownerEmail: track.authorEmail, preview: track.title, link: "/Music", collection: "MusicReview")
                    } label: { Label("Report", systemImage: "flag") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.muted)
                        .frame(width: 32, height: 40).contentShape(Rectangle())
                }
                .accessibilityLabel("More: report")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(current ? Palette.surface2 : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .offset(y: visible ? 0 : 6)
            .animation(reduceMotion ? nil : Motion.enter.delay(Double(min(index, 7)) * Motion.staggerStep), value: shown)
    }
}
