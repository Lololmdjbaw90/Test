import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks

// MARK: - Notifications on your phone

// Real iOS notifications for new DMs, server messages, likes / comments /
// follows / mentions, and new reels from people you follow. The app checks
// while it's open (and in voice calls), and iOS wakes it now and then in the
// background to check too. Each kind can be turned off in Settings.
@MainActor
@Observable
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()
    static let refreshTask = "com.mimilocks.app.refresh"

    enum Kind: String, CaseIterable, Identifiable {
        case dms, servers, social, reels
        var id: String { rawValue }
        var key: String { "sugerly.alerts.\(rawValue)" }
        var title: String {
            switch self {
            case .dms: return "Direct messages"
            case .servers: return "Server messages"
            case .social: return "Likes, comments & follows"
            case .reels: return "New reels from people you follow"
            }
        }
        var icon: String {
            switch self {
            case .dms: return "bubble.left.and.bubble.right.fill"
            case .servers: return "person.3.fill"
            case .social: return "heart.fill"
            case .reels: return "play.rectangle.fill"
            }
        }
        var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    }

    struct Destination: Equatable { var kind: String; var target: String; var stamp = UUID() }

    // Tapped notification → MainShell opens the right place.
    var destination: Destination?
    var permission: UNAuthorizationStatus = .notDetermined

    // What's on screen now (no banner for the chat you're reading).
    @ObservationIgnored var openConversation: String?
    @ObservationIgnored var openChannel: String?
    @ObservationIgnored var following: [String] = []
    // People you ignore or block never ping you; Do not disturb silences everything.
    @ObservationIgnored var muted = Set<String>()
    @ObservationIgnored var doNotDisturb = false

    @ObservationIgnored private var serverIds: [String] = []
    @ObservationIgnored private var serverNames: [String: String] = [:]
    @ObservationIgnored private var serversLoaded = Date.distantPast
    @ObservationIgnored private var channelNames: [String: String] = [:]
    @ObservationIgnored private var checking = false

    // MARK: setup

    // Called once at launch (before the app finishes starting).
    func registerBackground() {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTask, using: nil) { task in
            Task { @MainActor in await Alerts.shared.runBackground(task) }
        }
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        permission = await center.notificationSettings().authorizationStatus
    }

    func scheduleBackground() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func runBackground(_ task: BGTask) async {
        scheduleBackground()
        let work = Task { @MainActor in await self.check() }
        task.expirationHandler = { work.cancel() }
        await work.value
        WidgetBridge.reload()
        task.setTaskCompleted(success: true)
    }

    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
    }

    // MARK: checking

    func check() async {
        guard !checking, AuthClient.shared.hasSession, let me = AuthClient.shared.email, !me.isEmpty else { return }
        checking = true
        defer { checking = false }
        if Kind.dms.enabled { await checkDMs(me) }
        if Kind.servers.enabled { await checkServers(me) }
        if Kind.social.enabled { await checkSocial(me) }
        if Kind.reels.enabled { await checkReels(me) }
    }

    // Only things newer than the last check (the first check just starts the clock).
    private func since(_ kind: Kind) -> String? {
        let key = "sugerly.alerts.since.\(kind.rawValue)"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        UserDefaults.standard.set(FS.nowISO(), forKey: key)
        return nil
    }

    private func mark(_ kind: Kind, _ newest: String) {
        let key = "sugerly.alerts.since.\(kind.rawValue)"
        if newest > (UserDefaults.standard.string(forKey: key) ?? "") { UserDefaults.standard.set(newest, forKey: key) }
    }

    private func checkDMs(_ me: String) async {
        guard let from = since(.dms) else { return }
        guard let docs = try? await FS.query("DirectMessage", [.contains("member_emails", me), .after("created_date", from)], orderBy: "created_date", limit: 30) else { return }
        let messages = docs.map(Message.init).sorted { $0.created < $1.created }
        if let newest = messages.last?.created { mark(.dms, newest) }
        let fresh = messages.filter { $0.authorEmail != me && !$0.readBy.contains(me) && $0.conversationId != openConversation && !muted.contains($0.authorEmail) }
        for m in fresh.suffix(5) {
            let title = m.isGroup && !m.groupName.isEmpty ? "\(m.authorName) · \(m.groupName)" : m.authorName
            post(id: "dm-\(m.id)", title: title, body: m.text.isEmpty ? Media.label(m.imageURL) : m.text, thread: m.conversationId, kind: "dm", target: m.conversationId)
        }
    }

    private func checkServers(_ me: String) async {
        guard let from = since(.servers) else { return }
        if Date().timeIntervalSince(serversLoaded) > 600 {
            if let docs = try? await FS.query("Community", [.contains("member_emails", me)], limit: 100) {
                serverIds = docs.map { $0.str("id") }
                serverNames = Dictionary(docs.map { ($0.str("id"), $0.str("name")) }, uniquingKeysWith: { a, _ in a })
                serversLoaded = Date()
            }
        }
        guard !serverIds.isEmpty else { return }
        // One cheap query: the newest messages everywhere, keep the ones in your servers.
        guard let docs = try? await FS.query("ChannelMessage", [.after("created_date", from)], orderBy: "created_date", limit: 50) else { return }
        let mine = Set(serverIds)
        let messages = docs.map(ChannelMessage.init).sorted { $0.created < $1.created }
        if let newest = messages.last?.created { mark(.servers, newest) }
        let fresh = messages.filter { mine.contains($0.serverId) && $0.authorEmail != me && $0.channelId != openChannel && $0.kind != "join" && !muted.contains($0.authorEmail) }
        let name = (UserDefaults.standard.string(forKey: "sugerly.name") ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        // Mentions first, then the latest few.
        let mentions = fresh.filter { !name.isEmpty && $0.text.lowercased().replacingOccurrences(of: " ", with: "").contains("@\(name)") }
        let shown = Array((mentions + fresh.filter { m in !mentions.contains { $0.id == m.id } }.suffix(3)).prefix(5))
        for m in shown {
            let channel = await channelName(m.channelId)
            let server = serverNames[m.serverId] ?? "Server"
            let body = m.text.isEmpty ? Media.label(m.imageURL) : m.text
            post(id: "cm-\(m.id)", title: "\(m.authorName) · #\(channel)", subtitle: server, body: body, thread: m.serverId, kind: "server", target: m.serverId)
        }
    }

    private func channelName(_ id: String) async -> String {
        if let hit = channelNames[id] { return hit }
        let name = (try? await FS.get("ServerChannel", id))?.str("name") ?? "chat"
        channelNames[id] = name
        return name
    }

    private func checkSocial(_ me: String) async {
        guard let from = since(.social) else { return }
        guard let docs = try? await FS.query("Notification", [.equals("to_email", me), .after("created_date", from)], orderBy: "created_date", limit: 20) else { return }
        let items = docs.map(AppNotification.init).sorted { $0.created < $1.created }
        if let newest = items.last?.created { mark(.social, newest) }
        for n in items.filter({ !$0.read && !muted.contains($0.fromEmail) }).suffix(5) {
            // Server mentions already arrive as server messages.
            if n.type == "mention" && Kind.servers.enabled { continue }
            let kind = n.link.contains("Reels") ? "reels" : "social"
            post(id: "n-\(n.id)", title: n.fromName.isEmpty ? "Sugerly" : n.fromName, body: n.message, thread: n.type, kind: kind, target: n.link)
        }
    }

    private func checkReels(_ me: String) async {
        guard let from = since(.reels) else { return }
        if following.isEmpty, let uid = AuthClient.shared.uid, let doc = try? await FS.get("User", uid) {
            following = doc.strs("following")
        }
        guard !following.isEmpty else { return }
        guard let docs = try? await FS.query("Reel", [.after("created_date", from)], orderBy: "created_date", limit: 20) else { return }
        let reels = docs.map(Reel.init).sorted { $0.created < $1.created }
        if let newest = reels.last?.created { mark(.reels, newest) }
        let follows = Set(following)
        for r in reels.filter({ follows.contains($0.authorEmail) && $0.authorEmail != me }).suffix(3) {
            post(id: "reel-\(r.id)", title: "\(r.authorName) posted a reel", body: r.caption.isEmpty ? "Tap to watch" : r.caption, thread: "reels", kind: "reels", target: r.id)
        }
    }

    private func post(id: String, title: String, subtitle: String = "", body: String, thread: String, kind: String, target: String) {
        guard !doNotDisturb else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = String(body.prefix(240))
        content.sound = .default
        content.threadIdentifier = thread
        content.userInfo = ["kind": kind, "target": target]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let target = notification.request.content.userInfo["target"] as? String ?? ""
        let hidden = await MainActor.run { target == Alerts.shared.openConversation || target == Alerts.shared.openChannel }
        return hidden ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        let target = info["target"] as? String ?? ""
        await MainActor.run { Alerts.shared.destination = Destination(kind: kind, target: target) }
    }
}

// The notification switches in Settings.
struct AlertSettings: View {
    private var alerts = Alerts.shared
    @AppStorage(Alerts.Kind.dms.key) private var dms = true
    @AppStorage(Alerts.Kind.servers.key) private var servers = true
    @AppStorage(Alerts.Kind.social.key) private var social = true
    @AppStorage(Alerts.Kind.reels.key) private var reels = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if alerts.permission == .denied {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(Palette.danger)
                    Text("Notifications are off for Sugerly.").font(.jakarta(13, .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Button("Turn on") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.jakarta(13, .heavy)).foregroundStyle(Theme.main)
                }
                .padding(12)
                .background(Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            toggle(.dms, $dms)
            toggle(.servers, $servers)
            toggle(.social, $social)
            toggle(.reels, $reels)
        }
        .task { await alerts.requestPermission() }
    }

    private func toggle(_ kind: Alerts.Kind, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Label(kind.title, systemImage: kind.icon).font(.jakarta(14, .semibold)).foregroundStyle(Palette.text)
        }
        .tint(Theme.main)
    }
}
