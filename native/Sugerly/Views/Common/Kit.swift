import SwiftUI
import UIKit

// The frame every page sits in: iPhone's own tab bar and top bars (so the
// back button, the swipe back, the keyboard and the safe areas all behave
// exactly like other iPhone apps), in Sugerly's calm neutrals.

// MARK: - Main pages (the first page of each tab)

extension View {
    /// The first page of a tab: your picture on the left (your account), the
    /// bell and the + on the right, and the music / call bar at the bottom.
    func rootBar(create: Bool = true, search: (() -> Void)? = nil) -> some View {
        modifier(RootBar(create: create, search: search))
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
                .buttonStyle(SoftPressStyle(scale: 0.94))
                .accessibilityLabel("Search")
            }
            Button {
                TapSound.play(.tap)
                bellTaps += 1
                model.showNotifications = true
            } label: {
                BarIcon(icon: notes.unread > 0 ? "bell.badge.fill" : "bell", alert: notes.unread > 0, bounce: bellTaps)
            }
            .buttonStyle(SoftPressStyle(scale: 0.94))
            .accessibilityLabel("Notifications")
            .accessibilityValue(notes.unread > 0 ? "\(notes.unread) new" : "")
            if create {
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

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { leading }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { trailing }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { leading }
                ToolbarItem(placement: .topBarTrailing) { trailing }
            }
        }
    }
}

// A round top bar button: a white (or dark) circle with a thin edge.
private struct BarIcon: View {
    let icon: String
    var alert = false
    var bounce = 0

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(alert ? .multicolor : .monochrome)
            .foregroundStyle(Palette.text2)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 34, height: 34)
            .background(Palette.surface, in: Circle())
            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(Circle())
    }
}

// MARK: - The tab bar

extension View {
    /// On iOS 26 the tab bar shrinks to a small bubble while you scroll down
    /// (the page gets the room) and comes back as soon as you scroll up.
    func compactTabBar() -> some View {
        modifier(CompactTabBar())
    }
}

private struct CompactTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

enum TabBarLook {
    // Before iOS 26 (which draws its own floating glass bar): a plain
    // frosted bar matching the page, quiet grey icons, the accent for the
    // tab you're on, and red badges, in the iPhone's own font.
    static func apply() {
        guard #unavailable(iOS 26.0) else { return }
        let small = UIFont.systemFont(ofSize: 10, weight: .medium)
        let bold = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x85817B) : UIColor(hex: 0x8A867F) }
        let bar = UITabBarAppearance()
        bar.configureWithDefaultBackground()
        bar.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        bar.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x111111, alpha: 0.78) : UIColor(hex: 0xF6F5F2, alpha: 0.82) }
        bar.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x2C2C2C) : UIColor(hex: 0xE5E3DE) }
        for layout in [bar.stackedLayoutAppearance, bar.inlineLayoutAppearance, bar.compactInlineLayoutAppearance] {
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted, .font: small]
            layout.selected.titleTextAttributes = [.font: bold]
            layout.normal.badgeBackgroundColor = UIColor(hex: 0xD64545)
            layout.selected.badgeBackgroundColor = UIColor(hex: 0xD64545)
        }
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }
}

// The + (and other "make something" buttons): a solid accent circle, the
// one spot of colour in the top bar so it's easy to find. Still.
struct PinkCircleButton: View {
    let icon: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button {
            TapSound.play(.tap)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.main, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle(scale: 0.94))
        .accessibilityLabel(label)
    }
}

// The menu button in the top left corner: a little pill with the menu
// lines and your picture, so it's clear it opens something.
struct AccountButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showMenu = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text2)
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 28)
            }
            .padding(.leading, 11)
            .padding(.trailing, 3)
            .frame(height: 34)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        // (No click: the menu opening makes its own sound.)
        .buttonStyle(SoftPressStyle(scale: 0.95))
        .accessibilityLabel("Menu")
        .accessibilityHint("Your profile, music, servers, settings and more")
    }
}

// The first-time hint for the menu: a small bubble just under
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
                    .foregroundStyle(Palette.text)
                    .frame(width: 30, height: 30)
                    .background(Palette.surface2, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your menu").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                    Text("Profile, music, servers & settings").font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .padding(.leading, 12)
        .padding(.top, 2)
        .contentShape(Rectangle())
        .onTapGesture { hide() }
        .transition(.opacity.combined(with: .offset(y: -4)))
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
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.25)) { shown = true }
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
        let busy = player.track != nil || voice.room != nil
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

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(Motion.fade) { shown = true } }
            .onDisappear { shown = false }
    }
}

private struct ScrollFade: ViewModifier {
    let axis: Axis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            let vertical = axis == .vertical
            content.scrollTransition(.interactive.threshold(.visible(vertical ? 0.3 : 0.45)), axis: axis) { view, phase in
                view.opacity(phase.isIdentity ? 1 : 0.8)
            }
        }
    }
}

// MARK: - Page titles

extension View {
    /// The page's name in the middle of the top bar.
    func roundTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.jakarta(17, .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

// Two titles as a small segmented switch: the one you're on sits on a
// white tab (in the middle of the top bar, so it takes no extra room).
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
                        .font(.jakarta(15, .semibold))
                        .foregroundStyle(selection == i ? Palette.text : Palette.muted)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if selection == i {
                                Capsule().fill(Palette.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
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
        .background(Palette.surface2, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Lists in Sugerly's colours

extension View {
    /// A native grouped list on the page background with white cards.
    func sugarList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { Palette.bg.ignoresSafeArea() }
    }
}

// A row title with a small grey icon tile (lists, account, settings). The
// colours the pages pass in aren't used any more: rows of rainbow tiles
// made every list look the same and busy.
struct IconRow: View {
    let title: String
    var detail: String? = nil
    let icon: String
    var colors: [UInt32] = [0xEE8FAE, 0xD9577F]
    var value: String? = nil
    var danger = false
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(danger ? Palette.danger : Palette.text2)
                .frame(width: 30, height: 30)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.jakarta(16, .medium)).foregroundStyle(danger ? Palette.danger : Palette.text)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let value {
                Text(value).font(.jakarta(15)).foregroundStyle(Palette.muted)
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
        Text(title).font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
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
