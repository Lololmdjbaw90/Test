import SwiftUI
import UIKit

// Sugerly's look: soft pastel pages built from one palette — cream
// (FCF0D6), ivory (F8FBE6), blush (FAD0DC), pink (F6BDCC) and rose (F9B0C4) —
// with a deeper rose for buttons and links so text stays easy to read, plum
// text instead of black, and the iPhone's own fonts. Pick another accent in
// Settings and the pinks follow it; the cream stays.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    // 0xRRGGBB, for saving a picked colour.
    var rgbHex: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}

enum Palette {
    // The palette itself.
    static let creamHex: UInt32 = 0xFCF0D6
    static let ivoryHex: UInt32 = 0xF8FBE6
    static let blushHex: UInt32 = 0xFAD0DC
    static let pinkHex: UInt32 = 0xF6BDCC
    static let roseHex: UInt32 = 0xF9B0C4

    // Pages: a warm cream-white with a breath of your pastel. Cards: near
    // white. Fields, chips and tracks: your pastel, softened. Text: plum.
    static var bg: Color { pastel(0xFFF9F2, 0.10, dark: 0x141215, 0.07) }
    static var surface: Color { pastel(0xFFFFFF, 0.035, dark: 0x1D181C, 0.07) }
    static var surface2: Color { pastel(0xFFFDF8, 0.30, dark: 0x2A2227, 0.09) }
    static var border: Color { pastel(0xFFFDF8, 0.36, dark: 0x382D33, 0.10) }
    static var borderStrong: Color { pastel(0xFFFDF8, 0.60, dark: 0x4A3B43, 0.12) }
    static var text: Color { ink(0x2B1D24, 0.10, dark: 0xFBF1F4, 0.04) }
    static var text2: Color { ink(0x5E4A53, 0.12, dark: 0xD6C3CB, 0.05) }
    static var muted: Color { ink(0x95838B, 0.12, dark: 0x9C8891, 0.06) }

    // Cream and ivory for warm touches (coins, rewards, highlights).
    static let cream = Color.dynamic(light: creamHex, dark: 0x3A3023)
    static let ivory = Color.dynamic(light: ivoryHex, dark: 0x2B2D24)
    // Your blush (the palette's own for rose).
    static var blush: Color { pastel(0xFFFFFF, 0.55, dark: 0x2A2227, 0.16) }

    // The three stops of a hero card: cream → blush → your pastel. In dark
    // mode, deep plum shades of your colour.
    static var heroA: Color { hero(light: mix(creamHex, Theme.lightHex, 0.08), 0.12) }
    static var heroB: Color { hero(light: mix(0xFFFFFF, Theme.lightHex, 0.55), 0.22) }
    static var heroC: Color { hero(light: Theme.lightHex, 0.34) }

    // One of the palette colours as a soft tile (light mode), or a plum
    // shade of it in dark mode.
    static func tile(_ hex: UInt32) -> Color {
        let d = mix(0x2A2227, hex, 0.14)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: d) : UIColor(hex: hex) })
    }

    static let danger = Color(hex: 0xE5484D)
    static let success = Color(hex: 0x2E9E6B)
    static let warning = Color(hex: 0xE09A1A)
    static let gold = Color(hex: 0xE9A21F)
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.4) : UIColor(hex: 0x7A2E4E, alpha: 0.08) })

    // Reading the accent here makes every view that uses a page colour
    // redraw when you pick another accent.
    private static func pastel(_ light: UInt32, _ lightAmount: Double, dark: UInt32, _ darkAmount: Double) -> Color {
        let l = mix(light, Theme.lightHex, lightAmount), d = mix(dark, Theme.mainHex, darkAmount)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: d) : UIColor(hex: l) })
    }

    private static func ink(_ light: UInt32, _ lightAmount: Double, dark: UInt32, _ darkAmount: Double) -> Color {
        let l = mix(light, Theme.mainHex, lightAmount), d = mix(dark, Theme.lightHex, darkAmount)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: d) : UIColor(hex: l) })
    }

    private static func hero(light: UInt32, _ darkAmount: Double) -> Color {
        let d = mix(0x1D171B, Theme.mainHex, darkAmount)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: d) : UIColor(hex: light) })
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
        func blend(_ shift: UInt32) -> UInt32 {
            UInt32(max(0, min(255, (ch(a, shift) * (1 - t) + ch(b, shift) * t).rounded()))) << shift
        }
        return blend(16) | blend(8) | blend(0)
    }
}

// The five accent colours you can pick in Settings (the logo follows along).
enum Accent: String, CaseIterable, Identifiable {
    case rose, lavender, mint, peach, sky
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    private var rgb: (UInt32, UInt32) {
        switch self {
        // Rose is the palette's own pink, with a deeper rose for buttons.
        case .rose: return (0xDB6491, Palette.roseHex)
        case .lavender: return (0x7F67E0, 0xC3B6F5)
        case .mint: return (0x2A9C7C, 0x9EDCC8)
        case .peach: return (0xE07650, 0xF6C2AC)
        case .sky: return (0x3A84D8, 0xA9CDF3)
        }
    }
    var main: Color { Color(hex: rgb.0) }
    var light: Color { Color(hex: rgb.1) }
    var mainHex: UInt32 { rgb.0 }
    var lightHex: UInt32 { rgb.1 }
    // Flat: the accent itself (kept as a gradient type so every place that
    // used one still works).
    var gradient: LinearGradient { LinearGradient(colors: [main, main], startPoint: .top, endPoint: .bottom) }
    var logo: String { "Logo-\(rawValue)" }
}

// The colours in use. It's observable, so every view that reads a Theme
// colour redraws (with a smooth fade) when you pick another — without
// rebuilding the app, so music, calls and where you are all stay put.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    var accent: Accent = .rose
    var customMain: UInt32?
    var customLight: UInt32?
}

enum Theme {
    // Set from your profile at the top of the app.
    static var accent: Accent {
        get { ThemeStore.shared.accent }
        set { if ThemeStore.shared.accent != newValue { ThemeStore.shared.accent = newValue } }
    }
    // App colours an admin picked for everyone (Admin → App colors), used
    // unless you chose your own accent in Settings.
    static var custom: (main: UInt32, light: UInt32)? {
        get {
            guard let main = ThemeStore.shared.customMain else { return nil }
            return (main, ThemeStore.shared.customLight ?? main)
        }
        set {
            if ThemeStore.shared.customMain != newValue?.main { ThemeStore.shared.customMain = newValue?.main }
            if ThemeStore.shared.customLight != newValue?.light { ThemeStore.shared.customLight = newValue?.light }
        }
    }
    static var main: Color { custom.map { Color(hex: $0.main) } ?? accent.main }
    static var mainHex: UInt32 { custom?.main ?? accent.mainHex }
    static var lightHex: UInt32 { custom?.light ?? accent.lightHex }
    static var light: Color { custom.map { Color(hex: $0.light) } ?? accent.light }
    static var pink: Color { main }
    static var rose: Color { main }
    static var soft: Color { main.opacity(0.12) }
    // The accent as a candy fill (a touch lighter at the top), used for
    // buttons, badges and highlights everywhere.
    static var gradient: LinearGradient { candy }
    // The palette as a soft wash, for hero cards: cream → blush → pastel.
    static var pastel: LinearGradient {
        LinearGradient(colors: [Palette.heroA, Palette.heroB, Palette.heroC], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    // A juicy candy fill for main buttons: the accent, a touch lighter at
    // the top.
    static var candy: LinearGradient {
        LinearGradient(colors: [Color(hex: Palette.mix(mainHex, 0xFFFFFF, 0.14)), main], startPoint: .top, endPoint: .bottom)
    }
    // Progress bars: pastel into the accent.
    static var progress: LinearGradient {
        LinearGradient(colors: [light, main], startPoint: .leading, endPoint: .trailing)
    }
    static let lavender = Color(hex: 0xB19CFF)
    static var background: Color { Palette.bg }
    static var card: Color { Palette.surface }
    // Mimi and the logo: with a custom colour they use the rose drawings,
    // turned to the custom hue; otherwise the drawing for your accent.
    static var logoName: String { custom == nil ? accent.logo : Accent.rose.logo }
    static var tint: TintShift { custom.map { TintShift(from: 0xD9577F, to: $0.main) } ?? .none }
}

// The home screen icon follows your colour: one icon per accent, and custom
// colours get the closest one. iOS shows a short "icon changed" note.
@MainActor
enum AppIconSync {
    private static var pending: Task<Void, Never>?

    static func match(_ accent: Accent, custom: UInt32?) {
        let target = custom.map(nearest) ?? accent
        let name: String? = target == .rose ? nil : "AppIcon-\(target.rawValue.capitalized)"
        pending?.cancel()
        pending = Task { @MainActor in
            // Wait a moment so trying colours quickly only changes it once.
            try? await Task.sleep(for: .milliseconds(800))
            // Not in the middle of a call: iOS shows a pop-up for the new
            // icon, which got in the way. It changes once the call is over.
            while VoiceEngine.live && !Task.isCancelled { try? await Task.sleep(for: .seconds(2)) }
            let app = UIApplication.shared
            guard !Task.isCancelled, app.supportsAlternateIcons, app.alternateIconName != name,
                  app.applicationState == .active else { return }
            try? await app.setAlternateIconName(name)
        }
    }

    static func nearest(_ hex: UInt32) -> Accent {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let hue = h * 360
        let hues: [(Accent, CGFloat)] = [(.rose, 340), (.lavender, 253), (.mint, 163), (.peach, 16), (.sky, 213)]
        func distance(_ x: CGFloat) -> CGFloat { let d = abs(x - hue); return min(d, 360 - d) }
        return hues.min { distance($0.1) < distance($1.1) }?.0 ?? .rose
    }
}

// Turns the rose artwork (logo, Mimi) to any colour: rotates the hue from
// rose to the target and matches how strong the colour is. White and the
// dark outlines stay as they are.
struct TintShift: Equatable {
    var hue: Double = 0
    var saturation: Double = 1
    static let none = TintShift()

    init() {}
    init(from base: UInt32, to target: UInt32) {
        var h0: CGFloat = 0, s0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        UIColor(hex: base).getHue(&h0, saturation: &s0, brightness: &b0, alpha: &a0)
        UIColor(hex: target).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        hue = Double(h1 - h0) * 360
        saturation = min(1.5, max(0, Double(s1 / max(s0, 0.01))))
    }
}

extension View {
    func tintShift(_ t: TintShift) -> some View {
        hueRotation(.degrees(t.hue)).saturation(t.saturation)
    }
}

// MARK: - Fonts

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

extension UIFont {
    /// The top bars' titles: the iPhone's own letters, semibold.
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
        UIFont.systemFont(ofSize: size * 0.9, weight: weight == .heavy || weight == .black ? .semibold : weight)
    }
}

extension Font {
    // Headings: the iPhone's own letters, bold but not shouty, a little
    // smaller than the size asked for (the old fonts ran large). Grows with
    // the text size picked in iPhone Settings.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size * 0.82), weight: .bold)
    }
    // Small accents (greetings): the same letters, a touch lighter.
    static func cute(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size * 0.8), weight: .semibold)
    }
    // Everything else: the iPhone's own text font. (Named after the old
    // font so every screen picks it up.) Extra-heavy weights are calmed to
    // semibold / bold.
    static func jakarta(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let calm: Font.Weight
        switch weight {
        case .heavy, .black: calm = .bold
        case .bold: calm = .semibold
        default: calm = weight
        }
        return .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size), weight: calm)
    }
}

// MARK: - Building blocks

// A card: the near-white surface, a soft blush hairline and a gentle plum
// shadow underneath, so it sits lightly on the page.
struct SugarCard: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 22), style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(Palette.surface)
                    .shadow(color: Palette.shadow, radius: 10, y: 4)
            }
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
    }
}

// A hero card in the palette: cream into blush into your pastel.
struct PastelCard: ViewModifier {
    var radius: CGFloat = 22
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(Theme.pastel)
                    .overlay(alignment: .topLeading) {
                        // A soft sheen along the top edge.
                        shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    }
                    .shadow(color: Palette.shadow, radius: 14, y: 6)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.55), lineWidth: 1))
    }
}

extension View {
    func sugarCard(radius: CGFloat = 18, padding: CGFloat = 0) -> some View { modifier(SugarCard(radius: radius, padding: padding)) }
    func pastelCard(radius: CGFloat = 22, padding: CGFloat = 16) -> some View { modifier(PastelCard(radius: radius, padding: padding)) }

    // Floating bits (the music player): the surface with a hairline edge and
    // a soft shadow so it reads above the page.
    func glassPill(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(cornerRadius, 22), style: .continuous)
        return self
            .background { shape.fill(Palette.surface).shadow(color: Palette.shadow, radius: 12, y: 4) }
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
    }

    // Text filled with the accent gradient.
    func gradientFill() -> some View {
        self.foregroundStyle(Theme.gradient)
    }
}

struct GradientButtonStyle: ButtonStyle {
    var height: CGFloat = 48
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        GradientButtonBody(configuration: configuration, height: height, fullWidth: fullWidth)
    }
}

// The main button: a candy-rose pill — the accent with a soft highlight on
// top, white text and a little rosy shadow. It squishes when pressed and
// springs back.
private struct GradientButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    let fullWidth: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        configuration.label
            .font(.jakarta(15, .semibold))
            .foregroundStyle(.white)
            // Stays on one line (shrinking a little if it must).
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: min(height, 50))
            .background {
                shape.fill(Theme.candy)
                    .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: Theme.main.opacity(enabled ? (pressed ? 0.12 : 0.28) : 0), radius: pressed ? 4 : 10, y: pressed ? 2 : 5)
            }
            .opacity(enabled ? (pressed ? 0.92 : 1) : 0.45)
            .scaleEffect(pressed && !Motion.reduced ? 0.965 : 1)
            .animation(pressed ? Motion.press : Motion.release, value: pressed)
    }
}

// The quieter button: a soft grey fill with the accent colour's text.
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jakarta(14, .semibold))
            .foregroundStyle(Theme.main)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: min(height, 46))
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.97 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
    }
}

// Rounded filter chip ("For you", "Pop", "#wip"…).
struct Chip: View {
    let title: String
    var icon: String? = nil
    let active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.jakarta(14, .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(active ? Color.white : Palette.text2)
            .background {
                if active {
                    Capsule().fill(Theme.candy)
                        .shadow(color: Theme.main.opacity(0.25), radius: 6, y: 3)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    Capsule().fill(Palette.surface2)
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
            }
            .scaleEffect(active ? 1 : 0.97)
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.92))
        .sensoryFeedback(.selection, trigger: active)
        .motion(Motion.playful, value: active)
    }
}

// Section title in the round font with a small accent icon, and an
// optional "See all". Kept quiet so the content is what stands out.
struct SectionHeader: View {
    let icon: String
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title).font(.display(22)).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.jakarta(14, .medium))
                    .foregroundStyle(Theme.main)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.soft, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.92))
            }
        }
    }
}

// Levels (same ladder as the website).
struct LevelInfo {
    static let ladder: [(level: Int, xp: Int, title: String, color: UInt32)] = [
        (1, 0, "Newcomer", 0x94A3B8), (2, 100, "Sketcher", 0x3B82F6), (3, 300, "Artisan", 0x10B981),
        (4, 700, "Creator", 0x8B5CF6), (5, 1500, "Master", 0xF0A020), (6, 3000, "Luminary", 0xF97316),
        (7, 6000, "Legend", 0xE86D98), (8, 10000, "Mimi Elite", 0xDB2777),
    ]
    let level: Int
    let title: String
    let color: Color
    let progress: Double
    let xpInLevel: Int
    let xpNeeded: Int
    let nextLevel: Int?

    init(xp: Int) {
        var index = 0
        for (i, step) in Self.ladder.enumerated() where xp >= step.xp { index = i }
        let current = Self.ladder[index]
        level = current.level
        title = current.title
        color = Color(hex: current.color)
        if index + 1 < Self.ladder.count {
            let next = Self.ladder[index + 1]
            xpInLevel = xp - current.xp
            xpNeeded = next.xp - current.xp
            progress = min(1, Double(xpInLevel) / Double(max(1, xpNeeded)))
            nextLevel = next.level
        } else {
            xpInLevel = 0
            xpNeeded = 0
            progress = 1
            nextLevel = nil
        }
    }
}

struct XPBar: View {
    let info: LevelInfo
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(info.nextLevel.map { "\(info.xpInLevel) / \(info.xpNeeded) XP to Lv.\($0)" } ?? "Max level reached")
                Spacer()
                Text("\(Int(info.progress * 100))%")
            }
            .font(.jakarta(11, .semibold))
            .foregroundStyle(Palette.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface2)
                    Capsule().fill(Theme.progress).frame(width: max(8, geo.size.width * shown))
                        .overlay(alignment: .trailing) {
                            // A little glowing bead at the end of the bar.
                            Circle().fill(.white).frame(width: 4, height: 4).padding(.trailing, 2).opacity(shown > 0.04 ? 0.9 : 0)
                        }
                }
            }
            .frame(height: 8)
        }
        .onAppear { updateProgress() }
        .onChange(of: info.progress) { _, _ in updateProgress() }
    }

    private func updateProgress() {
        withAnimation(reduceMotion ? nil : Motion.drawer.delay(0.12)) { shown = info.progress }
    }
}

// Tiny logo with a soft shine, like the website's top bar. The shine sweeps
// across every few seconds (a one-off animation, not a constant redraw) and
// is clipped to the logo's own shape; the logo gives a little hop when tapped.
struct BrandLogo: View {
    var height: CGFloat = 34
    @State private var hop = false

    private var logo: some View {
        Image(Theme.logoName).resizable().scaledToFit().frame(height: height).tintShift(Theme.tint)
    }

    var body: some View {
        // Still: it only does a little hop when you tap it.
        logo
            .scaleEffect(hop ? 1.12 : 1)
            .rotationEffect(.degrees(hop ? -4 : 0))
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { hop = true }
                Task { try? await Task.sleep(for: .milliseconds(220)); withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { hop = false } }
            }
            .accessibilityLabel("Sugerly")
    }
}

// The app icon (the polka-dot S with Mimi peeking over it) in your colour,
// with sparkles that twinkle and drift a little — the home screen icon
// can't move, this can.
struct AppBadge: View {
    var size: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var art: String {
        let accent = Theme.custom.map { AppIconSync.nearest($0.main) } ?? Theme.accent
        return "IconBadge-\(accent.rawValue)"
    }

    // Same spots as the home screen icon (x, y, size out of 1024).
    private let sparkles: [(CGFloat, CGFloat, CGFloat, Double)] = [(846, 170, 124, 0), (930, 296, 52, 0.5), (130, 250, 76, 1.0)]

    var body: some View {
        Image(art).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityLabel("Sugerly")
    }
}

// A soft four-point star, like the sparkles on the icon.
struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : r * 0.28
            let point = CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

// A reward moment: two soft rings ripple out in your colour and fade.
// Clean, quick, and it never covers text.
struct SparkleBurst: View {
    var radius: CGFloat = 80
    @State private var go = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ring(0)
            ring(0.12)
        }
        .frame(width: radius * 2, height: radius * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { go = true }
    }

    private func ring(_ delay: Double) -> some View {
        Circle()
            .strokeBorder(Theme.main, lineWidth: go ? 1 : 5)
            .scaleEffect(go ? 1 : 0.35)
            .opacity(reduceMotion ? 0 : (go ? 0 : 0.55))
            .animation(.easeOut(duration: 0.8).delay(delay), value: go)
    }
}

// MARK: - Loading placeholders

// A soft light sweeping across a placeholder, like the website's .skeleton.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var sweep = false

    func body(content: Content) -> some View {
        // With Reduce Motion on, the placeholder gently breathes instead.
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    // A soft rosy light glides across, moved by the graphics
                    // chip (no redrawing every frame).
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Theme.light.opacity(scheme == .dark ? 0.16 : 0.42), .white.opacity(scheme == .dark ? 0.06 : 0.5), Theme.light.opacity(scheme == .dark ? 0.16 : 0.42), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.7)
                            .offset(x: sweep ? geo.size.width * 1.1 : -geo.size.width * 0.8)
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) { sweep = true }
                }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }

    // Sections rise a few points and fade in one after another when a page
    // opens (quickly: the page is usable straight away).
    func stagger(_ shown: Bool, _ index: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduced ? 0 : 10)
            .animation(Motion.staggered(Motion.enter, index), value: shown)
    }
}

struct SkeletonBlock: View {
    var height: CGFloat
    var radius: CGFloat = 18
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.surface2)
            .frame(height: height)
            .shimmer()
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// A post-shaped placeholder card.
struct SkeletonCard: View {
    var media = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Palette.surface2).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Palette.surface2).frame(width: 120, height: 10)
                    Capsule().fill(Palette.surface2).frame(width: 70, height: 8)
                }
            }
            Capsule().fill(Palette.surface2).frame(height: 10)
            Capsule().fill(Palette.surface2).frame(width: 200, height: 10)
            if media { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface2).frame(height: 220) }
        }
        .shimmer()
        .sugarCard(radius: 26, padding: 16)
    }
}

// A chat-row placeholder.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Palette.surface2).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Palette.surface2).frame(width: 140, height: 11)
                Capsule().fill(Palette.surface2).frame(width: 200, height: 9)
            }
            Spacer()
        }
        .shimmer()
        .sugarCard(radius: 22, padding: 12)
    }
}

// Little sparkles that enter once (for greetings and empty states).
// All three stay inside their own little box, so they never sit on top of
// the text next to them; they twinkle and turn in place.
struct Twinkle: View {
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
