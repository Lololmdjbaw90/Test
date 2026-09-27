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
    @State private var pulse = false
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .scaleEffect(pulse ? 1.05 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var chats = ChatStore()

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
        }
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
}
