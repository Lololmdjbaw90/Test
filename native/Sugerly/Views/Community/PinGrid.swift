import SwiftUI

// The Community feed laid out like a pin board: two columns (three on iPad)
// of cards that keep their own height, so pictures show at their own shape
// and the columns interlock. Pictures are shown whole; posts with only words
// become colourful quote cards.
struct PinGrid: View {
    let posts: [Post]
    @Binding var path: [Route]
    @Binding var reporting: ReportSheet.Target?
    var columns: Int = 2
    // Called near the end, to load more.
    var onNearEnd: () -> Void = {}

    // Each post goes to whichever column is shortest so far (by a rough
    // guess of its height that never changes, so cards don't hop columns
    // while pictures load).
    private struct Placed: Identifiable {
        let index: Int
        let post: Post
        var id: String { post.id }
    }

    private var split: [[Placed]] {
        var cols = Array(repeating: [Placed](), count: max(1, columns))
        var heights = Array(repeating: 0.0, count: max(1, columns))
        for (i, post) in posts.enumerated() {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            cols[shortest].append(Placed(index: i, post: post))
            heights[shortest] += PinCard.guessHeight(post)
        }
        return cols
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(split.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: 10) {
                    ForEach(column) { placed in
                        PinCard(post: placed.post, path: $path, reporting: $reporting, index: placed.index)
                            .onAppear { if placed.index >= posts.count - 6 { onNearEnd() } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

struct PinCard: View {
    let post: Post
    @Binding var path: [Route]
    @Binding var reporting: ReportSheet.Target?
    var index = 0
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var heart = false
    @State private var confirmDelete = false
    @State private var sendSheet = false
    @State private var shown = false

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { LikeBook.shared.isLiked(post, me: me) }
    private var saved: Bool { model.me?.savedPosts.contains(post.id) ?? false }
    private var author: UserProfile? { model.person(post.authorEmail) }
    private var name: String { model.name(post.authorEmail, post.authorName) }

    // A stable number from the post, for its colour and a guess at its size.
    private static func seed(_ post: Post) -> Int {
        post.id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
    }

    private var candy: Candy { Candy.allCases[Self.seed(post) % Candy.allCases.count] }

    // Roughly how tall the card is, in widths.
    static func guessHeight(_ post: Post) -> Double {
        if post.imageURL.isEmpty {
            let words = Double((post.title + " " + post.text).count)
            return 0.7 + min(0.8, words / 140) + 0.25
        }
        return 1.1 + Double(seed(post) % 5) * 0.08 + (post.title.isEmpty && post.text.isEmpty ? 0.15 : 0.3)
    }

    private var snippet: String {
        let words = post.title.isEmpty ? post.text : post.title
        return words.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            picture
                .overlay { likeBurst }
                .overlay(alignment: .topTrailing) { saveButton }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture(count: 2) { doubleTapLike() }
                .onTapGesture { open() }
                .zoomSource("post-" + post.id)
            if !post.imageURL.isEmpty && !snippet.isEmpty {
                Text(snippet)
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .onTapGesture { open() }
            }
            footer.padding(.horizontal, 4)
        }
        .scaleEffect(shown || Motion.reduced ? 1 : 0.92)
        .opacity(shown || Motion.reduced ? 1 : 0)
        .onAppear {
            guard !shown else { return }
            withAnimation(Motion.reduced ? nil : Motion.playful.delay(Double(index % 6) * 0.04)) { shown = true }
        }
        .contextMenu { menu }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { try? await store.delete(post) } }
        } message: { Text("This can't be undone.") }
        .sheet(isPresented: $sendSheet) {
            SendToChatsSheet(title: "Send post") { targets, note in
                guard let me = model.me, await TextGuard.clear([note], kind: .message, model: model) else { return }
                try await ReelLinks.sendPost(post, to: targets, note: note, me: me)
            }
            .presentationDetents([.height(340)])
            .presentationCornerRadius(30)
        }
        .accessibilityElement(children: .contain)
    }

    // The picture at its own shape, or the words as a colourful quote card.
    @ViewBuilder
    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if post.imageURL.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.75))
                if !post.title.isEmpty {
                    Text(post.title).font(.display(19)).foregroundStyle(.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !post.text.isEmpty {
                    Text(post.text).font(.jakarta(post.title.isEmpty ? 16 : 13, post.title.isEmpty ? .bold : .medium))
                        .foregroundStyle(.white.opacity(post.title.isEmpty ? 1 : 0.92))
                        .lineLimit(post.title.isEmpty ? 7 : 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .background {
                shape.fill(candy.gradient)
                    .overlay {
                        GeometryReader { geo in
                            Circle().fill(.white.opacity(0.14)).frame(width: geo.size.width * 0.9)
                                .offset(x: geo.size.width * 0.45, y: geo.size.height * 0.45)
                        }
                        .clipShape(shape)
                    }
                    .overlay(shape.fill(LinearGradient(colors: [Palette.rim(0.3), .clear], startPoint: .top, endPoint: .center)).padding(1))
            }
            .budgetShadow(color: candy.color.softGlow(0.3), radius: 10, y: 5)
        } else {
            ArtImage(url: post.imageURL, tallest: 0.56, widest: 1.25)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Palette.border.opacity(0.6), lineWidth: 1))
                .budgetShadow(color: Palette.shadow, radius: 10, y: 5)
        }
    }

    private var saveButton: some View {
        Button { toggleSave() } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(saved ? Candy.lemon.color : Palette.text2)
                .symbolEffect(.bounce, value: saved)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.9), in: Circle())
                .budgetShadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
        .padding(8)
        .sensoryFeedback(.impact(weight: .light), trigger: saved)
        .accessibilityLabel(saved ? "Remove from saved" : "Save")
    }

    // A big heart that pops when you double-tap.
    private var likeBurst: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 62))
            .foregroundStyle(Candy.berry.gradient)
            .budgetShadow(color: .black.opacity(0.18), radius: 8)
            .scaleEffect(heart ? 1 : 0.3)
            .opacity(heart ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { path.append(.person(post.authorEmail)) } label: {
                HStack(spacing: 6) {
                    Avatar(url: author?.picture ?? post.authorPicture, name: name, size: 22)
                    Text(name).font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                }
            }
            .buttonStyle(SoftPressStyle())
            Spacer(minLength: 4)
            Button { store.toggleLike(post, me: model.me) } label: {
                HStack(spacing: 3) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .bold))
                        .symbolEffect(.bounce, value: liked)
                    if post.likeTotal > 0 {
                        Text("\(post.likeTotal)").font(.jakarta(12, .bold)).contentTransition(.numericText())
                    }
                }
                .foregroundStyle(liked ? Candy.berry.color : Palette.muted)
                .frame(minWidth: 30, minHeight: 28, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.8))
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
            .accessibilityLabel(liked ? "Unlike" : "Like")
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button { store.toggleLike(post, me: model.me) } label: { Label(liked ? "Unlike" : "Like", systemImage: liked ? "heart.slash" : "heart") }
        Button { toggleSave() } label: { Label(saved ? "Remove from saved" : "Save", systemImage: saved ? "bookmark.slash" : "bookmark") }
        Button { open() } label: { Label("Comments", systemImage: "bubble.right") }
        Button { sendSheet = true } label: { Label("Send to a chat", systemImage: "paperplane") }
        ShareLink(item: ReelLinks.post(post.id), subject: Text("Sugerly"), message: Text(snippet)) { Label("Share", systemImage: "square.and.arrow.up") }
        if !post.text.isEmpty {
            Button { UIPasteboard.general.string = post.text; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy text", systemImage: "doc.on.doc") }
        }
        if post.authorEmail != me {
            Button { reporting = ReportSheet.Target(id: post.id, type: "post", ownerEmail: post.authorEmail, preview: snippet, link: "/Community?post=\(post.id)") } label: { Label("Report", systemImage: "flag") }
        }
        if post.authorEmail == me || model.me?.isModerator == true {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func open() { path.append(.post(post)) }

    private func doubleTapLike() {
        if !liked { store.toggleLike(post, me: model.me) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heart = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
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
