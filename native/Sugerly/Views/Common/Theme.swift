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
        Palette.swatch(light, 1, dark, 1)
    }
    // A coloured glow under a tile on light pages; on dark pages a plain soft
    // shadow (coloured glows look like neon there).
    func softGlow(_ opacity: Double) -> Color {
        let tint = UIColor(self)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.3) : tint.withAlphaComponent(opacity) })
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

    // Pages: a calm warm off-white with only a breath of your pastel, so
    // white cards and the candy colours stand out (pink on pink on pink
    // looked messy). Cards: clean white. Fields, chips and tracks: a soft
    // warm grey with a hint of your colour. Hairlines: barely there. Text: plum.
    static var bg: Color { pastel(0xFFFFFF, 0.015, dark: 0x131114, 0.05) }
    static var surface: Color { pastel(0xFFFFFF, 0.0, dark: 0x1D191C, 0.06) }
    static var surface2: Color { pastel(0xF4F0EF, 0.12, dark: 0x29232A, 0.07) }
    static var border: Color { pastel(0xEEE8E7, 0.10, dark: 0x352D33, 0.08) }
    static var borderStrong: Color { pastel(0xE2DAD9, 0.18, dark: 0x473B43, 0.10) }
    static var text: Color { ink(0x2B1D24, 0.10, dark: 0xFBF1F4, 0.04) }
    static var text2: Color { ink(0x5E4A53, 0.12, dark: 0xD6C3CB, 0.05) }
    static var muted: Color { ink(0x95838B, 0.12, dark: 0x9C8891, 0.06) }

    // Cream and ivory for warm touches (coins, rewards, highlights).
    static let cream = Color.dynamic(light: creamHex, dark: 0x3A3023)
    static let ivory = Color.dynamic(light: ivoryHex, dark: 0x2B2D24)
    // Your blush: a light tint of your colour, for small highlights.
    static var blush: Color { pastel(0xFFFFFF, 0.30, dark: 0x2A2227, 0.14) }

    // The three stops of a hero card: a fresh, clear run from a pale tint of
    // your pastel into a juicier shade of it. In dark mode, deep plum shades
    // of your colour.
    static var heroA: Color { hero(light: mix(0xFFFFFF, Theme.peachHex, 0.42), 0.12) }
    static var heroB: Color { hero(light: mix(0xFFFFFF, Theme.lightHex, 0.75), 0.22) }
    static var heroC: Color { hero(light: mix(Theme.lightHex, Theme.partnerHex, 0.45), 0.34) }

    // The glossy touches (a white rim, a sheen along the top) are for light
    // pages. On dark pages they fade to a faint hairline, so nothing shines
    // like plastic.
    static func rim(_ opacity: Double) -> Color {
        swatch(0xFFFFFF, opacity, 0xFFFFFF, min(0.07, opacity * 0.12))
    }

    static let danger = Color(hex: 0xE5484D)
    static let success = Color(hex: 0x2E9E6B)
    static let warning = Color(hex: 0xE09A1A)
    static let gold = Color(hex: 0xE9A21F)
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.4) : UIColor(hex: 0x4A2A3A, alpha: 0.07) })

    // Reading the accent here makes every view that uses a page colour
    // redraw when you pick another accent.
    private static func pastel(_ light: UInt32, _ lightAmount: Double, dark: UInt32, _ darkAmount: Double) -> Color {
        swatch(mix(light, Theme.lightHex, lightAmount), 1, mix(dark, Theme.mainHex, darkAmount), 1)
    }

    private static func ink(_ light: UInt32, _ lightAmount: Double, dark: UInt32, _ darkAmount: Double) -> Color {
        swatch(mix(light, Theme.mainHex, lightAmount), 1, mix(dark, Theme.lightHex, darkAmount), 1)
    }

    private static func hero(light: UInt32, _ darkAmount: Double) -> Color {
        swatch(light, 1, mix(0x1D171B, Theme.mainHex, darkAmount), 1)
    }

    // Every light/dark pair is made once and then reused, so a colour is the
    // very same value each time a page redraws. (Fresh copies made SwiftUI
    // think colours had changed, and bits of a page could blink dark while it
    // "animated" between two copies of the same colour.)
    private struct SwatchKey: Hashable {
        let light: UInt32, dark: UInt32
        let lightAlpha: UInt8, darkAlpha: UInt8
    }
    nonisolated(unsafe) private static var swatches: [SwatchKey: Color] = [:]
    private static let swatchLock = NSLock()

    static func swatch(_ light: UInt32, _ lightAlpha: Double, _ dark: UInt32, _ darkAlpha: Double) -> Color {
        func byte(_ v: Double) -> UInt8 { UInt8((max(0, min(1, v)) * 255).rounded()) }
        let key = SwatchKey(light: light, dark: dark, lightAlpha: byte(lightAlpha), darkAlpha: byte(darkAlpha))
        swatchLock.lock()
        defer { swatchLock.unlock() }
        if let hit = swatches[key] { return hit }
        let la = CGFloat(key.lightAlpha) / 255, da = CGFloat(key.darkAlpha) / 255
        let made = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: da) : UIColor(hex: light, alpha: la) })
        swatches[key] = made
        return made
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
        func blend(_ shift: UInt32) -> UInt32 {
            UInt32(max(0, min(255, (ch(a, shift) * (1 - t) + ch(b, shift) * t).rounded()))) << shift
        }
        return blend(16) | blend(8) | blend(0)
    }

    // The same colour turned round the colour wheel (negative: towards
    // purple, positive: towards orange).
    static func turn(_ hex: UInt32, _ degrees: Double, saturation: Double = 1, brightness: Double = 1) -> UInt32 {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = h + CGFloat(degrees / 360)
        hue -= floor(hue)
        let color = UIColor(hue: hue, saturation: min(1, s * saturation), brightness: min(1, b * brightness), alpha: 1)
        return color.rgbHex
    }
}

extension UIColor {
    var rgbHex: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}

// The few colours icons and tiles use, so colour always means the same
// thing instead of looking random: your accent for places, settings and
// actions; gold for rewards (coins, crowns, stars, streaks); green for
// "ready" and "online"; amber for "needs a look"; red for things that delete
// or block; a quiet grey for the rest.
enum Tone {
    case accent, gold, success, warning, danger, neutral

    var color: Color {
        switch self {
        case .accent: return Theme.main
        case .gold: return Palette.gold
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        case .neutral: return Palette.muted
        }
    }
    // The soft tile behind an icon in this colour.
    var soft: Color { color.opacity(0.12) }
}

// Juicy candy colours for the little icon tiles that take you places (Home's
// shortcuts, the "new post / reel / drawing / song" buttons, menus). Each
// place keeps its own colour everywhere: music is always sky, servers mint,
// people grape, rewards lemon, posts berry, reels peach.
enum Candy: CaseIterable {
    case berry, peach, lemon, mint, sky, grape

    private var stops: (UInt32, UInt32) {
        switch self {
        case .berry: return (0xFF8DB4, 0xEC4F86)
        case .peach: return (0xFFB487, 0xF27D45)
        case .lemon: return (0xFFD46A, 0xF0A92C)
        case .mint: return (0x7EDFBD, 0x24B386)
        case .sky: return (0x8DC7FF, 0x3F92EE)
        case .grape: return (0xC4A6FF, 0x8763EE)
        }
    }
    var color: Color { Color(hex: stops.1) }
    // Lighter at the top, like a boiled sweet. A touch deeper in dark mode.
    var gradient: LinearGradient {
        LinearGradient(colors: [Palette.swatch(stops.0, 1, Palette.mix(stops.0, stops.1, 0.4), 1),
                                Palette.swatch(stops.1, 1, Palette.mix(stops.1, 0x000000, 0.12), 1)],
                       startPoint: .top, endPoint: .bottom)
    }
    // The colour a symbol gets in lists and menus, so the same kind of
    // thing always has the same colour.
    static func matching(_ icon: String) -> Candy? {
        let rules: [(String, Candy)] = [
            ("music", .sky), ("bell", .berry), ("heart", .berry), ("drop", .berry), ("hare", .berry),
            ("person", .grape), ("moon", .grape), ("gearshape", .grape),
            ("bubble", .mint), ("message", .mint), ("phone", .mint), ("video", .mint),
            ("crown", .lemon), ("star", .lemon), ("gift", .lemon), ("hexagongrid", .lemon), ("sparkles", .lemon), ("key", .lemon), ("flame", .lemon),
            ("paint", .peach), ("storefront", .peach), ("photo", .peach), ("play", .peach), ("film", .peach),
            ("qrcode", .sky), ("lock", .sky), ("eye", .sky), ("globe", .sky), ("doc", .sky), ("info", .sky), ("link", .sky),
        ]
        return rules.first { icon.contains($0.0) }?.1
    }
    // A pale wash of the colour, for a tile's soft background.
    var soft: Color { Palette.swatch(Palette.mix(0xFFFFFF, stops.1, 0.14), 1, Palette.mix(0x1D191C, stops.1, 0.22), 1) }
}

// Flat look: no soft shadows. The menu uses it: every soft shadow is drawn
// again on each frame while something slides or scrolls, and the menu had
// dozens of them, which made it stutter.
private struct FlatKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var flat: Bool {
        get { self[FlatKey.self] }
        set { self[FlatKey.self] = newValue }
    }
}

extension View {
    /// A soft shadow, left off in the flat look (see `flat`).
    func softShadow(_ color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(SoftShadow(color: color, radius: radius, x: x, y: y))
    }
}

private struct SoftShadow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    @Environment(\.flat) private var flat

    func body(content: Content) -> some View {
        if flat {
            content
        } else {
            content.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
}

// A rounded candy square with a white icon: a shine on top and a soft
// coloured glow under it.
struct CandyTile: View {
    let icon: String
    let candy: Candy
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .softShadow(.black.opacity(0.12), radius: 1, y: 1)
            .frame(width: size, height: size)
            .background {
                shape.fill(candy.gradient)
                    .overlay(alignment: .top) {
                        shape.fill(LinearGradient(colors: [Palette.rim(0.45), .clear], startPoint: .top, endPoint: .center))
                            .padding(1)
                    }
                    .softShadow(candy.color.softGlow(0.28), radius: 6, y: 3)
            }
            .accessibilityHidden(true)
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
    // Your colour's partner: the same colour turned a little towards
    // purple (rose → orchid, sky → periwinkle…), and a warm peach. Gradients
    // run between them so they look juicy instead of flat.
    static var partnerHex: UInt32 { Palette.turn(mainHex, -28, saturation: 0.95) }
    static var peachHex: UInt32 { Palette.turn(mainHex, 30, saturation: 0.9, brightness: 1.08) }
    static var partner: Color { Color(hex: partnerHex) }
    // A juicy wash for hero cards: peachy light → your pastel → a touch of
    // its purple partner.
    static var pastel: LinearGradient {
        LinearGradient(colors: [Palette.heroA, Palette.heroB, Palette.heroC], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    // A juicy candy fill for main buttons: a lighter, warmer top-left into
    // the accent, then its purple partner bottom-right. In dark mode it's
    // a touch deeper, so it doesn't glow.
    static var candy: LinearGradient {
        let top = Palette.swatch(Palette.mix(Palette.turn(mainHex, 12), 0xFFFFFF, 0.2), 1, Palette.mix(mainHex, 0xFFFFFF, 0.06), 1)
        let middle = Palette.swatch(mainHex, 1, Palette.mix(mainHex, 0x000000, 0.06), 1)
        let bottom = Palette.swatch(partnerHex, 1, Palette.mix(partnerHex, 0x000000, 0.14), 1)
        return LinearGradient(colors: [top, middle, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    // The soft rosy glow under candy buttons and chips. On dark pages it's a
    // plain shadow instead (a pink glow there looks like neon).
    static func glow(_ opacity: Double) -> Color {
        Palette.swatch(mainHex, opacity, 0x000000, opacity > 0 ? 0.32 : 0)
    }
    // Progress bars: pastel into the accent into its partner.
    static var progress: LinearGradient {
        LinearGradient(colors: [light, main, partner], startPoint: .leading, endPoint: .trailing)
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
        .system(size: grown(size * 0.82, style, limit: 1.12), weight: .bold)
    }
    // Small accents (greetings): the same letters, a touch lighter.
    static func cute(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: grown(size * 0.8, style, limit: 1.12), weight: .semibold)
    }
    // Text grows with the iPhone's text size, but only so far: past that,
    // labels, chips and buttons got cut off ("45 c…") or pushed off the
    // screen. Smaller sizes are followed all the way down.
    static func grown(_ size: CGFloat, _ style: Font.TextStyle, limit: CGFloat = 1.15) -> CGFloat {
        min(UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size), (size * limit).rounded())
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
        return .system(size: grown(size, style), weight: calm)
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
                    .softShadow(Palette.shadow, radius: 1, y: 1)
                    .softShadow(Palette.shadow, radius: 14, y: 6)
            }
            .overlay(shape.strokeBorder(Palette.border.opacity(0.8), lineWidth: 1))
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
                        shape.fill(LinearGradient(colors: [Palette.rim(0.35), .clear], startPoint: .top, endPoint: .center))
                    }
                    .softShadow(Palette.shadow, radius: 14, y: 6)
            }
            .overlay(shape.strokeBorder(Palette.rim(0.55), lineWidth: 1))
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
                    .overlay { if enabled { ShineSweep(every: 4.2).clipShape(shape) } }
                    .overlay(shape.strokeBorder(Palette.rim(0.22), lineWidth: 1))
                    .shadow(color: Theme.glow(enabled ? (pressed ? 0.12 : 0.28) : 0), radius: pressed ? 4 : 10, y: pressed ? 2 : 5)
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
            // White with a soft shadow and a hint of your colour on the
            // edge, so it stands out on tinted pages too.
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface)
                    .shadow(color: Palette.shadow, radius: 6, y: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.main.opacity(0.2), lineWidth: 1))
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
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(active ? Color.white : Palette.text2)
            .background {
                if active {
                    Capsule().fill(Theme.candy)
                        .shadow(color: Theme.glow(0.25), radius: 6, y: 3)
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
    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // A little candy badge in the section's colour, which gives a
            // hop when the section comes into view.
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: shown)
                .frame(width: 30, height: 30)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    if let candy = Candy.matching(icon) {
                        shape.fill(candy.gradient).shadow(color: candy.color.softGlow(0.3), radius: 5, y: 2)
                    } else {
                        shape.fill(Theme.candy).shadow(color: Theme.glow(0.28), radius: 5, y: 2)
                    }
                }
                .accessibilityHidden(true)
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
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.soft, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.92))
            }
        }
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }
}

// A soft band of light that sweeps across now and then (buttons, hero
// cards). Still with Reduce Motion on.
struct ShineSweep: View {
    var every: Double = 4.5
    var strength: Double = 0.38

    var body: some View {
        if Motion.ambient && !Motion.reduced && !Motion.paused {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(strength), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(36, geo.size.width * 0.32), height: geo.size.height * 2)
                    .rotationEffect(.degrees(16))
                    .offset(y: -geo.size.height / 2)
                    .phaseAnimator([false, true]) { band, across in
                        band.offset(x: across ? geo.size.width * 1.25 : -geo.size.width * 0.55)
                    } animation: { across in
                        across ? .easeInOut(duration: 0.95).delay(every) : nil
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// Neat sparkles: a few four-pointed stars in fixed spots, each softly
// twinkling in turn. Core Animation does the twinkling, so it costs almost
// nothing; with Reduce Motion they just sit still.
struct TwinkleField: UIViewRepresentable {
    // Where a star sits, in points in from the top-right corner (so the
    // gaps between them stay the same on any size of card).
    struct Spot {
        let right: CGFloat, top: CGFloat, size: CGFloat, delay: Double
    }
    var colors: [UIColor] = [.white]
    // One neat little triangle in the top-right corner: a big star with two
    // small ones under it, far enough apart that they never touch, even at
    // their biggest and with their glow.
    var spots: [Spot] = [
        Spot(right: 24, top: 18, size: 13, delay: 0),
        Spot(right: 40, top: 40, size: 7, delay: 0.6),
        Spot(right: 10, top: 40, size: 7, delay: 1.2),
    ]

    func makeUIView(context: Context) -> FieldView { FieldView(colors: colors, spots: spots) }
    func updateUIView(_ view: FieldView, context: Context) {}

    final class FieldView: UIView {
        private var stars: [(CALayer, Spot)] = []
        private let moving: Bool

        init(colors: [UIColor], spots: [Spot]) {
            moving = Motion.ambient && !UIAccessibility.isReduceMotionEnabled
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            for (i, spot) in spots.enumerated() {
                let star = CALayer()
                let color = colors.isEmpty ? UIColor.white : colors[i % colors.count]
                star.contents = Self.sparkle(color)
                star.contentsGravity = .resizeAspect
                star.shadowColor = color.cgColor
                star.shadowOpacity = 0.6
                star.shadowRadius = 3
                star.shadowOffset = .zero
                layer.addSublayer(star)
                stars.append((star, spot))
            }
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (star, spot) in stars {
                star.bounds = CGRect(x: 0, y: 0, width: spot.size, height: spot.size)
                star.position = CGPoint(x: bounds.width - spot.right, y: spot.top)
            }
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            for (star, spot) in stars {
                star.removeAllAnimations()
                guard window != nil, moving else { continue }
                let twinkle = CAKeyframeAnimation(keyPath: "transform")
                twinkle.values = [
                    NSValue(caTransform3D: CATransform3DMakeScale(0.55, 0.55, 1)),
                    NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(1.1, 1.1, 1), CATransform3DMakeRotation(.pi / 8, 0, 0, 1))),
                    NSValue(caTransform3D: CATransform3DMakeScale(0.55, 0.55, 1)),
                ]
                let glow = CAKeyframeAnimation(keyPath: "opacity")
                glow.values = [0.35, 1, 0.35]
                let group = CAAnimationGroup()
                group.animations = [twinkle, glow]
                group.duration = 2.6
                group.repeatCount = .infinity
                group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                group.beginTime = CACurrentMediaTime() + spot.delay
                group.fillMode = .backwards
                group.isRemovedOnCompletion = false
                star.add(group, forKey: "twinkle")
            }
        }

        // A soft four-pointed sparkle in a colour, drawn once per colour.
        private static var drawn: [UIColor: CGImage] = [:]
        static func sparkle(_ color: UIColor) -> CGImage? {
            if let hit = drawn[color] { return hit }
            let size = CGSize(width: 40, height: 40)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                let path = UIBezierPath()
                let c = CGPoint(x: 20, y: 20)
                path.move(to: CGPoint(x: c.x, y: 1))
                path.addQuadCurve(to: CGPoint(x: 39, y: c.y), controlPoint: c)
                path.addQuadCurve(to: CGPoint(x: c.x, y: 39), controlPoint: c)
                path.addQuadCurve(to: CGPoint(x: 1, y: c.y), controlPoint: c)
                path.addQuadCurve(to: CGPoint(x: c.x, y: 1), controlPoint: c)
                path.close()
                color.setFill()
                path.fill()
            }.cgImage
            drawn[color] = image
            return image
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
        // Two colours, not a rainbow: your accent, and gold from Master up.
        color = current.level >= 5 ? Palette.gold : Theme.main
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

// Collecting a reward: a warm glow swells, then little coins and sparkles
// fly out and fade. Drawn from the clock each frame (so it can't get stuck
// halfway or be skipped by other animations) and played again whenever
// `trigger` changes.
struct RewardBurst: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t < 1.3 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = min(size.width, size.height) / 2

                var glow = context
                glow.opacity = 0.55 * max(0, 1 - t / 0.9)
                let r = reach * CGFloat(0.35 + 0.45 * min(1, t / 0.25))
                glow.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                          with: .radialGradient(Gradient(colors: [Palette.gold.opacity(0.7), Theme.light.opacity(0.35), .clear]),
                                                center: center, startRadius: 0, endRadius: r))

                let pieces = 14
                let flight = 1 - pow(1 - min(1, t), 3)
                for i in 0..<pieces {
                    let seed = Double(i) * 12.9898
                    let jitter = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    // Evenly round the circle, starting far enough out that
                    // neighbours never touch, and all flying out alike.
                    let angle = Double(i) / Double(pieces) * 2 * .pi + jitter * 0.1
                    let distance = reach * CGFloat(0.45 + 0.5 * flight)
                    var piece = context
                    piece.opacity = max(0, 1 - max(0, t - 0.45) / 0.6)
                    piece.translateBy(x: center.x + CGFloat(cos(angle)) * distance,
                                      y: center.y + CGFloat(sin(angle)) * distance - CGFloat(10 * flight))
                    let dot = CGFloat((i % 3 == 0 ? 5.0 : 3.6) * (1 - 0.3 * flight))
                    if i % 3 == 0 {
                        // A little gold coin with a shine.
                        piece.fill(Path(ellipseIn: CGRect(x: -dot, y: -dot, width: dot * 2, height: dot * 2)), with: .color(Palette.gold))
                        piece.fill(Path(ellipseIn: CGRect(x: -dot * 0.45, y: -dot * 0.6, width: dot * 0.7, height: dot * 0.5)), with: .color(.white.opacity(0.7)))
                    } else {
                        piece.rotate(by: .radians(t * 3 + jitter * 6))
                        piece.fill(Self.sparkle(dot * 1.5), with: .color(i % 2 == 0 ? Theme.main : Theme.light))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            guard trigger > 0, !reduceMotion else { return }
            start = .now
            try? await Task.sleep(for: .seconds(1.4))
            start = nil
        }
    }

    // A four-pointed sparkle.
    private static func sparkle(_ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: .zero)
        p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: .zero)
        p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: .zero)
        return p
    }
}

// MARK: - Loading placeholders

// A soft light sweeping across a placeholder, like the website's .skeleton.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date.now

    func body(content: Content) -> some View {
        // With Reduce Motion on, the placeholder simply stays still.
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    // A soft rosy light glides across the placeholder's own
                    // shapes (never the gaps between them). Its place is worked
                    // out from the clock, so it can't set anything else drifting
                    // the way an endless animation can.
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        GeometryReader { geo in
                            let t = (context.date.timeIntervalSince(start) / 1.25).truncatingRemainder(dividingBy: 1)
                            let eased = t < 0.5 ? 2 * t * t : 1 - pow(2 - 2 * t, 2) / 2
                            LinearGradient(colors: [.clear, Theme.light.opacity(scheme == .dark ? 0.16 : 0.42), .white.opacity(scheme == .dark ? 0.06 : 0.5), Theme.light.opacity(scheme == .dark ? 0.16 : 0.42), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * 0.7)
                                .offset(x: geo.size.width * (1.9 * eased - 0.8))
                        }
                    }
                    .mask { content }
                    .allowsHitTesting(false)
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
