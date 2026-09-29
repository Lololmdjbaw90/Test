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

    // Whoever collected the most hearts this week.
    private var spotlight: (email: String, likes: Int, art: [Artwork])? {
        let weekAgo = Dates.iso(Date().addingTimeInterval(-7 * 86_400))
        var score: [String: Int] = [:]
        for a in artworks where a.created > weekAgo { score[a.authorEmail, default: 0] += a.likeTotal + 1 }
        guard let best = score.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return (best.key, best.value, artworks.filter { $0.authorEmail == best.key }.prefix(3).map { $0 })
    }

    var body: some View {
        let content = ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header.stagger(appeared, 0)
                SearchField(text: $query, placeholder: "Search fan art or artists…").stagger(appeared, 1)
                chips.stagger(appeared, 2)
                if query.isEmpty && medium == "all" && sort == .newest {
                    if let spot = spotlight { spotlightCard(spot).stagger(appeared, 3) }
                    let featured = artworks.filter(\.featured).prefix(8)
                    if !featured.isEmpty { featuredRow(Array(featured)).stagger(appeared, 4) }
                }
                if let loadError {
                    VStack(spacing: 8) {
                        Text(loadError).font(.jakarta(13)).foregroundStyle(Palette.danger)
                        Button("Try again") { Task { await load() } }.buttonStyle(OutlineButtonStyle())
                    }
                }
                if loading && artworks.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) { SkeletonBlock(height: 240, radius: 22); SkeletonBlock(height: 180, radius: 22) }
                        VStack(spacing: 12) { SkeletonBlock(height: 180, radius: 22); SkeletonBlock(height: 240, radius: 22) }
                    }
                } else if shown.isEmpty {
                    if sort == .saved {
                        EmptyCard(icon: "bookmark.fill", title: "Nothing saved yet", text: "Tap the bookmark on a drawing you love and it'll wait for you here.")
                    } else {
                        EmptyCard(icon: "paintpalette.fill", title: "The fan art wall is empty", text: "No fan art here yet. Hang the first piece up!", actionTitle: "Share fan art") { adding = true }
                    }
                }
                // Two staggered columns, like a pinboard.
                HStack(alignment: .top, spacing: 12) {
                    column(stride(from: 0, to: shown.count, by: 2).map { shown[$0] }, offset: 0)
                    column(stride(from: 1, to: shown.count, by: 2).map { shown[$0] }, offset: 1)
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

    // An editorial sketchbook header; the art is the hero of this page.
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THE COMMUNITY SKETCHBOOK").font(.jakarta(9, .heavy)).tracking(1.7).foregroundStyle(Theme.main)
                Text("Fan Art").font(.custom("LilitaOne", size: 48)).foregroundStyle(Palette.text)
                    .overlay(alignment: .bottomLeading) {
                        Capsule().fill(Theme.main.opacity(0.35)).frame(width: 128, height: 5).rotationEffect(.degrees(-3)).offset(y: 3)
                    }
                Text("Made by fans. Kept with love.").font(.jakarta(12)).foregroundStyle(Palette.muted).padding(.top, 8)
            }
            Spacer(minLength: 0)
            Button { adding = true } label: {
                VStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 23, weight: .semibold))
                    Text("Share art").font(.jakarta(11, .heavy))
                }
                .foregroundStyle(.white).frame(width: 82, height: 90)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 18))
                .rotationEffect(.degrees(4))
            }
            .buttonStyle(BouncyStyle(scale: 0.94)).accessibilityLabel("Share fan art")
        }.padding(.vertical, 12)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Sort.allCases, id: \.self) { s in
                        Chip(title: s.rawValue, icon: s == .newest ? "clock.fill" : s == .liked ? "heart.fill" : s == .featured ? "star.fill" : "bookmark.fill", active: sort == s) { withAnimation(.snappy) { sort = s } }
                    }
                }
                .padding(.vertical, 2)
            }
            if mediums.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mediums, id: \.self) { m in
                            Button { withAnimation(.snappy) { medium = m } } label: {
                                Text(m == "all" ? "All mediums" : m.capitalized)
                                    .font(.jakarta(12, .bold))
                                    .foregroundStyle(medium == m ? Theme.main : Palette.text2)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(medium == m ? Theme.soft : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(medium == m ? Theme.main.opacity(0.4) : Palette.border, lineWidth: 1))
                            }
                            .buttonStyle(BouncyStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func spotlightCard(_ spot: (email: String, likes: Int, art: [Artwork])) -> some View {
        let person = model.person(spot.email)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").foregroundStyle(Color(hex: 0xF0A020))
                Text("ARTIST OF THE WEEK").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.text2)
            }
            HStack(spacing: 12) {
                Button { path.append(.person(spot.email)) } label: {
                    Avatar(url: person?.picture ?? spot.art.first?.authorPicture ?? "", name: person?.displayName ?? spot.art.first?.authorName ?? "", size: 58, ring: true)
                }
                .buttonStyle(BouncyStyle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(person?.displayName ?? spot.art.first?.authorName ?? "").font(.display(24)).foregroundStyle(Palette.text).lineLimit(1)
                    Label("\(spot.likes) hearts this week", systemImage: "heart.fill").font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
                }
                Spacer()
                FollowButton(email: spot.email, compact: true)
            }
            HStack(spacing: 8) {
                ForEach(spot.art) { art in
                    Button { path.append(.artwork(art)) } label: {
                        RemoteImage(url: art.imageURL).frame(height: 96).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFE7A8).opacity(0.45), Theme.light.opacity(0.25), Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .shadow(color: Theme.main.opacity(0.14), radius: 18, y: 8)
        }
    }

    private func featuredRow(_ list: [Artwork]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "star.fill", title: "Featured")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(list) { art in
                        Button { path.append(.artwork(art)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: art.imageURL)
                                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(art.title).font(.display(18)).foregroundStyle(.white).lineLimit(1)
                                    Text(model.name(art.authorEmail, art.authorName)).font(.jakarta(11, .semibold)).foregroundStyle(.white.opacity(0.85))
                                }
                                .padding(12)
                            }
                            .frame(width: 180, height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 26, height: 26).background(Color(hex: 0xF0A020), in: Circle()).padding(10)
                            }
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

    private func column(_ list: [Artwork], offset: Int) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, art in
                GalleryCard(artwork: art, liked: LikeBook.shared.isLiked(art, me: model.me?.email ?? ""), onOpen: { path.append(.artwork(art)) }, onLike: { toggleLike(art) }, onProfile: { path.append(.person(art.authorEmail)) })
                    .stagger(appeared, min(6, 2 + i + offset))
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
    private var saved: Bool { model.me?.savedArtworks.contains(artwork.id) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                ArtImage(url: artwork.imageURL, tallest: 0.55, widest: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if artwork.featured {
                            Text("STAFF PICK").font(.jakarta(9, .heavy)).tracking(1)
                                .padding(7).foregroundStyle(Color(hex: 0x3A2230)).background(Color(hex: 0xFFE8A3)).rotationEffect(.degrees(-5)).padding(8)
                        }
                    }
            }.buttonStyle(BouncyStyle(scale: 0.98)).accessibilityLabel("Open \(artwork.title)")
            Button(action: onOpen) {
                Text(artwork.title).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }.buttonStyle(.plain)
            Button(action: onProfile) {
                HStack(spacing: 6) {
                    Avatar(url: model.person(artwork.authorEmail)?.picture ?? artwork.authorPicture, name: artwork.authorName, size: 23)
                    Text(model.name(artwork.authorEmail, artwork.authorName)).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
            HStack(spacing: 0) {
                Button(action: onLike) {
                    HStack(spacing: 5) {
                        Image(systemName: liked ? "heart.fill" : "heart").symbolEffect(.bounce, value: liked)
                        Text("\(artwork.likeTotal)").font(.jakarta(12, .bold)).contentTransition(.numericText())
                    }.foregroundStyle(liked ? Theme.main : Palette.text2).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(BouncyStyle()).accessibilityLabel(liked ? "Unlike artwork" : "Like artwork")
                Spacer(minLength: 0)
                Button { save() } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark").foregroundStyle(saved ? Theme.main : Palette.text2)
                        .frame(width: 44, height: 44).symbolEffect(.bounce, value: saved)
                }.buttonStyle(BouncyStyle()).disabled(saving).accessibilityLabel(saved ? "Unsave artwork" : "Save artwork")
            }
        }
        .padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
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
                Text(artwork.title).font(.display(32)).foregroundStyle(Palette.text)
                Button { path.append(.person(artwork.authorEmail)) } label: {
                    HStack(spacing: 10) {
                        Avatar(url: model.person(artwork.authorEmail)?.picture ?? artwork.authorPicture, name: model.name(artwork.authorEmail, artwork.authorName), size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name(artwork.authorEmail, artwork.authorName)).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                            Text(Dates.ago(artwork.created)).font(.jakarta(12)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                if !artwork.text.isEmpty { Text(artwork.text).font(.jakarta(15)).foregroundStyle(Palette.text2) }
                if !artwork.medium.isEmpty {
                    Text(artwork.medium.capitalized).font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.pink.opacity(0.1), in: Capsule())
                }
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

// Pinch to zoom, drag down to close.
struct ZoomImage: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    private var backdrop: Double {
        let pulled = Double(abs(offset.height)) / 400.0
        return 1.0 - Swift.min(0.6, pulled)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea().opacity(backdrop)
            RemoteImage(url: url, contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation(.spring) { if scale < 1.1 { scale = 1 } } })
                .simultaneousGesture(DragGesture().onChanged { v in if scale == 1 { offset = v.translation } }.onEnded { v in
                    if abs(v.translation.height) > 140 { dismiss() } else { withAnimation(.spring) { offset = .zero } }
                })
                .onTapGesture(count: 2) { withAnimation(.spring) { scale = scale > 1 ? 1 : 2.5 } }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.white.opacity(0.18), in: Circle())
            }
            .padding(16)
        }
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
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "New fan art", actionTitle: "Share", busy: busy, canPost: image != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty, onClose: { dismiss() }, onPost: { Task { await share() } }) {
            PhotoPickerCard(item: $item, image: $image)
            SugarField(placeholder: "Title", text: $title)
            SugarField(placeholder: "Tell people about it (optional)", text: $text, lines: 3...6)
            Text("Medium").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.mediums, id: \.self) { m in
                        Chip(title: m.replacingOccurrences(of: "_", with: " ").capitalized, active: medium == m) { medium = m }
                    }
                }
            }
            if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
        }
    }

    private func share() async {
        guard let me = model.me, let image, let data = ImageTools.jpeg(image) else { return }
        guard await TextGuard.clear([title, text], kind: .caption, model: model) else { return }
        busy = true
        defer { busy = false }
        do {
            let url = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            let now = FS.nowISO()
            let doc: Doc = [
                "title": title.trimmingCharacters(in: .whitespaces), "description": text, "image_url": url, "medium": medium,
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
            self.error = error.localizedDescription
        }
    }
}
