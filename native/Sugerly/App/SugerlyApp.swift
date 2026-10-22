import SwiftUI
import UIKit

@main
struct SugerlyApp: App {
    @State private var model = AppModel()

    init() {
        _ = RenderingBudget.shared
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
        // The bunny's drawings, ready before Home or the menu shows her.
        BunnyImages.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            // iPhone's own text styles grow only so far (like Sugerly's own
            // text), so the biggest text sizes can't push things off screen.
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--editor-loop-ui-test") {
                    EditorLoopUITestHost().environment(model).sugarProgress()
                } else if ProcessInfo.processInfo.arguments.contains("--reel-playback-ui-test") {
                    ReelPlaybackUITestHost().environment(model).sugarProgress()
                } else if ProcessInfo.processInfo.arguments.contains("--appearance-ui-test") {
                    AppearanceUITestHost().environment(model).sugarProgress()
                } else if ProcessInfo.processInfo.arguments.contains("--polish-ui-test") {
                    PolishUITestHost().environment(model).sugarProgress()
                } else if ProcessInfo.processInfo.arguments.contains("--shell-ui-test") {
                    ShellUITestHost().environment(model).sugarProgress()
                } else {
                    RootView().environment(model).sugarProgress()
                }
                #else
                RootView()
                    .environment(model)
                    .sugarProgress()
                #endif
            }
            .modifier(CaptureBudgetObserver())
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
        guard animated && !VoiceEngine.live && !RenderingBudget.shared.limited else {
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
            ThemeFade.apply(new, animated: old != new && !VoiceEngine.live && !RenderingBudget.shared.limited)
        }
        .animation(.smooth(duration: 0.35), value: model.phase)
        .animation(.smooth(duration: 0.5), value: model.needsSetup)
        .task {
            // Uploads that break the picture rules add strike points to you.
            MediaGuard.app = model
            await model.start()
        }
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
    var body: some View { SugerlyLaunchScreen(message: "Welcome back", detail: "Your friends, creations and little moments") }
}

struct SplashView: View {
    var body: some View { SugerlyLaunchScreen(message: "Welcome back", detail: "Welcome to Sugerly") }
}

private struct SugerlyLaunchScreen: View {
    let message: String
    let detail: String
    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            VStack {
                Circle().fill(Theme.soft).frame(width: 230, height: 230).offset(x: -140, y: -90)
                Spacer()
                Circle().fill(Theme.main.opacity(0.07)).frame(width: 280, height: 280).offset(x: 140, y: 100)
            }.ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 22) {
                AppBadge(size: 108)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 44).fill(Theme.soft))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "sparkle").font(.system(size: 25, weight: .bold)).foregroundStyle(Theme.main).offset(x: 4, y: -4)
                    }
                BrandLogo(height: 56)
                VStack(spacing: 8) {
                    Text(message).font(.display(23)).foregroundStyle(Palette.text)
                    Text(detail).font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                }.multilineTextAlignment(.center)
                ProgressView().progressViewStyle(.circular).tint(Theme.main)
                    .frame(width: 46, height: 46).background(Theme.soft, in: Circle())
            }.padding(28)
            VStack { Spacer(); Text("Made for your little world").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted).padding(.bottom, 24) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
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
