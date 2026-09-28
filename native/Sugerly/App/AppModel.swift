import Foundation
import Observation
import SwiftUI

// The signed-in person and everything shared across tabs.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, signedOut, signedIn, offline(String) }

    var phase: Phase = .loading
    var me: UserProfile?
    // Everyone on Sugerly, by email (names and pictures for chats and posts).
    var people: [String: UserProfile] = [:]
    // The little pop-up at the top ("Saved", "Posted!", errors).
    var toast: Toast?
    // The notifications pop-up (opened from the bell).
    var showNotifications = false
    // Ask the shell to switch tabs (e.g. "See all" art → Gallery tab).
    var tabRequest: AppTab?

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
            phase = .signedIn
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
        phase = .signedIn
    }

    func signUp(name: String, email: String, password: String) async throws {
        try await auth.signUp(email: email, password: password, name: name)
        try await loadProfile(newName: name)
        phase = .signedIn
    }

    // Loads User/<uid>, creating it the same way the website does on first login.
    func loadProfile(newName: String? = nil) async throws {
        guard let uid = auth.uid else { throw APIError(message: "Please log in again.", status: 401) }
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
        Task { try? await FS.update("User", uid, ["last_seen": FS.nowISO()]) }
        Task { await loadPeople() }
    }

    func loadPeople() async {
        guard let docs = try? await FS.query("User", limit: 1000) else { return }
        var map: [String: UserProfile] = [:]
        for doc in docs {
            let user = UserProfile(doc)
            if !user.email.isEmpty { map[user.email] = user }
        }
        people = map
    }

    func person(_ email: String) -> UserProfile? { people[email.lowercased()] }

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
        ]
    }

    func signOut() {
        auth.signOut()
        me = nil
        people = [:]
        phase = .signedOut
    }

    func deleteAccount() async throws {
        if let me { try? await FS.delete("User", me.id) }
        try await auth.deleteAccount()
        self.me = nil
        phase = .signedOut
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var icon: String
    var error: Bool
}
