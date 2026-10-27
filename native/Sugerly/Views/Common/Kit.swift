import SwiftUI
import UIKit

// The frame every page sits in: iPhone's own tab bar and top bars (so the
// back button, the swipe back, the keyboard and the safe areas all behave
// exactly like other iPhone apps), in Sugerly's pink.

// MARK: - Main pages (the first page of each tab)

extension View {
    /// The first page of a tab: your picture on the left (your account), the
    /// bell and the + on the right, and the music / call bar at the bottom.
    func rootBar(create: Bool = true, search: (() -> Void)? = nil, message: (() -> Void)? = nil) -> some View {
        modifier(RootBar(create: create, search: search, message: message))
    }

    /// The music player and the call bar, just above the tab bar.
    func bottomDock(_ shown: Bool = true) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if shown { BottomDock() }
        }
    }
}

private struct RootBar: ViewModifier {
    var create: Bool
    var search: (() -> Void)?
    var message: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @State private var bellTaps = 0

    func body(content: Content) -> some View {
        content
            .plainToolbar(leading: { AccountButton() }, trailing: { trailing })
            .overlay(alignment: .topLeading) { MenuHintBubble() }
            .bottomDock()
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            if let search {
                Button {
                    TapSound.play(.tap)
                    search()
                } label: {
                    BarIcon(icon: "magnifyingglass")
                }
                .buttonStyle(BouncyStyle(scale: 0.88, sound: false))
                .accessibilityLabel("Search")
            }
            Button {
                TapSound.play(.tap)
                bellTaps += 1
                model.showNotifications = true
            } label: {
                // The bell gives a little wiggle when tapped.
                BarIcon(icon: notes.unread > 0 ? "bell.badge.fill" : "bell", alert: notes.unread > 0, bounce: bellTaps)
            }
            .buttonStyle(BouncyStyle(scale: 0.88, sound: false))
            .accessibilityLabel("Notifications")
            .accessibilityValue(notes.unread > 0 ? "\(notes.unread) new" : "")
            if let message {
                PinkCircleButton(icon: "square.and.pencil", label: "New message", action: message)
            } else if create {
                PinkCircleButton(icon: "plus", label: "Create") { model.showCreate = true }
            }
        }
    }
}

extension View {
    /// Top bar buttons in Sugerly's own solid look. On iOS 26 the bar's glass
    /// bubbles around them are switched off: less glass, no wobbly glass
    /// animation when you tap, and a lighter, smoother bar.
    func plainToolbar<Leading: View, Trailing: View>(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(PlainToolbar(leading: leading(), trailing: trailing()))
    }
}

private struct PlainToolbar<Leading: View, Trailing: View>: ViewModifier {
    let leading: Leading
    let trailing: Trailing
    // The app's real light / dark look, read from the page.
    @Environment(\.colorScheme) private var scheme

    @AppStorage("sugerly.topbar.style") private var style = "soft"

    private var bar: some View {
        HStack(spacing: 6) {
            leading
            Spacer(minLength: 4)
            BrandLogo(height: 28)
                .accessibilityLabel("Sugerly")
            Spacer(minLength: 4)
            trailing
        }
        .environment(\.colorScheme, scheme)
        .environment(\.barScheme, scheme)
        .environment(\.unifiedBar, true)
        .padding(.horizontal, 8)
        .frame(width: min(UIScreen.main.bounds.width - 32, 728), height: 48)
        // Frosted glass, like the cards, with a real blur since the page scrolls
        // under it (the outlined style adds a theme edge).
        .glassFrame(radius: 22, tint: style == "tinted" ? Theme.soft : nil, blur: true)
        .overlay {
            if style == "outline" {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.main.opacity(0.5), lineWidth: 1)
            }
        }
        .accessibilityIdentifier("unified-top-bar")
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .principal) { bar }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar { ToolbarItem(placement: .principal) { bar } }
        }
    }
}

private struct UnifiedBarKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var unifiedBar: Bool {
        get { self[UnifiedBarKey.self] }
        set { self[UnifiedBarKey.self] = newValue }
    }
}

// The light / dark look a top bar's buttons keep whatever scrolls under them
// (set by plainToolbar). nil everywhere else.
private struct BarSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    var barScheme: ColorScheme? {
        get { self[BarSchemeKey.self] }
        set { self[BarSchemeKey.self] = newValue }
    }
}

extension Color {
    /// This colour as it looks in `scheme`, so it stays that way even where
    /// iOS switches light / dark by itself (nil: keeps following the page).
    func fixed(_ scheme: ColorScheme?) -> Color {
        guard let scheme else { return self }
        return Color(uiColor: UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)))
    }
}

// A round top bar button: a white (or dark) circle with a thin edge.
private struct BarIcon: View {
    @Environment(\.unifiedBar) private var unified
    let icon: String
    var alert = false
    var bounce = 0
    @Environment(\.barScheme) private var barScheme

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(alert ? .multicolor : .monochrome)
            .foregroundStyle(Palette.text2.fixed(barScheme))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: bounce)
            .frame(width: 34, height: 34)
            .background(Palette.surface.fixed(barScheme).opacity(unified ? 0 : 1), in: Circle())
            .overlay(Circle().strokeBorder(Palette.border.fixed(barScheme).opacity(unified ? 0 : 1), lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - The tab bar

extension View {
    /// On iOS 26 the tab bar shrinks to a small bubble while you scroll down
    /// (the page gets the room) and comes back as soon as you scroll up.
    func compactTabBar(enabled: Bool = true) -> some View {
        modifier(CompactTabBar(enabled: enabled))
    }
}

private struct CompactTabBar: ViewModifier {
    var enabled = true
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            content
        }
    }
}

enum TabBarLook {
    // Before iOS 26 (which draws its own floating glass bar): a frosted bar,
    // readable grey icons, your accent for the tab you're on, and red
    // badges.
    static func apply() {
        guard #unavailable(iOS 26.0) else { return }
        let small = UIFont.systemFont(ofSize: 10, weight: .medium)
        let bold = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xA29BA8) : UIColor(hex: 0x6A646F) }
        let bar = UITabBarAppearance()
        bar.configureWithDefaultBackground()
        bar.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        bar.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x1B191F, alpha: 0.6) : UIColor(hex: 0xFFFFFF, alpha: 0.55) }
        bar.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x312D36) : UIColor(hex: 0xE9E5EA) }
        for layout in [bar.stackedLayoutAppearance, bar.inlineLayoutAppearance, bar.compactInlineLayoutAppearance] {
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted, .font: small]
            layout.selected.titleTextAttributes = [.font: bold]
            layout.normal.badgeBackgroundColor = UIColor(hex: 0xD12F45)
            layout.selected.badgeBackgroundColor = UIColor(hex: 0xD12F45)
        }
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }
}

// The + (and other "make something" buttons): a bright pink circle that
// gives a little bounce when the page opens, so it's easy to spot.
struct PinkCircleButton: View {
    let icon: String
    let label: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.barScheme) private var barScheme
    @State private var bounce = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(Theme.candy)
                        .frostGrain(in: Circle(), strength: 0.05)
                        .overlay(Circle().strokeBorder(Palette.rim(0.25).fixed(barScheme), lineWidth: 1))
                        .shadow(color: Theme.glow(0.3).fixed(barScheme), radius: 6, y: 3)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.86))
        .accessibilityLabel(label)
    }
}

// The menu button in the top left corner: a little pill with the pink
// menu lines and your picture, so it's clear it opens something. The
// picture is the pill's round end (no edge curving around it, which looked
// like a frame).
struct AccountButton: View {
    @Environment(\.unifiedBar) private var unified
    @Environment(AppModel.self) private var model
    @Environment(\.barScheme) private var barScheme

    var body: some View {
        Button {
            model.showMenu = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.main.fixed(barScheme))
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: unified ? 28 : 34)
            }
            .padding(.leading, unified ? 4 : 12)
            .frame(height: 34)
            .background(Palette.surface.fixed(barScheme).opacity(unified ? 0 : 1), in: Capsule())
            .shadow(color: .black.opacity(unified ? 0 : 0.08), radius: 5, y: 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        // (No click: the menu opening makes its own sound.)
        .buttonStyle(BouncyStyle(scale: 0.9, sound: false))
        .accessibilityLabel("Menu")
        .accessibilityHint("Your profile, music, servers, settings and more")
    }
}

// The first-time hint for the menu: a small pink-edged bubble just under
// the menu button, once, a moment after the app opens. It goes away by
// itself after 5 seconds, when tapped, or when the menu opens. (Drawn on
// the page, not as a pop-up from the bar, so there's no glass and no lag.)
private struct MenuHintBubble: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sugerly.hint.menu") private var seen = false
    @State private var shown = false
    // Only one page (there's one per tab) shows it.
    @MainActor private static var claimed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shown { bubble }
        }
        .task { await showOnce() }
        .onChange(of: model.showMenu) { _, open in
            if open { seen = true; hide() }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            HintArrow()
                .fill(Palette.surface)
                .frame(width: 18, height: 9)
                .padding(.leading, 26)
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.candy, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your menu").font(.display(17)).foregroundStyle(Palette.text)
                    Text("Profile, music, servers & settings").font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frostedFill(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.main.opacity(0.25), lineWidth: 1))
        }
        .shadow(color: Palette.shadow, radius: 12, y: 6)
        .padding(.leading, 12)
        .padding(.top, 2)
        .contentShape(Rectangle())
        .onTapGesture { hide() }
        .transition(.scale(scale: 0.85, anchor: .topLeading).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func showOnce() async {
        guard !seen, !Self.claimed,
              !ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("-ui-test") }) else { return }
        Self.claimed = true
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled, !seen else { return }
        seen = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.72)) { shown = true }
        try? await Task.sleep(for: .seconds(5))
        hide()
    }

    private func hide() {
        guard shown else { return }
        withAnimation(.easeOut(duration: 0.22)) { shown = false }
    }
}

// The little point on top of the hint bubble.
private struct HintArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// The music player and the call bar, stacked. Empty (no height at all) when
// nothing is playing and you're not in a call.
struct BottomDock: View {
    @Environment(Player.self) private var player
    @Environment(VoiceEngine.self) private var voice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let busy = (player.track != nil && !player.widgetHidden) || voice.room != nil
        VStack(spacing: 8) {
            VoiceDock()
            MiniPlayer()
        }
        // On iPad they stay a comfortable width in the middle.
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .padding(.top, busy ? 6 : 0)
        .padding(.bottom, busy ? 8 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: player.track?.id)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: voice.room?.id)
    }
}

// MARK: - Always a little motion

extension View {
    /// A tab's page fades in each time it comes on screen (switching tabs,
    /// swiping back to it). Put it on the content, not the background, so
    /// the page's colour never flashes.
    func appearFade() -> some View {
        modifier(AppearFade())
    }

    /// Fades and settles in as it scrolls onto the screen (and out as it
    /// leaves), following your finger.
    func scrollFade() -> some View {
        modifier(ScrollFade(axis: .vertical))
    }

    /// The same for cards in a sideways row, as you swipe through them.
    func swipeFade() -> some View {
        modifier(ScrollFade(axis: .horizontal))
    }
}

private struct AppearFade: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The page rises a few points as it fades in.
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear { withAnimation(reduceMotion ? Motion.fade : Motion.enter) { shown = true } }
    }
}

private struct ScrollFade: ViewModifier {
    let axis: Axis

    func body(content: Content) -> some View {
        // Native scrolling already moves the content. Transforming and fading
        // every card on every scroll frame forces extra compositing passes.
        content
    }
}

// MARK: - Titles in the round font

extension View {
    /// The page's name in the round font, in the middle of the top bar.
    func roundTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

// Two titles in the round font with a pink pill behind the one you're on
// (sits in the middle of the top bar, so it takes no extra room).
struct TitleSwitch: View {
    let titles: [String]
    @Binding var selection: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, title in
                Button {
                    if selection != i { TapSound.play(.select) }
                    withMotion(Motion.standard) { selection = i }
                } label: {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == i ? Theme.main : Palette.muted)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if selection == i {
                                Capsule().fill(Palette.surface)
                                    .shadow(color: Palette.shadow, radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(3)
        .glassFrame(radius: 18)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Lists in Sugerly's colours

extension View {
    /// A native grouped list on the blush background with white cards, in
    /// the flat look (no soft shadows under every row's icon, which made
    /// long lists like Settings stutter).
    func sugarList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .sugarBackground()
            .environment(\.flat, true)
    }
}

// A row title with a little icon tile (lists, account, settings). Every row
// uses your accent unless its colour means something (see Tone).
struct IconRow: View {
    let title: String
    var detail: String? = nil
    let icon: String
    var tone: Tone = .accent
    var value: String? = nil
    var danger = false
    var chevron = false

    var candy: Candy? = nil

    // Places and things get a candy tile in their own colour (music sky,
    // people grape, chats mint, rewards lemon…). Warnings, grey and
    // red rows keep a soft tile in their colour, so they still stand apart.
    private var tile: Candy? {
        if let candy { return candy }
        guard !danger, tone == .accent || tone == .gold else { return nil }
        return Candy.matching(icon) ?? (tone == .gold ? .lemon : nil)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let tile {
                CandyTile(icon: icon, candy: tile, size: 32)
            } else {
                // A soft tile in the row's colour with the symbol in that colour.
                let shade = danger ? Tone.danger : tone
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(shade.color)
                    .frame(width: 32, height: 32)
                    .background(shade.soft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.jakarta(15, .semibold)).foregroundStyle(danger ? Palette.danger : Palette.text)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let value {
                Text(value).font(.jakarta(14, .semibold)).foregroundStyle(Palette.muted)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted.opacity(0.7))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// Section titles in lists.
struct ListHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.jakarta(12, .semibold)).tracking(0.4).foregroundStyle(Palette.muted)
    }
}

// MARK: - Page openers

extension Binding where Value == [Route] {
    // A quick double tap opens a page once, not twice (which used to need two
    // taps on Back to get out again).
    var once: Binding<[Route]> {
        Binding(get: { wrappedValue }, set: { next in
            var clean: [Route] = []
            for route in next where clean.last != route { clean.append(route) }
            wrappedValue = clean
        })
    }
}
