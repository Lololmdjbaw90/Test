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
    }

    @Binding var path: [Route]
    var compose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var feed: Feed = .forYou
    @State private var tag: String?
    @State private var reporting: ReportSheet.Target?
    @State private var searching = false

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

    // Three people to follow, shown between posts.
    private var suggestions: [UserProfile] {
        guard let me = model.me else { return [] }
        let following = Set(me.following)
        let blocked = Set(me.blocked)
        return model.people.values
            .filter { $0.email != me.email && !following.contains($0.email) && !blocked.contains($0.email) }
            .sorted { $0.isOnline && !$1.isOnline }
            .prefix(3).map { $0 }
    }

    // Laid out like a social timeline: tabs along the top (they stick while
    // you scroll), "What's happening?", then one post after another on a
    // plain page with thin lines between them, and a round pink button to
    // write a post.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    composeRow
                    if !trending.isEmpty || tag != nil { trendingRow }
                    feedContent
                } header: {
                    UnderlineTabs(items: Feed.allCases.map { ($0, $0.rawValue) }, selection: $feed)
                }
            }
            // Room so the last post isn't under the pink button.
            .padding(.bottom, 90)
            .sideRails(640)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: feed)
        }
        .appearFade()
        .background { Palette.surface.ignoresSafeArea() }
        .overlay(alignment: .bottomTrailing) { composeButton }
        .roundTitle("Community")
        .rootBar(create: false, search: { searching = true })
        .refreshable { await store.load() }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $searching) {
            SearchView { route in path.append(route) }.presentationCornerRadius(34)
        }
        .task { if store.posts.isEmpty { await store.load() } }
        // Saved: bring in saved posts that aren't among the loaded pages yet.
        .task(id: feed == .saved ? (model.me?.savedPosts ?? []) : []) {
            guard feed == .saved, let ids = model.me?.savedPosts else { return }
            let have = Set(store.posts.map(\.id))
            let missing = ids.filter { !have.contains($0) }
            guard !missing.isEmpty, let docs = try? await FS.getMany("CommunityPost", Array(missing.suffix(100))) else { return }
            let fresh = docs.values.map { Post($0) }.filter { p in !store.posts.contains { $0.id == p.id } }
            withAnimation(.snappy) { store.posts.append(contentsOf: fresh) }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        let list = visible
        if store.loading && store.posts.isEmpty {
            ForEach(0..<3, id: \.self) { i in SkeletonCard(media: i != 1).padding(14) }
        } else if list.isEmpty {
            EmptyCard(icon: feed == .saved ? "bookmark.fill" : "photo.on.rectangle.angled",
                      title: feed == .saved ? "No saved posts" : feed == .following ? "It's quiet over here" : "Nothing here yet",
                      text: feed == .saved ? "Tap the bookmark on a post and it'll wait for you here." : feed == .following ? "The people you follow haven't posted yet. Follow a few more artists?" : "No posts yet. Yours could be the first!",
                      actionTitle: feed == .saved ? nil : "Share a post", action: feed == .saved ? nil : compose)
                .padding(16)
        }
        let followAt = min(2, list.count - 1)
        ForEach(Array(list.enumerated()), id: \.element.id) { index, post in
            PostCard(post: post, path: $path, reporting: $reporting)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 18)), removal: .opacity))
                .onAppear { if index >= list.count - 5 { Task { await store.loadMore() } } }
            if index == followAt && feed == .forYou && !suggestions.isEmpty {
                whoToFollow
            }
        }
    }

    // "What's happening?" at the top: tap to write a post.
    private var composeRow: some View {
        Button(action: compose) {
            HStack(spacing: 12) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 42)
                Text("What's happening?").font(.jakarta(16)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Image(systemName: "photo").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.main)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1).allowsHitTesting(false) }
        .accessibilityLabel("Write a post")
    }

    // The round pink button in the corner for a new post.
    private var composeButton: some View {
        Button(action: compose) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.gradient, in: Circle())
                .shadow(color: Theme.main.opacity(0.4), radius: 12, y: 6)
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
        .padding(.trailing, 18)
        .padding(.bottom, 16)
        .accessibilityLabel("New post")
    }

    private var trendingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "number").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Theme.gradient, in: Circle())
                if let tag, !trending.contains(tag) { tagChip(tag) }
                ForEach(trending, id: \.self) { t in tagChip(t) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1).allowsHitTesting(false) }
    }

    private func tagChip(_ t: String) -> some View {
        let on = tag == t
        return Button { withAnimation(.snappy) { tag = on ? nil : t } } label: {
            HStack(spacing: 5) {
                Text("#\(t)").font(.jakarta(13, .bold))
                if on { Image(systemName: "xmark").font(.system(size: 10, weight: .black)) }
            }
            .foregroundStyle(on ? .white : Palette.text2)
            .padding(.horizontal, 14).frame(height: 34)
            .background {
                if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface2) }
            }
        }
        .buttonStyle(BouncyStyle())
    }

    // "Who to follow": three people with a Follow button, and Show more.
    private var whoToFollow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who to follow").font(.display(21)).foregroundStyle(Palette.text)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            ForEach(suggestions) { person in
                personRow(person)
            }
            Button { path.append(.people) } label: {
                Text("Show more").font(.jakarta(15, .semibold)).foregroundStyle(Theme.main)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Palette.surface2.opacity(0.5))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1).allowsHitTesting(false) }
    }

    private func personRow(_ person: UserProfile) -> some View {
        let reason = person.following.contains(model.me?.email ?? "") ? "Follows you" : person.isOnline ? "Active now" : "New on Sugerly"
        return HStack(spacing: 12) {
            Avatar(url: person.picture, name: person.displayName, size: 44, online: person.isOnline)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                Text(reason).font(.jakarta(13)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            FollowButton(email: person.email, compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { path.append(.person(person.email)) }
        .accessibilityElement(children: .contain)
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
    // In the feed (tap to open). Off on the post's own page, which shows
    // everything in full with the date and counts, like a social app.
    var openable = true

    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var heart = false
    @State private var confirmDelete = false
    @State private var sendSheet = false
    @State private var likeBurst: UUID?

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { LikeBook.shared.isLiked(post, me: me) }
    private var saved: Bool { model.me?.savedPosts.contains(post.id) ?? false }
    private var author: UserProfile? { model.person(post.authorEmail) }
    private var following: Bool { model.me?.following.contains(post.authorEmail) ?? false }
    private var comments: Int { store.commentCounts[post.id] ?? 0 }

    // Someone you follow who liked this post ("Luna liked").
    private var friendLiker: UserProfile? {
        guard let me = model.me else { return nil }
        let following = Set(me.following)
        return post.likes.first { following.contains($0) && $0 != post.authorEmail }.flatMap { model.person($0) }
    }

    var body: some View {
        Group {
            if openable { timelineRow } else { fullPost }
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

    // MARK: in the feed

    // Like a post on a social timeline: picture on the left; name, level and
    // time on one line; the words; the picture; then the buttons with their
    // counts spread across. Tap anywhere to open it.
    private var timelineRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let friend = friendLiker { likedByFriend(friend) }
            HStack(alignment: .top, spacing: 10) {
                authorPicture(42)
                VStack(alignment: .leading, spacing: 5) {
                    nameLine
                    words(lines: 8, size: 15)
                    if !post.imageURL.isEmpty {
                        media
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
                            .padding(.top, 4)
                    }
                    actionRow(size: 16)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1).allowsHitTesting(false) }
        // Posts glide up and fade in as they come into view.
        .scrollTransition(.animated(.spring(response: 0.5, dampingFraction: 0.86)).threshold(.visible(0.08))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .offset(y: phase == .bottomTrailing ? 24 : 0)
        }
    }

    // "♥ Luna liked" above the post, lined up with the words.
    private func likedByFriend(_ friend: UserProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.main)
                .frame(width: 42, alignment: .trailing)
            Text("\(friend.displayName) liked")
                .font(.jakarta(13, .bold)).foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
    }

    private func authorPicture(_ size: CGFloat) -> some View {
        Button { path.append(.person(post.authorEmail)) } label: {
            Avatar(url: author?.picture ?? post.authorPicture, name: author?.displayName ?? post.authorName, size: size,
                   online: author?.isOnline ?? false, nitro: author?.isNitro ?? false)
        }
        .buttonStyle(BouncyStyle())
        .accessibilityLabel(author?.displayName ?? post.authorName)
    }

    // Name, then "Lv.3 · 2h" in grey, and the ⋯ menu on the right.
    private var nameLine: some View {
        HStack(spacing: 4) {
            Button { path.append(.person(post.authorEmail)) } label: {
                NameText(name: author?.displayName ?? post.authorName, style: author?.nameStyle ?? "", size: 15, nitro: author?.isNitro ?? false)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            if author?.isNitro == true { NitroBadge(compact: true) }
            Text(levelAndTime)
                .font(.jakarta(14)).foregroundStyle(Palette.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            moreMenu
        }
        .frame(height: 22)
    }

    private var levelAndTime: String {
        let ago = Dates.ago(post.created)
        guard let author else { return "· \(ago)" }
        return "Lv.\(LevelInfo(xp: author.xp).level) · \(ago)"
    }

    @ViewBuilder
    private func words(lines: Int?, size: CGFloat) -> some View {
        if !post.title.isEmpty {
            Text(post.title).font(.jakarta(size + 1, .heavy)).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !post.text.isEmpty {
            Text(Hashtags.styled(post.text)).font(.jakarta(size)).foregroundStyle(Palette.text)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Reply, like, send and save / share, spread across like a social app.
    private func actionRow(size: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button { open() } label: { iconCount("bubble.left", openable ? comments : nil, on: false, size: size) }
                .accessibilityLabel("Reply")
                .accessibilityValue(comments > 0 ? "\(comments)" : "")
            Spacer(minLength: 8)
            Button {
                if !liked { burstLike() }
                store.toggleLike(post, me: model.me)
            } label: {
                iconCount(liked ? "heart.fill" : "heart", openable ? post.likeTotal : nil, on: liked, size: size)
                    .overlay(alignment: .leading) {
                        if let likeBurst { HeartPop().id(likeBurst).offset(x: 8) }
                    }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
            .accessibilityLabel(liked ? "Unlike" : "Like")
            .accessibilityValue(post.likeTotal > 0 ? "\(post.likeTotal)" : "")
            Spacer(minLength: 8)
            Button { sendSheet = true } label: { iconCount("paperplane", nil, on: false, size: size) }
                .accessibilityLabel("Send to a chat")
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                Button { toggleSave() } label: { iconCount(saved ? "bookmark.fill" : "bookmark", nil, on: saved, size: size) }
                    .sensoryFeedback(.impact(weight: .light), trigger: saved)
                    .accessibilityLabel(saved ? "Remove from saved" : "Save")
                ShareLink(item: ReelLinks.post(post.id), subject: Text("Sugerly"), message: Text(post.title.isEmpty ? post.text : post.title)) {
                    iconCount("square.and.arrow.up", nil, on: false, size: size)
                }
                .accessibilityLabel("Share")
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.8))
    }

    private func iconCount(_ icon: String, _ count: Int?, on: Bool, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: size, weight: .medium))
                .symbolEffect(.bounce, value: on)
            if let count, count > 0 {
                Text("\(count)").font(.jakarta(13, .medium)).contentTransition(.numericText())
            }
        }
        .foregroundStyle(on ? AnyShapeStyle(Theme.main) : AnyShapeStyle(Palette.muted))
        .frame(minWidth: 32, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: on its own page

    // The post in full: bigger words, the exact date, the counts, then the
    // buttons (comments follow underneath).
    private var fullPost: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let friend = friendLiker {
                Label("\(friend.displayName) liked", systemImage: "heart.fill")
                    .font(.jakarta(13, .bold)).foregroundStyle(Palette.muted)
                    .labelStyle(TintedIconLabel(tint: Theme.main))
            }
            fullHeader
            words(lines: nil, size: 17)
            if !post.imageURL.isEmpty {
                media
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
            }
            Text(fullDate).font(.jakarta(14)).foregroundStyle(Palette.muted)
            fullStats
            Divider()
            actionRow(size: 19)
                .padding(.horizontal, 4)
        }
        .sugarCard(radius: 24, padding: 16)
    }

    // Their picture, name and level, Follow, and the ⋯ menu.
    private var fullHeader: some View {
        HStack(spacing: 10) {
            authorPicture(46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    NameText(name: author?.displayName ?? post.authorName, style: author?.nameStyle ?? "", size: 16, nitro: author?.isNitro ?? false)
                        .lineLimit(1)
                    if author?.isNitro == true { NitroBadge(compact: true) }
                }
                if let author {
                    let info = LevelInfo(xp: author.xp)
                    Text("Lv.\(info.level) · \(info.title)").font(.jakarta(13, .semibold)).foregroundStyle(info.color)
                }
            }
            Spacer(minLength: 4)
            if post.authorEmail != me && !following {
                Button { follow() } label: {
                    Text("Follow").font(.jakarta(14, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(Theme.gradient, in: Capsule())
                }
                .buttonStyle(BouncyStyle())
            }
            moreMenu
        }
    }

    // "12 Likes  3 Comments" between thin lines.
    @ViewBuilder
    private var fullStats: some View {
        if comments > 0 || post.likeTotal > 0 {
            Divider()
            HStack(spacing: 18) {
                if post.likeTotal > 0 { stat(post.likeTotal, post.likeTotal == 1 ? "Like" : "Likes") }
                if comments > 0 { stat(comments, comments == 1 ? "Comment" : "Comments") }
            }
        }
    }

    private var fullDate: String {
        guard let date = Dates.parse(post.created) else { return Dates.ago(post.created) }
        return "\(date.formatted(date: .omitted, time: .shortened)) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        (Text("\(value) ").font(.jakarta(14, .heavy)).foregroundColor(Palette.text)
         + Text(label).font(.jakarta(14)).foregroundColor(Palette.muted))
    }

    // MARK: shared

    // Little hearts fly out of the button when you like.
    private func burstLike() {
        let id = UUID()
        likeBurst = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            if likeBurst == id { likeBurst = nil }
        }
    }

    private var moreMenu: some View {
        Menu {
            if !post.text.isEmpty { Button { UIPasteboard.general.string = post.text; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy text", systemImage: "doc.on.doc") } }
            Button { sendSheet = true } label: { Label("Send to a chat", systemImage: "paperplane") }
            if post.authorEmail != me && !following {
                Button { follow() } label: { Label("Follow \(author?.displayName ?? post.authorName)", systemImage: "person.badge.plus") }
            }
            if post.authorEmail != me {
                Button { reporting = ReportSheet.Target(id: post.id, type: "post", ownerEmail: post.authorEmail, preview: post.title.isEmpty ? post.text : post.title, link: "/Community?post=\(post.id)") } label: { Label("Report", systemImage: "flag") }
            }
            if post.authorEmail == me || model.me?.isAdmin == true {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.muted)
                .frame(width: 32, height: 30).contentShape(Rectangle())
        }
        .accessibilityLabel("More")
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
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { doubleTapLike() }
            .onTapGesture { open() }
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
                HStack(spacing: 8) {
                    Text("Comments").font(.display(24)).foregroundStyle(Palette.text)
                    if !comments.isEmpty {
                        Text("\(comments.count)\(hasOlder ? "+" : "")").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 9).frame(height: 24)
                            .background(Theme.gradient, in: Capsule())
                    }
                }
                .padding(.horizontal, 4)
                if comments.isEmpty {
                    Text("Be the first to say something nice.").font(.jakarta(14)).foregroundStyle(Palette.muted).padding(.horizontal, 4)
                }
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
            withAnimation(.snappy) {
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
        if liking { next.likes.append(me) } else { next.likes.removeAll { $0 == me } }
        comments[i] = next
        Task { try? await FS.change(collection, c.id, [liking ? .add("likes", me) : .remove("likes", me)], set: ["updated_date": FS.nowISO()]) }
    }

    private func report(_ c: Comment) {
        reporting = ReportSheet.Target(id: c.id, type: "comment", ownerEmail: c.authorEmail, preview: c.text, link: link, collection: collection, media: c.gifURL)
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
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
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
                "image_url": imageURL, "user_email": me.email, "user_display_name": me.displayName,
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

// Shared look for the "new post / artwork / track" screens: close on the
// left, the title, and the post button on the right. While it posts, a soft
// card says what's happening; a failed try shows why at the top.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding(18)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // What's missing, or why it didn't post, just under the top bar.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let note = error ?? shownHint {
                    Label(note, systemImage: error != nil ? "exclamationmark.circle.fill" : "hand.point.up.left.fill")
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(error != nil ? Palette.danger : Theme.main)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: 640, alignment: .leading)
                        .background((error != nil ? Palette.danger : Theme.main).opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sugarBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                        .font(.jakarta(16, .semibold))
                        .disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if canPost { onPost() } else { nudgeHint() }
                    } label: {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Text(actionTitle).font(.jakarta(15, .heavy))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.main)
                    .disabled(busy || (!canPost && hint == nil))
                    .opacity(canPost || busy ? 1 : 0.5)
                    .modifier(ShakeEffect(shakes: nudge))
                    .animation(.easeOut(duration: 0.2), value: canPost)
                }
            }
        }
        .tint(Theme.main)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: error)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shownHint)
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(Theme.main)
                        Text(status ?? "Posting…").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.2), value: status)
                    }
                    .padding(.horizontal, 30).padding(.vertical, 24)
                    .frame(minWidth: 200)
                    .sugarCard(radius: 28)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: busy)
        .interactiveDismissDisabled(busy)
        .onDisappear { hintTask?.cancel() }
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
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.pink.opacity(0.55) : Palette.border, lineWidth: focused ? 2 : 1))
        .shadow(color: focused ? Theme.pink.opacity(0.18) : .clear, radius: 10, y: 4)
        .animation(.snappy(duration: 0.2), value: focused)
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
                                ProgressView().controlSize(.large).tint(Theme.main)
                                Text("Opening your picture…").font(.jakarta(15, .bold)).foregroundStyle(Theme.pink)
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(Theme.gradient)
                                Text("Add a picture").font(.jakarta(15, .bold)).foregroundStyle(Theme.pink)
                                Text("From your photos").font(.jakarta(12)).foregroundStyle(Palette.muted)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .background(Theme.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.pink.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
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
                PhotoEditorView(image: image) { edited in withAnimation(.snappy) { self.image = edited } }
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
                Button { withAnimation(.snappy) { self.image = nil; item = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
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
                        Label("Change", systemImage: "photo.on.rectangle.angled").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(BouncyStyle())
                    Spacer(minLength: 0)
                    Button { editing = true } label: {
                        Label("Edit", systemImage: "wand.and.stars").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Theme.gradient, in: Capsule())
                            .shadow(color: Theme.main.opacity(0.4), radius: 8, y: 3)
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
            if item == newItem { withAnimation { failed = true } }
            return
        }
        let shrunk = await Task.detached(priority: .userInitiated) { ImagePipeline.downsample(data, maxPixel: 2560) }.value
        guard item == newItem else { return }
        if let shrunk {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { image = shrunk }
        } else {
            withAnimation { failed = true }
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
