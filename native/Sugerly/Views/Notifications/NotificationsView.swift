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

    private let filters: [(String, String, String)] = [("all", "All", "sparkles"), ("like", "Likes", "heart.fill"), ("comment", "Comments", "bubble.left.fill"), ("follow", "Follows", "person.fill.badge.plus")]

    private var shown: [AppNotification] {
        switch filter {
        case "like": return notes.items.filter { $0.type == "like" }
        case "comment": return notes.items.filter { $0.type == "comment" || $0.type == "reply" }
        case "follow": return notes.items.filter { $0.type == "follow" }
        default: return notes.items
        }
    }

    // Today / This week / Earlier, like the website.
    private var groups: [(String, [AppNotification])] {
        let now = Date()
        var today: [AppNotification] = [], week: [AppNotification] = [], earlier: [AppNotification] = []
        for n in shown {
            let age = now.timeIntervalSince(Dates.parse(n.created) ?? now)
            if age < 86_400 { today.append(n) } else if age < 7 * 86_400 { week.append(n) } else { earlier.append(n) }
        }
        return [("Today", today), ("This week", week), ("Earlier", earlier)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture(perform: close)
            card
                .frame(maxWidth: 420)
                .padding(.horizontal, 12)
                .padding(.top, 58)
                .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
        }
        .onAppear { appeared = true }
        .onDisappear { notes.markAllRead() }
    }

    private var card: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").font(.display(28)).foregroundStyle(Palette.text)
                        Text(notes.unread > 0 ? "\(notes.unread) new" : "You're all caught up").font(.jakarta(13, .semibold)).foregroundStyle(notes.unread > 0 ? Theme.main : Palette.muted)
                    }
                    Spacer()
                    if notes.unread > 0 {
                        Button { withAnimation { notes.markAllRead() } } label: { Label("Read all", systemImage: "checkmark.circle.fill") }
                            .buttonStyle(OutlineButtonStyle(height: 36))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.0) { f in
                            Chip(title: f.1, icon: f.2, active: filter == f.0) { withAnimation(.snappy) { filter = f.0 } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 4)
                if shown.isEmpty {
                    EmptyCard(icon: "bell.fill", title: "All caught up", text: "Likes, follows and comments show up here.")
                }
                ForEach(Array(groups.enumerated()), id: \.element.0) { gi, group in
                    Text(group.0.uppercased()).font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                        .padding(.top, 8).padding(.leading, 4)
                    ForEach(Array(group.1.enumerated()), id: \.element.id) { i, n in
                        Button { open(n) } label: { row(n) }
                            .buttonStyle(BouncyStyle(scale: 0.97))
                            .stagger(appeared, gi * 3 + i)
                    }
                }
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.light.opacity(0.6), lineWidth: 1.2))
        .shadow(color: Theme.main.opacity(0.25), radius: 30, y: 14)
        .refreshable { await notes.refresh(me: model.me?.email ?? "") }
    }

    private func row(_ n: AppNotification) -> some View {
        HStack(spacing: 12) {
            Avatar(url: model.person(n.fromEmail)?.picture ?? n.fromPicture, name: n.fromName, size: 50)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: icon(n.type)).font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(LinearGradient(colors: tint(n.type), startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(n.message).font(.jakarta(14, n.read ? .medium : .bold)).foregroundStyle(Palette.text).multilineTextAlignment(.leading).lineLimit(3)
                Text(Dates.ago(n.created)).font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            if n.type == "follow" && !n.fromEmail.isEmpty {
                FollowButton(email: n.fromEmail, compact: true)
            } else if !n.read {
                Circle().fill(Theme.gradient).frame(width: 10, height: 10).shadow(color: Theme.main.opacity(0.5), radius: 4)
            }
        }
        .padding(12)
        .background(n.read ? Palette.surface : Theme.pink.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(n.read ? Palette.border : Theme.pink.opacity(0.25), lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 6, y: 2)
    }

    private func tint(_ type: String) -> [Color] {
        switch type {
        case "like": return [Color(hex: 0xFF7AA2), Color(hex: 0xE0406F)]
        case "follow": return [Color(hex: 0xB19CFF), Color(hex: 0x7C5CF0)]
        case "comment", "reply": return [Color(hex: 0x7CBEFF), Color(hex: 0x2F80E0)]
        case "message": return [Color(hex: 0x5FD3B0), Color(hex: 0x16A37F)]
        default: return [Theme.light, Theme.main]
        }
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "like": return "heart.fill"
        case "follow": return "person.fill.badge.plus"
        case "comment", "reply": return "bubble.left.fill"
        case "message": return "paperplane.fill"
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

    func load() async {
        guard let docs = try? await FS.query("SiteConfig", [.equals("key", "global")], limit: 1), let doc = docs.first else { return }
        configId = doc.str("id")
        primary = Self.hex(doc.str("app_primary"))
        secondary = Self.hex(doc.str("app_secondary"))
    }

    static func hex(_ s: String) -> UInt32? {
        let clean = s.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard clean.count == 6, let v = UInt32(clean, radix: 16) else { return nil }
        return v
    }

    static func string(_ v: UInt32) -> String { String(format: "#%06X", v) }
}

struct AdminView: View {
    enum Tab: String, CaseIterable { case reports = "Reports", colors = "App colors" }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .reports
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
                HStack(spacing: 8) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Chip(title: t.rawValue, icon: t == .reports ? "flag.fill" : "paintpalette.fill", active: tab == t) { withAnimation(.snappy) { tab = t } }
                    }
                }
                if tab == .reports { reportsList } else { colors }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReports()
            await SiteTheme.shared.load()
            if let p = SiteTheme.shared.primary { primary = Color(hex: p) }
            if let s = SiteTheme.shared.secondary { secondary = Color(hex: s) }
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
