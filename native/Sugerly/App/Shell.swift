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
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                        .onTapGesture { withAnimation { model.toast = nil } }
                        .zIndex(10)
                }
            }
            .overlay(alignment: .top) {
                if let incoming = calls.incoming {
                    IncomingCallBanner(call: incoming)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(30)
                }
            }
            .sheet(isPresented: accountShown, onDismiss: openPending) {
                AccountView { route in
                    pendingRoute = route
                    model.showMenu = false
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
            let target = parts?.queryItems?.first(where: { ["id", "art", "post", "reel", "conversation"].contains($0.name) })?.value
                ?? url.pathComponents.dropFirst().first ?? ""
            Task { await open(url.host()?.lowercased() ?? "", target) }
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
        .scaleEffect(visible ? 1 : 0.88)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72).delay(0.04 + Double(index) * 0.05), value: shown)
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
