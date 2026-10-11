import SwiftUI
import UIKit

@main
struct SugerlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        // Keep pictures around so feeds scroll without reloading them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
        // Page titles in the iPhone's fully round letters.
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: UIFont.rounded(19)]
        nav.largeTitleTextAttributes = [.font: UIFont.rounded(32)]
        // The tab bar's labels in Sugerly's font, and its look before iOS 26.
        if let small = UIFont(name: "PlusJakartaSans-SemiBold", size: 10) {
            let item = UITabBarItem.appearance()
            item.setTitleTextAttributes([.font: small], for: .normal)
            item.setTitleTextAttributes([.font: small], for: .selected)
        }
        TabBarLook.apply()
        // Notifications + background checks have to be set up at launch.
        Alerts.shared.registerBackground()
        // Calls ring this phone even when Sugerly is closed (iPhone's own
        // call screen); a call push can launch the app, so this starts here.
        IncomingCalls.shared.start()
        // Reels start at normal speed each time the app opens (a speed picked
        // last time shouldn't leave every video slow or fast).
        UserDefaults.standard.set(1.0, forKey: "sugerly.reels.speed")
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--polish-ui-test") {
                PolishUITestHost().environment(model)
            } else if ProcessInfo.processInfo.arguments.contains("--shell-ui-test") {
                ShellUITestHost().environment(model)
            } else {
                RootView().environment(model)
            }
            #else
            RootView()
                .environment(model)
            #endif
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    private var site = SiteTheme.shared
    private var connection = Connection.shared

    @State private var colorFlash = false
    // Tapping the no-internet card hides it until the next time it drops.
    @State private var offlineHidden = false

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
        AppIconSync.match(model.accent, custom: custom?.main)
        // During a call the colours switch at once: fading every view on the
        // screen to the new colour kept the phone busy and froze the call's
        // picture and buttons for a moment.
        guard animated && !VoiceEngine.live else {
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
                if model.needsSetup {
                    // New account: the welcome setup first.
                    WelcomeSetupView().transition(.opacity)
                } else {
                    // A fresh shell per account: no pages, chats or players carry over.
                    // Just a fade: zooming the whole app while it builds its
                    // first screen made logging in stutter.
                    MainShell().id(model.me?.id ?? "").transition(.opacity)
                }
            case .banned(let message):
                BannedView(message: message).transition(.opacity)
            case .offline(let message):
                VStack(spacing: 16) {
                    Image("MimiOffline")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 220)
                        .accessibilityHidden(true)
                    Text("You're offline").font(.display(30))
                    Text(message).font(.jakarta(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Sugerly will open by itself once you're back online.")
                        .font(.jakarta(13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
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
            if connection.offline && !offlineHidden && model.phase == .signedIn {
                VStack {
                    OfflineNotice()
                        .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { offlineHidden = true } }
                        .padding(.top, 6)
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(10)
            }
            if model.settingUp {
                SettingUpCover().transition(.opacity).zIndex(20)
            }
            if model.goodbye {
                GoodbyeCover().transition(.opacity).zIndex(21)
            }
        }
        .onChange(of: connection.offline) { _, offline in
            if !offline {
                offlineHidden = false
                // Opened with no internet: get going as soon as it's back.
                if case .offline(_) = model.phase { Task { await model.start() } }
            }
        }
        .onChange(of: themeKey, initial: true) { old, _ in applyTheme(animated: old != themeKey && model.phase == .signedIn) }
        .tint(Theme.main)
        // Light / dark: the whole screen (open pages and sheets too) fades
        // over to the new colours instead of snapping.
        .onChange(of: model.colorScheme, initial: true) { old, new in
            ThemeFade.apply(new, animated: old != new && !VoiceEngine.live)
        }
        .animation(.smooth(duration: 0.35), value: model.phase)
        .animation(.smooth(duration: 0.5), value: model.needsSetup)
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

// Fades in over the app while logging out, then fades away onto the login
// page, so leaving is one calm cross-fade.
struct GoodbyeCover: View {
    var body: some View {
        VStack(spacing: 14) {
            MimiBuddy(icon: "hand.wave.fill", mood: .happy, size: 130, animated: false)
            Text("See you soon!").font(.display(30)).foregroundStyle(Palette.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sugarBackground()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// Shown while logging in: the app gets ready behind it.
struct SettingUpCover: View {
    @State private var dot = 0

    var body: some View {
        VStack(spacing: 14) {
            MimiBuddy(icon: "sparkles", mood: .happy, size: 130, animated: false)
            Text("Setting things up for you").font(.display(28)).foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.main)
                        .frame(width: 9, height: 9)
                        .opacity(dot == i ? 1 : 0.3)
                        .scaleEffect(dot == i ? 1.15 : 0.9)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: dot)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sugarBackground()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setting things up for you")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(380))
                dot = (dot + 1) % 3
            }
        }
    }
}

// The icon stays still (Mimi never moves); only its sparkles twinkle.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            AppBadge(size: 132)
            BrandLogo(height: 58)
            SugarLoader(size: 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sugarBackground()
    }
}

// Switches light / dark on the app's windows with a soft cross-fade.
enum ThemeFade {
    @MainActor
    static func apply(_ scheme: ColorScheme?, animated: Bool) {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : scheme == .light ? .light : .unspecified
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] where window.overrideUserInterfaceStyle != style {
                guard animated else { window.overrideUserInterfaceStyle = style; continue }
                UIView.transition(with: window, duration: 0.5, options: [.transitionCrossDissolve, .allowUserInteraction, .curveEaseInOut]) {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}
