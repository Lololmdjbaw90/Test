import SwiftUI
import UIKit
import PhotosUI

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
    @State private var adding = false
    @State private var appeared = false

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
        case .liked: return list.sorted { $0.likes.count > $1.likes.count }
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
        for a in artworks where a.created > weekAgo { score[a.authorEmail, default: 0] += a.likes.count + 1 }
        guard let best = score.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return (best.key, best.value, artworks.filter { $0.authorEmail == best.key }.prefix(3).map { $0 })
    }

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header.stagger(appeared, 0)
                SearchField(text: $query, placeholder: "Search art or artists…").stagger(appeared, 1)
                chips.stagger(appeared, 2)
                if query.isEmpty && medium == "all" && sort == .newest {
                    if let spot = spotlight { spotlightCard(spot).stagger(appeared, 3) }
                    let featured = artworks.filter(\.featured).prefix(8)
                    if !featured.isEmpty { featuredRow(Array(featured)).stagger(appeared, 4) }
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
                        EmptyCard(icon: "paintpalette.fill", title: "The wall is empty", text: "No drawings here yet. Hang the first one up!", actionTitle: "Upload a drawing") { adding = true }
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
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .fullScreenCover(isPresented: $adding) { NewArtworkView() }

        if isRoot {
            content.sugarTopBar($path)
        } else {
            content.navigationTitle("Gallery").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Gallery").font(.display(42)).foregroundStyle(Palette.text)
                    Image(systemName: "paintpalette.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.gradient)
                        .rotationEffect(.degrees(appeared ? -8 : 8))
                        .animation(.spring(response: 0.6, dampingFraction: 0.35).delay(0.3), value: appeared)
                }
                Text("\(artworks.count) artworks · \(Set(artworks.map(\.authorEmail)).count) artists")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { adding = true } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
        }
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
                                    Text(art.authorName).font(.jakarta(11, .semibold)).foregroundStyle(.white.opacity(0.85))
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
                GalleryCard(artwork: art, liked: art.likes.contains(model.me?.email ?? ""), onOpen: { path.append(.artwork(art)) }, onLike: { toggleLike(art) })
                    .stagger(appeared, 5 + i * 2 + offset)
            }
        }
    }

    private func toggleLike(_ art: Artwork) {
        guard let me = model.me, let i = artworks.firstIndex(where: { $0.id == art.id }) else { return }
        let before = artworks[i].likes
        let liking = !before.contains(me.email)
        artworks[i].likes = liking ? before + [me.email] : before.filter { $0 != me.email }
        let next = artworks[i].likes
        Task {
            do {
                try await FS.update("Artwork", art.id, ["likes": next, "updated_date": FS.nowISO()])
                if liking { Notify.send(to: art.authorEmail, from: me, type: "like", message: "\(me.displayName) loved your artwork", link: "/Gallery?art=\(art.id)") }
            } catch {
                if let j = artworks.firstIndex(where: { $0.id == art.id }) { artworks[j].likes = before }
            }
        }
    }

    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("Artwork", orderBy: "created_date", limit: 200) else { return }
        artworks = docs.map(Artwork.init)
    }
}

// One pinboard card: the whole drawing, a heart you can tap (or double-tap
// the picture), title and artist.
struct GalleryCard: View {
    let artwork: Artwork
    let liked: Bool
    var onOpen: () -> Void
    var onLike: () -> Void
    @Environment(AppModel.self) private var model
    @State private var burst = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtImage(url: artwork.imageURL, tallest: 0.55, widest: 1.5)
                .overlay {
                    Image(systemName: "heart.fill").font(.system(size: 56)).foregroundStyle(Theme.gradient)
                        .shadow(color: Theme.main.opacity(0.6), radius: 12)
                        .scaleEffect(burst ? 1 : 0.2).opacity(burst ? 1 : 0)
                }
                .overlay(alignment: .topLeading) {
                    if artwork.featured {
                        Label("Featured", systemImage: "star.fill").font(.jakarta(10, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.gradient, in: Capsule()).padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: onLike) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(liked ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white))
                            .symbolEffect(.bounce, value: liked)
                            .frame(width: 34, height: 34)
                            .background(liked ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.28)), in: Circle())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.8))
                    .sensoryFeedback(.impact(weight: .light), trigger: liked)
                    .padding(8)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if !liked { onLike() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { burst = true }
                    Task { try? await Task.sleep(for: .milliseconds(650)); withAnimation(.easeOut(duration: 0.25)) { burst = false } }
                }
                .onTapGesture(perform: onOpen)
            VStack(alignment: .leading, spacing: 5) {
                Text(artwork.title).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                HStack(spacing: 6) {
                    Avatar(url: model.person(artwork.authorEmail)?.picture ?? artwork.authorPicture, name: artwork.authorName, size: 20)
                    Text(artwork.authorName).font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(artwork.likes.count)").font(.jakarta(11, .heavy)).foregroundStyle(Theme.pink)
                        .contentTransition(.numericText())
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .sugarCard(radius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ArtworkDetailView: View {
    @State var artwork: Artwork
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var zoom = false
    @State private var heart = false
    @State private var reporting: ReportSheet.Target?

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { artwork.likes.contains(me) }
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
                        Avatar(url: model.person(artwork.authorEmail)?.picture ?? artwork.authorPicture, name: artwork.authorName, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(artwork.authorName).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
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
                        Label("\(artwork.likes.count)", systemImage: liked ? "heart.fill" : "heart")
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
                            Button(role: .destructive) { Task { try? await FS.delete("Artwork", artwork.id); if !path.isEmpty { path.removeLast() } } } label: { Label("Delete", systemImage: "trash") }
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
        guard let meProfile = model.me else { return }
        let before = artwork.likes
        let liking = !before.contains(me)
        artwork.likes = liking ? before + [me] : before.filter { $0 != me }
        Task {
            do {
                try await FS.update("Artwork", artwork.id, ["likes": artwork.likes, "updated_date": FS.nowISO()])
                if liking { Notify.send(to: artwork.authorEmail, from: meProfile, type: "like", message: "\(meProfile.displayName) liked your artwork \"\(artwork.title)\"", link: "/Gallery?art=\(artwork.id)") }
            } catch { artwork.likes = before }
        }
    }

    private func toggleSave() {
        guard let meProfile = model.me else { return }
        var next = meProfile.savedArtworks
        let saving = !next.contains(artwork.id)
        if saving { next.append(artwork.id) } else { next.removeAll { $0 == artwork.id } }
        model.showToast(saving ? "Saved to your collection" : "Removed from saved", icon: saving ? "bookmark.fill" : "bookmark")
        Task { try? await model.updateMe(["saved_artworks": next]) }
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
        ComposerScaffold(title: "New artwork", actionTitle: "Share", busy: busy, canPost: image != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty, onClose: { dismiss() }, onPost: { Task { await share() } }) {
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
            try await FS.create("Artwork", doc)
            try? await model.updateMe(["xp": me.xp + 25, "coins": me.coins + 5])
            dismiss()
            model.showToast("Added to the gallery · +25 XP", icon: "paintpalette.fill")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
