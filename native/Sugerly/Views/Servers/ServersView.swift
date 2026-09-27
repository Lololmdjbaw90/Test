import SwiftUI
import UIKit
import PhotosUI

// MARK: - Models (same collections as the website: Community, ServerChannel, ChannelMessage)

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

    init(_ d: Doc) {
        id = d.str("id")
        name = d.str("name")
        description = d.str("description")
        emoji = d.str("icon_emoji")
        iconURL = d.str("icon_url")
        bannerURL = d.str("banner_url")
        ownerEmail = d.str("owner_email")
        members = d.strs("member_emails")
        welcome = d.str("welcome_message")
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

    var isVoice: Bool { type == "voice" }

    init(_ d: Doc) {
        id = d.str("id")
        serverId = d.str("community_id")
        name = d.str("name")
        type = d.str("type")
        description = d.str("description")
        position = d.int("position")
        isPrivate = d.bool("private")
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
    var created: String
    var pending = false

    init(_ d: Doc) {
        id = d.str("id")
        text = d.str("content")
        imageURL = d.str("image_url")
        authorEmail = d.str("user_email")
        authorName = d.str("user_display_name")
        authorPicture = d.str("user_profile_picture")
        replyPreview = d.str("reply_to_preview")
        kind = d.str("type")
        pinned = d.bool("is_pinned")
        created = d.str("created_date")
    }
}

enum ServerTemplate: String, CaseIterable, Identifiable {
    case art, friends, blank
    var id: String { rawValue }
    var label: String { self == .art ? "Art community" : self == .friends ? "Friends hangout" : "Start from scratch" }
    var emoji: String { self == .art ? "🎨" : self == .friends ? "🫶" : "✨" }
    var channels: [(name: String, type: String, description: String)] {
        switch self {
        case .art: return [("general", "text", "Say hi and hang out"), ("showcase", "text", "Share finished work"), ("wip-and-critique", "text", "Works in progress & friendly feedback"), ("Studio", "voice", "Draw together")]
        case .friends: return [("general", "text", "Everything and anything"), ("memes", "text", "The good stuff"), ("Lounge", "voice", "Hop in")]
        case .blank: return [("general", "text", "General chat")]
        }
    }
}

enum Servers {
    @MainActor
    static func join(_ server: Server, me: UserProfile) async throws {
        var members = server.members
        if !members.contains(me.email) { members.append(me.email) }
        try await FS.update("Community", server.id, ["member_emails": members, "updated_date": FS.nowISO()])
        try await ensureMembership(server.id, me: me)
        let channels = (try? await FS.query("ServerChannel", [.equals("community_id", server.id)], orderBy: "position", descending: false)) ?? []
        if let general = channels.map(ServerChannel.init).first(where: { !$0.isVoice }) {
            _ = try? await FS.create("ChannelMessage", message(channel: general.id, server: server.id, me: me, text: "\(me.displayName) joined the server", imageURL: "", type: "join"))
        }
    }

    @MainActor
    static func leave(_ server: Server, me: UserProfile) async throws {
        try await FS.update("Community", server.id, ["member_emails": server.members.filter { $0 != me.email }, "updated_date": FS.nowISO()])
        let rows = (try? await FS.query("ServerMember", [.equals("community_id", server.id), .equals("user_email", me.email)])) ?? []
        for row in rows { try? await FS.delete("ServerMember", row.str("id")) }
    }

    @MainActor
    static func ensureMembership(_ serverId: String, me: UserProfile) async throws {
        let rows = (try? await FS.query("ServerMember", [.equals("community_id", serverId), .equals("user_email", me.email)], limit: 1)) ?? []
        guard rows.isEmpty else { return }
        _ = try await FS.create("ServerMember", ["community_id": serverId, "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture, "roles": [String](), "nickname": ""])
    }

    @MainActor
    static func create(me: UserProfile, name: String, description: String, emoji: String, iconURL: String, welcome: String, template: ServerTemplate) async throws -> Server {
        let doc = try await FS.create("Community", [
            "name": name, "description": description, "icon_emoji": emoji, "icon_url": iconURL, "banner_url": "",
            "welcome_message": welcome, "owner_email": me.email, "owner_display_name": me.displayName, "member_emails": [me.email],
        ])
        let server = Server(doc)
        for (position, ch) in template.channels.enumerated() {
            _ = try? await FS.create("ServerChannel", ["community_id": server.id, "name": ch.name, "type": ch.type, "description": ch.description, "position": position, "allowed_roles": [String]()])
        }
        let modPerms: [String: Any] = ["pin_messages": true, "manage_messages": true, "kick_members": true, "mention_roles": true]
        _ = try? await FS.create("ServerRole", ["community_id": server.id, "name": "Moderator", "color": "#d9577f", "permissions": modPerms, "position": 0])
        _ = try? await FS.create("ServerRole", ["community_id": server.id, "name": "Member", "color": "#64748b", "permissions": [String: Any](), "position": 1])
        try? await ensureMembership(server.id, me: me)
        return server
    }

    static func message(channel: String, server: String, me: UserProfile, text: String, imageURL: String, type: String = "", reply: ChannelMessage? = nil) -> Doc {
        var doc: Doc = [
            "channel_id": channel, "community_id": server, "content": text, "image_url": imageURL,
            "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
            "reply_to_id": reply?.id ?? "",
            "reply_to_preview": reply.map { "\($0.authorName): \(String(($0.text.isEmpty ? "image" : $0.text).prefix(80)))" } ?? "",
            "reactions": [String: Any](), "is_pinned": false, "is_edited": false,
        ]
        if !type.isEmpty { doc["type"] = type }
        return doc
    }
}

// Server icon: uploaded picture or emoji on a soft tile.
struct ServerIcon: View {
    let server: Server
    var size: CGFloat = 52
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(Theme.soft)
            if !server.iconURL.isEmpty {
                RemoteImage(url: server.iconURL)
            } else {
                Text(server.emoji.isEmpty ? "💬" : server.emoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

// MARK: - Server list (Your servers / Discover)

struct ServersView: View {
    @Binding var path: [Route]
    var embedded = false
    @Environment(AppModel.self) private var model
    @State private var servers: [Server] = []
    @State private var loading = true
    @State private var tab = 0
    @State private var search = ""
    @State private var creating = false
    @State private var busy: String?

    private var me: String { model.me?.email ?? "" }

    private var shown: [Server] {
        let base = tab == 0 ? servers.filter { $0.members.contains(me) } : servers.sorted { $0.members.count > $1.members.count }
        guard !search.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        if embedded {
            content
        } else {
            ScrollView { content.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 30).frame(maxWidth: 680).frame(maxWidth: .infinity) }
                .sugarBackground()
                .navigationTitle("Servers")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable { await load() }
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Chip(title: "Your servers", icon: "house.fill", active: tab == 0) { withAnimation(.snappy) { tab = 0 } }
                Chip(title: "Discover", icon: "sparkles", active: tab == 1) { withAnimation(.snappy) { tab = 1 } }
                Spacer()
                Button { creating = true } label: { Label("Create", systemImage: "plus") }
                    .buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search servers…", text: $search).font(.jakarta(15))
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))

            if loading && servers.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else if shown.isEmpty {
                EmptyCard(icon: "person.3.fill", title: tab == 0 ? "No servers yet" : "Nothing found", text: tab == 0 ? "Join one from Discover or create your own." : "Try another name.")
                if tab == 0 {
                    Button { withAnimation(.snappy) { tab = 1 } } label: { Label("Explore servers", systemImage: "sparkles") }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            ForEach(shown) { server in
                ServerCard(server: server, joined: server.members.contains(me), busy: busy == server.id) {
                    if server.members.contains(me) { path.append(.server(server)) } else { Task { await join(server) } }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $creating) {
            CreateServerView { server in
                servers.insert(server, at: 0)
                path.append(.server(server))
            }
        }
    }

    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("Community", orderBy: "created_date", limit: 150) else { return }
        servers = docs.map(Server.init)
    }

    private func join(_ server: Server) async {
        guard let meProfile = model.me else { return }
        busy = server.id
        defer { busy = nil }
        do {
            try await Servers.join(server, me: meProfile)
            var joined = server
            joined.members.append(meProfile.email)
            if let i = servers.firstIndex(where: { $0.id == server.id }) { servers[i] = joined }
            path.append(.server(joined))
        } catch {}
    }
}

struct ServerCard: View {
    let server: Server
    let joined: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if server.bannerURL.isEmpty {
                            LinearGradient(colors: [Theme.light.opacity(0.9), Theme.main.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            RemoteImage(url: server.bannerURL)
                        }
                    }
                    .frame(height: 74)
                    .clipped()
                    ServerIcon(server: server, size: 56)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.surface, lineWidth: 3))
                        .offset(x: 14, y: 26)
                }
                .frame(height: 74)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        if !server.description.isEmpty {
                            Text(server.description).font(.jakarta(13)).foregroundStyle(Palette.text2).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Label("\(server.members.count) members", systemImage: "person.2.fill").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 8)
                    Group {
                        if busy {
                            ProgressView().tint(Theme.main)
                        } else if joined {
                            Label("Open", systemImage: "arrow.right").font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                        } else {
                            Text("Join").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(height: 32).background(Theme.gradient, in: Capsule())
                                .shadow(color: Theme.main.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 34)
                .padding(.bottom, 14)
            }
            .sugarCard(radius: 24)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }
}

// MARK: - One server: banner, channels, members

struct ServerView: View {
    @State var server: Server
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var channels: [ServerChannel] = []
    @State private var loading = true
    @State private var confirmLeave = false

    private var me: String { model.me?.email ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !server.welcome.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.wave.fill").foregroundStyle(Theme.gradient)
                        Text(server.welcome).font(.jakarta(14, .medium)).foregroundStyle(Palette.text2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if loading && channels.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(30)
                }
                let text = channels.filter { !$0.isVoice }
                let voice = channels.filter(\.isVoice)
                if !text.isEmpty {
                    channelSection("TEXT CHANNELS", text)
                }
                if !voice.isEmpty {
                    channelSection("VOICE CHANNELS", voice)
                }
                membersRow
                if server.ownerEmail != me && server.members.contains(me) {
                    Button(role: .destructive) { confirmLeave = true } label: { Label("Leave server", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Leave \(server.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                guard let meProfile = model.me else { return }
                Task { try? await Servers.leave(server, me: meProfile); dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if server.bannerURL.isEmpty {
                    LinearGradient(colors: [Theme.light, Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    RemoteImage(url: server.bannerURL)
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                ServerIcon(server: server, size: 78)
                    .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(Palette.bg, lineWidth: 4))
                    .shadow(color: Theme.main.opacity(0.3), radius: 12, y: 6)
                    .offset(x: 18, y: 39)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(server.name).font(.display(32)).foregroundStyle(Palette.text)
                if !server.description.isEmpty {
                    Text(server.description).font(.jakarta(14)).foregroundStyle(Palette.text2)
                }
                HStack(spacing: 14) {
                    Label("\(server.members.count) members", systemImage: "person.2.fill")
                    Label("\(onlineCount) online", systemImage: "circle.fill").foregroundStyle(Palette.success)
                }
                .font(.jakarta(12, .bold))
                .foregroundStyle(Palette.muted)
            }
            .padding(.top, 48)
        }
        .padding(.top, 8)
    }

    private var onlineCount: Int { server.members.filter { model.person($0)?.isOnline == true }.count }

    private func channelSection(_ title: String, _ list: [ServerChannel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted).padding(.leading, 6)
            VStack(spacing: 2) {
                ForEach(list) { channel in
                    Button {
                        if channel.isVoice { path.append(.voice(server, channel)) } else { path.append(.channel(server, channel)) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: channel.isVoice ? "speaker.wave.2.fill" : "number")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.main)
                                .frame(width: 36, height: 36)
                                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(channel.name).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                                    if channel.isPrivate { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                                }
                                if !channel.description.isEmpty {
                                    Text(channel.description).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.97))
                }
            }
            .sugarCard(radius: 22, padding: 6)
        }
    }

    private var membersRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMBERS").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted).padding(.leading, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(server.members.sorted { (model.person($0)?.isOnline == true ? 0 : 1) < (model.person($1)?.isOnline == true ? 0 : 1) }, id: \.self) { email in
                        let person = model.person(email)
                        Button { path.append(.person(email)) } label: {
                            VStack(spacing: 6) {
                                Avatar(url: person?.picture ?? "", name: person?.displayName ?? email, size: 54, online: person?.isOnline ?? false)
                                    .overlay(alignment: .topTrailing) {
                                        if email == server.ownerEmail {
                                            Image(systemName: "crown.fill").font(.system(size: 12)).foregroundStyle(Palette.warning).offset(x: 2, y: -4)
                                        }
                                    }
                                Text(person?.displayName ?? String(email.split(separator: "@").first ?? "")).font(.jakarta(11, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                            }
                            .frame(width: 66)
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
        }
    }

    private func load() async {
        defer { loading = false }
        async let fresh = try? FS.get("Community", server.id)
        async let list = try? FS.query("ServerChannel", [.equals("community_id", server.id)], orderBy: "position", descending: false)
        if let doc = await fresh ?? nil { server = Server(doc) }
        channels = ((await list) ?? []).map(ServerChannel.init).sorted { $0.position < $1.position }
    }
}

// MARK: - A text channel

struct ChannelChatView: View {
    let server: Server
    let channel: ServerChannel
    @Environment(AppModel.self) private var model
    @State private var messages: [ChannelMessage] = []
    @State private var draft = ""
    @State private var replyTo: ChannelMessage?
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false
    @State private var failed: String?
    @State private var reporting: ReportSheet.Target?
    @FocusState private var focused: Bool

    private var me: String { model.me?.email ?? "" }
    private var isMember: Bool { server.members.contains(me) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if loaded {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "number").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 64, height: 64).background(Theme.gradient, in: Circle())
                                .shadow(color: Theme.main.opacity(0.35), radius: 12, y: 6)
                            Text("Welcome to #\(channel.name)!").font(.display(28)).foregroundStyle(Palette.text)
                            Text(channel.description.isEmpty ? "This is the start of the #\(channel.name) channel." : channel.description)
                                .font(.jakarta(14)).foregroundStyle(Palette.muted)
                        }
                        .padding(.vertical, 20)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let grouped = previous != nil && previous!.authorEmail == message.authorEmail && previous!.kind != "join" && !gap(previous!, message)
                        ChannelMessageRow(message: message, grouped: grouped, mine: message.authorEmail == me, onProfile: {})
                            .id(message.id)
                            .contextMenu {
                                Button { replyTo = message; focused = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                                if !message.text.isEmpty { Button { UIPasteboard.general.string = message.text } label: { Label("Copy", systemImage: "doc.on.doc") } }
                                if message.authorEmail == me || model.me?.isAdmin == true {
                                    Button(role: .destructive) { delete(message) } label: { Label("Delete", systemImage: "trash") }
                                }
                                if message.authorEmail != me {
                                    Button { reporting = ReportSheet.Target(id: message.id, type: "message", ownerEmail: message.authorEmail, preview: message.text, link: "/CommunityChat?id=\(server.id)") } label: { Label("Report", systemImage: "flag") }
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .sugarBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ServerIcon(server: server, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("#\(channel.name)").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                        Text(server.name).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .task { await poll() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let failed { Text(failed).font(.jakarta(12, .semibold)).foregroundStyle(Palette.danger) }
            if let replyTo {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(Theme.main)
                    Text("Replying to \(replyTo.authorName)").font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                    Spacer()
                    Button { self.replyTo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                }
                .padding(.horizontal, 6)
            }
            if isMember {
                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.main)
                            .frame(width: 42, height: 42)
                            .background(Theme.soft, in: Circle())
                    }
                    .buttonStyle(BouncyStyle())
                    TextField("Message #\(channel.name)", text: $draft, axis: .vertical)
                        .font(.jakarta(15))
                        .focused($focused)
                        .lineLimit(1...6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    SendButton(enabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { Task { await send() } }
                }
            } else {
                Text("Join the server to chat here.").font(.jakarta(14, .semibold)).foregroundStyle(Palette.muted).padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Palette.surface
                .shadow(color: Palette.shadow, radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func gap(_ a: ChannelMessage, _ b: ChannelMessage) -> Bool {
        guard let x = Dates.parse(a.created), let y = Dates.parse(b.created) else { return false }
        return y.timeIntervalSince(x) > 7 * 60
    }

    private func poll() async {
        while !Task.isCancelled {
            await load()
            let slow = FS.missingIndex.contains("ChannelMessage")
            try? await Task.sleep(for: .seconds(slow ? 4 : 2.5))
        }
    }

    private func load() async {
        var filters: [FS.Filter] = [.equals("channel_id", channel.id)]
        let newest = messages.last(where: { !$0.pending })?.created ?? ""
        if loaded, !newest.isEmpty { filters.append(.after("created_date", ChatStore.minus(newest, seconds: 60))) }
        guard let docs = try? await FS.query("ChannelMessage", filters, orderBy: "created_date", limit: loaded ? 60 : 150) else {
            loaded = true
            return
        }
        let known = Set(messages.map(\.id))
        let fresh = docs.map(ChannelMessage.init).filter { !known.contains($0.id) }
        let blocked = Set(model.me?.blocked ?? [])
        if !fresh.isEmpty || !loaded {
            withAnimation(loaded ? .snappy : nil) {
                messages = (messages + fresh).filter { !blocked.contains($0.authorEmail) }.sorted { $0.created < $1.created }
            }
        }
        loaded = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let meProfile = model.me else { return }
        if Moderation.hasLink(text) && meProfile.isAdmin == false {
            failed = "Links aren't allowed in server chats."
            return
        }
        draft = ""
        failed = nil
        let data = Servers.message(channel: channel.id, server: server.id, me: meProfile, text: text, imageURL: "", reply: replyTo)
        replyTo = nil
        var pending = ChannelMessage(data)
        pending.id = "pending-\(UUID().uuidString)"
        pending.created = FS.nowISO()
        pending.pending = true
        withAnimation(.snappy) { messages.append(pending) }
        do {
            let doc = try await FS.create("ChannelMessage", data)
            let created = ChannelMessage(doc)
            if let i = messages.firstIndex(where: { $0.id == pending.id }) { messages[i] = created }
        } catch {
            withAnimation { messages.removeAll { $0.id == pending.id } }
            draft = text
            failed = "Couldn't send — \(error.localizedDescription)"
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let meProfile = model.me,
              let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw), let jpeg = ImageTools.jpeg(image, maxSide: 1600) else { return }
        do {
            let url = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            let doc = try await FS.create("ChannelMessage", Servers.message(channel: channel.id, server: server.id, me: meProfile, text: "", imageURL: url))
            withAnimation(.snappy) { messages.append(ChannelMessage(doc)) }
        } catch {
            failed = "Couldn't send the photo — \(error.localizedDescription)"
        }
    }

    private func delete(_ message: ChannelMessage) {
        withAnimation { messages.removeAll { $0.id == message.id } }
        Task { try? await FS.delete("ChannelMessage", message.id) }
    }
}

struct ChannelMessageRow: View {
    let message: ChannelMessage
    let grouped: Bool
    let mine: Bool
    var onProfile: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        if message.kind == "join" {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(Palette.success)
                Text(message.text).font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                Text(Dates.time(message.created)).font(.jakarta(11)).foregroundStyle(Palette.muted.opacity(0.7))
            }
            .padding(.vertical, 6)
            .padding(.leading, 12)
        } else {
            HStack(alignment: .top, spacing: 10) {
                if grouped {
                    Color.clear.frame(width: 40, height: 1)
                } else {
                    Avatar(url: model.person(message.authorEmail)?.picture ?? message.authorPicture, name: message.authorName, size: 40)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !message.replyPreview.isEmpty {
                        Label(message.replyPreview, systemImage: "arrowshape.turn.up.left.fill")
                            .font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if !grouped {
                        HStack(spacing: 6) {
                            Text(model.person(message.authorEmail)?.displayName ?? message.authorName)
                                .font(.jakarta(14, .heavy))
                                .foregroundStyle(mine ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text))
                            Text(Dates.ago(message.created)).font(.jakarta(11)).foregroundStyle(Palette.muted)
                            if message.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.main) }
                        }
                    }
                    if !message.text.isEmpty {
                        Text(message.text).font(.jakarta(15)).foregroundStyle(Palette.text).textSelection(.enabled)
                    }
                    if !message.imageURL.isEmpty {
                        RemoteImage(url: message.imageURL, contentMode: .fit)
                            .frame(maxWidth: 260, maxHeight: 280, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .opacity(message.pending ? 0.55 : 1)
                Spacer(minLength: 0)
            }
            .padding(.top, grouped ? 0 : 10)
        }
    }
}

// Voice channels: the website runs the call; in the app you can see who's
// in there and hop in from the website.
struct VoiceChannelView: View {
    let server: Server
    let channel: ServerChannel
    @Environment(AppModel.self) private var model
    @State private var inside: [String] = []

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                .frame(width: 110, height: 110).background(Theme.gradient, in: Circle())
                .shadow(color: Theme.main.opacity(0.45), radius: 24, y: 10)
            Text(channel.name).font(.display(34)).foregroundStyle(Palette.text)
            Text(inside.isEmpty ? "Nobody's here right now." : "\(inside.count) in the channel").font(.jakarta(15)).foregroundStyle(Palette.muted)
            HStack(spacing: -10) {
                ForEach(inside.prefix(6), id: \.self) { email in
                    Avatar(url: model.person(email)?.picture ?? "", name: model.person(email)?.displayName ?? email, size: 50)
                        .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 3))
                }
            }
            Text("Voice chat runs on the Sugerly website for now — open it there to talk.")
                .font(.jakarta(13)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).padding(.horizontal, 40)
            Link(destination: URL(string: "https://sugerly.netlify.app/CommunityChat?id=\(server.id)")!) {
                Label("Open on the website", systemImage: "safari.fill")
            }
            .buttonStyle(GradientButtonStyle(fullWidth: false))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .sugarBackground()
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let docs = (try? await FS.query("VoicePresence", [.equals("channel_id", channel.id)])) ?? []
            inside = docs.map { $0.str("user_email") }.filter { !$0.isEmpty }
        }
    }
}

// MARK: - Create a server

struct CreateServerView: View {
    var onCreate: (Server) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var template: ServerTemplate = .art
    @State private var name = ""
    @State private var about = ""
    @State private var welcome = ""
    @State private var emoji = "🌸"
    @State private var busy = false
    @State private var error: String?

    private let emojis = ["🌸", "🎨", "🫶", "✨", "🎧", "🌙", "🍓", "🦋", "🎮", "📚", "🌈", "🐱"]

    var body: some View {
        ComposerScaffold(title: "Create a server", actionTitle: "Create", busy: busy, canPost: !name.trimmingCharacters(in: .whitespaces).isEmpty, onClose: { dismiss() }, onPost: { Task { await create() } }) {
            VStack(alignment: .leading, spacing: 18) {
                Text("START FROM").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                VStack(spacing: 8) {
                    ForEach(ServerTemplate.allCases) { t in
                        Button { withAnimation(.snappy) { template = t } } label: {
                            HStack(spacing: 14) {
                                Text(t.emoji).font(.system(size: 26)).frame(width: 50, height: 50).background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.label).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                                    Text(t.channels.map { $0.type == "voice" ? "🔊 \($0.name)" : "#\($0.name)" }.joined(separator: "  ·  "))
                                        .font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if template == t { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.gradient) }
                            }
                            .padding(12)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(template == t ? Theme.main : Palette.border, lineWidth: template == t ? 2 : 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.97))
                    }
                }
                Text("ICON").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(emojis, id: \.self) { e in
                        Button { emoji = e } label: {
                            Text(e).font(.system(size: 24)).frame(maxWidth: .infinity).frame(height: 48)
                                .background(emoji == e ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(emoji == e ? Theme.main : Palette.border, lineWidth: emoji == e ? 2 : 1))
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                SugarField(placeholder: "Server name", text: $name)
                SugarField(placeholder: "What's it about?", text: $about, lines: 2...4)
                SugarField(placeholder: "Welcome message for new members", text: $welcome)
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
    }

    private func create() async {
        guard let meProfile = model.me else { return }
        busy = true
        defer { busy = false }
        do {
            let server = try await Servers.create(me: meProfile, name: String(name.trimmingCharacters(in: .whitespaces).prefix(40)), description: String(about.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)), emoji: emoji, iconURL: "", welcome: String(welcome.trimmingCharacters(in: .whitespaces).prefix(160)), template: template)
            dismiss()
            onCreate(server)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
