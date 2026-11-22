import SwiftUI

// A #tag's own page: everything with it, reels, drawings, posts and songs
// together. Each part is one small indexed look-up (things whose tags
// contain this one, newest first, a page at a time) and "Show more" carries
// on from the last one, so the page is just as quick with a billion posts
// as with ten. "Top" orders what's loaded by how loved it is for its age;
// "Latest" is newest first.
struct HashtagView: View {
    let tag: String
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @Environment(PostsStore.self) private var store
    @State private var sort: Sort = .top
    @State private var reels: [Reel] = []
    @State private var art: [Artwork] = []
    @State private var posts: [Post] = []
    @State private var tracks: [Track] = []
    @State private var total: Int?
    @State private var loaded = false
    @State private var postCursor: String?
    @State private var morePosts = false
    @State private var loadingMore = false
    @State private var appeared = false

    enum Sort: String, CaseIterable, Identifiable {
        case top = "Top", latest = "Latest"
        var id: String { rawValue }
    }

    private static let pageSize = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header.stagger(appeared, 0)
                if !loaded {
                    VStack(spacing: 12) {
                        SkeletonBlock(height: 196, radius: 22)
                        SkeletonBlock(height: 110, radius: 22)
                        SkeletonBlock(height: 110, radius: 22)
                    }
                } else if reels.isEmpty && art.isEmpty && posts.isEmpty && tracks.isEmpty {
                    EmptyCard(icon: "number", title: "Nothing with #\(tag) yet",
                              text: "Be the first: add #\(tag) to a post, reel, drawing or song.")
                        .padding(.top, 12)
                } else {
                    if !reels.isEmpty { reelStrip.stagger(appeared, 1) }
                    if !art.isEmpty { artGrid.stagger(appeared, 2) }
                    if !posts.isEmpty { postList.stagger(appeared, 3) }
                    if !tracks.isEmpty { trackList.stagger(appeared, 4) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onAppear { appeared = true }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "number")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Theme.candy, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .budgetShadow(color: Theme.glow(0.3), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text("#\(tag)").font(.display(30)).foregroundStyle(Palette.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(summary).font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(Sort.allCases) { s in
                    Chip(title: s.rawValue, icon: s == .top ? "flame.fill" : "clock.fill", active: sort == s) {
                        withAnimation(Motion.pick(Motion.standard)) { sort = s }
                    }
                }
            }
        }
        .pastelCard(radius: 24, padding: 16)
    }

    private var summary: String {
        guard let total else { return "Posts, reels, drawings and songs" }
        return total == 1 ? "1 thing tagged" : "\(total.formatted()) things tagged"
    }

    // MARK: ordering

    // How loved something is for its age.
    private static func hot(_ points: Double, _ created: String) -> Double {
        let hours = max(0, Date().timeIntervalSince(Dates.parse(created) ?? Date()) / 3600)
        return (points + 1) / pow(hours + 2, 1.2)
    }

    private static func points(_ r: Reel) -> Double {
        hot(Double(r.likeTotal) + Double(r.commentCount ?? 0) * 2 + Double(r.views) * 0.05, r.created)
    }

    private var shownReels: [Reel] {
        guard sort == .top else { return reels }
        return reels.sorted { Self.points($0) > Self.points($1) }
    }

    private var shownArt: [Artwork] {
        guard sort == .top else { return art }
        return art.sorted { Self.hot(Double($0.likeTotal), $0.created) > Self.hot(Double($1.likeTotal), $1.created) }
    }

    private var shownPosts: [Post] {
        guard sort == .top else { return posts }
        return posts.sorted { Self.hot(Double($0.likeTotal), $0.created) > Self.hot(Double($1.likeTotal), $1.created) }
    }

    // MARK: parts

    private var reelStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "play.rectangle.fill", title: "Reels")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(shownReels) { reel in
                        Button { path.append(.reel(reel)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: reel.coverURL.isEmpty ? (reel.pictures.first ?? "") : reel.coverURL)
                                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                                Label("\(reel.views)", systemImage: "play.fill")
                                    .font(.jakarta(12, .semibold)).foregroundStyle(.white)
                                    .padding(10)
                            }
                            .frame(width: 118, height: 196)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.95))
                        .accessibilityLabel("Open reel")
                        .swipeFade()
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var artGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "paintpalette.fill", title: "Drawings")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(shownArt) { a in
                    Button { path.append(.artwork(a)) } label: {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay { RemoteImage(url: a.imageURL) }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                    .accessibilityLabel("Open \(a.title)")
                }
            }
        }
    }

    private var postList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "text.bubble.fill", title: "Posts")
            VStack(spacing: 10) {
                ForEach(shownPosts) { p in postRow(p) }
            }
            if morePosts {
                Button { Task { await loadMorePosts() } } label: {
                    if loadingMore { ProgressView() } else { Text("Show more posts") }
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
                .disabled(loadingMore)
            }
        }
    }

    private func postRow(_ p: Post) -> some View {
        Button { path.append(.post(p)) } label: {
            HStack(alignment: .top, spacing: 12) {
                Avatar(url: model.person(p.authorEmail)?.picture ?? p.authorPicture, name: model.name(p.authorEmail, p.authorName), size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.name(p.authorEmail, p.authorName)).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(Dates.ago(p.created)).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if !p.title.isEmpty {
                        Text(p.title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text).lineLimit(2)
                    }
                    if !p.text.isEmpty {
                        Text(p.text).font(.jakarta(14)).foregroundStyle(Palette.text2).lineLimit(3)
                    }
                    Label("\(p.likeTotal)", systemImage: "heart.fill")
                        .font(.jakarta(12, .semibold)).foregroundStyle(Theme.main)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if !p.imageURL.isEmpty {
                    RemoteImage(url: p.imageURL)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sugarCard(radius: 20)
        }
        .buttonStyle(BouncyStyle(scale: 0.98))
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "music.note", title: "Songs")
            VStack(spacing: 8) {
                ForEach(tracks) { t in
                    Button { player.play(t, in: tracks) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: t.coverURL)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                Text(t.artist).font(.jakarta(13)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: player.isCurrent(t) && player.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Theme.candy, in: Circle())
                        }
                        .padding(10)
                        .sugarCard(radius: 18)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.98))
                }
            }
        }
    }

    // MARK: loading

    private func load() async {
        let hidden = Set((model.me?.blocked ?? []) + (model.me?.ignored ?? []))
        async let r = Self.fetch("Reel", tag, limit: 24)
        async let a = Self.fetch("Artwork", tag, limit: 24)
        async let p = Self.fetch("CommunityPost", tag, limit: Self.pageSize)
        async let t = Self.fetch("MusicReview", tag, limit: 12)
        let (reelDocs, artDocs, postDocs, trackDocs) = await (r, a, p, t)
        // Older posts whose tags the server hasn't saved yet: the ones this
        // phone has loaded already count too.
        let found = postDocs.map(Post.init)
        let ids = Set(found.map(\.id))
        let loadedHere = store.posts.filter { $0.tags.contains(tag) && !ids.contains($0.id) }
        let allPosts = (found + loadedHere).sorted { $0.created > $1.created }
        withAnimation(Motion.pick(.smooth(duration: 0.35))) {
            reels = reelDocs.map(Reel.init).filter { !hidden.contains($0.authorEmail) }
            art = artDocs.map(Artwork.init).filter { !hidden.contains($0.authorEmail) }
            posts = allPosts.filter { !hidden.contains($0.authorEmail) }
            tracks = trackDocs.map(Track.init).filter { !hidden.contains($0.authorEmail) }
            postCursor = postDocs.map { $0.str("created_date") }.filter { !$0.isEmpty }.min()
            morePosts = postDocs.count >= Self.pageSize
            loaded = true
        }
        // Opening a tag counts as a little interest in it (your For You).
        await ReelBrain.shared.visited(tag: tag)
        let counted = await Self.count(tag)
        withAnimation(Motion.pick(Motion.standard)) { total = counted }
    }

    private func loadMorePosts() async {
        guard let cursor = postCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let hidden = Set((model.me?.blocked ?? []) + (model.me?.ignored ?? []))
        let docs = await Self.fetch("CommunityPost", tag, before: cursor, limit: Self.pageSize)
        let known = Set(posts.map(\.id))
        let next = docs.map(Post.init).filter { !known.contains($0.id) && !hidden.contains($0.authorEmail) }
        withAnimation(Motion.pick(Motion.standard)) { posts += next }
        postCursor = docs.map { $0.str("created_date") }.filter { !$0.isEmpty }.min() ?? cursor
        morePosts = docs.count >= Self.pageSize
    }

    private static func fetch(_ collection: String, _ tag: String, before: String? = nil, limit: Int) async -> [Doc] {
        var filters: [FS.Filter] = [.contains("tags", tag)]
        if let before { filters.append(.before("created_date", before)) }
        return (try? await FS.query(collection, filters, orderBy: "created_date", limit: limit)) ?? []
    }

    // How many things have it, counted by the database itself (nothing is
    // downloaded, so it costs the same for ten or ten million).
    private static func count(_ tag: String) async -> Int? {
        var sum = 0
        for collection in ["Reel", "Artwork", "CommunityPost", "MusicReview"] {
            guard let n = try? await FS.count(collection, [.contains("tags", tag)]) else { return nil }
            sum += n
        }
        return sum
    }
}
