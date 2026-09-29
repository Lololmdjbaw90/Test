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

enum AppTab: Hashable {
    case home, community, gallery, reels, chat, me
    var order: Int {
        switch self {
        case .home: 0
        case .community: 1
        case .gallery: 2
        case .reels: 3
        case .chat: 4
        case .me: 5
        }
    }
}

enum Composer: String, Identifiable { case post, artwork, reel, track; var id: String { rawValue } }

// Pages open and close in place, without the sideways slide.
extension Binding where Value == [Route] {
    var instant: Binding<[Route]> {
        Binding(get: { wrappedValue }, set: { next in
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { wrappedValue = next }
        })
    }
}

// Where a tap leads, shared by every tab's navigation stack.
struct RouteView: View {
    let route: Route
    @Binding var path: [Route]

    var body: some View {
        page
            // Our own back button (and a swipe from the left edge), both
            // instant, instead of the system one that slides.
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Back")
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { drag in
                    if drag.startLocation.x < 28, drag.translation.width > 90, abs(drag.translation.height) < 70 { back() }
                }
            )
    }

    private func back() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    @ViewBuilder
    private var page: some View {
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

}

// Presses squish a little and spring back, with a light tap (all buttons).
struct BouncyStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .clickSound(configuration.isPressed)
    }
}

extension View {
    // A soft pop when a button goes down.
    func clickSound(_ pressed: Bool, _ kind: TapSound.Kind = .tap) -> some View {
        onChange(of: pressed) { _, down in if down { TapSound.play(kind) } }
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
    @State private var calls = CallCenter()
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
    @State private var menuSheet: MenuSheet?

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
        case .home: return $homePath.instant
        case .community: return $communityPath.instant
        case .gallery: return $galleryPath.instant
        case .reels: return $reelsPath.instant
        case .chat: return $chatPath.instant
        case .me: return $mePath.instant
        }
    }

    // The six tabs, each with its own navigation stack.
    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath.instant) {
                HomeView(path: $homePath.instant, compose: { composer = $0 }).sugarRoutes($homePath.instant)
            }
            .tag(AppTab.home)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $communityPath.instant) {
                CommunityView(path: $communityPath.instant, compose: { composer = .post }).sugarRoutes($communityPath.instant)
            }
            .tag(AppTab.community)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $galleryPath.instant) {
                GalleryView(path: $galleryPath.instant, isRoot: true).sugarRoutes($galleryPath.instant)
            }
            .tag(AppTab.gallery)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $reelsPath.instant) {
                ReelsView(visible: tab == .reels && reelsPath.isEmpty, path: $reelsPath.instant, create: { composer = .reel }).sugarRoutes($reelsPath.instant)
            }
            .tag(AppTab.reels)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $chatPath.instant) {
                ChatListView(path: $chatPath.instant).sugarRoutes($chatPath.instant)
            }
            .tag(AppTab.chat)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $mePath.instant) {
                PersonView(email: model.me?.email ?? "", path: $mePath.instant)
                    .sugarTopBar($mePath.instant)
                    .sugarRoutes($mePath.instant)
            }
            .tag(AppTab.me)
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // Pop-ups over everything: notifications and the quick menu.
    @ViewBuilder
    private var popups: some View {
        if model.showNotifications {
            NotificationsPopup(path: currentPathBinding) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.showNotifications = false }
            }
            .transition(.opacity)
            .zIndex(5)
        }
        if model.showMenu {
            QuickMenu(close: closeMenu, go: { route in
                closeMenu()
                currentPathBinding.wrappedValue.append(route)
            }, open: { sheet in
                closeMenu()
                menuSheet = sheet
            })
            .transition(.opacity)
            .zIndex(6)
        }
    }

    @ViewBuilder
    private func menuSheetView(_ sheet: MenuSheet) -> some View {
        switch sheet {
        case .settings: SettingsView()
        case .shop: NitroShopView()
        case .status: StatusSheet().presentationCornerRadius(30)
        case .legal(let doc): LegalView(doc: doc)
        }
    }

    // Tabs, tab bar, pop-ups and the shared stores.
    private var core: some View {
        tabs
        .environment(\.backgroundPaused, menuSheet != nil || composer != nil || model.showMenu || model.showNotifications)
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
        .overlay { ZStack { popups } }
        .sheet(item: $menuSheet) { sheet in menuSheetView(sheet) }
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
        .environment(calls)
    }

    var body: some View {
        core
        .overlay(alignment: .top) {
            if let incoming = calls.incoming {
                IncomingCallBanner(call: incoming)
                    .environment(calls)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { calls.showScreen }, set: { calls.showScreen = $0 })) {
            CallScreen().environment(calls).environment(voice).environment(model)
        }
        .task {
            calls.attach(voice: voice)
        }
        // Signing out: stop the music and leave any call.
        .onReceive(NotificationCenter.default.publisher(for: AppModel.signingOut)) { _ in
            player.pause()
            if calls.current != nil { Task { await calls.hangUp() } }
            if voice.room != nil { Task { await voice.leave(silent: true) } }
        }
        .task(id: model.me?.email) {
            if let me = model.me { await calls.watch(me: me) }
        }
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
        // Live names, pictures and online status while the app is open
        // (and straight away when you come back to it).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            var tick = 0
            while !Task.isCancelled {
                await model.syncProfiles(presence: tick % 4 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .background { Alerts.shared.scheduleBackground() }
            guard scenePhase == .active else { return }
            var tick = 0
            while !Task.isCancelled {
                let me = model.me?.email ?? ""
                await chats.refresh(me: me)
                if tick % 6 == 0 { await notes.refresh(me: me) }
                Alerts.shared.following = model.me?.following ?? []
                let muted = Set((model.me?.ignored ?? []) + (model.me?.blocked ?? []))
                Alerts.shared.muted = muted
                chats.muted = muted
                Alerts.shared.doNotDisturb = model.me?.presence == "dnd"
                // Stay "online" for others while the app is open.
                if tick % 8 == 0, let uid = model.me?.id { Task { try? await FS.update("User", uid, ["last_seen": FS.nowISO()]) } }
                if tick % 8 == 4 { await model.checkBan() }
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
    fileprivate func closeMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { model.showMenu = false }
    }

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
            Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { model.showMenu = true } } label: {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 38, ring: true,
                       presence: Presence(rawValue: model.me?.presence ?? "") ?? .online)
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

    // Older notifications, a page at a time, as you scroll the list.
    var hasOlder = true
    private var loadingOlder = false

    func loadOlder(me: String) async {
        guard hasOlder, !loadingOlder, let oldest = items.last?.created, !me.isEmpty else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let docs = try? await FS.query("Notification", [.equals("to_email", me), .before("created_date", oldest)], orderBy: "created_date", limit: 40) else { return }
        hasOlder = docs.count >= 40
        let known = Set(items.map(\.id))
        items += docs.map(AppNotification.init).filter { !known.contains($0.id) }
    }

    func markAllRead() {
        let unread = items.filter { !$0.read }
        for i in items.indices { items[i].read = true }
        for n in unread { Task { try? await FS.update("Notification", n.id, ["is_read": true]) } }
    }
}
