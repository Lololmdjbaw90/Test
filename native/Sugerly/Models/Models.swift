import Foundation

// Reading loosely-typed Firestore documents safely.
extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String { self[key] as? String ?? "" }
    func strs(_ key: String) -> [String] { (self[key] as? [Any] ?? []).compactMap { $0 as? String } }
    func int(_ key: String) -> Int {
        if let v = self[key] as? Int { return v }
        if let v = self[key] as? Double { return Int(v) }
        return 0
    }
    func bool(_ key: String) -> Bool { self[key] as? Bool ?? false }
}

enum Dates {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func iso(_ date: Date) -> String { withFraction.string(from: date) }
    static func parse(_ s: String) -> Date? { withFraction.date(from: s) ?? plain.date(from: s) }

    // "now", "5m", "3h", "2d", then a short date.
    static func ago(_ s: String) -> String {
        guard let date = parse(s) else { return "" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        if seconds < 7 * 86400 { return "\(Int(seconds / 86400))d" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func time(_ s: String) -> String {
        guard let date = parse(s) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct UserProfile: Identifiable, Hashable {
    var id: String
    var email: String
    var displayName: String
    var picture: String
    var banner: String
    var bio: String
    var role: String
    var following: [String]
    var savedPosts: [String]
    var blocked: [String]
    var xp: Int
    var coins: Int
    var lastSeen: String
    var accent: String
    var theme: String
    var lastDailyClaim: String
    var dailyStreak: Int
    var joined: String
    var savedArtworks: [String]
    var savedReels: [String]

    init(_ d: Doc) {
        id = d.str("id")
        email = d.str("email").lowercased()
        let name = d.str("display_name")
        displayName = name.isEmpty ? (d.str("full_name").isEmpty ? String(email.split(separator: "@").first ?? "") : d.str("full_name")) : name
        picture = d.str("profile_picture")
        banner = d.str("banner_url")
        bio = d.str("bio")
        role = d.str("role")
        following = d.strs("following")
        savedPosts = d.strs("saved_posts")
        blocked = d.strs("blocked").map { $0.lowercased() }
        xp = d.int("xp")
        coins = d.int("coins")
        lastSeen = d.str("last_seen")
        accent = d.str("accent")
        theme = d.str("theme")
        lastDailyClaim = d.str("last_daily_claim")
        dailyStreak = d.int("daily_streak")
        joined = d.str("created_date")
        savedArtworks = d.strs("saved_artworks")
        savedReels = d.strs("saved_reels")
    }

    var isAdmin: Bool { role == "admin" || FirebaseConfig.siteOwners.contains(email) }
    var isOnline: Bool {
        guard let seen = Dates.parse(lastSeen) else { return false }
        return Date().timeIntervalSince(seen) < 5 * 60
    }
    var level: Int { LevelInfo(xp: xp).level }
}

struct Post: Identifiable, Hashable {
    var id: String
    var title: String
    var text: String
    var imageURL: String
    var authorEmail: String
    var authorName: String
    var authorPicture: String
    var likes: [String]
    var created: String

    init(_ d: Doc) {
        id = d.str("id")
        title = d.str("title")
        text = d.str("description")
        imageURL = d.str("image_url")
        authorEmail = d.str("user_email").lowercased()
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        likes = d.strs("likes")
        created = d.str("created_date")
    }
}

struct Comment: Identifiable, Hashable {
    var id: String
    var postId: String
    var text: String
    var gifURL: String
    var authorEmail: String
    var authorName: String
    var authorPicture: String
    var likes: [String]
    var parentId: String
    var replyToName: String
    var created: String

    init(_ d: Doc) {
        id = d.str("id")
        postId = d.str("post_id")
        text = d.str("content")
        gifURL = d.str("gif_url")
        authorEmail = d.str("user_email").lowercased()
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        likes = d.strs("likes")
        parentId = d.str("parent_id")
        replyToName = d.str("reply_to_name")
        created = d.str("created_date")
    }
}

struct Message: Identifiable, Hashable {
    var id: String
    var conversationId: String
    var isGroup: Bool
    var groupName: String
    var text: String
    var imageURL: String
    var authorEmail: String
    var authorName: String
    var authorPicture: String
    var members: [String]
    var readBy: [String]
    var created: String
    var edited: Bool
    var pending = false

    init(_ d: Doc) {
        id = d.str("id")
        conversationId = d.str("conversation_id")
        isGroup = d.str("conversation_type") == "group"
        groupName = d.str("group_name")
        text = d.str("content")
        imageURL = d.str("image_url")
        authorEmail = d.str("user_email").lowercased()
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        members = d.strs("member_emails").map { $0.lowercased() }
        readBy = d.strs("read_by").map { $0.lowercased() }
        created = d.str("created_date")
        edited = d.bool("is_edited")
    }
}

// One chat in the Messages list (a DM or a group), with its newest message.
struct Conversation: Identifiable, Hashable {
    var id: String
    var members: [String]
    var isGroup: Bool
    var groupName: String
    var last: Message?
    var unread: Int
}

enum Social {
    // Same id the website uses for a one-to-one chat.
    static func dmId(_ a: String, _ b: String) -> String { [a.lowercased(), b.lowercased()].sorted().joined(separator: "__dm__") }
    static let reportReasons = [
        "Spam or scam", "Harassment or bullying", "Hate speech", "Nudity or sexual content",
        "Violence or threats", "Stolen art / copyright", "Pretending to be someone else", "Something else",
    ]
}

struct Artwork: Identifiable, Hashable {
    var id: String
    var title: String
    var text: String
    var imageURL: String
    var medium: String
    var authorEmail: String
    var authorName: String
    var authorPicture: String
    var likes: [String]
    var featured: Bool
    var created: String

    init(_ d: Doc) {
        id = d.str("id")
        title = d.str("title")
        text = d.str("description")
        imageURL = d.str("image_url")
        medium = d.str("medium").replacingOccurrences(of: "_", with: " ")
        authorEmail = d.str("user_email").lowercased()
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        likes = d.strs("likes")
        featured = d.bool("is_featured") || d.bool("featured")
        created = d.str("created_date")
    }
}

// Songs people upload to the Music tab (stored as "MusicReview" on the website).
struct Track: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var audioURL: String
    var coverURL: String
    var genre: String
    var mood: String
    var authorEmail: String
    var likes: [String]
    var created: String
    var external: URL? = nil

    init(_ d: Doc) {
        id = d.str("id")
        title = d.str("title").isEmpty ? "Untitled" : d.str("title")
        artist = d.str("user_display_name")
        audioURL = d.str("music_url")
        coverURL = d.str("cover_url")
        genre = d.str("genre")
        mood = d.str("mood")
        authorEmail = d.str("user_email").lowercased()
        likes = d.strs("likes")
        created = d.str("created_date")
    }

    init(id: String, title: String, artist: String, audioURL: String, coverURL: String, external: URL?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.audioURL = audioURL
        self.coverURL = coverURL
        genre = ""
        mood = ""
        authorEmail = ""
        likes = []
        created = ""
        self.external = external
    }
}

struct Reel: Identifiable, Hashable {
    var id: String
    var kind: String
    var mediaURL: String
    var mediaURLs: [String]
    var coverURL: String
    var caption: String
    var musicTitle: String
    var musicArtist: String
    var musicURL: String
    var musicSource: String
    var authorEmail: String
    var authorName: String
    var authorPicture: String
    var likes: [String]
    var views: Int
    var commentsOff: Bool
    var trimStart: Double
    var created: String

    init(_ d: Doc) {
        id = d.str("id")
        kind = d.str("kind")
        mediaURL = d.str("media_url")
        mediaURLs = d.strs("media_urls")
        coverURL = d.str("cover_url")
        caption = d.str("caption")
        musicTitle = d.str("music_title")
        musicArtist = d.str("music_artist")
        musicURL = d.str("music_url")
        musicSource = d.str("music_source")
        authorEmail = d.str("user_email").lowercased()
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        likes = d.strs("likes")
        views = d.int("views")
        commentsOff = d.bool("comments_off")
        let edits = d["edits"] as? [String: Any] ?? [:]
        trimStart = (edits["trim_start"] as? Double) ?? Double((edits["trim_start"] as? Int) ?? 0)
        created = d.str("created_date")
    }

    var isVideo: Bool { kind == "video" || (mediaURLs.isEmpty && [".mp4", ".mov", ".m4v", ".webm"].contains(where: { mediaURL.lowercased().contains($0) })) }
    var pictures: [String] { mediaURLs.isEmpty ? [mediaURL] : mediaURLs }
}

struct AppNotification: Identifiable, Hashable {
    var id: String
    var type: String
    var message: String
    var link: String
    var fromEmail: String
    var fromName: String
    var fromPicture: String
    var read: Bool
    var created: String

    init(_ d: Doc) {
        id = d.str("id")
        type = d.str("type")
        message = d.str("message")
        link = d.str("link")
        fromEmail = d.str("from_email").lowercased()
        fromName = d.str("from_display_name")
        fromPicture = d.str("from_profile_picture")
        read = d.bool("is_read")
        created = d.str("created_date")
    }
}
