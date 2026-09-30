import SwiftUI

// MARK: - Models (same collections as the website)

struct Server: Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
    var emoji: String
    var iconURL: String
    var bannerURL: String
    var ownerEmail: String
    var members: [String]
    var welcome: String
    var everyone: [String: Bool]

    init(_ d: Doc) {
        id = d.str("id")
        name = d.str("name")
        description = d.str("description")
        emoji = d.str("icon_emoji")
        iconURL = d.str("icon_url")
        bannerURL = d.str("banner_url")
        ownerEmail = d.str("owner_email").lowercased()
        members = d.strs("member_emails").map { $0.lowercased() }
        welcome = d.str("welcome_message")
        var perms: [String: Bool] = [:]
        for (k, v) in (d["everyone_permissions"] as? [String: Any] ?? [:]) { perms[k] = v as? Bool ?? false }
        everyone = perms
    }
}

struct ServerChannel: Identifiable, Hashable {
    var id: String
    var serverId: String
    var name: String
    var type: String
    var description: String
    var position: Int
    var isPrivate: Bool
    var allowedRoles: [String]

    var isVoice: Bool { type == "voice" }

    init(_ d: Doc) {
        id = d.str("id")
        serverId = d.str("community_id")
        name = d.str("name")
        type = d.str("type")
        description = d.str("description")
        position = d.int("position")
        isPrivate = d.bool("private")
        allowedRoles = d.strs("allowed_roles")
    }
}

struct ServerRole: Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var permissions: [String: Bool]
    var position: Int

    var tint: Color { Color(hex: ReelText.hex(color.isEmpty ? "#94a3b8" : color)) }

    init(_ d: Doc) {
        id = d.str("id")
        name = d.str("name")
        color = d.str("color")
        position = d.int("position")
        var perms: [String: Bool] = [:]
        let legacy = ["can_pin_messages": "pin_messages", "can_manage_messages": "manage_messages"]
        for (k, v) in (d["permissions"] as? [String: Any] ?? [:]) { perms[legacy[k] ?? k] = v as? Bool ?? false }
        permissions = perms
    }
}

struct ServerMember: Identifiable, Hashable {
    var id: String
    var email: String
    var name: String
    var picture: String
    var roles: [String]
    var nickname: String

    init(_ d: Doc) {
        id = d.str("id")
        email = d.str("user_email").lowercased()
        name = d.str("user_display_name")
        picture = d.str("user_profile_picture")
        roles = d.strs("roles")
        nickname = d.str("nickname")
    }
}

struct ChannelMessage: Identifiable, Hashable {
    var id: String
    var text: String
    var imageURL: String
    var authorEmail: String
    var authorName: String
    var authorPicture: String
    var replyPreview: String
    var kind: String
    var pinned: Bool
    var edited: Bool
    var created: String
    var reactions: [String: [String]] = [:]
    var pending = false
    var channelId = ""
    var serverId = ""

    init(_ d: Doc) {
        id = d.str("id")
        text = d.str("content")
        imageURL = d.str("image_url")
        authorEmail = d.str("user_email").lowercased()
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        replyPreview = d.str("reply_to_preview")
        kind = d.str("type")
        channelId = d.str("channel_id")
        serverId = d.str("community_id")
        pinned = d.bool("is_pinned")
        edited = d.bool("is_edited")
        created = d.str("created_date")
        var parsed: [String: [String]] = [:]
        for (emoji, value) in (d["reactions"] as? [String: Any] ?? [:]) {
            let people = (value as? [Any] ?? []).compactMap { $0 as? String }
            if !people.isEmpty { parsed[emoji] = people }
        }
        reactions = parsed
    }
}

// MARK: - Permissions (Discord-style, same rules as the website)

enum ServerPerm: String, CaseIterable {
    case administrator, manage_server, manage_channels, manage_roles, kick_members, create_invite
    case send_messages, attach_files, add_reactions, mention_roles, pin_messages, manage_messages
    case connect, speak, video

    var label: String {
        switch self {
        case .administrator: return "Administrator"
        case .manage_server: return "Manage server"
        case .manage_channels: return "Manage channels"
        case .manage_roles: return "Manage roles"
        case .kick_members: return "Kick members"
        case .create_invite: return "Create invites"
        case .send_messages: return "Send messages"
        case .attach_files: return "Attach images"
        case .add_reactions: return "Add reactions"
        case .mention_roles: return "Mention roles & @everyone"
        case .pin_messages: return "Pin messages"
        case .manage_messages: return "Manage messages"
        case .connect: return "Connect to voice"
        case .speak: return "Speak in voice"
        case .video: return "Video & screen share"
        }
    }

    var detail: String {
        switch self {
        case .administrator: return "Every permission, and can manage everything."
        case .manage_server: return "Change the name, icon, banner, description and welcome."
        case .manage_channels: return "Create, edit and delete channels, see private ones."
        case .manage_roles: return "Create and edit roles below their own, and give them out."
        case .kick_members: return "Remove members ranked below them."
        case .create_invite: return "Copy the server's invite link."
        case .send_messages: return "Post in text channels."
        case .attach_files: return "Upload pictures in messages."
        case .add_reactions: return "React to messages with emoji."
        case .mention_roles: return "Notify a whole role or the server."
        case .pin_messages: return "Pin and unpin messages."
        case .manage_messages: return "Delete other people's messages."
        case .connect: return "Join voice channels."
        case .speak: return "Talk in voice channels."
        case .video: return "Turn on the camera in voice."
        }
    }

    static let groups: [(String, [ServerPerm])] = [
        ("General", [.administrator, .manage_server, .manage_channels, .manage_roles, .kick_members, .create_invite]),
        ("Text", [.send_messages, .attach_files, .add_reactions, .mention_roles, .pin_messages, .manage_messages]),
        ("Voice", [.connect, .speak, .video]),
    ]

    static let everyoneDefaults: [String: Bool] = [
        "create_invite": true, "send_messages": true, "attach_files": true, "add_reactions": true,
        "mention_roles": false, "connect": true, "speak": true, "video": true,
    ]
    static let indexed = ["manage_server", "manage_channels", "manage_roles", "kick_members", "manage_messages", "pin_messages"]
}

struct Access {
    var perms: Set<String>
    var isOwner: Bool
    var top: Int // lower = more senior; owner / site admin = Int.min
    var roleIds: [String]

    func can(_ p: ServerPerm) -> Bool { perms.contains(p.rawValue) }
}

// MARK: - One server's live data

@MainActor
@Observable
final class ServerStore {
    var server: Server
    var channels: [ServerChannel] = []
    var roles: [ServerRole] = []
    var members: [ServerMember] = []
    var voice: [String: [VoicePresenceInfo]] = [:] // channel id -> who's in there
    var loaded = false

    init(_ server: Server) { self.server = server }

    var sortedRoles: [ServerRole] { roles.sorted { $0.position < $1.position } }

    func load() async {
        async let fresh = try? FS.get("Community", server.id)
        async let ch = try? FS.query("ServerChannel", [.equals("community_id", server.id)])
        async let ro = try? FS.query("ServerRole", [.equals("community_id", server.id)])
        async let me = try? FS.query("ServerMember", [.equals("community_id", server.id)])
        if let doc = await fresh ?? nil { server = Server(doc) }
        channels = ((await ch) ?? []).map(ServerChannel.init).sorted { $0.position < $1.position }
        roles = ((await ro) ?? []).map(ServerRole.init)
        members = ((await me) ?? []).map(ServerMember.init)
        loaded = true
        await loadVoice()
    }

    func loadVoice() async {
        let docs = (try? await FS.query("VoicePresence", [.equals("community_id", server.id)])) ?? []
        let now = Date().timeIntervalSince1970 * 1000
        var map: [String: [VoicePresenceInfo]] = [:]
        for d in docs {
            let info = VoicePresenceInfo(d)
            guard now - info.lastActive < 35_000 else { continue }
            map[info.channelId, default: []].append(info)
        }
        voice = map
    }

    func member(_ email: String) -> ServerMember? { members.first { $0.email == email } }

    func access(_ email: String, siteAdmin: Bool = false) -> Access {
        let isOwner = server.ownerEmail == email
        let roleIds = member(email)?.roles ?? []
        if isOwner || siteAdmin {
            return Access(perms: Set(ServerPerm.allCases.map(\.rawValue)), isOwner: isOwner, top: Int.min, roleIds: roleIds)
        }
        var perms = Set<String>()
        for (k, v) in ServerPerm.everyoneDefaults.merging(server.everyone, uniquingKeysWith: { $1 }) where v { perms.insert(k) }
        let mine = sortedRoles.filter { roleIds.contains($0.id) }
        for r in mine { for (k, v) in r.permissions where v { perms.insert(k) } }
        let top = mine.map(\.position).min() ?? Int.max
        if perms.contains("administrator") { perms = Set(ServerPerm.allCases.map(\.rawValue)) }
        return Access(perms: perms, isOwner: false, top: top, roleIds: roleIds)
    }

    // Highest role of a member (for name colours and grouping).
    func topRole(_ email: String) -> ServerRole? {
        let ids = member(email)?.roles ?? []
        return sortedRoles.first { ids.contains($0.id) }
    }

    func nameColor(_ email: String) -> Color? {
        guard let role = topRole(email), !role.color.isEmpty else { return nil }
        return role.tint
    }

    func canView(_ channel: ServerChannel, _ a: Access) -> Bool {
        let bypass = a.can(.administrator) || a.can(.manage_channels)
        let names = roles.filter { a.roleIds.contains($0.id) }.map(\.name)
        let inRole = channel.allowedRoles.contains { a.roleIds.contains($0) || names.contains($0) }
        return !channel.isPrivate || channel.allowedRoles.isEmpty || inRole || bypass
    }

    func canPost(_ channel: ServerChannel, _ a: Access) -> Bool {
        guard !channel.isVoice, a.can(.send_messages) else { return false }
        let bypass = a.can(.administrator) || a.can(.manage_channels)
        let names = roles.filter { a.roleIds.contains($0.id) }.map(\.name)
        let inRole = channel.allowedRoles.contains { a.roleIds.contains($0) || names.contains($0) }
        return channel.allowedRoles.isEmpty || inRole || bypass
    }

    func canEditRole(_ actor: Access, _ role: ServerRole) -> Bool {
        actor.can(.manage_roles) && (actor.top == Int.min || role.position > actor.top)
    }

    func canActOn(_ actor: Access, _ email: String) -> Bool {
        if email == server.ownerEmail { return false }
        if actor.top == Int.min { return true }
        return access(email).top > actor.top
    }

    // The website's rules read moderation permissions from perm_index; keep it
    // up to date after role changes.
    func syncPermIndex() async {
        var index: [String: [String]] = [:]
        for k in ServerPerm.indexed { index[k] = [] }
        for m in members where server.members.contains(m.email) && m.email != server.ownerEmail {
            let a = access(m.email)
            for k in ServerPerm.indexed where a.perms.contains(k) { index[k, default: []].append(m.email) }
        }
        for k in index.keys { index[k]?.sort() }
        let payload: [String: Any] = index.mapValues { $0 as Any }
        try? await FS.update("Community", server.id, ["perm_index": payload])
    }
}

struct VoicePresenceInfo: Identifiable, Hashable {
    var id: String
    var channelId: String
    var peerId: String
    var email: String
    var name: String
    var picture: String
    var muted: Bool
    var deafened: Bool
    var lastActive: Double
    var video: String      // "", "camera" or "screen"

    init(_ d: Doc) {
        id = d.str("id")
        channelId = d.str("channel_id")
        peerId = d.str("peer_id")
        email = d.str("user_email").lowercased()
        let user = d["user"] as? [String: Any] ?? [:]
        name = user["display_name"] as? String ?? ""
        picture = user["profile_picture"] as? String ?? ""
        muted = d.bool("muted")
        deafened = d.bool("deafened")
        lastActive = ReelText.num(d["last_active"]) ?? 0
        video = d.str("video")
    }
}
