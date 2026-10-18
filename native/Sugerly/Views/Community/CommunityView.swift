import SwiftUI
import UIKit
import PhotosUI

// Posts shared by the whole app (feed, post page, profiles, Home) so a like
// or a save shows everywhere at once.
@MainActor
@Observable
final class PostsStore {
    var posts: [Post] = []
    var commentCounts: [String: Int] = [:]
    // The newest comment on each post, shown under it like the website.
    var latestComment: [String: CommentPreview] = [:]
    var loading = false
    var error: String?

    // Pages of posts (newest first); more load as you scroll, so the feed
    // costs the same however many posts exist.
    var hasMore = true
    private var loadingMore = false
    static let pageSize = 30

    func load() async {
        loading = true
        defer { loading = false }
        do {
            async let comments = try? FS.query("CommunityComment", orderBy: "created_date", limit: 300)
            let docs = try await FS.query("CommunityPost", orderBy: "created_date", limit: Self.pageSize)
            let page = docs.map(Post.init)
            // Refresh the newest page but keep older pages you've scrolled to.
            let cutoff = page.map(\.created).min() ?? ""
            let older = posts.filter { !cutoff.isEmpty && $0.created < cutoff }
            if posts.isEmpty { hasMore = docs.count >= Self.pageSize }
            posts = page + older
            var latest = latestComment
            for c in (await comments ?? []) {
                let post = c.str("post_id")
                if latest[post] == nil, c.str("parent_id").isEmpty, !c.str("content").isEmpty {
                    latest[post] = CommentPreview(id: c.str("id"), email: c.str("user_email").lowercased(), name: c.str("user_display_name"), text: c.str("content"))
                }
            }
            latestComment = latest
            error = nil
            await LikeBook.shared.prime(page)
            await countComments(page)
        } catch {
            if posts.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore, let oldest = posts.map(\.created).filter({ !$0.isEmpty }).min() else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let docs = try? await FS.query("CommunityPost", [.before("created_date", oldest)], orderBy: "created_date", limit: Self.pageSize) else { return }
        hasMore = docs.count >= Self.pageSize
        let known = Set(posts.map(\.id))
        let page = docs.map(Post.init).filter { !known.contains($0.id) }
        posts += page
        await LikeBook.shared.prime(page)
        await countComments(page)
    }

    // Comment counts are counted by the database, one per post on the page.
    private func countComments(_ page: [Post]) async {
        let ids = page.map(\.id)
        let results = await withTaskGroup(of: (String, Int)?.self) { group -> [(String, Int)] in
            for id in ids {
                group.addTask {
                    guard let n = try? await FS.count("CommunityComment", [.equals("post_id", id)]) else { return nil }
                    return (id, n)
                }
            }
            var out: [(String, Int)] = []
            for await item in group { if let item { out.append(item) } }
            return out
        }
        var counts = commentCounts
        for (id, n) in results { counts[id] = n }
        commentCounts = counts
    }

    func replace(_ post: Post) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = post }
    }

    func toggleLike(_ post: Post, me: UserProfile?) {
        guard let me else { return }
        var next = post
        let liking = !LikeBook.shared.isLiked(post, me: me.email)
        TapSound.play(liking ? .like : .tap)
        next.setLiked(liking, me: me.email)
        replace(next)
        Task {
            do {
                try await LikeBook.shared.write(post, liking: liking, me: me.email, owner: post.authorEmail)
                if liking { Notify.send(to: post.authorEmail, from: me, type: "like", message: "\(me.displayName) liked your post\(post.title.isEmpty ? "" : " \"\(post.title)\"")", link: "/Community?post=\(post.id)") }
            } catch {
                if let i = self.posts.firstIndex(where: { $0.id == post.id }) { self.posts[i].restoreLikes(from: post) }
            }
        }
    }

    func delete(_ post: Post) async throws {
        try await FS.delete("CommunityPost", post.id)
        posts.removeAll { $0.id == post.id }
        Removed.shared.add(post.id)
    }
}

struct CommentPreview {
    var id = ""
    var email: String
    var name: String
    var text: String
}

// Notifications for likes, follows and comments (like the website sends).
enum Notify {
    @MainActor
    static func send(to email: String, from me: UserProfile, type: String, message: String, link: String) {
        guard !email.isEmpty, email != me.email else { return }
        let now = FS.nowISO()
        let data: Doc = [
            "to_email": email, "from_email": me.email, "from_display_name": me.displayName,
            "from_profile_picture": me.picture, "type": type, "message": message, "link": link,
            "is_read": false, "created_by": me.email, "created_date": now, "updated_date": now,
        ]
        Task { try? await FS.create("Notification", data) }
    }
}

struct CommunityView: View {
    enum Feed: String, CaseIterable {
        case forYou = "For you", following = "Following", latest = "Latest", top = "Top", saved = "Saved"
        var icon: String {
            switch self {
            case .forYou: return "sparkles"
            case .following: return "person.2.fill"
            case .latest: return "clock.fill"
            case .top: return "flame.fill"
            case .saved: return "bookmark.fill"
            }
        }
        var candy: Candy {
            switch self {
            case .forYou: return .berry
            case .following: return .grape
            case .latest: return .sky
            case .top: return .peach
            case .saved: return .lemon
            }
        }
    }

    @Binding var path: [Route]
    var compose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var feed: Feed = .forYou
    @State private var tag: String?
    @State private var reporting: ReportSheet.Target?
    @State private var dismissed = Set<String>()
    @State private var searching = false
    @State private var appeared = false
    // How much you like each #tag (learned from reels, posts and drawings).
    @State private var taste: [String: Double] = [:]
    @State private var bunny = BunnyStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var feedPill

    private var visible: [Post] {
        guard let me = model.me else { return [] }
        let blocked = Set(me.blocked + me.ignored)
        var all = store.posts.filter { !blocked.contains($0.authorEmail) }
        if let tag { all = all.filter { $0.tags.contains(tag) } }
        let following = Set(me.following)
        switch feed {
        case .forYou:
            return all.sorted { score($0, following) > score($1, following) }
        case .following:
            return all.filter { following.contains($0.authorEmail) || $0.authorEmail == me.email }
        case .latest:
            return all
        case .top:
            let weekAgo = Dates.iso(Date().addingTimeInterval(-7 * 86400))
            let counts = store.commentCounts
            func points(_ p: Post) -> Int { p.likeTotal + (counts[p.id] ?? 0) * 2 }
            return all.filter { $0.created > weekAgo }.sorted { points($0) > points($1) }
        case .saved:
            let saved = Set(me.savedPosts)
            return all.filter { saved.contains($0.id) }
        }
    }

    // Recent, liked, from people you follow and about #tags you like
    // floats up.
    private func score(_ p: Post, _ following: Set<String>) -> Double {
        let hours = max(0, Date().timeIntervalSince(Dates.parse(p.created) ?? Date()) / 3600)
        let engagement = Double(p.likeTotal) + Double(store.commentCounts[p.id] ?? 0) * 2 + 1
        let boost = following.contains(p.authorEmail) ? 1.6 : 1
        // Your taste: up to about twice as likely for tags you love, and less
        // for ones you keep skipping.
        let interest = tanh(p.tags.reduce(0) { $0 + (taste[$1] ?? 0) } / 2)
        return engagement * boost * (1 + 0.8 * interest) / pow(hours + 2, 1.15)
    }

    // Trending across all of Sugerly (worked out on the server); just these
    // posts until that's loaded.
    private var trending: [String] {
        let everywhere = TagTrends.shared.items.map(\.tag)
        if !everywhere.isEmpty { return Array(everywhere.prefix(10)) }
        var counts: [String: Int] = [:]
        for p in store.posts { for t in Set(p.tags) { counts[t, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(8).map(\.key)
    }

    private var storyPeople: [String] {
        let threeDays = Dates.iso(Date().addingTimeInterval(-3 * 86400))
        var seen = Set<String>()
        var out: [String] = []
        for p in store.posts where p.created > threeDays && p.authorEmail != model.me?.email && !seen.contains(p.authorEmail) {
            seen.insert(p.authorEmail)
            out.append(p.authorEmail)
        }
        return Array(out.prefix(14))
    }

    // Most-liked people this week.
    private var topCreators: [(String, Int)] {
        let weekAgo = Dates.iso(Date().addingTimeInterval(-7 * 86400))
        var likes: [String: Int] = [:]
        for p in store.posts where p.created > weekAgo { likes[p.authorEmail, default: 0] += p.likeTotal }
        return likes.filter { $0.value > 0 && model.person($0.key) != nil }
            .sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    private var creatorsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "crown.fill", title: "Top creators") { path.append(.topArtists) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(topCreators.enumerated()), id: \.element.0) { i, entry in
                        let person = model.person(entry.0)
                        Button { path.append(.person(entry.0)) } label: {
                            VStack(spacing: 5) {
                                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 54)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(i == 0 ? Palette.gold : i == 1 ? Color(hex: 0x94A3B8) : i == 2 ? Color(hex: 0xC2773A) : Palette.border, lineWidth: i < 3 ? 2 : 1))
                                    .overlay(alignment: .bottomTrailing) {
                                        PresenceBadge(online: person?.isOnline ?? false, size: 54).padding(3)
                                    }
                                    .overlay(alignment: .top) {
                                        if i == 0 {
                                            Image(systemName: "crown.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.gold)
                                                .offset(y: -13)
                                        }
                                    }
                                Text(person?.displayName ?? "").font(.jakarta(12, .medium)).foregroundStyle(Palette.text).lineLimit(1)
                                Label("\(entry.1)", systemImage: "heart.fill").font(.jakarta(11)).foregroundStyle(Palette.muted)
                            }
                            .frame(width: 70)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.92))
                    }
                }
                .padding(.top, 12).padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
        .sugarCard(radius: 20, padding: 14)
    }

    private var suggestions: [UserProfile] {
        guard let me = model.me else { return [] }
        let following = Set(me.following)
        let blocked = Set(me.blocked)
        return model.people.values
            .filter { $0.email != me.email && !following.contains($0.email) && !blocked.contains($0.email) && !dismissed.contains($0.email) }
            .sorted { $0.isOnline && !$1.isOnline }
            .prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                hero.stagger(appeared, 0)
                if !storyPeople.isEmpty { stories.stagger(appeared, 1) }
                WeeklyChallengeCard(posts: store.posts, active: tag != nil && tag == DailyContent.challenge?.tag, compose: compose) { t in
                    withAnimation(Motion.pick(.snappy(duration: 0.3))) { tag = tag == t ? nil : t }
                }
                .stagger(appeared, 2)
                if !topCreators.isEmpty { creatorsRow.stagger(appeared, 3) }
                Section {
                    if !trending.isEmpty || tag != nil { trendingRow }

                    if store.loading && store.posts.isEmpty {
                        ForEach(0..<3, id: \.self) { i in SkeletonCard(media: i != 1) }
                    }

                    // A pin board: a "start a thread" box on top, then every
                    // post as a card in interlocking columns (pictures at
                    // their own shape, words as colourful quote cards).
                    // Switching feeds swaps the whole board with a soft
                    // crossfade (posts don't fly around).
                    VStack(spacing: 14) {
                        startThread
                        if feed == .forYou && !suggestions.isEmpty && !visible.isEmpty { suggested }
                        PinGrid(posts: visible, path: $path, reporting: $reporting, columns: sizeClass == .regular ? 3 : 2) {
                            Task { await store.loadMore() }
                        }
                    }
                    .id(feed.rawValue + (tag ?? ""))
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity.animation(Motion.exit)))

                    // Nothing in this feed: say so under the "start a thread" box.
                    if visible.isEmpty && !(store.loading && store.posts.isEmpty) {
                        EmptyCard(icon: feed == .saved ? "bookmark.fill" : "photo.on.rectangle.angled",
                                  title: feed == .saved ? "No saved posts" : feed == .following ? "It's quiet over here" : "Nothing here yet",
                                  text: feed == .saved ? "Tap the bookmark on a post and it'll wait for you here." : feed == .following ? "The people you follow haven't posted yet. Follow a few more artists?" : "No posts yet. Yours could be the first!",
                                  actionTitle: feed == .saved ? nil : "Share a post", action: feed == .saved ? nil : compose, compact: true)
                            .transition(.opacity)
                    }
                } header: {
                    feedBar
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 30)
            .sideRails(680)
        }
        .appearFade()
        .sugarBackground()
        .roundTitle("Community")
        .rootBar(search: { searching = true })
        .refreshable { await store.load() }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $searching) {
            SearchView { route in path.append(route) }.presentationCornerRadius(34)
        }
        .task { if store.posts.isEmpty { await store.load() } }
        .task {
            await TagTrends.shared.refresh()
            taste = await ReelBrain.shared.tagWeights()
        }
        // Saved: bring in saved posts that aren't among the loaded pages yet.
        .task(id: feed == .saved ? (model.me?.savedPosts ?? []) : []) {
            guard feed == .saved, let ids = model.me?.savedPosts else { return }
            let have = Set(store.posts.map(\.id))
            let missing = ids.filter { !have.contains($0) }
            guard !missing.isEmpty, let docs = try? await FS.getMany("CommunityPost", Array(missing.suffix(100))) else { return }
            let fresh = docs.values.map { Post($0) }.filter { p in !store.posts.contains { $0.id == p.id } }
            withMotion(Motion.standard) { store.posts.append(contentsOf: fresh) }
        }
        .onAppear { appeared = true }
    }

    private var onlineCount: Int { model.people.values.filter(\.isOnline).count }

    private var postsToday: Int {
        let start = Dates.iso(Calendar.current.startOfDay(for: Date()))
        return store.posts.filter { $0.created >= start }.count
    }

    // A bright hello at the top: what Community is, who's around, a button
    // to share, and your bunny.
    private var hero: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's new today").font(.display(25)).foregroundStyle(Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("Little updates. Long conversations.")
                    .font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    heroPill(icon: "circle.fill", text: "\(onlineCount) online", tint: Palette.success)
                    heroPill(icon: "flame.fill", text: "\(postsToday) today", tint: Palette.warning)
                }
                Button(action: compose) {
                    Label("Share something", systemImage: "square.and.pencil")
                }
                .buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            BunnyBuddy(look: bunny.look, height: 112)
                .onLongPressGesture { path.append(.bunny) }
        }
        .pastelCard(radius: 26, padding: 16)
        .overlay {
            TwinkleField(colors: [UIColor(hex: 0xFFC53D), .white, UIColor(Theme.main)])
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .opacity(0.8)
                .allowsHitTesting(false)
        }
        .overlay {
            ShineSweep(every: 6, strength: 0.28)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .onAppear { bunny.use(model.me?.email ?? "") }
    }

    private func heroPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
            Text(text).font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .padding(.horizontal, 10).frame(height: 26)
        .background(Palette.surface.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.rim(0.6), lineWidth: 1))
    }

    // "Start a thread…" at the top of the feed, like a social app.
    private var startThread: some View {
        Button(action: compose) {
            HStack(spacing: 12) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.me?.displayName ?? "You").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text)
                    Text("Start a thread…").font(.jakarta(14)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Text("Post").font(.jakarta(13, .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 16).frame(height: 34)
                    .background {
                        Capsule().fill(Theme.candy)
                            .shadow(color: Theme.glow(0.28), radius: 6, y: 3)
                    }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .sugarCard(radius: 22)
    }

    // Feed tabs in one bar that always fits the screen: the chosen one is a
    // candy pill with its name, the others show just their icon (each in its
    // own colour). The pill slides over to the one you tap.
    private var feedBar: some View {
        HStack(spacing: 4) {
            ForEach(Feed.allCases, id: \.self) { f in
                let on = feed == f
                Button {
                    guard feed != f else { return }
                    withAnimation(Motion.pick(.snappy(duration: 0.32))) { feed = f }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: f.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(on ? Color.white : f.candy.color)
                            .symbolEffect(.bounce, value: on)
                        if on {
                            Text(f.rawValue)
                                .font(.jakarta(13, .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, on ? 14 : 0)
                    .frame(maxWidth: on ? nil : .infinity)
                    .frame(height: 38)
                    .background {
                        if on {
                            Capsule().fill(f.candy.gradient)
                                .shadow(color: f.candy.color.softGlow(0.3), radius: 5, y: 2)
                                .matchedGeometryEffect(id: "feed", in: feedPill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.94))
                .accessibilityLabel(f.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
        .shadow(color: Palette.shadow, radius: 8, y: 3)
        .sensoryFeedback(.selection, trigger: feed)
        .padding(.vertical, 8)
        // When it sticks to the top, its strip reaches the screen edges so
        // posts don't peek out beside it.
        .background { Rectangle().fill(Palette.bg.opacity(0.97)).padding(.horizontal, -14) }
    }

    private var trendingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CandyTile(icon: "number", candy: .berry, size: 34)
                // The challenge filter that's on (tap to clear it).
                if let tag { tagChip(tag) }
                ForEach(Array(trending.filter { $0 != tag }.enumerated()), id: \.element) { i, t in
                    trendChip(t, candy: Candy.allCases[i % Candy.allCases.count])
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    // A trending tag: opens its page, with every post, reel, drawing and
    // song that has it.
    private func trendChip(_ t: String, candy: Candy) -> some View {
        Button { path.append(.hashtag(t)) } label: {
            Text("#\(t)").font(.jakarta(13, .bold))
                .foregroundStyle(candy.color)
                .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(candy.soft).overlay(Capsule().strokeBorder(candy.color.opacity(0.25), lineWidth: 1)))
        }
        .buttonStyle(BouncyStyle(scale: 0.92))
        .accessibilityHint("Shows everything tagged #\(t)")
    }

    private func tagChip(_ t: String) -> some View {
        let on = tag == t
        return Button { withMotion(Motion.standard) { tag = on ? nil : t } } label: {
            HStack(spacing: 5) {
                Text("#\(t)").font(.jakarta(13, .semibold))
                if on { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).transition(.scale.combined(with: .opacity)) }
            }
            .foregroundStyle(on ? .white : Palette.text2)
            .padding(.horizontal, 14).frame(height: 34)
            .background {
                if on {
                    Capsule().fill(Theme.candy).shadow(color: Theme.glow(0.25), radius: 5, y: 2)
                } else {
                    Capsule().fill(Palette.surface).overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.92))
    }

    // Who's been posting lately, as round stories; you first, with a +.
    private var stories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button(action: compose) {
                    VStack(spacing: 6) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 62)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(Theme.candy, in: Circle())
                                    .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 2.5))
                            }
                        Text("You").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    }
                }
                .buttonStyle(BouncyStyle()).accessibilityLabel("Share a post")
                ForEach(Array(storyPeople.enumerated()), id: \.element) { i, email in
                    let person = model.person(email)
                    Button { path.append(.person(email)) } label: {
                        VStack(spacing: 6) {
                            // A ring in the palette for people who posted lately.
                            Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 58, online: person?.isOnline ?? false)
                                .padding(3)
                                .overlay(Circle().strokeBorder(AngularGradient(colors: [Theme.main, Theme.partner, Candy.peach.color, Candy.lemon.color, Theme.main], center: .center), lineWidth: 3))
                            Text(person?.displayName ?? "").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text).lineLimit(1).frame(width: 70)
                        }
                    }
                    .buttonStyle(BouncyStyle())
                    .scaleEffect(appeared || Motion.reduced ? 1 : 0.88)
                    .opacity(appeared ? 1 : 0)
                    .animation(Motion.staggered(Motion.enter, i).delay(0.1), value: appeared)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private var suggested: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "person.crop.circle.badge.plus", title: "Suggested for you") { path.append(.people) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, person in
                        let candy = Candy.allCases[i % Candy.allCases.count]
                        let reason = person.following.contains(model.me?.email ?? "") ? "Follows you" : person.isOnline ? "Recently active" : "New on Sugerly"
                        VStack(spacing: 6) {
                            Avatar(url: person.picture, name: person.displayName, size: 76, online: person.isOnline)
                                .padding(3)
                                .overlay(Circle().strokeBorder(candy.gradient, lineWidth: 3))
                                .padding(.top, 6)
                            Text(person.displayName).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                            Text(reason).font(.jakarta(13)).foregroundStyle(Palette.muted)
                            FollowButton(email: person.email)
                                .padding(.top, 6)
                        }
                        .frame(width: 150)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [candy.soft, Palette.surface], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(candy.color.opacity(0.2), lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            Button { withMotion(Motion.standard) { _ = dismissed.insert(person.email) } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 34, height: 34)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 24))
                        .onTapGesture { path.append(.person(person.email)) }
                        .transition(.pop)
                    }
                }
            }
        }
        .sugarCard(radius: 22, padding: 16)
    }
}

// A label whose icon has its own colour.
struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

// MARK: - Post card

struct PostCard: View {
    let post: Post
    @Binding var path: [Route]
    @Binding var reporting: ReportSheet.Target?
    var openable = true
    var conversational = false

    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var heart = false
    @State private var confirmDelete = false
    @State private var sendSheet = false
    @State private var likeBurst: UUID?
    // Just followed: the button stays a moment to show "Following", then goes.
    @State private var justFollowed = false

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { LikeBook.shared.isLiked(post, me: me) }

    // "name  words…" under the picture, like a photo feed.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !post.title.isEmpty {
                Text(post.title).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
            }
            if !post.text.isEmpty {
                (Text(model.name(post.authorEmail, post.authorName) + "  ").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                 + Text(Hashtags.styled(post.text)).font(.jakarta(14)).foregroundStyle(Palette.text))
                    .lineLimit(openable ? 4 : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }
    private var saved: Bool { model.me?.savedPosts.contains(post.id) ?? false }
    private var author: UserProfile? { model.person(post.authorEmail) }
    private var following: Bool { model.me?.following.contains(post.authorEmail) ?? false }

    // Someone you follow who liked this post (the website's "Liked by Luna").
    private var friendLiker: UserProfile? {
        guard let me = model.me else { return nil }
        let following = Set(me.following)
        return post.likes.first { following.contains($0) && $0 != post.authorEmail }.flatMap { model.person($0) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let friend = friendLiker {
                Label("Liked by \(friend.displayName)", systemImage: "heart.fill")
                    .font(.jakarta(12, .bold)).foregroundStyle(Palette.muted)
                    .labelStyle(TintedIconLabel(tint: Theme.main))
                    .padding(.horizontal, 16).padding(.top, 14)
            }
            header
                .padding(.horizontal, 14)
                .padding(.top, friendLiker == nil ? 14 : 8)
                .padding(.bottom, 12)
            // Social layout: the picture right under the name, edge to edge,
            // then the buttons, then the words (like a photo feed).
            if conversational && !post.imageURL.isEmpty {
                media
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(.bottom, 6)
                actions.padding(.horizontal, 8)
                caption.padding(.horizontal, 16).padding(.top, 4)
                footer
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            } else {
            if !post.title.isEmpty {
                Text(post.title).font(conversational ? .jakarta(19, .bold) : .display(22)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { open() }
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
            if !post.text.isEmpty {
                Text(Hashtags.styled(post.text)).font(.jakarta(15)).foregroundStyle(Palette.text).lineLimit(openable ? 6 : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { open() }
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if !post.imageURL.isEmpty {
                media
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
            actions.padding(.horizontal, 12)
            footer
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .modifier(ConversationSurface(flat: conversational))
    }

    var body: some View {
        Group {
            if conversational { threadRow } else { card }
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await store.delete(post)
                    if !openable, !path.isEmpty { path.removeLast() }
                }
            }
        } message: { Text("This can't be undone.") }
        .sheet(isPresented: $sendSheet) {
            SendToChatsSheet(title: "Send post") { targets, note in
                guard let me = model.me, await TextGuard.clear([note], kind: .message, model: model) else { return }
                try await ReelLinks.sendPost(post, to: targets, note: note, me: me)
            }
            .presentationDetents([.height(340)])
            .presentationCornerRadius(30)
        }
    }

    // MARK: conversation row (the Community feed)

    // A post as a conversation: picture on the left with a thread line
    // running down to who replied, name and time, the words, the picture,
    // then light icon buttons with counts.
    private var threadRow: some View {
        let comments = store.commentCounts[post.id] ?? 0
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Button { path.append(.person(post.authorEmail)) } label: {
                    Avatar(url: author?.picture ?? post.authorPicture, name: author?.displayName ?? post.authorName, size: 42,
                           online: author?.isOnline ?? false, nitro: author?.isNitro ?? false)
                }
                .buttonStyle(BouncyStyle())
                if comments > 0, let top = store.latestComment[post.id] {
                    Capsule().fill(Palette.border).frame(width: 2).frame(maxHeight: .infinity)
                    Avatar(url: model.person(top.email)?.picture ?? "", name: model.person(top.email)?.displayName ?? top.name, size: 20)
                }
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button { path.append(.person(post.authorEmail)) } label: {
                        NameText(name: author?.displayName ?? post.authorName, style: author?.nameStyle ?? "", size: 15, nitro: author?.isNitro ?? false).lineLimit(1)
                    }
                    .buttonStyle(SoftPressStyle())
                    if author?.isNitro == true { NitroBadge(compact: true) }
                    Text(Dates.ago(post.created)).font(.jakarta(13)).foregroundStyle(Palette.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    if post.authorEmail != me && (!following || justFollowed) {
                        MorphPill(on: following, offTitle: "Follow", onTitle: "Following", size: .small) { follow() }
                            .transition(.pop)
                    }
                    moreMenu
                }
                if !post.title.isEmpty {
                    Text(post.title).font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle()).onTapGesture { open() }
                }
                if !post.text.isEmpty {
                    Text(Hashtags.styled(post.text)).font(.jakarta(15)).foregroundStyle(Palette.text).lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle()).onTapGesture { open() }
                }
                if !post.imageURL.isEmpty {
                    media
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
                        .padding(.top, 2)
                }
                HStack(spacing: 18) {
                    Button {
                        if !liked { burstLike() }
                        store.toggleLike(post, me: model.me)
                    } label: {
                        iconCount(liked ? "heart.fill" : "heart", post.likeTotal, on: liked, tint: Candy.berry.color)
                            .overlay(alignment: .leading) {
                                if let likeBurst { HeartPop().id(likeBurst).offset(x: 8) }
                            }
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: liked)
                    .accessibilityLabel(liked ? "Unlike" : "Like")
                    Button { open() } label: { iconCount("bubble.right", comments, on: false) }
                        .accessibilityLabel("Comments")
                    Button { sendSheet = true } label: { iconCount("paperplane", nil, on: false) }
                        .accessibilityLabel("Send to a chat")
                    ShareLink(item: ReelLinks.post(post.id), subject: Text("Sugerly"), message: Text(post.title.isEmpty ? post.text : post.title)) {
                        iconCount("square.and.arrow.up", nil, on: false)
                    }
                    .accessibilityLabel("Share")
                    Spacer(minLength: 0)
                    Button { toggleSave() } label: { iconCount(saved ? "bookmark.fill" : "bookmark", nil, on: saved, tint: Candy.lemon.color) }
                        .sensoryFeedback(.impact(weight: .light), trigger: saved)
                        .accessibilityLabel(saved ? "Remove from saved" : "Save")
                }
                .buttonStyle(BouncyStyle(scale: 0.8))
                .padding(.top, 2)
                if comments > 0 || post.likeTotal > 0 {
                    Button { open() } label: {
                        Text(summary(comments))
                            .font(.jakarta(13)).foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(SoftPressStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1).allowsHitTesting(false) }
        // Posts glide up as they come into view from below, following your
        // finger (no popping in or vanishing at the top).
        .scrollTransition(.interactive.threshold(.visible(0.25))) { content, phase in
            content
                .opacity(phase == .bottomTrailing ? 0.35 : 1)
                .offset(y: phase == .bottomTrailing && !Motion.reduced ? 16 : 0)
                .scaleEffect(phase == .bottomTrailing && !Motion.reduced ? 0.985 : 1, anchor: .top)
        }
    }

    // Little hearts fly out of the button when you like.
    private func burstLike() {
        let id = UUID()
        likeBurst = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            if likeBurst == id { likeBurst = nil }
        }
    }

    // "3 replies · 12 likes"
    private func summary(_ comments: Int) -> String {
        var parts: [String] = []
        if comments > 0 { parts.append(comments == 1 ? "1 reply" : "\(comments) replies") }
        if post.likeTotal > 0 { parts.append(post.likeTotal == 1 ? "1 like" : "\(post.likeTotal) likes") }
        return parts.joined(separator: " · ")
    }

    private func iconCount(_ icon: String, _ count: Int?, on: Bool, tint: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .symbolEffect(.bounce, value: on)
            if let count, count > 0 {
                Text("\(count)").font(.jakarta(13, .semibold)).contentTransition(.numericText())
            }
        }
        .foregroundStyle(on ? AnyShapeStyle(tint ?? Theme.main) : AnyShapeStyle(Palette.text2))
        .motion(Motion.playful, value: count)
        .frame(minWidth: 30, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var moreMenu: some View {
        Menu {
            if !post.text.isEmpty { Button { UIPasteboard.general.string = post.text; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy text", systemImage: "doc.on.doc") } }
            Button { sendSheet = true } label: { Label("Send to a chat", systemImage: "paperplane") }
            if post.authorEmail != me {
                Button { reporting = ReportSheet.Target(id: post.id, type: "post", ownerEmail: post.authorEmail, preview: post.title.isEmpty ? post.text : post.title, link: "/Community?post=\(post.id)") } label: { Label("Report", systemImage: "flag") }
            }
            if post.authorEmail == me || model.me?.isAdmin == true {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.muted)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { path.append(.person(post.authorEmail)) } label: {
                Avatar(url: author?.picture ?? post.authorPicture, name: author?.displayName ?? post.authorName, size: 44, online: author?.isOnline ?? false, ring: author?.isOnline ?? false, nitro: author?.isNitro ?? false)
            }
            .buttonStyle(BouncyStyle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    NameText(name: author?.displayName ?? post.authorName, style: author?.nameStyle ?? "", size: 15, nitro: author?.isNitro ?? false).lineLimit(1)
                    if author?.isNitro == true { NitroBadge(compact: true) }
                }
                HStack(spacing: 6) {
                    if let author {
                        let info = LevelInfo(xp: author.xp)
                        Text("Lv.\(info.level)")
                            .font(.jakarta(10, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(height: 17)
                            .background(info.color, in: Capsule())
                    }
                    Text(Dates.ago(post.created)).font(.jakarta(12, .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if post.authorEmail != me && (!following || justFollowed) {
                MorphPill(on: following, offTitle: "Follow", onTitle: "Following", size: .small) { follow() }
                    .transition(.pop)
            }
            Menu {
                if !post.text.isEmpty { Button { UIPasteboard.general.string = post.text; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy text", systemImage: "doc.on.doc") } }
                Button { sendSheet = true } label: { Label("Send to a chat", systemImage: "paperplane") }
                if post.authorEmail != me {
                    Button { reporting = ReportSheet.Target(id: post.id, type: "post", ownerEmail: post.authorEmail, preview: post.title.isEmpty ? post.text : post.title, link: "/Community?post=\(post.id)") } label: { Label("Report", systemImage: "flag") }
                }
                if post.authorEmail == me || model.me?.isAdmin == true {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text2)
                    .frame(width: 34, height: 34)
                    .background(Palette.surface2, in: Circle())
                    .contentShape(Circle())
            }
        }
    }

    private var media: some View {
        ArtImage(url: post.imageURL, tallest: 0.7)
            .background(Palette.surface2)
            .overlay {
                ZStack {
                    ForEach(0..<6, id: \.self) { i in
                        let angle = Double(i) / 6 * 2 * .pi - .pi / 2
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.light)
                            .offset(x: heart ? cos(angle) * 110 : 0, y: heart ? sin(angle) * 110 : 0)
                            .scaleEffect(heart ? 1 : 0.2)
                            .opacity(heart ? 0.9 : 0)
                    }
                    Image(systemName: "heart.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(Theme.gradient)
                        .shadow(color: Palette.shadow, radius: 12)
                        .scaleEffect(heart ? 1 : 0.3)
                        .opacity(heart ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { doubleTapLike() }
            .onTapGesture { open() }
    }

    // Likes and comments as soft pills; send, share and save as round buttons.
    private var actions: some View {
        HStack(spacing: 8) {
            Button { store.toggleLike(post, me: model.me) } label: {
                pill(liked ? "heart.fill" : "heart", count: post.likeTotal, active: liked, bounce: liked)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
            .accessibilityLabel(liked ? "Unlike" : "Like")
            Button { open() } label: {
                pill("bubble.right.fill", count: store.commentCounts[post.id] ?? 0, active: false, bounce: false)
            }
            .accessibilityLabel("Comments")
            Button { sendSheet = true } label: { pill("paperplane.fill", count: nil, active: false, bounce: false) }
                .accessibilityLabel("Send to a chat")
            ShareLink(item: ReelLinks.post(post.id), subject: Text("Sugerly"), message: Text(post.title.isEmpty ? post.text : post.title)) {
                pill("square.and.arrow.up", count: nil, active: false, bounce: false)
            }
            .accessibilityLabel("Share")
            Spacer(minLength: 0)
            Button { toggleSave() } label: { pill(saved ? "bookmark.fill" : "bookmark", count: nil, active: saved, bounce: saved) }
                .sensoryFeedback(.impact(weight: .light), trigger: saved)
                .accessibilityLabel(saved ? "Remove from saved" : "Save")
        }
        .buttonStyle(BouncyStyle(scale: 0.86))
    }

    private func pill(_ icon: String, count: Int?, active: Bool, bounce: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .symbolEffect(.bounce, value: bounce)
            if let count {
                Text("\(count)").font(.jakarta(14, .bold)).contentTransition(.numericText())
            }
        }
        .foregroundStyle(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text2))
        .padding(.horizontal, count == nil ? 0 : 14)
        .frame(minWidth: 40, minHeight: 40)
        .background(active ? Theme.soft : Palette.surface2, in: Capsule())
    }

    // Who liked it, the newest comment, and a box to add yours.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !post.likes.isEmpty { likedBy }
            if let top = store.latestComment[post.id] {
                Button { open() } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Avatar(url: model.person(top.email)?.picture ?? "", name: model.person(top.email)?.displayName ?? top.name, size: 26)
                        (Text(model.person(top.email)?.displayName ?? top.name).font(.jakarta(13, .bold)).foregroundColor(Palette.text)
                         + Text("  " + top.text).font(.jakarta(13)).foregroundColor(Palette.text2))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(SoftPressStyle())
                .contextMenu {
                    if top.email != me, !top.id.isEmpty {
                        Button { reporting = ReportSheet.Target(id: top.id, type: "comment", ownerEmail: top.email, preview: top.text, link: "/Community?post=\(post.id)", collection: "CommunityComment") } label: { Label("Report comment", systemImage: "flag") }
                    }
                }
            }
            if openable {
                Button { open() } label: {
                    HStack(spacing: 10) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 28)
                        Text((store.commentCounts[post.id] ?? 0) > 1 ? "View all \(store.commentCounts[post.id] ?? 0) comments" : "Add a comment…")
                            .font(.jakarta(14)).foregroundStyle(Palette.muted)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.gradient)
                    }
                    .padding(.leading, 5).padding(.trailing, 8)
                    .frame(height: 40)
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
                .buttonStyle(SoftPressStyle())
            }
        }
    }

    private var likedBy: some View {
        let likers = post.likes.compactMap { model.person($0) }
        return HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(likers.prefix(3)) { p in
                    Avatar(url: p.picture, name: p.displayName, size: 22).overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                }
            }
            if let first = likers.first {
                (Text("Liked by ") + Text(first.displayName).bold() + Text(post.likeTotal > 1 ? " and \(post.likeTotal - 1) other\(post.likeTotal == 2 ? "" : "s")" : ""))
                    .font(.jakarta(13)).foregroundStyle(Palette.text2).lineLimit(1)
            }
        }
    }

    private func open() { if openable { path.append(.post(post)) } }

    private func follow() {
        guard let me = model.me, !following else { return }
        justFollowed = true
        Task {
            // "Following" shows for a moment, then the button tucks away.
            try? await Task.sleep(for: .seconds(1.4))
            withMotion(Motion.exit) { justFollowed = false }
        }
        Task {
            try? await model.updateMe(["following": me.following + [post.authorEmail]])
            Notify.send(to: post.authorEmail, from: me, type: "follow", message: "\(me.displayName) started following you", link: "/Profile?email=\(me.email)")
            model.showToast("Following \(author?.displayName ?? post.authorName)", icon: "heart.fill")
        }
    }

    private func doubleTapLike() {
        if !liked { store.toggleLike(post, me: model.me) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heart = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.25)) { heart = false }
        }
    }

    private func toggleSave() {
        guard let me = model.me else { return }
        var next = me.savedPosts
        let saving = !next.contains(post.id)
        if saving { next.append(post.id) } else { next.removeAll { $0 == post.id } }
        model.showToast(saving ? "Saved" : "Removed from saved", icon: saving ? "bookmark.fill" : "bookmark")
        Task { try? await model.updateMe(["saved_posts": next]) }
    }
}

// MARK: - A post with its comments

struct PostDetailView: View {
    let postId: String
    let initial: Post
    @Binding var path: [Route]

    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var reporting: ReportSheet.Target?

    private var post: Post { store.posts.first { $0.id == postId } ?? initial }

    var body: some View {
        CommentsScreen(collection: "CommunityComment", field: "post_id", targetId: postId, ownerEmail: post.authorEmail, link: "/Community?post=\(postId)") {
            PostCard(post: post, path: $path, reporting: $reporting, openable: false)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
    }
}

// A scrolling page with something on top (post, artwork, reel) and its
// comments, with replies and likes, and a comment box that rides the keyboard.
struct CommentsScreen<Header: View>: View {
    let collection: String
    let field: String
    let targetId: String
    let ownerEmail: String
    let link: String
    var disabled = false
    @ViewBuilder var header: () -> Header

    @Environment(AppModel.self) private var model
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var replyTo: Comment?
    @State private var sending = false
    @State private var reporting: ReportSheet.Target?
    @State private var gifs = false
    @State private var hasOlder = false
    @State private var loadingOlder = false
    @FocusState private var typing: Bool

    private static var pageSize: Int { 300 }

    struct Thread: Identifiable {
        let parent: Comment
        let replies: [Comment]
        var id: String { parent.id }
    }

    // Grouped in one pass, so thousands of comments stay quick.
    private var threads: [Thread] {
        let blocked = Set(model.me?.blocked ?? [])
        let visible = comments.filter { !blocked.contains($0.authorEmail) }
        var replies: [String: [Comment]] = [:]
        for c in visible where !c.parentId.isEmpty { replies[c.parentId, default: []].append(c) }
        return visible.filter { $0.parentId.isEmpty }.map { Thread(parent: $0, replies: replies[$0.id] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header()
                HStack(spacing: 8) {
                    Text("Comments").font(.display(24)).foregroundStyle(Palette.text)
                    if !comments.isEmpty {
                        Text("\(comments.count)\(hasOlder ? "+" : "")").font(.jakarta(13, .bold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 9).frame(height: 24)
                            .background(Theme.candy, in: Capsule())
                            .contentTransition(.numericText())
                            .transition(.pop)
                    }
                }
                .padding(.horizontal, 4)
                if comments.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right").foregroundStyle(Theme.main)
                        Text("Be the first to say something nice.").font(.jakarta(14)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.blush.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
                }
                if hasOlder {
                    Button { Task { await loadOlder() } } label: {
                        HStack(spacing: 8) {
                            if loadingOlder { ProgressView().controlSize(.small).tint(Theme.main) } else { Image(systemName: "arrow.up.circle.fill") }
                            Text("Load earlier comments")
                        }
                        .font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 14).frame(height: 36)
                        .background(Theme.soft, in: Capsule())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                    .disabled(loadingOlder)
                }
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(threads) { thread in
                        CommentRow(comment: thread.parent, onReply: { reply(to: thread.parent) }, onReport: { report(thread.parent) }, onDelete: { delete(thread.parent) }, onLike: { like(thread.parent) })
                            .transition(Self.arrival)
                        ForEach(thread.replies) { r in
                            CommentRow(comment: r, onReply: { reply(to: thread.parent) }, onReport: { report(r) }, onDelete: { delete(r) }, onLike: { like(r) })
                                .padding(.leading, 44)
                                .transition(Self.arrival)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(14)
            .padding(.bottom, 10)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) { if !disabled { composer } }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $gifs) { GifPickerSheet { url in Task { await post(text: "", gif: url) } } }
        .task { await load() }
        .refreshable { await load() }
    }

    // A new comment grows in from its corner; a deleted one fades.
    private static var arrival: AnyTransition {
        guard !Motion.reduced else { return .opacity }
        return .asymmetric(insertion: .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity).combined(with: .offset(y: 8)),
                           removal: .opacity.combined(with: .scale(scale: 0.96)))
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let replyTo {
                HStack {
                    Text("Replying to \(replyTo.authorName)").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { withMotion { self.replyTo = nil } } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                GifButton { gifs = true }
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(.jakarta(15))
                    .lineLimit(1...5)
                    .focused($typing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(typing ? Theme.main.opacity(0.5) : Palette.border, lineWidth: 1.2))
                    .motion(Motion.fade, value: typing)
                SendButton(enabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending) { Task { await send() } }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background {
            Palette.surface
                .shadow(color: Palette.shadow, radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // The newest page of comments; older ones load on request, so a post
    // with a huge thread never downloads it all at once.
    private func load() async {
        guard let docs = try? await FS.query(collection, [.equals(field, targetId)], orderBy: "created_date", limit: Self.pageSize) else { return }
        let fresh = docs.map(Comment.init)
        let cutoff = fresh.map(\.created).min() ?? ""
        let older = comments.filter { $0.created < cutoff }
        if comments.isEmpty { hasOlder = docs.count >= Self.pageSize }
        withMotion(Motion.standard) { comments = (older + fresh).sorted { $0.created < $1.created } }
    }

    private func loadOlder() async {
        guard let oldest = comments.first?.created, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let docs = try? await FS.query(collection, [.equals(field, targetId), .before("created_date", oldest)], orderBy: "created_date", limit: Self.pageSize) else { return }
        hasOlder = docs.count >= Self.pageSize
        let known = Set(comments.map(\.id))
        let page = docs.map(Comment.init).filter { !known.contains($0.id) }
        withMotion(Motion.standard) { comments = (page + comments).sorted { $0.created < $1.created } }
    }

    private func reply(to comment: Comment) {
        withMotion { replyTo = comment }
        typing = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await post(text: text, gif: "")
    }

    private func post(text: String, gif: String) async {
        guard let me = model.me else { return }
        guard await TextGuard.clear([text], kind: .comment, model: model) else { return }
        sending = true
        defer { sending = false }
        let now = FS.nowISO()
        let data: Doc = [
            field: targetId, "content": text, "gif_url": gif,
            "parent_id": replyTo.map { $0.parentId.isEmpty ? $0.id : $0.parentId } ?? "",
            "reply_to_email": replyTo?.authorEmail ?? "", "reply_to_name": replyTo?.authorName ?? "",
            "user_email": me.email, "user_display_name": me.displayName, "user_full_name": me.displayName,
            "user_profile_picture": me.picture, "likes": [String](),
            "created_by": me.email, "created_date": now, "updated_date": now,
        ]
        do {
            let created = try await FS.create(collection, data)
            TapSound.play(.send)
            withMotion(Motion.standard) {
                comments.append(Comment(created))
                if !text.isEmpty { draft = "" }
            }
            let target = replyTo?.authorEmail ?? ownerEmail
            let said = text.isEmpty ? Media.label(gif).replacingOccurrences(of: "Sent", with: "sent") : "\"\(text.prefix(60))\""
            Notify.send(to: target, from: me, type: "comment", message: "\(me.displayName) \(replyTo == nil ? "commented" : "replied"): \(said)", link: link)
            replyTo = nil
        } catch {
            // Say why (it used to fail silently), and let them try again.
            TextGuard.forget(.comment, model: model)
            model.showToast(PostProblem.message(error), icon: "exclamationmark.circle", error: true)
        }
    }

    private func like(_ c: Comment) {
        guard let me = model.me?.email, let i = comments.firstIndex(where: { $0.id == c.id }) else { return }
        var next = c
        let liking = !next.likes.contains(me)
        TapSound.play(liking ? .like : .tap)
        if liking { next.likes.append(me) } else { next.likes.removeAll { $0 == me } }
        comments[i] = next
        Task { try? await FS.change(collection, c.id, [liking ? .add("likes", me) : .remove("likes", me)], set: ["updated_date": FS.nowISO()]) }
    }

    private func report(_ c: Comment) {
        reporting = ReportSheet.Target(id: c.id, type: "comment", ownerEmail: c.authorEmail, preview: c.text, link: link, collection: collection, media: c.gifURL)
    }

    private func delete(_ c: Comment) {
        withMotion { comments.removeAll { $0.id == c.id || $0.parentId == c.id } }
        Task { try? await FS.delete(collection, c.id) }
    }
}

struct SendButton: View {
    let enabled: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Theme.candy, in: Circle())
                .shadow(color: Theme.glow(enabled ? 0.32 : 0), radius: 8, y: 3)
                .scaleEffect(enabled ? 1 : 0.88)
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
        .disabled(!enabled)
        .motion(Motion.playful, value: enabled)
    }
}

struct CommentRow: View {
    let comment: Comment
    var onReply: () -> Void
    var onReport: () -> Void
    var onDelete: () -> Void
    var onLike: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let me = model.me?.email ?? ""
        let liked = comment.likes.contains(me)
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: model.person(comment.authorEmail)?.picture ?? comment.authorPicture, name: comment.authorName, size: 36, nitro: model.person(comment.authorEmail)?.isNitro ?? false)
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        NameText(name: comment.authorName, style: model.person(comment.authorEmail)?.nameStyle ?? "", size: 13, nitro: model.person(comment.authorEmail)?.isNitro ?? false)
                            .lineLimit(1)
                        Text(Dates.ago(comment.created)).font(.jakarta(11, .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if !comment.text.isEmpty { Text(comment.text).font(.jakarta(15)).foregroundStyle(Palette.text) }
                    if !comment.gifURL.isEmpty {
                        // GIFs play, stickers show without a frame (same as chats).
                        MessageMedia(url: comment.gifURL, width: 180)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(comment.authorEmail == me ? Palette.blush.opacity(0.55) : Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                HStack(spacing: 14) {
                    Button(action: onReply) { Label("Reply", systemImage: "arrowshape.turn.up.left.fill") }
                        .foregroundStyle(Palette.text2)
                    if !comment.likes.isEmpty {
                        Text("\(comment.likes.count) like\(comment.likes.count == 1 ? "" : "s")").foregroundStyle(Palette.muted)
                    }
                    // Always visible (not only on a long press), so anyone can report.
                    if comment.authorEmail != me {
                        Button(action: onReport) { Label("Report", systemImage: "flag") }
                            .foregroundStyle(Palette.muted)
                    } else {
                        Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                            .foregroundStyle(Palette.muted)
                    }
                }
                .font(.jakarta(12, .semibold))
                .buttonStyle(SoftPressStyle())
                .padding(.leading, 6)
            }
            Spacer(minLength: 0)
            Button(action: onLike) {
                VStack(spacing: 2) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted))
                        .symbolEffect(.bounce, value: liked)
                }
                .frame(width: 32)
                .padding(.top, 10)
            }
            .buttonStyle(BouncyStyle(scale: 0.8))
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
        }
        .contextMenu {
            if !comment.text.isEmpty { Button { UIPasteboard.general.string = comment.text } label: { Label("Copy", systemImage: "doc.on.doc") } }
            if comment.authorEmail != me { Button(action: onReport) { Label("Report", systemImage: "flag") } }
            if comment.authorEmail == me || model.me?.isAdmin == true { Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") } }
        }
    }
}

// MARK: - New post

struct NewPostView: View {
    var onPosted: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var gif = ""
    @State private var gifs = false
    @State private var posting = false
    @State private var status: String?
    @State private var error: String?
    @State private var drafts: [Drafts.Post] = []
    @State private var draftId: String?
    @State private var askDraft = false

    private var hasContent: Bool {
        image != nil || !gif.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ComposerScaffold(title: "New post", actionTitle: "Post", busy: posting, canPost: image != nil || !gif.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         hint: "Write something or add a picture first", status: status, error: error,
                         onClose: { if hasContent { askDraft = true } else { dismiss() } }, onPost: { Task { await post() } }) {
            if !drafts.isEmpty && draftId == nil && !hasContent {
                DraftStrip(title: "Drafts", items: drafts, thumb: { d in d.hasImage ? Drafts.image("posts", d.id, "image.jpg") : nil },
                           label: { d in d.title.isEmpty ? (d.text.isEmpty ? "Draft" : d.text) : d.title },
                           onOpen: { d in openDraft(d) },
                           onDelete: { d in Drafts.delete("posts", d.id); drafts = Drafts.posts() })
            }
            HStack(spacing: 12) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 46)
                VStack(alignment: .leading) {
                    Text(model.me?.displayName ?? "").font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
                    Text("Posting to Community").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
            }
            SugarField(placeholder: "Title (optional)", text: $title)
            SugarField(placeholder: "What's on your mind? Add #tags!", text: $text, lines: 4...12)
            if gif.isEmpty {
                Text("Add to your post").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                PhotoPickerCard(item: $item, image: $image)
                Button { gifs = true } label: { Label("Add a GIF or sticker instead", systemImage: "photo.stack.fill") }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
            } else {
                AnimatedThumb(url: gif, fill: false, maxPixel: 600, maxFrames: 90)
                    .frame(height: 260).frame(maxWidth: .infinity)
                    .background(Theme.pastel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.rim(0.55), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        Button { withMotion(Motion.standard) { gif = "" } } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(.black.opacity(0.45), in: Circle())
                        }
                        .padding(10)
                    }
            }
        }
        .sheet(isPresented: $gifs) { GifPickerSheet { url in withMotion(Motion.standard) { gif = url; image = nil; item = nil } } }
        .onAppear { drafts = Drafts.posts() }
        .confirmationDialog("Save this post as a draft?", isPresented: $askDraft, titleVisibility: .visible) {
            Button("Save draft") {
                Drafts.savePost(id: draftId, title: title, text: text, gif: gif, image: image)
                model.showToast("Saved to drafts", icon: "tray.and.arrow.down.fill")
                dismiss()
            }
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private func openDraft(_ d: Drafts.Post) {
        withMotion(Motion.standard) {
            draftId = d.id
            title = d.title
            text = d.text
            gif = d.gif
            image = d.hasImage ? Drafts.image("posts", d.id, "image.jpg") : nil
        }
    }

    private func post() async {
        guard let me = model.me else { return }
        error = nil
        guard await TextGuard.clear([title, text], kind: .post, model: model) else { return }
        posting = true
        defer { posting = false; status = nil }
        do {
            var imageURL = gif
            if gif.isEmpty, let image {
                status = "Getting your picture ready…"
                let picture = image
                guard let data = await Task.detached(priority: .userInitiated, operation: { ImageTools.jpeg(picture) }).value else {
                    throw APIError(message: "Couldn't read that picture. Try another one.")
                }
                status = "Uploading…"
                imageURL = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
            status = "Posting…"
            let now = FS.nowISO()
            let data: Doc = [
                "title": title.trimmingCharacters(in: .whitespaces), "description": text.trimmingCharacters(in: .whitespacesAndNewlines),
                "image_url": imageURL, "tags": Hashtags.tags(title, text), "user_email": me.email, "user_display_name": me.displayName,
                "user_profile_picture": me.picture, "likes": [String](), "created_by": me.email,
                "created_date": now, "updated_date": now,
            ]
            try await FS.create("CommunityPost", data)
            if let draftId { Drafts.delete("posts", draftId) }
            try? await model.addToMe(["xp": 20, "coins": 5])
            await onPosted()
            dismiss()
            model.showToast("Posted! +20 XP · +5 coins", icon: "sparkles")
        } catch {
            TextGuard.forget(.post, model: model)
            self.error = PostProblem.message(error)
        }
    }
}

// Shared look for the "new post / artwork / track" screens: Cancel at the
// top, the form in the middle and one big button at the bottom (it rides
// above the keyboard). While it posts, a card shows each step with a bar
// that moves along; a failed try shows why at the top.
struct ComposerScaffold<Content: View>: View {
    let title: String
    let actionTitle: String
    let busy: Bool
    let canPost: Bool
    // Said when the post button is tapped before it's ready ("Add a
    // picture first"), instead of the button doing nothing.
    var hint: String? = nil
    // What's happening while it posts ("Uploading your drawing…").
    var status: String? = nil
    // Why the last try didn't work.
    var error: String? = nil
    var onClose: () -> Void
    var onPost: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var nudge: CGFloat = 0
    @State private var shownHint: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var shown = false
    @State private var progress = 0.0
    @State private var creep: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(18)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    // The form settles in as the sheet opens.
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || Motion.reduced ? 0 : 14)
            }
            .scrollDismissesKeyboard(.interactively)
            // What's missing, or why it didn't post, just under the top bar.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let note = error ?? shownHint {
                    Label(note, systemImage: error != nil ? "exclamationmark.circle.fill" : "hand.point.up.left.fill")
                        .font(.jakarta(13, .semibold))
                        .foregroundStyle(error != nil ? Palette.danger : Theme.main)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: 640, alignment: .leading)
                        .background((error != nil ? Palette.danger : Theme.main).opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { postBar }
            .sugarBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                        .font(.jakarta(16, .semibold))
                        .disabled(busy)
                }
            }
        }
        .tint(Theme.main)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: error)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shownHint)
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    uploadCard
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: busy)
        .interactiveDismissDisabled(busy)
        .onAppear { withAnimation(Motion.pick(Motion.enter)) { shown = true } }
        .onChange(of: busy) { _, now in now ? startProgress() : stopProgress() }
        .onChange(of: status) { _, _ in if busy { step() } }
        .onDisappear {
            hintTask?.cancel()
            creep?.cancel()
        }
    }

    // The one big button at the bottom.
    private var postBar: some View {
        Button {
            if canPost { onPost() } else { nudgeHint() }
        } label: {
            Text(actionTitle)
        }
        .buttonStyle(GradientButtonStyle(height: 52))
        .disabled(busy || (!canPost && hint == nil))
        .opacity(canPost || busy ? 1 : 0.5)
        .modifier(ShakeEffect(shakes: nudge))
        .animation(.easeOut(duration: 0.2), value: canPost)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            // The page fades out under the button so nothing collides.
            LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg.opacity(0.94), Palette.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    // While posting: what's happening, and a bar that moves along with it.
    private var uploadCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.soft).frame(width: 64, height: 64)
                Image(systemName: progress >= 1 ? "checkmark" : "arrow.up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.main)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: progress < 1 && !Motion.reduced)
            }
            Text(status ?? "Posting…")
                .font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: status)
            SugarBar(value: progress)
                .tint(Theme.main)
                .frame(width: 200)
            Text("Keep Sugerly open until it's done")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 28).padding(.vertical, 26)
        .frame(minWidth: 260)
        .sugarCard(radius: 28)
    }

    // The bar jumps a little at each new step and creeps on slowly in
    // between, but never fills up until it's really done.
    private func startProgress() {
        progress = 0.08
        creep?.cancel()
        creep = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { progress += (0.9 - progress) * 0.04 }
            }
        }
    }

    private func step() {
        withAnimation(Motion.pick(Motion.standard)) { progress = min(0.9, progress + (0.9 - progress) * 0.45) }
    }

    private func stopProgress() {
        creep?.cancel()
        creep = nil
        progress = 0
    }

    // Not ready yet: the button gives a little shake and says what's missing.
    private func nudgeHint() {
        guard let hint else { return }
        withAnimation(.linear(duration: 0.4)) { nudge += 1 }
        shownHint = hint
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            shownHint = nil
        }
    }
}

// A quick side-to-side shake (a button saying "not yet").
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(shakes * .pi * 4), y: 0))
    }
}

// Friendly words for why posting didn't work.
enum PostProblem {
    static func message(_ error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline. Check your internet and try again."
            case .timedOut:
                return "That took too long. Check your internet and try again."
            default:
                return "Couldn't reach Sugerly. Try again in a moment."
            }
        }
        if let api = error as? APIError {
            switch api.status {
            case -1: return "You're offline. Check your internet and try again."
            case 401: return "Your login ran out. Log out and back in, then try again."
            case 403: return "Sugerly couldn't save this right now. If you're on a cooldown, wait a little and try again."
            case 413: return "That file is too big. Try a smaller one."
            default: return api.message
            }
        }
        return error.localizedDescription
    }
}

struct SugarField: View {
    let placeholder: String
    @Binding var text: String
    var lines: ClosedRange<Int>? = nil
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let lines {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(lines)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.jakarta(16))
        .focused($focused)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.main.opacity(0.5) : Palette.border, lineWidth: focused ? 1.5 : 1))
        .shadow(color: focused ? Theme.glow(0.16) : Palette.shadow.opacity(0.5), radius: focused ? 10 : 6, y: 3)
        .animation(.snappy(duration: 0.2), value: focused)
    }
}

// A small label over a field (or a few) on the upload pages.
struct FieldGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            content()
        }
    }
}

// Pick a picture (or see the one picked, with Edit / Change / remove).
// Big pictures (huge drawing canvases) are shrunk while they load, so they
// open quickly and never run the phone out of memory.
struct PhotoPickerCard: View {
    @Binding var item: PhotosPickerItem?
    @Binding var image: UIImage?
    @State private var editing = false
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image {
                    picked(image)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    PhotosPicker(selection: $item, matching: .images) {
                        VStack(spacing: 10) {
                            if loading {
                                ProgressView()
                                Text("Opening your picture…").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2)
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Theme.candy, in: Circle())
                                    .shadow(color: Theme.glow(0.28), radius: 8, y: 4)
                                Text("Add a picture").font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
                                Text("Choose one from your photos").font(.jakarta(13)).foregroundStyle(Palette.muted)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .background(Theme.pastel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.rim(0.55), lineWidth: 1))
                        .shadow(color: Palette.shadow, radius: 10, y: 4)
                        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.97))
                    .disabled(loading)
                    .transition(.opacity)
                }
            }
            if failed {
                Label("Couldn't open that picture. Try another one.", systemImage: "exclamationmark.triangle.fill")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: image == nil)
        .animation(.easeOut(duration: 0.2), value: loading)
        .fullScreenCover(isPresented: $editing) {
            if let image {
                PhotoEditorView(image: image) { edited in withMotion(Motion.standard) { self.image = edited } }
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task { await load(newItem) }
        }
    }

    private func picked(_ image: UIImage) -> some View {
        // Shown whole; very tall pictures sit in a frame a little taller
        // than wide, so the fields below stay close.
        let ratio = image.size.width / max(1, image.size.height)
        return Color.clear
            .aspectRatio(min(2, max(0.8, ratio)), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(8)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { withMotion(Motion.standard) { self.image = nil; item = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(.black.opacity(0.5), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(BouncyStyle())
                .accessibilityLabel("Remove picture")
                .padding(14)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Change", systemImage: "photo.on.rectangle.angled").font(.jakarta(13, .semibold)).foregroundStyle(Palette.text)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(BouncyStyle())
                    Spacer(minLength: 0)
                    Button { editing = true } label: {
                        Label("Edit", systemImage: "wand.and.stars").font(.jakarta(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Theme.candy, in: Capsule())
                            .shadow(color: Theme.glow(0.28), radius: 6, y: 3)
                    }
                    .buttonStyle(BouncyStyle())
                }
                .padding(14)
            }
    }

    private func load(_ newItem: PhotosPickerItem) async {
        loading = true
        failed = false
        defer { loading = false }
        guard let data = try? await newItem.loadTransferable(type: Data.self) else {
            if item == newItem { withMotion { failed = true } }
            return
        }
        let shrunk = await Task.detached(priority: .userInitiated) { ImagePipeline.downsample(data, maxPixel: 2560) }.value
        guard item == newItem else { return }
        if let shrunk {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { image = shrunk }
        } else {
            withMotion { failed = true }
        }
    }
}

enum ImageTools {
    // Pictures are resized to at most 2048 px and saved as JPEG before upload.
    nonisolated static func jpeg(_ image: UIImage, maxSide: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // JPEG can't be see-through: fill with white first so transparent
        // pictures (PNG stickers, cut-outs) don't turn black.
        format.opaque = true
        format.preferredRange = .standard
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

extension View {
    // Soft rounded pill behind a post action (like, comment, share, save).
    func actionPill(active: Bool) -> some View {
        self
            .padding(.horizontal, 12)
            .frame(minWidth: 42, minHeight: 38)
            .background(active ? Theme.soft : Palette.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Theme.main.opacity(0.25) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
    }
}

// Feed posts: a clean rounded card each (light, no heavy shadow, so the
// feed scrolls smoothly), like a social app.
private struct ConversationSurface: ViewModifier {
    let flat: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if flat {
            content
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
        } else { content.sugarCard(radius: 22) }
    }
}

// A little burst of hearts (a like). Shows once and fades away.
struct HeartPop: View {
    var size: CGFloat = 9
    var spread: CGFloat = 22
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let a = Double(i) / 7 * 2 * .pi - .pi / 2
                Image(systemName: "heart.fill").font(.system(size: size, weight: .bold))
                    .foregroundStyle(i.isMultiple(of: 2) ? Theme.main : Theme.light)
                    .offset(x: go ? cos(a) * spread : 0, y: go ? sin(a) * spread : 0)
                    .scaleEffect(go ? 1 : 0.2)
                    .opacity(go ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.65)) { go = true } }
    }
}
