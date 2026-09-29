import SwiftUI
import UIKit

// Notifications as a pop-up card under the bell (tap outside to close).
struct NotificationsPopup: View {
    @Binding var path: [Route]
    var close: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @Environment(PostsStore.self) private var posts
    @State private var filter = "all"
    @State private var appeared = false

    private let filters: [(String, String, String)] = [("all", "All", "sparkles"), ("like", "Likes", "heart.fill"), ("comment", "Comments", "bubble.left.fill"), ("follow", "Follows", "person.fill.badge.plus"), ("mention", "Mentions", "at")]

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

    // Today / This week / Earlier, like the website.
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
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.22).ignoresSafeArea()
                .onTapGesture(perform: close)
            card
                .frame(maxWidth: 400)
                .padding(.horizontal, 12)
                .padding(.top, 58)
                .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
        }
        .onAppear { appeared = true }
        .onDisappear { notes.markAllRead() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.0) { f in
                        let on = filter == f.0
                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = f.0 } } label: {
                            Label(f.1, systemImage: f.2).font(.jakarta(12, .bold))
                                .foregroundStyle(on ? .white : Palette.text2)
                                .padding(.horizontal, 12).frame(height: 32)
                                .background {
                                    if on { Capsule().fill(Theme.gradient).matchedGeometryEffect(id: "pill", in: pill) }
                                    else { Capsule().fill(Palette.surface2) }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            Divider().overlay(Palette.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if shown.isEmpty {
                        VStack(spacing: 6) {
                            MimiBuddy(icon: "bell.fill", mood: .sleepy, size: 100)
                            Text("All quiet here").font(.display(22)).foregroundStyle(Palette.text)
                            Doodles.squiggle.stroke(Theme.main.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).frame(width: 54, height: 7)
                            Text(filter == "all" ? "When someone likes, follows, comments or mentions you, it pops up here." : "Nothing like this yet.")
                                .font(.jakarta(13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 20)
                    }
                    ForEach(Array(groups.enumerated()), id: \.element.0) { gi, group in
                        Text(group.0).font(.jakarta(12, .heavy)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                        ForEach(Array(group.1.enumerated()), id: \.element.id) { i, b in
                            Button { open(b.first) } label: { row(b) }
                                .buttonStyle(.plain)
                                .stagger(appeared, gi * 3 + i)
                        }
                    }
                    if !shown.isEmpty && notes.hasOlder {
                        ProgressView().controlSize(.small).tint(Theme.main)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .onAppear { Task { await notes.loadOlder(me: model.me?.email ?? "") } }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 470)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.main.opacity(0.22), radius: 28, y: 14)
    }

    @Namespace private var pill

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Activity").font(.jakarta(18, .heavy)).foregroundStyle(Palette.text)
                Text(notes.unread > 0 ? "\(notes.unread) new" : "You're all caught up").font(.jakarta(12, .semibold))
                    .foregroundStyle(notes.unread > 0 ? Theme.main : Palette.muted)
            }
            Spacer()
            if notes.unread > 0 {
                Button { withAnimation { notes.markAllRead() } } label: {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.main)
                }
                .accessibilityLabel("Mark all as read")
            }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text2)
                    .frame(width: 32, height: 32).background(Palette.surface2, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14).padding(.top, 14)
    }

    private func row(_ b: Bundle) -> some View {
        let n = b.first
        var names: [String] = []
        for item in b.items {
            let name = model.name(item.fromEmail, item.fromName.isEmpty ? "Someone" : item.fromName)
            if !names.contains(name) { names.append(name) }
        }
        let text: String = {
            guard b.items.count > 1 else { return n.message }
            let what = n.link.contains("Reels") ? "your reel" : n.link.contains("Gallery") ? "your artwork" : "your post"
            let others = names.count - 1
            return "\(names[0]) and \(others) other\(others == 1 ? "" : "s") liked \(what)"
        }()
        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if b.items.count > 1 {
                    ZStack(alignment: .topLeading) {
                        Avatar(url: model.person(b.items[1].fromEmail)?.picture ?? b.items[1].fromPicture, name: b.items[1].fromName, size: 34)
                        Avatar(url: model.person(n.fromEmail)?.picture ?? n.fromPicture, name: n.fromName, size: 34)
                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                            .offset(x: 12, y: 12)
                    }
                    .frame(width: 48, height: 48, alignment: .topLeading)
                } else {
                    Avatar(url: model.person(n.fromEmail)?.picture ?? n.fromPicture, name: n.fromName, size: 46)
                }
                Image(systemName: icon(n.type)).font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(LinearGradient(colors: tint(n.type), startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.jakarta(14, b.unread ? .bold : .medium)).foregroundStyle(Palette.text).multilineTextAlignment(.leading).lineLimit(3)
                Text(Dates.ago(n.created)).font(.jakarta(11, .semibold)).foregroundStyle(b.unread ? Theme.main : Palette.muted)
            }
            Spacer(minLength: 0)
            if n.type == "follow" && !n.fromEmail.isEmpty {
                FollowButton(email: n.fromEmail, compact: true)
            } else if b.unread {
                Circle().fill(Theme.main).frame(width: 9, height: 9)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(b.unread ? Theme.soft : Color.clear)
        .contentShape(Rectangle())
    }

    private func tint(_ type: String) -> [Color] {
        switch type {
        case "like": return [Color(hex: 0xFF7AA2), Color(hex: 0xE0406F)]
        case "follow": return [Color(hex: 0xB19CFF), Color(hex: 0x7C5CF0)]
        case "comment", "reply": return [Color(hex: 0x7CBEFF), Color(hex: 0x2F80E0)]
        case "message": return [Color(hex: 0x5FD3B0), Color(hex: 0x16A37F)]
        case "commission": return [Color(hex: 0xFFD166), Color(hex: 0xF0A020)]
        default: return [Theme.light, Theme.main]
        }
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "like": return "heart.fill"
        case "follow": return "person.fill.badge.plus"
        case "comment", "reply": return "bubble.left.fill"
        case "message": return "paperplane.fill"
        case "commission": return "storefront.fill"
        default: return "sparkles"
        }
    }

    // Links are website paths; open the matching screen.
    private func open(_ n: AppNotification) {
        close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            go(n)
        }
    }

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
        case overview = "Overview", users = "Users", content = "Content", servers = "Servers", reports = "Reports", colors = "Site"
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .users: return "person.2.fill"
            case .content: return "photo.stack.fill"
            case .servers: return "server.rack"
            case .reports: return "flag.fill"
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
                    .buttonStyle(.plain)
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
            HStack(spacing: 10) {
                Button { editChallenges = true } label: { Label("Weekly challenges", systemImage: "trophy.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
                Button { editPrompts = true } label: { Label("Daily prompts", systemImage: "paintpalette.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            }
            .sheet(isPresented: $editChallenges) { DailyContentEditor(kind: .challenges).presentationCornerRadius(30) }
            .sheet(isPresented: $editPrompts) { DailyContentEditor(kind: .prompts).presentationCornerRadius(30) }
            Divider().padding(.vertical, 6)
            Text("App colours").font(.display(22)).foregroundStyle(Palette.text)
        }
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

    private var reportsList: some View {
        VStack(spacing: 12) {
            if loading { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
            if !loading && reports.isEmpty { EmptyCard(icon: "checkmark.seal.fill", title: "No reports", text: "When people report posts or accounts, they show up here.") }
            ForEach(reports.indices, id: \.self) { i in
                let r = reports[i]
                let resolved = r.str("status") == "resolved"
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(r.str("reason"), systemImage: "flag.fill").font(.jakarta(12, .bold)).foregroundStyle(Palette.danger)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Palette.danger.opacity(0.1), in: Capsule())
                        Text(r.str("target_type").uppercased()).font(.jakarta(11, .heavy)).foregroundStyle(Palette.muted)
                        Spacer()
                        if resolved { Label(r.str("resolution").isEmpty ? "Resolved" : r.str("resolution"), systemImage: "checkmark").font(.jakarta(11, .bold)).foregroundStyle(Palette.success) }
                    }
                    if !r.str("target_preview").isEmpty { Text("“\(r.str("target_preview"))”").font(.jakarta(14)).foregroundStyle(Palette.text).lineLimit(3) }
                    if !r.str("details").isEmpty { Text(r.str("details")).font(.jakarta(13)).italic().foregroundStyle(Palette.text2) }
                    Text("By \(r.str("reporter_name").isEmpty ? r.str("reporter_email") : r.str("reporter_name")) · \(Dates.ago(r.str("created_date")))").font(.jakarta(11)).foregroundStyle(Palette.muted)
                    if !resolved {
                        HStack(spacing: 8) {
                            if let target = collection(for: r.str("target_type")) {
                                Button { Task { await resolve(i, remove: target) } } label: { Label("Remove", systemImage: "trash") }
                                    .buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
                            }
                            Button { Task { await resolve(i, remove: nil) } } label: { Label("Dismiss", systemImage: "checkmark") }
                                .buttonStyle(OutlineButtonStyle(height: 38))
                        }
                    }
                }
                .padding(14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                .opacity(resolved ? 0.6 : 1)
            }
        }
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

    private func resolve(_ index: Int, remove collection: String?) async {
        guard reports.indices.contains(index), let me = model.me else { return }
        let r = reports[index]
        if let collection { try? await FS.delete(collection, r.str("target_id")) }
        let resolution = collection == nil ? "Dismissed" : "Content removed"
        try? await FS.update("Report", r.str("id"), ["status": "resolved", "resolution": resolution, "resolved_by": me.email, "updated_date": FS.nowISO()])
        withAnimation(.snappy) {
            reports[index]["status"] = "resolved"
            reports[index]["resolution"] = resolution
        }
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
