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

    var unread: Int { conversations.filter { !isClosed($0) }.reduce(0) { $0 + $1.unread } }
    // Conversations where someone else has written / where you have written
    // (for message requests).
    private(set) var heard = Set<String>()
    private(set) var wrote = Set<String>()
    // People you ignore: their messages don't count as unread.
    var muted = Set<String>()

    // Closed DMs hide from the list until a new message comes in (like Discord).
    private(set) var closed: [String: String] = (UserDefaults.standard.dictionary(forKey: "sugerly.closedDMs") as? [String: String]) ?? [:]

    private var closedKey: String { "sugerly.closedDMs." + Drafts.owner }
    private var removedChats = Set<String>()
    private var cleanupChecked = Date.distantPast
    private var cleanupCursor = ""

    func isClosed(_ c: Conversation) -> Bool {
        guard let at = closed[c.id] else { return false }
        return (c.last?.created ?? "") <= at
    }

    func close(_ id: String) {
        closed[id] = FS.nowISO()
        markRead(id)
        UserDefaults.standard.set(closed, forKey: closedKey)
    }

    func reopen(_ id: String) {
        guard closed[id] != nil else { return }
        closed[id] = nil
        UserDefaults.standard.set(closed, forKey: closedKey)
    }

    // Older chats (beyond the newest messages) load as you scroll the list.
    var hasOlder = false
    var loadingOlder = false
    private var oldestFetched = ""
    private var restored = false

    func refresh(me: String) async {
        guard !me.isEmpty else { return }
        restore()
        await removeDeletedAccountChats(me: me)
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

    private func removeDeletedAccountChats(me: String) async {
        guard Date().timeIntervalSince(cleanupChecked) > 15 else { return }
        do {
            var filters: [FS.Filter] = [.equals("to_email", me)]
            if !cleanupCursor.isEmpty { filters.append(.after("created_date", cleanupCursor)) }
            let docs = try await FS.query("ChatRemoval", filters, orderBy: "created_date", descending: false, limit: 300)
            for doc in docs {
                let id = doc.str("conversation_id")
                guard !id.isEmpty else { continue }
                removedChats.insert(id)
                ChatCache.save(id, [])
                if doc.str("created_date") > cleanupCursor { cleanupCursor = doc.str("created_date") }
            }
            if !docs.isEmpty {
                conversations.removeAll { removedChats.contains($0.id) }
                UserDefaults.standard.set(Array(removedChats), forKey: "sugerly.removedChats." + Drafts.owner)
                UserDefaults.standard.set(cleanupCursor, forKey: "sugerly.chatCleanupCursor." + Drafts.owner)
                persist()
            }
            cleanupChecked = Date()
        } catch { /* Offline is not evidence that somebody deleted their account. */ }
    }

    func wasRemoved(_ id: String) -> Bool { removedChats.contains(id) }

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
        closed = (UserDefaults.standard.dictionary(forKey: closedKey) as? [String: String]) ?? [:]
        removedChats = Set(UserDefaults.standard.stringArray(forKey: "sugerly.removedChats." + Drafts.owner) ?? [])
        cleanupCursor = UserDefaults.standard.string(forKey: "sugerly.chatCleanupCursor." + Drafts.owner) ?? ""
        guard conversations.isEmpty else { return }
        let saved: [Conversation] = ChatCache.read("list").compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            let last = (d["last"] as? [String: Any]).map(Message.init)
            return Conversation(id: id, members: d.strs("members"), isGroup: d.bool("group"), groupName: d.str("name"), last: last, unread: 0)
        }
        conversations = saved.filter { !removedChats.contains($0.id) }.sorted { ($0.last?.created ?? "") > ($1.last?.created ?? "") }
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
        ChatStreaks.shared.note(messages, me: me)
        var byId = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        // Oldest first, so the newest message ends up as "last".
        for m in messages.sorted(by: { $0.created < $1.created }) where !processed.contains(m.id) && !removedChats.contains(m.conversationId) {
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

    func removedMessage(_ id: String, in conversationID: String, remaining: [Message]) {
        processed.remove(id)
        if let i = conversations.firstIndex(where: { $0.id == conversationID }), conversations[i].last?.id == id {
            conversations[i].last = remaining.last
            if remaining.isEmpty { close(conversationID) }
        }
        persist()
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

// Your chats, or your servers (the switch at the top). A plain iPhone list:
// tap to open, swipe left to close a chat, swipe right to mark it read.
struct ChatListView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var store
    @State private var search = ""
    @State private var starting = false
    @State private var showRequests = false
    @State private var showIgnored = false
    @AppStorage("sugerly.chat.section") private var section = 0

    private var visible: [Conversation] {
        let blocked = Set(model.me?.blocked ?? [])
        let me = model.me?.email ?? ""
        return store.conversations.filter { c in
            (c.isGroup || !c.others(me).contains(where: blocked.contains)) &&
                !store.isClosed(c) && (search.isEmpty || c.title(model).localizedCaseInsensitiveContains(search))
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

    // Friends (you follow each other) who are online right now.
    private var onlineFriends: [String] {
        guard let me = model.me else { return [] }
        let blocked = Set(me.blocked)
        return me.following.filter { email in
            guard !blocked.contains(email), let person = model.person(email) else { return false }
            return person.isOnline && person.following.contains(me.email)
        }
    }

    // A row of friends who are online, each a tap away from a chat.
    private var onlineStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Palette.success).frame(width: 8, height: 8)
                Text("Online now").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(onlineFriends.enumerated()), id: \.element) { i, email in
                        let person = model.person(email)
                        Button { openChat(with: email) } label: {
                            VStack(spacing: 5) {
                                Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 44, online: true)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(Candy.allCases[i % Candy.allCases.count].gradient, lineWidth: 2.5))
                                Text(person?.displayName ?? "").font(.jakarta(11, .semibold)).foregroundStyle(Palette.text2)
                                    .lineLimit(1).frame(width: 58)
                            }
                        }
                        .buttonStyle(BouncyStyle(scale: 0.9))
                        .accessibilityLabel("Chat with \(person?.displayName ?? email)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(10)
        .sugarCard(radius: 20)
    }

    private func openChat(with email: String) {
        guard let me = model.me?.email else { return }
        let id = Social.dmId(me, email)
        let existing = store.conversations.first { $0.id == id }
        let c = existing ?? Conversation(id: id, members: [me, email.lowercased()], isGroup: false, groupName: "", last: nil, unread: 0)
        path.append(.chat(c))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chats or Servers, under the logo.
            TitleSwitch(titles: ["Chats", "Servers"], selection: $section)
                .padding(.top, 2)
                .padding(.bottom, 6)
            sections
        }
        // The page colour stays put while the list fades in.
        .sugarBackground()
        .quietTitle(section == 0 ? "Chats" : "Servers")
        .rootBar(create: false, message: { starting = true })
        .sheet(isPresented: $starting) {
            NewChatView { email in
                starting = false
                guard let me = model.me?.email else { return }
                let id = Social.dmId(me, email)
                let existing = store.conversations.first { $0.id == id }
                let c = existing ?? Conversation(id: id, members: [me, email.lowercased()], isGroup: false, groupName: "", last: nil, unread: 0)
                if section != 0 { section = 0 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    path.append(.chat(c))
                }
            }
            .presentationCornerRadius(34)
        }
    }

    private var sections: some View {
        Group {
            // The two sides slide in from their own side of the switch.
            if section == 1 {
                ServersHome(path: $path, embedded: true)
                    .transition(.asymmetric(insertion: .offset(x: 28).combined(with: .opacity), removal: .opacity.animation(Motion.exit)))
            } else {
                chats
                    .transition(.asymmetric(insertion: .offset(x: -28).combined(with: .opacity), removal: .opacity.animation(Motion.exit)))
            }
        }
        .animation(Motion.pick(.snappy(duration: 0.3)), value: section)
        .appearFade()
    }

    private var chats: some View {
        List {
            PageTitle(title: "Chats", subtitle: "Friends and group chats", icon: "bubble.left.and.bubble.right.fill", candy: .mint,
                      search: $search, prompt: "Search chats")
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if search.isEmpty && !onlineFriends.isEmpty {
                onlineStrip
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if store.loading && store.conversations.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonRow()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if let error = store.error, store.conversations.isEmpty {
                EmptyCard(icon: "wifi.exclamationmark", title: "Couldn't load chats", text: error)
                    .emptyRow()
            } else if shown.isEmpty && requests.isEmpty {
                Group {
                    if search.isEmpty {
                        EmptyCard(icon: "bubble.left.and.bubble.right.fill", title: "No chats yet", text: "Say hi to someone! Your chats and group chats live here.", actionTitle: "Start a chat") { starting = true }
                    } else {
                        EmptyCard(icon: "magnifyingglass", title: "No chats found", text: "No one by that name. Try another?")
                    }
                }
                .emptyRow()
            }

            if search.isEmpty && !requests.isEmpty {
                tucked("Message requests", note: "People you aren't friends with yet", icon: "envelope.badge.fill", list: requests, open: $showRequests)
            }

            ForEach(shown) { c in
                row(c)
            }

            if search.isEmpty && !ignoredChats.isEmpty {
                tucked("Ignored", note: "They can't ping you", icon: "bell.slash.fill", list: ignoredChats, open: $showIgnored)
            }

            if search.isEmpty && store.hasOlder {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Theme.main)
                    Text("Loading older chats").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onAppear { Task { await store.loadOlder(me: model.me?.email ?? "") } }
            }

            let hidden = store.conversations.filter { store.isClosed($0) }.count
            if search.isEmpty && hidden > 0 {
                Label("\(hidden) closed chat\(hidden == 1 ? "" : "s") — search a name to open one again", systemImage: "eye.slash")
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .sugarBackground()
        .motion(Motion.standard, value: shown.map(\.id))
        .refreshable { await store.refresh(me: model.me?.email ?? "") }
        // Long streaks on a fresh phone: fetch the older days they need.
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            await ChatStreaks.shared.deepen(store.conversations, me: model.me?.email ?? "")
        }
    }

    private func row(_ c: Conversation) -> some View {
        Button { path.append(.chat(c)) } label: {
            ConversationRow(conversation: c, card: true)
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { withMotion(Motion.standard) { store.close(c.id) } } label: {
                Label(c.isGroup ? "Hide" : "Close", systemImage: "xmark.circle")
            }
        }
        .swipeActions(edge: .leading) {
            if c.unread > 0 {
                Button { store.markRead(c.id) } label: { Label("Read", systemImage: "checkmark.bubble") }
                    .tint(Theme.main)
            }
        }
        .contextMenu {
            if c.unread > 0 {
                Button { store.markRead(c.id) } label: { Label("Mark as read", systemImage: "checkmark.bubble") }
            }
            Button(role: .destructive) { withMotion(Motion.standard) { store.close(c.id) } } label: {
                Label(c.isGroup ? "Hide chat" : "Close DM", systemImage: "xmark.circle")
            }
        }
    }

    // A folded group of chats (requests, ignored) that opens with a tap.
    private func tucked(_ title: String, note: String, icon: String, list: [Conversation], open: Binding<Bool>) -> some View {
        DisclosureGroup(isExpanded: open) {
            ForEach(list) { c in row(c) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.main)
                    .frame(width: 40, height: 40).background(Theme.soft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                    Text(note).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(list.count)").font(.jakarta(12, .semibold)).foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22).background(Theme.main, in: Capsule())
            }
        }
        .tint(Palette.muted)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Palette.border)
    }
}

private extension View {
    // An empty state inside a list: no card behind it, no lines.
    func emptyRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// Two big segments ("Chats | Servers") with a sliding pink pill.
struct SectionSwitch: View {
    let options: [(String, String)]
    @Binding var selection: Int
    @Namespace private var pill

    var body: some View {
        // With big text or a narrow screen the icons go, so the names fit.
        ViewThatFits(in: .horizontal) {
            row(icons: true)
            row(icons: false)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(icons: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                Button { withAnimation(Motion.pick(.spring(response: 0.38, dampingFraction: 0.78))) { selection = i } } label: {
                    Label(option.0, systemImage: option.1)
                        .labelStyle(SwitchLabel(icon: icons))
                        .font(.jakarta(14, .semibold))
                        .foregroundStyle(selection == i ? Theme.main : Palette.muted)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == i {
                                Capsule().fill(Palette.surface)
                                    .budgetShadow(color: Palette.shadow, radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.96))
            }
        }
        .padding(3)
        .background(Palette.surface2, in: Capsule())
    }
}

// A section's name, with or without its icon.
private struct SwitchLabel: LabelStyle {
    let icon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if icon { configuration.icon }
            configuration.title.lineLimit(1)
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    // A card of its own, or a plain row in a list.
    var card = true
    @Environment(AppModel.self) private var model

    var body: some View {
        let me = model.me?.email ?? ""
        let other = conversation.others(me).first.flatMap { model.person($0) }
        let unread = conversation.unread > 0
        let row = HStack(spacing: 10) {
            if conversation.isGroup {
                Image(systemName: "person.3.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.main)
                    .frame(width: 44, height: 44)
                    .background(Theme.soft, in: Circle())
            } else {
                Avatar(url: conversation.picture(model), name: conversation.title(model), size: 44, online: other?.isOnline ?? false)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title(model)).font(.jakarta(16, unread ? .bold : .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    if !conversation.isGroup, let streak = ChatStreaks.shared.streak(conversation.id) {
                        StreakBadge(streak: streak)
                    }
                    Spacer()
                    Text(Dates.ago(conversation.last?.created ?? "")).fixedSize().font(.jakarta(12, unread ? .semibold : .regular)).foregroundStyle(unread ? Theme.main : Palette.muted)
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
                            .font(.jakarta(11, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).frame(minWidth: 20, minHeight: 20)
                            .background(Theme.candy, in: Capsule())
                            .contentTransition(.numericText())
                            .transition(.pop)
                    }
                }
            }
        }
        if card {
            row
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(unread ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(unread ? Theme.main.opacity(0.28) : Palette.border, lineWidth: 1))
        } else {
            row.contentShape(Rectangle())
        }
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
        let name = model.name(last.authorEmail, last.authorName)
        return "\(name.split(separator: " ").first.map(String.init) ?? name): \(body)"
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
                    if model.people.isEmpty { SugarLoader().padding(30) }
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
        .task(id: search) {
            // Anyone on Sugerly, not just people this phone already knows.
            guard !search.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            _ = await model.searchPeople(search)
        }
    }
}
