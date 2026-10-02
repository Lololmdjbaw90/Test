import PhotosUI
import SwiftUI

// MARK: - Help & support chat
//
// Everyone has one conversation with the Sugerly team:
//   SupportTicket/{email}   who it is, the topic, open / solved, unread flags
//   SupportMessage          the messages (ticket_id = the person's email)
// Admins answer from Admin → Support. Moderation notices (when something of
// yours is removed) also land here, so people always know why.

struct SupportTicket: Identifiable, Hashable {
    var id: String
    var email: String
    var name: String
    var picture: String
    var status: String
    var topic: String
    var last: String
    var lastFromTeam: Bool
    var teamUnread: Bool
    var userUnread: Bool
    var updated: String

    var solved: Bool { status == "solved" }

    init(_ d: Doc) {
        id = d.str("id")
        email = d.str("user_email").lowercased()
        name = d.str("user_name")
        picture = d.str("user_picture")
        status = d.str("status")
        topic = d.str("topic")
        last = d.str("last_message")
        lastFromTeam = d.bool("last_from_team")
        teamUnread = d.bool("team_unread")
        userUnread = d.bool("user_unread")
        updated = d.str("updated_date")
    }
}

struct SupportMessage: Identifiable, Hashable {
    var id: String
    var ticketId: String
    var text: String
    var imageURL: String
    var fromTeam: Bool
    var authorName: String
    var kind: String      // "" normal, "notice" safety notice, "report" report update
    var created: String
    var pending = false

    init(_ d: Doc) {
        id = d.str("id")
        ticketId = d.str("ticket_id")
        text = d.str("text")
        imageURL = d.str("image_url")
        fromTeam = d.bool("from_team")
        authorName = d.str("author_name")
        kind = d.str("kind")
        created = d.str("created_date")
    }
}

enum Support {
    struct Topic: Identifiable, Hashable {
        let title: String
        let icon: String
        let hint: String
        let colors: [UInt32]
        var id: String { title }
    }

    static let topics: [Topic] = [
        Topic(title: "Account & login", icon: "person.crop.circle.fill", hint: "What happens when you try to log in or change your account?", colors: [0x7CBEFF, 0x2F80E0]),
        Topic(title: "Something's broken", icon: "ladybug.fill", hint: "What were you doing when it went wrong? A screenshot helps a lot.", colors: [0xFFAA80, 0xEE6E40]),
        Topic(title: "MimiPlus & coins", icon: "sparkles", hint: "Tell us what you bought or expected to get.", colors: [0xF472B6, 0xC084FC]),
        Topic(title: "Commissions", icon: "paintbrush.pointed.fill", hint: "Which order is it about, and what's the problem?", colors: [0x5FD3B0, 0x16A37F]),
        Topic(title: "Safety & reports", icon: "shield.lefthalf.filled", hint: "Who or what is it about? We keep this private.", colors: [0xFF7AA2, 0xD9577F]),
        Topic(title: "Privacy & my data", icon: "lock.fill", hint: "What would you like to see, change or delete?", colors: [0xB19CFF, 0x7C5CF0]),
        Topic(title: "Something else", icon: "questionmark.bubble.fill", hint: "Ask us anything.", colors: [0xFFD166, 0xF0A020]),
    ]

    static let answers: [(String, String)] = [
        ("How do I report someone?", "Tap ••• or long-press a post, comment, reel, message or profile and choose Report. You can follow what happened in My reports."),
        ("How do I block someone?", "Open their profile, tap ••• and choose Block. They can't message or call you and you won't see their posts."),
        ("How do I delete my account?", "Settings → Account → Delete account. Everything you made is removed."),
        ("I didn't get my MimiPlus or coins", "Pull down on the MimiPlus page to refresh. If it's still missing, send us a message here with the time you bought it."),
    ]

    static func ticketId(_ email: String) -> String { email.lowercased() }

    // Adds a message and keeps the conversation summary up to date.
    @MainActor
    @discardableResult
    static func send(to ticketEmail: String, text: String, imageURL: String = "", fromTeam: Bool, kind: String = "",
                     topic: String? = nil, owner: (name: String, picture: String)? = nil, model: AppModel) async throws -> Doc {
        guard let me = model.me else { throw APIError(message: "Please log in again.") }
        let ticket = ticketId(ticketEmail)
        let now = FS.nowISO()
        let message: Doc = [
            "ticket_id": ticket, "text": text, "image_url": imageURL, "from_team": fromTeam, "kind": kind,
            "author_email": me.email, "author_name": fromTeam ? "Sugerly Team" : me.displayName,
            "created_by": me.email, "created_date": now, "updated_date": now,
        ]
        let created = try await FS.create("SupportMessage", message)
        let preview = text.isEmpty ? "Sent a picture" : String(text.prefix(160))
        var summary: Doc = [
            "last_message": preview, "last_from_team": fromTeam, "updated_date": now,
            "team_unread": !fromTeam, "user_unread": fromTeam,
        ]
        if !fromTeam { summary["status"] = "open" }
        if let topic { summary["topic"] = topic }
        do {
            try await FS.update("SupportTicket", ticket, summary)
        } catch {
            var fresh = summary
            fresh["user_email"] = ticket
            fresh["user_name"] = fromTeam ? (owner?.name ?? model.person(ticket)?.displayName ?? "") : me.displayName
            fresh["user_picture"] = fromTeam ? (owner?.picture ?? model.person(ticket)?.picture ?? "") : me.picture
            fresh["status"] = "open"
            fresh["topic"] = topic ?? (kind == "notice" ? "Safety notice" : "")
            fresh["created_date"] = now
            try await FS.create("SupportTicket", fresh, id: ticket)
        }
        // A heads-up in their notifications (and to the team for new questions).
        if fromTeam {
            Notify.send(to: ticket, from: me, type: "support", message: kind == "notice" ? "Sugerly Team: a note about your content" : "Sugerly Team replied: \(preview)", link: "/Support")
        } else {
            for admin in model.people.values where admin.isAdmin && admin.email != me.email {
                Notify.send(to: admin.email, from: me, type: "support", message: "Needs help: \(preview)", link: "/Support?ticket=\(ticket)")
            }
        }
        return created
    }
}

// MARK: - Your help page (chat + your reports)

struct SupportView: View {
    enum Pane: String, CaseIterable { case chat = "Chat", reports = "My reports" }
    @Environment(AppModel.self) private var model
    @State private var section: Pane = .chat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Pane.allCases, id: \.self) { s in
                    Chip(title: s.rawValue, icon: s == .chat ? "bubble.left.and.bubble.right.fill" : "flag.fill", active: section == s) {
                        withAnimation(.snappy) { section = s }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ZStack {
                if section == .chat {
                    SupportChatView(ticketEmail: model.me?.email ?? "", team: false)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    MyReportsView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: section)
        }
        .sugarBackground()
        .navigationTitle("Help & support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - The conversation (you, or an admin answering someone)

struct SupportChatView: View {
    let ticketEmail: String
    let team: Bool
    @Environment(AppModel.self) private var model
    @State private var ticket: SupportTicket?
    @State private var messages: [SupportMessage] = []
    @State private var loaded = false
    @State private var draft = ""
    @State private var topic: Support.Topic?
    @State private var picked: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var sending = false
    @State private var openAnswer: String?
    @FocusState private var typing: Bool

    private var ticketId: String { Support.ticketId(ticketEmail) }
    private var person: UserProfile? { model.person(ticketId) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        header
                        if loaded && messages.isEmpty && !team { starter }
                        ForEach(messages) { m in
                            bubble(m)
                                .id(m.id)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                        if ticket?.solved == true {
                            Label(team ? "Marked solved" : "Marked solved — send a message to open it again", systemImage: "checkmark.seal.fill")
                                .font(.jakarta(12, .bold)).foregroundStyle(Palette.success)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Palette.success.opacity(0.12), in: Capsule())
                                .padding(.top, 4)
                        }
                        Color.clear.frame(height: 6).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: messages.map(\.id))
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            composer
        }
        .task(id: ticketId) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    withAnimation(.snappy) { photo = image }
                }
                picked = nil
            }
        }
        .toolbar {
            if team, ticket != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ticket?.solved == true ? "Reopen" : "Solved") { Task { await setSolved(!(ticket?.solved ?? false)) } }
                        .font(.jakarta(14, .heavy))
                }
            }
        }
    }

    // Who you're talking to.
    private var header: some View {
        VStack(spacing: 10) {
            if team {
                Avatar(url: person?.picture ?? ticket?.picture ?? "", name: person?.displayName ?? ticket?.name ?? ticketId, size: 64)
                Text(person?.displayName ?? ticket?.name ?? ticketId).font(.display(24)).foregroundStyle(Palette.text).lineLimit(1)
                Text(ticketId).font(.jakarta(12)).foregroundStyle(Palette.muted)
                if let topic = ticket?.topic, !topic.isEmpty { tag(topic) }
            } else {
                ZStack {
                    Circle().fill(Theme.soft).frame(width: 84, height: 84)
                    MimiBuddy(icon: "heart.fill", size: 70)
                }
                Text("Sugerly Team").font(.display(26)).foregroundStyle(Palette.text)
                Label("Usually replies within a day", systemImage: "clock.fill")
                    .font(.jakarta(12, .bold)).foregroundStyle(Palette.muted)
                if let topic = ticket?.topic, !topic.isEmpty { tag(topic) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.jakarta(11, .heavy)).foregroundStyle(Theme.main)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.soft, in: Capsule())
    }

    // Before the first message: pick what it's about, or find a quick answer.
    private var starter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you need help with?").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Support.topics) { t in
                    let active = topic == t
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { topic = active ? nil : t }
                        if !active { typing = true }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: t.icon).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(LinearGradient(colors: t.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(t.title).font(.jakarta(13, .bold)).foregroundStyle(Palette.text).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(active ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(active ? Theme.main : Palette.border, lineWidth: active ? 2 : 1))
                        .scaleEffect(active ? 1.02 : 1)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                }
            }
            Text("Quick answers").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Support.answers, id: \.0) { q, a in
                    let open = openAnswer == q
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { openAnswer = open ? nil : q } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(q).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
                                    .rotationEffect(.degrees(open ? 180 : 0))
                            }
                            if open {
                                Text(a).font(.jakarta(13)).foregroundStyle(Palette.text2).multilineTextAlignment(.leading)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if q != Support.answers.last?.0 { Divider().padding(.leading, 14) }
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func bubble(_ m: SupportMessage) -> some View {
        let mine = m.fromTeam == team
        if m.kind == "notice" {
            VStack(alignment: .leading, spacing: 8) {
                Label("Safety notice", systemImage: "shield.lefthalf.filled").font(.jakarta(12, .heavy)).foregroundStyle(Palette.danger)
                Text(m.text).font(.jakarta(14)).foregroundStyle(Palette.text)
                Text(Dates.ago(m.created)).font(.jakarta(11)).foregroundStyle(Palette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.danger.opacity(0.25), lineWidth: 1))
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 50) }
                if !mine {
                    if m.fromTeam {
                        Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Theme.gradient, in: Circle())
                    } else {
                        Avatar(url: person?.picture ?? ticket?.picture ?? "", name: person?.displayName ?? ticket?.name ?? "", size: 28)
                    }
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    if !mine && m.fromTeam {
                        Text(team ? m.authorName : "Sugerly Team").font(.jakarta(11, .heavy)).foregroundStyle(Theme.main)
                    }
                    if !m.imageURL.isEmpty {
                        RemoteImage(url: m.imageURL)
                            .frame(width: 200, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if !m.text.isEmpty {
                        Text(m.text).font(.jakarta(15)).foregroundStyle(mine ? .white : Palette.text)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background {
                                if mine { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.gradient) }
                                else { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface) }
                            }
                            .overlay { if !mine { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1) } }
                            .textSelection(.enabled)
                    }
                    Text(m.pending ? "Sending…" : Dates.time(m.created)).font(.jakarta(10, .medium)).foregroundStyle(Palette.muted)
                }
                if !mine { Spacer(minLength: 50) }
            }
            .opacity(m.pending ? 0.7 : 1)
        }
    }

    private var canSend: Bool { !sending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil) }

    private var composer: some View {
        VStack(spacing: 8) {
            if let photo {
                HStack {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { withAnimation(.snappy) { self.photo = nil } } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20).background(.black.opacity(0.6), in: Circle())
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove picture")
                        }
                    Spacer()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $picked, matching: .images) {
                    Image(systemName: "photo.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.main)
                        .frame(width: 42, height: 42).background(Theme.soft, in: Circle())
                }
                .accessibilityLabel("Add a screenshot")
                TextField(team ? "Reply as Sugerly Team…" : (topic?.hint ?? "Write to the Sugerly team…"), text: $draft, axis: .vertical)
                    .font(.jakarta(15))
                    .lineLimit(1...5)
                    .focused($typing)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                SendButton(enabled: canSend) { Task { await send() } }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(.snappy, value: photo != nil)
    }

    private func load() async {
        async let t = try? FS.get("SupportTicket", ticketId)
        let docs = (try? await FS.query("SupportMessage", [.equals("ticket_id", ticketId)], limit: 500)) ?? []
        let fresh = docs.map(SupportMessage.init).sorted { $0.created < $1.created }
        let doc = await t
        let pending = messages.filter { m in m.pending && !fresh.contains(where: { f in f.text == m.text && f.fromTeam == m.fromTeam }) }
        if fresh.map(\.id) + pending.map(\.id) != messages.map(\.id) { messages = fresh + pending }
        if let doc = doc ?? nil {
            let next = SupportTicket(doc)
            if next != ticket { ticket = next }
            // Opened: it's read now.
            if team && next.teamUnread { try? await FS.update("SupportTicket", ticketId, ["team_unread": false]) }
            if !team && next.userUnread { try? await FS.update("SupportTicket", ticketId, ["user_unread": false]) }
        }
        loaded = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        if !text.isEmpty, !team, !(await TextGuard.clear([text], kind: .message, model: model)) { return }
        sending = true
        defer { sending = false }
        let image = photo
        var temp = SupportMessage(["id": "pending-\(UUID().uuidString)", "ticket_id": ticketId, "text": text, "from_team": team, "created_date": FS.nowISO()])
        temp.pending = true
        withAnimation(.snappy) { messages.append(temp); draft = ""; photo = nil }
        do {
            var url = ""
            if let image, let data = ImageTools.jpeg(image, maxSide: 1600) {
                url = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
            try await Support.send(to: ticketId, text: text, imageURL: url, fromTeam: team, topic: messages.count <= 1 ? topic?.title : nil,
                                   owner: team ? (name: person?.displayName ?? ticket?.name ?? "", picture: person?.picture ?? ticket?.picture ?? "") : nil, model: model)
            topic = nil
            await load()
            messages.removeAll { $0.id == temp.id }
        } catch {
            withAnimation(.snappy) { messages.removeAll { $0.id == temp.id }; draft = text; photo = image }
            model.showToast("Couldn't send — \(error.localizedDescription)", error: true)
        }
    }

    private func setSolved(_ solved: Bool) async {
        try? await FS.update("SupportTicket", ticketId, ["status": solved ? "solved" : "open", "updated_date": FS.nowISO()])
        if solved, let me = model.me {
            Notify.send(to: ticketId, from: me, type: "support", message: "Sugerly Team marked your question as solved", link: "/Support")
        }
        await load()
    }
}

// MARK: - Your reports and what happened to them

struct MyReportsView: View {
    @Environment(AppModel.self) private var model
    @State private var reports: [Doc] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if loading { ForEach(0..<4, id: \.self) { _ in SkeletonRow() } }
                if !loading && reports.isEmpty {
                    EmptyCard(icon: "checkmark.seal.fill", title: "No reports", text: "When you report something, you can follow it here. Reports are private — nobody is told who sent them.")
                        .padding(.top, 30)
                }
                ForEach(reports.indices, id: \.self) { i in
                    ReportStatusCard(report: reports[i])
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        defer { loading = false }
        guard let me = model.me?.email else { return }
        let docs = (try? await FS.query("Report", [.equals("reporter_email", me)], limit: 200)) ?? []
        let mine = docs.filter { $0.str("target_type") != "support" }.sorted { $0.str("created_date") > $1.str("created_date") }
        withAnimation(.snappy) { reports = mine }
    }
}

struct ReportStatusCard: View {
    let report: Doc

    private var state: (String, String, Color) {
        guard report.str("status") == "resolved" else { return ("Under review", "hourglass", Color(hex: 0xF0A020)) }
        switch report.str("resolution") {
        case "Content removed": return ("Removed", "checkmark.shield.fill", Palette.success)
        case "Warned": return ("Owner warned", "exclamationmark.bubble.fill", Palette.success)
        default: return ("Reviewed — no rule broken", "checkmark.circle", Palette.muted)
        }
    }

    var body: some View {
        let s = state
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(report.str("target_type").capitalized).font(.jakarta(11, .heavy)).foregroundStyle(Theme.main)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.soft, in: Capsule())
                Spacer()
                Label(s.0, systemImage: s.1).font(.jakarta(11, .heavy)).foregroundStyle(s.2)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(s.2.opacity(0.12), in: Capsule())
            }
            HStack(alignment: .top, spacing: 10) {
                let media = report.str("target_media")
                if !media.isEmpty, !media.lowercased().contains(".m4a"), !media.lowercased().contains(".mp4") {
                    AnimatedThumb(url: media, fill: true, maxPixel: 200, maxFrames: 20)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !report.str("target_preview").isEmpty {
                        Text("“\(report.str("target_preview"))”").font(.jakarta(14)).foregroundStyle(Palette.text).lineLimit(3)
                    }
                    Text("\(report.str("reason")) · \(Dates.ago(report.str("created_date")))").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
            }
            if report.str("status") == "resolved", !report.str("note").isEmpty {
                Text(report.str("note")).font(.jakarta(13)).foregroundStyle(Palette.text2)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }
}

// MARK: - Admin inbox

struct SupportInbox: View {
    @Environment(AppModel.self) private var model
    @State private var tickets: [SupportTicket] = []
    @State private var filter = "Open"
    @State private var loading = true

    private var shown: [SupportTicket] {
        let list: [SupportTicket]
        switch filter {
        case "Open": list = tickets.filter { !$0.solved }
        case "Solved": list = tickets.filter(\.solved)
        default: list = tickets
        }
        return list.sorted { ($0.teamUnread ? 1 : 0, $0.updated) > ($1.teamUnread ? 1 : 0, $1.updated) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["Open", "Solved", "All"], id: \.self) { f in
                    let count = f == "Open" ? tickets.filter { !$0.solved && $0.teamUnread }.count : 0
                    Chip(title: count > 0 ? "\(f) · \(count) new" : f, icon: f == "Open" ? "tray.full.fill" : f == "Solved" ? "checkmark.seal.fill" : "square.stack.fill", active: filter == f) {
                        withAnimation(.snappy) { filter = f }
                    }
                }
            }
            if loading { ForEach(0..<4, id: \.self) { _ in SkeletonRow() } }
            if !loading && shown.isEmpty {
                EmptyCard(icon: "checkmark.seal.fill", title: "Inbox zero", text: "No one needs help right now.", compact: true)
            }
            ForEach(shown) { t in
                NavigationLink(value: Route.supportTicket(t.id)) {
                    HStack(spacing: 12) {
                        Avatar(url: model.person(t.email)?.picture ?? t.picture, name: t.name, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(model.person(t.email)?.displayName ?? (t.name.isEmpty ? t.email : t.name)).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                                if !t.topic.isEmpty {
                                    Text(t.topic).font(.jakarta(10, .heavy)).foregroundStyle(Theme.main)
                                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.soft, in: Capsule()).lineLimit(1)
                                }
                            }
                            Text((t.lastFromTeam ? "You: " : "") + t.last).font(.jakarta(13, t.teamUnread ? .bold : .regular))
                                .foregroundStyle(t.teamUnread ? Palette.text : Palette.muted).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(Dates.ago(t.updated)).font(.jakarta(11)).foregroundStyle(Palette.muted)
                            if t.teamUnread { Circle().fill(Theme.main).frame(width: 10, height: 10) }
                            else if t.solved { Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Palette.success) }
                        }
                    }
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(t.teamUnread ? Theme.main.opacity(0.5) : Palette.border, lineWidth: t.teamUnread ? 1.5 : 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.98))
            }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("SupportTicket", orderBy: "updated_date", limit: 300) else { return }
        let fresh = docs.map(SupportTicket.init)
        if fresh != tickets { withAnimation(.snappy) { tickets = fresh } }
    }
}

// An admin answering one person.
struct SupportTicketView: View {
    let email: String
    var body: some View {
        SupportChatView(ticketEmail: email, team: true)
            .sugarBackground()
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
    }
}
