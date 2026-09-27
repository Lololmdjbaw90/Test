import SwiftUI
import UIKit
import PhotosUI

struct GalleryView: View {
    enum Sort: String, CaseIterable { case newest = "Newest", liked = "Most liked", featured = "Featured", saved = "Saved" }

    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var artworks: [Artwork] = []
    @State private var sort: Sort = .newest
    @State private var loading = true
    @State private var adding = false

    private var shown: [Artwork] {
        let blocked = Set(model.me?.blocked ?? [])
        let list = artworks.filter { !blocked.contains($0.authorEmail) }
        switch sort {
        case .newest: return list
        case .liked: return list.sorted { $0.likes.count > $1.likes.count }
        case .featured: return list.filter(\.featured)
        case .saved:
            let saved = Set(model.me?.savedArtworks ?? [])
            return list.filter { saved.contains($0.id) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gallery").font(.display(40)).foregroundStyle(Palette.text)
                        Text("\(artworks.count) artworks").font(.jakarta(14)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { adding = true } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Sort.allCases, id: \.self) { s in
                            Chip(title: s.rawValue, icon: s == .newest ? "clock" : s == .liked ? "heart" : s == .featured ? "star" : "bookmark", active: sort == s) { withAnimation(.snappy) { sort = s } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if loading && artworks.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if shown.isEmpty {
                    EmptyCard(icon: "paintpalette.fill", title: sort == .saved ? "Nothing saved yet" : "No artworks here", text: sort == .saved ? "Tap the bookmark on any artwork to keep it." : "Add the first one!")
                }
                // Two staggered columns, like a pinboard.
                HStack(alignment: .top, spacing: 12) {
                    column(stride(from: 0, to: shown.count, by: 2).map { shown[$0] }, tall: true)
                    column(stride(from: 1, to: shown.count, by: 2).map { shown[$0] }, tall: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(isPresented: $adding) { NewArtworkView() }
    }

    private func column(_ list: [Artwork], tall: Bool) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(list) { art in
                Button { path.append(.artwork(art)) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        ArtImage(url: art.imageURL, tallest: 0.55, widest: 1.5)
                            .overlay(alignment: .topLeading) {
                                if art.featured {
                                    Label("Featured", systemImage: "star.fill").font(.jakarta(10, .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.gradient, in: Capsule()).padding(8)
                                }
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(art.title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                            HStack(spacing: 6) {
                                Avatar(url: model.person(art.authorEmail)?.picture ?? art.authorPicture, name: art.authorName, size: 20)
                                Text(art.authorName).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.pink)
                                Text("\(art.likes.count)").font(.jakarta(11, .bold)).foregroundStyle(Theme.pink)
                            }
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

    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("Artwork", orderBy: "created_date", limit: 200) else { return }
        artworks = docs.map(Artwork.init)
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
                    ShareLink(item: artwork.title) { Image(systemName: "paperplane.fill") }
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
        if next.contains(artwork.id) { next.removeAll { $0 == artwork.id } } else { next.append(artwork.id) }
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}
