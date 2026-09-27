import Foundation
import Observation

// The signed-in person and everything shared across tabs.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, signedOut, signedIn, offline(String) }

    var phase: Phase = .loading
    var me: UserProfile?
    // Everyone on Sugerly, by email (names and pictures for chats and posts).
    var people: [String: UserProfile] = [:]

    private var auth: AuthClient { AuthClient.shared }

    func start() async {
#if DEBUG
        if DesignPreview.active { DesignPreview.verifyFonts(); me = UserProfile(DesignPreview.profile); phase = .signedIn; return }
#endif
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
            "saved_posts": u.savedPosts, "blocked": u.blocked, "xp": u.xp, "coins": u.coins, "last_seen": u.lastSeen, "last_daily_claim": u.lastDaily, "daily_streak": u.dailyStreak,
        ]
    }

    func claimDaily() async throws -> Int {
        guard let me else { return 0 }
        let reward = try await FS.claimDaily(me.id)
        try await loadProfile()
        return reward
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
