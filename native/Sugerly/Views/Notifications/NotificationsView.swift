import SwiftUI
import UIKit

// Notifications: a page of its own (the bell in the top bar), laid out like
// a social app. Tabs along the top, then Today / This week / Earlier; each
// row has a big coloured icon for what happened, the faces of who did it,
// their names in bold, and what they said or liked. Likes on the same thing
// come together in one row ("Mia and 3 others liked your post").
struct NotificationsPage: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @Environment(PostsStore.self) private var posts
    @State private var filter = "all"

    private let filters: [(String, String)] = [("all", "All"), ("like", "Likes"), ("comment", "Comments"), ("follow", "Follows"), ("mention", "Mentions")]

    private var shown: [AppNotification] {
        let hidden = Set((model.me?.ignored ?? []) + (model.me?.blocked ?? []))
        return byType.filter { !hidden.contains($0.fromEmail) }
    }

    private var byType: [AppNotification] {
        switch filter {
        case "like": return notes.items.filter { $0.type == "like" }
        case "comment": return notes.items.filter { $0.type == "comment" || $0.type == "reply" }
        case "follow": return notes.items.filter { $0.type == "follow" }
        case "mention": return notes.items.filter { $0.type == "mention" }
        default: return notes.items
        }
    }

    // Likes on the same thing collapse into one row ("Mia and 3 others liked…").
    struct Bundle: Identifiable {
        var items: [AppNotification]
        var id: String { items[0].id }
        var first: AppNotification { items[0] }
        var unread: Bool { items.contains { !$0.read } }
    }

    // Today / This week / Earlier.
    private var groups: [(String, [Bundle])] {
        let now = Date()
        var buckets: [String: [AppNotification]] = [:]
        for n in shown {
            let age = now.timeIntervalSince(Dates.parse(n.created) ?? now)
            let key = age < 86_400 ? "Today" : age < 7 * 86_400 ? "This week" : "Earlier"
            buckets[key, default: []].append(n)
        }
        return ["Today", "This week", "Earlier"].compactMap { (key: String) -> (String, [Bundle])? in
            guard let list = buckets[key], !list.isEmpty else { return nil }
            var bundles: [Bundle] = []
            var index: [String: Int] = [:]
            for n in list {
                if n.type == "like", !n.link.isEmpty, let i = index[n.link] {
                    bundles[i].items.append(n)
                } else {
                    if n.type == "like" && !n.link.isEmpty { index[n.link] = bundles.count }
                    bundles.append(Bundle(items: [n]))
                }
            }
            return (key, bundles)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    content
                } header: {
                    UnderlineTabs(items: filters, selection: $filter)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .appearFade()
        .background { Palette.surface.ignoresSafeArea() }
        .roundTitle("Notifications")
        .toolbar {
            if notes.unread > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation(.snappy) { notes.markAllRead() } } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("Mark all as read")
                }
            }
        }
        .refreshable { await notes.refresh(me: model.me?.email ?? "") }
        .animation(.snappy, value: filter)
        .onDisappear { notes.markAllRead() }
    }

    @ViewBuilder
    private var content: some View {
        if shown.isEmpty {
            EmptyCard(icon: "bell.fill", title: "All quiet here",
                      text: filter == "all" ? "When someone likes, follows, comments or mentions you, it shows up here." : "Nothing like this yet.",
                      mood: .sleepy)
                .padding(16)
        }
        ForEach(groups, id: \.0) { group in
            Text(group.0)
                .font(.display(19)).foregroundStyle(Palette.text)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(group.1) { b in
                tappable(b)
                    .transition(.opacity)
            }
        }
        if !shown.isEmpty && notes.hasOlder {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.main)
                Text("Loading older").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .onAppear { Task { await notes.loadOlder(me: model.me?.email ?? "") } }
        }
    }

    // MARK: a row

    private func row(_ b: Bundle) -> some View {
        let n = b.first
        let words = headline(b)
        return HStack(alignment: .top, spacing: 12) {
            // What happened, as a big coloured icon (like a social app).
            Image(systemName: icon(n.type))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LinearGradient(colors: tint(n.type), startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 7) {
                topLine(b)
                sentence(words.names, words.rest)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let quote = words.quote, !quote.isEmpty {
                    Text(quote)
                        .font(.jakarta(14)).foregroundStyle(Palette.text2)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if n.type == "follow" && !n.fromEmail.isEmpty {
                    FollowButton(email: n.fromEmail, compact: true)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(b.unread ? Theme.main.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1).allowsHitTesting(false) }
    }

    // A row lights up pink and squishes a little while you press it.
    @ViewBuilder
    private func tappable(_ b: Bundle) -> some View {
        if b.first.type == "follow" && !b.first.fromEmail.isEmpty {
            row(b)
                .contentShape(Rectangle())
                .onTapGesture { open(b) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(b) }
        } else {
            Button { open(b) } label: { row(b) }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .combine)
        }
    }

    // The faces on the left; how long ago (and a pink dot if it's new) on the right.
    private func topLine(_ b: Bundle) -> some View {
        HStack(spacing: 8) {
            faces(b)
            Spacer(minLength: 4)
            Text(Dates.ago(b.first.created))
                .font(.jakarta(12, .semibold))
                .foregroundStyle(b.unread ? Theme.main : Palette.muted)
            if b.unread {
                Circle().fill(Theme.main).frame(width: 8, height: 8)
            }
        }
    }

    private func sentence(_ names: String, _ rest: String) -> Text {
        let bold = Text(names).font(.jakarta(15, .heavy)).foregroundColor(Palette.text)
        let plain = Text(rest).font(.jakarta(15)).foregroundColor(Palette.text)
        return bold + plain
    }

    // Up to six faces of who did it, overlapping a little.
    private func faces(_ b: Bundle) -> some View {
        var seen = Set<String>()
        var people: [AppNotification] = []
        for item in b.items where !seen.contains(item.fromEmail) {
            seen.insert(item.fromEmail)
            people.append(item)
        }
        return HStack(spacing: -8) {
            ForEach(people.prefix(6), id: \.id) { item in
                Avatar(url: model.person(item.fromEmail)?.picture ?? item.fromPicture, name: item.fromName, size: 32)
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
            }
        }
    }

    // Who (in bold), what they did, and what they said or liked.
    private func headline(_ b: Bundle) -> (names: String, rest: String, quote: String?) {
        let n = b.first
        let name = model.name(n.fromEmail, n.fromName.isEmpty ? "Someone" : n.fromName)
        if b.items.count > 1 {
            let others = Set(b.items.map(\.fromEmail)).count - 1
            let what = n.link.contains("Reels") ? "your reel" : n.link.contains("Gallery") ? "your artwork" : "your post"
            let rest = others > 0 ? " and \(others) other\(others == 1 ? "" : "s") liked \(what)" : " liked \(what)"
            return (name, rest, likedPost(n))
        }
        var rest = n.message
        var names = ""
        for prefix in [n.fromName, name] where !prefix.isEmpty && rest.hasPrefix(prefix) {
            names = name
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        var quote: String?
        if ["comment", "reply", "support"].contains(n.type), let r = rest.range(of: ": ") {
            quote = String(rest[r.upperBound...])
            rest = String(rest[..<r.lowerBound])
        } else if n.type == "like" {
            quote = likedPost(n)
        }
        return (names, rest, quote)
    }

    // The words of the post that was liked (when it's loaded).
    private func likedPost(_ n: AppNotification) -> String? {
        guard n.link.lowercased().hasPrefix("/community"),
              let id = URLComponents(string: n.link)?.queryItems?.first(where: { $0.name == "post" })?.value,
              let post = posts.posts.first(where: { $0.id == id }) else { return nil }
        let words = post.title.isEmpty ? post.text : post.title
        return words.isEmpty ? nil : words
    }

    private func open(_ b: Bundle) {
        notes.markRead(b.items.map(\.id))
        go(b.first)
    }

    private func tint(_ type: String) -> [Color] {
        switch type {
        case "like": return [Color(hex: 0xFF7AA2), Color(hex: 0xE0406F)]
        case "follow": return [Color(hex: 0xB19CFF), Color(hex: 0x7C5CF0)]
        case "comment", "reply": return [Color(hex: 0x7CBEFF), Color(hex: 0x2F80E0)]
        case "mention": return [Color(hex: 0x5FD3B0), Color(hex: 0x16A37F)]
        case "message": return [Color(hex: 0x5FD3B0), Color(hex: 0x16A37F)]
        case "commission": return [Color(hex: 0xFFD166), Color(hex: 0xF0A020)]
        default: return [Theme.light, Theme.main]
        }
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "like": return "heart.fill"
        case "follow": return "person.fill"
        case "comment", "reply": return "bubble.left.fill"
        case "mention": return "at"
        case "message": return "paperplane.fill"
        case "commission": return "storefront.fill"
        case "support": return "questionmark.bubble.fill"
        default: return "sparkles"
        }
    }

    // Links are website paths; open the matching screen.
    private func go(_ n: AppNotification) {
        guard let comps = URLComponents(string: n.link) else { return }
        let value = { (name: String) in comps.queryItems?.first { $0.name == name }?.value ?? "" }
        switch comps.path.lowercased() {
        case "/community":
            let id = value("post")
            if let post = posts.posts.first(where: { $0.id == id }) { path.append(.post(post)) }
            else if !id.isEmpty { Task { if let doc = try? await FS.get("CommunityPost", id) { path.append(.post(Post(doc))) } } }
        case "/profile":
            let email = value("email")
            if !email.isEmpty { path.append(.person(email)) }
        case "/gallery":
            let id = value("art")
            if !id.isEmpty { Task { if let doc = try? await FS.get("Artwork", id) { path.append(.artwork(Artwork(doc))) } } }
        case "/commissions":
            let id = value("order")
            path.append(id.isEmpty ? .commissions : .commissionOrder(id))
        case "/support":
            let ticket = value("ticket")
            path.append(ticket.isEmpty ? .support : .supportTicket(ticket))
        case "/reels":
            let id = value("r")
            if !id.isEmpty { Task { if let doc = try? await FS.get("Reel", id) { path.append(.reel(Reel(doc))) } } }
        default:
            if !n.fromEmail.isEmpty { path.append(.person(n.fromEmail)) }
        }
    }
}

// MARK: - Admin panel

// Site-wide colours the admin can set (stored in SiteConfig on the website).
@MainActor
@Observable
final class SiteTheme {
    static let shared = SiteTheme()
    var primary: UInt32?
    var secondary: UInt32?
    var configId: String?
    var announcement = ""
    var announcementActive = false
    var announcementColor: UInt32 = 0xD9577F
    var defaultAccent = "rose"
    var giphyKey = ""
    // Sugerly's cut of each paid commission, in percent.
    var commissionFee: Double = 10
    // Admin-picked weekly challenges and daily art prompts (nil = built-ins).
    var challenges: [Challenge]?
    var challengePinned = ""
    var prompts: [ArtPrompt]?
    var promptPinned = ""

    func load() async {
        guard let docs = try? await FS.query("SiteConfig", [.equals("key", "global")], limit: 1), let doc = docs.first else { return }
        configId = doc.str("id")
        primary = Self.hex(doc.str("app_primary"))
        secondary = Self.hex(doc.str("app_secondary"))
        announcement = doc.str("announcement")
        announcementActive = doc.bool("announcement_active")
        announcementColor = Self.hex(doc.str("announcement_color")) ?? 0xD9577F
        defaultAccent = doc.str("default_accent").isEmpty ? "rose" : doc.str("default_accent")
        giphyKey = doc.str("giphy_key")
        commissionFee = ReelText.num(doc["commission_fee_percent"]) ?? 10
        if let list = doc["challenges"] as? [Any] {
            challenges = list.compactMap { ($0 as? Doc).flatMap { Challenge($0) } }
        }
        challengePinned = doc.str("challenge_pinned")
        if let list = doc["prompts"] as? [Any] {
            prompts = list.compactMap { ($0 as? Doc).flatMap { ArtPrompt($0) } }
        }
        promptPinned = doc.str("prompt_pinned")
    }

    // Writes a few fields to the shared SiteConfig doc (creating it if needed).
    func save(_ fields: Doc) async throws {
        var fields = fields
        fields["updated_date"] = FS.nowISO()
        if let id = configId {
            try await FS.update("SiteConfig", id, fields)
        } else {
            var doc = fields
            doc["key"] = "global"
            doc["created_date"] = FS.nowISO()
            let created = try await FS.create("SiteConfig", doc)
            configId = created.str("id")
        }
    }

    nonisolated static func hex(_ s: String) -> UInt32? {
        let clean = s.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard clean.count == 6, let v = UInt32(clean, radix: 16) else { return nil }
        return v
    }

    nonisolated static func string(_ v: UInt32) -> String { String(format: "#%06X", v) }
}

struct AdminView: View {
    enum Tab: String, CaseIterable {
        case overview = "Overview", users = "Users", content = "Content", servers = "Servers", reports = "Reports", support = "Support", colors = "Site"
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .users: return "person.2.fill"
            case .content: return "photo.stack.fill"
            case .servers: return "server.rack"
            case .reports: return "flag.fill"
            case .support: return "lifepreserver.fill"
            case .colors: return "paintpalette.fill"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .overview
    @State private var data = AdminData()
    @State private var search = ""
    @State private var contentType = "All"
    @State private var confirmDelete: AdminItem?
    @State private var confirmRole: UserProfile?
    @State private var managing: String?
    @State private var announcement = ""
    @State private var announcementOn = false
    @State private var giphyKey = ""
    @State private var commissionFee = "10"
    @State private var announcementColor = Color(hex: 0xD9577F)
    @State private var defaultAccent = "rose"
    @State private var editChallenges = false
    @State private var editPrompts = false
    @State private var reports: [Doc] = []
    @State private var reportFilter = "Open"
    @State private var loading = true
    @State private var primary = Color(hex: 0xD9577F)
    @State private var secondary = Color(hex: 0xEE8FAE)
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?

    private let presets: [(String, UInt32, UInt32)] = [
        ("Bubblegum", 0xD9577F, 0xEE8FAE), ("Candy", 0xFF4D8D, 0xFFB3D1), ("Lilac", 0x7C5CF0, 0xB19CFF),
        ("Mint", 0x16A37F, 0x5FD3B0), ("Peach", 0xEE6E40, 0xFFAA80), ("Sky", 0x2F80E0, 0x7CBEFF),
        ("Cherry", 0xC81D4E, 0xFF7A9C), ("Sunset", 0xF0560A, 0xFFB347),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xF0A020)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MISSION CONTROL").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                        Text("Admin panel").font(.display(32)).foregroundStyle(Palette.text)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Chip(title: t.rawValue, icon: t.icon, active: tab == t) { withAnimation(.snappy) { tab = t; search = "" } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                switch tab {
                case .overview: overview
                case .users: users
                case .content: contentList
                case .servers: serverList
                case .reports: reportsList
                case .support: SupportInbox()
                case .colors:
                    siteSettings
                    colors
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await data.load(); await loadReports() }
        .task {
            async let everything: Void = data.load()
            await loadReports()
            await SiteTheme.shared.load()
            if let p = SiteTheme.shared.primary { primary = Color(hex: p) }
            if let s = SiteTheme.shared.secondary { secondary = Color(hex: s) }
            announcement = SiteTheme.shared.announcement
            announcementOn = SiteTheme.shared.announcementActive
            announcementColor = Color(hex: SiteTheme.shared.announcementColor)
            defaultAccent = SiteTheme.shared.defaultAccent
            giphyKey = SiteTheme.shared.giphyKey
            commissionFee = String(Int(SiteTheme.shared.commissionFee))
            if model.people.isEmpty { await model.loadPeople() }
            await everything
        }
        .confirmationDialog("Delete this \(confirmDelete?.label.lowercased() ?? "item")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = confirmDelete { Task { await remove(item) } }
            }
        }
        .confirmationDialog(confirmRole?.role == "admin" ? "Remove admin from \(confirmRole?.displayName ?? "")?" : "Make \(confirmRole?.displayName ?? "") an admin?",
                            isPresented: Binding(get: { confirmRole != nil }, set: { if !$0 { confirmRole = nil } }), titleVisibility: .visible) {
            Button("Confirm", role: confirmRole?.role == "admin" ? .destructive : nil) {
                if let u = confirmRole { Task { await setRole(u) } }
            }
        }
    }

    // MARK: overview

    private var overview: some View {
        let weekAgo = Dates.iso(Date().addingTimeInterval(-7 * 86_400))
        let people = Array(model.people.values)
        let online = people.filter(\.isOnline).count
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statCard("person.2.fill", "Members", "\(people.count)", "\(online) online", [0xFF7AA2, 0xD9577F])
                statCard("photo.stack.fill", "Posts & art", "\(data.posts.count + data.art.count)", "+\(data.items.filter { $0.date > weekAgo && ($0.label == "Post" || $0.label == "Artwork") }.count) this week", [0xFFAA80, 0xEE6E40])
                statCard("bubble.left.and.bubble.right.fill", "Messages", "\(data.items.filter { $0.label == "Message" || $0.label == "Comment" }.count)", "+\(data.items.filter { $0.date > weekAgo && ($0.label == "Message" || $0.label == "Comment") }.count) this week", [0xB19CFF, 0x7C5CF0])
                statCard("music.note", "Tracks & servers", "\(data.tracks.count + data.servers.count)", "\(data.reels.count) reels", [0x7CBEFF, 0x2F80E0])
            }
            activityChart
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest content").font(.display(22)).foregroundStyle(Palette.text)
                ForEach(data.items.prefix(8)) { item in
                    HStack(spacing: 10) {
                        Text(item.label).font(.jakarta(11, .heavy)).foregroundStyle(Theme.main)
                            .frame(width: 74).padding(.vertical, 4).background(Theme.soft, in: Capsule())
                        Text(item.title.isEmpty ? "—" : item.title).font(.jakarta(13)).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer()
                        Text(Dates.ago(item.date)).font(.jakarta(11)).foregroundStyle(Palette.muted)
                    }
                }
            }
            .sugarCard(radius: 22, padding: 14)
        }
    }

    private func statCard(_ icon: String, _ label: String, _ value: String, _ sub: String, _ colors: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(value).font(.display(30)).foregroundStyle(Palette.text).contentTransition(.numericText())
            Text(label.uppercased()).font(.jakarta(10, .heavy)).tracking(0.8).foregroundStyle(Palette.muted)
            Text(sub).font(.jakarta(11, .semibold)).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
    }

    // New content per day for the last 14 days.
    private var activityChart: some View {
        let cal = Calendar.current
        let days: [Date] = (0..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
        var counts: [Int] = Array(repeating: 0, count: days.count)
        for item in data.items {
            guard let d = Dates.parse(item.date) else { continue }
            let start = cal.startOfDay(for: d)
            if let i = days.firstIndex(of: start) { counts[i] += 1 }
        }
        let top = max(1, counts.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Activity · 14 days").font(.display(22)).foregroundStyle(Palette.text)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.gradient)
                            .frame(height: max(4, 110 * CGFloat(counts[i]) / CGFloat(top)))
                        Text(days[i].formatted(.dateTime.day())).font(.jakarta(9, .semibold)).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .sugarCard(radius: 22, padding: 14)
    }

    // MARK: users

    private var users: some View {
        let rank: (UserProfile) -> Int = { u in FirebaseConfig.siteOwners.contains(u.email) ? 0 : (u.role == "admin" ? 1 : 2) }
        let list = model.people.values
            .filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) || $0.email.localizedCaseInsensitiveContains(search) }
            .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.displayName.lowercased() < $1.displayName.lowercased() }
        let owner = FirebaseConfig.siteOwners.contains(model.me?.email ?? "")
        return VStack(alignment: .leading, spacing: 10) {
            SearchField(text: $search, placeholder: "Search users…")
                .task(id: search) {
                    guard !search.isEmpty else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    _ = await model.searchPeople(search)
                    if search.contains("@"), let docs = try? await FS.prefix("User", field: "email", search.lowercased(), limit: 20) {
                        var map = model.people
                        for doc in docs { let u = UserProfile(doc); if !u.email.isEmpty { map[u.email] = u } }
                        model.people = map
                    }
                }
            Text("\(model.people.values.filter { rank($0) < 2 }.count) admins · Tap a name to give coins, MimiPlus or ban. \(owner ? "The shield makes or removes admins." : "")")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
            ForEach(Array(list.prefix(200))) { u in
                HStack(spacing: 12) {
                    NavigationLink(value: Route.person(u.email)) {
                        Avatar(url: u.picture, name: u.displayName, size: 42, online: u.isOnline)
                    }
                    Button { managing = u.email } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(u.displayName).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                if u.isBanned {
                                    Text("banned").font(.jakarta(9, .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.danger, in: Capsule())
                                }
                            }
                            Text("\(u.email) · \(u.coins) coins\(u.isNitro ? " · MimiPlus" : "")").font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SoftPressStyle())
                    Text(FirebaseConfig.siteOwners.contains(u.email) ? "owner" : (u.role.isEmpty ? "user" : u.role))
                        .font(.jakarta(10, .heavy)).foregroundStyle(rank(u) < 2 ? Theme.main : Palette.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(rank(u) < 2 ? Theme.soft : Palette.surface2, in: Capsule())
                    if owner && u.email != model.me?.email && !FirebaseConfig.siteOwners.contains(u.email) {
                        Button { confirmRole = u } label: {
                            Image(systemName: u.role == "admin" ? "shield.slash.fill" : "checkmark.shield.fill")
                                .foregroundStyle(u.role == "admin" ? Palette.danger : Palette.success)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                .sugarCard(radius: 18, padding: 10)
            }
        }
        .sheet(item: Binding(get: { managing.map { ManagedUser(id: $0) } }, set: { managing = $0?.id })) { m in
            AdminUserSheet(email: m.id).presentationCornerRadius(30)
        }
    }

    struct ManagedUser: Identifiable { var id: String }

    private func setRole(_ u: UserProfile) async {
        let next = u.role == "admin" ? "user" : "admin"
        do {
            try await FS.update("User", u.id, ["role": next, "updated_date": FS.nowISO()])
            _ = try? await FS.create("Log", ["action": "role_change", "details": "\(u.email) → \(next)", "user_email": model.me?.email ?? ""])
            await model.loadPeople()
            model.showToast("Role updated", icon: "shield.fill")
        } catch {
            model.showToast("Couldn't change role — \(error.localizedDescription)", error: true)
        }
    }

    // MARK: content

    private var contentList: some View {
        let types = ["All", "Post", "Artwork", "Track", "Reel", "Comment", "Message"]
        let list = data.items.filter { (contentType == "All" || $0.label == contentType) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.owner.localizedCaseInsensitiveContains(search)) }
        return VStack(alignment: .leading, spacing: 10) {
            SearchField(text: $search, placeholder: "Search content…")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(types, id: \.self) { t in
                        Chip(title: t, active: contentType == t) { contentType = t }
                    }
                }
            }
            if data.loading && data.items.isEmpty { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
            ForEach(Array(list.prefix(150))) { item in
                HStack(spacing: 12) {
                    if !item.image.isEmpty {
                        RemoteImage(url: item.image).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "text.alignleft").foregroundStyle(Theme.main).frame(width: 48, height: 48).background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "(no text)" : item.title).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text).lineLimit(2)
                        Text("\(item.label) · \(item.owner) · \(Dates.ago(item.date))").font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer()
                    Button { confirmDelete = item } label: {
                        Image(systemName: "trash.fill").foregroundStyle(Palette.danger).frame(width: 36, height: 36).background(Palette.danger.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(BouncyStyle())
                }
                .sugarCard(radius: 18, padding: 10)
            }
        }
    }

    private func remove(_ item: AdminItem) async {
        do {
            try await FS.delete(item.collection, item.id)
            _ = try? await FS.create("Log", ["action": "moderation_delete", "details": "Deleted \(item.label.lowercased()) \(item.id)", "user_email": model.me?.email ?? ""])
            withAnimation(.snappy) { data.items.removeAll { $0.id == item.id && $0.collection == item.collection } }
            if item.collection == "Community" { data.servers.removeAll { $0.id == item.id } }
            model.showToast("\(item.label) deleted", icon: "trash.fill")
        } catch {
            model.showToast("Couldn't delete — \(error.localizedDescription)", error: true)
        }
        confirmDelete = nil
    }

    // MARK: servers

    private var serverList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(data.servers) { server in
                HStack(spacing: 12) {
                    ServerIcon(server: server, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                        Text("\(server.members.count) members · owner \(model.person(server.ownerEmail)?.displayName ?? server.ownerEmail)").font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer()
                    Button { confirmDelete = AdminItem(collection: "Community", label: "Server", id: server.id, title: server.name, owner: server.ownerEmail, date: "", image: server.iconURL) } label: {
                        Image(systemName: "trash.fill").foregroundStyle(Palette.danger).frame(width: 36, height: 36).background(Palette.danger.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(BouncyStyle())
                }
                .sugarCard(radius: 18, padding: 10)
            }
            if data.servers.isEmpty && !data.loading { EmptyCard(icon: "server.rack", title: "No servers", text: "Servers people create show up here.") }
        }
    }

    // MARK: site settings

    private var siteSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Announcement banner").font(.display(22)).foregroundStyle(Palette.text)
            SugarField(placeholder: "e.g. Art jam this Saturday in the Music Lounge!", text: $announcement)
            HStack {
                Toggle(isOn: $announcementOn) { Text("Show banner").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text) }
                    .tint(Theme.main)
                ColorPicker("", selection: $announcementColor, supportsOpacity: false).labelsHidden()
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Default accent for new members").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            HStack(spacing: 8) {
                ForEach(Accent.allCases) { a in
                    Button { defaultAccent = a.rawValue } label: {
                        Circle().fill(a.gradient).frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(.white, lineWidth: defaultAccent == a.rawValue ? 3 : 0))
                            .shadow(color: a.main.opacity(defaultAccent == a.rawValue ? 0.5 : 0), radius: 6)
                    }
                    .buttonStyle(BouncyStyle())
                }
            }
            Text("GIFs").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            SugarField(placeholder: "GIPHY API key (empty = built-in key)", text: $giphyKey)
            Text("Commissions").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            HStack(spacing: 10) {
                SugarField(placeholder: "Fee", text: $commissionFee).keyboardType(.numberPad).frame(width: 90)
                Text("% Sugerly keeps from each paid commission (0–50). Artists get the rest.").font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            Button { Task { await saveSite() } } label: { Label("Save site settings", systemImage: "checkmark") }
                .buttonStyle(GradientButtonStyle(height: 46))
            Text("Community").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            // One full-width row each (side by side, the names wrapped onto
            // two lines and the icons floated at the top).
            VStack(spacing: 8) {
                adminLink("Weekly challenges", "The themes everyone draws this week", "trophy.fill", [0xFFD166, 0xF0A020]) { editChallenges = true }
                adminLink("Daily prompts", "A new idea to draw each day", "paintpalette.fill", [0xFF9EC4, 0xE0508A]) { editPrompts = true }
            }
            .sheet(isPresented: $editChallenges) { DailyContentEditor(kind: .challenges).presentationCornerRadius(30) }
            .sheet(isPresented: $editPrompts) { DailyContentEditor(kind: .prompts).presentationCornerRadius(30) }
            Divider().padding(.vertical, 6)
            Text("App colours").font(.display(22)).foregroundStyle(Palette.text)
        }
    }

    private func adminLink(_ title: String, _ detail: String, _ icon: String, _ colors: [UInt32], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconRow(title: title, detail: detail, icon: icon, colors: colors, chevron: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .sugarCard(radius: 18)
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private func saveSite() async {
        let fields: Doc = [
            "announcement": String(announcement.prefix(160)), "announcement_active": announcementOn,
            "announcement_color": SiteTheme.string(hexValue(announcementColor)), "default_accent": defaultAccent,
            "giphy_key": giphyKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "commission_fee_percent": min(50, max(0, Double(commissionFee) ?? 10)),
            "updated_date": FS.nowISO(),
        ]
        do {
            if let id = SiteTheme.shared.configId {
                try await FS.update("SiteConfig", id, fields)
            } else {
                var doc = fields
                doc["key"] = "global"
                let created = try await FS.create("SiteConfig", doc)
                SiteTheme.shared.configId = created.str("id")
            }
            SiteTheme.shared.announcement = announcement
            SiteTheme.shared.announcementActive = announcementOn
            SiteTheme.shared.announcementColor = hexValue(announcementColor)
            SiteTheme.shared.defaultAccent = defaultAccent
            SiteTheme.shared.giphyKey = giphyKey.trimmingCharacters(in: .whitespacesAndNewlines)
            model.showToast("Site settings saved", icon: "checkmark.seal.fill")
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }

    // MARK: reports

    private struct ReportGroup: Identifiable {
        var id: String
        var reports: [Doc]
        var first: Doc { reports[0] }
        var open: Bool { reports.contains { $0.str("status") != "resolved" } }
        var urgent: Bool { reports.contains { $0.bool("urgent") } }
    }

    // Reports about the same thing are shown together, urgent ones first.
    private var reportGroups: [ReportGroup] {
        var order: [String] = []
        var map: [String: [Doc]] = [:]
        for r in reports {
            let key = r.str("target_type") == "support" ? "support:" + r.str("id") : r.str("target_type") + ":" + r.str("target_id")
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(r)
        }
        let groups = order.map { ReportGroup(id: $0, reports: map[$0] ?? []) }.filter { !$0.reports.isEmpty }
        switch reportFilter {
        case "Open": return groups.filter(\.open).sorted { $0.urgent && !$1.urgent }
        case "Urgent": return groups.filter { $0.open && $0.urgent }
        case "Done": return groups.filter { !$0.open }
        default: return groups
        }
    }

    private var reportsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["Open", "Urgent", "Done", "All"], id: \.self) { f in
                    Chip(title: f, icon: f == "Urgent" ? "exclamationmark.triangle.fill" : f == "Done" ? "checkmark.seal.fill" : f == "Open" ? "tray.full.fill" : "square.stack.fill", active: reportFilter == f) {
                        withAnimation(.snappy) { reportFilter = f }
                    }
                }
            }
            if loading { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
            if !loading && reportGroups.isEmpty {
                EmptyCard(icon: "checkmark.seal.fill", title: reportFilter == "Done" ? "Nothing yet" : "All clear", text: "When people report posts, comments, messages or accounts, they show up here.", compact: true)
            }
            ForEach(reportGroups) { g in
                reportCard(g).transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: reportGroups.map(\.id))
    }

    private func reportCard(_ g: ReportGroup) -> some View {
        let r = g.first
        let type = r.str("target_type")
        let owner = r.str("target_owner_email")
        let reporter = r.str("reporter_email")
        let reasons = Array(Set(g.reports.map { $0.str("reason") })).sorted()
        let media = r.str("target_media").lowercased()
        let removable = (r.str("target_collection").isEmpty ? collection(for: type) : r.str("target_collection")) != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if g.urgent {
                    Label("Urgent", systemImage: "exclamationmark.triangle.fill").font(.jakarta(11, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Palette.danger, in: Capsule())
                }
                Text(type == "support" ? "HELP REQUEST" : type.uppercased()).font(.jakarta(11, .heavy)).foregroundStyle(Theme.main)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.soft, in: Capsule())
                if g.reports.count > 1 {
                    Text("\(g.reports.count) reports").font(.jakarta(11, .heavy)).foregroundStyle(Palette.danger)
                }
                Spacer()
                if !g.open {
                    Label(r.str("resolution").isEmpty ? "Resolved" : r.str("resolution"), systemImage: "checkmark").font(.jakarta(11, .bold)).foregroundStyle(Palette.success)
                } else {
                    Text(Dates.ago(r.str("created_date"))).font(.jakarta(11)).foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                if !media.isEmpty, !media.contains(".m4a"), !media.contains(".mp4"), !media.contains(".mov"), !media.contains("audio"), !media.contains("video") {
                    AnimatedThumb(url: r.str("target_media"), fill: true, maxPixel: 240, maxFrames: 30)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !r.str("target_preview").isEmpty {
                        Text("“\(r.str("target_preview"))”").font(.jakarta(14)).foregroundStyle(Palette.text).lineLimit(4)
                    }
                    if type != "support", !owner.isEmpty {
                        Text("By \(model.person(owner)?.displayName ?? owner)").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2)
                    }
                }
            }
            if type != "support" {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(reasons, id: \.self) { reason in
                            Label(reason, systemImage: "flag.fill").font(.jakarta(11, .bold)).foregroundStyle(Palette.danger)
                                .padding(.horizontal, 9).padding(.vertical, 5).background(Palette.danger.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            ForEach(Array(g.reports.filter { !$0.str("details").isEmpty }.prefix(3).enumerated()), id: \.offset) { _, d in
                Text("“\(d.str("details"))” — \(d.str("reporter_name").isEmpty ? d.str("reporter_email") : d.str("reporter_name"))")
                    .font(.jakarta(13)).italic().foregroundStyle(Palette.text2).lineLimit(4)
            }
            Text(g.reports.count > 1 ? "Reported by \(Set(g.reports.map { $0.str("reporter_name") }).filter { !$0.isEmpty }.sorted().prefix(3).joined(separator: ", "))" : "By \(r.str("reporter_name").isEmpty ? reporter : r.str("reporter_name")) · \(Dates.ago(r.str("created_date")))")
                .font(.jakarta(11)).foregroundStyle(Palette.muted)
            if g.open {
                if type == "support" {
                    HStack(spacing: 8) {
                        NavigationLink(value: Route.supportTicket(reporter)) { Label("Reply in chat", systemImage: "bubble.left.and.bubble.right.fill") }
                            .buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
                        Button { Task { await resolve(g, action: "dismiss") } } label: { Label("Done", systemImage: "checkmark") }
                            .buttonStyle(OutlineButtonStyle(height: 38))
                    }
                } else {
                    HStack(spacing: 8) {
                        if removable {
                            Button { Task { await resolve(g, action: "remove") } } label: { Label("Remove", systemImage: "trash") }
                                .buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
                        }
                        if !owner.isEmpty {
                            Button { Task { await resolve(g, action: "warn") } } label: { Label("Warn", systemImage: "exclamationmark.bubble") }
                                .buttonStyle(OutlineButtonStyle(height: 38))
                        }
                        Button { Task { await resolve(g, action: "dismiss") } } label: { Label("Dismiss", systemImage: "checkmark") }
                            .buttonStyle(OutlineButtonStyle(height: 38))
                    }
                }
            }
            HStack(spacing: 14) {
                if type != "support", !owner.isEmpty {
                    NavigationLink(value: Route.supportTicket(owner)) { Label("Message owner", systemImage: "bubble.left.fill") }
                }
                if !reporter.isEmpty && type != "support" {
                    NavigationLink(value: Route.supportTicket(reporter)) { Label("Message reporter", systemImage: "bubble.right.fill") }
                }
            }
            .font(.jakarta(12, .bold))
            .foregroundStyle(Theme.main)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(g.urgent && g.open ? Palette.danger.opacity(0.5) : Palette.border, lineWidth: g.urgent && g.open ? 1.5 : 1))
        .opacity(g.open ? 1 : 0.65)
    }

    private func collection(for type: String) -> String? {
        switch type {
        case "post": return "CommunityPost"
        case "comment": return "CommunityComment"
        case "message": return "DirectMessage"
        case "reel": return "Reel"
        case "artwork": return "Artwork"
        case "track": return "MusicReview"
        default: return nil
        }
    }

    private func loadReports() async {
        defer { loading = false }
        guard let docs = try? await FS.query("Report", orderBy: "created_date", limit: 200) else { return }
        reports = docs.sorted { ($0.str("status") == "resolved" ? 1 : 0, $1.str("created_date")) < ($1.str("status") == "resolved" ? 1 : 0, $0.str("created_date")) }
    }

    // Remove: deletes it and tells the owner why. Warn: tells the owner but
    // keeps it. Dismiss: no rule broken. Everyone who reported it sees the
    // outcome in Help & support → My reports.
    private func resolve(_ g: ReportGroup, action: String) async {
        guard let me = model.me else { return }
        let first = g.first
        let type = first.str("target_type")
        let owner = first.str("target_owner_email")
        if action == "remove", let target = first.str("target_collection").isEmpty ? collection(for: type) : first.str("target_collection") {
            try? await FS.delete(target, first.str("target_id"))
        }
        let resolution = action == "remove" ? "Content removed" : action == "warn" ? "Warned" : type == "support" ? "Answered" : "Dismissed"
        let note = action == "remove" ? "Thanks for reporting — we removed it."
            : action == "warn" ? "Thanks for reporting — we warned the person who posted it."
            : "We checked and it doesn't break our rules. If it still bothers you, you can block them."
        let now = FS.nowISO()
        for r in g.reports where r.str("status") != "resolved" {
            try? await FS.update("Report", r.str("id"), ["status": "resolved", "resolution": resolution, "note": note, "resolved_by": me.email, "updated_date": now])
        }
        if action != "dismiss", !owner.isEmpty, owner.lowercased() != me.email.lowercased() {
            let reason = first.str("reason").lowercased()
            let what = type == "user" ? "profile" : type
            let text = action == "remove"
                ? "Hi! Your \(what) was removed because it went against our Community Guidelines (\(reason)). Please help keep Sugerly kind and safe — repeated problems can limit your account. If you think this was a mistake, just reply here."
                : "Hi! Your \(what) was reported for \(reason). Please have a look at our Community Guidelines — repeated problems can limit your account. If you have questions, just reply here."
            try? await Support.send(to: owner, text: text, fromTeam: true, kind: "notice", model: model)
        }
        let ids = Set(g.reports.map { $0.str("id") })
        withAnimation(.snappy) {
            for i in reports.indices where ids.contains(reports[i].str("id")) && reports[i].str("status") != "resolved" {
                reports[i]["status"] = "resolved"
                reports[i]["resolution"] = resolution
            }
        }
        model.showToast(action == "remove" ? "Removed and owner told" : action == "warn" ? "Owner warned" : "Dismissed", icon: "checkmark.seal.fill")
    }

    // MARK: colours

    private var colors: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Sugerly's colours for everyone. People who picked their own accent in Settings keep theirs.")
                .font(.jakarta(14)).foregroundStyle(Palette.text2)
            // Live preview
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview").font(.jakarta(12, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                HStack(spacing: 10) {
                    Text("Claim reward").font(.jakarta(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(LinearGradient(colors: [secondary, primary], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                        .shadow(color: primary.opacity(0.45), radius: 10, y: 5)
                    Text("Follow").font(.jakarta(14, .bold)).foregroundStyle(primary)
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(Capsule().strokeBorder(primary.opacity(0.35), lineWidth: 1.5))
                    Image(systemName: "heart.fill").font(.system(size: 24)).foregroundStyle(LinearGradient(colors: [secondary, primary], startPoint: .top, endPoint: .bottom))
                }
                Text("Good afternoon,").font(.display(28)).foregroundStyle(Palette.text)
                    + Text(" Sugerly").font(.display(28)).foregroundStyle(primary)
            }
            .sugarCard(radius: 24, padding: 16)

            Text("Presets").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                ForEach(presets, id: \.0) { name, p, s in
                    Button { withAnimation(.snappy) { primary = Color(hex: p); secondary = Color(hex: s) } } label: {
                        VStack(spacing: 6) {
                            Circle().fill(LinearGradient(colors: [Color(hex: s), Color(hex: p)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44).shadow(color: Color(hex: p).opacity(0.4), radius: 6, y: 3)
                            Text(name).font(.jakarta(11, .semibold)).foregroundStyle(Palette.text2)
                        }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.88))
                }
            }
            HStack(spacing: 12) {
                ColorPicker(selection: $primary, supportsOpacity: false) { Text("Main colour").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text) }
                ColorPicker(selection: $secondary, supportsOpacity: false) { Text("Light colour").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text) }
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            HStack(spacing: 10) {
                Button { Task { await saveColors(reset: false) } } label: {
                    if saving { ProgressView().tint(.white) } else { Label(saved ? "Saved!" : "Save for everyone", systemImage: saved ? "checkmark" : "paintbrush.fill") }
                }
                .buttonStyle(GradientButtonStyle(height: 50))
                .sensoryFeedback(.success, trigger: saved)
                Button("Reset") { Task { await saveColors(reset: true) } }.buttonStyle(OutlineButtonStyle(height: 50))
            }
        }
    }

    private func hexValue(_ c: Color) -> UInt32 {
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(Swift.max(0.0, Swift.min(255.0, Double(v) * 255.0))) }
        let red: UInt32 = byte(r) << 16
        let green: UInt32 = byte(g) << 8
        return red | green | byte(b)
    }

    private func saveColors(reset: Bool) async {
        saving = true
        defer { saving = false }
        let fields: Doc = [
            "app_primary": reset ? "" : SiteTheme.string(hexValue(primary)),
            "app_secondary": reset ? "" : SiteTheme.string(hexValue(secondary)),
            "updated_date": FS.nowISO(),
        ]
        do {
            if let id = SiteTheme.shared.configId {
                try await FS.update("SiteConfig", id, fields)
            } else {
                var doc = fields
                doc["key"] = "global"
                doc["created_date"] = FS.nowISO()
                let created = try await FS.create("SiteConfig", doc)
                SiteTheme.shared.configId = created.str("id")
            }
            SiteTheme.shared.primary = reset ? nil : hexValue(primary)
            SiteTheme.shared.secondary = reset ? nil : hexValue(secondary)
            if reset { primary = Color(hex: 0xD9577F); secondary = Color(hex: 0xEE8FAE) }
            saved = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}


// Everything the admin panel moderates.
struct AdminItem: Identifiable, Hashable {
    var collection: String
    var label: String
    var id: String
    var title: String
    var owner: String
    var date: String
    var image: String
}

@MainActor
@Observable
final class AdminData {
    var items: [AdminItem] = []
    var posts: [Doc] = []
    var art: [Doc] = []
    var tracks: [Doc] = []
    var reels: [Doc] = []
    var servers: [Server] = []
    var loading = false

    func load() async {
        loading = true
        defer { loading = false }
        async let p = try? FS.query("CommunityPost", orderBy: "created_date", limit: 200)
        async let a = try? FS.query("Artwork", orderBy: "created_date", limit: 200)
        async let t = try? FS.query("MusicReview", orderBy: "created_date", limit: 100)
        async let r = try? FS.query("Reel", orderBy: "created_date", limit: 100)
        async let c1 = try? FS.query("Comment", orderBy: "created_date", limit: 150)
        async let c2 = try? FS.query("CommunityComment", orderBy: "created_date", limit: 150)
        async let m = try? FS.query("ChannelMessage", orderBy: "created_date", limit: 150)
        async let s = try? FS.query("Community", orderBy: "created_date", limit: 150)
        posts = await p ?? []
        art = await a ?? []
        tracks = await t ?? []
        reels = await r ?? []
        let comments1 = await c1 ?? []
        let comments2 = await c2 ?? []
        let messages = await m ?? []
        servers = (await s ?? []).map(Server.init)
        var out: [AdminItem] = []
        out += posts.map { AdminItem(collection: "CommunityPost", label: "Post", id: $0.str("id"), title: $0.str("title").isEmpty ? $0.str("description") : $0.str("title"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: $0.str("image_url")) }
        out += art.map { AdminItem(collection: "Artwork", label: "Artwork", id: $0.str("id"), title: $0.str("title"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: $0.str("image_url")) }
        out += tracks.map { AdminItem(collection: "MusicReview", label: "Track", id: $0.str("id"), title: $0.str("title"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: $0.str("cover_url")) }
        out += reels.map { AdminItem(collection: "Reel", label: "Reel", id: $0.str("id"), title: $0.str("caption"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: $0.str("cover_url")) }
        out += comments1.map { AdminItem(collection: "Comment", label: "Comment", id: $0.str("id"), title: $0.str("content"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: "") }
        out += comments2.map { AdminItem(collection: "CommunityComment", label: "Comment", id: $0.str("id"), title: $0.str("content"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: "") }
        out += messages.filter { $0.str("type") != "join" }.map { AdminItem(collection: "ChannelMessage", label: "Message", id: $0.str("id"), title: $0.str("content").isEmpty ? "Image" : $0.str("content"), owner: $0.str("user_display_name"), date: $0.str("created_date"), image: $0.str("image_url")) }
        items = out.sorted { $0.date > $1.date }
    }
}
