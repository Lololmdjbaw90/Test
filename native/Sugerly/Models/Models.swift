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
    // Nitro + profile customisation (website fields, plus a few app extras)
    var nitroActive: Bool
    var nitroUntil: String
    var nameStyle: String
    var bannerColor: String
    var interests: [String]
    var pronouns: String
    var status: String
    var profileColor: String
    var profileEffect: String
    var website: String
    var stickers: [String]
    var myGifs: [String]
    // Privacy and presence (app extras, like Discord)
    var acceptedChats: [String]   // people whose message requests you accepted
    var ignored: [String]         // muted: no notifications, their chats and posts tucked away
    var presence: String          // online, idle, dnd or invisible
    var statusUntil: String       // when the custom status clears ("" = never)
    // Set by admins
    var banned: Bool
    var banReason: String
    var bannedUntil: String       // "" = until an admin lifts it

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
        nitroActive = d.bool("nitro_active")
        nitroUntil = d.str("nitro_until")
        nameStyle = d.str("name_style")
        bannerColor = d.str("banner_color")
        interests = d.strs("interests")
        pronouns = d.str("pronouns")
        status = d.str("custom_status")
        profileColor = d.str("profile_color")
        profileEffect = d.str("profile_effect")
        website = d.str("website")
        stickers = d.strs("stickers")
        myGifs = d.strs("my_gifs")
        acceptedChats = d.strs("accepted_chats").map { $0.lowercased() }
        ignored = d.strs("ignored").map { $0.lowercased() }
        presence = d.str("presence")
        statusUntil = d.str("custom_status_until")
        banned = d.bool("banned")
        banReason = d.str("ban_reason")
        bannedUntil = d.str("banned_until")
    }

    var isBanned: Bool {
        guard banned else { return false }
        guard let until = Dates.parse(bannedUntil) else { return true }
        return until > Date()
    }

    // MimiNitro: active and not expired (same rule as the website).
    var isNitro: Bool {
        guard nitroActive else { return false }
        guard let until = Dates.parse(nitroUntil) else { return nitroUntil.isEmpty }
        return until > Date()
    }

    var isAdmin: Bool { role == "admin" || FirebaseConfig.siteOwners.contains(email) }

    // What others see: invisible (or away from the app) shows as offline.
    var presenceNow: Presence {
        guard presence != "invisible", let seen = Dates.parse(lastSeen), Date().timeIntervalSince(seen) < 5 * 60 else { return .offline }
        return Presence(rawValue: presence) ?? .online
    }
    var isOnline: Bool { presenceNow != .offline }

    // The custom status, unless it has expired.
    var activeStatus: String {
        guard !status.isEmpty else { return "" }
        if let until = Dates.parse(statusUntil), until < Date() { return "" }
        return status
    }
    var level: Int { LevelInfo(xp: xp).level }
}

// Discord-style presence.
enum Presence: String, CaseIterable, Identifiable {
    case online, idle, dnd, invisible, offline
    var id: String { rawValue }

    var label: String {
        switch self {
        case .online: return "Online"
        case .idle: return "Idle"
        case .dnd: return "Do not disturb"
        case .invisible: return "Invisible"
        case .offline: return "Offline"
        }
    }

    var hint: String {
        switch self {
        case .online: return "People can see you're around"
        case .idle: return "Shows you're away for a bit"
        case .dnd: return "No notifications, and people see you're busy"
        case .invisible: return "Look offline, but use everything as normal"
        case .offline: return ""
        }
    }

    var icon: String {
        switch self {
        case .online: return "circle.fill"
        case .idle: return "moon.fill"
        case .dnd: return "minus.circle.fill"
        case .invisible, .offline: return "circle.dashed"
        }
    }

    var color: UInt32 {
        switch self {
        case .online: return 0x17A673
        case .idle: return 0xF0A020
        case .dnd: return 0xE5484D
        case .invisible, .offline: return 0x9A8A93
        }
    }
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
    var reactions: [String: [String]] = [:]
    var pending = false
    // Extras (same fields as the website): calls, shared reels, replies, voice notes.
    var kind = ""
    var callOutcome = ""
    var callDuration: Double = 0      // milliseconds
    var sharedReel: SharedReel?
    var replyId = ""
    var replyPreview = ""
    var replyName = ""
    var audioURL = ""
    var audioSeconds: Double = 0
    var videoURL = ""

    struct SharedReel: Hashable {
        var id: String
        var cover: String
        var caption: String
        var by: String
    }

    // The words to show (the website puts the reel link on its own line).
    var displayText: String {
        guard sharedReel != nil else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("\u{1F3AC}") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(_ d: Doc) {
        id = d.str("id")
        var parsed: [String: [String]] = [:]
        for (emoji, value) in (d["reactions"] as? [String: Any] ?? [:]) {
            let people = (value as? [Any] ?? []).compactMap { $0 as? String }
            if !people.isEmpty { parsed[emoji] = people }
        }
        reactions = parsed
        kind = d.str("type")
        callOutcome = d.str("call_outcome")
        callDuration = ReelText.num(d["call_duration"]) ?? 0
        if let r = d["shared_reel"] as? [String: Any], let rid = r["id"] as? String {
            sharedReel = SharedReel(id: rid, cover: r["cover_url"] as? String ?? "", caption: r["caption"] as? String ?? "", by: r["by"] as? String ?? "")
        }
        replyId = d.str("reply_to_id")
        replyPreview = d.str("reply_to_preview")
        replyName = d.str("reply_to_name")
        audioURL = d.str("audio_url")
        audioSeconds = ReelText.num(d["audio_duration"]) ?? 0
        videoURL = d.str("video_url")
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
    var duration: Double = 0
    // Website edits played live on top of the video.
    var texts: [ReelText] = []
    var filterId = "none"
    var speed: Double = 1
    var muted = false
    var mirror = false

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
        duration = ReelText.num(d["duration"]) ?? 0
        let edits = d["edits"] as? [String: Any] ?? [:]
        trimStart = ReelText.num(edits["trim_start"]) ?? 0
        if let clips = edits["clips"] as? [Any], let first = clips.first as? [String: Any], let start = ReelText.num(first["start"]) {
            trimStart = start
        }
        texts = (edits["text"] as? [Any] ?? []).compactMap { ($0 as? [String: Any]).map(ReelText.init) }.filter { !$0.text.isEmpty }
        filterId = edits["filter"] as? String ?? "none"
        speed = ReelText.num(edits["speed"]) ?? 1
        muted = edits["muted"] as? Bool ?? false
        mirror = edits["mirror"] as? Bool ?? false
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

// A text sticker made on the website: { text, x, y (0…1), size (of the
// frame width), rot (degrees), color, font, style, anim }.
struct ReelText: Hashable, Identifiable {
    var id: String
    var text: String
    var x: Double
    var y: Double
    var size: Double
    var rot: Double
    var color: String
    var bg: String
    var font: String
    var style: String
    var anim: String

    init(_ d: [String: Any]) {
        id = d["id"] as? String ?? UUID().uuidString
        text = d["text"] as? String ?? ""
        x = ReelText.num(d["x"]) ?? 0.5
        y = ReelText.num(d["y"]) ?? 0.4
        size = ReelText.num(d["size"]) ?? 0.07
        rot = ReelText.num(d["rot"]) ?? 0
        color = d["color"] as? String ?? "#ffffff"
        bg = d["bg"] as? String ?? ""
        font = d["font"] as? String ?? "sans"
        let st = d["style"] as? String ?? ""
        style = st.isEmpty ? (bg.isEmpty ? "plain" : "pill") : st
        anim = d["anim"] as? String ?? "none"
    }

    static func num(_ any: Any?) -> Double? {
        if let v = any as? Double { return v }
        if let v = any as? Int { return Double(v) }
        if let v = any as? String { return Double(v) }
        return nil
    }

    static func hex(_ s: String) -> UInt32 {
        var h = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        return UInt32(h.prefix(6), radix: 16) ?? 0xFFFFFF
    }

    static func isLight(_ v: UInt32) -> Bool {
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (r * 299 + g * 587 + b * 114) / 1000 > 150
    }
}
