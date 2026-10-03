import SwiftUI
import UIKit
import TipKit

// The frame every page sits in: iPhone's own tab bar and top bars (so the
// back button, the swipe back, the keyboard and the safe areas all behave
// exactly like other iPhone apps), in Sugerly's pink.

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

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let search {
                        Button(action: search) {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search")
                    }
                    Button { model.showNotifications = true } label: {
                        Image(systemName: notes.unread > 0 ? "bell.badge.fill" : "bell")
                            .symbolRenderingMode(.multicolor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel("Notifications")
                    .accessibilityValue(notes.unread > 0 ? "\(notes.unread) new" : "")
                }
                if create {
                    ToolbarItem(placement: .topBarTrailing) {
                        PinkCircleButton(icon: "plus", label: "Create") { model.showCreate = true }
                    }
                }
            }
            .bottomDock()
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
    // Before iOS 26 (which draws its own floating glass bar): a soft blush
    // frosted bar, quiet icons, the pink one for the tab you're on, and
    // pink badges, in Sugerly's font.
    static func apply() {
        guard #unavailable(iOS 26.0) else { return }
        let small = UIFont(name: "PlusJakartaSans-SemiBold", size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)
        let bold = UIFont(name: "PlusJakartaSans-Bold", size: 10) ?? .systemFont(ofSize: 10, weight: .bold)
        let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x86707C) : UIColor(hex: 0x9C8A93) }
        let bar = UITabBarAppearance()
        bar.configureWithDefaultBackground()
        bar.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        bar.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x140A11, alpha: 0.72) : UIColor(hex: 0xFFF3F7, alpha: 0.8) }
        bar.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x351F2C) : UIColor(hex: 0xF8D9E4) }
        for layout in [bar.stackedLayoutAppearance, bar.inlineLayoutAppearance, bar.compactInlineLayoutAppearance] {
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted, .font: small]
            layout.selected.titleTextAttributes = [.font: bold]
            layout.normal.badgeBackgroundColor = UIColor(hex: 0xE8457C)
            layout.selected.badgeBackgroundColor = UIColor(hex: 0xE8457C)
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
    @State private var bounce = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .symbolEffect(.bounce, value: bounce)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(Theme.main)
        .accessibilityLabel(label)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(0.9))
            bounce += 1
        }
    }
}

// The menu button in the top left corner: a little pill with the pink
// menu lines and your picture, so it's clear it opens something. Everything
// stays inside the pill (nothing sticks out to get cut off), and the first
// time you open the app a tip bubble points at it.
struct AccountButton: View {
    @Environment(AppModel.self) private var model
    private let tip = MenuTip()

    var body: some View {
        Button {
            tip.invalidate(reason: .actionPerformed)
            model.showMenu = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.main)
                Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 28)
            }
            .padding(.leading, 11)
            .padding(.trailing, 3)
            .frame(height: 34)
            .background { MenuPillBackground() }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popoverTip(tip)
        .accessibilityLabel("Menu")
        .accessibilityHint("Your profile, music, servers, settings and more")
    }
}

// On iOS 26 the top bar already puts its glass around the pill; before
// that, a soft pink pill of its own.
private struct MenuPillBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
        } else {
            Capsule()
                .fill(Theme.main.opacity(0.12))
                .overlay(Capsule().strokeBorder(Theme.main.opacity(0.18), lineWidth: 1))
        }
    }
}

// The first-time hint for the menu.
struct MenuTip: Tip {
    var title: Text { Text("Your menu") }
    var message: Text? { Text("Tap here for your profile, music, servers, settings and more.") }
    var image: Image? { Image(systemName: "line.3.horizontal.circle.fill") }
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
            .onAppear { withAnimation(.easeOut(duration: 0.24)) { shown = true } }
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
                view
                    .opacity(phase.isIdentity ? 1 : 0.4)
                    .scaleEffect(phase.isIdentity ? 1 : (vertical ? 0.95 : 0.9))
            }
        }
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
                        .font(.display(24))
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
                Button { withAnimation(.snappy(duration: 0.28)) { selection = i } } label: {
                    Text(title)
                        .font(.display(19))
                        .foregroundStyle(selection == i ? Color.white : Palette.text2)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if selection == i {
                                Capsule().fill(Theme.gradient)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
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
    /// A native grouped list on the blush background with white cards.
    func sugarList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { Palette.bg.ignoresSafeArea() }
    }
}

// A row title with a little gradient icon tile (lists, account, settings).
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        Text(title).font(.jakarta(12, .heavy)).tracking(0.8).foregroundStyle(Palette.muted)
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
