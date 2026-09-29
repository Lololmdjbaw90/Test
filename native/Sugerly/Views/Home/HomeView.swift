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
    @State private var confetti = false
    @State private var wiggle = false
    @State private var claiming = false

    var body: some View {
        let status = DailyReward.status(model.me)
        Button {
            guard !status.claimed, !claiming else { return }
            claiming = true
            Task {
                defer { claiming = false }
                do {
                    if try await DailyReward.claim(model) != nil {
                        confetti = true
                        try? await Task.sleep(for: .seconds(2))
                        confetti = false
                    }
                } catch {
                    model.showToast(DailyReward.failed, error: true)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(status.claimed ? AnyShapeStyle(Theme.pink) : AnyShapeStyle(Color.white))
                    .frame(width: 42, height: 42)
                    .background(status.claimed ? Theme.pink.opacity(0.12) : Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .rotationEffect(.degrees(wiggle && !status.claimed ? 8 : -8))
                    .animation(status.claimed ? .default : .easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: wiggle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.claimed ? "Daily reward claimed" : "Claim daily reward").font(.jakarta(15, .bold))
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 11))
                        Text(status.streak > 0 ? "\(status.streak)-day streak" : "Start a streak today").font(.jakarta(12, .medium))
                    }
                    .opacity(0.85)
                }
                .foregroundStyle(status.claimed ? Palette.text : .white)
                Spacer(minLength: 0)
                if claiming { ProgressView().tint(.white) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                if status.claimed {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.gradient)
                        .shadow(color: Theme.pink.opacity(0.45), radius: 16, y: 8)
                }
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
        .overlay { if confetti { ConfettiView() } }
        .sensoryFeedback(.success, trigger: status.claimed)
        .onAppear { wiggle = true }
    }
}

// Pops up once a day when you open the app.
struct DailyRewardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reward: Int?
    @State private var bounce = false
    @State private var claiming = false
    @State private var failed = false

    var body: some View {
        let status = DailyReward.status(model.me)
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 130, height: 130).blur(radius: 30).opacity(0.6)
                Image(systemName: reward == nil ? "gift.fill" : "sparkles")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 118, height: 118)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .shadow(color: Theme.pink.opacity(0.5), radius: 20, y: 10)
                    .scaleEffect(bounce ? 1.06 : 0.96)
                    .rotationEffect(.degrees(bounce ? 4 : -4))
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bounce)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.top, 34)
            .overlay { if reward != nil { ConfettiView() } }

            Text(reward == nil ? "Daily reward!" : "+\(reward ?? 0) coins").font(.display(38)).foregroundStyle(Theme.gradient)
            Text(reward == nil ? "Log in every day to grow your streak and earn more coins." : "See you tomorrow — your streak is \(max(1, DailyReward.status(model.me).streak)) days!")
                .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).padding(.horizontal, 30)

            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    let done = day <= status.streak
                    VStack(spacing: 4) {
                        Text("\(20 + day * 5)").font(.jakarta(11, .bold))
                        Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted").font(.system(size: 18))
                        Text("D\(day)").font(.jakarta(10, .semibold))
                    }
                    .foregroundStyle(done ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(done ? Theme.pink.opacity(0.1) : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    } catch {
                        withAnimation(.snappy) { failed = true }
                    }
                }
            } label: {
                if claiming {
                    ProgressView().tint(.white)
                } else {
                    Text(reward != nil || status.claimed ? "Yay!" : failed ? "Try again" : "Claim reward")
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

struct HomeView: View {
    @Binding var path: [Route]
    var compose: (Composer) -> Void
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var posts
    @Environment(Player.self) private var player
    @State private var artworks: [Artwork] = []
    @State private var tracks: [Track] = []
    @State private var servers: [Server] = []
    @State private var reels: [Reel] = []
    @State private var loaded = false
    @State private var appeared = false
    @State private var lastLoad = Date.distantPast
    @State private var tagSearch: String?
    @AppStorage("sugerly.dismissedAnnouncement") private var dismissedAnnouncement = ""

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                announcementBanner
                StoriesRow(reels: reels, path: $path, compose: compose).homeSection(appeared, 0)
                hero.homeSection(appeared, 1)
                HomeComposerBar(compose: compose).homeSection(appeared, 2)
                quickLinks.homeSection(appeared, 3)
                ArtPromptCard(compose: compose).homeSection(appeared, 4)
                InlineExtras(part: .top).homeSection(appeared, 5)
                HappeningNow(posts: posts.posts, artworks: artworks, reels: reels, tracks: tracks, path: $path).homeSection(appeared, 6)
                featured.homeSection(appeared, 7)
                if !reels.isEmpty { reelStrip.homeSection(appeared, 8).transition(.opacity) }
                SuggestedPeople(path: $path).homeSection(appeared, 9)
                community.homeSection(appeared, 10)
                TrendingTags(posts: posts.posts, reels: reels) { tagSearch = $0 }.homeSection(appeared, 11)
                freshTracks.homeSection(appeared, 12)
                artists.homeSection(appeared, 13)
                friendsRow.homeSection(appeared, 14)
                yourServers.homeSection(appeared, 15)
                InlineExtras(part: .bottom).homeSection(appeared, 16)
                Label("Last activity \(Dates.ago(posts.posts.first?.created ?? ""))", systemImage: "sparkles")
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .sideRails(760)
        }
        .patternBackground()
        .sugarTopBar($path)
        .refreshable { await load() }
        .task {
            if !appeared {
                // The first time: wait a moment for the first things to load,
                // then let the sections float in (so nothing jumps in later).
                let first = Task { await load() }
                let started = Date()
                while !loaded && Date().timeIntervalSince(started) < 0.7 { try? await Task.sleep(for: .milliseconds(40)) }
                appeared = true
                await first.value
            } else if Date().timeIntervalSince(lastLoad) > 60 {
                // Coming back later: freshen up quietly, no replay.
                await load()
            }
        }
        .dropRemoved($artworks)
        .dropRemoved($reels)
        .sheet(item: Binding(get: { tagSearch.map { TagQuery(id: $0) } }, set: { tagSearch = $0?.id })) { tag in
            SearchView(go: { route in
                tagSearch = nil
                path.append(route)
            }, initial: tag.id)
            .presentationCornerRadius(34)
        }
    }

    struct TagQuery: Identifiable { var id: String }

    private func load() async {
        async let art = try? FS.query("Artwork", orderBy: "created_date", limit: 40)
        async let music = try? FS.query("MusicReview", orderBy: "created_date", limit: 8)
        async let serverDocs = try? FS.query("Community", [.contains("member_emails", model.me?.email ?? "")], limit: 12)
        async let reelDocs = try? FS.query("Reel", orderBy: "created_date", limit: 30)
        if posts.posts.isEmpty { await posts.load() }
        let nextArt = (await art ?? []).map(Artwork.init)
        let nextTracks = (await music ?? []).map(Track.init)
        let nextServers = (await serverDocs ?? []).map(Server.init)
        let nextReels = (await reelDocs ?? []).map(Reel.init)
        // New things fade in place instead of making the page jump.
        withAnimation(.smooth(duration: 0.4)) {
            if nextArt != artworks { artworks = nextArt }
            if nextTracks != tracks { tracks = nextTracks }
            if nextServers != servers { servers = nextServers }
            if nextReels != reels { reels = nextReels }
        }
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
                Image(systemName: "megaphone.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .repeat(2), value: appeared)
                Text(site.announcement).font(.jakarta(14, .bold)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation(.snappy) { dismissedAnnouncement = site.announcement } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white.opacity(0.85)).frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(hex: site.announcementColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: site.announcementColor).opacity(0.4), radius: 12, y: 5)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: quick links (like the website's sidebar)

    private var quickLinks: some View {
        let items: [(String, String, [UInt32])] = [
            ("Music", "music.note", [0xFF7AA2, 0xD9577F]),
            ("Servers", "person.3.fill", [0xB19CFF, 0x7C5CF0]),
            ("People", "person.crop.circle.badge.plus", [0xFFAA80, 0xEE6E40]),
            ("Alerts", "bell.fill", [0x7CBEFF, 0x2F80E0]),
        ]
        return HStack(spacing: 10) {
            ForEach(items, id: \.0) { item in
                Button {
                    switch item.0 {
                    case "Music": path.append(.music)
                    case "Servers": path.append(.servers)
                    case "People": path.append(.people)
                    default: withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.showNotifications = true }
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.1)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(LinearGradient(colors: item.2.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .shadow(color: Color(hex: item.2[1]).opacity(0.35), radius: 10, y: 5)
                        Text(item.0).font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BouncyStyle(scale: 0.9))
            }
        }
        .padding(.vertical, 14)
        .sugarCard(radius: 26)
    }

    // MARK: reels strip

    private var reelStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "play.rectangle.fill", title: "Fresh reels")
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
                                .font(.jakarta(12, .heavy)).foregroundStyle(.white)
                                .padding(10)
                            }
                            .frame(width: 124, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            .shadow(color: Palette.shadow, radius: 10, y: 5)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.95))
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
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
                    HStack(spacing: 16) {
                        ForEach(friends, id: \.self) { email in
                            let person = model.person(email)
                            Button { path.append(.person(email)) } label: {
                                VStack(spacing: 6) {
                                    Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 62, online: person?.isOnline ?? false)
                                    Text(person?.displayName ?? "").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                                }
                                .frame(width: 74)
                            }
                            .buttonStyle(BouncyStyle())
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(mine)) { server in
                        Button { path.append(.server(server)) } label: {
                            HStack(spacing: 10) {
                                ServerIcon(server: server, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                    Text("\(server.members.count) members").font(.jakarta(11)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .sugarCard(radius: 20, padding: 10)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                    }
                }
            }
        }
    }

    // MARK: sections

    private var hero: some View {
        let me = model.me
        let info = LevelInfo(xp: me?.xp ?? 0)
        let friends = mutualFriends
        return VStack(alignment: .leading, spacing: 16) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.jakarta(12, .bold))
                .tracking(1.4)
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting),").font(.display(40)).foregroundStyle(Palette.text)
                Text(me?.displayName ?? "").font(.display(40)).foregroundStyle(Theme.gradient)
                    .shadow(color: Theme.pink.opacity(0.25), radius: 10, y: 4)
                    .overlay(alignment: .topTrailing) { Twinkle(size: 14).offset(x: 22, y: -2) }
            }
            Text("Here's what's happening across Sugerly today — fresh art, new tracks and friends online.")
                .font(.jakarta(15)).foregroundStyle(Palette.text2)
            DailyRewardButton()
            HStack(spacing: 10) {
                stat("\(info.level)", "LEVEL", info.title, info.color)
                stat(Self.compact(me?.coins ?? 0), "COINS", "MimiCoins", Palette.text)
                stat("\(friends.count)", "FRIENDS", "\(friends.filter { model.person($0)?.isOnline == true }.count) online", Palette.text)
            }
            XPBar(info: info)
        }
        .padding(22)
        .sugarCard(radius: 32)
    }

    private func stat(_ value: String, _ label: String, _ sub: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.display(28)).foregroundStyle(color)
            Text(label).font(.jakarta(10, .bold)).tracking(0.8).foregroundStyle(Palette.muted)
            Text(sub).font(.jakarta(11)).foregroundStyle(Palette.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private var featured: some View {
        let list = artworks.sorted { a, b in
            if a.featured != b.featured { return a.featured }
            return a.likeTotal > b.likeTotal
        }.prefix(10)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "star.fill", title: "Featured art") { model.tabRequest = .gallery }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if !loaded {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.surface2).frame(width: 220, height: 280)
                        }
                    }
                    ForEach(Array(list)) { art in
                        Button { path.append(.artwork(art)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: art.imageURL).frame(width: 220, height: 280)
                                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(art.title).font(.display(20)).foregroundStyle(.white).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                        Text("\(art.likeTotal)")
                                        if !art.medium.isEmpty { Text("· \(art.medium.capitalized)") }
                                    }
                                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.9))
                                }
                                .padding(14)
                            }
                            .frame(width: 220, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: Palette.shadow, radius: 12, y: 6)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    private var communityPicks: [Post] {
        let blocked = Set(model.me?.blocked ?? [])
        let me = model.me?.email ?? ""
        return posts.posts.filter { !blocked.contains($0.authorEmail) && $0.authorEmail != me && (!$0.imageURL.isEmpty || !$0.text.isEmpty) }
            .sorted { Self.pickScore($0) > Self.pickScore($1) }
            .prefix(6).map { $0 }
    }

    private var community: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "flame.fill", title: "For you in the community")
            if communityPicks.isEmpty {
                if loaded {
                    EmptyCard(icon: "photo.on.rectangle.angled", title: "Nothing new yet", text: "Be the first to share something today.", actionTitle: "Share a post", action: { compose(.post) }, compact: true)
                } else {
                    SkeletonBlock(height: 160, radius: 24)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(communityPicks) { post in
                    Button { path.append(.post(post)) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle().fill(post.imageURL.isEmpty ? AnyShapeStyle(LinearGradient(colors: [Theme.light.opacity(0.35), Palette.surface2], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Palette.surface2))
                                .aspectRatio(0.8, contentMode: .fit)
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
                                Avatar(url: model.person(post.authorEmail)?.picture ?? post.authorPicture, name: model.name(post.authorEmail, post.authorName), size: 26)
                                Text(model.name(post.authorEmail, post.authorName)).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Theme.pink)
                                Text("\(post.likeTotal)").font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                            }
                            .padding(10)
                        }
                        .sugarCard(radius: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.96))
                }
            }
        }
    }

    private var freshTracks: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "music.note", title: "Fresh tracks") { path.append(.music) }
            VStack(spacing: 4) {
                ForEach(tracks.prefix(5)) { track in
                    TrackRow(track: track, list: tracks)
                }
                if tracks.isEmpty {
                    Text(loaded ? "No tracks yet." : "Loading…").font(.jakarta(14)).foregroundStyle(Palette.muted).padding(20)
                }
            }
            .sugarCard(radius: 26, padding: 8)
        }
    }

    private var topArtists: [(String, Int)] {
        var score: [String: Int] = [:]
        for a in artworks { score[a.authorEmail, default: 0] += a.likeTotal }
        for p in posts.posts { score[p.authorEmail, default: 0] += p.likeTotal }
        return score.filter { $0.value > 0 && model.person($0.key) != nil }.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var artists: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "crown.fill", title: "Top artists") { path.append(.topArtists) }
            VStack(spacing: 2) {
                if topArtists.isEmpty {
                    Text("Post art to get on the board!").font(.jakarta(14)).foregroundStyle(Palette.muted).padding(20)
                }
                ForEach(Array(topArtists.enumerated()), id: \.offset) { index, entry in
                    let person = model.person(entry.0)
                    Button { path.append(.person(entry.0)) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.display(20)).foregroundStyle(index == 0 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted)).frame(width: 24)
                            Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 46)
                                .overlay(alignment: .top) {
                                    if index == 0 {
                                        Image(systemName: "crown.fill").font(.system(size: 14)).foregroundStyle(Color(hex: 0xF0A020)).offset(y: -12)
                                    }
                                }
                            Text(person?.displayName ?? "").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                            Spacer()
                            Label("\(entry.1)", systemImage: "heart.fill").font(.jakarta(13, .bold)).foregroundStyle(Theme.pink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.97))
                }
            }
            .sugarCard(radius: 26, padding: 6)
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
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Theme.pink.opacity(0.12), in: Capsule())
                }
                .buttonStyle(BouncyStyle())
            }
            if reportable {
                Menu {
                    Button {
                        reporting = ReportSheet.Target(id: track.id, type: "music", ownerEmail: track.authorEmail, preview: track.title, link: "/Music")
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
    // Home sections rise and fade in one after another the first time Home
    // opens, then glide softly as they scroll into and out of view.
    func homeSection(_ shown: Bool, _ index: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 28)
            .scaleEffect(shown ? 1 : 0.96, anchor: .top)
            .animation(.spring(response: 0.62, dampingFraction: 0.86).delay(0.04 + Double(min(index, 8)) * 0.06), value: shown)
            .scrollTransition(.interactive(timingCurve: .easeOut), axis: .vertical) { content, phase in
                content
                    .opacity(1 - abs(phase.value) * 0.3)
                    .scaleEffect(1 - abs(phase.value) * 0.025)
                    .offset(y: phase.value * 8)
            }
    }
}
