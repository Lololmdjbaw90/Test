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
        // Notifications + background checks have to be set up at launch.
        Alerts.shared.registerBackground()
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

    @State private var colorFlash = false

    // Your own colours win; then the admin's site colours, unless you
    // picked one of the preset accents.
    private var themeKey: String {
        "\(model.accent.rawValue)-\(site.primary.map(String.init) ?? "none")-\(site.secondary.map(String.init) ?? "none")-\(model.me?.accentMain ?? "")-\(model.me?.accentSub ?? "")"
    }

    private func applyTheme(animated: Bool) {
        let custom: (main: UInt32, light: UInt32)?
        if let mine = model.myColors {
            custom = mine
        } else if model.accent == .rose, let main = site.primary {
            custom = (main, site.secondary ?? main)
        } else {
            custom = nil
        }
        guard animated else {
            Theme.accent = model.accent
            Theme.custom = custom
            return
        }
        // A soft wash of the new colour sweeps over while everything fades to it.
        withAnimation(.easeInOut(duration: 0.5)) {
            Theme.accent = model.accent
            Theme.custom = custom
            colorFlash = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.25)) { colorFlash = false }
    }

    var body: some View {
        ZStack {
            switch model.phase {
            case .loading:
                SplashView().transition(.opacity)
            case .signedOut:
                LoginView().transition(.opacity)
            case .signedIn:
                // A fresh shell per account: no pages, chats or players carry over.
                MainShell().id(model.me?.id ?? "").transition(.opacity)
            case .banned(let message):
                BannedView(message: message).transition(.opacity)
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
            Theme.gradient
                .opacity(colorFlash ? 0.22 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onChange(of: themeKey, initial: true) { old, _ in applyTheme(animated: old != themeKey && model.phase == .signedIn) }
        .tint(Theme.main)
        .preferredColorScheme(model.colorScheme)
        .animation(.smooth(duration: 0.35), value: model.phase)
        .task { await model.start() }
        .task { await site.load() }
    }
}

// Shown instead of the app when an admin has banned the account.
struct BannedView: View {
    let message: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            MimiBuddy(icon: "hand.raised.fill", mood: .sad, size: 150)
            Text("Your account is banned").font(.display(30)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Text(message).font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Text("If you think this is a mistake, contact the Sugerly team.").font(.jakarta(13)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Button("Try again") { Task { await model.start() } }
                .buttonStyle(OutlineButtonStyle(height: 48, fullWidth: true))
                .padding(.horizontal, 30)
            Button("Log out") { model.signOut() }
                .buttonStyle(GradientButtonStyle(height: 50))
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sugarBackground()
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
