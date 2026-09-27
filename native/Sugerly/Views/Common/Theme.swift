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
}

enum Palette {
    static let bg = Color.dynamic(light: 0xFBF7F6, dark: 0x110A0F)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1A1117)
    static let surface2 = Color.dynamic(light: 0xF8F2F4, dark: 0x22171F)
    static let border = Color.dynamic(light: 0xEFE4E9, dark: 0x2D1F28)
    static let borderStrong = Color.dynamic(light: 0xE3D3DB, dark: 0x3B2934)
    static let text = Color.dynamic(light: 0x2A1620, dark: 0xF7EDF2)
    static let text2 = Color.dynamic(light: 0x6B5560, dark: 0xC2ADB8)
    static let muted = Color.dynamic(light: 0x9C8A93, dark: 0x86707C)
    static let danger = Color(hex: 0xE0526B)
    static let success = Color(hex: 0x17A673)
    static let warning = Color(hex: 0xF0A020)
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.35) : UIColor(hex: 0x2A1620, alpha: 0.07) })
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

enum Theme {
    // Set from your profile at the top of the app; the whole app redraws when it changes.
    nonisolated(unsafe) static var accent: Accent = .rose
    // App colours an admin picked for everyone (Admin → App colors), used
    // unless you chose your own accent in Settings.
    nonisolated(unsafe) static var custom: (main: UInt32, light: UInt32)?
    static var main: Color { custom.map { Color(hex: $0.main) } ?? accent.main }
    static var light: Color { custom.map { Color(hex: $0.light) } ?? accent.light }
    static var pink: Color { main }
    static var rose: Color { main }
    static var soft: Color { main.opacity(0.1) }
    static var gradient: LinearGradient { LinearGradient(colors: [light, main], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static let lavender = Color(hex: 0xB19CFF)
    static let background = Palette.bg
    static let card = Palette.surface
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

struct SugarCard: ViewModifier {
    var radius: CGFloat = 24
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .shadow(color: Palette.shadow, radius: 12, y: 4)
    }
}

extension View {
    func sugarCard(radius: CGFloat = 24, padding: CGFloat = 0) -> some View { modifier(SugarCard(radius: radius, padding: padding)) }

    // Frosted pill used by the tab bar and floating buttons (real Liquid Glass on iOS 26).
    @ViewBuilder
    func glassPill(cornerRadius: CGFloat = 30) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: Palette.shadow, radius: 16, y: 8)
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: Palette.shadow, radius: 16, y: 8)
        #endif
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
        configuration.label
            .font(.jakarta(15, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(Theme.gradient, in: Capsule())
            .shadow(color: Theme.pink.opacity(0.3), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.pink.opacity(0.25), lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
                    Capsule().fill(Theme.gradient).shadow(color: Theme.pink.opacity(0.3), radius: 8, y: 4)
                } else {
                    Capsule().fill(Palette.surface).overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.pink)
                .frame(width: 34, height: 34)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.display(22)).foregroundStyle(Palette.text)
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) { Text("See all"); Image(systemName: "arrow.right") }
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(Theme.pink)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
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

// Tiny logo with a soft shine, like the website's top bar.
struct BrandLogo: View {
    var height: CGFloat = 34
    @State private var shine = false
    var body: some View {
        Image(Theme.accent.logo)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .overlay {
                LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: height * 0.9)
                    .rotationEffect(.degrees(18))
                    .offset(x: shine ? height * 3 : -height * 3)
                    .mask(Image(Theme.accent.logo).resizable().scaledToFit())
                    .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).delay(1).repeatForever(autoreverses: false)) { shine = true }
            }
            .accessibilityLabel("Sugerly")
    }
}

// Colourful confetti for rewards.
struct ConfettiView: View {
    @State private var fall = false
    private let pieces = (0..<36).map { _ in (x: Double.random(in: -160...160), delay: Double.random(in: 0...0.25), rot: Double.random(in: 0...360), color: [Color(hex: 0xFF7AA2), Color(hex: 0xB19CFF), Color(hex: 0xFFD166), Color(hex: 0x5FD3B0), Color(hex: 0x7CBEFF)].randomElement()!) }
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
