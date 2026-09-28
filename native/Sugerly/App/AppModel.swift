import Foundation
import Observation
import SwiftUI
import UIKit

// The signed-in person and everything shared across tabs.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, signedOut, signedIn, offline(String), banned(String) }

    var phase: Phase = .loading
    var me: UserProfile?
    // Everyone on Sugerly, by email (names and pictures for chats and posts).
    var people: [String: UserProfile] = [:]
    // The little pop-up at the top ("Saved", "Posted!", errors).
    var toast: Toast?
    // The notifications pop-up (opened from the bell).
    var showNotifications = false
    // The quick menu (opened from your picture in the top bar).
    var showMenu = false
    // Ask the shell to switch tabs (e.g. "See all" art → Gallery tab).
    var tabRequest: AppTab?
    // "Use this sound" on a reel: opens the reel maker with that sound.
    var soundRequest: Track?

    private var auth: AuthClient { AuthClient.shared }

    func showToast(_ text: String, icon: String = "checkmark.circle.fill", error: Bool = false) {
        let next = Toast(text: text, icon: error ? "exclamationmark.circle.fill" : icon, error: error)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { toast = next }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast?.id == next.id { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }

    func start() async {
        guard auth.hasSession else { phase = .signedOut; return }
        do {
            try await loadProfile()
            phase = entryPhase
        } catch let error as APIError where error.status == -1 {
            phase = .offline(error.message)
        } catch {
            auth.signOut()
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        try await auth.signIn(email: email, password: password)
        try await loadProfile()
        phase = entryPhase
    }

    func signUp(name: String, email: String, password: String) async throws {
        try await auth.signUp(email: email, password: password, name: name)
        try await loadProfile(newName: name)
        phase = entryPhase
    }

    // Banned accounts see the ban screen instead of the app.
    var entryPhase: Phase {
        guard let me, me.isBanned else { return .signedIn }
        return .banned(Self.banMessage(me))
    }

    static func banMessage(_ u: UserProfile) -> String {
        var text = u.banReason.isEmpty ? "An admin banned this account." : u.banReason
        if let until = Dates.parse(u.bannedUntil) {
            text += "\nThe ban ends \(until.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }

    // Checked every couple of minutes while the app is open.
    func checkBan() async {
        guard let uid = auth.uid, let doc = try? await FS.get("User", uid) else { return }
        let fresh = UserProfile(doc)
        if fresh.isBanned { phase = .banned(Self.banMessage(fresh)) }
    }

    // Loads User/<uid>, creating it the same way the website does on first login.
    func loadProfile(newName: String? = nil) async throws {
        guard let uid = auth.uid else { throw APIError(message: "Please log in again.", status: 401) }
        Drafts.owner = uid
        Drafts.adoptLegacy()
        let email = (auth.email ?? "").lowercased()
        if let doc = try await FS.get("User", uid) {
            me = UserProfile(doc)
        } else {
            let name = (newName?.isEmpty == false ? newName! : String(email.split(separator: "@").first ?? "artist"))
            let now = FS.nowISO()
            let profile: Doc = [
                "id": uid, "email": email, "full_name": name, "display_name": name, "profile_picture": "",
                "role": FirebaseConfig.siteOwners.contains(email) ? "admin" : "user",
                "bio": "", "following": [String](), "xp": 0, "coins": 0, "nitro_active": false,
                "onboarding_completed": true, "theme": "light", "accent": "rose",
                "saved_artworks": [String](), "saved_posts": [String](),
                "last_seen": now, "created_date": now, "updated_date": now,
            ]
            let created = try await FS.create("User", profile, id: uid)
            me = UserProfile(created)
        }
        let searchName = (me?.displayName ?? "").lowercased()
        Task { try? await FS.update("User", uid, ["last_seen": FS.nowISO(), "search_name": searchName]) }
        Task { await loadPeople() }
        Task {
            await Referrals.ensureCode(self)
            await Referrals.claim(self)
        }
    }

    // A starter set of the most recently active people (not everyone: there
    // could be billions). Anyone else is fetched on demand the first time
    // they show up on screen (see person()).
    func loadPeople() async {
        let recent = (try? await FS.query("User", orderBy: "last_seen", limit: 300)) ?? []
        var map = people
        for doc in recent {
            let user = UserProfile(doc)
            if !user.email.isEmpty { map[user.email] = user }
        }
        if let me { map[me.email] = me }
        people = map
    }

    func person(_ email: String) -> UserProfile? {
        let key = email.lowercased()
        if let hit = people[key] { return hit }
        request(key)
        return nil
    }

    // People we still need, fetched 30 at a time a moment later.
    @ObservationIgnored private var wanted = Set<String>()
    @ObservationIgnored private var unknown = Set<String>()
    @ObservationIgnored private var fetchingPeople = false

    private func request(_ email: String) {
        guard email.contains("@"), !unknown.contains(email), !wanted.contains(email) else { return }
        wanted.insert(email)
        guard !fetchingPeople else { return }
        fetchingPeople = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            while !wanted.isEmpty {
                let batch = Array(wanted.prefix(30))
                wanted.subtract(batch)
                guard let docs = try? await FS.query("User", [.isIn("email", batch)], limit: 30) else { continue }
                var map = people
                for doc in docs {
                    let user = UserProfile(doc)
                    if !user.email.isEmpty { map[user.email] = user }
                }
                for email in batch where map[email] == nil { unknown.insert(email) }
                people = map
            }
            fetchingPeople = false
        }
    }

    // Look people up by name on the server (prefix search).
    func searchPeople(_ text: String) async -> [UserProfile] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        async let lower = try? FS.prefix("User", field: "search_name", q.lowercased(), limit: 20)
        async let exact = try? FS.prefix("User", field: "display_name", q, limit: 20)
        async let capital = try? FS.prefix("User", field: "display_name", q.prefix(1).uppercased() + q.dropFirst(), limit: 20)
        var found: [String: UserProfile] = [:]
        for doc in (await lower ?? []) + (await exact ?? []) + (await capital ?? []) {
            let u = UserProfile(doc)
            if !u.email.isEmpty { found[u.email] = u }
        }
        var map = people
        for (k, v) in found { map[k] = v }
        people = map
        return Array(found.values)
    }

    var accent: Accent { Accent(rawValue: me?.accent ?? "") ?? .rose }
    var colorScheme: ColorScheme? {
        switch me?.theme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    // Changes your profile at once and saves in the background; undone if saving fails.
    func updateMe(_ fields: Doc) async throws {
        guard let current = me else { return }
        var next = fields
        if let name = fields["display_name"] as? String { next["search_name"] = name.lowercased() }
        next["updated_date"] = FS.nowISO()
        var merged = currentDoc(current)
        for (k, v) in next { merged[k] = v }
        me = UserProfile(merged)
        do {
            try await FS.update("User", current.id, next)
        } catch {
            me = current
            throw error
        }
    }

    private func currentDoc(_ u: UserProfile) -> Doc {
        [
            "id": u.id, "email": u.email, "display_name": u.displayName, "profile_picture": u.picture,
            "banner_url": u.banner, "bio": u.bio, "role": u.role, "following": u.following,
            "saved_posts": u.savedPosts, "blocked": u.blocked, "xp": u.xp, "coins": u.coins, "last_seen": u.lastSeen,
            "accent": u.accent, "theme": u.theme, "last_daily_claim": u.lastDailyClaim, "daily_streak": u.dailyStreak,
            "created_date": u.joined, "saved_artworks": u.savedArtworks, "saved_reels": u.savedReels,
            "nitro_active": u.nitroActive, "nitro_until": u.nitroUntil, "name_style": u.nameStyle, "banner_color": u.bannerColor,
            "interests": u.interests, "pronouns": u.pronouns, "custom_status": u.status, "profile_color": u.profileColor,
            "profile_effect": u.profileEffect, "website": u.website, "stickers": u.stickers, "my_gifs": u.myGifs,
            "accepted_chats": u.acceptedChats, "ignored": u.ignored, "presence": u.presence, "custom_status_until": u.statusUntil,
            "banned": u.banned, "ban_reason": u.banReason, "banned_until": u.bannedUntil,
            "muted_until_ms": u.mutedUntilMs, "mod_strikes": u.modStrikes,
            "invite_code": u.inviteCode, "invites_joined": u.invitesJoined,
            "effect_color": u.effectColor, "effect_amount": u.effectAmount, "name_color": u.nameColor,
            "avatar_frame": u.avatarFrame, "banner_pattern": u.bannerPattern,
            "accent_main": u.accentMain, "accent_sub": u.accentSub,
        ]
    }

    // Your own colours from Settings (main + sub tone), if you set them.
    var myColors: (main: UInt32, light: UInt32)? {
        guard let me, let main = SiteTheme.hex(me.accentMain) else { return nil }
        return (main, SiteTheme.hex(me.accentSub) ?? main)
    }

    func signOut() {
        auth.signOut()
        resetForNextAccount()
        phase = .signedOut
    }

    // Everything tied to the account that just left: close every page and
    // pop-up, and forget what this phone remembered for them, so the next
    // account starts fresh.
    static let signingOut = Notification.Name("sugerly.signingOut")

    private func resetForNextAccount() {
        NotificationCenter.default.post(name: Self.signingOut, object: nil)
        me = nil
        people = [:]
        toast = nil
        showNotifications = false
        showMenu = false
        tabRequest = nil
        soundRequest = nil
        Drafts.owner = "guest"
        let defaults = UserDefaults.standard
        for key in ["sugerly.closedDMs", "sugerly.storiesSeen", "sugerly.recentSearches", "sugerly.reelbrain.v1",
                    "sugerly.name", "sugerly.chat.section", "sugerly.dismissedAnnouncement"] {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sugerly.alerts.since.") {
            defaults.removeObject(forKey: key)
        }
        WidgetBridge.clear()
        Alerts.shared.setBadge(0)
        // Sheets and full-screen pages are shown by UIKit; close them all.
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.rootViewController?.dismiss(animated: false)
            }
        }
    }

    func deleteAccount() async throws {
        if let me { try? await FS.delete("User", me.id) }
        try await auth.deleteAccount()
        resetForNextAccount()
        phase = .signedOut
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var icon: String
    var error: Bool
}
