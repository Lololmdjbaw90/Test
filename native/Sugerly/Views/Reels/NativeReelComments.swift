import SwiftUI

struct NativeReelComments: View {
    let reel: NativeReel
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [Comment] = []
    @State private var cursor: Doc?
    @State private var more = true
    @State private var loading = false
    @State private var sending = false
    @State private var draft = ""
    @State private var reply: Comment?
    @State private var error: String?
    @State private var reporting: ReportSheet.Target?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(comments.filter { !(model.me?.blocked ?? []).contains($0.authorEmail) }) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            if !comment.replyToName.isEmpty { Text("Reply to \(comment.replyToName)").font(.caption).foregroundStyle(Theme.pink) }
                            CommentRow(comment: comment, onReply: { reply = comment }, onReport: {
                                reporting = ReportSheet.Target(id: comment.id, type: "comment", ownerEmail: comment.authorEmail, preview: comment.text, link: "/Reels?r=\(reel.id)")
                            }, onDelete: { Task { await remove(comment) } }, onLike: { Task { await like(comment) } })
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    if more { Button(loading ? "Loading…" : "Load more comments") { Task { await load() } }.disabled(loading) }
                    if comments.isEmpty && !loading { Text("Be the first to comment.").foregroundStyle(.secondary) }
                }.padding(20)
            }.background(Theme.background).navigationTitle("Comments").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let reply { HStack { Text("Replying to \(reply.authorName)").font(.caption); Spacer(); Button("Cancel") { self.reply = nil } } }
                        HStack {
                            TextField("Add a comment…", text: $draft, axis: .vertical).lineLimit(1...4)
                            Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                        }
                    }.padding(16).background(Theme.card)
                }.sheet(item: $reporting) { ReportSheet(target: $0) }.task { await load() }
        }
    }
    private func load() async {
        guard !loading, more else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let page = try await FS.page("CommunityComment", after: cursor, equalTo: ("post_id", "reel_\(reel.id)"), descending: false)
            let known = Set(comments.map(\.id))
            comments += page.rows.map(Comment.init).filter { !known.contains($0.id) }
            cursor = page.rows.last ?? cursor; more = page.more
        } catch { self.error = error.localizedDescription }
    }
    private func send() async {
        guard let me = model.me, !sending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { return }
        sending = true; error = nil
        defer { sending = false }
        do {
            guard let latest = try await FS.get("Reel", reel.id), !latest.bool("comments_off") else { throw APIError(message: "Comments are closed for this reel.") }
            let data: Doc = ["post_id": "reel_\(reel.id)", "content": text, "parent_id": reply.map { $0.parentId.isEmpty ? $0.id : $0.parentId } ?? "", "reply_to_name": reply?.authorName ?? "", "reply_to_email": reply?.authorEmail ?? "", "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture, "likes": [String](), "created_by": me.email, "created_date": FS.nowISO(), "updated_date": FS.nowISO()]
            let created = try await FS.create("CommunityComment", data)
            comments.append(Comment(created)); draft = ""; reply = nil
        } catch { self.error = error.localizedDescription }
    }
    private func remove(_ comment: Comment) async {
        do { try await FS.delete("CommunityComment", comment.id); comments.removeAll { $0.id == comment.id } }
        catch { self.error = error.localizedDescription }
    }
    private func like(_ comment: Comment) async {
        guard let me = model.me else { return }
        do {
            guard let latest = try await FS.get("CommunityComment", comment.id) else { return }
            var likes = latest.strs("likes")
            if likes.contains(me.email) { likes.removeAll { $0 == me.email } } else { likes.append(me.email) }
            try await FS.update("CommunityComment", comment.id, ["likes": likes])
            if let i = comments.firstIndex(where: { $0.id == comment.id }) { comments[i].likes = likes }
        } catch { self.error = error.localizedDescription }
    }
}
