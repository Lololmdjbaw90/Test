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
    case commissionOrder(String)
    case topArtists
    case updates
    case server(Server)
    case channel(Server, ServerChannel)
    case voice(Server, ServerChannel)
    case support
    case supportTicket(String)
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

// Pages open and close with the iPhone's own smooth animation. (Turning it
// off made pages jump, and could leave a page without its top bar, so the
// back button wasn't there.)
extension Binding where Value == [Route] {
    var instant: Binding<[Route]> { self }
}

// Swipe from the left edge to go back on every page, also on the full
// screen ones (Reels, Music) whose top bar is hidden: hiding the bar
// normally turns the swipe off too.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && transitionCoordinator == nil && presentedViewController == nil
    }
}

// Where a tap leads, shared by every tab's navigation stack. Every page has
// exactly one back button: iPhone's own (with the swipe from the edge);
// pages never add a second one of their own.
struct RouteView: View {
    let route: Route
    @Binding var path: [Route]
    var loadContent = true

    var body: some View {
        page
            .navigationBarBackButtonHidden(fullScreen)
            .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
    }

    // Reels and Music bring their own back button.
    private var fullScreen: Bool {
        switch route {
        case .reel, .music: return true
        default: return false
        }
    }

    @ViewBuilder
    private var page: some View {
        switch route {
        case .post(let post): PostDetailView(postId: post.id, initial: post, path: $path)
        case .person(let email): PersonView(email: email, path: $path)
        case .chat(let conversation): ChatView(conversation: conversation, loadMessages: loadContent)
        case .artwork(let artwork): ArtworkDetailView(artwork: artwork, path: $path)
        case .reel(let reel): SingleReelView(reel: reel, path: $path)
        case .gallery: GalleryView(path: $path)
        case .music: MusicView(path: $path)
        case .admin: AdminView()
        case .servers: ServerHubView(path: $path).navigationTitle("Servers").navigationBarTitleDisplayMode(.inline).sugarBackground()
        case .people: PeopleView(path: $path)
        case .commissions: CommissionsView(path: $path)
        case .commissionOrder(let id): CommissionOrderView(orderId: id, path: $path)
        case .topArtists: TopArtistsView(path: $path)
        case .updates: UpdatesView()
        case .server(let server): ServerHubView(path: $path, initial: server).navigationTitle(server.name).navigationBarTitleDisplayMode(.inline).sugarBackground()
        case .channel(let server, let channel): ChannelChatView(server: server, channel: channel)
        case .voice(let server, let channel): VoiceRoomView(server: server, channel: channel)
        case .support: SupportView()
        case .supportTicket(let email): SupportTicketView(email: email)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .home
    @State private var chats = ChatStore()
    @State private var posts = PostsStore()
    @State private var player = Player()
    @State private var notes = NotificationsStore()
    @State private var voice = VoiceEngine.shared
    @State private var calls = CallCenter.shared
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
    @State private var openedAt = Date()

    // Right after logging in, background refreshes wait a moment so the first
    // screen can draw smoothly (coming back to the app doesn't wait).
    private func settle(_ seconds: Double) async {
        let left = seconds - Date().timeIntervalSince(openedAt)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
    }

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
    private var barHidden: Bool { typing || !currentPath.isEmpty || composer != nil || calls.showScreen }
    @State private var barHeight: CGFloat = 0
    // Room each main page keeps free at the bottom for the floating bar.
    private var room: CGFloat { barHidden ? 0 : barHeight + 8 }

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
                HomeView(path: $homePath.instant, compose: { composer = $0 }).tabRoom(room).sugarRoutes($homePath.instant)
            }
            .tag(AppTab.home)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $communityPath.instant) {
                CommunityView(path: $communityPath.instant, compose: { composer = .post }).tabRoom(room).sugarRoutes($communityPath.instant)
            }
            .tag(AppTab.community)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $galleryPath.instant) {
                GalleryView(path: $galleryPath.instant, isRoot: true).tabRoom(room).sugarRoutes($galleryPath.instant)
            }
            .tag(AppTab.gallery)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $reelsPath.instant) {
                ReelsView(visible: tab == .reels && reelsPath.isEmpty && !calls.showScreen, path: $reelsPath.instant, create: { composer = .reel }, bottomRoom: room).sugarRoutes($reelsPath.instant)
            }
            .tag(AppTab.reels)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $chatPath.instant) {
                ChatListView(path: $chatPath.instant).tabRoom(room).sugarRoutes($chatPath.instant)
            }
            .tag(AppTab.chat)
            .toolbar(.hidden, for: .tabBar)

            NavigationStack(path: $mePath.instant) {
                PersonView(email: model.me?.email ?? "", path: $mePath.instant)
                    .sugarTopBar($mePath.instant)
                    .tabRoom(room)
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
                // Let the menu finish fading away first: closing it and
                // sliding a page up in the same moment made both stutter.
                Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    menuSheet = sheet
                }
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
        // The bar floats on top; each page makes exactly its height of room
        // at the bottom (tabRoom), so nothing ends up hidden under it. (Room
        // made around the whole tab view didn't always reach every page.)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if !barHidden {
                    VStack(spacing: 8) {
                        VoiceDock()
                        if tab != .reels { MiniPlayer() }
                        SugarTabBar(tab: $tab, unread: chats.unread, dark: tab == .reels) { creating = true }
                    }
                    // On iPad the bar and the player stay a comfortable width
                    // in the middle instead of stretching edge to edge.
                    .frame(maxWidth: 600)
                    .padding(.bottom, 2)
                    .background(GeometryReader { g in Color.clear.preference(key: TabBarHeightKey.self, value: g.size.height) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            // Only the bar animates (never the pages underneath it): it slides
            // away when a page opens and back when you return.
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: barHidden)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: player.track?.id)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: voice.room?.id)
        }
        .onPreferenceChange(TabBarHeightKey.self) { height in
            if abs(height - barHeight) > 0.5 { barHeight = height }
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
            guard url.scheme?.lowercased() == "sugerly" else { return }
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let target = parts?.queryItems?.first(where: { ["id", "art", "post", "reel", "conversation"].contains($0.name) })?.value
                ?? url.pathComponents.dropFirst().first ?? ""
            Task { await open(url.host()?.lowercased() ?? "", target) }
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
            calls.reset()
        }
        .task(id: model.me?.email) {
            guard let me = model.me else { return }
            // This phone can be rung while the app is closed.
            await IncomingCalls.shared.upload()
            await calls.watch(me: me)
        }
        // Joining a call: the song stops so you can hear each other.
        .onChange(of: voice.room?.id) { _, id in
            if id != nil, player.playing { player.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in typing = false }
        // Leaving the app closes the keyboard without always saying so, which
        // left the bottom bar hidden when you came back. Coming back with the
        // keyboard still up tells us again.
        .onChange(of: scenePhase) { _, phase in if phase != .active { typing = false } }
        .onChange(of: tab) { _, _ in typing = false }
        .onChange(of: currentPath.isEmpty) { _, atRoot in
            if atRoot { typing = false }
        }
        .sheet(isPresented: $creating, onDismiss: {
            if let pendingComposer { composer = pendingComposer; self.pendingComposer = nil }
        }) {
            CreateSheet { choice in pendingComposer = choice; creating = false }
                .presentationDetents([.height(460), .large])
                .presentationCornerRadius(34)
        }
        .onChange(of: model.soundRequest?.id) { _, id in
            if id != nil { composer = .reel }
        }
        .fullScreenCover(item: $composer, onDismiss: { typing = false }) { kind in
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
            // First the notifications question (only ever asked once), then
            // the daily reward. On a new account both used to pop up at the
            // same moment and the reward sheet could get stuck. Nothing pops
            // up while the "Setting things up" screen is still showing.
            while model.settingUp { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            await Alerts.shared.requestPermission()
            try? await Task.sleep(for: .seconds(1.5))
            if model.me?.lastDailyClaim != DailyReward.todayKey() { dailyShown = true }
        }
        // Live names, pictures and online status while the app is open
        // (and straight away when you come back to it).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await settle(2.5)
            var tick = 0
            while !Task.isCancelled {
                await model.syncProfiles(presence: tick % 2 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .background {
                Alerts.shared.scheduleBackground()
                // Leaving the app: show as offline to friends straight away.
                if let uid = model.me?.id {
                    let away = Dates.iso(Date().addingTimeInterval(-UserProfile.onlineWindow - 5))
                    Task { try? await FS.update("User", uid, ["last_seen": away]) }
                }
            }
            guard scenePhase == .active else { return }
            await settle(1.2)
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
                if tick % 4 == 0, let uid = model.me?.id { Task { try? await FS.update("User", uid, ["last_seen": FS.nowISO()]) } }
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
        // Close pop-ups first, and let a tab switch finish before opening a
        // page on it: doing both in the same instant could lock up the screen.
        if model.showMenu || model.showNotifications {
            model.showMenu = false
            if kind != "alerts" && kind != "social" { model.showNotifications = false }
        }
        let switching: (AppTab) async -> Void = { next in
            guard tab != next else { return }
            tab = next
            try? await Task.sleep(for: .milliseconds(350))
        }
        switch kind {
        case "dm", "chat":
            await switching(.chat)
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
            await switching(.chat)
            UserDefaults.standard.set(1, forKey: "sugerly.chat.section")
            if !target.isEmpty, let doc = try? await FS.get("Community", target) { chatPath = [.server(Server(doc))] }
        case "reels", "reel":
            await switching(.reels)
            if target.isEmpty { reelsPath = [] }
            else if let doc = try? await FS.get("Reel", target) { reelsPath = [.reel(Reel(doc))] }
            else { model.showToast("This reel is no longer available.", error: true) }
        case "gallery", "artwork":
            await switching(.gallery)
            if target.isEmpty { galleryPath = [] }
            else if let doc = try? await FS.get("Artwork", target) { galleryPath = [.artwork(Artwork(doc))] }
            else { model.showToast("This artwork is no longer available.", error: true) }
        case "community", "post":
            await switching(.community)
            if target.isEmpty { communityPath = [] }
            else if let doc = try? await FS.get("CommunityPost", target) { communityPath = [.post(Post(doc))] }
            else { model.showToast("This post is no longer available.", error: true) }
        case "home": tab = .home; homePath = []
        case "alerts", "social":
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.showNotifications = true }
        case "support":
            await switching(.home)
            let ticket = URLComponents(string: target)?.queryItems?.first { $0.name == "ticket" }?.value ?? ""
            homePath = [ticket.isEmpty ? .support : .supportTicket(ticket)]
        default: break
        }
    }
}

// MARK: - The floating tab bar

// One soft floating bar: three tabs, the pink + in the middle, three tabs.
// The tab you're on gets a little pink pill behind its icon that glides
// over when you switch (the pages themselves switch instantly). Every tab
// keeps its name under the icon, so it never jumps around.
struct SugarTabBar: View {
    @Binding var tab: AppTab
    var unread: Int
    var dark: Bool
    var onCreate: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var lensSpace
    // Where the pill is (moves with a spring, apart from the page switch).
    @State private var lens: AppTab = .home

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "Home", "house", "house.fill")
            item(.community, "Community", "person.2", "person.2.fill")
            item(.gallery, "Fan Art", "paintpalette", "paintpalette.fill")
            createButton
            item(.reels, "Reels", "play.rectangle", "play.rectangle.fill")
            item(.chat, "Chat", "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill", badge: unread)
            meItem
        }
        .padding(.horizontal, 6)
        .frame(height: 66)
        .background {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            shape.fill(dark ? Color(hex: 0x241C21).opacity(0.97) : Palette.surface)
                .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.1) : Theme.main.opacity(0.14), lineWidth: 1))
                .shadow(color: dark ? .black.opacity(0.35) : Theme.main.opacity(0.13), radius: 16, y: 6)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .onAppear { lens = tab }
        .onChange(of: tab) { _, next in
            guard lens != next else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)) { lens = next }
        }
        .accessibilityIdentifier("main-dock")
    }

    private var tint: Color { dark ? .white : Theme.main }
    private var idle: Color { dark ? Color.white.opacity(0.62) : Palette.muted }

    private var createButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background {
                    Circle().fill(Theme.gradient)
                        .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .center)).padding(2))
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                }
                .shadow(color: Theme.main.opacity(0.4), radius: 10, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .frame(width: 60)
        .accessibilityLabel("Create")
    }

    private func lensPill(_ active: Bool) -> some View {
        ZStack {
            if active {
                Capsule()
                    .fill(dark ? Color.white.opacity(0.16) : Theme.main.opacity(0.13))
                    .matchedGeometryEffect(id: "lens", in: lensSpace)
            }
        }
        .frame(width: 50, height: 32)
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String, _ filled: String, badge: Int = 0) -> some View {
        let active = tab == t
        return Button { select(t) } label: {
            VStack(spacing: 4) {
                Image(systemName: active ? filled : icon)
                    .font(.system(size: 19, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? tint : idle)
                    .frame(width: 50, height: 32)
                    .background { lensPill(lens == t) }
                    .overlay(alignment: .topTrailing) { badgeView(badge) }
                    .symbolEffect(.bounce.down, options: .nonRepeating, value: active)
                    .symbolEffectsRemoved(reduceMotion)
                label(title, active: active)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel(title)
        .accessibilityValue(badge > 0 ? "\(badge) unread" : "")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // Your own picture as the profile tab.
    private var meItem: some View {
        let active = tab == .me
        return Button { select(.me) } label: {
            VStack(spacing: 4) {
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 24)
                    .padding(2)
                    .overlay(Circle().strokeBorder(active ? tint : idle.opacity(0.5), lineWidth: active ? 2 : 1))
                    .frame(width: 50, height: 32)
                    .background { lensPill(lens == .me) }
                label("Me", active: active)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel("Your profile")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private func label(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.jakarta(10, active ? .bold : .semibold, relativeTo: .caption2))
            .foregroundStyle(active ? tint : idle)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func badgeView(_ badge: Int) -> some View {
        if badge > 0 {
            Text(badge > 9 ? "9+" : "\(badge)")
                .font(.jakarta(10, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Palette.danger, in: Capsule())
                .overlay(Capsule().strokeBorder(dark ? Color(hex: 0x241C21) : Palette.surface, lineWidth: 2))
                .offset(x: 2, y: -3)
                .transition(.scale.combined(with: .opacity))
                .contentTransition(.numericText())
                .animation(.snappy, value: badge)
        }
    }

    private func select(_ t: AppTab) {
        guard tab != t else { return }
        // The page switches straight away; only the pill glides.
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
        // Frosted: the page shows softly through it as it scrolls under.
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Palette.bg.opacity(0.72))
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

// How tall the floating bottom bar is right now (tab bar, music, call).
struct TabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    // Keeps the bottom of a main page clear of the floating bar.
    func tabRoom(_ height: CGFloat) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: height).allowsHitTesting(false)
        }
    }

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
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create something").font(.display(30)).foregroundStyle(Palette.text)
                    Text("What would you like to share today?").font(.jakarta(14, .medium)).foregroundStyle(Palette.muted)
                }
                .padding(.top, 22)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile(0, .reel, "Reel", "Film or pick a video", "video.fill", [Color(hex: 0xFF7AA2), Color(hex: 0xD9577F)])
                    tile(1, .artwork, "Fan art", "Hang a drawing on the wall", "paintpalette.fill", [Color(hex: 0xFFAA80), Color(hex: 0xEE6E40)])
                    tile(2, .post, "Post", "Share with the community", "text.bubble.fill", [Color(hex: 0xB19CFF), Color(hex: 0x7C5CF0)])
                    tile(3, .track, "Track", "Share your music", "music.note", [Color(hex: 0x7CBEFF), Color(hex: 0x2F80E0)])
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sugarBackground()
        .presentationDragIndicator(.visible)
        .onAppear { shown = true }
    }

    // The four tiles pop in one after another.
    private func tile(_ index: Int, _ kind: Composer, _ title: String, _ sub: String, _ icon: String, _ colors: [Color]) -> some View {
        let visible = shown || reduceMotion
        return Button { onPick(kind) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)).padding(1.5))
                    .shadow(color: colors[1].opacity(0.4), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                    Text(sub).font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sugarCard(radius: 24, padding: 16)
        }
        .buttonStyle(BouncyStyle(scale: 0.95))
        .scaleEffect(visible ? 1 : 0.88)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72).delay(0.04 + Double(index) * 0.05), value: shown)
        .accessibilityLabel(title)
        .accessibilityHint(sub)
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
        let known = Set(items.map(\.id))
        let fresh = docs.map(AppNotification.init).filter { !known.contains($0.id) }
        loaded = true
        guard !fresh.isEmpty else { return }
        items = (items + fresh).sorted { $0.created > $1.created }
        newest = items.first?.created ?? newest
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
