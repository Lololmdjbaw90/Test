import SwiftUI
import UIKit
import PhotosUI

// MARK: - Server helpers (same writes as the website's lib/servers.js)

enum ServerTemplate: String, CaseIterable, Identifiable {
    case art, friends, blank
    var id: String { rawValue }
    var label: String { self == .art ? "Art community" : self == .friends ? "Friends hangout" : "Start from scratch" }
    var icon: String { self == .art ? "paintpalette.fill" : self == .friends ? "heart.circle.fill" : "sparkles" }
    var channels: [(name: String, type: String, description: String)] {
        switch self {
        case .art: return [("general", "text", "Say hi and hang out"), ("showcase", "text", "Share finished work"), ("wip-and-critique", "text", "Works in progress & friendly feedback"), ("Studio", "voice", "Draw together")]
        case .friends: return [("general", "text", "Everything and anything"), ("memes", "text", "The good stuff"), ("Lounge", "voice", "Hop in")]
        case .blank: return [("general", "text", "General chat")]
        }
    }
}

enum Servers {
    static let site = "https://sugerly.netlify.app"

    @MainActor
    static func join(_ server: Server, me: UserProfile) async throws {
        var members = server.members
        if !members.contains(me.email) { members.append(me.email) }
        try await FS.update("Community", server.id, ["member_emails": members, "updated_date": FS.nowISO()])
        try await ensureMembership(server.id, me: me)
        let channels = (try? await FS.query("ServerChannel", [.equals("community_id", server.id)])) ?? []
        if let general = channels.map(ServerChannel.init).sorted(by: { $0.position < $1.position }).first(where: { !$0.isVoice }) {
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

    static func slug(_ name: String, voice: Bool) -> String {
        if voice { return String(name.trimmingCharacters(in: .whitespaces).prefix(40)) }
        let lowered = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return String(lowered.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(40))
    }
}

// Server icon: uploaded picture or emoji on a soft tile.
struct ServerIcon: View {
    let server: Server
    var size: CGFloat = 52
    var corner: CGFloat? = nil

    var body: some View {
        let radius = corner ?? size * 0.32
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.light.opacity(0.35), Theme.soft], startPoint: .top, endPoint: .bottom))
            if !server.iconURL.isEmpty {
                RemoteImage(url: server.iconURL)
            } else {
                // Initials on the accent gradient (no emoji icons).
                LinearGradient(colors: [Theme.light, Theme.main], startPoint: .top, endPoint: .bottom)
                Text(ServerIcon.initials(server.name)).font(.display(size * 0.38)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "S" : letters
    }
}

// MARK: - Servers: a list you tap into on iPhone, the rail on iPad

// On iPhone your servers are a list (each opens as its own page, with the
// one back button); servers to join are below. On iPad it's the
// Discord-like rail with the open server next to it.
struct ServersHome: View {
    @Binding var path: [Route]
    // Inside the Chat tab, which has its own title.
    var embedded = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let content = Group {
            if sizeClass == .regular {
                ServerHubView(path: $path)
            } else {
                ServerList(path: $path)
            }
        }
        .sugarBackground()
        if embedded {
            content
        } else {
            content.quietTitle("Servers")
        }
    }
}

struct ServerList: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var servers: [Server] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var busy: String?
    @State private var creating = false
    @State private var appeared = false

    private var me: String { model.me?.email ?? "" }
    private var mine: [Server] { servers.filter { $0.members.contains(me) } }
    private var discover: [Server] {
        let others = servers.filter { !$0.members.contains(me) }.sorted { $0.members.count > $1.members.count }
        guard !query.isEmpty else { return others }
        return others.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "Servers", subtitle: "Groups to hang out in", icon: "person.3.fill", candy: .sky,
                          search: $query, prompt: "Search servers")
                HStack {
                    Text("Your servers").font(.display(22)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { creating = true } label: {
                        Label("New", systemImage: "plus")
                            .font(.jakarta(13, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background {
                                Capsule().fill(Theme.candy).shadow(color: Theme.glow(0.28), radius: 6, y: 3)
                            }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.9))
                    .accessibilityLabel("Create a server")
                }
                .stagger(appeared, 0)
                if !loaded {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 64, radius: 20) }
                } else if mine.isEmpty {
                    EmptyCard(icon: "person.3.fill", title: "No servers yet", text: "Servers are group chats with channels and voice rooms. Join one below or make your own.", compact: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(mine) { server in
                            Button { path.append(.server(server)) } label: { row(server) }
                                .buttonStyle(SoftPressStyle())
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = "\(Servers.site)/CommunityChat?id=\(server.id)"
                                        model.showToast("Invite link copied", icon: "link")
                                    } label: { Label("Copy invite link", systemImage: "link") }
                                }
                            if server.id != mine.last?.id {
                                Rectangle().fill(Palette.border).frame(height: 1).padding(.leading, 74)
                            }
                        }
                    }
                    .sugarCard(radius: 22)
                    .stagger(appeared, 1)
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover").font(.display(22)).foregroundStyle(Palette.text)
                    Text("Find your people").font(.jakarta(13, .medium)).foregroundStyle(Palette.muted)
                }
                .padding(.top, 10)
                .stagger(appeared, 2)
                if loaded && discover.isEmpty {
                    EmptyCard(icon: "sparkles", title: query.isEmpty ? "You're in them all" : "Nothing found", text: query.isEmpty ? "Make a new one with New." : "Try another name.", compact: true)
                }
                ForEach(Array(discover.enumerated()), id: \.element.id) { i, server in
                    ServerCard(server: server, joined: false, busy: busy == server.id) {
                        Task { await join(server) }
                    }
                    .stagger(appeared, min(i + 4, 10))
                    .scrollFade()
                    .transition(.opacity.combined(with: .offset(y: 10)))
                }
            }
            .padding(16)
            .padding(.bottom, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .onAppear { appeared = true }
        .fullScreenCover(isPresented: $creating) {
            CreateServerView { server in
                servers.insert(server, at: 0)
                path.append(.server(server))
            }
        }
    }

    private func row(_ server: Server) -> some View {
        let online = server.members.filter { model.person($0)?.isOnline == true }.count
        return HStack(spacing: 12) {
            ServerIcon(server: server, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.name).font(.jakarta(16, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(server.members.count)", systemImage: "person.2.fill").foregroundStyle(Palette.muted)
                    if online > 0 {
                        Label("\(online) online", systemImage: "circle.fill").foregroundStyle(Palette.success)
                    }
                }
                .font(.jakarta(12, .semibold))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // Servers you're in come straight from membership (so an old server
    // never goes missing), plus the newest ones to discover.
    private func load() async {
        async let joined = try? FS.query("Community", [.contains("member_emails", me)], limit: 300)
        async let newest = try? FS.query("Community", orderBy: "created_date", limit: 100)
        let mineDocs = await joined ?? []
        let docs = await newest ?? []
        var seen = Set<String>()
        let next = (mineDocs + docs).map(Server.init).filter { seen.insert($0.id).inserted }
        withAnimation(Motion.pick(.smooth(duration: 0.4))) {
            if !next.isEmpty || !loaded { servers = next }
            loaded = true
        }
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
            model.showToast("Welcome to \(server.name)!", icon: "party.popper.fill")
            path.append(.server(joined))
        } catch {
            model.showToast("Couldn't join — try again", error: true)
        }
    }
}

// One server as its own page: banner, channels (with who's in voice), roles.
struct ServerPage: View {
    @Binding var path: [Route]
    @State private var store: ServerStore

    init(server: Server, path: Binding<[Route]>) {
        _path = path
        _store = State(initialValue: ServerStore(server))
    }

    var body: some View {
        ServerPanel(store: store, path: $path, onLeft: {
            if !path.isEmpty { path.removeLast() }
        })
        .sugarBackground()
        .navigationTitle(store.server.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - The hub: a rail of your servers + the open server (like Discord)

struct ServerHubView: View {
    @Binding var path: [Route]
    var initial: Server? = nil
    @Environment(AppModel.self) private var model
    @State private var servers: [Server] = []
    @State private var selected: String?
    @State private var stores: [String: ServerStore] = [:]
    @State private var creating = false
    @State private var loaded = false

    private var me: String { model.me?.email ?? "" }
    private var mine: [Server] { servers.filter { $0.members.contains(me) } }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Group {
                if let id = selected, let store = stores[id] {
                    ServerPanel(store: store, path: $path, onLeft: {
                        selected = nil
                        Task { await load() }
                    })
                    .id(id)
                    .transition(.opacity)
                } else {
                    DiscoverServers(servers: servers, loaded: loaded, onOpen: open, onJoined: { server in
                        if let i = servers.firstIndex(where: { $0.id == server.id }) { servers[i] = server }
                        open(server)
                    })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if let initial, stores[initial.id] == nil {
                stores[initial.id] = ServerStore(initial)
                selected = initial.id
            }
            await load()
        }
        .fullScreenCover(isPresented: $creating) {
            CreateServerView { server in
                servers.insert(server, at: 0)
                open(server)
            }
        }
    }

    private var rail: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                railButton(active: selected == nil) {
                    Image(systemName: "safari.fill").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selected == nil ? .white : Theme.main)
                        .frame(width: 50, height: 50)
                        .background(selected == nil ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.surface), in: RoundedRectangle(cornerRadius: selected == nil ? 16 : 25, style: .continuous))
                } action: { withMotion(Motion.standard) { selected = nil } }

                Capsule().fill(Palette.border).frame(width: 30, height: 2)

                ForEach(mine) { server in
                    railButton(active: selected == server.id) {
                        ServerIcon(server: server, size: 50, corner: selected == server.id ? 16 : 25)
                            .shadow(color: selected == server.id ? Theme.main.opacity(0.35) : .clear, radius: 8, y: 3)
                    } action: { open(server) }
                    .contextMenu {
                        Button { UIPasteboard.general.string = "\(Servers.site)/CommunityChat?id=\(server.id)"; model.showToast("Invite link copied", icon: "link") } label: { Label("Copy invite link", systemImage: "link") }
                    }
                }

                Button { creating = true } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.success)
                        .frame(width: 50, height: 50)
                        .frostedFill(in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .buttonStyle(BouncyStyle())
                .accessibilityLabel("Create a server")
            }
            .padding(.vertical, 12)
            .frame(width: 74)
        }
        .frame(width: 74)
        .background(Palette.surface2.opacity(0.7))
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.border).frame(width: 1) }
    }

    private func railButton<Label: View>(active: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .leading) {
            Button(action: action) { label() }
                .buttonStyle(BouncyStyle(scale: 0.9))
                .frame(maxWidth: .infinity)
            Capsule().fill(Theme.main)
                .frame(width: 4, height: active ? 36 : 0)
        }
        .frame(width: 74)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
        .sensoryFeedback(.selection, trigger: active)
    }

    private func open(_ server: Server) {
        if stores[server.id] == nil { stores[server.id] = ServerStore(server) }
        withMotion(Motion.standard) { selected = server.id }
    }

    // Servers you're in come straight from membership (so an old server
    // never goes missing), plus the newest ones to discover.
    private func load() async {
        async let joined = try? FS.query("Community", [.contains("member_emails", me)], limit: 300)
        async let newest = try? FS.query("Community", orderBy: "created_date", limit: 100)
        let mineDocs = await joined ?? []
        guard let docs = await newest else { loaded = true; return }
        var seen = Set<String>()
        servers = (mineDocs + docs).map(Server.init).filter { seen.insert($0.id).inserted }
        loaded = true
        if selected == nil && initial == nil, let first = mine.first { open(first) }
    }
}

// Browse and join servers (the website's Communities page).
struct DiscoverServers: View {
    let servers: [Server]
    let loaded: Bool
    var onOpen: (Server) -> Void
    var onJoined: (Server) -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var busy: String?

    private var shown: [Server] {
        let list = servers.sorted { $0.members.count > $1.members.count }
        guard !query.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover").font(.display(30)).foregroundStyle(Palette.text)
                    Label("Find your people", systemImage: "sparkles").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                }
                SearchField(text: $query, placeholder: "Search servers…")
                if !loaded {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 150, radius: 24) }
                } else if shown.isEmpty {
                    EmptyCard(icon: "person.3.fill", title: "Nothing found", text: "Try another name, or make your own with +.")
                }
                // One column on iPhone, more side by side on iPad.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(shown) { server in
                        let joined = server.members.contains(model.me?.email ?? "")
                        ServerCard(server: server, joined: joined, busy: busy == server.id) {
                            if joined { onOpen(server) } else { Task { await join(server) } }
                        }
                    }
                }
            }
            .padding(12)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func join(_ server: Server) async {
        guard let me = model.me else { return }
        busy = server.id
        defer { busy = nil }
        do {
            try await Servers.join(server, me: me)
            var joined = server
            joined.members.append(me.email)
            model.showToast("Welcome to \(server.name)!", icon: "party.popper.fill")
            onJoined(joined)
        } catch {
            model.showToast("Couldn't join — try again", error: true)
        }
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
                            Theme.pastel
                        } else {
                            RemoteImage(url: server.bannerURL)
                        }
                    }
                    .frame(height: 70)
                    .clipped()
                    ServerIcon(server: server, size: 52)
                        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Palette.surface, lineWidth: 3))
                        .offset(x: 12, y: 24)
                }
                .frame(height: 70)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(server.name).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        if !server.description.isEmpty {
                            Text(server.description).font(.jakarta(12)).foregroundStyle(Palette.text2).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Label("\(server.members.count) members", systemImage: "person.2.fill").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 6)
                    Group {
                        if busy {
                            ProgressView().tint(Theme.main)
                        } else if joined {
                            Text("Open").font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                                .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 12).frame(height: 30).background(Theme.soft, in: Capsule())
                                .transition(.blurSwap)
                        } else {
                            Text("Join").font(.jakarta(12, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 30).background(Theme.gradient, in: Capsule())
                                .shadow(color: Palette.shadow, radius: 6, y: 3)
                                .transition(.blurSwap)
                        }
                    }
                    // Join turns into Open in one soft morph.
                    .motion(.spring(response: 0.34, dampingFraction: 0.78), value: joined)
                }
                .padding(.horizontal, 12)
                .padding(.top, 30)
                .padding(.bottom, 12)
            }
            .sugarCard(radius: 22)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }
}

// MARK: - One server: banner, channels (with who's in voice), roles

struct ServerPanel: View {
    @Bindable var store: ServerStore
    @Binding var path: [Route]
    var onLeft: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(VoiceEngine.self) private var voice
    @State private var settings = false
    @State private var membersShown = false
    @State private var confirmLeave = false
    @State private var editingChannel: ServerChannel?
    @State private var newChannelType: String?

    private var me: String { model.me?.email ?? "" }
    private var access: Access { store.access(me, siteAdmin: model.me?.isAdmin ?? false) }
    private var online: Int { store.server.members.filter { model.person($0)?.isOnline == true }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !store.server.welcome.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.wave.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.gradient)
                        Text(store.server.welcome).font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Palette.cream, Palette.blush.opacity(0.7)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
                }
                if !store.loaded {
                    ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 44, radius: 14) }
                }
                let visible = store.channels.filter { store.canView($0, access) }
                section("TEXT CHANNELS", type: "text", visible.filter { !$0.isVoice })
                section("VOICE CHANNELS", type: "voice", visible.filter(\.isVoice))
                rolesSummary
            }
            .padding(12)
            .padding(.bottom, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        .task(id: store.server.id) {
            // Keep "who's in voice" fresh.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                await store.loadVoice()
            }
        }
        .sheet(isPresented: $settings) {
            ServerSettingsView(store: store, onDeleted: onLeft).presentationCornerRadius(32)
        }
        .sheet(isPresented: $membersShown) {
            MembersSheet(store: store) { route in
                membersShown = false
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); path.append(route) }
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
        }
        .sheet(item: $editingChannel) { channel in
            ChannelEditor(store: store, channel: channel, type: channel.type).presentationCornerRadius(32)
        }
        .sheet(item: Binding(get: { newChannelType.map { NewChannelKind(type: $0) } }, set: { newChannelType = $0?.type })) { kind in
            ChannelEditor(store: store, channel: nil, type: kind.type).presentationCornerRadius(32)
        }
        .confirmationDialog("Leave \(store.server.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave server", role: .destructive) {
                guard let meProfile = model.me else { return }
                Task {
                    try? await Servers.leave(store.server, me: meProfile)
                    model.showToast("You left \(store.server.name)", icon: "door.left.hand.open")
                    onLeft()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if store.server.bannerURL.isEmpty {
                    Theme.pastel
                } else {
                    RemoteImage(url: store.server.bannerURL, live: true)
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                ServerIcon(server: store.server, size: 60)
                    .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Palette.bg, lineWidth: 4))
                    .shadow(color: Palette.shadow, radius: 10, y: 4)
                    .offset(x: 12, y: 30)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.server.name).font(.display(26)).foregroundStyle(Palette.text).lineLimit(2)
                    HStack(spacing: 10) {
                        Label("\(store.server.members.count)", systemImage: "person.2.fill").foregroundStyle(Palette.muted)
                        Label("\(online) online", systemImage: "circle.fill").foregroundStyle(Palette.success)
                    }
                    .font(.jakarta(12, .bold))
                }
                Spacer()
            }
            .padding(.top, 38)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("person.2.fill", "Members") { membersShown = true }
                    if access.can(.create_invite) {
                        pill("link", "Invite") {
                            UIPasteboard.general.string = "\(Servers.site)/CommunityChat?id=\(store.server.id)"
                            model.showToast("Invite link copied", icon: "link")
                        }
                    }
                    if access.can(.manage_server) || access.can(.manage_roles) || access.can(.manage_channels) {
                        pill("gearshape.fill", "Settings") { settings = true }
                    }
                    if !access.isOwner && store.server.members.contains(me) {
                        pill("rectangle.portrait.and.arrow.right", "Leave") { confirmLeave = true }
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func pill(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Theme.soft, in: Capsule())
        }
        .buttonStyle(BouncyStyle())
    }

    @ViewBuilder
    private func section(_ title: String, type: String, _ list: [ServerChannel]) -> some View {
        if !list.isEmpty || access.can(.manage_channels) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.jakarta(11, .heavy)).tracking(1.1).foregroundStyle(Palette.muted)
                    Spacer()
                    if access.can(.manage_channels) {
                        Button { newChannelType = type } label: {
                            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.muted).frame(width: 30, height: 26)
                        }
                        .accessibilityLabel("Add a \(type) channel")
                    }
                }
                .padding(.leading, 6)
                ForEach(list) { channel in
                    channelRow(channel)
                }
            }
        }
    }

    private func channelRow(_ channel: ServerChannel) -> some View {
        let inVoice = store.voice[channel.id] ?? []
        let here = voice.room?.id == channel.id
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if channel.isVoice { path.append(.voice(store.server, channel)) } else { path.append(.channel(store.server, channel)) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: channel.isVoice ? "speaker.wave.2.fill" : "number")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(here ? .white : Theme.main)
                        .frame(width: 32, height: 32)
                        .background(here ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.soft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(channel.name).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                            if channel.isPrivate { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                        }
                        if !channel.description.isEmpty {
                            Text(channel.description).font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if channel.isVoice && !inVoice.isEmpty {
                        Text("\(inVoice.count)").font(.jakarta(11, .heavy)).foregroundStyle(Palette.success)
                            .padding(.horizontal, 7).frame(height: 20).background(Palette.success.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frostedFill(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.97))
            .contextMenu {
                if access.can(.manage_channels) {
                    Button { editingChannel = channel } label: { Label("Edit channel", systemImage: "pencil") }
                    Button(role: .destructive) {
                        Task {
                            try? await FS.delete("ServerChannel", channel.id)
                            await store.load()
                        }
                    } label: { Label("Delete channel", systemImage: "trash") }
                }
            }
            if channel.isVoice && !inVoice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(inVoice) { p in
                        HStack(spacing: 8) {
                            Avatar(url: model.person(p.email)?.picture ?? p.picture, name: p.name, size: 22)
                            Text(model.person(p.email)?.displayName ?? p.name).font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                            if p.muted { Image(systemName: "mic.slash.fill").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                            if p.deafened { Image(systemName: "speaker.slash.fill").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                        }
                    }
                }
                .padding(.leading, 50)
            }
        }
    }

    // Roles with their colours, like the website's member list header.
    @ViewBuilder
    private var rolesSummary: some View {
        let roles = store.sortedRoles
        if !roles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ROLES").font(.jakarta(11, .heavy)).tracking(1.1).foregroundStyle(Palette.muted).padding(.leading, 6)
                FlowLayout(spacing: 6) {
                    ForEach(roles) { role in
                        let count = store.members.filter { $0.roles.contains(role.id) }.count
                        HStack(spacing: 5) {
                            Circle().fill(role.tint).frame(width: 9, height: 9)
                            Text(role.name).font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                            Text("\(count)").font(.jakarta(11, .heavy)).foregroundStyle(Palette.muted)
                        }
                        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 28)
                        .frostedFill(in: Capsule())
                        .overlay(Capsule().strokeBorder(role.tint.opacity(0.4), lineWidth: 1))
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

struct NewChannelKind: Identifiable { var type: String; var id: String { type } }
struct EmailBox: Identifiable { var email: String; var id: String { email } }

// MARK: - Create a server

struct CreateServerView: View {
    var onCreate: (Server) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var template: ServerTemplate = .art
    @State private var name = ""
    @State private var about = ""
    @State private var welcome = ""
    @State private var icon: PhotosPickerItem?
    @State private var iconImage: UIImage?
    @State private var busy = false
    @State private var error: String?


    var body: some View {
        ComposerScaffold(title: "Create a server", actionTitle: "Create", busy: busy, canPost: !name.trimmingCharacters(in: .whitespaces).isEmpty, onClose: { dismiss() }, onPost: { Task { await create() } }) {
            VStack(alignment: .leading, spacing: 18) {
                Text("START FROM").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                VStack(spacing: 8) {
                    ForEach(ServerTemplate.allCases) { t in
                        Button { withMotion(Motion.standard) { template = t } } label: {
                            HStack(spacing: 14) {
                                Image(systemName: t.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.gradient).frame(width: 50, height: 50).background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.label).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                                    Text(t.channels.map { $0.type == "voice" ? "\($0.name) (voice)" : "#\($0.name)" }.joined(separator: "  ·  "))
                                        .font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if template == t { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.gradient) }
                            }
                            .padding(12)
                            .frostedFill(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(template == t ? Theme.main : Palette.border, lineWidth: template == t ? 2 : 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.97))
                    }
                }
                Text("ICON").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                HStack(spacing: 14) {
                    PhotosPicker(selection: $icon, matching: .images) {
                        ZStack {
                            LinearGradient(colors: [Theme.light, Theme.main], startPoint: .top, endPoint: .bottom)
                            if let iconImage { Image(uiImage: iconImage).resizable().scaledToFill() }
                            else { Text(ServerIcon.initials(name.isEmpty ? "Server" : name)).font(.display(28)).foregroundStyle(.white) }
                        }
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 26, height: 26).background(Theme.gradient, in: Circle()).offset(x: 4, y: 4)
                        }
                    }
                    Text("Upload a picture, or keep the letters from the server's name.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                SugarField(placeholder: "Server name", text: $name)
                SugarField(placeholder: "What's it about?", text: $about, lines: 2...4)
                SugarField(placeholder: "Welcome message for new members", text: $welcome)
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
        .onChange(of: icon) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { iconImage = image }
            }
        }
    }

    private func create() async {
        guard let meProfile = model.me else { return }
        guard await TextGuard.clear([name], kind: .name, model: model),
              await TextGuard.clear([about, welcome], kind: .profile, model: model, cooldown: false) else { return }
        busy = true
        defer { busy = false }
        do {
            var iconURL = ""
            if let iconImage, let jpeg = ImageTools.jpeg(iconImage, maxSide: 512) {
                iconURL = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            }
            let server = try await Servers.create(me: meProfile, name: String(name.trimmingCharacters(in: .whitespaces).prefix(40)), description: String(about.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)), emoji: "", iconURL: iconURL, welcome: String(welcome.trimmingCharacters(in: .whitespaces).prefix(160)), template: template)
            dismiss()
            model.showToast("\(server.name) is ready!", icon: "sparkles")
            onCreate(server)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
