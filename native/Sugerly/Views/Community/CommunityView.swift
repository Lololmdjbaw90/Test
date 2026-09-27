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
    var loading = false
    var error: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            async let comments = try? FS.query("CommunityComment", orderBy: "created_date", limit: 400)
            let docs = try await FS.query("CommunityPost", orderBy: "created_date", limit: 150)
            posts = docs.map(Post.init)
            var counts: [String: Int] = [:]
            for c in (await comments ?? []) { counts[c.str("post_id"), default: 0] += 1 }
            commentCounts = counts
            error = nil
        } catch {
            if posts.isEmpty { self.error = error.localizedDescription }
        }
    }

    func replace(_ post: Post) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = post }
    }

    func toggleLike(_ post: Post, me: UserProfile?) {
        guard let me else { return }
        var next = post
        let liking = !next.likes.contains(me.email)
        if liking { next.likes.append(me.email) } else { next.likes.removeAll { $0 == me.email } }
        replace(next)
        Task {
            do {
                try await FS.update("CommunityPost", post.id, ["likes": next.likes, "updated_date": FS.nowISO()])
                if liking { Notify.send(to: post.authorEmail, from: me, type: "like", message: "\(me.displayName) liked your post\(post.title.isEmpty ? "" : " \"\(post.title)\"")", link: "/Community?post=\(post.id)") }
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

    private var visible: [Post] {
        guard let me = model.me else { return [] }
        let blocked = Set(me.blocked)
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
            func points(_ p: Post) -> Int { p.likes.count + (counts[p.id] ?? 0) * 2 }
            return all.filter { $0.created > weekAgo }.sorted { points($0) > points($1) }
        case .saved:
            let saved = Set(me.savedPosts)
            return all.filter { saved.contains($0.id) }
        }
    }

    // Recent, liked and from people you follow floats up.
    private func score(_ p: Post, _ following: Set<String>) -> Double {
        let hours = max(0, Date().timeIntervalSince(Dates.parse(p.created) ?? Date()) / 3600)
        let engagement = Double(p.likes.count) + Double(store.commentCounts[p.id] ?? 0) * 2 + 1
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
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Community").font(.display(38)).foregroundStyle(Palette.text).padding(.horizontal, 4)
                stories
                composerCard
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(.forYou, "sparkles"); chip(.following, "person.crop.circle.badge.checkmark"); chip(.latest, "clock"); chip(.top, "flame"); chip(.saved, "bookmark")
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                if !trending.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Label("Trending", systemImage: "chart.line.uptrend.xyaxis").font(.jakarta(13, .bold)).foregroundStyle(Theme.pink)
                            ForEach(trending, id: \.self) { t in
                                Chip(title: "#\(t)", active: tag == t) { withAnimation(.snappy) { tag = tag == t ? nil : t } }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                if store.loading && store.posts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if visible.isEmpty {
                    EmptyCard(icon: feed == .saved ? "bookmark.fill" : "sparkles",
                              title: feed == .saved ? "No saved posts" : feed == .following ? "Nothing from people you follow" : "Nothing here yet",
                              text: feed == .saved ? "Tap the bookmark on any post to keep it here." : "Be the first to share something!")
                }

                ForEach(Array(visible.enumerated()), id: \.element.id) { index, post in
                    PostCard(post: post, path: $path, reporting: $reporting)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    if index == 1 && !suggestions.isEmpty && feed == .forYou { suggested }
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
        .task { if store.posts.isEmpty { await store.load() } }
    }

    private func chip(_ f: Feed, _ icon: String) -> some View {
        Chip(title: f.rawValue, icon: icon, active: feed == f) { feed = f }
    }

    private var stories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button(action: compose) {
                    VStack(spacing: 6) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 64)
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
                            Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 60, online: person?.isOnline ?? false)
                                .padding(3)
                                .overlay(Circle().strokeBorder(AngularGradient(colors: [Theme.light, Theme.main, Color(hex: 0xF0A020), Theme.light], center: .center), lineWidth: 2.5))
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested for you").font(.jakarta(17, .bold)).foregroundStyle(Palette.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestions) { person in
                        VStack(spacing: 8) {
                            Avatar(url: person.picture, name: person.displayName, size: 64, online: person.isOnline)
                            Text(person.displayName).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                            Text(person.isOnline ? "Online now" : "On Sugerly").font(.jakarta(11)).foregroundStyle(Palette.muted)
                            Button {
                                guard let me = model.me else { return }
                                Task {
                                    try? await model.updateMe(["following": me.following + [person.email]])
                                    Notify.send(to: person.email, from: me, type: "follow", message: "\(me.displayName) started following you", link: "/Profile?email=\(me.email)")
                                }
                            } label: { Label("Follow", systemImage: "person.badge.plus").font(.jakarta(13, .bold)) }
                                .buttonStyle(GradientButtonStyle(height: 36))
                        }
                        .frame(width: 150)
                        .padding(14)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { withAnimation { _ = dismissed.insert(person.email) } } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 30, height: 30)
                            }
                        }
                        .onTapGesture { path.append(.person(person.email)) }
                    }
                }
            }
        }
        .sugarCard(radius: 26, padding: 14)
    }
}

struct EmptyCard: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Theme.pink.opacity(0.4), radius: 12, y: 6)
            Text(title).font(.display(24)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Text(text).font(.jakarta(14)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .sugarCard(radius: 28)
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

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { post.likes.contains(me) }
    private var saved: Bool { model.me?.savedPosts.contains(post.id) ?? false }
    private var author: UserProfile? { model.person(post.authorEmail) }
    private var following: Bool { model.me?.following.contains(post.authorEmail) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !post.title.isEmpty || !post.text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !post.title.isEmpty { Text(post.title).font(.jakarta(17, .bold)).foregroundStyle(Palette.text) }
                    if !post.text.isEmpty { Text(Hashtags.styled(post.text)).font(.jakarta(15)).foregroundStyle(Palette.text).lineLimit(openable ? 6 : nil) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { open() }
            }
            if !post.imageURL.isEmpty { media }
            actions
            if !post.likes.isEmpty { likedBy }
            if openable {
                Button { open() } label: {
                    HStack(spacing: 10) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 30)
                        Text((store.commentCounts[post.id] ?? 0) > 0 ? "View \(store.commentCounts[post.id] ?? 0) comments…" : "Add a comment…")
                            .font(.jakarta(14)).foregroundStyle(Palette.muted)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .sugarCard(radius: 28)
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await store.delete(post)
                    if !openable, !path.isEmpty { path.removeLast() }
                }
            }
        } message: { Text("This can't be undone.") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { path.append(.person(post.authorEmail)) } label: {
                Avatar(url: author?.picture ?? post.authorPicture, name: author?.displayName ?? post.authorName, size: 46, online: author?.isOnline ?? false)
            }
            .buttonStyle(BouncyStyle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(author?.displayName ?? post.authorName).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                    if post.authorEmail != me && !following {
                        Text("·").foregroundStyle(Palette.muted)
                        Button("Follow") { follow() }.font(.jakarta(14, .bold)).foregroundStyle(Theme.pink).buttonStyle(.plain)
                    }
                }
                Text(Dates.ago(post.created) + (post.title.isEmpty ? "" : " · \(post.title)")).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
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
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 36, height: 36).contentShape(Rectangle())
            }
        }
    }

    private var media: some View {
        Rectangle().fill(Palette.surface2)
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .overlay { RemoteImage(url: post.imageURL) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Theme.gradient)
                    .shadow(color: Theme.pink.opacity(0.6), radius: 20)
                    .scaleEffect(heart ? 1 : 0.3)
                    .opacity(heart ? 1 : 0)
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
                    Text("\(post.likes.count)").font(.jakarta(15, .bold)).foregroundStyle(liked ? Theme.pink : Palette.text2)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
            Button { open() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right").foregroundStyle(Palette.text2)
                    Text("\(store.commentCounts[post.id] ?? 0)").font(.jakarta(15, .bold)).foregroundStyle(Palette.text2)
                }
            }
            ShareLink(item: post.title.isEmpty ? post.text : post.title, subject: Text("Sugerly")) {
                Image(systemName: "paperplane").foregroundStyle(Palette.text2)
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
        .font(.system(size: 21, weight: .semibold))
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
                (Text("Liked by ") + Text(first.displayName).bold() + Text(post.likes.count > 1 ? " and \(post.likes.count - 1) other\(post.likes.count == 2 ? "" : "s")" : ""))
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
        if next.contains(post.id) { next.removeAll { $0 == post.id } } else { next.append(post.id) }
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
    @FocusState private var typing: Bool

    struct Thread: Identifiable {
        let parent: Comment
        let replies: [Comment]
        var id: String { parent.id }
    }

    private var threads: [Thread] {
        let blocked = Set(model.me?.blocked ?? [])
        let visible = comments.filter { !blocked.contains($0.authorEmail) }
        return visible.filter { $0.parentId.isEmpty }.map { parent in Thread(parent: parent, replies: visible.filter { $0.parentId == parent.id }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header()
                Text(comments.isEmpty ? "No comments yet" : "\(comments.count) comment\(comments.count == 1 ? "" : "s")")
                    .font(.display(22)).foregroundStyle(Palette.text).padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 16) {
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
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 36)
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

    private func load() async {
        guard let docs = try? await FS.query(collection, [.equals(field, targetId)]) else { return }
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
            field: targetId, "content": text, "gif_url": "",
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
                draft = ""
            }
            let target = replyTo?.authorEmail ?? ownerEmail
            Notify.send(to: target, from: me, type: "comment", message: "\(me.displayName) \(replyTo == nil ? "commented" : "replied"): \"\(text.prefix(60))\"", link: link)
            replyTo = nil
        } catch {}
    }

    private func like(_ c: Comment) {
        guard let me = model.me?.email, let i = comments.firstIndex(where: { $0.id == c.id }) else { return }
        var next = c
        if next.likes.contains(me) { next.likes.removeAll { $0 == me } } else { next.likes.append(me) }
        comments[i] = next
        Task { try? await FS.update(collection, c.id, ["likes": next.likes, "updated_date": FS.nowISO()]) }
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
            Avatar(url: model.person(comment.authorEmail)?.picture ?? comment.authorPicture, name: comment.authorName, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.authorName).font(.jakarta(13, .bold)).foregroundStyle(Palette.text)
                    if !comment.text.isEmpty { Text(comment.text).font(.jakarta(15)).foregroundStyle(Palette.text) }
                    if !comment.gifURL.isEmpty {
                        RemoteImage(url: comment.gifURL, contentMode: .fit).frame(maxWidth: 200, maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 12))
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
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "New post", actionTitle: "Post", busy: posting, canPost: image != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, onClose: { dismiss() }, onPost: { Task { await post() } }) {
            HStack(spacing: 12) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 46)
                VStack(alignment: .leading) {
                    Text(model.me?.displayName ?? "").font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
                    Text("Posting to Community").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
            }
            SugarField(placeholder: "Title (optional)", text: $title)
            SugarField(placeholder: "What's on your mind? Add #tags!", text: $text, lines: 4...12)
            PhotoPickerCard(item: $item, image: $image)
            if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
        }
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
