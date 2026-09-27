import SwiftUI

@main
struct SugerlyApp: App {
    @State private var model = AppModel()

    init() {
        // Keep pictures around so feeds scroll without reloading them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.pink)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .loading:
                SplashView().transition(.opacity)
            case .signedOut:
                LoginView().transition(.opacity)
            case .signedIn:
                MainTabView().transition(.opacity)
            case .offline(let message):
                ContentUnavailableView {
                    Label("You're offline", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await model.start() } }.buttonStyle(.borderedProminent)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.phase)
        .task { await model.start() }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("Logo").resizable().scaledToFit().frame(width: 220, height: 90)
                Text("Your little corner of the internet.").font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.pink)
                ProgressView().tint(Theme.pink)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var chats = ChatStore()
    @State private var music = NativeMusicPlayer()

    var body: some View {
        TabView(selection: $tab) {
            CommunityView()
                .tabItem { Label("Community", systemImage: "person.2.fill") }
                .tag(0)
            ChatListView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(chats.unread)
                .tag(1)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(2)
            NativeReelsView(isSelected: tab == 3).tabItem { Label("Reels", systemImage: "play.rectangle.fill") }.tag(3)
            NativeMusicView().tabItem { Label("Music", systemImage: "music.note") }.tag(4)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if music.track != nil && tab != 3 { NativeMiniPlayer() }
                HStack(spacing: 2) {
                    tabButton(0, "Community", "person.2.fill")
                    tabButton(3, "Reels", "play.rectangle.fill")
                    tabButton(4, "Music", "music.note")
                    tabButton(1, "Chat", "bubble.left.and.bubble.right.fill")
                    tabButton(2, "Profile", "person.crop.circle.fill")
                }.padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.border, lineWidth: 1))
                    .shadow(color: Theme.pink.opacity(0.12), radius: 12, y: 4)
            }.frame(maxWidth: 560).padding(.horizontal, 12).padding(.bottom, 4)
        }
        .environment(music)
        .onChange(of: tab) { _, next in if next == 3 { music.pause() } }
        .sensoryFeedback(.selection, trigger: tab)
        .environment(chats)
        // New messages: every 6 s while you're in Chat, every 20 s elsewhere,
        // not at all while the app is in the background.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await chats.refresh(me: model.me?.email ?? "")
                let base: Double = tab == 1 ? 6 : 20
                let slow = FS.missingIndex.contains("DirectMessage") ? 2.0 : 1.0
                try? await Task.sleep(for: .seconds(base * slow))
            }
        }
    }
    private func tabButton(_ value: Int, _ label: String, _ symbol: String) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .bold, design: .rounded))
            }.frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(tab == value ? Theme.pink : Color.secondary)
                .background(tab == value ? Theme.pink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(tab == value ? [.isSelected] : [])
    }
}
