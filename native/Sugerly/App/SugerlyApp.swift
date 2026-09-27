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
                .font(.custom("PlusJakartaSans-Regular", size: 15, relativeTo: .body))
                .preferredColorScheme(Appearance.shared.scheme)
                .buttonStyle(CandyButtonStyle())
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
    @State private var visited: Set<Int> = [0]
    @State private var keyboard = false
    @State private var editing = false
    @State private var chats = ChatStore()
    @State private var music = NativeMusicPlayer()

    var body: some View {
        ZStack {
            CommunityView().opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
            if visited.contains(1) { ChatListView().opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1) }
            if visited.contains(2) { ProfileView().opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).accessibilityHidden(tab != 2) }
            if visited.contains(3) { NativeReelsView(isSelected: tab == 3).opacity(tab == 3 ? 1 : 0).allowsHitTesting(tab == 3).accessibilityHidden(tab != 3) }
            if visited.contains(4) { NativeMusicView().opacity(tab == 4 ? 1 : 0).allowsHitTesting(tab == 4).accessibilityHidden(tab != 4) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboard && !editing { VStack(spacing: 8) {
                if music.track != nil && tab != 3 { NativeMiniPlayer() }
                HStack(spacing: 2) {
                    tabButton(0, "Community", "person.2.fill")
                    tabButton(3, "Reels", "play.rectangle.fill")
                    tabButton(4, "Music", "music.note")
                    tabButton(1, "Chat", "bubble.left.and.bubble.right.fill")
                    tabButton(2, "Profile", "person.crop.circle.fill")
                }.padding(6).background(Theme.card, in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.border, lineWidth: 1))
                    .shadow(color: Theme.pink.opacity(0.12), radius: 12, y: 4)
            }.frame(maxWidth: 560).padding(.horizontal, 12).padding(.bottom, 4) }
        }
        .environment(music)
        .onChange(of: tab) { _, next in visited.insert(next); if next == 3 { music.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in editing = true }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in editing = false }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in editing = true }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in editing = false }
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
        }.buttonStyle(CandyButtonStyle()).accessibilityLabel(label).accessibilityAddTraits(tab == value ? [.isSelected] : [])
    }
}
