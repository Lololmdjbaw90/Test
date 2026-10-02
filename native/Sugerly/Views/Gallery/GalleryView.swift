import SwiftUI
import UIKit
import PhotosUI

private enum ArtworkEvents {
    static let changed = Notification.Name("sugerly.artwork.changed")
    static func publish(_ artwork: Artwork) {
        NotificationCenter.default.post(name: changed, object: artwork)
    }
}

struct GalleryView: View {
    enum Sort: String, CaseIterable { case newest = "Newest", liked = "Most loved", featured = "Featured", saved = "Saved" }

    @Binding var path: [Route]
    var isRoot = false
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var artworks: [Artwork] = []
    @State private var sort: Sort = .newest
    @State private var medium = "all"
    @State private var query = ""
    @State private var loading = true
    @State private var hasMore = true
    @State private var loadingMore = false
    @State private var adding = false
    @State private var appeared = false
    @State private var pendingLikes = Set<String>()
    @State private var loadError: String?
    @State private var featuredIndex = 0

    init(path: Binding<[Route]>, isRoot: Bool = false, initialArtworks: [Artwork] = []) {
        _path = path
        self.isRoot = isRoot
        _artworks = State(initialValue: initialArtworks)
        _loading = State(initialValue: initialArtworks.isEmpty)
        _hasMore = State(initialValue: initialArtworks.isEmpty)
    }

    private var mediums: [String] {
        let found = Set(artworks.map { $0.medium.lowercased() }.filter { !$0.isEmpty })
        return ["all"] + found.sorted()
    }

    private var shown: [Artwork] {
        let blocked = Set(model.me?.blocked ?? [])
        var list = artworks.filter { !blocked.contains($0.authorEmail) }
        if medium != "all" { list = list.filter { $0.medium.lowercased() == medium } }
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.authorName.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .newest: return list
        case .liked: return list.sorted { $0.likeTotal > $1.likeTotal }
        case .featured: return list.filter(\.featured)
        case .saved:
            let saved = Set(model.me?.savedArtworks ?? [])
            return list.filter { saved.contains($0.id) }
        }
    }

    var body: some View {
        let content = ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if query.isEmpty && medium == "all" && sort == .newest && !featuredList.isEmpty {
                    featuredCarousel.stagger(appeared, 0)
                }
                searchRow.stagger(appeared, 1)
                browseTiles.stagger(appeared, 3)
                if query.isEmpty && topArtists.count > 1 { artistsRow.stagger(appeared, 4) }
                if !shown.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(wallTitle).font(.jakarta(18, .heavy)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("\(shown.count) pieces").font(.jakarta(12, .bold)).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 4)
                    .stagger(appeared, 5)
                }
                if let loadError {
                    VStack(spacing: 8) {
                        Text(loadError).font(.jakarta(13)).foregroundStyle(Palette.danger)
                        Button("Try again") { Task { await load() } }.buttonStyle(OutlineButtonStyle())
                    }
                }
                if loading && artworks.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) { SkeletonBlock(height: 240, radius: 18); SkeletonBlock(height: 180, radius: 18) }
                        VStack(spacing: 12) { SkeletonBlock(height: 180, radius: 18); SkeletonBlock(height: 240, radius: 18) }
                        if sizeClass == .regular {
                            VStack(spacing: 12) { SkeletonBlock(height: 210, radius: 18); SkeletonBlock(height: 200, radius: 18) }
                        }
                    }
                } else if shown.isEmpty {
                    if sort == .saved {
                        EmptyCard(icon: "bookmark.fill", title: "Nothing saved yet", text: "Tap the bookmark on a drawing you love and it'll wait for you here.")
                    } else {
                        EmptyCard(icon: "paintpalette.fill", title: "The fan art wall is empty", text: "No fan art here yet. Hang the first piece up!", actionTitle: "Share fan art") { adding = true }
                    }
                }
                // Staggered columns, like a pinboard: two on iPhone, three on iPad.
                let columns = sizeClass == .regular ? 3 : 2
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<columns, id: \.self) { c in
                        column(stride(from: c, to: shown.count, by: columns).map { shown[$0] }, offset: c)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .refreshable { await load() }
        .task { if artworks.isEmpty { await load() } }
        // Saved: bring in saved pieces that aren't among the loaded ones yet.
        .task(id: sort == .saved ? (model.me?.savedArtworks ?? []) : []) {
            guard sort == .saved, let ids = model.me?.savedArtworks else { return }
            let have = Set(artworks.map(\.id))
            let missing = ids.filter { !have.contains($0) }
            guard !missing.isEmpty, let docs = try? await FS.getMany("Artwork", Array(missing.suffix(100))) else { return }
            let fresh = docs.values.map { Artwork($0) }.filter { a in !artworks.contains { $0.id == a.id } }
            withAnimation(.snappy) { artworks.append(contentsOf: fresh) }
        }
        .dropRemoved($artworks)
        .onReceive(NotificationCenter.default.publisher(for: ArtworkEvents.changed)) { note in
            guard let artwork = note.object as? Artwork else { return }
            if let index = artworks.firstIndex(where: { $0.id == artwork.id }) { artworks[index] = artwork }
            else { artworks.insert(artwork, at: 0) }
        }
        .onAppear { appeared = true }
        .fullScreenCover(isPresented: $adding, onDismiss: { Task { await load() } }) { NewArtworkView() }

        if isRoot {
            content.sugarTopBar($path)
        } else {
            content.navigationTitle("Fan Art").navigationBarTitleDisplayMode(.inline)
        }
    }

    // No big title: just search and a round + to share, on one line.
    private var searchRow: some View {
        HStack(spacing: 10) {
            SearchField(text: $query, placeholder: "Search fan art or artists…")
            Button { adding = true } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.gradient, in: Circle())
                    .shadow(color: Theme.main.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(BouncyStyle(scale: 0.88)).accessibilityLabel("Share fan art")
        }
    }

    // The most-loved pieces (this week first), as a sliding showcase.
    private var featuredList: [Artwork] {
        let weekAgo = Dates.iso(Date().addingTimeInterval(-7 * 86_400))
        let recent = artworks.filter { $0.created > weekAgo }
        let pool = recent.count >= 3 ? recent : artworks
        return Array(pool.sorted { ($0.featured ? 1 : 0, $0.likeTotal) > ($1.featured ? 1 : 0, $1.likeTotal) }.prefix(5))
    }

    private var featuredCarousel: some View {
        let list = featuredList
        return VStack(spacing: 10) {
            TabView(selection: $featuredIndex) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, art in
                    Button { path.append(.artwork(art)) } label: {
                        GeometryReader { geo in
                            RemoteImage(url: art.imageURL)
                                .frame(width: geo.size.width, height: geo.size.height)
                                // A slow zoom while each piece is on show.
                                .scaleEffect(featuredIndex == i ? 1.08 : 1)
                                .animation(.easeOut(duration: 5), value: featuredIndex)
                                .clipped()
                        }
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.2), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                        }
                        .overlay(alignment: .topLeading) {
                            Label(i == 0 ? "FEATURED" : "#\(i + 1) MOST LOVED", systemImage: i == 0 ? "sparkles" : "heart.fill")
                                .font(.jakarta(10, .heavy)).tracking(1.1).foregroundStyle(.white)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(.black.opacity(0.3), in: Capsule())
                                .padding(14)
                        }
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(art.title).font(.display(28)).foregroundStyle(.white).lineLimit(2)
                                HStack(spacing: 8) {
                                    Avatar(url: model.person(art.authorEmail)?.picture ?? art.authorPicture, name: art.authorName, size: 26)
                                    Text("by \(model.name(art.authorEmail, art.authorName))").font(.jakarta(13, .bold)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Label("\(art.likeTotal)", systemImage: "heart.fill").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 10).frame(height: 30)
                                        .background(.white.opacity(0.22), in: Capsule())
                                }
                            }
                            .padding(18)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .padding(.horizontal, 2)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.98))
                    .accessibilityLabel("Open \(art.title)")
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 400)
            .shadow(color: Theme.main.opacity(0.22), radius: 18, y: 10)
            // Page dots: the current one stretches.
            HStack(spacing: 6) {
                ForEach(list.indices, id: \.self) { i in
                    Capsule().fill(i == featuredIndex ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border))
                        .frame(width: i == featuredIndex ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: featuredIndex)
        }
        // Moves on by itself every few seconds.
        .task(id: list.map(\.id)) {
            while !Task.isCancelled, list.count > 1 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.6)) { featuredIndex = (featuredIndex + 1) % list.count }
            }
        }
    }

    private var wallTitle: String {
        if !query.isEmpty { return "Results" }
        if medium != "all" { return medium.capitalized }
        switch sort {
        case .newest: return "Fresh on the wall"
        case .liked: return "Most loved"
        case .featured: return "Staff picks"
        case .saved: return "Your saved pieces"
        }
    }

    // Colourful tiles to browse the wall (and one per medium).
    private var browseTiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Sort.allCases, id: \.self) { s in
                    let on = sort == s && medium == "all"
                    let look: (String, [UInt32]) = {
                        switch s {
                        case .newest: return ("clock.fill", [0xFF9EC4, 0xE0508A])
                        case .liked: return ("heart.fill", [0xFFB38A, 0xF25F8C])
                        case .featured: return ("star.fill", [0xFFD166, 0xF0A020])
                        case .saved: return ("bookmark.fill", [0xB19CFF, 0x7C5CF0])
                        }
                    }()
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { sort = s; medium = "all" } } label: {
                        tile(s.rawValue, look.0, look.1, on: on)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                }
                ForEach(mediums.dropFirst(), id: \.self) { m in
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { medium = medium == m ? "all" : m } } label: {
                        tile(m.capitalized, "paintbrush.pointed.fill", [0x7CBEFF, 0x2F80E0], on: medium == m)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 2)
        }
    }

    private func tile(_ title: String, _ icon: String, _ colors: [UInt32], on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(title).font(.jakarta(13, .heavy)).foregroundStyle(.white).lineLimit(1)
                if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
            }
        }
        .padding(12)
        .frame(width: 118, height: 84, alignment: .leading)
        .background(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(on ? 0.95 : 0.25), lineWidth: on ? 2.5 : 1))
        .scaleEffect(on ? 1.04 : 1)
        .shadow(color: Color(hex: colors.last ?? 0).opacity(on ? 0.45 : 0.2), radius: on ? 10 : 5, y: 4)
        .opacity(on || (sort == .newest && medium == "all") ? 1 : 0.85)
    }

    // Fans with the most pieces, as round portraits.
    private var topArtists: [(email: String, count: Int)] {
        var count: [String: Int] = [:]
        for a in artworks { count[a.authorEmail, default: 0] += 1 }
        return count.sorted { $0.value > $1.value }.prefix(12).map { ($0.key, $0.value) }
    }

    private var artistsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artists on the wall").font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(topArtists, id: \.email) { entry in
                        let art = artworks.first { $0.authorEmail == entry.email }
                        Button { path.append(.person(entry.email)) } label: {
                            VStack(spacing: 6) {
                                Avatar(url: model.person(entry.email)?.picture ?? art?.authorPicture ?? "", name: model.name(entry.email, art?.authorName ?? ""), size: 58)
                                Text(model.name(entry.email, art?.authorName ?? "")).font(.jakarta(11, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                Text("\(entry.count) piece\(entry.count == 1 ? "" : "s")").font(.jakarta(10, .semibold)).foregroundStyle(Palette.muted)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.92))
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
    }

    private func column(_ list: [Artwork], offset: Int) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, art in
                GalleryCard(artwork: art, liked: LikeBook.shared.isLiked(art, me: model.me?.email ?? ""), onOpen: { path.append(.artwork(art)) }, onLike: { toggleLike(art) }, onProfile: { path.append(.person(art.authorEmail)) })
                    .scrollTransition(.animated(.spring(response: 0.5, dampingFraction: 0.8)).threshold(.visible(0.05))) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0)
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                            .offset(y: phase == .bottomTrailing ? 30 : 0)
                    }
                    .onAppear { if i >= list.count - 3 { Task { await loadMore() } } }
            }
        }
    }

    private func toggleLike(_ art: Artwork) {
        guard let me = model.me, !pendingLikes.contains(art.id), let i = artworks.firstIndex(where: { $0.id == art.id }) else { return }
        pendingLikes.insert(art.id)
        let before = artworks[i]
        let liking = !LikeBook.shared.isLiked(before, me: me.email)
        artworks[i].setLiked(liking, me: me.email)
        Task {
            defer { pendingLikes.remove(art.id) }
            do {
                try await LikeBook.shared.write(before, liking: liking, me: me.email, owner: art.authorEmail)
                if let updated = artworks.first(where: { $0.id == art.id }) { ArtworkEvents.publish(updated) }
                if liking { Notify.send(to: art.authorEmail, from: me, type: "like", message: "\(me.displayName) loved your fan art", link: "/Gallery?art=\(art.id)") }
            } catch {
                if let j = artworks.firstIndex(where: { $0.id == art.id }) { artworks[j].restoreLikes(from: before) }
                model.showToast("Could not save your like. Try again.", icon: "exclamationmark.circle")
            }
        }
    }

    // Pages of 60 (newest first); more load as you scroll down the wall.
    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("Artwork", orderBy: "created_date", limit: 60) else { loadError = "Could not load fan art. Pull down to retry."; return }
        loadError = nil
        let page = docs.map(Artwork.init)
        let cutoff = page.map(\.created).min() ?? ""
        let older = artworks.filter { !cutoff.isEmpty && $0.created < cutoff }
        if artworks.isEmpty { hasMore = docs.count >= 60 }
        artworks = page + older
        await LikeBook.shared.prime(page)
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, let oldest = artworks.map(\.created).filter({ !$0.isEmpty }).min() else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let docs = try? await FS.query("Artwork", [.before("created_date", oldest)], orderBy: "created_date", limit: 60) else { return }
        hasMore = docs.count >= 60
        let known = Set(artworks.map(\.id))
        let page = docs.map(Artwork.init).filter { !known.contains($0.id) }
        artworks += page
        await LikeBook.shared.prime(page)
    }
}

// One pinboard card: the whole drawing, a heart you can tap (or double-tap
// the picture), title and artist.
struct GalleryCard: View {
    let artwork: Artwork
    let liked: Bool
    var onOpen: () -> Void
    var onLike: () -> Void
    var onProfile: () -> Void
    @Environment(AppModel.self) private var model
    @State private var saving = false
    @State private var pop: UUID?
    private var saved: Bool { model.me?.savedArtworks.contains(artwork.id) == true }

    // A big heart pops over the picture (and little ones fly) when you love it.
    private func love() {
        if !liked {
            let id = UUID()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { pop = id }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                if pop == id { withAnimation(.easeOut(duration: 0.25)) { pop = nil } }
            }
        }
        onLike()
    }

    // A piece on the wall, Pinterest style: just the picture with a small
    // heart, and underneath a short title and the artist. No box around it.
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: onOpen) {
                ArtImage(url: artwork.imageURL, tallest: 0.62, widest: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if artwork.featured {
                            Image(systemName: "star.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: 0x3A2230))
                                .frame(width: 26, height: 26).background(Color(hex: 0xFFE8A3), in: Circle())
                                .padding(8)
                                .accessibilityLabel("Staff pick")
                        }
                    }
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
            .buttonStyle(BouncyStyle(scale: 0.97))
            .accessibilityLabel("Open \(artwork.title)")
            .contextMenu {
                Button { onOpen() } label: { Label("Open", systemImage: "arrow.up.left.and.arrow.down.right") }
                Button { save() } label: { Label(saved ? "Unsave" : "Save", systemImage: saved ? "bookmark.slash" : "bookmark") }
                Button { onProfile() } label: { Label("See the artist", systemImage: "person.crop.circle") }
            }
            .overlay {
                if let pop {
                    ZStack {
                        HeartPop(size: 14, spread: 46).id(pop)
                        Image(systemName: "heart.fill").font(.system(size: 54)).foregroundStyle(Theme.gradient)
                            .shadow(color: Theme.main.opacity(0.5), radius: 12)
                    }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: love) {
                    Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(liked ? Theme.main : Palette.text2)
                        .symbolEffect(.bounce, value: liked)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.94), in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .buttonStyle(BouncyStyle(scale: 0.85))
                .accessibilityLabel(liked ? "Unlike artwork" : "Like artwork")
                .padding(8)
            }
            Text(artwork.title).font(.jakarta(13, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                .padding(.horizontal, 2)
            HStack(spacing: 6) {
                Button(action: onProfile) {
                    HStack(spacing: 5) {
                        Avatar(url: model.person(artwork.authorEmail)?.picture ?? artwork.authorPicture, name: artwork.authorName, size: 18)
                        Text(model.name(artwork.authorEmail, artwork.authorName)).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if artwork.likeTotal > 0 {
                    Label("\(artwork.likeTotal)", systemImage: "heart.fill").font(.jakarta(10, .heavy)).foregroundStyle(Theme.main)
                        .labelStyle(.titleAndIcon)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 2)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
        .sensoryFeedback(.selection, trigger: saved)
    }

    private func save() {
        guard let me = model.me, !saving else { return }
        saving = true
        var next = me.savedArtworks
        if saved { next.removeAll { $0 == artwork.id } } else { next.append(artwork.id) }
        Task {
            defer { saving = false }
            do { try await model.updateMe(["saved_artworks": next]) }
            catch { model.showToast("Couldn't save this artwork. Try again.", icon: "exclamationmark.circle") }
        }
    }
}

struct ArtworkDetailView: View {
    @State var artwork: Artwork
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var zoom = false
    @State private var heart = false
    @State private var reporting: ReportSheet.Target?
    @State private var saving = false
    @State private var liking = false

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { LikeBook.shared.isLiked(artwork, me: me) }
    private var saved: Bool { model.me?.savedArtworks.contains(artwork.id) ?? false }

    var body: some View {
        CommentsScreen(collection: "Comment", field: "artwork_id", targetId: artwork.id, ownerEmail: artwork.authorEmail, link: "/Gallery?art=\(artwork.id)") {
            VStack(alignment: .leading, spacing: 14) {
                ArtImage(url: artwork.imageURL, tallest: 0.5, widest: 2.2)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: Palette.shadow, radius: 16, y: 8)
                    .overlay {
                        Image(systemName: "heart.fill").font(.system(size: 100)).foregroundStyle(Theme.gradient)
                            .shadow(color: Theme.pink.opacity(0.6), radius: 20)
                            .scaleEffect(heart ? 1 : 0.3).opacity(heart ? 1 : 0)
                    }
                    .onTapGesture(count: 2) { doubleTap() }
                    .onTapGesture { zoom = true }
                // Who drew it and what it is, on one soft card.
                VStack(alignment: .leading, spacing: 12) {
                    if !artwork.title.isEmpty {
                        Text(artwork.title).font(.display(30)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button { path.append(.person(artwork.authorEmail)) } label: {
                            HStack(spacing: 10) {
                                Avatar(url: model.person(artwork.authorEmail)?.picture ?? artwork.authorPicture, name: model.name(artwork.authorEmail, artwork.authorName), size: 42)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.name(artwork.authorEmail, artwork.authorName)).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                    Text(Dates.ago(artwork.created)).font(.jakarta(12)).foregroundStyle(Palette.muted)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 8)
                        FollowButton(email: artwork.authorEmail, compact: true)
                    }
                    if !artwork.text.isEmpty {
                        Text(artwork.text).font(.jakarta(15)).foregroundStyle(Palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !artwork.medium.isEmpty || !artwork.year.isEmpty {
                        HStack(spacing: 8) {
                            if !artwork.medium.isEmpty { tag(artwork.medium.replacingOccurrences(of: "_", with: " ").capitalized, "paintbrush.pointed.fill") }
                            if !artwork.year.isEmpty { tag(artwork.year, "calendar") }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sugarCard(radius: 26, padding: 16)
                HStack(spacing: 12) {
                    Button { toggleLike() } label: {
                        Label("\(artwork.likeTotal)", systemImage: liked ? "heart.fill" : "heart")
                            .symbolEffect(.bounce, value: liked)
                    }
                    .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
                    .sensoryFeedback(.impact(weight: .light), trigger: liked)
                    Button { toggleSave() } label: { Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark") }
                        .buttonStyle(OutlineButtonStyle())
                    ShareLink(item: ReelLinks.artwork(artwork.id), subject: Text(artwork.title), message: Text("\(artwork.title) by \(artwork.authorName) on Sugerly")) { Image(systemName: "paperplane.fill") }
                        .buttonStyle(OutlineButtonStyle())
                    Spacer()
                    Menu {
                        if artwork.authorEmail != me {
                            Button { reporting = ReportSheet.Target(id: artwork.id, type: "artwork", ownerEmail: artwork.authorEmail, preview: artwork.title, link: "/Gallery?art=\(artwork.id)") } label: { Label("Report", systemImage: "flag") }
                        }
                        if artwork.authorEmail == me || model.me?.isAdmin == true {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await FS.delete("Artwork", artwork.id)
                                        Removed.shared.add(artwork.id)
                                        model.showToast("Drawing deleted", icon: "trash.fill")
                                        if !path.isEmpty { path.removeLast() }
                                    } catch {
                                        model.showToast("Couldn't delete it. Try again.", error: true)
                                    }
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 40, height: 40) }
                }
            }
            .padding(4)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .fullScreenCover(isPresented: $zoom) { ZoomImage(url: artwork.imageURL) }
    }

    private func tag(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.soft, in: Capsule())
    }

    private func doubleTap() {
        if !liked { toggleLike() }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heart = true }
        Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { heart = false } }
    }

    private func toggleLike() {
        guard let meProfile = model.me, !liking else { return }
        liking = true
        let before = artwork
        let liking = !LikeBook.shared.isLiked(before, me: me)
        artwork.setLiked(liking, me: me)
        Task {
            defer { self.liking = false }
            do {
                try await LikeBook.shared.write(before, liking: liking, me: me, owner: before.authorEmail)
                ArtworkEvents.publish(artwork)
                if liking { Notify.send(to: artwork.authorEmail, from: meProfile, type: "like", message: "\(meProfile.displayName) liked your artwork \"\(artwork.title)\"", link: "/Gallery?art=\(artwork.id)") }
            } catch { artwork.restoreLikes(from: before); model.showToast("Could not save your like. Try again.", error: true) }
        }
    }

    private func toggleSave() {
        guard let meProfile = model.me, !saving else { return }
        saving = true
        var next = meProfile.savedArtworks
        let saving = !next.contains(artwork.id)
        if saving { next.append(artwork.id) } else { next.removeAll { $0 == artwork.id } }
        Task {
            defer { self.saving = false }
            do {
                try await model.updateMe(["saved_artworks": next])
                model.showToast(saving ? "Saved to your collection" : "Removed from saved", icon: "bookmark")
            } catch { model.showToast("Could not save your change. Try again.", icon: "exclamationmark.circle") }
        }
    }
}

// Pinch to zoom (then drag to look around), double-tap to zoom in or out,
// and drag down to close.
struct ZoomImage: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private var zoomed: Bool { scale > 1.01 }

    private var backdrop: Double {
        guard !zoomed else { return 1 }
        let pulled = Double(abs(offset.height)) / 400.0
        return 1.0 - Swift.min(0.6, pulled)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea().opacity(backdrop)
            RemoteImage(url: url, contentMode: .fit)
                .scaleEffect(zoomed ? scale : 1 - Swift.min(0.15, abs(offset.height) / 1600))
                .offset(offset)
                .gesture(magnify.simultaneously(with: drag))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        if zoomed { reset() } else { scale = 2.5; baseScale = 2.5 }
                    }
                }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.white.opacity(0.18), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Close")
            .padding(16)
            .opacity(backdrop)
        }
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .light), trigger: zoomed)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = Swift.min(6, Swift.max(1, baseScale * v.magnification)) }
            .onEnded { _ in
                baseScale = scale
                if scale < 1.05 { withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in
                if zoomed {
                    offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                } else {
                    offset = CGSize(width: 0, height: v.translation.height)
                }
            }
            .onEnded { v in
                if zoomed {
                    baseOffset = offset
                } else if abs(v.translation.height) > 140 || abs(v.predictedEndTranslation.height) > 420 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { offset = .zero; baseOffset = .zero }
                }
            }
    }

    private func reset() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }
}

struct NewArtworkView: View {
    static let mediums = ["painting", "digital", "drawing", "photography", "sculpture", "mixed_media", "other"]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var medium = "digital"
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?

    private var named: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ComposerScaffold(title: "New fan art", actionTitle: "Share", busy: busy, canPost: image != nil && named,
                         hint: image == nil ? "Add your drawing first" : "Give your drawing a title",
                         status: status, error: error,
                         onClose: { dismiss() }, onPost: { Task { await share() } }) {
            PhotoPickerCard(item: $item, image: $image)
            VStack(alignment: .leading, spacing: 8) {
                Text("Title").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                SugarField(placeholder: "Name your drawing", text: $title)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("About it").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                SugarField(placeholder: "Tell people about it (optional)", text: $text, lines: 3...6)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Medium").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.mediums, id: \.self) { m in
                            Chip(title: m.replacingOccurrences(of: "_", with: " ").capitalized, active: medium == m) { medium = m }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
        .onChange(of: image == nil) { _, _ in error = nil }
    }

    private func share() async {
        guard let me = model.me, let image else { return }
        error = nil
        guard await TextGuard.clear([title, text], kind: .caption, model: model) else { return }
        busy = true
        status = "Getting your drawing ready…"
        defer { busy = false; status = nil }
        let picture = image
        guard let data = await Task.detached(priority: .userInitiated, operation: { ImageTools.jpeg(picture) }).value else {
            TextGuard.forget(.caption, model: model)
            error = "Couldn't read that picture. Try another one."
            return
        }
        do {
            status = "Uploading…"
            let url = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            status = "Hanging it on the wall…"
            let now = FS.nowISO()
            let doc: Doc = [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines), "description": text.trimmingCharacters(in: .whitespacesAndNewlines),
                "image_url": url, "medium": medium,
                "year": "\(Calendar.current.component(.year, from: Date()))", "is_featured": false,
                "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
                "likes": [String](), "created_by": me.email, "created_date": now, "updated_date": now,
            ]
            let created = try await FS.create("Artwork", doc)
            ArtworkEvents.publish(Artwork(created))
            try? await model.addToMe(["xp": 25, "coins": 5])
            dismiss()
            model.showToast("Added to the fan art wall · +25 XP", icon: "paintpalette.fill")
        } catch {
            TextGuard.forget(.caption, model: model)
            self.error = PostProblem.message(error)
        }
    }
}
