import SwiftUI
import UIKit
import PhotosUI

enum Route: Hashable {
    case post(Post)
    case person(String)
    case chat(Conversation)
}

// Posts shared by the whole app (feed, post page, profiles) so a like or a
// save shows everywhere at once.
@MainActor
@Observable
final class PostsStore {
    var posts: [Post] = []
    var loading = false
    var error: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let docs = try await FS.query("CommunityPost", orderBy: "created_date", limit: 150)
            posts = docs.map(Post.init)
            error = nil
        } catch {
            if posts.isEmpty { self.error = error.localizedDescription }
        }
    }

    func replace(_ post: Post) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = post }
    }

    func toggleLike(_ post: Post, me: String) {
        var next = post
        if next.likes.contains(me) { next.likes.removeAll { $0 == me } } else { next.likes.append(me) }
        replace(next)
        Task {
            do {
                try await FS.update("CommunityPost", post.id, ["likes": next.likes, "updated_date": FS.nowISO()])
            } catch {
                self.replace(post)
            }
        }
    }

    func delete(_ post: Post) async throws {
        try await FS.delete("CommunityPost", post.id)
        posts.removeAll { $0.id == post.id }
    }
}

struct CommunityView: View {
    enum Feed: String, CaseIterable { case latest = "Latest", following = "Following", saved = "Saved" }

    @Environment(AppModel.self) private var model
    @State private var store = PostsStore()
    @State private var feed: Feed = .latest
    @State private var path: [Route] = []
    @State private var composing = false
    @State private var reporting: ReportSheet.Target?

    private var visible: [Post] {
        guard let me = model.me else { return [] }
        let blocked = Set(me.blocked)
        let all = store.posts.filter { !blocked.contains($0.authorEmail) }
        switch feed {
        case .latest: return all
        case .following:
            let following = Set(me.following)
            return all.filter { following.contains($0.authorEmail) || $0.authorEmail == me.email }
        case .saved:
            let saved = Set(me.savedPosts)
            return all.filter { saved.contains($0.id) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    Picker("Feed", selection: $feed.animation(.snappy)) {
                        ForEach(Feed.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)

                    ForEach(visible) { post in
                        PostCard(post: post, store: store, path: $path, reporting: $reporting)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .overlay {
                if store.loading && store.posts.isEmpty {
                    ProgressView()
                } else if let error = store.error, store.posts.isEmpty {
                    ContentUnavailableView("Couldn't load posts", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if visible.isEmpty && !store.loading {
                    ContentUnavailableView(feed == .saved ? "No saved posts" : feed == .following ? "Nothing from people you follow" : "No posts yet",
                                           systemImage: feed == .saved ? "bookmark" : "sparkles",
                                           description: Text(feed == .saved ? "Tap the bookmark on any post to keep it here." : "Be the first to share something!"))
                }
            }
            .refreshable { await store.load() }
            .navigationTitle("Community")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New post")
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route, store: store, path: $path)
            }
            .sheet(isPresented: $composing) {
                NewPostView { await store.load() }
            }
            .sheet(item: $reporting) { target in ReportSheet(target: target) }
            .task { if store.posts.isEmpty { await store.load() } }
        }
    }
}

// Where a tap leads, used by every tab's navigation stack.
struct RouteView: View {
    let route: Route
    var store: PostsStore
    @Binding var path: [Route]

    var body: some View {
        switch route {
        case .post(let post): PostDetailView(postId: post.id, initial: post, store: store, path: $path)
        case .person(let email): PersonView(email: email, store: store, path: $path)
        case .chat(let conversation): ChatView(conversation: conversation)
        }
    }
}

struct PostCard: View {
    let post: Post
    var store: PostsStore
    @Binding var path: [Route]
    @Binding var reporting: ReportSheet.Target?
    var openable = true

    @Environment(AppModel.self) private var model
    @State private var heart = false
    @State private var confirmDelete = false

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { post.likes.contains(me) }
    private var saved: Bool { model.me?.savedPosts.contains(post.id) ?? false }
    private var author: UserProfile? { model.person(post.authorEmail) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { path.append(.person(post.authorEmail)) } label: {
                    HStack(spacing: 10) {
                        Avatar(url: author?.picture ?? post.authorPicture, name: author?.displayName ?? post.authorName, size: 40, online: author?.isOnline ?? false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(author?.displayName ?? post.authorName).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                            Text(Dates.ago(post.created)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    if !post.text.isEmpty { Button { UIPasteboard.general.string = post.text } label: { Label("Copy text", systemImage: "doc.on.doc") } }
                    if post.authorEmail != me {
                        Button { reporting = ReportSheet.Target(id: post.id, type: "post", ownerEmail: post.authorEmail, preview: post.title.isEmpty ? post.text : post.title, link: "/Community?post=\(post.id)") } label: { Label("Report", systemImage: "flag") }
                    }
                    if post.authorEmail == me || model.me?.isAdmin == true {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
            }

            if !post.title.isEmpty || !post.text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !post.title.isEmpty { Text(post.title).font(.headline) }
                    if !post.text.isEmpty { Text(post.text).font(.body).lineLimit(openable ? 6 : nil) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if openable { path.append(.post(post)) } }
            }

            if !post.imageURL.isEmpty {
                RemoteImage(url: post.imageURL, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 90))
                            .foregroundStyle(.white)
                            .shadow(radius: 12)
                            .scaleEffect(heart ? 1 : 0.4)
                            .opacity(heart ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { doubleTapLike() }
                    .onTapGesture { if openable { path.append(.post(post)) } }
            }

            HStack(spacing: 18) {
                Button { store.toggleLike(post, me: me) } label: {
                    Label("\(post.likes.count)", systemImage: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? Theme.pink : .primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: liked)
                Button { if openable { path.append(.post(post)) } } label: {
                    Label("Comments", systemImage: "bubble.right")
                        .labelStyle(.iconOnly)
                }
                ShareLink(item: post.title.isEmpty ? post.text : post.title, subject: Text("Sugerly")) {
                    Image(systemName: "square.and.arrow.up")
                }
                Spacer()
                Button { toggleSave() } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(saved ? Theme.pink : .primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: saved)
                .accessibilityLabel(saved ? "Remove from saved" : "Save")
            }
            .font(.title3)
            .buttonStyle(.plain)
            .labelStyle(TightLabel())
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await store.delete(post)
                    if !openable, !path.isEmpty { path.removeLast() }
                }
            }
        } message: { Text("This can't be undone.") }
    }

    private func doubleTapLike() {
        if !liked { store.toggleLike(post, me: me) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { heart = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { heart = false }
        }
    }

    private func toggleSave() {
        guard let me = model.me else { return }
        var next = me.savedPosts
        if next.contains(post.id) { next.removeAll { $0 == post.id } } else { next.append(post.id) }
        Task { try? await model.updateMe(["saved_posts": next]) }
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title.font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

// MARK: - A post with its comments

struct PostDetailView: View {
    let postId: String
    let initial: Post
    var store: PostsStore
    @Binding var path: [Route]

    @Environment(AppModel.self) private var model
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var replyTo: Comment?
    @State private var sending = false
    @State private var reporting: ReportSheet.Target?
    @FocusState private var typing: Bool

    private var post: Post { store.posts.first { $0.id == postId } ?? initial }
    struct Thread: Identifiable {
        let parent: Comment
        let replies: [Comment]
        var id: String { parent.id }
    }
    private var threads: [Thread] {
        let blocked = Set(model.me?.blocked ?? [])
        let visible = comments.filter { !blocked.contains($0.authorEmail) }
        let top = visible.filter { $0.parentId.isEmpty }
        return top.map { parent in Thread(parent: parent, replies: visible.filter { $0.parentId == parent.id }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PostCard(post: post, store: store, path: $path, reporting: $reporting, openable: false)

                Text(comments.isEmpty ? "No comments yet" : "\(comments.count) comments")
                    .font(.headline)
                    .padding(.horizontal, 4)

                ForEach(threads) { thread in
                    VStack(alignment: .leading, spacing: 12) {
                        CommentRow(comment: thread.parent, onReply: { reply(to: thread.parent) }, onReport: { report(thread.parent) }, onDelete: { delete(thread.parent) }, onLike: { like(thread.parent) })
                        ForEach(thread.replies) { r in
                            CommentRow(comment: r, onReply: { reply(to: thread.parent) }, onReport: { report(r) }, onDelete: { delete(r) }, onLike: { like(r) })
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .task { await loadComments() }
        .refreshable { await loadComments() }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let replyTo {
                HStack {
                    Text("Replying to \(replyTo.authorName)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { withAnimation { self.replyTo = nil } } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 34)
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).symbolRenderingMode(.hierarchical)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func loadComments() async {
        guard let docs = try? await FS.query("CommunityComment", [.equals("post_id", postId)]) else { return }
        withAnimation(.snappy) { comments = docs.map(Comment.init).sorted { $0.created < $1.created } }
    }

    private func reply(to comment: Comment) {
        withAnimation { replyTo = comment }
        typing = true
    }

    private func send() async {
        guard let me = model.me else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        let now = FS.nowISO()
        let data: Doc = [
            "post_id": postId, "content": text, "gif_url": "",
            "parent_id": replyTo.map { $0.parentId.isEmpty ? $0.id : $0.parentId } ?? "",
            "reply_to_email": replyTo?.authorEmail ?? "", "reply_to_name": replyTo?.authorName ?? "",
            "user_email": me.email, "user_display_name": me.displayName, "user_full_name": me.displayName,
            "user_profile_picture": me.picture, "likes": [String](),
            "created_by": me.email, "created_date": now, "updated_date": now,
        ]
        do {
            let created = try await FS.create("CommunityComment", data)
            withAnimation(.snappy) {
                comments.append(Comment(created))
                draft = ""
                replyTo = nil
            }
        } catch {}
    }

    private func like(_ c: Comment) {
        guard let me = model.me?.email, let i = comments.firstIndex(where: { $0.id == c.id }) else { return }
        var next = c
        if next.likes.contains(me) { next.likes.removeAll { $0 == me } } else { next.likes.append(me) }
        comments[i] = next
        Task { try? await FS.update("CommunityComment", c.id, ["likes": next.likes, "updated_date": FS.nowISO()]) }
    }

    private func report(_ c: Comment) {
        reporting = ReportSheet.Target(id: c.id, type: "comment", ownerEmail: c.authorEmail, preview: c.text, link: "/Community?post=\(postId)")
    }

    private func delete(_ c: Comment) {
        withAnimation { comments.removeAll { $0.id == c.id || $0.parentId == c.id } }
        Task { try? await FS.delete("CommunityComment", c.id) }
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
            Avatar(url: model.person(comment.authorEmail)?.picture ?? comment.authorPicture, name: comment.authorName, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName).font(.subheadline.weight(.bold))
                    Text(Dates.ago(comment.created)).font(.caption).foregroundStyle(.secondary)
                }
                if !comment.text.isEmpty { Text(comment.text).font(.subheadline) }
                if !comment.gifURL.isEmpty {
                    RemoteImage(url: comment.gifURL, contentMode: .fit).frame(maxWidth: 200, maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button("Reply", action: onReply).font(.caption.weight(.semibold)).foregroundStyle(.secondary).buttonStyle(.plain)
            }
            Spacer()
            Button(action: onLike) {
                VStack(spacing: 2) {
                    Image(systemName: liked ? "heart.fill" : "heart").foregroundStyle(liked ? Theme.pink : .secondary)
                    if !comment.likes.isEmpty { Text("\(comment.likes.count)").font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(width: 32)
            }
            .buttonStyle(.plain)
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
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 40)
                        Text(model.me?.displayName ?? "").font(.headline)
                    }
                    TextField("Title (optional)", text: $title).font(.title3.weight(.semibold))
                    TextField("What's on your mind?", text: $text, axis: .vertical).lineLimit(4...12)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { withAnimation { self.image = nil; item = nil } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .padding(8)
                            }
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    PhotosPicker(selection: $item, matching: .images) {
                        Label(image == nil ? "Add a picture" : "Change picture", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await post() } } label: { if posting { ProgressView() } else { Text("Post").bold() } }
                        .disabled(posting || (image == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
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
        .interactiveDismissDisabled(posting)
    }

    private func post() async {
        guard let me = model.me else { return }
        posting = true
        defer { posting = false }
        do {
            var imageURL = ""
            if let image, let data = ImageTools.jpeg(image) {
                imageURL = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
            let now = FS.nowISO()
            let data: Doc = [
                "title": title.trimmingCharacters(in: .whitespaces), "description": text.trimmingCharacters(in: .whitespacesAndNewlines),
                "image_url": imageURL, "user_email": me.email, "user_display_name": me.displayName,
                "user_profile_picture": me.picture, "likes": [String](), "created_by": me.email,
                "created_date": now, "updated_date": now,
            ]
            try await FS.create("CommunityPost", data)
            try? await model.updateMe(["xp": me.xp + 20, "coins": me.coins + 5])
            await onPosted()
            dismiss()
        } catch {
            self.error = error.localizedDescription
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
