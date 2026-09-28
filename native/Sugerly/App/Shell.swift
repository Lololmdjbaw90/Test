import SwiftUI
import UIKit

enum Route: Hashable {
    case post(Post)
    case person(String)
    case chat(Conversation)
    case artwork(Artwork)
    case reel(Reel)
    case gallery
    case music
    case admin
    case servers
    case people
    case commissions
    case topArtists
    case updates
    case server(Server)
    case channel(Server, ServerChannel)
    case voice(Server, ServerChannel)
}

enum AppTab: Hashable { case home, community, gallery, reels, chat, me }

enum Composer: String, Identifiable { case post, artwork, reel, track; var id: String { rawValue } }

// Where a tap leads, shared by every tab's navigation stack.
struct RouteView: View {
    let route: Route
    @Binding var path: [Route]

    var body: some View {
        switch route {
        case .post(let post): PostDetailView(postId: post.id, initial: post, path: $path)
        case .person(let email): PersonView(email: email, path: $path)
        case .chat(let conversation): ChatView(conversation: conversation)
        case .artwork(let artwork): ArtworkDetailView(artwork: artwork, path: $path)
        case .reel(let reel): SingleReelView(reel: reel, path: $path)
        case .gallery: GalleryView(path: $path)
        case .music: MusicView(path: $path)
        case .admin: AdminView()
        case .servers: ServerHubView(path: $path).navigationTitle("Servers").navigationBarTitleDisplayMode(.inline).sugarBackground()
        case .people: PeopleView(path: $path)
        case .commissions: CommissionsView(path: $path)
        case .topArtists: TopArtistsView(path: $path)
        case .updates: UpdatesView()
        case .server(let server): ServerHubView(path: $path, initial: server).navigationTitle(server.name).navigationBarTitleDisplayMode(.inline).sugarBackground()
        case .channel(let server, let channel): ChannelChatView(server: server, channel: channel)
        case .voice(let server, let channel): VoiceRoomView(server: server, channel: channel)
        }
    }
}

extension View {
    func sugarRoutes(_ path: Binding<[Route]>) -> some View {
        navigationDestination(for: Route.self) { route in RouteView(route: route, path: path) }
    }

    // Page background: warm off-white with two soft accent glows.
    func sugarBackground() -> some View {
        background {
            ZStack {
                Palette.bg
                Circle().fill(Theme.light.opacity(0.32)).frame(width: 360).blur(radius: 95).offset(x: 150, y: -300)
                Circle().fill(Theme.lavender.opacity(0.18)).frame(width: 320).blur(radius: 95).offset(x: -170, y: 260)
                Circle().fill(Color(hex: 0xFFD6A5).opacity(0.14)).frame(width: 240).blur(radius: 80).offset(x: 140, y: 120)
            }
            .drawingGroup()
            .ignoresSafeArea()
        }
    }
}

// Presses squish a little and spring back, with a light tap (all buttons).
struct BouncyStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - App shell

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    @State private var chats = ChatStore()
    @State private var posts = PostsStore()
    @State private var player = Player()
    @State private var notes = NotificationsStore()
    @State private var voice = VoiceEngine()
    @State private var homePath: [Route] = []
    @State private var communityPath: [Route] = []
    @State private var galleryPath: [Route] = []
    @State private var reelsPath: [Route] = []
    @State private var chatPath: [Route] = []
    @State private var mePath: [Route] = []
    @State private var creating = false
    @State private var pendingComposer: Composer?
    @State private var composer: Composer?
    @State private var typing = false
    @State private var dailyShown = false

    private var currentPath: [Route] {
        switch tab {
        case .home: return homePath
        case .community: return communityPath
        case .gallery: return galleryPath
        case .reels: return reelsPath
        case .chat: return chatPath
        case .me: return mePath
        }
    }
    private var barHidden: Bool { typing || !currentPath.isEmpty }

    private var currentPathBinding: Binding<[Route]> {
        switch tab {
        case .home: return $homePath
        case .community: return $communityPath
        case .gallery: return $galleryPath
        case .reels: return $reelsPath
        case .chat: return $chatPath
        case .me: return $mePath
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(path: $homePath, compose: { composer = $0 }).sugarRoutes($homePath)
            }
            .tag(AppTab.home)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $communityPath) {
                CommunityView(path: $communityPath, compose: { composer = .post }).sugarRoutes($communityPath)
            }
            .tag(AppTab.community)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $galleryPath) {
                GalleryView(path: $galleryPath, isRoot: true).sugarRoutes($galleryPath)
            }
            .tag(AppTab.gallery)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $reelsPath) {
                ReelsView(visible: tab == .reels && reelsPath.isEmpty, path: $reelsPath, create: { composer = .reel }).sugarRoutes($reelsPath)
            }
            .tag(AppTab.reels)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $chatPath) {
                ChatListView(path: $chatPath).sugarRoutes($chatPath)
            }
            .tag(AppTab.chat)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $mePath) {
                PersonView(email: model.me?.email ?? "", path: $mePath)
                    .sugarTopBar($mePath)
                    .sugarRoutes($mePath)
            }
            .tag(AppTab.me)
            .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !barHidden {
                VStack(spacing: 8) {
                    VoiceDock()
                    if tab != .reels { MiniPlayer() }
                    SugarTabBar(tab: $tab, unread: chats.unread, dark: tab == .reels) { creating = true }
                }
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if model.showNotifications {
                NotificationsPopup(path: currentPathBinding) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.showNotifications = false }
                }
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .onChange(of: model.tabRequest) { _, next in
            guard let next else { return }
            tab = next
            model.tabRequest = nil
        }
        .onChange(of: Alerts.shared.destination) { _, dest in
            guard let dest else { return }
            Alerts.shared.destination = nil
            Task { await open(dest.kind, dest.target) }
        }
        .onOpenURL { url in
            // Widgets: sugerly://chat, sugerly://gallery, sugerly://alerts …
            Task { await open(url.host() ?? "", "") }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .onTapGesture { withAnimation { model.toast = nil } }
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: barHidden)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.track?.id)
        .environment(chats)
        .environment(posts)
        .environment(player)
        .environment(notes)
        .environment(voice)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.room?.id)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
        .sheet(isPresented: $creating, onDismiss: {
            if let pendingComposer { composer = pendingComposer; self.pendingComposer = nil }
        }) {
            CreateSheet { choice in pendingComposer = choice; creating = false }
                .presentationDetents([.height(430)])
                .presentationCornerRadius(34)
        }
        .onChange(of: model.soundRequest?.id) { _, id in
            if id != nil { composer = .reel }
        }
        .fullScreenCover(item: $composer) { kind in
            switch kind {
            case .post: NewPostView { await posts.load() }
            case .artwork: NewArtworkView()
            case .track: NewTrackView()
            case .reel: ReelStudioView()
            }
        }
        .sheet(isPresented: $dailyShown) {
            DailyRewardSheet().presentationDetents([.height(520)]).presentationCornerRadius(34)
        }
        .task {
            // Daily login: pop the reward once a day.
            try? await Task.sleep(for: .seconds(1.2))
            if model.me?.lastDailyClaim != DailyReward.todayKey() { dailyShown = true }
        }
        .task { await Alerts.shared.requestPermission() }
        .task(id: scenePhase) {
            if scenePhase == .background { Alerts.shared.scheduleBackground() }
            guard scenePhase == .active else { return }
            var tick = 0
            while !Task.isCancelled {
                let me = model.me?.email ?? ""
                await chats.refresh(me: me)
                if tick % 6 == 0 { await notes.refresh(me: me) }
                Alerts.shared.following = model.me?.following ?? []
                if tick % 2 == 0 { await Alerts.shared.check() }
                Alerts.shared.setBadge(chats.unread + notes.unread)
                WidgetBridge.update(model: model, unreadDMs: chats.unread, unreadAlerts: notes.unread)
                tick += 1
                let base: Double = tab == .chat ? 6 : 15
                try? await Task.sleep(for: .seconds(base * (FS.missingIndex.contains("DirectMessage") ? 2 : 1)))
            }
        }
    }
}

extension MainShell {
    // Opens the place a notification or widget points at.
    func open(_ kind: String, _ target: String) async {
        switch kind {
        case "dm", "chat":
            tab = .chat
            guard !target.isEmpty else { return }
            let me = model.me?.email ?? ""
            if chats.conversations.first(where: { $0.id == target }) == nil { await chats.refresh(me: me) }
            if let c = chats.conversations.first(where: { $0.id == target }) {
                chatPath = [.chat(c)]
            } else if target.contains("__dm__") {
                let members = target.components(separatedBy: "__dm__")
                chatPath = [.chat(Conversation(id: target, members: members, isGroup: false, groupName: "", last: nil, unread: 0))]
            }
        case "server":
            tab = .chat
            UserDefaults.standard.set(1, forKey: "sugerly.chat.section")
            if !target.isEmpty, let doc = try? await FS.get("Community", target) { chatPath = [.server(Server(doc))] }
        case "reels": tab = .reels
        case "gallery": tab = .gallery
        case "home": tab = .home
        case "alerts", "social":
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.showNotifications = true }
        default: break
        }
    }
}

// MARK: - Floating tab bar: one soft pill, the pink + raised in the middle

struct SugarTabBar: View {
    @Binding var tab: AppTab
    var unread: Int
    var dark: Bool
    var onCreate: () -> Void
    @Namespace private var lens
    @State private var plusSpin = false
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "Home", "house", "house.fill")
            item(.community, "Community", "person.2", "person.2.fill")
            item(.gallery, "Gallery", "paintpalette", "paintpalette.fill")
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { plusSpin.toggle() }
                onCreate()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(plusSpin ? 90 : 0))
                    .frame(width: 58, height: 58)
                    .background(Theme.gradient, in: Circle())
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)).padding(2))
                    .shadow(color: Theme.main.opacity(0.45), radius: 12, y: 5)
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            .padding(.horizontal, 4)
            .accessibilityLabel("Create")
            item(.reels, "Reels", "film.stack", "film.stack.fill")
            item(.chat, "Chat", "bubble.left", "bubble.left.fill", badge: unread)
            meItem
        }
        .padding(.horizontal, 6)
        .frame(height: 70)
        .background {
            Capsule().fill(dark ? Color(hex: 0x2A2226) : Palette.surface)
                .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.1) : Palette.border, lineWidth: 1))
                .shadow(color: dark ? .black.opacity(0.4) : Theme.main.opacity(0.14), radius: 18, y: 8)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.75), value: tab)
        .padding(.horizontal, 12)
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String, _ filled: String, badge: Int = 0) -> some View {
        let active = tab == t
        return Button { select(t) } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? filled : icon)
                    .font(.system(size: 19, weight: .medium))
                    .symbolEffect(.bounce.up, value: active)
                Text(title).font(.jakarta(10, .bold)).lineLimit(1).minimumScaleFactor(0.65)
            }
            .foregroundStyle(active ? (dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.main)) : AnyShapeStyle(dark ? Color.white.opacity(0.6) : Palette.muted))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background { lensView(active) }
            .overlay(alignment: .topTrailing) { badgeView(badge) }
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel(title)
    }

    private var meItem: some View {
        let active = tab == .me
        return Button { select(.me) } label: {
            VStack(spacing: 3) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 22)
                    .overlay(Circle().strokeBorder(active ? Theme.main : Color.clear, lineWidth: 1.5))
                Text("Me").font(.jakarta(10, .bold))
            }
            .foregroundStyle(active ? (dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.main)) : AnyShapeStyle(dark ? Color.white.opacity(0.6) : Palette.muted))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background { lensView(active) }
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel("Your profile")
    }

    @ViewBuilder
    private func lensView(_ active: Bool) -> some View {
        if active {
            Capsule()
                .fill(dark ? Color.white.opacity(0.12) : Color.white)
                .overlay(Capsule().fill(dark ? Color.clear : Theme.main.opacity(0.06)))
                .shadow(color: dark ? .clear : Theme.main.opacity(0.18), radius: 8, y: 3)
                .padding(.horizontal, 2)
                .matchedGeometryEffect(id: "lens", in: lens)
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: Int) -> some View {
        if badge > 0 {
            Text(badge > 9 ? "9+" : "\(badge)")
                .font(.jakarta(10, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Theme.gradient, in: Capsule())
                .overlay(Capsule().strokeBorder(dark ? Color.clear : .white, lineWidth: 1.5))
                .offset(x: -2, y: 2)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func select(_ t: AppTab) {
        guard tab != t else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { tab = t }
    }
}

// MARK: - Top bar (logo, notifications, you)

struct TopBar: View {
    @Binding var path: [Route]
    var title: String? = nil
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @State private var more = false
    @State private var searching = false

    var body: some View {
        HStack(spacing: 10) {
            BrandLogo(height: 34)
            Spacer()
            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 42, height: 42)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                    .shadow(color: Palette.shadow, radius: 6, y: 2)
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Search")
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.showNotifications = true } } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 42, height: 42)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                    .shadow(color: Palette.shadow, radius: 6, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if notes.unread > 0 {
                            Text(notes.unread > 9 ? "9+" : "\(notes.unread)")
                                .font(.jakarta(10, .heavy)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Theme.gradient, in: Capsule())
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Notifications")
            Button { more = true } label: {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 38, ring: true)
                    .shadow(color: Theme.pink.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Rectangle().fill(Palette.bg)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.border.opacity(0.7)).frame(height: 0.5) }
                .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: $searching) {
            SearchView { route in path.append(route) }
                .presentationDetents([.large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $more) {
            MoreSheet(path: $path).presentationDetents([.medium, .large]).presentationCornerRadius(34)
        }
    }
}

extension View {
    // Tab root screens: our own top bar instead of the system navigation bar.
    func sugarTopBar(_ path: Binding<[Route]>) -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { TopBar(path: path) }
    }
}

// MARK: - The + menu

struct CreateSheet: View {
    var onPick: (Composer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create something").font(.display(28)).foregroundStyle(Palette.text).padding(.top, 26)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile(.reel, "Create a reel", "Film or pick a video", "video.fill", [Color(hex: 0xFF7AA2), Color(hex: 0xD9577F)])
                tile(.post, "Post", "Share with the community", "text.bubble.fill", [Color(hex: 0xB19CFF), Color(hex: 0x7C5CF0)])
                tile(.artwork, "Artwork", "Add to the gallery", "paintpalette.fill", [Color(hex: 0xFFAA80), Color(hex: 0xEE6E40)])
                tile(.track, "Track", "Share your music", "music.note", [Color(hex: 0x7CBEFF), Color(hex: 0x2F80E0)])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .sugarBackground()
    }

    private func tile(_ kind: Composer, _ title: String, _ sub: String, _ icon: String, _ colors: [Color]) -> some View {
        Button { onPick(kind) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: colors[1].opacity(0.45), radius: 10, y: 5)
                Text(title).font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
                Text(sub).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sugarCard(radius: 24, padding: 16)
        }
        .buttonStyle(BouncyStyle())
    }
}

// MARK: - Menu behind your avatar

struct MoreSheet: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = false
    @State private var shop = false
    @State private var legal: LegalDoc?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let me = model.me {
                    let info = LevelInfo(xp: me.xp)
                    Button { go(.person(me.email)) } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                Avatar(url: me.picture, name: me.displayName, size: 62, ring: true, nitro: me.isNitro)
                                VStack(alignment: .leading, spacing: 4) {
                                    NameText(name: me.displayName, style: me.nameStyle, size: 26, display: true, nitro: me.isNitro).lineLimit(1)
                                    Text("Lv. \(info.level) · \(info.title)").font(.jakarta(13, .bold)).foregroundStyle(info.color)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(Palette.muted)
                            }
                            HStack(spacing: 8) {
                                miniStat("\(me.coins)", "Coins", "circle.hexagongrid.fill", Color(hex: 0xF0A020))
                                miniStat("\(me.dailyStreak)", "Streak", "flame.fill", Color(hex: 0xF08A20))
                                miniStat("\(me.following.count)", "Following", "heart.fill", Theme.main)
                            }
                            XPBar(info: info)
                        }
                        .padding(16)
                        .sugarCard(radius: 28)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.97))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile("Nitro", "sparkles", [0xC084FC, 0x8B5CF6]) { shop = true }
                    tile("Music", "music.note", [0xFF7AA2, 0xD9577F]) { go(.music) }
                    tile("Servers", "person.3.fill", [0xFF9EC4, 0xE0508A]) { go(.servers) }
                    tile("People", "person.crop.circle.badge.plus", [0xFFD166, 0xF08A20]) { go(.people) }
                    tile("Commissions", "storefront.fill", [0x5FD3B0, 0x16A37F]) { go(.commissions) }
                    tile("Top artists", "crown.fill", [0xFFD166, 0xF0A020]) { go(.topArtists) }
                    tile("What's new", "sparkles", [0xFF9EC4, 0xE0508A]) { go(.updates) }
                    tile("Alerts", "bell.fill", [0xB19CFF, 0x7C5CF0]) {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.showNotifications = true }
                        }
                    }
                    tile("Settings", "gearshape.fill", [0x7CBEFF, 0x2F80E0]) { settings = true }
                    tile("Help", "questionmark.circle.fill", [0x5FD3B0, 0x16A37F]) { legal = .guidelines }
                    if model.me?.isAdmin == true {
                        tile("Admin", "shield.lefthalf.filled", [0xFFD166, 0xF0A020]) { go(.admin) }
                    }
                }

                Button {
                    Task {
                        let next = model.me?.theme == "dark" ? "light" : "dark"
                        try? await model.updateMe(["theme": next])
                    }
                } label: {
                    Label(model.me?.theme == "dark" ? "Light mode" : "Dark mode", systemImage: model.me?.theme == "dark" ? "sun.max.fill" : "moon.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
            }
            .padding(20)
        }
        .patternBackground()
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $shop) { NitroShopView() }
        .sheet(item: $legal) { doc in LegalView(doc: doc) }
    }

    private func go(_ route: Route) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            path.append(route)
        }
    }

    private func miniStat(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                Text(label).font(.jakarta(10, .semibold)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tile(_ title: String, _ icon: String, _ colors: [UInt32], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: Color(hex: colors[1]).opacity(0.4), radius: 8, y: 4)
                Text(title).font(.jakarta(13, .bold)).foregroundStyle(Palette.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .sugarCard(radius: 22)
        }
        .buttonStyle(BouncyStyle())
    }
}

// MARK: - Notifications (checked in the background, like chats)

@MainActor
@Observable
final class NotificationsStore {
    var items: [AppNotification] = []
    var unread: Int { items.filter { !$0.read }.count }
    private var newest = ""
    private var loaded = false

    func refresh(me: String) async {
        guard !me.isEmpty else { return }
        var filters: [FS.Filter] = [.equals("to_email", me)]
        if loaded, !newest.isEmpty { filters.append(.after("created_date", ChatStore.minus(newest, seconds: 60))) }
        guard let docs = try? await FS.query("Notification", filters, orderBy: "created_date", limit: loaded ? 30 : 60) else { return }
        let fresh = docs.map(AppNotification.init)
        let known = Set(items.map(\.id))
        items = (items + fresh.filter { !known.contains($0.id) }).sorted { $0.created > $1.created }
        newest = items.first?.created ?? newest
        loaded = true
    }

    func markAllRead() {
        let unread = items.filter { !$0.read }
        for i in items.indices { items[i].read = true }
        for n in unread { Task { try? await FS.update("Notification", n.id, ["is_read": true]) } }
    }
}
