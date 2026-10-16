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
    case notifications
}

enum AppTab: Hashable {
    case home, community, gallery, reels, chat
}

enum Composer: String, Identifiable { case post, artwork, reel, track; var id: String { rawValue } }

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

// Where a tap leads, shared by every tab. Every page has exactly one back
// button: iPhone's own, in iPhone's own top bar (pages never add one).
struct RouteView: View {
    let route: Route
    @Binding var path: [Route]
    var loadContent = true

    var body: some View {
        page
            .navigationBarBackButtonHidden(fullScreen)
            .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
            .toolbar(focused ? .hidden : .automatic, for: .tabBar)
            .bottomDock(!focused)
    }

    // Reels and Music fill the screen and bring their own back button.
    private var fullScreen: Bool {
        switch route {
        case .reel, .music: return true
        default: return false
        }
    }

    // Chats, comments and full screen pages get the whole screen: the tab
    // bar slides away so the typing bar sits at the bottom.
    private var focused: Bool {
        switch route {
        case .chat, .channel, .voice, .post, .artwork, .reel, .music, .support, .supportTicket: return true
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
        case .servers: ServersHome(path: $path)
        case .people: PeopleView(path: $path)
        case .commissions: CommissionsView(path: $path)
        case .commissionOrder(let id): CommissionOrderView(orderId: id, path: $path)
        case .topArtists: TopArtistsView(path: $path)
        case .updates: UpdatesView()
        case .server(let server): ServerPage(server: server, path: $path)
        case .channel(let server, let channel): ChannelChatView(server: server, channel: channel)
        case .voice(let server, let channel): VoiceRoomView(server: server, channel: channel)
        case .support: SupportView()
        case .supportTicket(let email): SupportTicketView(email: email)
        case .notifications: NotificationsPage(path: $path)
        }
    }
}

extension View {
    func sugarRoutes(_ path: Binding<[Route]>) -> some View {
        modifier(SugarRoutes(path: path))
    }
}

// Each tab's pages share one namespace, so a drawing, post or reel can
// grow out of the card you tapped and shrink back into it (iOS 18+).
private struct SugarRoutes: ViewModifier {
    let path: Binding<[Route]>
    @Namespace private var zoom

    func body(content: Content) -> some View {
        content
            .environment(\.zoomSpace, zoom)
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route, path: path)
                    .zoomDestination(route.zoomID)
                    .environment(\.zoomSpace, zoom)
            }
    }
}

extension Route {
    // Pages that grow out of the card you tapped.
    var zoomID: String? {
        switch self {
        case .artwork(let a): return "art-" + a.id
        case .post(let p): return "post-" + p.id
        case .reel(let r): return "reel-" + r.id
        default: return nil
        }
    }
}

private struct ZoomSpaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomSpace: Namespace.ID? {
        get { self[ZoomSpaceKey.self] }
        set { self[ZoomSpaceKey.self] = newValue }
    }
}

extension View {
    /// The card a page grows out of when you open it.
    func zoomSource(_ id: String) -> some View { modifier(ZoomSource(id: id)) }
    fileprivate func zoomDestination(_ id: String?) -> some View { modifier(ZoomDestination(id: id)) }
}

private struct ZoomSource: ViewModifier {
    let id: String
    @Environment(\.zoomSpace) private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let space, !reduceMotion {
            content.matchedTransitionSource(id: id, in: space)
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let id: String?
    @Environment(\.zoomSpace) private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let id, let space, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: space))
        } else {
            content
        }
    }
}

// Icon buttons: a squish the moment your finger lands (with a soft click),
// a springy return with a tiny overshoot when you let go, and the icon
// inside gives a little hop.
struct BouncyStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    var sound = true
    func makeBody(configuration: Configuration) -> some View {
        JellyPress(content: configuration.label, pressed: configuration.isPressed, scale: scale, sound: sound)
    }
}

// Links and text buttons: the same, gentler and quiet (they're everywhere),
// with no hop.
struct SoftPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        JellyPress(content: configuration.label, pressed: configuration.isPressed, scale: scale, sound: false, fade: true, hop: false)
    }
}

// List rows inside a card: a soft pink highlight, a tiny squish, and the
// row's icon hops when you let go.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        JellyPress(content: configuration.label.contentShape(Rectangle()).background(configuration.isPressed ? Palette.surface2 : Color.clear),
                   pressed: configuration.isPressed, scale: 0.985, sound: false)
    }
}

// The press itself. Down answers straight away (fast ease-out, plus the
// click on the same frame). Up is a spring, so a quick second tap carries
// on from wherever the button is instead of restarting. With Reduce Motion
// it only dims a touch.
struct JellyPress<Content: View>: View {
    let content: Content
    let pressed: Bool
    var scale: CGFloat = 0.94
    var sound = true
    var fade = false
    var hop = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Down: a quick squish. Up: a soft spring back with a tiny overshoot
    // (the "hop"), so buttons feel alive without anything flashing.
    var body: some View {
        content
            .scaleEffect(pressed && !reduceMotion ? max(scale, 0.92) : 1)
            .opacity(pressed ? (fade ? 0.6 : 0.88) : 1)
            .animation(pressed ? Motion.press : (hop && !reduceMotion ? Motion.release : Motion.standard), value: pressed)
    }
}

extension View {
    // A soft pop when a button goes down.
    func clickSound(_ pressed: Bool, _ kind: TapSound.Kind = .tap) -> some View {
        onChange(of: pressed) { _, down in if down { TapSound.play(kind) } }
    }
}

// Soft sounds: the menu and the + sheet whoosh open and closed, and a
// little bell rings when a message or notification comes in (not for what's
// already waiting when the app opens).
private struct ShellSounds: ViewModifier {
    let chats: ChatStore
    let notes: NotificationsStore
    @Environment(AppModel.self) private var model
    @State private var ready = false

    func body(content: Content) -> some View {
        content
            .onChange(of: model.showMenu) { _, open in TapSound.play(open ? .open : .close) }
            .onChange(of: model.showCreate) { _, open in TapSound.play(open ? .open : .close) }
            .onChange(of: chats.unread) { old, new in if ready && new > old { TapSound.play(.receive) } }
            .onChange(of: notes.unread) { old, new in if ready && new > old { TapSound.play(.receive) } }
            .task {
                try? await Task.sleep(for: .seconds(8))
                ready = true
            }
    }
}

// Which tab is open and the pages open on each tab. Each tab's pages only
// redraw that tab: opening your account, the + or a sheet doesn't redraw
// all five tabs (that made opening them stutter).
@MainActor
@Observable
final class Navigator {
    var tab: AppTab = .home
    var home: [Route] = []
    var community: [Route] = []
    var gallery: [Route] = []
    var reels: [Route] = []
    var chat: [Route] = []
    // The page that makes a post / drawing / reel / track.
    var composer: Composer?

    subscript(_ t: AppTab) -> [Route] {
        get {
            switch t {
            case .home: return home
            case .community: return community
            case .gallery: return gallery
            case .reels: return reels
            case .chat: return chat
            }
        }
        set {
            switch t {
            case .home: home = newValue
            case .community: community = newValue
            case .gallery: gallery = newValue
            case .reels: reels = newValue
            case .chat: chat = newValue
            }
        }
    }

    // A tab's pages. A quick double tap opens a page once, not twice (which
    // used to need two taps on Back to get out again).
    func path(_ t: AppTab) -> Binding<[Route]> {
        Binding(get: { self[t] }, set: { next in
            var clean: [Route] = []
            for route in next where clean.last != route { clean.append(route) }
            self[t] = clean
        })
    }

    // Opens a page on the tab you're on.
    func push(_ route: Route) {
        guard self[tab].last != route else { return }
        self[tab].append(route)
    }
}

// The five tabs, each its own view with its own pages.
private struct ShellTabs: View {
    let nav: Navigator
    @Environment(ChatStore.self) private var chats
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Tapping the tab you're already on takes it back to its first page.
    private var selection: Binding<AppTab> {
        Binding(get: { nav.tab }, set: { next in
            if next == nav.tab { nav[next] = [] }
            TapSound.play(.select)
            nav.tab = next
        })
    }

    var body: some View {
        TabView(selection: selection) {
            HomeTab(nav: nav)
                .environment(\.horizontalSizeClass, sizeClass)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            CommunityTab(nav: nav)
                .environment(\.horizontalSizeClass, sizeClass)
                .tabItem { Label("Community", systemImage: "person.2") }
                .tag(AppTab.community)
            GalleryTab(nav: nav)
                .environment(\.horizontalSizeClass, sizeClass)
                .tabItem { Label("Fan Art", systemImage: "paintpalette") }
                .tag(AppTab.gallery)
            ReelsTab(nav: nav)
                .environment(\.horizontalSizeClass, sizeClass)
                .tabItem { Label("Reels", systemImage: "play.rectangle") }
                .tag(AppTab.reels)
            ChatTab(nav: nav)
                .environment(\.horizontalSizeClass, sizeClass)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .badge(chats.unread)
                .tag(AppTab.chat)
        }
        .compactTabBar()
        .tint(Theme.main)
        // iPad: the tab bar sits at the bottom like on iPhone. (iPadOS puts
        // the tabs at the top, squeezed in with each page's title and
        // buttons, which looked crowded.) The pages inside keep their iPad
        // layout.
        .environment(\.horizontalSizeClass, .compact)
    }
}

private struct HomeTab: View {
    let nav: Navigator
    var body: some View {
        let path = nav.path(.home)
        NavigationStack(path: path) {
            HomeView(path: path, compose: { nav.composer = $0 })
                .sugarRoutes(path)
        }
    }
}

private struct CommunityTab: View {
    let nav: Navigator
    var body: some View {
        let path = nav.path(.community)
        NavigationStack(path: path) {
            CommunityView(path: path, compose: { nav.composer = .post })
                .sugarRoutes(path)
        }
    }
}

private struct GalleryTab: View {
    let nav: Navigator
    var body: some View {
        let path = nav.path(.gallery)
        NavigationStack(path: path) {
            GalleryView(path: path, isRoot: true)
                .sugarRoutes(path)
        }
    }
}

private struct ReelsTab: View {
    let nav: Navigator
    @Environment(CallCenter.self) private var calls
    var body: some View {
        let path = nav.path(.reels)
        NavigationStack(path: path) {
            ReelsView(visible: nav.tab == .reels && nav.reels.isEmpty && !calls.showScreen, path: path, create: { nav.composer = .reel })
                .sugarRoutes(path)
        }
    }
}

private struct ChatTab: View {
    let nav: Navigator
    var body: some View {
        let path = nav.path(.chat)
        NavigationStack(path: path) {
            ChatListView(path: path)
                .sugarRoutes(path)
        }
    }
}

// MARK: - App shell

// iPhone's own tab bar with five tabs, each with its own pages. Your
// account, the bell and the + live in the top bar of each tab's first page.
struct MainShell: View {
    @State private var quickLink: QuickLink?
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var nav = Navigator()
    @State private var chats = ChatStore()
    @State private var posts = PostsStore()
    @State private var player = Player()
    @State private var notes = NotificationsStore()
    @State private var voice = VoiceEngine.shared
    @State private var calls = CallCenter.shared
    @State private var pendingComposer: Composer?
    @State private var pendingRoute: Route?
    @State private var dailyShown = false
    @State private var openedAt = Date()

    // Right after logging in, background refreshes wait a moment so the first
    // screen can draw smoothly (coming back to the app doesn't wait).
    private func settle(_ seconds: Double) async {
        let left = seconds - Date().timeIntervalSince(openedAt)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
    }

    private var accountShown: Binding<Bool> {
        Binding(get: { model.showMenu }, set: { model.showMenu = $0 })
    }

    private var createShown: Binding<Bool> {
        Binding(get: { model.showCreate }, set: { model.showCreate = $0 })
    }

    private var callShown: Binding<Bool> {
        Binding(get: { calls.showScreen }, set: { calls.showScreen = $0 })
    }

    private var composerShown: Binding<Composer?> {
        Binding(get: { nav.composer }, set: { nav.composer = $0 })
    }

    // The tabs with everything that opens over them.
    private var framed: some View {
        ShellTabs(nav: nav)
            .overlay(alignment: .top) {
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .padding(.top, 6)
                        .transition(.slideIn(from: .top))
                        .onTapGesture { withMotion(Motion.exit) { model.toast = nil } }
                        // A flick up sends it away.
                        .gesture(DragGesture(minimumDistance: 6).onEnded { v in
                            if v.translation.height < -8 || v.predictedEndTranslation.height < -40 {
                                withMotion(Motion.exit) { model.toast = nil }
                            }
                        })
                        .zIndex(10)
                }
            }
            .overlay(alignment: .top) {
                if let incoming = calls.incoming {
                    IncomingCallBanner(call: incoming)
                        .padding(.top, 4)
                        .transition(.slideIn(from: .top))
                        .zIndex(30)
                }
            }
            .sheet(isPresented: accountShown, onDismiss: openPending) {
                AccountView { route in
                    pendingRoute = route
                    Task { @MainActor in model.showMenu = false }
                }
            }
            .sheet(isPresented: createShown, onDismiss: {
                if let pendingComposer { nav.composer = pendingComposer; self.pendingComposer = nil }
            }) {
                CreateSheet { choice in pendingComposer = choice; model.showCreate = false }
                    .presentationDetents([.height(460), .large])
                    .presentationCornerRadius(34)
            }
            .fullScreenCover(item: composerShown) { kind in
                switch kind {
                case .post: NewPostView { await posts.load() }
                case .artwork: NewArtworkView()
                case .track: NewTrackView()
                case .reel: ReelStudioView()
                }
            }
            .fullScreenCover(isPresented: callShown) {
                CallScreen().environment(calls).environment(voice).environment(model)
            }
            .sheet(isPresented: $dailyShown) {
                DailyRewardSheet().presentationDetents([.height(520)]).presentationCornerRadius(34)
            }
    }

    // A page picked in your account opens once the sheet has slid away.
    private func openPending() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        nav.push(route)
    }

    var body: some View {
        framed
        .onChange(of: model.tabRequest) { _, next in
            guard let next else { return }
            nav.tab = next
            model.tabRequest = nil
        }
        .modifier(ShellSounds(chats: chats, notes: notes))
        // The bell (and a notification tapped) opens the notifications page
        // on the tab you're on.
        .onChange(of: model.showNotifications) { _, show in
            guard show else { return }
            model.showNotifications = false
            nav.push(.notifications)
        }
        .onChange(of: Alerts.shared.destination) { _, dest in
            guard let dest else { return }
            Alerts.shared.destination = nil
            Task { await open(dest.kind, dest.target) }
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "sugerly" else { return }
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.host()?.lowercased() == "quick", let code = parts?.queryItems?.first(where: { $0.name == "c" })?.value {
                quickLink = QuickLink(code: code)
                return
            }
            let target = parts?.queryItems?.first(where: { ["id", "art", "post", "reel", "conversation"].contains($0.name) })?.value
                ?? url.pathComponents.dropFirst().first ?? ""
            Task { await open(url.host()?.lowercased() ?? "", target) }
        }
        .sheet(item: $quickLink) { link in QuickApproveSheet(initialCode: link.code) }
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
        .onChange(of: model.soundRequest?.id) { _, id in
            if id != nil { nav.composer = .reel }
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
                let base: Double = nav.tab == .chat ? 6 : 15
                try? await Task.sleep(for: .seconds(base * (FS.missingIndex.contains("DirectMessage") ? 2 : 1)))
            }
        }
        .environment(chats)
        .environment(posts)
        .environment(player)
        .environment(notes)
        .environment(voice)
        .environment(calls)
    }
}

extension MainShell {
    // Opens the place a notification or widget points at.
    func open(_ kind: String, _ target: String) async {
        // Close your account or the + sheet first, and let a tab switch
        // finish before opening a page on it: doing both in the same instant
        // could lock up the screen.
        if model.showMenu || model.showCreate {
            pendingRoute = nil
            model.showMenu = false
            model.showCreate = false
            try? await Task.sleep(for: .milliseconds(450))
        }
        let switching: (AppTab) async -> Void = { next in
            guard nav.tab != next else { return }
            nav.tab = next
            try? await Task.sleep(for: .milliseconds(350))
        }
        switch kind {
        case "dm", "chat":
            await switching(.chat)
            guard !target.isEmpty else { return }
            let me = model.me?.email ?? ""
            if chats.conversations.first(where: { $0.id == target }) == nil { await chats.refresh(me: me) }
            if let c = chats.conversations.first(where: { $0.id == target }) {
                nav.chat = [.chat(c)]
            } else if target.contains("__dm__") {
                let members = target.components(separatedBy: "__dm__")
                nav.chat = [.chat(Conversation(id: target, members: members, isGroup: false, groupName: "", last: nil, unread: 0))]
            }
        case "server":
            await switching(.chat)
            UserDefaults.standard.set(1, forKey: "sugerly.chat.section")
            if !target.isEmpty, let doc = try? await FS.get("Community", target) { nav.chat = [.server(Server(doc))] }
        case "reels", "reel":
            await switching(.reels)
            if target.isEmpty { nav.reels = [] }
            else if let doc = try? await FS.get("Reel", target) { nav.reels = [.reel(Reel(doc))] }
            else { model.showToast("This reel is no longer available.", error: true) }
        case "gallery", "artwork":
            await switching(.gallery)
            if target.isEmpty { nav.gallery = [] }
            else if let doc = try? await FS.get("Artwork", target) { nav.gallery = [.artwork(Artwork(doc))] }
            else { model.showToast("This artwork is no longer available.", error: true) }
        case "community", "post":
            await switching(.community)
            if target.isEmpty { nav.community = [] }
            else if let doc = try? await FS.get("CommunityPost", target) { nav.community = [.post(Post(doc))] }
            else { model.showToast("This post is no longer available.", error: true) }
        case "home": nav.tab = .home; nav.home = []
        case "alerts", "social":
            model.showNotifications = true
        case "support":
            await switching(.home)
            let ticket = URLComponents(string: target)?.queryItems?.first { $0.name == "ticket" }?.value ?? ""
            nav.home = [ticket.isEmpty ? .support : .supportTicket(ticket)]
        default: break
        }
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
        .scaleEffect(visible ? 1 : 0.92)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.enter.delay(0.03 + Double(index) * Motion.staggerStep), value: shown)
        .accessibilityLabel(title)
        .accessibilityHint(sub)
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

    // Opening a notification marks it (and the likes grouped with it) read.
    func markRead(_ ids: [String]) {
        let wanted = Set(ids)
        for i in items.indices where wanted.contains(items[i].id) && !items[i].read {
            items[i].read = true
            let id = items[i].id
            Task { try? await FS.update("Notification", id, ["is_read": true]) }
        }
    }

    func markAllRead() {
        let unread = items.filter { !$0.read }
        for i in items.indices { items[i].read = true }
        for n in unread { Task { try? await FS.update("Notification", n.id, ["is_read": true]) } }
    }
}
