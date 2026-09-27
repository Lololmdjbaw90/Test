import SwiftUI
import UIKit

@main
struct SugerlyApp: App {
    @State private var model = AppModel()

    init() {
        // Keep pictures around so feeds scroll without reloading them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
        let nav = UINavigationBar.appearance()
        if let title = UIFont(name: "PlusJakartaSans-Bold", size: 17) {
            nav.titleTextAttributes = [.font: title]
        }
        if let large = UIFont(name: "Bubbly-Regular", size: 34) {
            nav.largeTitleTextAttributes = [.font: large]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    private var site = SiteTheme.shared

    // The admin's site colours apply unless you picked your own accent.
    private var themeKey: String {
        let custom: (main: UInt32, light: UInt32)?
        if model.accent == .rose, let main = site.primary {
            custom = (main, site.secondary ?? main)
        } else {
            custom = nil
        }
        Theme.accent = model.accent
        Theme.custom = custom
        return "\(model.accent.rawValue)-\(custom.map { "\($0.main)-\($0.light)" } ?? "none")"
    }

    var body: some View {
        let key = themeKey
        ZStack {
            switch model.phase {
            case .loading:
                SplashView().transition(.opacity)
            case .signedOut:
                LoginView().transition(.opacity)
            case .signedIn:
                MainShell().transition(.opacity)
            case .offline(let message):
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.gradient)
                    Text("You're offline").font(.display(30))
                    Text(message).font(.jakarta(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try again") { Task { await model.start() } }
                        .buttonStyle(GradientButtonStyle())
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sugarBackground()
            }
        }
        .id(key)
        .tint(Theme.main)
        .preferredColorScheme(model.colorScheme)
        .animation(.smooth(duration: 0.35), value: model.phase)
        .task { await model.start() }
        .task { await site.load() }
    }
}

struct SplashView: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 14) {
            BrandLogo(height: 86)
                .scaleEffect(pulse ? 1.06 : 0.96)
                .shadow(color: Theme.main.opacity(0.45), radius: pulse ? 28 : 10)
            ProgressView().tint(Theme.main)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sugarBackground()
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}
