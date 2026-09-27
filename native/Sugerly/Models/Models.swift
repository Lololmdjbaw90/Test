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
    }

    var isAdmin: Bool { role == "admin" || FirebaseConfig.siteOwners.contains(email) }
    var isOnline: Bool {
        guard let seen = Dates.parse(lastSeen) else { return false }
        return Date().timeIntervalSince(seen) < 5 * 60
    }
    var level: Int { max(1, Int((Double(xp) / 300).squareRoot()) + 1) }
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
