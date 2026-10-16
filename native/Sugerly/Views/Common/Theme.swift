import SwiftUI
import UIKit

// Sugerly's look: a warm paper white (or soft charcoal in dark mode), flat
// cards with a thin edge, one solid accent colour used sparingly, and the
// iPhone's own fonts. Calm on purpose, so people's posts, art and reels are
// what stand out.

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
    // Neutral paper and ink: no tint, so the accent and people's pictures
    // carry the colour.
    static let bg = Color.dynamic(light: 0xF6F5F2, dark: 0x111111)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let surface2 = Color.dynamic(light: 0xEFEEEA, dark: 0x242424)
    static let border = Color.dynamic(light: 0xE5E3DE, dark: 0x2C2C2C)
    static let borderStrong = Color.dynamic(light: 0xD3D0C9, dark: 0x3A3A3A)
    static let text = Color.dynamic(light: 0x191817, dark: 0xF2F1EE)
    static let text2 = Color.dynamic(light: 0x55524D, dark: 0xB4B0A9)
    static let muted = Color.dynamic(light: 0x8A867F, dark: 0x85817B)
    static let danger = Color(hex: 0xD64545)
    static let success = Color(hex: 0x1F9D6B)
    static let warning = Color(hex: 0xD98B1C)
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.4) : UIColor.black.withAlphaComponent(0.05) })
}

// The five accent colours you can pick in Settings (the logo follows along).
enum Accent: String, CaseIterable, Identifiable {
    case rose, lavender, mint, peach, sky
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    private var rgb: (UInt32, UInt32) {
        switch self {
        case .rose: return (0xC94C73, 0xE8A3B9)
        case .lavender: return (0x6A55D6, 0xAFA3EE)
        case .mint: return (0x158765, 0x7CC7AF)
        case .peach: return (0xD7643A, 0xF0AC8E)
        case .sky: return (0x2A6FCC, 0x8DB9EC)
        }
    }
    var main: Color { Color(hex: rgb.0) }
    var light: Color { Color(hex: rgb.1) }
    // Solid: the old two-tone gradients everywhere looked machine-made.
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
    static var light: Color { custom.map { Color(hex: $0.light) } ?? accent.light }
    static var pink: Color { main }
    static var rose: Color { main }
    static var soft: Color { main.opacity(0.1) }
    // One solid colour. (Every place that used the accent gradient now gets
    // a calm, flat fill without having to change.)
    static var gradient: LinearGradient { LinearGradient(colors: [main, main], startPoint: .top, endPoint: .bottom) }
    static let lavender = Color(hex: 0x8E83C9)
    static let background = Palette.bg
    static let card = Palette.surface
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
    /// The top bars' titles: the iPhone's own letters (no longer rounded).
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight == .heavy || weight == .black ? .bold : weight)
    }
}

extension Font {
    // Headings: the iPhone's own letters, bold (not the round extra-heavy
    // ones), a little smaller than asked so titles feel calm. Grows with the
    // text size picked in iPhone Settings.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size * 0.86), weight: .bold)
    }
    // The odd warm accent (a name in the greeting, an empty page): a serif
    // instead of the old brush lettering. (The brush font ran large, so the
    // serif is drawn smaller.)
    static func cute(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size * 0.74), weight: .semibold, design: .serif)
    }
    // Everything else: the iPhone's own text font. (The name stays so no
    // page has to change.) Bold asks come out one step lighter: the old font
    // was thin, so pages had asked for heavy weights everywhere.
    static func jakarta(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let calmer: Font.Weight
        switch weight {
        case .black, .heavy: calmer = .bold
        case .bold: calmer = .semibold
        default: calmer = weight
        }
        return .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size), weight: calmer)
    }
}

// MARK: - Building blocks

// A flat card: plain surface, a thin edge and barely any shadow. Big
// corners come out a little tighter than asked for (the old pages asked for
// very round, bubbly cards).
struct SugarCard: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.calm(radius), style: .continuous)
        // The shadow belongs to the card's shape only (not everything inside
        // it), so long cards scroll smoothly.
        content
            .padding(padding)
            .background {
                shape.fill(Palette.surface)
                    .shadow(color: scheme == .dark ? .clear : Palette.shadow, radius: 2, y: 1)
            }
            .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
    }

    // Big radii come down a bit; small ones stay as they are.
    static func calm(_ radius: CGFloat) -> CGFloat {
        radius <= 14 ? radius : 14 + (radius - 14) * 0.35
    }
}

extension View {
    func sugarCard(radius: CGFloat = 16, padding: CGFloat = 0) -> some View { modifier(SugarCard(radius: radius, padding: padding)) }

    // Floating bits (the music player): a plain surface with a thin edge and
    // a soft shadow so it reads above the page.
    func glassPill(cornerRadius: CGFloat = 30) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background { shape.fill(Palette.surface).shadow(color: .black.opacity(0.1), radius: 12, y: 4) }
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
    }

    // Text in the accent colour.
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

// The main button: one solid accent colour, gently rounded, no gloss or
// glow. Pressing dims it a touch.
private struct GradientButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    let fullWidth: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        JellyPress(content: styled, pressed: configuration.isPressed, scale: 0.98, fade: true)
    }

    private var styled: some View {
        let shape = RoundedRectangle(cornerRadius: min(height / 2, 13), style: .continuous)
        return configuration.label
            .font(.jakarta(16, .semibold))
            .foregroundStyle(.white)
            // Buttons stay on one line (shrinking a little if they must)
            // instead of wrapping into a lopsided two-line blob.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(shape.fill(Theme.main))
            .contentShape(shape)
            .saturation(enabled ? 1 : 0)
            .opacity(enabled ? 1 : 0.45)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(height / 2, 12), style: .continuous)
        let styled = configuration.label
            .font(.jakarta(15, .semibold))
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(configuration.isPressed ? Palette.surface2 : Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.borderStrong, lineWidth: 1))
            .contentShape(shape)
        return JellyPress(content: styled, pressed: configuration.isPressed, scale: 0.98)
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
            // The picked one is ink on paper turned around; the rest are quiet.
            .foregroundStyle(active ? Palette.bg : Palette.text2)
            .background {
                if active {
                    Capsule().fill(Palette.text)
                } else {
                    Capsule().fill(Palette.surface).overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SoftPressStyle())
        .sensoryFeedback(.selection, trigger: active)
        .motion(Motion.standard, value: active)
    }
}

// Section title and an optional "See all". Just the words (the icon the
// pages pass in isn't drawn any more), so the content is what stands out.
struct SectionHeader: View {
    let icon: String
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title).font(.display(22)).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) { Text("See all"); Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                        .font(.jakarta(14, .medium))
                        .foregroundStyle(Palette.text2)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
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
                    Capsule().fill(Theme.main).frame(width: max(6, geo.size.width * shown))
                }
            }
            .frame(height: 6)
        }
        .onAppear { updateProgress() }
        .onChange(of: info.progress) { _, _ in updateProgress() }
    }

    private func updateProgress() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { shown = info.progress }
    }
}

// The logo, still.
struct BrandLogo: View {
    var height: CGFloat = 34

    var body: some View {
        Image(Theme.logoName).resizable().scaledToFit().frame(height: height).tintShift(Theme.tint)
            .accessibilityLabel("Sugerly")
    }
}

// The app icon in your colour, still, with a soft shadow.
struct AppBadge: View {
    var size: CGFloat = 120

    private var art: String {
        let accent = Theme.custom.map { AppIconSync.nearest($0.main) } ?? Theme.accent
        return "IconBadge-\(accent.rawValue)"
    }

    var body: some View {
        Image(art).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.03)
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

// Rewards used to burst into sparkles. Not any more (it read as noise);
// this stays so the places that showed it keep working.
struct SparkleBurst: View {
    var radius: CGFloat = 80
    var body: some View { EmptyView() }
}

// MARK: - Loading placeholders

// A soft light sweeping across a placeholder, like the website's .skeleton.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // With Reduce Motion on, the placeholder stays still.
        if reduceMotion { content } else { sweeping(content) }
    }

    private func sweeping(_ content: Content) -> some View {
        content.overlay {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: -geo.size.width * 0.6 + CGFloat(t) * geo.size.width * 1.6)
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .clipped()
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

// Greetings and empty pages used to have little sparkles next to them.
// Gone (too decorative); this stays so those pages keep working.
struct Twinkle: View {
    var size: CGFloat = 16
    var body: some View { EmptyView() }
}
