import SwiftUI
import UIKit

// Your bunny, drawn from the artist's own layers (fur, outline, clothes,
// faces; the bow cut from the finished picture; see scripts/bunny-layers.py).
// Each part can take its own colour; faces, clothes and a scene can be
// swapped. She floats gently and jumps when you tap her.

// MARK: - The look

struct BunnyTint: Identifiable, Equatable {
    let name: String
    let hue: Double
    let saturation: Double
    let brightness: Double
    // What the colour comes out as (for the picker).
    let swatch: UInt32
    var id: String { name }
}

enum BunnyPart: String, CaseIterable, Identifiable {
    case fur, bow, collar, outfit
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    // Worked out from the artwork's own colours (pink fur, pink bow,
    // berry collar).
    var tints: [BunnyTint] {
        switch self {
        case .fur:
            return [
                BunnyTint(name: "Pink", hue: 0, saturation: 1, brightness: 0, swatch: 0xF793B2),
                BunnyTint(name: "Peach", hue: 30, saturation: 1, brightness: 0.02, swatch: 0xF69E90),
                BunnyTint(name: "Honey", hue: 62, saturation: 1.25, brightness: 0.1, swatch: 0xF9BC74),
                BunnyTint(name: "Mint", hue: 175, saturation: 0.9, brightness: 0, swatch: 0x67C09E),
                BunnyTint(name: "Sky", hue: -140, saturation: 0.9, brightness: 0.02, swatch: 0x77BDD7),
                BunnyTint(name: "Lavender", hue: -85, saturation: 0.9, brightness: 0.02, swatch: 0xAFA9F5),
                BunnyTint(name: "Snow", hue: 0, saturation: 0.1, brightness: 0.12, swatch: 0xE3DADD),
                BunnyTint(name: "Cocoa", hue: 35, saturation: 0.8, brightness: -0.25, swatch: 0xA05E4D),
            ]
        case .bow:
            return [
                BunnyTint(name: "Pink", hue: 0, saturation: 1, brightness: 0, swatch: 0xF8B1D5),
                BunnyTint(name: "Coral", hue: 25, saturation: 1.4, brightness: -0.05, swatch: 0xF29FAE),
                BunnyTint(name: "Peach", hue: 55, saturation: 1.2, brightness: 0.02, swatch: 0xFEBCA0),
                BunnyTint(name: "Lemon", hue: 85, saturation: 1.3, brightness: 0.02, swatch: 0xE6C685),
                BunnyTint(name: "Mint", hue: -160, saturation: 1, brightness: 0, swatch: 0x8AD3C4),
                BunnyTint(name: "Sky", hue: -120, saturation: 1, brightness: 0, swatch: 0x98CCE8),
                BunnyTint(name: "Lilac", hue: -70, saturation: 1, brightness: 0, swatch: 0xC4BDFB),
                BunnyTint(name: "Snow", hue: 0, saturation: 0.1, brightness: 0.05, swatch: 0xD5CED1),
            ]
        case .collar:
            return [
                BunnyTint(name: "Berry", hue: 0, saturation: 1, brightness: 0, swatch: 0xCB469C),
                BunnyTint(name: "Cherry", hue: 25, saturation: 1.4, brightness: -0.05, swatch: 0xF22D63),
                BunnyTint(name: "Tangerine", hue: 55, saturation: 1.2, brightness: 0.02, swatch: 0xE45130),
                BunnyTint(name: "Mustard", hue: 85, saturation: 1.3, brightness: 0.02, swatch: 0xBB6305),
                BunnyTint(name: "Jade", hue: -160, saturation: 1, brightness: 0, swatch: 0x008B5A),
                BunnyTint(name: "Ocean", hue: -120, saturation: 1, brightness: 0, swatch: 0x0B7EA4),
                BunnyTint(name: "Violet", hue: -70, saturation: 1, brightness: 0, swatch: 0x5A62D7),
                BunnyTint(name: "Stone", hue: 0, saturation: 0.1, brightness: 0.05, swatch: 0x7F727A),
            ]
        case .outfit:
            // Clothes are made of differently coloured pieces, so an outfit
            // colour is a target hue each piece is turned to (see BunnyPiece).
            return [
                BunnyTint(name: "Original", hue: .nan, saturation: 1, brightness: 0, swatch: 0x3A5BB0),
                BunnyTint(name: "Berry", hue: 340, saturation: 1, brightness: 0, swatch: 0xC8466E),
                BunnyTint(name: "Toffee", hue: 18, saturation: 1, brightness: 0, swatch: 0xC07A4A),
                BunnyTint(name: "Lemon", hue: 50, saturation: 1.1, brightness: 0.03, swatch: 0xD9B43C),
                BunnyTint(name: "Mint", hue: 155, saturation: 1, brightness: 0, swatch: 0x45B98C),
                BunnyTint(name: "Teal", hue: 190, saturation: 1, brightness: 0, swatch: 0x3AA6B8),
                BunnyTint(name: "Grape", hue: 270, saturation: 1, brightness: 0, swatch: 0x8A5BD6),
                BunnyTint(name: "Mono", hue: 0, saturation: 0, brightness: 0, swatch: 0x4A4A55),
            ]
        }
    }
}

// The clothes, each its own layer (with the hue it was painted in).
enum BunnyPiece: String {
    case skirt = "BunnySkirt", pinafore = "BunnyPinafore", bloomers = "BunnyBloomers", sailor = "BunnySailor"

    var baseHue: Double {
        switch self {
        case .skirt: return 196
        case .pinafore: return 222
        case .bloomers: return 29
        case .sailor: return 252
        }
    }

    // How far to turn this piece for an outfit colour.
    func turn(to tint: BunnyTint) -> Double {
        guard !tint.hue.isNaN else { return 0 }
        var d = (tint.hue - baseHue).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

// Clothes: one top at a time.
enum BunnyTop: String, CaseIterable, Codable, Identifiable {
    case none, sailor, tee, hoodie, ruffle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .sailor: return "Sailor"
        case .tee: return "T-shirt"
        case .hoodie: return "Hoodie"
        case .ruffle: return "Ruffles"
        }
    }
    var piece: BunnyPiece? {
        switch self {
        case .none: return nil
        case .sailor: return .sailor
        case .tee: return .skirt
        case .hoodie: return .pinafore
        case .ruffle: return .bloomers
        }
    }
}

enum BunnyFace: String, CaseIterable, Codable, Identifiable {
    case cute, happy, silly, shy, smug, worried, dreamy, meh, grumpy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var image: String { "BunnyFace" + rawValue.capitalized }
    var eyes: String { image + "Eyes" }
}

enum BunnyScene: String, CaseIterable, Codable, Identifiable {
    case candy, sky, mint, sunset, night, lilac
    var id: String { rawValue }
    var label: String {
        switch self {
        case .candy: return "Candy"
        case .sky: return "Clouds"
        case .mint: return "Mint"
        case .sunset: return "Sunset"
        case .night: return "Night"
        case .lilac: return "Picnic"
        }
    }
    var colors: [Color] {
        switch self {
        case .candy: return [Color(hex: 0xFFD3E4), Color(hex: 0xFFB5CF), Color(hex: 0xFFC9A8)]
        case .sky: return [Color(hex: 0xBFE4FF), Color(hex: 0xA9CFFF), Color(hex: 0xD9C8FF)]
        case .mint: return [Color(hex: 0xC9F5E2), Color(hex: 0x9FE8CB), Color(hex: 0xFFF1A8)]
        case .sunset: return [Color(hex: 0xFFD6A5), Color(hex: 0xFFA8B8), Color(hex: 0xC9A7FF)]
        case .night: return [Color(hex: 0x2B2360), Color(hex: 0x4B2F86), Color(hex: 0x8A4FA8)]
        case .lilac: return [Color(hex: 0xEADFFF), Color(hex: 0xD7C6FF), Color(hex: 0xFFD0E6)]
        }
    }
}

struct BunnyLook: Codable, Equatable {
    var fur = 0
    var bowOn = true
    var bow = 0
    var collar = 0
    var outfit = 0
    var top = BunnyTop.sailor
    var face = BunnyFace.cute
    var scene = BunnyScene.candy
    // A picture item worn instead of the top, and one on her head or face
    // (instead of the bow); ids from BunnyCatalog, empty for none.
    var wear = ""
    var head = ""

    func tint(_ part: BunnyPart) -> BunnyTint {
        let list = part.tints
        return list[max(0, min(list.count - 1, index(part)))]
    }

    func index(_ part: BunnyPart) -> Int {
        switch part {
        case .fur: return fur
        case .bow: return bow
        case .collar: return collar
        case .outfit: return outfit
        }
    }

    mutating func set(_ part: BunnyPart, _ value: Int) {
        switch part {
        case .fur: fur = value
        case .bow: bow = value
        case .collar: collar = value
        case .outfit: outfit = value
        }
    }

    static func random() -> BunnyLook {
        var look = BunnyLook()
        for part in BunnyPart.allCases { look.set(part, Int.random(in: 0..<part.tints.count)) }
        look.bowOn = Int.random(in: 0..<5) > 0
        look.top = BunnyTop.allCases.randomElement() ?? BunnyTop.sailor
        look.face = BunnyFace.allCases.randomElement() ?? BunnyFace.cute
        look.scene = BunnyScene.allCases.randomElement() ?? BunnyScene.candy
        // Sometimes one of the picture clothes, sometimes something on her head.
        if Bool.random() { look.wear = BunnyItem.builtIn.filter { $0.slot == .top }.randomElement()?.id ?? "" }
        if Int.random(in: 0..<3) == 0 { look.head = BunnyItem.builtIn.filter { $0.slot == .head }.randomElement()?.id ?? "" }
        return look
    }
}

extension BunnyLook {
    // Anything missing or unknown (an older bunny) keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fur = (try? c.decodeIfPresent(Int.self, forKey: .fur)) ?? fur
        bowOn = (try? c.decodeIfPresent(Bool.self, forKey: .bowOn)) ?? bowOn
        bow = (try? c.decodeIfPresent(Int.self, forKey: .bow)) ?? bow
        collar = (try? c.decodeIfPresent(Int.self, forKey: .collar)) ?? collar
        outfit = (try? c.decodeIfPresent(Int.self, forKey: .outfit)) ?? outfit
        top = (try? c.decodeIfPresent(BunnyTop.self, forKey: .top)) ?? top
        face = (try? c.decodeIfPresent(BunnyFace.self, forKey: .face)) ?? face
        scene = (try? c.decodeIfPresent(BunnyScene.self, forKey: .scene)) ?? scene
        wear = (try? c.decodeIfPresent(String.self, forKey: .wear)) ?? wear
        head = (try? c.decodeIfPresent(String.self, forKey: .head)) ?? head
    }
}

// Your bunny, kept on this iPhone for each account.
@MainActor
@Observable
final class BunnyStore {
    static let shared = BunnyStore()
    private(set) var look = BunnyLook()
    // Whether you've made your own yet (Home shows an invite until then).
    private(set) var made = false
    @ObservationIgnored private var email = ""

    private var key: String { "sugerly.bunny." + (email.isEmpty ? "guest" : email) }

    func use(_ email: String) {
        guard email != self.email else { return }
        self.email = email
        // The team's clothes and accessories, in case she wears one.
        Task { await BunnyCatalog.shared.load() }
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(BunnyLook.self, from: data) {
            look = saved
            made = true
            BunnyImages.warmUp(saved)
        } else {
            look = BunnyLook()
            made = false
        }
    }

    func save(_ next: BunnyLook) {
        look = next
        made = true
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Drawing

enum BunnyArt {
    // The artwork's canvas (all layers share it).
    static let aspect: CGFloat = 878.0 / 1210.0
    // Roughly where the eyes sit (for the heart specs).
    static let leftEye = CGRect(x: 0.2711, y: 0.3372, width: 0.1834, height: 0.1091)
    static let rightEye = CGRect(x: 0.5456, y: 0.3372, width: 0.1845, height: 0.1091)
    // The outline colour of the drawing.
    static let ink = Color(hex: 0x2A0812)
}

// The layers, decoded once at a size that's sharp on screen (the drawings
// are big; decoding them while a page opened made it stutter). The usual
// bunny's layers are decoded in the background when the app starts.
@MainActor
enum BunnyImages {
    private static var cache: [String: UIImage] = [:]
    private static let pixels = CGSize(width: 653, height: 900)

    static func image(_ name: String) -> Image {
        if let hit = cache[name] { return Image(uiImage: hit) }
        let made = load(name)
        cache[name] = made
        return Image(uiImage: made)
    }

    nonisolated static func load(_ name: String) -> UIImage {
        guard let full = UIImage(named: name) else { return UIImage() }
        return full.preparingThumbnail(of: pixels) ?? full
    }

    static func warmUp(_ look: BunnyLook = BunnyLook()) {
        var names = ["BunnyFur", "BunnyOutline", "BunnyBow", "BunnyCollar", look.face.image, look.face.eyes]
        if let piece = look.top.piece { names.append(piece.rawValue) }
        for id in [look.wear, look.head] {
            if let asset = BunnyItem.builtIn.first(where: { $0.id == id })?.asset { names.append(asset) }
        }
        let missing = names.filter { cache[$0] == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            var made: [(String, UIImage)] = []
            for name in missing { made.append((name, load(name))) }
            let ready = made
            await MainActor.run {
                for (name, image) in ready where cache[name] == nil { cache[name] = image }
            }
        }
    }
}

// One layer of the drawing in a colour.
struct BunnyLayer: View {
    let name: String
    var hue: Double = 0
    var saturation: Double = 1
    var brightness: Double = 0

    var body: some View {
        BunnyImages.image(name).resizable().interpolation(.high)
            .hueRotation(.degrees(hue))
            .saturation(saturation)
            .brightness(brightness)
    }
}

extension BunnyLayer {
    init(_ name: String, _ tint: BunnyTint) {
        self.init(name: name, hue: tint.hue, saturation: tint.saturation, brightness: tint.brightness)
    }

    init(_ piece: BunnyPiece, _ tint: BunnyTint) {
        self.init(name: piece.rawValue, hue: piece.turn(to: tint), saturation: tint.saturation, brightness: tint.brightness)
    }
}

// The bunny, standing still. Equatable, so moving her around never redraws
// the layers.
struct BunnyFigure: View, Equatable {
    var look: BunnyLook

    nonisolated static func == (a: BunnyFigure, b: BunnyFigure) -> Bool {
        a.look == b.look
    }

    var body: some View {
        let outfit = look.tint(.outfit)
        ZStack {
            BunnyLayer("BunnyFur", look.tint(.fur))
            BunnyImages.image("BunnyOutline").resizable().interpolation(.high)
            if let item = BunnyCatalog.shared.item(look.wear) {
                BunnyItemLayer(item: item)
            } else {
                if let piece = look.top.piece { BunnyLayer(piece, outfit) }
                if look.top == .sailor { BunnyLayer("BunnyCollar", look.tint(.collar)) }
            }
            BunnyImages.image(look.face.image).resizable().interpolation(.high)
            BunnyImages.image(look.face.eyes).resizable().interpolation(.high)
            // A hat or accessory takes the bow's place.
            if let item = BunnyCatalog.shared.item(look.head) {
                BunnyItemLayer(item: item)
            } else if look.bowOn {
                BunnyLayer("BunnyBow", look.tint(.bow))
            }
        }
        .aspectRatio(BunnyArt.aspect, contentMode: .fit)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

enum BunnyShapes {
    static func heart(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.32), control1: CGPoint(x: r.midX - r.width * 0.12, y: r.maxY - r.height * 0.18), control2: CGPoint(x: r.minX, y: r.midY + r.height * 0.08))
        p.addArc(center: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.midY + r.height * 0.08), control2: CGPoint(x: r.midX + r.width * 0.12, y: r.maxY - r.height * 0.18))
        p.closeSubpath()
        return p
    }
}

// MARK: - The living bunny

// Your bunny, alive but calm: she floats up and down a touch, slowly, and
// jumps with a puff of hearts when you tap her.
struct BunnyBuddy: View {
    var look: BunnyLook
    var height: CGFloat = 120
    var lively = true
    // Off inside buttons (the button gets the tap).
    var tappable = true
    var onTap: (() -> Void)? = nil
    @State private var hops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = lively && !reduceMotion && Motion.ambient && !Motion.paused
        BunnyFigure(look: look)
            .equatable()
            .frame(height: height)
            // Only moved, never stretched, so she stays crisp.
            .phaseAnimator(moving ? [false, true] : [false]) { content, up in
                content.offset(y: up ? -height * 0.015 : 0)
            } animation: { _ in .easeInOut(duration: 2.2) }
            .keyframeAnimator(initialValue: BunnyHop(), trigger: hops) { content, hop in
                content
                    .scaleEffect(x: hop.squash, y: 2 - hop.squash, anchor: .bottom)
                    .offset(y: hop.lift)
            } keyframes: { _ in
                KeyframeTrack(\.squash) {
                    SpringKeyframe(1.06, duration: 0.1)
                    SpringKeyframe(0.96, duration: 0.18)
                    SpringKeyframe(1, duration: 0.25)
                }
                KeyframeTrack(\.lift) {
                    LinearKeyframe(0, duration: 0.1)
                    SpringKeyframe(-height * 0.12, duration: 0.22)
                    SpringKeyframe(0, duration: 0.26)
                }
            }
            .overlay { HeartPuff(trigger: hops).frame(width: height * 1.1, height: height * 1.1) }
            .contentShape(Rectangle())
            .allowsHitTesting(tappable)
            .onTapGesture {
                hops += 1
                onTap?()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hops)
            .accessibilityElement()
            .accessibilityLabel("Your bunny")
            .accessibilityAddTraits(.isButton)
    }
}

// Your bunny inside a rounded tile of the background you picked for her in
// the maker, so it shows wherever she does. She stays inside the tile (with
// room above her ears for a hop).
struct BunnyOnScene: View {
    var look: BunnyLook
    // The tile's height.
    var height: CGFloat = 104
    var lively = true

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: height * 0.24, style: .continuous)
        ZStack(alignment: .bottom) {
            BunnySceneView(scene: look.scene, animated: false)
                .allowsHitTesting(false)
            BunnyBuddy(look: look, height: height * 0.8, lively: lively)
                .padding(.bottom, height * 0.04)
        }
        .frame(width: height * 0.9, height: height)
        .clipShape(tile)
        .overlay(tile.strokeBorder(.white.opacity(0.75), lineWidth: 2))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

struct BunnyHop {
    var squash: CGFloat = 1
    var lift: CGFloat = 0
}

// A puff of little hearts floating up (clock-driven, plays on each tap).
struct HeartPuff: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { ctx, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t < 1.1 else { return }
                let colors = [Color(hex: 0xFF5C9A), Color(hex: 0xFF8FB8), Color(hex: 0xC4A6FF), Color(hex: 0xFFB487)]
                for i in 0..<7 {
                    let seed = Double(i) * 1.7
                    let x = size.width * (0.2 + 0.6 * CGFloat((sin(seed * 3.1) + 1) / 2))
                    let rise = CGFloat(t / 1.1) * size.height * (0.35 + 0.15 * CGFloat(i % 3))
                    let y = size.height * 0.45 - rise
                    let r = size.width * (0.05 + 0.015 * CGFloat(i % 3))
                    var c = ctx
                    c.opacity = max(0, 1 - t / 1.1)
                    c.translateBy(x: x + CGFloat(sin(t * 6 + seed)) * 6, y: y)
                    c.fill(BunnyShapes.heart(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 1.8)), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            guard trigger > 0, !reduceMotion else { return }
            start = .now
            try? await Task.sleep(for: .seconds(1.15))
            start = nil
        }
    }
}

// MARK: - Scenes

// The scene behind your bunny: a soft gradient with a drifting pattern.
struct BunnySceneView: View {
    let scene: BunnyScene
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = animated && !reduceMotion && Motion.ambient
        ZStack {
            LinearGradient(colors: scene.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { timeline in
                let t = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
                Canvas { ctx, size in Self.motif(scene, &ctx, size, t) }
            }
        }
        .accessibilityHidden(true)
    }

    static func motif(_ scene: BunnyScene, _ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        let light = Color.white.opacity(scene == .night ? 0.85 : 0.5)
        switch scene {
        case .candy:
            let gap = max(w, h) / 9
            let shift = CGFloat((t * 8).truncatingRemainder(dividingBy: Double(gap)))
            var y = -gap
            var row = 0
            while y < h + gap {
                var x = (row % 2 == 0 ? 0 : gap / 2) - gap + shift
                while x < w + gap {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - gap * 0.13, y: y + shift - gap * 0.13, width: gap * 0.26, height: gap * 0.26)), with: .color(light))
                    x += gap
                }
                y += gap * 0.85
                row += 1
            }
        case .sky:
            for i in 0..<5 {
                let speed = 6 + Double(i) * 3
                let span = w * 1.6
                let x = CGFloat((t * speed + Double(i) * 97).truncatingRemainder(dividingBy: Double(span))) - w * 0.3
                let y = h * (0.12 + 0.18 * CGFloat(i))
                let s = w * (0.12 + 0.03 * CGFloat(i % 3))
                var cloud = Path()
                cloud.addEllipse(in: CGRect(x: x, y: y, width: s * 1.6, height: s * 0.7))
                cloud.addEllipse(in: CGRect(x: x + s * 0.3, y: y - s * 0.35, width: s * 0.8, height: s * 0.8))
                cloud.addEllipse(in: CGRect(x: x + s * 0.8, y: y - s * 0.2, width: s * 0.6, height: s * 0.6))
                ctx.fill(cloud, with: .color(.white.opacity(0.75)))
            }
        case .mint, .night:
            for i in 0..<14 {
                let seed = Double(i) * 12.9898
                let fx = CGFloat(abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1))
                let fy = CGFloat(abs(sin(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1))
                let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.2 + seed))
                let s = w * (0.025 + 0.02 * CGFloat(i % 3))
                var c = ctx
                c.opacity = twinkle
                c.fill(FourPointStar().path(in: CGRect(x: fx * w - s / 2, y: fy * h - s / 2, width: s, height: s)),
                       with: .color(scene == .night ? Color(hex: 0xFFF1A8) : .white))
            }
        case .sunset:
            for i in 0..<9 {
                let seed = Double(i) * 3.3
                let speed = 14 + Double(i % 3) * 6
                let y = h + 30 - CGFloat((t * speed + seed * 40).truncatingRemainder(dividingBy: Double(h + 60)))
                let x = w * CGFloat(0.08 + 0.105 * Double(i)) + CGFloat(sin(t + seed)) * 8
                let s = w * 0.05
                ctx.fill(BunnyShapes.heart(in: CGRect(x: x, y: y, width: s, height: s * 0.9)), with: .color(.white.opacity(0.55)))
            }
        case .lilac:
            let band = w / 6
            let shift = CGFloat((t * 6).truncatingRemainder(dividingBy: Double(band * 2)))
            var x = -band * 2 + shift
            while x < w + band {
                ctx.fill(Path(CGRect(x: x, y: 0, width: band, height: h)), with: .color(.white.opacity(0.22)))
                x += band * 2
            }
            var y = -band * 2 + shift
            while y < h + band {
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: band)), with: .color(.white.opacity(0.22)))
                y += band * 2
            }
        }
    }
}

// Your bunny standing in her scene (the maker's stage, and the picture you
// save or use as your profile picture).
struct BunnyPortrait: View {
    var look: BunnyLook
    var animated = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BunnySceneView(scene: look.scene, animated: animated)
                // A soft shadow under her feet.
                Ellipse().fill(.black.opacity(0.12))
                    .frame(width: geo.size.height * 0.36, height: geo.size.height * 0.05)
                    .offset(y: geo.size.height * 0.38)
                if animated {
                    BunnyBuddy(look: look, height: geo.size.height * 0.78)
                        .offset(y: geo.size.height * 0.02)
                } else {
                    BunnyFigure(look: look).frame(height: geo.size.height * 0.78).offset(y: geo.size.height * 0.02)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // A square picture of your bunny.
    @MainActor
    static func render(_ look: BunnyLook, side: CGFloat = 900) -> UIImage? {
        let renderer = ImageRenderer(content: BunnyPortrait(look: look, animated: false).frame(width: side, height: side))
        renderer.scale = 1
        return renderer.uiImage
    }
}
