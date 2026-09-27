import SwiftUI
import UIKit
import PhotosUI

// Your chats. It checks for new messages every few seconds, asking only for
// messages newer than the last one it has (a check with nothing new costs a
// single database read).
@MainActor
@Observable
final class ChatStore {
    var conversations: [Conversation] = []
    var loading = false
    var error: String?
    private var newest = ""
    private var loaded = false
    private var processed = Set<String>() // message ids already counted

    var unread: Int { conversations.reduce(0) { $0 + $1.unread } }

    func refresh(me: String) async {
        guard !me.isEmpty else { return }
        if !loaded { loading = true }
        defer { loading = false }
        do {
            var filters: [FS.Filter] = [.contains("member_emails", me)]
            if loaded, !newest.isEmpty { filters.append(.after("created_date", Self.minus(newest, seconds: 60))) }
            let docs = try await FS.query("DirectMessage", filters, orderBy: "created_date", limit: loaded ? 100 : 300)
            merge(docs.map(Message.init), me: me)
            loaded = true
            error = nil
        } catch {
            if !loaded { self.error = error.localizedDescription }
        }
    }

    private func merge(_ messages: [Message], me: String) {
        var byId = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        // Oldest first, so the newest message ends up as "last".
        for m in messages.sorted(by: { $0.created < $1.created }) where !processed.contains(m.id) {
            processed.insert(m.id)
            var c = byId[m.conversationId] ?? Conversation(id: m.conversationId, members: m.members, isGroup: m.isGroup, groupName: m.groupName, last: nil, unread: 0)
            if (c.last?.created ?? "") <= m.created { c.last = m }
            if m.authorEmail != me && !m.readBy.contains(me) { c.unread += 1 }
            if c.members.isEmpty { c.members = m.members }
            byId[m.conversationId] = c
            if m.created > newest { newest = m.created }
        }
        conversations = byId.values.sorted { ($0.last?.created ?? "") > ($1.last?.created ?? "") }
    }

    func markRead(_ id: String) {
        if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].unread = 0 }
    }

    func upsert(_ message: Message, me: String) { merge([message], me: me) }

    static func minus(_ iso: String, seconds: Double) -> String {
        guard let date = Dates.parse(iso) else { return iso }
        return Dates.iso(date.addingTimeInterval(-seconds))
    }
}

extension Conversation {
    func others(_ me: String) -> [String] { members.filter { $0 != me } }

    @MainActor
    func title(_ model: AppModel) -> String {
        let me = model.me?.email ?? ""
        if isGroup { return groupName.isEmpty ? "Group" : groupName }
        let other = others(me).first ?? me
        if let person = model.person(other) { return person.displayName }
        if let last, last.authorEmail == other { return last.authorName }
        return String(other.split(separator: "@").first ?? "")
    }

    @MainActor
    func picture(_ model: AppModel) -> String {
        guard !isGroup else { return "" }
        let other = others(model.me?.email ?? "").first ?? ""
        return model.person(other)?.picture ?? ""
    }
}

struct ChatListView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var store
    @State private var path: [Route] = []
    @State private var search = ""
    @State private var starting = false
    @State private var posts = PostsStore()

    private var shown: [Conversation] {
        let blocked = Set(model.me?.blocked ?? [])
        let me = model.me?.email ?? ""
        return store.conversations.filter { c in
            (c.isGroup || !c.others(me).contains(where: blocked.contains)) &&
                (search.isEmpty || c.title(model).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(shown) { c in
                NavigationLink(value: Route.chat(c)) {
                    ConversationRow(conversation: c)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listStyle(.plain)
            .overlay {
                if store.loading && store.conversations.isEmpty {
                    ProgressView()
                } else if let error = store.error, store.conversations.isEmpty {
                    ContentUnavailableView("Couldn't load chats", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if shown.isEmpty && !store.loading {
                    ContentUnavailableView {
                        Label(search.isEmpty ? "No messages yet" : "No chats found", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text(search.isEmpty ? "Start a chat with someone on Sugerly." : "Try another name.")
                    } actions: {
                        if search.isEmpty { Button("New message") { starting = true }.buttonStyle(.borderedProminent) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search chats")
            .refreshable { await store.refresh(me: model.me?.email ?? "") }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { starting = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New message")
                }
            }
            .navigationDestination(for: Route.self) { route in RouteView(route: route, store: posts, path: $path) }
            .sheet(isPresented: $starting) {
                NewChatView { email in
                    starting = false
                    guard let me = model.me?.email else { return }
                    let id = Social.dmId(me, email)
                    let existing = store.conversations.first { $0.id == id }
                    let c = existing ?? Conversation(id: id, members: [me, email.lowercased()], isGroup: false, groupName: "", last: nil, unread: 0)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(.chat(c))
                    }
                }
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model

    var body: some View {
        let me = model.me?.email ?? ""
        let other = conversation.others(me).first.flatMap { model.person($0) }
        HStack(spacing: 12) {
            if conversation.isGroup {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Theme.lavender, Theme.pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "person.3.fill").foregroundStyle(.white).font(.system(size: 18))
                }
                .frame(width: 52, height: 52)
            } else {
                Avatar(url: conversation.picture(model), name: conversation.title(model), size: 52, online: other?.isOnline ?? false)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title(model)).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(Dates.ago(conversation.last?.created ?? "")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(preview(me)).font(.subheadline).foregroundStyle(conversation.unread > 0 ? .primary : .secondary).lineLimit(2)
                    Spacer()
                    if conversation.unread > 0 {
                        Text("\(min(conversation.unread, 99))")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.pink, in: Capsule())
                    }
                }
            }
        }
    }

    private func preview(_ me: String) -> String {
        guard let last = conversation.last else { return "Say hi 👋" }
        let body = last.text.isEmpty ? (last.imageURL.isEmpty ? "Message" : "📷 Photo") : last.text
        if last.authorEmail == me { return "You: \(body)" }
        return conversation.isGroup ? "\(last.authorName): \(body)" : body
    }
}

// MARK: - One conversation

struct ChatView: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var chats
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var photo: PhotosPickerItem?
    @State private var sending = false
    @State private var loaded = false
    @State private var reporting: ReportSheet.Target?
    @State private var failed: String?

    private var me: String { model.me?.email ?? "" }
    private var members: [String] { conversation.members.isEmpty ? [me] : conversation.members }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if loaded && messages.isEmpty {
                        VStack(spacing: 10) {
                            Avatar(url: conversation.picture(model), name: conversation.title(model), size: 72)
                            Text(conversation.title(model)).font(.title3.bold())
                            Text("Say hi 👋").foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        Bubble(message: message,
                               mine: message.authorEmail == me,
                               showName: conversation.isGroup && message.authorEmail != me && previous?.authorEmail != message.authorEmail,
                               showTime: previous == nil || gap(previous!, message))
                            .id(message.id)
                            .contextMenu {
                                if !message.text.isEmpty { Button { UIPasteboard.general.string = message.text } label: { Label("Copy", systemImage: "doc.on.doc") } }
                                if message.authorEmail == me {
                                    Button(role: .destructive) { delete(message) } label: { Label("Delete", systemImage: "trash") }
                                } else {
                                    Button { reporting = ReportSheet.Target(id: message.id, type: "message", ownerEmail: message.authorEmail, preview: message.text, link: "/DirectMessages") } label: { Label("Report", systemImage: "flag") }
                                }
                            }
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(conversation.title(model))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .task { await poll() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let failed { Text(failed).font(.caption).foregroundStyle(.red) }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 20)).frame(width: 36, height: 38)
                }
                .accessibilityLabel("Send a photo")
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).symbolRenderingMode(.hierarchical)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .sensoryFeedback(.impact(weight: .medium), trigger: messages.count)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func gap(_ a: Message, _ b: Message) -> Bool {
        guard let x = Dates.parse(a.created), let y = Dates.parse(b.created) else { return false }
        return y.timeIntervalSince(x) > 15 * 60
    }

    // New messages every 2 seconds while the chat is open (4 if this
    // project lacks the chat index, to keep database reads low).
    private func poll() async {
        while !Task.isCancelled {
            await load()
            let slow = FS.missingIndex.contains("DirectMessage")
            try? await Task.sleep(for: .seconds(slow ? 4 : 2))
        }
    }

    private func load() async {
        guard !me.isEmpty else { return }
        var filters: [FS.Filter] = [.equals("conversation_id", conversation.id), .contains("member_emails", me)]
        let newest = messages.last(where: { !$0.pending })?.created ?? ""
        if loaded, !newest.isEmpty { filters.append(.after("created_date", ChatStore.minus(newest, seconds: 60))) }
        guard let docs = try? await FS.query("DirectMessage", filters, orderBy: "created_date", limit: loaded ? 100 : 200) else {
            loaded = true
            return
        }
        let incoming = docs.map(Message.init)
        let known = Set(messages.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }.sorted { $0.created < $1.created }
        if !fresh.isEmpty || !loaded {
            withAnimation(loaded ? .snappy : nil) {
                messages = (messages + fresh).sorted { $0.created < $1.created }
            }
        }
        loaded = true
        markRead(messages)
    }

    private func markRead(_ list: [Message]) {
        let unread = list.filter { $0.authorEmail != me && !$0.readBy.contains(me) && !$0.pending }
        guard !unread.isEmpty else { return }
        chats.markRead(conversation.id)
        for m in unread.suffix(30) {
            if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i].readBy.append(me) }
            Task { try? await FS.update("DirectMessage", m.id, ["read_by": m.readBy + [me], "updated_date": FS.nowISO()]) }
        }
    }

    private func payload(text: String, imageURL: String) -> Doc? {
        guard let meProfile = model.me else { return nil }
        let now = FS.nowISO()
        return [
            "conversation_id": conversation.id,
            "conversation_type": conversation.isGroup ? "group" : "dm",
            "group_name": conversation.isGroup ? conversation.groupName : "",
            "content": text, "image_url": imageURL,
            "user_email": meProfile.email, "user_display_name": meProfile.displayName,
            "user_profile_picture": meProfile.picture,
            "member_emails": members, "read_by": [meProfile.email],
            "reactions": [String: Any](), "is_edited": false,
            "created_by": meProfile.email, "created_date": now, "updated_date": now,
        ]
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var data = payload(text: text, imageURL: "") else { return }
        draft = ""
        failed = nil
        var pending = Message(data)
        pending.id = "pending-\(UUID().uuidString)"
        pending.pending = true
        withAnimation(.snappy) { messages.append(pending) }
        do {
            data["created_date"] = FS.nowISO()
            let doc = try await FS.create("DirectMessage", data)
            let created = Message(doc)
            if let i = messages.firstIndex(where: { $0.id == pending.id }) { messages[i] = created }
            chats.upsert(created, me: me)
        } catch {
            withAnimation { messages.removeAll { $0.id == pending.id } }
            draft = text
            failed = "Couldn't send — \(error.localizedDescription)"
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let jpeg = ImageTools.jpeg(image, maxSide: 1600) else { return }
        do {
            let url = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            guard let data = payload(text: "", imageURL: url) else { return }
            let doc = try await FS.create("DirectMessage", data)
            let created = Message(doc)
            withAnimation(.snappy) { messages.append(created) }
            chats.upsert(created, me: me)
        } catch {
            failed = "Couldn't send the photo — \(error.localizedDescription)"
        }
    }

    private func delete(_ message: Message) {
        withAnimation { messages.removeAll { $0.id == message.id } }
        Task { try? await FS.delete("DirectMessage", message.id) }
    }
}

struct Bubble: View {
    let message: Message
    let mine: Bool
    let showName: Bool
    let showTime: Bool

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if showTime {
                Text(Dates.ago(message.created) == "now" ? "Now" : Dates.time(message.created))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            if showName { Text(message.authorName).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 12) }
            HStack {
                if mine { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 6) {
                    if !message.imageURL.isEmpty {
                        RemoteImage(url: message.imageURL, contentMode: .fill)
                            .frame(width: 220, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .foregroundStyle(mine ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                if mine {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.gradient)
                                } else {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card)
                                }
                            }
                    }
                }
                .opacity(message.pending ? 0.6 : 1)
                if !mine { Spacer(minLength: 48) }
            }
        }
    }
}

// MARK: - Start a chat

struct NewChatView: View {
    var onPick: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var people: [UserProfile] {
        let me = model.me?.email ?? ""
        let blocked = Set(model.me?.blocked ?? [])
        let following = Set(model.me?.following ?? [])
        return model.people.values
            .filter { $0.email != me && !blocked.contains($0.email) }
            .filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) || $0.email.localizedCaseInsensitiveContains(search) }
            .sorted { a, b in
                let fa = following.contains(a.email), fb = following.contains(b.email)
                if fa != fb { return fa }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List(people) { person in
                Button { onPick(person.email) } label: {
                    HStack(spacing: 12) {
                        Avatar(url: person.picture, name: person.displayName, size: 44, online: person.isOnline)
                        VStack(alignment: .leading) {
                            Text(person.displayName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            if !person.bio.isEmpty { Text(person.bio).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay { if model.people.isEmpty { ProgressView() } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people")
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { if model.people.isEmpty { await model.loadPeople() } }
        }
    }
}
