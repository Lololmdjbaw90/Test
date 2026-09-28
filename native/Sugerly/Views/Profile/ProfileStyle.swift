import SwiftUI
import UIKit

// MARK: - Name styles (same ids as the website's NameStylePicker)

enum NameStyles {
    struct Style: Identifiable, Hashable {
        let id: String
        let label: String
        var premium = false
    }

    static let all: [Style] = [
        Style(id: "default", label: "Classic"),
        Style(id: "glow-pink", label: "Pink glow"),
        Style(id: "glow-purple", label: "Violet glow"),
        Style(id: "italic-serif", label: "Editorial"),
        Style(id: "bold-serif", label: "Rose serif"),
        Style(id: "glow-mint", label: "Mint glow"),
        Style(id: "glow-sky", label: "Sky glow"),
        Style(id: "cute", label: "Cute"),
        Style(id: "pop", label: "Pop shadow"),
        Style(id: "glow-gold", label: "Gold", premium: true),
        Style(id: "aurora", label: "Aurora", premium: true),
        Style(id: "neon", label: "Neon", premium: true),
        Style(id: "rainbow", label: "Rainbow", premium: true),
        Style(id: "sunset", label: "Sunset", premium: true),
    ]

    static func isPremium(_ id: String) -> Bool { all.first { $0.id == id }?.premium ?? false }
}

// A name drawn in the person's chosen style. Premium styles only show while
// their Nitro is active (like the website).
struct NameText: View {
    let name: String
    var style = ""
    var size: CGFloat = 15
    var display = false
    var nitro = true
    var color: Color = Palette.text
    // Their chosen name colour (hex), used by the plain styles.
    var tint = ""

    private var own: Color { ProfileColors.color(tint) ?? color }

    private var active: String {
        let s = style.isEmpty ? "default" : style
        return NameStyles.isPremium(s) && !nitro ? "default" : s
    }

    var body: some View {
        switch active {
        case "glow-pink":
            base.foregroundStyle(Color(hex: 0xE86D98)).shadow(color: Color(hex: 0xE86D98).opacity(0.6), radius: size * 0.3)
        case "glow-purple":
            base.foregroundStyle(Color(hex: 0xA67CF7)).shadow(color: Color(hex: 0xA67CF7).opacity(0.6), radius: size * 0.3)
        case "italic-serif":
            Text(name).font(.system(size: size, weight: .semibold, design: .serif)).italic().foregroundStyle(own)
        case "glow-mint":
            base.foregroundStyle(Color(hex: 0x2FAF8F)).shadow(color: Color(hex: 0x3FD1AB).opacity(0.6), radius: size * 0.3)
        case "glow-sky":
            base.foregroundStyle(Color(hex: 0x4A9BE8)).shadow(color: Color(hex: 0x7CBEFF).opacity(0.65), radius: size * 0.3)
        case "cute":
            Text(name).font(.cute(size * 1.1)).foregroundStyle(ProfileColors.color(tint) ?? Theme.main)
        case "pop":
            base.foregroundStyle(own).shadow(color: (ProfileColors.color(tint) ?? Theme.main).opacity(0.45), radius: 0, x: 2, y: 2)
        case "rainbow":
            base.foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF7AA2), Color(hex: 0xFFB38A), Color(hex: 0xFFD166), Color(hex: 0x5EC8B8), Color(hex: 0x7CBEFF), Color(hex: 0xB19CFF)], startPoint: .leading, endPoint: .trailing))
        case "sunset":
            base.foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF8A5C), Color(hex: 0xF25F8C), Color(hex: 0xA65CF2)], startPoint: .leading, endPoint: .trailing))
                .shadow(color: Color(hex: 0xF25F8C).opacity(0.35), radius: size * 0.2)
        case "bold-serif":
            Text(name).font(.system(size: size, weight: .heavy, design: .serif)).foregroundStyle(Theme.main)
        case "glow-gold":
            base.foregroundStyle(LinearGradient(colors: [Color(hex: 0xF5C04A), Color(hex: 0xE6A31C)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: 0xF0A020).opacity(0.55), radius: size * 0.32)
        case "aurora":
            AuroraName(text: base)
        case "neon":
            base.foregroundStyle(.white)
                .shadow(color: .white.opacity(0.9), radius: 1)
                .shadow(color: Color(hex: 0xEE8FAE), radius: size * 0.25)
                .shadow(color: Color(hex: 0xD9577F), radius: size * 0.5)
        default:
            base.foregroundStyle(own)
        }
    }

    private var base: Text {
        Text(name).font(display ? .display(size) : .jakarta(size, .bold))
    }
}

// Slowly sliding pink → lilac → sky gradient text.
private struct AuroraName: View {
    let text: Text
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 5) / 5)
            text.foregroundStyle(LinearGradient(
                colors: [Color(hex: 0xEE8FAE), Color(hex: 0xB19CFF), Color(hex: 0x7CBEFF), Color(hex: 0xEE8FAE), Color(hex: 0xB19CFF)],
                startPoint: UnitPoint(x: -phase, y: 0.5), endPoint: UnitPoint(x: 2 - phase, y: 0.5)))
        }
    }
}

struct NitroBadge: View {
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: compact ? 9 : 11, weight: .heavy))
            if !compact { Text("Nitro").font(.jakarta(12, .heavy)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 5 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(NitroStyle.gradient, in: Capsule())
        .shadow(color: Color(hex: 0x8B5CF6).opacity(0.35), radius: 6, y: 2)
        .accessibilityLabel("Nitro")
    }
}

enum NitroStyle {
    static let gradient = LinearGradient(colors: [Color(hex: 0x8B5CF6), Color(hex: 0xC084FC), Color(hex: 0xEE8FAE)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cost = 800
    static let xpBoostCost = 150
}

// MARK: - Profile colours + effects

enum ProfileColors {
    static let swatches: [(String, UInt32)] = [
        ("#ee8fae", 0xEE8FAE), ("#d9577f", 0xD9577F), ("#b19cff", 0xB19CFF), ("#8b5cf6", 0x8B5CF6),
        ("#7cbeff", 0x7CBEFF), ("#5ec8b8", 0x5EC8B8), ("#ffb38a", 0xFFB38A), ("#ffd166", 0xFFD166),
        ("#f472b6", 0xF472B6), ("#64748b", 0x64748B),
    ]

    static func color(_ hex: String) -> Color? { SiteTheme.hex(hex).map { Color(hex: $0) } }
}

struct ProfileEffect: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String

    static let all: [ProfileEffect] = [
        ProfileEffect(id: "", label: "None", icon: "circle.slash"),
        ProfileEffect(id: "sparkles", label: "Sparkles", icon: "sparkle"),
        ProfileEffect(id: "hearts", label: "Hearts", icon: "heart.fill"),
        ProfileEffect(id: "snow", label: "Snow", icon: "snowflake"),
        ProfileEffect(id: "stars", label: "Stars", icon: "star.fill"),
        ProfileEffect(id: "bubbles", label: "Bubbles", icon: "circle.fill"),
        ProfileEffect(id: "petals", label: "Petals", icon: "camera.macro"),
        ProfileEffect(id: "paws", label: "Paws", icon: "pawprint.fill"),
        ProfileEffect(id: "notes", label: "Music", icon: "music.note"),
        ProfileEffect(id: "moons", label: "Moons", icon: "moon.fill"),
        ProfileEffect(id: "leaves", label: "Leaves", icon: "leaf.fill"),
        ProfileEffect(id: "bolts", label: "Zaps", icon: "bolt.fill"),
        ProfileEffect(id: "clouds", label: "Clouds", icon: "cloud.fill"),
    ]

    // How many float at once: few, some or lots.
    static let amounts: [(Int, String)] = [(8, "Few"), (16, "Some"), (28, "Lots")]
}

// Little shapes floating up through a banner. They stay inside it (clipped).
struct ProfileEffectLayer: View {
    let effect: String
    var color = ""
    var amount = 0

    private var icon: String { ProfileEffect.all.first { $0.id == effect }?.icon ?? "sparkle" }
    private var count: Int { amount > 0 ? min(40, amount) : 16 }
    private var tint: Color {
        if let chosen = ProfileColors.color(color) { return chosen }
        switch effect {
        case "snow": return .white
        case "stars": return Color(hex: 0xFFE08A)
        case "bubbles": return .white.opacity(0.7)
        default: return .white
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                guard let symbol = context.resolveSymbol(id: 0) else { return }
                let n = count
                for i in 0..<n {
                    let seed = Double(i) * 12.9898
                    let rx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let speed = 0.05 + abs(rx) * 0.06
                    let phase = (Double(i) * 0.137).truncatingRemainder(dividingBy: 1)
                    let p = (t * speed + phase).truncatingRemainder(dividingBy: 1)
                    let fall = effect == "snow"
                    let y = fall ? p * (size.height + 30) - 15 : (1 - p) * (size.height + 30) - 15
                    let x = (Double(i) + 0.5) / Double(n) * size.width + sin(t * 1.3 + seed) * 10
                    let scale = 0.55 + abs(rx) * 0.7
                    let alpha = min(1, min(p, 1 - p) * 5) * 0.85
                    var c = context
                    c.opacity = alpha
                    c.translateBy(x: x, y: y)
                    c.scaleBy(x: scale, y: scale)
                    c.rotate(by: .degrees(sin(t + seed) * 20))
                    c.draw(symbol, at: .zero)
                }
            } symbols: {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                    .shadow(color: .black.opacity(0.12), radius: 2)
                    .tag(0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Picture frames + banner patterns

struct AvatarFrame: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    var premium = false

    static let all: [AvatarFrame] = [
        AvatarFrame(id: "", label: "Classic", icon: "circle"),
        AvatarFrame(id: "solid", label: "Colour ring", icon: "circle.circle"),
        AvatarFrame(id: "double", label: "Double", icon: "circle.circle.fill"),
        AvatarFrame(id: "dashed", label: "Stitched", icon: "circle.dashed"),
        AvatarFrame(id: "glow", label: "Glow", icon: "sun.max"),
        AvatarFrame(id: "rainbow", label: "Rainbow", icon: "rainbow", premium: true),
        AvatarFrame(id: "hearts", label: "Hearts", icon: "heart.circle", premium: true),
        AvatarFrame(id: "stars", label: "Stars", icon: "star.circle", premium: true),
    ]

    static func isPremium(_ id: String) -> Bool { all.first { $0.id == id }?.premium ?? false }
}

// Drawn around a profile picture (pass the picture's size).
struct AvatarFrameView: View {
    let frame: String
    var color: Color = Theme.main
    var size: CGFloat = 104

    var body: some View {
        let d = size + 14
        ZStack {
            switch frame {
            case "solid":
                Circle().strokeBorder(color, lineWidth: 4)
            case "double":
                Circle().strokeBorder(color, lineWidth: 3)
                Circle().strokeBorder(color.opacity(0.45), lineWidth: 2).padding(-6)
            case "dashed":
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            case "glow":
                Circle().strokeBorder(color.opacity(0.9), lineWidth: 3).shadow(color: color.opacity(0.8), radius: 10)
            case "rainbow":
                Circle().strokeBorder(AngularGradient(colors: [Color(hex: 0xFF7AA2), Color(hex: 0xFFD166), Color(hex: 0x5EC8B8), Color(hex: 0x7CBEFF), Color(hex: 0xB19CFF), Color(hex: 0xFF7AA2)], center: .center), lineWidth: 5)
            case "hearts", "stars":
                Circle().strokeBorder(color.opacity(0.35), lineWidth: 2)
                ForEach(0..<10, id: \.self) { i in
                    Image(systemName: frame == "hearts" ? "heart.fill" : "star.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                        .frame(width: d, height: d, alignment: .top)
                        .rotationEffect(.degrees(Double(i) * 36))
                }
            default:
                EmptyView()
            }
        }
        .frame(width: d, height: d)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BannerPattern: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String

    static let all: [BannerPattern] = [
        BannerPattern(id: "", label: "Plain", icon: "square"),
        BannerPattern(id: "dots", label: "Dots", icon: "circle.grid.3x3.fill"),
        BannerPattern(id: "stripes", label: "Stripes", icon: "line.diagonal"),
        BannerPattern(id: "checks", label: "Checks", icon: "checkerboard.rectangle"),
        BannerPattern(id: "hearts", label: "Hearts", icon: "heart.fill"),
        BannerPattern(id: "stars", label: "Stars", icon: "star.fill"),
        BannerPattern(id: "waves", label: "Waves", icon: "water.waves"),
    ]
}

// A soft white pattern over a banner (drawn once, it doesn't move).
struct BannerPatternView: View {
    let pattern: String

    var body: some View {
        Canvas { ctx, size in
            let ink = GraphicsContext.Shading.color(.white.opacity(0.22))
            switch pattern {
            case "dots":
                var y: CGFloat = 10
                var row = 0
                while y < size.height + 20 {
                    var x: CGFloat = row % 2 == 0 ? 10 : 24
                    while x < size.width + 20 { ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: ink); x += 28 }
                    y += 24; row += 1
                }
            case "stripes":
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    ctx.stroke(p, with: ink, lineWidth: 10); x += 34
                }
            case "checks":
                let s: CGFloat = 22
                var y: CGFloat = 0
                var row = 0
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? 0 : s
                    while x < size.width { ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(0.14))); x += s * 2 }
                    y += s; row += 1
                }
            case "hearts", "stars":
                guard let symbol = ctx.resolveSymbol(id: 0) else { return }
                var y: CGFloat = 16
                var row = 0
                while y < size.height + 20 {
                    var x: CGFloat = row % 2 == 0 ? 16 : 40
                    while x < size.width + 20 { ctx.draw(symbol, at: CGPoint(x: x, y: y)); x += 48 }
                    y += 34; row += 1
                }
            case "waves":
                var y: CGFloat = 14
                while y < size.height + 20 {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x < size.width {
                        p.addQuadCurve(to: CGPoint(x: x + 20, y: y), control: CGPoint(x: x + 10, y: y - 8))
                        p.addQuadCurve(to: CGPoint(x: x + 40, y: y), control: CGPoint(x: x + 30, y: y + 8))
                        x += 40
                    }
                    ctx.stroke(p, with: ink, lineWidth: 3); y += 26
                }
            default:
                break
            }
        } symbols: {
            Image(systemName: pattern == "stars" ? "star.fill" : "heart.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.28)).tag(0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Nitro shop (a sheet, not a page)

struct NitroShopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busy: String?
    @State private var burst = 0
    @State private var wiggle = false

    private var coins: Int { model.me?.coins ?? 0 }
    private var nitro: Bool { model.me?.isNitro ?? false }

    private let perks: [(String, String)] = [
        ("photo.stack.fill", "GIF profile picture and banner"),
        ("textformat", "Premium name styles: Gold, Aurora, Neon"),
        ("circle.hexagongrid.fill", "Animated avatar ring and Nitro badge"),
        ("sparkles", "Profile effects: sparkles, hearts, snow"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    HStack(spacing: 12) {
                        balance
                        boost
                    }
                    earn
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .sugarBackground()
            .overlay { ConfettiBurst(trigger: burst).allowsHitTesting(false) }
            .navigationTitle("MimiNitro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                }
            }
        }
        .presentationCornerRadius(34)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .rotationEffect(.degrees(wiggle ? 6 : -6))
                    .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { wiggle = true } }
                VStack(alignment: .leading, spacing: 3) {
                    Text(nitro ? "MimiNitro is active" : "MimiNitro").font(.display(28)).foregroundStyle(.white)
                    Text(renewText).font(.jakarta(13, .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(perks.indices, id: \.self) { i in
                    Label(perks[i].1, systemImage: perks[i].0).font(.jakarta(13, .semibold)).foregroundStyle(.white)
                }
            }
            Button { buyNitro() } label: {
                HStack(spacing: 8) {
                    if busy == "nitro" { ProgressView().tint(Color(hex: 0x7C3AED)) } else {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("\(nitro ? "Extend" : "Get") · \(NitroStyle.cost) coins")
                    }
                }
                .font(.jakarta(15, .heavy))
                .foregroundStyle(Color(hex: 0x7C3AED))
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(.white, in: Capsule())
            }
            .buttonStyle(BouncyStyle())
            .disabled(busy != nil)
        }
        .padding(20)
        .background {
            ZStack {
                NitroStyle.gradient
                Circle().fill(.white.opacity(0.22)).frame(width: 220).blur(radius: 40).offset(x: 140, y: -90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color(hex: 0x8B5CF6).opacity(0.3), radius: 20, y: 10)
    }

    private var renewText: String {
        if nitro, let until = Dates.parse(model.me?.nitroUntil ?? "") {
            return "Active until \(until.formatted(date: .abbreviated, time: .omitted))"
        }
        return "30 days of premium perks, paid with coins"
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "dollarsign.circle.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xF0A020)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("\(coins)").font(.display(26)).foregroundStyle(Palette.text).monospacedDigit().contentTransition(.numericText())
            Text("MimiCoins").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 24, padding: 16)
    }

    private var boost: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("XP boost").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
            Button { buy("xp", NitroStyle.xpBoostCost, ["xp": (model.me?.xp ?? 0) + 100], "+100 XP") } label: {
                if busy == "xp" { ProgressView() } else { Text("+100 XP · \(NitroStyle.xpBoostCost)") }
            }
            .buttonStyle(OutlineButtonStyle(fullWidth: true))
            .disabled(busy != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 24, padding: 16)
    }

    private var earn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to earn coins").font(.jakarta(12, .heavy)).tracking(0.8).foregroundStyle(Palette.muted)
            ForEach(earnRows.indices, id: \.self) { i in
                let row = earnRows[i]
                HStack(spacing: 12) {
                    Image(systemName: row.0).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.main)
                        .frame(width: 36, height: 36).background(Theme.soft, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.1).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                        Text(row.2).font(.jakarta(12)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 24, padding: 16)
    }

    private let earnRows: [(String, String, String)] = [
        ("gift.fill", "Daily reward", "25–55 coins, bigger with streaks"),
        ("square.and.pencil", "Post to Community", "+5 coins per post"),
        ("checkmark.seal.fill", "Finish onboarding", "+50 coins once"),
    ]

    private func buyNitro() {
        let now = Date()
        let from = (model.me?.isNitro ?? false) ? (Dates.parse(model.me?.nitroUntil ?? "") ?? now) : now
        let until = Dates.iso(from.addingTimeInterval(30 * 86400))
        buy("nitro", NitroStyle.cost, ["nitro_active": true, "nitro_until": until], nitro ? "Nitro extended by 30 days" : "Welcome to MimiNitro")
    }

    private func buy(_ id: String, _ cost: Int, _ patch: Doc, _ message: String) {
        guard coins >= cost else {
            model.showToast("You need \(cost - coins) more coins", icon: "dollarsign.circle", error: true)
            return
        }
        busy = id
        Task {
            var fields = patch
            fields["coins"] = coins - cost
            do {
                try await model.updateMe(fields)
                burst += 1
                model.showToast(message, icon: "sparkles")
            } catch {
                model.showToast(error.localizedDescription, icon: "exclamationmark.triangle", error: true)
            }
            busy = nil
        }
    }
}

// Candy confetti that falls once each time `trigger` changes.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < 2.2 else { return }
                let colors: [Color] = [Color(hex: 0xEE8FAE), Color(hex: 0xB19CFF), Color(hex: 0x7CBEFF), Color(hex: 0xFFD166), Color(hex: 0x5EC8B8)]
                for i in 0..<60 {
                    let seed = Double(i) * 78.233
                    let r = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.5 + (r - 0.5) * 0.3) + cos(seed) * 260 * t
                    let y = size.height * 0.25 - (220 + r * 200) * t + 520 * t * t
                    var c = context
                    c.opacity = max(0, 1 - t / 2.2)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * (4 + r * 6)))
                    let rect = CGRect(x: -4, y: -6, width: 8, height: 12)
                    c.fill(i % 3 == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[i % colors.count]))
                }
            }
        }
        .task(id: trigger) {
            guard trigger > 0 else { return }
            start = Date()
            try? await Task.sleep(for: .seconds(2.3))
            start = nil
        }
    }
}

// MARK: - Cropping

// Pinch and drag a picture inside a circle (profile picture) or a wide
// frame (banner). Returns the chosen part as a 0…1 rectangle of the picture.
// Shapes you can pick when cropping in the editors.
struct CropAspect: Identifiable, Hashable {
    let label: String
    let ratio: CGFloat   // width / height; 0 = the picture's own shape
    var id: String { label }

    static let editor: [CropAspect] = [
        CropAspect(label: "Original", ratio: 0), CropAspect(label: "9:16", ratio: 9 / 16),
        CropAspect(label: "4:5", ratio: 4 / 5), CropAspect(label: "1:1", ratio: 1),
        CropAspect(label: "3:4", ratio: 3 / 4), CropAspect(label: "16:9", ratio: 16 / 9),
    ]
}

struct ImageCropper: View {
    let image: UIImage
    let circle: Bool
    let aspect: CGFloat
    var choices: [CropAspect] = []
    var title: String? = nil
    var onDone: (CGRect) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var picked: CropAspect?
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private var ratio: CGFloat {
        guard let picked else { return aspect }
        return picked.ratio > 0 ? picked.ratio : max(0.1, image.size.width / max(1, image.size.height))
    }

    var body: some View {
        GeometryReader { geo in
            let maxW = min(geo.size.width - 40, 620)
            let maxH = max(120, geo.size.height - (choices.isEmpty ? 220 : 280))
            let fitW = circle ? min(maxW, maxH) : maxW
            let frameW = fitW / ratio > maxH ? maxH * ratio : fitW
            let frameH = frameW / ratio
            let base = max(frameW / max(1, image.size.width), frameH / max(1, image.size.height))
            let s = max(1, scale * pinch)
            let shown = CGSize(width: image.size.width * base * s, height: image.size.height * base * s)
            let off = clamp(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), shown: shown, frame: CGSize(width: frameW, height: frameH))

            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image).resizable()
                    .frame(width: shown.width, height: shown.height)
                    .offset(off)
                Rectangle().fill(.black.opacity(0.6))
                    .mask {
                        Rectangle().overlay {
                            cutout.frame(width: frameW, height: frameH).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .allowsHitTesting(false)
                cutoutStroke.frame(width: frameW, height: frameH).allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(6, max(1, scale * value.magnification)) },
                    DragGesture().updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            offset = clamp(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                                           shown: shown, frame: CGSize(width: frameW, height: frameH))
                        }
                )
            )
            .overlay(alignment: .top) {
                Text(title ?? (circle ? "Move and pinch your profile picture" : "Move and pinch your banner"))
                    .font(.jakarta(14, .bold)).foregroundStyle(.white.opacity(0.9)).padding(.top, 20)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 14) {
                if !choices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(choices) { c in
                                let on = (picked ?? choices.first) == c
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        picked = c
                                        scale = 1
                                        offset = .zero
                                    }
                                } label: {
                                    Text(c.label).font(.jakarta(13, .heavy))
                                        .foregroundStyle(on ? Color(hex: 0x2A1620) : .white)
                                        .padding(.horizontal, 14).frame(height: 36)
                                        .background(on ? Color.white : Color.white.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(BouncyStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel).buttonStyle(OutlineButtonStyle(fullWidth: true))
                    Button {
                        let rect = CGRect(
                            x: (shown.width / 2 - frameW / 2 - off.width) / shown.width,
                            y: (shown.height / 2 - frameH / 2 - off.height) / shown.height,
                            width: frameW / shown.width, height: frameH / shown.height)
                        onDone(rect)
                    } label: { Label("Use", systemImage: "checkmark") }
                        .buttonStyle(GradientButtonStyle(height: 48))
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 520)
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear { if picked == nil, let first = choices.first { picked = first } }
    }

    @ViewBuilder private var cutout: some View {
        if circle { Circle() } else { RoundedRectangle(cornerRadius: 18, style: .continuous) }
    }

    @ViewBuilder private var cutoutStroke: some View {
        if circle { Circle().strokeBorder(.white, lineWidth: 2) } else { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white, lineWidth: 2) }
    }

    private func clamp(_ o: CGSize, shown: CGSize, frame: CGSize) -> CGSize {
        let mx = max(0, (shown.width - frame.width) / 2)
        let my = max(0, (shown.height - frame.height) / 2)
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }
}

enum Cropping {
    nonisolated static func crop(_ image: UIImage, _ unit: CGRect, maxSide: CGFloat) -> UIImage {
        let upright = StickerKit.normalized(image, maxSide: 4096)
        guard let cg = upright.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: unit.minX * w, y: unit.minY * h, width: unit.width * w, height: unit.height * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let part = cg.cropping(to: rect) else { return upright }
        return StickerKit.normalized(UIImage(cgImage: part), maxSide: maxSide)
    }

    // Crops every frame of a GIF and builds a new GIF.
    nonisolated static func cropGIF(_ data: Data, _ unit: CGRect, maxSide: CGFloat) -> Data? {
        guard let animated = AnimatedImages.decode(data, maxPixel: 900, maxFrames: 80), let frames = animated.images, !frames.isEmpty else { return nil }
        let cropped = frames.map { crop($0, unit, maxSide: maxSide) }
        return GifKit.encode(cropped, delay: animated.duration / Double(frames.count))
    }
}
