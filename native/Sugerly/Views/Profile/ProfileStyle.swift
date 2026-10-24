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
    // Aurora holds still (pickers showing every style at once).
    var still = false

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
            base.foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF7AA2), Color(hex: 0xFFB38A), Color(hex: 0xFFD166), Color(hex: 0x5EC8B8), Color(hex: 0x7CBEFF), Color(hex: 0xB19CFF)], startPoint: .top, endPoint: .bottom))
        case "sunset":
            base.foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF8A5C), Color(hex: 0xF25F8C), Color(hex: 0xA65CF2)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: 0xF25F8C).opacity(0.35), radius: size * 0.2)
        case "bold-serif":
            Text(name).font(.system(size: size, weight: .heavy, design: .serif)).foregroundStyle(Theme.main)
        case "glow-gold":
            base.foregroundStyle(LinearGradient(colors: [Color(hex: 0xF5C04A), Color(hex: 0xE6A31C)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: 0xF0A020).opacity(0.55), radius: size * 0.32)
        case "aurora":
            AuroraName(text: base, still: still)
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
    var still = false
    var body: some View {
        // 12 updates a second is plenty for a slow 5-second slide (many of
        // these can be on screen at once in a feed).
        TimelineView(.animation(minimumInterval: 1 / 12, paused: still || !Motion.ambient)) { timeline in
            let t = still || !Motion.ambient ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 5) / 5)
            text.foregroundStyle(LinearGradient(
                colors: [Color(hex: 0xEE8FAE), Color(hex: 0xB19CFF), Color(hex: 0x7CBEFF), Color(hex: 0xEE8FAE), Color(hex: 0xB19CFF)],
                startPoint: UnitPoint(x: 0.5, y: -phase), endPoint: UnitPoint(x: 0.5, y: 2 - phase)))
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
    static let gradient = LinearGradient(colors: [Color(hex: 0x8B5CF6), Color(hex: 0xC084FC), Color(hex: 0xEE8FAE)], startPoint: .top, endPoint: .bottom)
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
// Each has its own column, they all rise at the same speed and sway
// together, and neighbours are spread far apart in height, so no two ever
// touch.
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
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused || !Motion.ambient)) { timeline in
            let t = paused || !Motion.ambient ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                guard let symbol = context.resolveSymbol(id: 0) else { return }
                let n = count
                let sway = sin(t * 1.3) * 6
                for i in 0..<n {
                    let seed = Double(i) * 12.9898
                    let rx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let phase = (Double(i) * 0.38).truncatingRemainder(dividingBy: 1)
                    let p = (t * 0.07 + phase).truncatingRemainder(dividingBy: 1)
                    let fall = effect == "snow"
                    let y = fall ? p * (size.height + 30) - 15 : (1 - p) * (size.height + 30) - 15
                    let x = (Double(i) + 0.5) / Double(n) * size.width + sway
                    let scale = 0.55 + abs(rx) * 0.5
                    let alpha = min(1, min(p, 1 - p) * 5) * 0.85
                    var c = context
                    c.opacity = alpha
                    c.translateBy(x: x, y: y)
                    c.scaleBy(x: scale, y: scale)
                    c.rotate(by: .degrees(sin(t + seed) * 10))
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
                            LinearGradient(colors: [light, tint], startPoint: .top, endPoint: .bottom)
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

// MimiPlus: premium looks for your profile, paid with coins you earn. A
// dreamy banner with the artist's gem heart floating in it, you with the
// perks switched on, the plans (the bigger one marked best value), the perks
// as candy tiles, and the buy button always in reach at the bottom.
// Plan changes are observed only by the picker and buy bar, not the animated
// hero/profile preview and the rest of the shop.
@Observable
private final class NitroPlanSelection {
    var plan = NitroStyle.plans[0].id
    var chosen: NitroStyle.Plan { NitroStyle.plans.first { $0.id == plan } ?? NitroStyle.plans[0] }
}

private let nitroViolet = Color(hex: 0x8B5CF6)

// The plan cards: a plain tap switches instantly (no springs, no changing
// shadows), and only these and the buy bar redraw.
private struct NitroPlanCards: View {
    let selection: NitroPlanSelection

    var body: some View {
        HStack(spacing: 12) {
            ForEach(NitroStyle.plans) { p in card(p) }
        }
    }

    private func card(_ p: NitroStyle.Plan) -> some View {
        let on = selection.plan == p.id
        let best = p.days > 30
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            selection.plan = p.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(p.title).font(.jakarta(15, .bold))
                    Spacer(minLength: 4)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(on ? nitroViolet : Palette.borderStrong)
                }
                HStack(alignment: .center, spacing: 6) {
                    CoinIcon(size: 22)
                    Text("\(p.cost)")
                        .font(.custom("LilitaOne", size: 30, relativeTo: .title))
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(p.note).font(.jakarta(12, .bold)).foregroundStyle(best ? Palette.success : Palette.muted)
            }
            .foregroundStyle(Palette.text)
            .padding(14)
            .padding(.top, best ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.surface).overlay(shape.fill(nitroViolet.opacity(on ? 0.08 : 0))))
            .overlay(shape.strokeBorder(on ? nitroViolet : Palette.border, lineWidth: on ? 2.5 : 1))
            .overlay(alignment: .top) {
                if best {
                    Text("BEST VALUE")
                        .font(.jakarta(10, .heavy)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 20)
                        .background(nitroViolet, in: Capsule())
                        .offset(y: -10)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mimiplus-plan-\(p.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// The buy button (and how many coins are still needed), always at the bottom.
private struct NitroBuyBar: View {
    let selection: NitroPlanSelection
    let coins: Int
    let nitro: Bool
    let busy: Bool
    var buy: () -> Void

    var body: some View {
        let chosen = selection.chosen
        VStack(spacing: 10) {
            if coins < chosen.cost { progress(chosen) }
            Button(action: buy) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) } else if coins < chosen.cost {
                        Text("You need \(chosen.cost - coins) more coins")
                    } else {
                        CoinIcon(size: 20)
                        Text("\(nitro ? "Add \(chosen.title)" : "Get MimiPlus") · \(chosen.cost)")
                    }
                }
            }
            .buttonStyle(GradientButtonStyle(height: 52))
            .accessibilityIdentifier("mimiplus-purchase")
            .disabled(busy || coins < chosen.cost)
            .opacity(coins < chosen.cost ? 0.55 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(Palette.bg)
                .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func progress(_ chosen: NitroStyle.Plan) -> some View {
        let part = min(1, Double(coins) / Double(max(1, chosen.cost)))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(coins) / \(chosen.cost) coins").font(.jakarta(13, .semibold)).foregroundStyle(Palette.text).monospacedDigit()
                Spacer()
                Text("\(Int(part * 100))%").font(.jakarta(12, .bold)).foregroundStyle(nitroViolet).monospacedDigit()
            }
            Capsule().fill(Palette.surface2)
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    Capsule().fill(nitroViolet).scaleEffect(x: max(0.04, part), anchor: .leading)
                }
        }
    }
}

private struct NitroSelectionSection<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

struct NitroShopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busy: String?
    @State private var burst = 0
    @State private var selection = NitroPlanSelection()
    @State private var editing = false
    @State private var shown = false

    private var me: UserProfile? { model.me }
    private var coins: Int { me?.coins ?? 0 }
    private var nitro: Bool { me?.isNitro ?? false }
    // Read only when buying (not while drawing), so switching plans redraws
    // just the plan cards and the buy bar.
    private var chosen: NitroStyle.Plan { selection.chosen }
    private static let violet = Color(hex: 0x8B5CF6)

    private struct Perk {
        let icon: String
        let title: String
        let text: String
        let candy: Candy
    }
    private let perks: [Perk] = [
        Perk(icon: "photo.stack.fill", title: "GIF picture & banner", text: "Bring your profile to life", candy: .berry),
        Perk(icon: "textformat", title: "Name styles", text: "Gold, Aurora, Neon, Rainbow and Sunset", candy: .grape),
        Perk(icon: "sparkles", title: "Profile effects", text: "12 floating effects for your banner", candy: .lemon),
        Perk(icon: "rectangle.inset.filled", title: "Plus banner", text: "A dreamy colour banner when you don't add your own", candy: .sky),
        Perk(icon: "checkmark.seal.fill", title: "MimiPlus badge", text: "Next to your name on your profile, so everyone can see it", candy: .mint),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    if nitro { activeCard }
                    preview
                    plans
                    perksGrid
                    walletLink
                }
                .padding(16)
                .padding(.bottom, 8)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NitroBuyBar(selection: selection, coins: coins, nitro: nitro, busy: busy == "nitro") { buyNitro() }
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

    // MARK: banner

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MimiPlus")
                    .font(.custom("LilitaOne", size: 38, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x5B21B6).opacity(0.35), radius: 6, y: 3)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(statusText)
                    .font(.jakarta(13, .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                statusPill
            }
            Spacer(minLength: 0)
            GemHeart(size: 116, trigger: burst)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .background {
            ZStack {
                NitroStyle.gradient
                RadialGradient(colors: [.white.opacity(0.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 240)
                RadialGradient(colors: [Color(hex: 0xFFB6D9).opacity(0.5), .clear], center: .bottomLeading, startRadius: 0, endRadius: 200)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
        .background(shape.fill(Self.violet.opacity(0.15)).offset(y: 4))
        .accessibilityElement(children: .combine)
    }

    // Active (with days left), or your coins.
    private var statusPill: some View {
        HStack(spacing: 6) {
            if nitro {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .bold))
                Text("Active")
            } else {
                CoinIcon(size: 18)
                Text("\(coins) coins").monospacedDigit().contentTransition(.numericText())
            }
        }
        .font(.jakarta(13, .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.white.opacity(0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }

    private var statusText: String {
        if nitro, let until = Dates.parse(me?.nitroUntil ?? "") {
            let days = max(0, Int(ceil(until.timeIntervalSinceNow / 86400)))
            return "\(days) day\(days == 1 ? "" : "s") left · until \(until.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Extra sparkle for your profile, paid with the free coins you earn."
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
                    .background(Palette.surface, in: Circle())
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
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var activeCard: some View {
        HStack(spacing: 12) {
            CandyTile(icon: "paintbrush.pointed.fill", candy: .grape, size: 38)
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
        VStack(alignment: .leading, spacing: 10) {
            ListHeader(title: nitro ? "ADD MORE TIME" : "PICK A PLAN").padding(.leading, 6)
            HStack(spacing: 12) {
                NitroPlanCards(selection: selection)
            }
            .padding(.top, 8)
            Text("It never renews by itself. When the time runs out, your profile simply goes back to the free looks.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
        }
    }

    // MARK: perks

    // Candy tiles, two by two (an odd last one gets the whole row).
    private var perksGrid: some View {
        let paired = perks.count - perks.count % 2
        return VStack(alignment: .leading, spacing: 10) {
            ListHeader(title: "WHAT YOU GET").padding(.leading, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<paired, id: \.self) { i in perkTile(perks[i]) }
            }
            if paired < perks.count { perkRow(perks[paired]) }
        }
    }

    private func perkTile(_ p: Perk) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            CandyTile(icon: p.icon, candy: p.candy, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Text(p.text).font(.jakarta(12)).foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(p.candy.soft, in: shape)
        .overlay(shape.strokeBorder(p.candy.color.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func perkRow(_ p: Perk) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(spacing: 12) {
            CandyTile(icon: p.icon, candy: p.candy, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                Text(p.text).font(.jakarta(12)).foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(p.candy.soft, in: shape)
        .overlay(shape.strokeBorder(p.candy.color.opacity(0.18), lineWidth: 1))
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

// The artist's gem heart floating in the MimiPlus banner, with gem sparkles
// twinkling round it. The heart and the sparkles each keep their own space
// (with a gap even as the heart floats), and the sparkles step aside while
// a puff of little hearts plays (tap it, or buy MimiPlus), so nothing ever
// touches.
struct GemHeart: View {
    var size: CGFloat = 110
    var trigger = 0
    @State private var taps = 0
    @State private var puffing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moving: Bool { !reduceMotion && Motion.ambient }

    var body: some View {
        ZStack {
            sparkles
            Image("MimiHeart").resizable().scaledToFit()
                .frame(width: size * 0.62)
                .shadow(color: Color(hex: 0x9D174D).opacity(0.3), radius: 8, y: 5)
                .phaseAnimator(moving ? [false, true] : [false]) { content, up in
                    content.offset(y: up ? -size * 0.03 : size * 0.015)
                } animation: { _ in .easeInOut(duration: 1.8) }
                .keyframeAnimator(initialValue: GemPop(), trigger: taps + trigger) { content, pop in
                    content.scaleEffect(pop.scale)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.1, duration: 0.14)
                        SpringKeyframe(0.94, duration: 0.16)
                        SpringKeyframe(1, duration: 0.3)
                    }
                }
        }
        .frame(width: size, height: size)
        .overlay { HeartPuff(trigger: taps + trigger).frame(width: size * 1.4, height: size * 1.4) }
        .contentShape(Rectangle())
        .onTapGesture { taps += 1 }
        .task(id: taps + trigger) {
            guard taps + trigger > 0 else { return }
            puffing = true
            try? await Task.sleep(for: .seconds(1.3))
            puffing = false
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityHidden(true)
    }

    private var sparkles: some View {
        ZStack {
            sparkle(x: -0.43, y: -0.36, scale: 0.17, delay: 0)
            sparkle(x: 0.43, y: -0.22, scale: 0.15, delay: 0.6)
            sparkle(x: 0.33, y: 0.39, scale: 0.13, delay: 1.1)
        }
        .opacity(puffing ? 0 : 1)
        .animation(.easeOut(duration: 0.1), value: puffing)
    }

    private func sparkle(x: CGFloat, y: CGFloat, scale: CGFloat, delay: Double) -> some View {
        Image("MimiSparkle").resizable().scaledToFit()
            .frame(width: size * scale)
            // They only fade and shrink a little, never grow past their spot.
            .phaseAnimator(moving ? [false, true] : [true]) { content, lit in
                content
                    .scaleEffect(lit ? 1 : 0.8)
                    .opacity(lit ? 1 : 0.55)
            } animation: { _ in .easeInOut(duration: 1.3).delay(delay * 0.3) }
            .offset(x: size * x, y: size * y)
    }
}

struct GemPop {
    var scale: CGFloat = 1
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

// Presets use the existing profile fields, so the same look is visible to
// other people and remains editable using the individual colour controls.
struct ProfileThemePreset: Identifiable {
    let id: String
    let name: String
    let banner: String
    let accent: String
    let pattern: String

    static let all = [
        ProfileThemePreset(id: "strawberry", name: "Strawberry", banner: "#FFD9E8", accent: "#DB5C91", pattern: "hearts"),
        ProfileThemePreset(id: "lavender", name: "Lavender", banner: "#E9DEFF", accent: "#8B65CE", pattern: "stars"),
        ProfileThemePreset(id: "mint", name: "Mint soda", banner: "#D6F5E9", accent: "#248B77", pattern: "dots"),
        ProfileThemePreset(id: "peach", name: "Peach picnic", banner: "#FFE3CE", accent: "#C86B42", pattern: "checks"),
        ProfileThemePreset(id: "sky", name: "Daydream", banner: "#DDEFFF", accent: "#417FBE", pattern: "waves"),
        ProfileThemePreset(id: "night", name: "Moonlight", banner: "#332A55", accent: "#AC96E2", pattern: "stars")
    ]
}
