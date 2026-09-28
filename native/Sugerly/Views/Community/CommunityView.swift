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
                    latest[post] = CommentPreview(email: c.str("user_email").lowercased(), name: c.str("user_display_name"), text: c.str("content"))
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
    }
}

struct CommentPreview {
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

// Words that start with # in a caption.
enum Hashtags {
    static func find(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { word in
            guard word.hasPrefix("#") else { return nil }
            let tag = word.dropFirst().filter { $0.isLetter || $0.isNumber || $0 == "_" }.lowercased()
            return tag.count >= 2 ? tag : nil
        }
    }

    // Caption with #tags in the accent colour.
    static func styled(_ text: String) -> AttributedString {
        var out = AttributedString()
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (i, word) in words.enumerated() {
            var piece = AttributedString(String(word))
            if word.hasPrefix("#") && word.count > 1 {
                piece.foregroundColor = Theme.pink
                piece.font = Font.jakarta(15, .bold)
            }
            out += piece
            if i < words.count - 1 { out += AttributedString(" ") }
        }
        return out
    }
}

struct CommunityView: View {
    enum Feed: String, CaseIterable { case forYou = "For you", following = "Following", latest = "Latest", top = "Top", saved = "Saved" }

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
    @State private var pulse = false
    @Namespace private var feedPill

    private var visible: [Post] {
        guard let me = model.me else { return [] }
        let blocked = Set(me.blocked + me.ignored)
        var all = store.posts.filter { !blocked.contains($0.authorEmail) }
        if let tag { all = all.filter { Hashtags.find($0.title + " " + $0.text).contains(tag) } }
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

    // Recent, liked and from people you follow floats up.
    private func score(_ p: Post, _ following: Set<String>) -> Double {
        let hours = max(0, Date().timeIntervalSince(Dates.parse(p.created) ?? Date()) / 3600)
        let engagement = Double(p.likeTotal) + Double(store.commentCounts[p.id] ?? 0) * 2 + 1
        let boost = following.contains(p.authorEmail) ? 1.6 : 1
        return engagement * boost / pow(hours + 2, 1.15)
    }

    private var trending: [String] {
        var counts: [String: Int] = [:]
        for p in store.posts { for t in Set(Hashtags.find(p.title + " " + p.text)) { counts[t, default: 0] += 1 } }
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
            HStack {
                Label("Top creators this week", systemImage: "crown.fill").font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                    .labelStyle(TintedIconLabel(tint: Color(hex: 0xF0A020)))
                Spacer()
                Button { path.append(.topArtists) } label: {
                    HStack(spacing: 3) { Text("Board"); Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)) }
                        .font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(topCreators.enumerated()), id: \.element.0) { i, entry in
                        let person = model.person(entry.0)
                        Button { path.append(.person(entry.0)) } label: {
                            VStack(spacing: 5) {
                                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 54, online: person?.isOnline ?? false)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(i == 0 ? Color(hex: 0xF0A020) : i == 1 ? Color(hex: 0x94A3B8) : i == 2 ? Color(hex: 0xC2773A) : Palette.border, lineWidth: i < 3 ? 2.5 : 1.5))
                                    .overlay(alignment: .top) {
                                        if i == 0 {
                                            Image(systemName: "crown.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0xF0A020))
                                                .offset(y: -13)
                                                .phaseAnimator([false, true]) { v, up in v.offset(y: up ? -3 : 0).rotationEffect(.degrees(up ? -8 : 8)) } animation: { _ in .easeInOut(duration: 0.9) }
                                        }
                                    }
                                Text(person?.displayName ?? "").font(.jakarta(11, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                Label("\(entry.1)", systemImage: "heart.fill").font(.jakarta(10, .heavy)).foregroundStyle(Theme.main)
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
        .sugarCard(radius: 26, padding: 14)
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
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                header.stagger(appeared, 0)
                stories.stagger(appeared, 1)
                composerCard.stagger(appeared, 2)
                WeeklyChallengeCard(posts: store.posts, active: tag != nil && tag == DailyContent.challenge?.tag, compose: compose) { t in
                    withAnimation(.snappy) { tag = tag == t ? nil : t; feed = .latest }
                }
                .stagger(appeared, 3)
                if !topCreators.isEmpty { creatorsRow.stagger(appeared, 4) }
                Section {
                    if !trending.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Label("Trending", systemImage: "chart.line.uptrend.xyaxis").font(.jakarta(14, .bold)).foregroundStyle(Theme.main)
                                    .padding(.trailing, 4)
                                ForEach(trending, id: \.self) { t in
                                    Button { withAnimation(.snappy) { tag = tag == t ? nil : t } } label: {
                                        Text("#\(t)").font(.jakarta(14, .semibold))
                                            .foregroundStyle(tag == t ? .white : Palette.text2)
                                            .padding(.horizontal, 16).frame(height: 38)
                                            .background {
                                                if tag == t { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface).overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1)) }
                                            }
                                    }
                                    .buttonStyle(BouncyStyle())
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                        }
                    }

                    if store.loading && store.posts.isEmpty {
                        ForEach(0..<3, id: \.self) { i in SkeletonCard(media: i != 1) }
                    } else if visible.isEmpty {
                        EmptyCard(icon: feed == .saved ? "bookmark.fill" : "photo.on.rectangle.angled",
                                  title: feed == .saved ? "No saved posts" : feed == .following ? "It's quiet over here" : "Nothing here yet",
                                  text: feed == .saved ? "Tap the bookmark on a post and it'll wait for you here." : feed == .following ? "The people you follow haven't posted yet. Follow a few more artists?" : "No posts yet. Yours could be the first!",
                                  actionTitle: feed == .saved ? nil : "Share a post", action: feed == .saved ? nil : compose)
                    }

                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, post in
                        PostCard(post: post, path: $path, reporting: $reporting)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            .onAppear { if index >= visible.count - 5 { Task { await store.loadMore() } } }
                        if index == 1 && !suggestions.isEmpty && feed == .forYou { suggested }
                    }
                } header: {
                    feedBar
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: feed)
        }
        .sugarBackground()
        .sugarTopBar($path)
        .refreshable { await store.load() }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $searching) {
            SearchView { route in path.append(route) }.presentationCornerRadius(34)
        }
        .task { if store.posts.isEmpty { await store.load() } }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Community").font(.display(38)).foregroundStyle(Palette.text)
                HStack(spacing: 7) {
                    Circle().fill(Palette.success).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Palette.success.opacity(0.5), lineWidth: 2).scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 1))
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                    Text("\(model.people.values.filter(\.isOnline).count) online · \(store.posts.count) posts")
                        .font(.jakarta(14, .medium)).foregroundStyle(Palette.muted)
                        .contentTransition(.numericText())
                }
                .onAppear { pulse = true }
            }
            Spacer()
            squareButton("magnifyingglass") { searching = true }
            squareButton("square.and.pencil") { compose() }
        }
        .padding(.horizontal, 4)
    }

    private func squareButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                .frame(width: 48, height: 48)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                .shadow(color: Palette.shadow, radius: 6, y: 2)
        }
        .buttonStyle(BouncyStyle())
    }

    // Feed tabs in one pill that sticks under the top bar while you scroll.
    private var feedBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                chip(.forYou, "sparkles"); chip(.following, "person.crop.circle.badge.checkmark"); chip(.latest, "clock"); chip(.top, "flame"); chip(.saved, "bookmark")
            }
            .padding(4)
        }
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 8, y: 3)
        .padding(.vertical, 6)
        .background(Palette.bg.opacity(0.92).padding(.horizontal, -14))
    }

    private func chip(_ f: Feed, _ icon: String) -> some View {
        let active = feed == f
        return Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { feed = f } } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(f.rawValue).font(.jakarta(15, .bold))
            }
            .foregroundStyle(active ? .white : Palette.text2)
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background {
                if active {
                    Capsule().fill(Theme.gradient)
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)).padding(1))
                        .shadow(color: Theme.main.opacity(0.35), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "feed", in: feedPill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.93))
        .sensoryFeedback(.selection, trigger: active)
    }

    private var stories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button(action: compose) {
                    VStack(spacing: 6) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 62)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 2.5))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24).background(Theme.gradient, in: Circle())
                                    .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 2.5))
                            }
                        Text("Your post").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2)
                    }
                }
                .buttonStyle(BouncyStyle())
                ForEach(storyPeople, id: \.self) { email in
                    let person = model.person(email)
                    Button { path.append(.person(email)) } label: {
                        VStack(spacing: 6) {
                            Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 62, online: person?.isOnline ?? false)
                                .padding(3)
                                .overlay(Circle().strokeBorder(LinearGradient(colors: [Color(hex: 0xF7A23B), Color(hex: 0xE8457C), Color(hex: 0xA855F7)], startPoint: .bottomLeading, endPoint: .topTrailing), lineWidth: 3))
                            Text(person?.displayName ?? "").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text).lineLimit(1).frame(width: 70)
                        }
                    }
                    .buttonStyle(BouncyStyle())
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private var composerCard: some View {
        Button(action: compose) {
            HStack(spacing: 12) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 44)
                Text("Share your latest piece, \(model.me?.displayName.split(separator: " ").first.map(String.init) ?? "")…")
                    .font(.jakarta(15)).foregroundStyle(Palette.muted).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).frame(height: 46)
                    .background(Palette.surface2, in: Capsule())
                Image(systemName: "photo.fill").font(.system(size: 18)).foregroundStyle(Theme.gradient)
            }
            .sugarCard(radius: 26, padding: 12)
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private var suggested: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Suggested for you").font(.jakarta(18, .heavy)).foregroundStyle(Palette.text)
                Spacer()
                Button("See all") { path.append(.people) }.font(.jakarta(15, .bold)).foregroundStyle(Theme.main)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestions) { person in
                        let reason = person.following.contains(model.me?.email ?? "") ? "Follows you" : person.isOnline ? "Recently active" : "New on Sugerly"
                        VStack(spacing: 6) {
                            Avatar(url: person.picture, name: person.displayName, size: 76, online: person.isOnline)
                                .padding(.top, 6)
                            Text(person.displayName).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                            Text(reason).font(.jakarta(13)).foregroundStyle(Palette.muted)
                            FollowButton(email: person.email)
                                .padding(.top, 6)
                        }
                        .frame(width: 150)
                        .padding(.vertical, 16)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { withAnimation(.snappy) { _ = dismissed.insert(person.email) } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 34, height: 34)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 24))
                        .onTapGesture { path.append(.person(person.email)) }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .sugarCard(radius: 28, padding: 16)
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

    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var heart = false
    @State private var confirmDelete = false
    @State private var sendSheet = false

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { LikeBook.shared.isLiked(post, me: me) }
    private var saved: Bool { model.me?.savedPosts.contains(post.id) ?? false }
    private var author: UserProfile? { model.person(post.authorEmail) }
    private var following: Bool { model.me?.following.contains(post.authorEmail) ?? false }

    // Someone you follow who liked this post (the website's "Liked by Luna").
    private var friendLiker: UserProfile? {
        guard let me = model.me else { return nil }
        let following = Set(me.following)
        return post.likes.first { following.contains($0) && $0 != post.authorEmail }.flatMap { model.person($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let friend = friendLiker {
                Label("Liked by \(friend.displayName)", systemImage: "heart")
                    .font(.jakarta(13, .bold)).foregroundStyle(Palette.muted)
                    .labelStyle(TintedIconLabel(tint: Theme.main))
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, -4)
            }
            header.padding(.horizontal, 16).padding(.top, friendLiker == nil ? 16 : 0)
            if !post.text.isEmpty {
                Text(Hashtags.styled(post.text)).font(.jakarta(16)).foregroundStyle(Palette.text).lineLimit(openable ? 6 : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { open() }
                    .padding(.horizontal, 16)
            }
            if !post.imageURL.isEmpty { media }
            VStack(alignment: .leading, spacing: 10) {
                actions
                if !post.likes.isEmpty { likedBy }
                if let top = store.latestComment[post.id] {
                    Button { open() } label: {
                        (Text(model.person(top.email)?.displayName ?? top.name).font(.jakarta(14, .heavy)).foregroundColor(Palette.text)
                         + Text("  " + top.text).font(.jakarta(14)).foregroundColor(Palette.text2))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                if openable {
                    Button { open() } label: {
                        HStack(spacing: 10) {
                            Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 30)
                            Text((store.commentCounts[post.id] ?? 0) > 1 ? "View all \(store.commentCounts[post.id] ?? 0) comments…" : "Add a comment…")
                                .font(.jakarta(15)).foregroundStyle(Palette.muted)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, post.imageURL.isEmpty ? 0 : 4)
        }
        .sugarCard(radius: 28)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                guard let me = model.me else { return }
                try await ReelLinks.sendPost(post, to: targets, note: note, me: me)
            }
            .presentationDetents([.height(340)])
            .presentationCornerRadius(30)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { path.append(.person(post.authorEmail)) } label: {
                Avatar(url: author?.picture ?? post.authorPicture, name: author?.displayName ?? post.authorName, size: 46, online: author?.isOnline ?? false, ring: author?.isOnline ?? false, nitro: author?.isNitro ?? false)
            }
            .buttonStyle(BouncyStyle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    NameText(name: author?.displayName ?? post.authorName, style: author?.nameStyle ?? "", size: 15, nitro: author?.isNitro ?? false).lineLimit(1)
                    if author?.isNitro == true { NitroBadge(compact: true) }
                    if let author {
                        let info = LevelInfo(xp: author.xp)
                        Text("Lv.\(info.level)")
                            .font(.jakarta(10, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(height: 17)
                            .background(info.color, in: Capsule())
                    }
                    if post.authorEmail != me && !following {
                        Button { follow() } label: {
                            Text("Follow").font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(Theme.soft, in: Capsule())
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                Text(Dates.ago(post.created) + (post.title.isEmpty ? "" : " · \(post.title)")).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            Menu {
                if !post.text.isEmpty { Button { UIPasteboard.general.string = post.text; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy text", systemImage: "doc.on.doc") } }
                if post.authorEmail != me {
                    Button { reporting = ReportSheet.Target(id: post.id, type: "post", ownerEmail: post.authorEmail, preview: post.title.isEmpty ? post.text : post.title, link: "/Community?post=\(post.id)") } label: { Label("Report", systemImage: "flag") }
                }
                if post.authorEmail == me || model.me?.isAdmin == true {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 36, height: 36).contentShape(Rectangle())
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
                        .shadow(color: Theme.pink.opacity(0.6), radius: 20)
                        .scaleEffect(heart ? 1 : 0.3)
                        .opacity(heart ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { doubleTapLike() }
            .onTapGesture { open() }
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button { store.toggleLike(post, me: model.me) } label: {
                HStack(spacing: 6) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text2))
                        .symbolEffect(.bounce, value: liked)
                    Text("\(post.likeTotal)").font(.jakarta(17, .semibold)).foregroundStyle(liked ? Theme.pink : Palette.text2)
                        .contentTransition(.numericText())
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
            Button { open() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right").foregroundStyle(Palette.text2)
                    Text("\(store.commentCounts[post.id] ?? 0)").font(.jakarta(17, .semibold)).foregroundStyle(Palette.text2)
                }
            }
            Button { sendSheet = true } label: {
                Image(systemName: "paperplane").foregroundStyle(Palette.text2)
            }
            .accessibilityLabel("Send to a chat")
            ShareLink(item: ReelLinks.post(post.id), subject: Text("Sugerly"), message: Text(post.title.isEmpty ? post.text : post.title)) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(Palette.text2)
            }
            Spacer()
            Button { toggleSave() } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(saved ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text2))
                    .symbolEffect(.bounce, value: saved)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: saved)
            .accessibilityLabel(saved ? "Remove from saved" : "Save")
        }
        .font(.system(size: 23, weight: .semibold))
        .buttonStyle(BouncyStyle(scale: 0.85))
    }

    private var likedBy: some View {
        let likers = post.likes.compactMap { model.person($0) }
        return HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(likers.prefix(3)) { p in
                    Avatar(url: p.picture, name: p.displayName, size: 24).overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
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
        guard let me = model.me else { return }
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
                Text(comments.isEmpty ? "No comments yet" : "\(comments.count)\(hasOlder ? "+" : "") comment\(comments.count == 1 ? "" : "s")")
                    .font(.display(22)).foregroundStyle(Palette.text).padding(.horizontal, 4)
                if hasOlder {
                    Button { Task { await loadOlder() } } label: {
                        HStack(spacing: 8) {
                            if loadingOlder { ProgressView().controlSize(.small).tint(Theme.main) } else { Image(systemName: "arrow.up.circle.fill") }
                            Text("Load earlier comments")
                        }
                        .font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Theme.soft, in: Capsule())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                    .disabled(loadingOlder)
                }
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(threads) { thread in
                        CommentRow(comment: thread.parent, onReply: { reply(to: thread.parent) }, onReport: { report(thread.parent) }, onDelete: { delete(thread.parent) }, onLike: { like(thread.parent) })
                        ForEach(thread.replies) { r in
                            CommentRow(comment: r, onReply: { reply(to: thread.parent) }, onReport: { report(r) }, onDelete: { delete(r) }, onLike: { like(r) })
                                .padding(.leading, 44)
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

    private var composer: some View {
        VStack(spacing: 6) {
            if let replyTo {
                HStack {
                    Text("Replying to \(replyTo.authorName)").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { withAnimation { self.replyTo = nil } } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(Palette.muted)
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
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(typing ? Theme.pink.opacity(0.5) : Palette.border, lineWidth: 1.2))
                SendButton(enabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending) { Task { await send() } }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
        withAnimation(.snappy) { comments = (older + fresh).sorted { $0.created < $1.created } }
    }

    private func loadOlder() async {
        guard let oldest = comments.first?.created, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let docs = try? await FS.query(collection, [.equals(field, targetId), .before("created_date", oldest)], orderBy: "created_date", limit: Self.pageSize) else { return }
        hasOlder = docs.count >= Self.pageSize
        let known = Set(comments.map(\.id))
        let page = docs.map(Comment.init).filter { !known.contains($0.id) }
        withAnimation(.snappy) { comments = (page + comments).sorted { $0.created < $1.created } }
    }

    private func reply(to comment: Comment) {
        withAnimation { replyTo = comment }
        typing = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await post(text: text, gif: "")
    }

    private func post(text: String, gif: String) async {
        guard let me = model.me else { return }
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
            withAnimation(.snappy) {
                comments.append(Comment(created))
                if !text.isEmpty { draft = "" }
            }
            let target = replyTo?.authorEmail ?? ownerEmail
            let said = text.isEmpty ? Media.label(gif).replacingOccurrences(of: "Sent", with: "sent") : "\"\(text.prefix(60))\""
            Notify.send(to: target, from: me, type: "comment", message: "\(me.displayName) \(replyTo == nil ? "commented" : "replied"): \(said)", link: link)
            replyTo = nil
        } catch {}
    }

    private func like(_ c: Comment) {
        guard let me = model.me?.email, let i = comments.firstIndex(where: { $0.id == c.id }) else { return }
        var next = c
        let liking = !next.likes.contains(me)
        if liking { next.likes.append(me) } else { next.likes.removeAll { $0 == me } }
        comments[i] = next
        Task { try? await FS.change(collection, c.id, [liking ? .add("likes", me) : .remove("likes", me)], set: ["updated_date": FS.nowISO()]) }
    }

    private func report(_ c: Comment) {
        reporting = ReportSheet.Target(id: c.id, type: "comment", ownerEmail: c.authorEmail, preview: c.text, link: link)
    }

    private func delete(_ c: Comment) {
        withAnimation { comments.removeAll { $0.id == c.id || $0.parentId == c.id } }
        Task { try? await FS.delete(collection, c.id) }
    }
}

struct SendButton: View {
    let enabled: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Theme.gradient, in: Circle())
                .shadow(color: Theme.pink.opacity(enabled ? 0.5 : 0), radius: 10, y: 4)
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
        .disabled(!enabled)
        .animation(.snappy, value: enabled)
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
                VStack(alignment: .leading, spacing: 3) {
                    NameText(name: comment.authorName, style: model.person(comment.authorEmail)?.nameStyle ?? "", size: 13, nitro: model.person(comment.authorEmail)?.isNitro ?? false)
                    if !comment.text.isEmpty { Text(comment.text).font(.jakarta(15)).foregroundStyle(Palette.text) }
                    if !comment.gifURL.isEmpty {
                        // GIFs play, stickers show without a frame (same as chats).
                        MessageMedia(url: comment.gifURL, width: 180)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                HStack(spacing: 14) {
                    Text(Dates.ago(comment.created)).foregroundStyle(Palette.muted)
                    Button("Reply", action: onReply).foregroundStyle(Palette.text2)
                }
                .font(.jakarta(12, .bold))
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            Spacer(minLength: 0)
            Button(action: onLike) {
                VStack(spacing: 2) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted))
                        .symbolEffect(.bounce, value: liked)
                    if !comment.likes.isEmpty { Text("\(comment.likes.count)").font(.jakarta(11, .bold)).foregroundStyle(Palette.muted) }
                }
                .frame(width: 32)
                .padding(.top, 10)
            }
            .buttonStyle(BouncyStyle(scale: 0.8))
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = comment.text } label: { Label("Copy", systemImage: "doc.on.doc") }
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
    @State private var error: String?
    @State private var drafts: [Drafts.Post] = []
    @State private var draftId: String?
    @State private var askDraft = false

    private var hasContent: Bool {
        image != nil || !gif.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ComposerScaffold(title: "New post", actionTitle: "Post", busy: posting, canPost: image != nil || !gif.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, onClose: { if hasContent { askDraft = true } else { dismiss() } }, onPost: { Task { await post() } }) {
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
                PhotoPickerCard(item: $item, image: $image)
                Button { gifs = true } label: { Label("Add a GIF or sticker", systemImage: "photo.stack.fill") }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
            } else {
                AnimatedThumb(url: gif, fill: false, maxPixel: 600, maxFrames: 90)
                    .frame(height: 260).frame(maxWidth: .infinity)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { withAnimation(.snappy) { gif = "" } } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(.black.opacity(0.45), in: Circle())
                        }
                        .padding(10)
                    }
            }
            if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
        }
        .sheet(isPresented: $gifs) { GifPickerSheet { url in withAnimation(.snappy) { gif = url; image = nil; item = nil } } }
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
        withAnimation(.snappy) {
            draftId = d.id
            title = d.title
            text = d.text
            gif = d.gif
            image = d.hasImage ? Drafts.image("posts", d.id, "image.jpg") : nil
        }
    }

    private func post() async {
        guard let me = model.me else { return }
        posting = true
        defer { posting = false }
        do {
            var imageURL = gif
            if gif.isEmpty, let image, let data = ImageTools.jpeg(image) {
                imageURL = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
            let now = FS.nowISO()
            let data: Doc = [
                "title": title.trimmingCharacters(in: .whitespaces), "description": text.trimmingCharacters(in: .whitespacesAndNewlines),
                "image_url": imageURL, "user_email": me.email, "user_display_name": me.displayName,
                "user_profile_picture": me.picture, "likes": [String](), "like_count": 0, "created_by": me.email,
                "created_date": now, "updated_date": now,
            ]
            try await FS.create("CommunityPost", data)
            if let draftId { Drafts.delete("posts", draftId) }
            try? await model.updateMe(["xp": me.xp + 20, "coins": me.coins + 5])
            await onPosted()
            dismiss()
            model.showToast("Posted! +20 XP · +5 coins", icon: "sparkles")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Shared look for the "new post / artwork / track" screens.
struct ComposerScaffold<Content: View>: View {
    let title: String
    let actionTitle: String
    let busy: Bool
    let canPost: Bool
    var onClose: () -> Void
    var onPost: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text2)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                }
                .buttonStyle(BouncyStyle())
                Spacer()
                Text(title).font(.display(24)).foregroundStyle(Palette.text)
                Spacer()
                Button(action: onPost) {
                    if busy { ProgressView().tint(.white) } else { Text(actionTitle) }
                }
                .buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
                .disabled(busy || !canPost)
                .opacity(canPost ? 1 : 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding(18)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sugarBackground()
        .interactiveDismissDisabled(busy)
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
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.pink.opacity(0.55) : Palette.border, lineWidth: focused ? 2 : 1))
        .shadow(color: focused ? Theme.pink.opacity(0.18) : .clear, radius: 10, y: 4)
        .animation(.snappy(duration: 0.2), value: focused)
    }
}

struct PhotoPickerCard: View {
    @Binding var item: PhotosPickerItem?
    @Binding var image: UIImage?
    @State private var editing = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { withAnimation(.snappy) { self.image = nil; item = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(.black.opacity(0.5), in: Circle())
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button { editing = true } label: {
                            Label("Edit", systemImage: "wand.and.stars").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(Theme.gradient, in: Capsule())
                                .shadow(color: Theme.main.opacity(0.4), radius: 8, y: 3)
                        }
                        .buttonStyle(BouncyStyle())
                        .padding(10)
                    }
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
                PhotosPicker(selection: $item, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.gradient)
                        Text("Add a picture").font(.jakarta(15, .bold)).foregroundStyle(Theme.pink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .background(Theme.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.pink.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                }
                .buttonStyle(BouncyStyle(scale: 0.97))
            }
        }
        .fullScreenCover(isPresented: $editing) {
            if let image {
                PhotoEditorView(image: image) { edited in withAnimation(.snappy) { self.image = edited } }
            }
        }
        .onChange(of: item) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    withAnimation(.snappy) { image = picked }
                }
            }
        }
    }
}

enum ImageTools {
    // Pictures are resized to at most 2048 px and saved as JPEG before upload.
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
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
