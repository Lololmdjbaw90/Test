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
    case notifications
    case admin
}

enum AppTab: Hashable { case home, community, reels, chat }

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
        case .notifications: NotificationsView(path: $path)
        case .admin: AdminView()
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
                Circle().fill(Theme.light.opacity(0.28)).frame(width: 340).blur(radius: 90).offset(x: 150, y: -300)
                Circle().fill(Theme.lavender.opacity(0.16)).frame(width: 300).blur(radius: 90).offset(x: -170, y: 260)
            }
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
    @State private var homePath: [Route] = []
    @State private var communityPath: [Route] = []
    @State private var reelsPath: [Route] = []
    @State private var chatPath: [Route] = []
    @State private var creating = false
    @State private var pendingComposer: Composer?
    @State private var composer: Composer?
    @State private var typing = false
    @State private var dailyShown = false

    private var currentPath: [Route] {
        switch tab {
        case .home: return homePath
        case .community: return communityPath
        case .reels: return reelsPath
        case .chat: return chatPath
        }
    }
    private var barHidden: Bool { typing || !currentPath.isEmpty }

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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !barHidden {
                VStack(spacing: 8) {
                    if tab != .reels { MiniPlayer() }
                    SugarTabBar(tab: $tab, unread: chats.unread, dark: tab == .reels) { creating = true }
                }
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: barHidden)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.track?.id)
        .environment(chats)
        .environment(posts)
        .environment(player)
        .environment(notes)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
        .sheet(isPresented: $creating, onDismiss: {
            if let pendingComposer { composer = pendingComposer; self.pendingComposer = nil }
        }) {
            CreateSheet { choice in pendingComposer = choice; creating = false }
                .presentationDetents([.height(430)])
                .presentationCornerRadius(34)
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            var tick = 0
            while !Task.isCancelled {
                let me = model.me?.email ?? ""
                await chats.refresh(me: me)
                if tick % 6 == 0 { await notes.refresh(me: me) }
                tick += 1
                let base: Double = tab == .chat ? 6 : 15
                try? await Task.sleep(for: .seconds(base * (FS.missingIndex.contains("DirectMessage") ? 2 : 1)))
            }
        }
    }
}

// MARK: - Floating tab bar (the one Liquid Glass piece)

struct SugarTabBar: View {
    @Binding var tab: AppTab
    var unread: Int
    var dark: Bool
    var onCreate: () -> Void
    @Namespace private var lens
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "Home", "house", "house.fill")
            item(.community, "Community", "person.2", "person.2.fill")
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.gradient, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: Theme.pink.opacity(0.55), radius: 14, y: 6)
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .padding(.horizontal, 6)
            .accessibilityLabel("Create")
            item(.reels, "Reels", "play.rectangle", "play.rectangle.fill")
            item(.chat, "Chat", "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill", badge: unread)
        }
        .padding(.horizontal, 6)
        .frame(height: 68)
        .glassPill(cornerRadius: 34)
        .environment(\.colorScheme, dark ? .dark : scheme)
        .padding(.horizontal, 14)
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String, _ filled: String, badge: Int = 0) -> some View {
        let active = tab == t
        return Button {
            if tab != t { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { tab = t } }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? filled : icon)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: active)
                Text(title).font(.jakarta(10, .bold))
            }
            .foregroundStyle(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(dark ? Color.white.opacity(0.7) : Palette.muted))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                if active {
                    Capsule().fill(dark ? Color.white.opacity(0.14) : Theme.pink.opacity(0.13))
                        .matchedGeometryEffect(id: "lens", in: lens)
                }
            }
            .overlay(alignment: .top) {
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .font(.jakarta(10, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.gradient, in: Capsule())
                        .offset(x: 14, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(BouncyStyle())
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel(title)
    }
}

// MARK: - Top bar (logo, notifications, you)

struct TopBar: View {
    @Binding var path: [Route]
    var title: String? = nil
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @State private var more = false

    var body: some View {
        HStack(spacing: 10) {
            BrandLogo(height: 34)
            Spacer()
            Button { path.append(.notifications) } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 42, height: 42)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
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
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 42)
                    .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 2))
                    .shadow(color: Theme.pink.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Palette.bg.opacity(0.94)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
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
    @State private var legal: LegalDoc?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let me = model.me {
                    Button { go(.person(me.email)) } label: {
                        HStack(spacing: 14) {
                            Avatar(url: me.picture, name: me.displayName, size: 60)
                                .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 2.5))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(me.displayName).font(.display(24)).foregroundStyle(Palette.text)
                                let info = LevelInfo(xp: me.xp)
                                Text("Lv. \(info.level) · \(info.title) · \(me.coins) coins").font(.jakarta(13, .semibold)).foregroundStyle(info.color)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                        }
                        .sugarCard(radius: 26, padding: 16)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.97))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile("Music", "music.note", [0xFF7AA2, 0xD9577F]) { go(.music) }
                    tile("Gallery", "photo.stack.fill", [0xFFAA80, 0xEE6E40]) { go(.gallery) }
                    tile("Alerts", "bell.fill", [0xB19CFF, 0x7C5CF0]) { go(.notifications) }
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
        .sugarBackground()
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(item: $legal) { doc in LegalView(doc: doc) }
    }

    private func go(_ route: Route) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            path.append(route)
        }
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
