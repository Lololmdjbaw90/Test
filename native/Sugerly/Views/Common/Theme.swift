import SwiftUI
import UIKit

// Sugerly's look, matching the website: warm off-white (or deep plum in dark
// mode), soft cards, the accent gradient, and the Bubbly / Cute Here /
// Plus Jakarta Sans fonts.

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
    // Blush pink background, candy-floss borders.
    static let bg = Color.dynamic(light: 0xFFF3F7, dark: 0x140A11)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1D1019)
    static let surface2 = Color.dynamic(light: 0xFFEAF1, dark: 0x271621)
    static let border = Color.dynamic(light: 0xF8D9E4, dark: 0x351F2C)
    static let borderStrong = Color.dynamic(light: 0xF0C3D3, dark: 0x45293A)
    static let text = Color.dynamic(light: 0x2A1620, dark: 0xF7EDF2)
    static let text2 = Color.dynamic(light: 0x6B5560, dark: 0xC2ADB8)
    static let muted = Color.dynamic(light: 0x9C8A93, dark: 0x86707C)
    static let danger = Color(hex: 0xE0526B)
    static let success = Color(hex: 0x17A673)
    static let warning = Color(hex: 0xF0A020)
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.35) : UIColor(hex: 0xC2476F, alpha: 0.10) })
}

// The five accent colours you can pick in Settings (the logo follows along).
enum Accent: String, CaseIterable, Identifiable {
    case rose, lavender, mint, peach, sky
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    private var rgb: (UInt32, UInt32) {
        switch self {
        case .rose: return (0xD9577F, 0xEE8FAE)
        case .lavender: return (0x7C5CF0, 0xB19CFF)
        case .mint: return (0x16A37F, 0x5FD3B0)
        case .peach: return (0xEE6E40, 0xFFAA80)
        case .sky: return (0x2F80E0, 0x7CBEFF)
        }
    }
    var main: Color { Color(hex: rgb.0) }
    var light: Color { Color(hex: rgb.1) }
    var gradient: LinearGradient { LinearGradient(colors: [light, main], startPoint: .topLeading, endPoint: .bottomTrailing) }
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
    static var gradient: LinearGradient { LinearGradient(colors: [light, main], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static let lavender = Color(hex: 0xB19CFF)
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

extension Font {
    // Bubbly: big friendly headings (like the website's font-display).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Bubbly-Regular", size: size, relativeTo: style)
    }
    // Cute Here: playful accents (names in the greeting, empty states).
    static func cute(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("CuteHereRegular", size: size, relativeTo: style)
    }
    // Plus Jakarta Sans: everything else.
    static func jakarta(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .medium: name = "PlusJakartaSans-Medium"
        case .semibold: name = "PlusJakartaSans-SemiBold"
        case .bold: name = "PlusJakartaSans-Bold"
        case .heavy, .black: name = "PlusJakartaSans-ExtraBold"
        default: name = "PlusJakartaSans-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

// MARK: - Building blocks

// White card with a soft pink-tinted edge, a light top highlight and a
// layered shadow — the website's .card.
struct SugarCard: ViewModifier {
    var radius: CGFloat = 24
    var padding: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // The shadow belongs to the card's shape only (not everything inside
        // it), so long cards scroll smoothly.
        content
            .padding(padding)
            .background {
                shape.fill(Palette.surface)
                    .shadow(color: Palette.shadow, radius: 2, y: 1)
                    .shadow(color: Theme.main.opacity(scheme == .dark ? 0.0 : 0.06), radius: 18, y: 8)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.08 : 0.9), Palette.border], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
    }
}

extension View {
    func sugarCard(radius: CGFloat = 24, padding: CGFloat = 0) -> some View { modifier(SugarCard(radius: radius, padding: padding)) }

    // Frosted pink pill for floating bits (music player): soft blur with a
    // blush tint and a candy border — cute rather than Apple's liquid glass.
    func glassPill(cornerRadius: CGFloat = 30) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background { shape.fill(Palette.surface).shadow(color: Theme.main.opacity(0.2), radius: 16, y: 8) }
            .overlay(shape.strokeBorder(Theme.light.opacity(0.55), lineWidth: 1.2))
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

// Candy button: accent gradient, glossy top edge, coloured glow, squish.
private struct GradientButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    let fullWidth: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.jakarta(15, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background {
                Capsule().fill(Theme.gradient)
                    .overlay {
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                            .padding(1.5)
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
            .shadow(color: Theme.main.opacity(configuration.isPressed ? 0.2 : 0.38), radius: configuration.isPressed ? 6 : 14, y: configuration.isPressed ? 3 : 7)
            .saturation(enabled ? 1 : 0.2)
            .opacity(enabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .clickSound(configuration.isPressed)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jakarta(14, .bold))
            .foregroundStyle(Theme.pink)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(configuration.isPressed ? Theme.soft : Color.clear, in: Capsule())
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.pink.opacity(0.3), lineWidth: 1.4))
            .shadow(color: Palette.shadow, radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .clickSound(configuration.isPressed)
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
            .padding(.horizontal, 16)
            .frame(height: 40)
            .foregroundStyle(active ? .white : Palette.text2)
            .background {
                if active {
                    Capsule().fill(Theme.gradient)
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)).padding(1))
                        .shadow(color: Theme.pink.opacity(0.35), radius: 8, y: 4)
                } else {
                    Capsule().fill(Palette.surface).overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.92))
        .sensoryFeedback(.selection, trigger: active)
        .animation(.snappy(duration: 0.25), value: active)
    }
}

// Section title with an icon tile and an optional "See all".
struct SectionHeader: View {
    let icon: String
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(color: Theme.main.opacity(0.3), radius: 6, y: 3)
            Text(title).font(.display(22)).foregroundStyle(Palette.text)
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 4) { Text("See all"); Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)) }
                        .font(.jakarta(12, .bold))
                        .foregroundStyle(Theme.main)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Theme.soft, in: Capsule())
                }
                .buttonStyle(BouncyStyle())
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
                    Capsule().fill(Palette.border)
                    Capsule().fill(Theme.gradient).frame(width: max(8, geo.size.width * shown))
                }
            }
            .frame(height: 8)
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.2)) { shown = info.progress } }
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
        let unit = size / 1024
        ZStack(alignment: .topLeading) {
            Image(art).resizable().interpolation(.high).scaledToFit()
            ForEach(sparkles.indices, id: \.self) { i in
                let s = sparkles[i]
                FourPointStar()
                    .fill(.white)
                    .frame(width: s.2 * unit, height: s.2 * unit)
                    // They twinkle and turn in place (no drifting up and down).
                    .phaseAnimator(reduceMotion ? [1.0] : [0.55, 1.0, 0.8]) { view, phase in
                        view
                            .scaleEffect(phase)
                            .rotationEffect(.degrees(phase * 90))
                            .opacity(0.55 + phase * 0.45)
                    } animation: { _ in .easeInOut(duration: 1.1 + Double(i) * 0.25).delay(s.3 * 0.3) }
                    .position(x: s.0 * unit, y: s.1 * unit)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: Theme.main.opacity(0.35), radius: size * 0.12, y: size * 0.05)
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

// Colourful confetti for rewards.
struct ConfettiView: View {
    @State private var fall = false
    // Picked once: before, every redraw of the screen around it (like the
    // coins counting up) gave the pieces new spots, so they jumped about.
    @State private var pieces = (0..<36).map { _ in (x: Double.random(in: -160...160), delay: Double.random(in: 0...0.25), rot: Double.random(in: 0...360), color: [Color(hex: 0xFF7AA2), Color(hex: 0xB19CFF), Color(hex: 0xFFD166), Color(hex: 0x5FD3B0), Color(hex: 0x7CBEFF)].randomElement()!) }
    var body: some View {
        ZStack {
            ForEach(0..<pieces.count, id: \.self) { i in
                let p = pieces[i]
                RoundedRectangle(cornerRadius: 2)
                    .fill(p.color)
                    .frame(width: 7, height: 11)
                    .rotationEffect(.degrees(fall ? p.rot + 540 : p.rot))
                    .offset(x: fall ? p.x : p.x * 0.2, y: fall ? 260 : -30)
                    .opacity(fall ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).delay(p.delay), value: fall)
            }
        }
        .allowsHitTesting(false)
        .onAppear { fall = true }
    }
}

// A burst of sparkles flying out and twinkling away (for rewards). Their
// spots are picked once, so they never jump when the screen updates.
struct SparkleBurst: View {
    var radius: CGFloat = 130
    struct Piece { var dx: CGFloat; var dy: CGFloat; var distance: CGFloat; var size: CGFloat; var delay: Double; var white: Bool }
    @State private var pieces: [Piece] = (0..<16).map { i in
        // Fanned out above and to the sides only, so they never cover the
        // text underneath.
        let angle: Double = -Double.pi * (0.08 + 0.84 * Double(i) / 15) + Double.random(in: -0.06...0.06)
        let x: Double = cos(angle)
        let y: Double = sin(angle)
        return Piece(dx: CGFloat(x), dy: CGFloat(y), distance: CGFloat.random(in: 0.55...1.0),
                     size: CGFloat.random(in: 12...26), delay: Double.random(in: 0...0.18), white: i % 3 == 0)
    }
    @State private var go = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(pieces.indices, id: \.self) { i in
                let p = pieces[i]
                FourPointStar()
                    .fill(p.white ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.gradient))
                    .frame(width: p.size, height: p.size)
                    .shadow(color: .white.opacity(0.9), radius: 3)
                    .phaseAnimator([0, 1, 2], trigger: go) { view, phase in
                        let reach: CGFloat = phase == 0 ? 0 : radius * p.distance * (phase == 2 ? 1.15 : 1)
                        return view
                            .scaleEffect(phase == 1 ? 1 : 0.3)
                            .rotationEffect(.degrees(phase == 0 ? 0 : phase == 1 ? 45 : 110))
                            .opacity(phase == 1 ? 1 : 0)
                            .offset(x: p.dx * reach, y: p.dy * reach)
                    } animation: { phase in
                        switch phase {
                        case 1: return .spring(response: 0.45, dampingFraction: 0.6).delay(p.delay)
                        case 2: return .easeIn(duration: 0.8).delay(0.35)
                        default: return .linear(duration: 0.01)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .onAppear { if !reduceMotion { go.toggle() } }
    }
}

// MARK: - Loading placeholders

// A soft light sweeping across a placeholder, like the website's .skeleton.
struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
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

    // Sections float up one after another when a page opens.
    func stagger(_ shown: Bool, _ index: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(Double(min(index, 10)) * 0.05), value: shown)
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

// Little sparkles that twinkle in turn (for greetings and empty states).
// All three stay inside their own little box, so they never sit on top of
// the text next to them; they twinkle and turn in place.
struct Twinkle: View {
    var size: CGFloat = 16
    var body: some View {
        ZStack(alignment: .topLeading) {
            sparkle(size, x: size * 0.45, y: 0, delay: 0)
            sparkle(size * 0.6, x: size * 1.45, y: size * 0.75, delay: 0.4)
            sparkle(size * 0.45, x: 0, y: size * 1.15, delay: 0.8)
        }
        .frame(width: size * 2.1, height: size * 1.65, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sparkle(_ s: CGFloat, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: s, weight: .bold))
            .foregroundStyle(Theme.gradient)
            .frame(width: s, height: s)
            .phaseAnimator([0.35, 1.0]) { view, phase in
                view.scaleEffect(phase).opacity(phase).rotationEffect(.degrees(phase * 45))
            } animation: { _ in .easeInOut(duration: 0.9).delay(delay) }
            .offset(x: x, y: y)
    }
}
