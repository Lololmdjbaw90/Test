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
    // Conversations where someone else has written / where you have written
    // (for message requests).
    private(set) var heard = Set<String>()
    private(set) var wrote = Set<String>()
    // People you ignore: their messages don't count as unread.
    var muted = Set<String>()

    // Closed DMs hide from the list until a new message comes in (like Discord).
    private(set) var closed: [String: String] = (UserDefaults.standard.dictionary(forKey: "sugerly.closedDMs") as? [String: String]) ?? [:]

    func isClosed(_ c: Conversation) -> Bool {
        guard let at = closed[c.id] else { return false }
        return (c.last?.created ?? "") <= at
    }

    func close(_ id: String) {
        closed[id] = FS.nowISO()
        markRead(id)
        UserDefaults.standard.set(closed, forKey: "sugerly.closedDMs")
    }

    func reopen(_ id: String) {
        guard closed[id] != nil else { return }
        closed[id] = nil
        UserDefaults.standard.set(closed, forKey: "sugerly.closedDMs")
    }

    // Older chats (beyond the newest messages) load as you scroll the list.
    var hasOlder = false
    var loadingOlder = false
    private var oldestFetched = ""
    private var restored = false

    func refresh(me: String) async {
        guard !me.isEmpty else { return }
        restore()
        if !loaded && conversations.isEmpty { loading = true }
        defer { loading = false }
        do {
            var filters: [FS.Filter] = [.contains("member_emails", me)]
            if loaded, !newest.isEmpty { filters.append(.after("created_date", Self.minus(newest, seconds: 60))) }
            let docs = try await FS.query("DirectMessage", filters, orderBy: "created_date", limit: loaded ? 100 : 300)
            let batch = docs.map(Message.init)
            if !loaded {
                hasOlder = docs.count >= 300
                oldestFetched = batch.map(\.created).filter { !$0.isEmpty }.min() ?? ""
            }
            merge(batch, me: me)
            loaded = true
            error = nil
            if !batch.isEmpty { persist() }
        } catch {
            if !loaded && conversations.isEmpty { self.error = error.localizedDescription }
        }
    }

    func loadOlder(me: String) async {
        guard hasOlder, !loadingOlder, !oldestFetched.isEmpty, !me.isEmpty else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let docs = try? await FS.query("DirectMessage", [.contains("member_emails", me), .before("created_date", oldestFetched)], orderBy: "created_date", limit: 300) else { return }
        let batch = docs.map(Message.init)
        hasOlder = docs.count >= 300
        oldestFetched = batch.map(\.created).filter { !$0.isEmpty }.min() ?? oldestFetched
        merge(batch, me: me, countUnread: false)
        persist()
    }

    // The chat list saved on the phone, so it shows instantly and old chats
    // never fall off it.
    private func restore() {
        guard !restored else { return }
        restored = true
        guard conversations.isEmpty else { return }
        let saved: [Conversation] = ChatCache.read("list").compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            let last = (d["last"] as? [String: Any]).map(Message.init)
            return Conversation(id: id, members: d.strs("members"), isGroup: d.bool("group"), groupName: d.str("name"), last: last, unread: 0)
        }
        conversations = saved.sorted { ($0.last?.created ?? "") > ($1.last?.created ?? "") }
    }

    private func persist() {
        let list: [Doc] = conversations.prefix(1000).map { c in
            var d: Doc = ["id": c.id, "members": c.members, "group": c.isGroup, "name": c.groupName]
            if let last = c.last { d["last"] = last.cacheDoc }
            return d
        }
        ChatCache.write("list", list)
    }

    private func merge(_ messages: [Message], me: String, countUnread: Bool = true) {
        var byId = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        // Oldest first, so the newest message ends up as "last".
        for m in messages.sorted(by: { $0.created < $1.created }) where !processed.contains(m.id) {
            processed.insert(m.id)
            var c = byId[m.conversationId] ?? Conversation(id: m.conversationId, members: m.members, isGroup: m.isGroup, groupName: m.groupName, last: nil, unread: 0)
            if (c.last?.created ?? "") <= m.created { c.last = m }
            if m.kind != "call" { if m.authorEmail == me { wrote.insert(m.conversationId) } else { heard.insert(m.conversationId) } }
            if countUnread && m.authorEmail != me && !m.readBy.contains(me) && !muted.contains(m.authorEmail) { c.unread += 1 }
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
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var store
    @State private var search = ""
    @State private var starting = false
    @State private var appeared = false
    @State private var showRequests = false
    @State private var showIgnored = false
    @AppStorage("sugerly.chat.section") private var section = 0

    private var visible: [Conversation] {
        let blocked = Set(model.me?.blocked ?? [])
        let me = model.me?.email ?? ""
        return store.conversations.filter { c in
            (c.isGroup || !c.others(me).contains(where: blocked.contains)) &&
                (search.isEmpty ? !store.isClosed(c) : c.title(model).localizedCaseInsensitiveContains(search))
        }
    }

    private func isIgnored(_ c: Conversation) -> Bool {
        guard !c.isGroup, let other = c.others(model.me?.email ?? "").first else { return false }
        return model.me?.ignored.contains(other) ?? false
    }

    // Message requests from people you aren't friends with yet.
    private var requests: [Conversation] {
        visible.filter { !isIgnored($0) && DMRules.state($0, model: model, chats: store) == .requestReceived }
    }
    private var ignoredChats: [Conversation] { visible.filter(isIgnored) }
    private var shown: [Conversation] {
        let tucked = Set(requests.map(\.id)).union(ignoredChats.map(\.id))
        return visible.filter { !tucked.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(section == 0 ? "Messages" : "Servers").font(.display(38)).foregroundStyle(Palette.text)
                        .contentTransition(.opacity)
                    Spacer()
                    if section == 0 {
                        Button { starting = true } label: { Label("New", systemImage: "square.and.pencil") }
                            .buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
                    }
                }
                .padding(.horizontal, 4)
                SectionSwitch(options: [("Chats", "bubble.left.and.bubble.right.fill"), ("Servers", "person.3.fill")], selection: $section)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: 680)

            if section == 1 {
                ServerHubView(path: $path)
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        chatList
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.refresh(me: model.me?.email ?? "") }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: section)
        .sugarBackground()
        .sugarTopBar($path)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
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
            .presentationCornerRadius(34)
        }
    }

    @ViewBuilder
    private var chatList: some View {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search conversations…", text: $search).font(.jakarta(15))
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                .padding(.bottom, 6)

                if store.loading && store.conversations.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                } else if let error = store.error, store.conversations.isEmpty {
                    EmptyCard(icon: "wifi.exclamationmark", title: "Couldn't load chats", text: error)
                } else if shown.isEmpty {
                    if search.isEmpty {
                        EmptyCard(icon: "bubble.left.and.bubble.right.fill", title: "No chats yet", text: "Say hi to someone! Your chats and group chats live here.", actionTitle: "Start a chat") { starting = true }
                    } else {
                        EmptyCard(icon: "magnifyingglass", title: "No chats found", text: "No one by that name. Try another?")
                    }
                }

                if search.isEmpty && !requests.isEmpty {
                    tuckedSection(title: "Message requests", icon: "envelope.badge.fill", list: requests, open: $showRequests,
                                  note: "People you aren't friends with yet. Open one to accept or decline.")
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, c in
                    Button { path.append(.chat(c)) } label: { ConversationRow(conversation: c) }
                        .buttonStyle(BouncyStyle(scale: 0.97))
                        .stagger(appeared, i + 1)
                        .contextMenu {
                            if c.unread > 0 {
                                Button { store.markRead(c.id) } label: { Label("Mark as read", systemImage: "checkmark.bubble") }
                            }
                            Button(role: .destructive) { withAnimation(.snappy) { store.close(c.id) } } label: {
                                Label(c.isGroup ? "Hide chat" : "Close DM", systemImage: "xmark.circle")
                            }
                        }
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                }
                if search.isEmpty && !ignoredChats.isEmpty {
                    tuckedSection(title: "Ignored", icon: "bell.slash.fill", list: ignoredChats, open: $showIgnored,
                                  note: "Chats with people you ignore. They can't ping you.")
                }
                if search.isEmpty && store.hasOlder {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Theme.main)
                        Text("Loading older chats").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .onAppear { Task { await store.loadOlder(me: model.me?.email ?? "") } }
                }
                let hidden = store.conversations.filter { store.isClosed($0) }.count
                if search.isEmpty && hidden > 0 {
                    Label("\(hidden) closed chat\(hidden == 1 ? "" : "s") — search a name to open one again", systemImage: "eye.slash")
                        .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
    }
}

extension ChatListView {
    // A folded group of chats (requests, ignored) that opens with a tap.
    func tuckedSection(title: String, icon: String, list: [Conversation], open: Binding<Bool>, note: String) -> some View {
        VStack(spacing: 8) {
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.wrappedValue.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Theme.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                        Text(note).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text("\(list.count)").font(.jakarta(12, .heavy)).foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22).background(Theme.main, in: Capsule())
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(open.wrappedValue ? 180 : 0))
                }
                .sugarCard(radius: 22, padding: 10)
            }
            .buttonStyle(BouncyStyle(scale: 0.98))
            if open.wrappedValue {
                ForEach(list) { c in
                    Button { path.append(.chat(c)) } label: { ConversationRow(conversation: c) }
                        .buttonStyle(BouncyStyle(scale: 0.97))
                        .padding(.leading, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

// Two big segments ("Chats | Servers") with a sliding pink pill.
struct SectionSwitch: View {
    let options: [(String, String)]
    @Binding var selection: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = i } } label: {
                    Label(option.0, systemImage: option.1)
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(selection == i ? .white : Palette.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if selection == i {
                                Capsule().fill(Theme.gradient)
                                    .shadow(color: Theme.main.opacity(0.35), radius: 8, y: 3)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.96))
            }
        }
        .padding(4)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model

    var body: some View {
        let me = model.me?.email ?? ""
        let other = conversation.others(me).first.flatMap { model.person($0) }
        let unread = conversation.unread > 0
        HStack(spacing: 14) {
            if conversation.isGroup {
                Image(systemName: "person.3.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(LinearGradient(colors: [Theme.lavender, Theme.pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Avatar(url: conversation.picture(model), name: conversation.title(model), size: 56, online: other?.isOnline ?? false, ring: unread)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title(model)).font(.jakarta(16, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer()
                    Text(Dates.ago(conversation.last?.created ?? "")).font(.jakarta(12, unread ? .bold : .regular)).foregroundStyle(unread ? Theme.pink : Palette.muted)
                }
                HStack(spacing: 5) {
                    if let last = conversation.last, last.authorEmail == me, last.kind != "call" {
                        Ticks(pending: false, read: last.readBy.contains { $0 != me })
                    }
                    if let icon = previewIcon {
                        Image(systemName: icon).font(.system(size: 12, weight: .bold))
                            .foregroundStyle(conversation.last?.callOutcome == "missed" ? Palette.danger : Palette.muted)
                    }
                    Text(preview(me)).font(.jakarta(14, unread ? .semibold : .regular)).foregroundStyle(unread ? Palette.text : Palette.muted).lineLimit(1)
                    Spacer()
                    if unread {
                        Text("\(min(conversation.unread, 99))")
                            .font(.jakarta(11, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 8).frame(minHeight: 22)
                            .background(Theme.gradient, in: Capsule())
                            .shadow(color: Theme.pink.opacity(0.4), radius: 6, y: 3)
                    }
                }
            }
        }
        .padding(12)
        .background(unread ? Theme.pink.opacity(0.06) : Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(unread ? Theme.pink.opacity(0.25) : Palette.border, lineWidth: 1))
        .shadow(color: unread ? Theme.main.opacity(0.12) : Palette.shadow, radius: unread ? 12 : 6, y: 3)
    }

    private var previewIcon: String? {
        guard let last = conversation.last else { return nil }
        if last.kind == "call" { return last.callOutcome == "missed" ? "phone.arrow.down.left.fill" : "phone.fill" }
        if !last.audioURL.isEmpty { return "mic.fill" }
        if last.sharedReel != nil { return "play.rectangle.fill" }
        if !last.imageURL.isEmpty && last.displayText.isEmpty { return Media.isSticker(last.imageURL) ? "face.smiling" : "photo.fill" }
        return nil
    }

    private func preview(_ me: String) -> String {
        guard let last = conversation.last else { return "Say hi" }
        if last.kind == "call" {
            switch last.callOutcome {
            case "missed": return last.authorEmail == me ? "No answer" : "Missed voice call"
            case "declined": return "Declined call"
            default:
                let s = Int(last.callDuration / 1000)
                return "Voice call · \(s / 60):\(String(format: "%02d", s % 60))"
            }
        }
        let body: String
        if !last.audioURL.isEmpty { body = "Voice message" }
        else if last.sharedReel != nil { body = last.displayText.isEmpty ? "Sent a reel" : last.displayText }
        else if last.displayText.isEmpty { body = last.imageURL.isEmpty ? "Message" : Media.label(last.imageURL) }
        else { body = last.displayText }
        if last.authorEmail == me || !conversation.isGroup { return body }
        return "\(last.authorName.split(separator: " ").first.map(String.init) ?? last.authorName): \(body)"
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
        VStack(spacing: 14) {
            HStack {
                Text("New message").font(.display(28)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text2)
                        .frame(width: 36, height: 36).background(Palette.surface, in: Circle())
                }
                .buttonStyle(BouncyStyle())
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search people", text: $search).font(.jakarta(15))
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.people.isEmpty { ProgressView().padding(30) }
                    ForEach(people) { person in
                        Button { onPick(person.email) } label: {
                            HStack(spacing: 12) {
                                Avatar(url: person.picture, name: person.displayName, size: 48, online: person.isOnline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.displayName).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                                    Text(person.bio.isEmpty ? "On Sugerly" : person.bio).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "paperplane.fill").foregroundStyle(Theme.pink)
                            }
                            .padding(12)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.97))
                    }
                }
            }
        }
        .padding(18)
        .sugarBackground()
        .task { if model.people.isEmpty { await model.loadPeople() } }
    }
}
