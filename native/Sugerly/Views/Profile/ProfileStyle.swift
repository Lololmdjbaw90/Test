import SwiftUI
import UIKit
import ImageIO

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
        // 12 updates a second is plenty for a slow 5-second slide (many of
        // these can be on screen at once in a feed).
        TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
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
            Image(systemName: "sparkles").font(.system(size: compact ? 9 : 11, weight: .bold))
            if !compact { Text("Plus").font(.jakarta(12, .heavy)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 5 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(NitroStyle.gradient, in: Capsule())
        .shadow(color: Color(hex: 0x8B5CF6).opacity(0.35), radius: 6, y: 2)
        .accessibilityLabel("MimiPlus")
    }
}

enum NitroStyle {
    static let gradient = LinearGradient(colors: [Color(hex: 0x8B5CF6), Color(hex: 0xC084FC), Color(hex: 0xEE8FAE)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cost = 800
    static let xpBoostCost = 150

    // Same plans as the website (src/components/profile/NitroShop.jsx).
    struct Plan: Identifiable {
        let id: String
        let days: Int
        let cost: Int
        let title: String
        let note: String
    }
    static let plans = [
        Plan(id: "month", days: 30, cost: 800, title: "1 month", note: "30 days"),
        Plan(id: "season", days: 90, cost: 2000, title: "3 months", note: "Save 400 coins"),
    ]
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
    // Stops moving (and redrawing) while something covers it, like Settings.
    var paused = false

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
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { timeline in
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

// MARK: - Banner patterns

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
            // Nothing ever draws past the banner's edges.
            ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
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
                // Each stripe runs well past the top and bottom, so their
                // cut-off ends never show inside the banner.
                let reach = size.height + 40
                var x: CGFloat = -reach
                while x < size.width + 20 {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height + 20)); p.addLine(to: CGPoint(x: x + reach, y: -20))
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
                    p.move(to: CGPoint(x: -40, y: y))
                    var x: CGFloat = -40
                    while x < size.width + 40 {
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
        // A fresh drawing for each pattern: without this the first one you
        // picked stayed on screen and you couldn't change it.
        .id(pattern)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Little banner tiles to pick a pattern from, each showing the pattern.
struct BannerPatternPicker: View {
    @Binding var selection: String
    var tint: Color = Theme.main
    var light: Color = Theme.light

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            ForEach(BannerPattern.all) { item in
                let active = selection == item.id
                Button { withMotion(Motion.standard) { selection = item.id } } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            LinearGradient(colors: [light, tint], startPoint: .topLeading, endPoint: .bottomTrailing)
                            if !item.id.isEmpty { BannerPatternView(pattern: item.id) }
                        }
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? Palette.text : .clear, lineWidth: 2.5).padding(-3))
                        .overlay(alignment: .topTrailing) {
                            if active {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white, Palette.text)
                                    .padding(5)
                                    .transition(.pop)
                            }
                        }
                        Text(item.label).font(.jakarta(12, active ? .heavy : .semibold)).foregroundStyle(active ? Palette.text : Palette.text2)
                    }
                }
                .buttonStyle(BouncyStyle(scale: 0.95))
                .accessibilityLabel("\(item.label) pattern")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }
}

// MARK: - Nitro shop (a sheet, not a page)

// A MimiCoin: a little gold coin with a sparkle (coins are just for fun,
// so no money signs).
struct CoinIcon: View {
    var size: CGFloat = 18
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hex: 0xFFD978), Color(hex: 0xF0A020)], startPoint: .top, endPoint: .bottom), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: max(1, size * 0.06)))
            .accessibilityHidden(true)
    }
}

// MimiPlus: premium looks for your profile, paid with coins you earn.
struct NitroShopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var busy: String?
    @State private var burst = 0
    @State private var plan = NitroStyle.plans[0].id
    @State private var editing = false
    @State private var shown = false

    private var me: UserProfile? { model.me }
    private var coins: Int { me?.coins ?? 0 }
    private var nitro: Bool { me?.isNitro ?? false }
    private var chosen: NitroStyle.Plan { NitroStyle.plans.first { $0.id == plan } ?? NitroStyle.plans[0] }

    private struct Perk {
        let icon: String
        let title: String
        let text: String
    }
    private let perks: [Perk] = [
        Perk(icon: "photo.stack.fill", title: "GIF picture & banner", text: "Bring your profile to life"),
        Perk(icon: "textformat", title: "Name styles", text: "Gold, Aurora, Neon, Rainbow and Sunset"),
        Perk(icon: "sparkles", title: "Profile effects", text: "12 floating effects for your banner"),
        Perk(icon: "rectangle.inset.filled", title: "Plus banner", text: "A dreamy colour banner when you don't add your own"),
        Perk(icon: "checkmark.seal.fill", title: "MimiPlus badge", text: "Next to your name on your profile"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero.entrance(shown, 0)
                    if nitro { activeCard.entrance(shown, 1) }
                    plans.entrance(shown, 2)
                    perksList.entrance(shown, 3)
                    walletLink.entrance(shown, 4)
                }
                .padding(16)
                .padding(.bottom, 20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .sugarBackground()
            .overlay { ConfettiBurst(trigger: burst) }
            .navigationTitle("MimiPlus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                        .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $editing) { EditProfileView() }
            .onAppear { shown = true }
        }
        .tint(Theme.main)
        .presentationCornerRadius(34)
    }

    // MARK: hero with a live preview of your profile

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("MimiPlus").font(.display(32)).foregroundStyle(Palette.text)
                    if nitro {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.jakarta(12, .bold)).foregroundStyle(Palette.success)
                            .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 26)
                            .background(Palette.success.opacity(0.12), in: Capsule())
                            .transition(.pop)
                    }
                }
                Text(statusText).font(.jakarta(14)).foregroundStyle(Palette.text2)
            }
            preview
        }
        .pastelCard(radius: 24, padding: 16)
    }

    // You, with the perks switched on (your own style if you have one).
    private var preview: some View {
        let name = me?.displayName ?? "You"
        let style = NameStyles.isPremium(me?.nameStyle ?? "") ? (me?.nameStyle ?? "aurora") : "aurora"
        let effect = (me?.profileEffect ?? "").isEmpty ? "sparkles" : (me?.profileEffect ?? "sparkles")
        return VStack(spacing: 0) {
            ZStack {
                NitroStyle.gradient.opacity(0.85)
                ProfileEffectLayer(effect: effect, color: me?.effectColor ?? "", amount: me?.effectAmount ?? 0)
            }
            .frame(height: 78)
            .clipped()
            VStack(spacing: 8) {
                Avatar(url: me?.picture ?? "", name: name, size: 70, nitro: true)
                    .padding(4)
                    .background(Palette.surface2, in: Circle())
                    .offset(y: -38)
                    .padding(.bottom, -38)
                HStack(spacing: 6) {
                    NameText(name: name, style: style, size: 24, display: true, nitro: true, tint: me?.nameColor ?? "")
                        .lineLimit(1)
                    NitroBadge(compact: true)
                }
                Text(nitro ? "Your MimiPlus look" : "This is you with MimiPlus").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.shadow, radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if nitro, let until = Dates.parse(me?.nitroUntil ?? "") {
            let days = max(0, Int(ceil(until.timeIntervalSinceNow / 86400)))
            return "\(days) day\(days == 1 ? "" : "s") left · until \(until.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Extra looks for your profile. Paid with the free coins you earn."
    }

    private var activeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintbrush.pointed.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.main)
                .frame(width: 36, height: 36)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Use your perks").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                Text("GIF picture, name style or effect").font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Button("Customise") { editing = true }
                .buttonStyle(OutlineButtonStyle())
        }
        .sugarCard(radius: 20, padding: 14)
    }

    // MARK: plans

    private var plans: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(nitro ? "Add more time" : "Pick a plan").font(.jakarta(16, .bold)).foregroundStyle(Palette.text)
            HStack(spacing: 10) {
                ForEach(NitroStyle.plans) { p in planCard(p) }
            }
            if coins < chosen.cost { progress.transition(.rise) }
            Button { buyNitro() } label: {
                HStack(spacing: 8) {
                    if busy == "nitro" { ProgressView().tint(.white) } else if coins < chosen.cost {
                        Text("You need \(chosen.cost - coins) more coins")
                    } else {
                        CoinIcon(size: 20)
                        Text("\(nitro ? "Add \(chosen.title)" : "Get MimiPlus") · \(chosen.cost)")
                    }
                }
                .contentTransition(.numericText())
            }
            .buttonStyle(GradientButtonStyle(height: 50))
            .disabled(busy != nil || coins < chosen.cost)
            .opacity(coins < chosen.cost ? 0.55 : 1)
            Text("It never renews by itself. When the time runs out, your profile simply goes back to the free looks.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
        }
        .motion(Motion.standard, value: plan)
        .sugarCard(radius: 22, padding: 16)
    }

    private func planCard(_ p: NitroStyle.Plan) -> some View {
        let on = plan == p.id
        return Button { withMotion(Motion.playful) { plan = p.id } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(p.title).font(.jakarta(15, .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(on ? Theme.main : Palette.borderStrong)
                        .contentTransition(.symbolEffect(.replace))
                }
                HStack(spacing: 6) {
                    CoinIcon(size: 18)
                    Text("\(p.cost)").font(.display(26)).monospacedDigit()
                }
                Text(p.note).font(.jakarta(12, .semibold)).foregroundStyle(p.days > 30 ? Palette.success : Palette.muted)
            }
            .foregroundStyle(Palette.text)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Theme.main : Palette.border, lineWidth: on ? 1.5 : 1))
            .scaleEffect(on ? 1 : 0.98)
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var progress: some View {
        let part = min(1, Double(coins) / Double(max(1, chosen.cost)))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(coins) / \(chosen.cost) coins").font(.jakarta(13, .semibold)).foregroundStyle(Palette.text).monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Text("\(Int(part * 100))%").font(.jakarta(12, .bold)).foregroundStyle(Theme.main).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface2)
                    Capsule().fill(Theme.main).frame(width: max(8, geo.size.width * part))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: perks

    private var perksList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListHeader(title: "WHAT YOU GET").padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(perks.indices, id: \.self) { i in
                    if i > 0 { Divider().padding(.leading, 62) }
                    perkRow(perks[i])
                }
            }
            .sugarCard(radius: 20)
        }
    }

    private func perkRow(_ p: Perk) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.accent.color)
                .frame(width: 34, height: 34)
                .background(Tone.accent.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                Text(p.text).font(.jakarta(12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    // MARK: coins

    // Your balance, and the way to the wallet (earning, XP boosts).
    private var walletLink: some View {
        NavigationLink {
            WalletPage()
        } label: {
            HStack(spacing: 12) {
                CoinIcon(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coins) coins").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("See how to earn more").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
            }
            .sugarCard(radius: 20, padding: 14)
        }
        .buttonStyle(SoftPressStyle())
    }

    // MARK: buying

    private func buyNitro() {
        let now = Date()
        let from = nitro ? max(now, Dates.parse(me?.nitroUntil ?? "") ?? now) : now
        let until = Dates.iso(from.addingTimeInterval(Double(chosen.days) * 86400))
        buy("nitro", chosen.cost, ["nitro_active": true, "nitro_until": until],
            nitro ? "MimiPlus extended by \(chosen.days) days" : "Welcome to MimiPlus")
    }

    private func buy(_ id: String, _ cost: Int, _ patch: Doc, _ message: String) {
        guard coins >= cost else {
            model.showToast("You need \(cost - coins) more coins", icon: "sparkle", error: true)
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

// A short shower of soft paper bits in your colour, for big moments
// (getting MimiPlus, a first post). A haptic says "done" too.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < 1.8 else { return }
                let colors: [Color] = [Theme.main, Theme.light, Palette.borderStrong, Theme.main.opacity(0.6)]
                for i in 0..<36 {
                    let seed = Double(i) * 78.233
                    let r = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.5 + (r - 0.5) * 0.4) + cos(seed) * 200 * t
                    let y = size.height * 0.22 - (200 + r * 160) * t + 460 * t * t
                    var c = context
                    c.opacity = max(0, 1 - t / 1.8)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * (3 + r * 5)))
                    let rect = CGRect(x: -3, y: -5, width: 6, height: 10)
                    c.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(.success, trigger: trigger)
        .task(id: trigger) {
            guard trigger > 0, !reduceMotion else { return }
            start = Date()
            try? await Task.sleep(for: .seconds(1.9))
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
                                        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 14).frame(height: 36)
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

    // Crops a GIF frame by frame at full quality: every frame and its own
    // timing are kept, and only one frame is in memory at a time. When
    // nothing was cut away the original file is kept untouched.
    nonisolated static func cropGIF(_ data: Data, _ unit: CGRect, maxSide: CGFloat) -> Data? {
        let limit = 15 * 1024 * 1024
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let whole = unit.minX <= 0.01 && unit.minY <= 0.01 && unit.maxX >= 0.99 && unit.maxY >= 0.99
        if whole && data.count <= limit && CGFloat(max(w, h)) <= maxSide * 1.6 { return data }
        var side = maxSide
        for _ in 0..<4 {
            if let out = recode(source, unit, width: w, height: h, maxSide: side), out.count <= limit { return out }
            side *= 0.8
        }
        return nil
    }

    nonisolated private static func recode(_ source: CGImageSource, _ unit: CGRect, width w: Int, height h: Int, maxSide: CGFloat) -> Data? {
        let rect = CGRect(x: unit.minX * CGFloat(w), y: unit.minY * CGFloat(h), width: unit.width * CGFloat(w), height: unit.height * CGFloat(h)).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let scale = min(1, maxSide / max(rect.width, rect.height))
        let outW = max(1, Int((rect.width * scale).rounded())), outH = max(1, Int((rect.height * scale).rounded()))
        let count = min(CGImageSourceGetCount(source), 600)
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "com.compuserve.gif" as CFString, count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var added = 0
        for i in 0..<count {
            autoreleasepool {
                guard let frame = CGImageSourceCreateImageAtIndex(source, i, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let part = frame.cropping(to: rect),
                      let context = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.interpolationQuality = .high
                context.draw(part, in: CGRect(x: 0, y: 0, width: outW, height: outH))
                guard let scaled = context.makeImage() else { return }
                let delay = AnimatedImages.frameDelay(source, i)
                CGImageDestinationAddImage(destination, scaled, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
                added += 1
            }
        }
        guard added > 0, CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
