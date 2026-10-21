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
    case fur, bow, collar, outfit, accessory
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
        case .outfit, .accessory:
            // Clothes are made of differently coloured pieces, so an outfit
            // colour is a target hue each piece is turned to (see BunnyPiece).
            // Picture clothes and accessories are dyed with the swatch
            // instead (see BunnyItemLayer).
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

struct BunnyClothingLayer: Codable, Equatable, Identifiable {
    var id: String
    var x: Double = 0
    var y: Double = 0
    var rotation: Double = 0
}

struct BunnyLook: Codable, Equatable {
    var fur = 0
    var bodyItem = ""
    var faceItem = ""
    var collarItem = ""
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
    // The accessory's colour (picture clothes use the outfit colour).
    var accessory = 0
    var clothesLayers: [BunnyClothingLayer]? = nil
    var headLayers: [BunnyClothingLayer]? = nil
    var customColors: [String: UInt32] = [:]

    func layers(_ slot: BunnySlot) -> [BunnyClothingLayer] {
        if slot == .top {
            return clothesLayers ?? (wear.isEmpty ? (top == .none ? [] : [.init(id: "classic:" + top.rawValue)]) : [.init(id: wear)])
        }
        return headLayers ?? (head.isEmpty ? (bowOn ? [.init(id: "classic:bow")] : []) : [.init(id: head)])
    }

    mutating func setLayers(_ layers: [BunnyClothingLayer], _ slot: BunnySlot) {
        let bounded = Array(layers.prefix(3))
        if slot == .top { clothesLayers = bounded; wear = ""; top = .none }
        else { headLayers = bounded; head = ""; bowOn = false }
    }


    func tint(_ part: BunnyPart) -> BunnyTint {
        if let hex = customColors[part.rawValue] {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(Color(hex: hex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return BunnyTint(name: "Custom", hue: Double(h) * 360, saturation: Double(s), brightness: Double(b) - 0.85, swatch: hex)
        }
        let list = part.tints
        return list[max(0, min(list.count - 1, index(part)))]
    }

    func index(_ part: BunnyPart) -> Int {
        switch part {
        case .fur: return fur
        case .bow: return bow
        case .collar: return collar
        case .outfit: return outfit
        case .accessory: return accessory
        }
    }

    mutating func set(_ part: BunnyPart, _ value: Int) {
        customColors[part.rawValue] = nil
        switch part {
        case .fur: fur = value
        case .bow: bow = value
        case .collar: collar = value
        case .outfit: outfit = value
        case .accessory: accessory = value
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
        bodyItem = (try? c.decodeIfPresent(String.self, forKey: .bodyItem)) ?? ""
        faceItem = (try? c.decodeIfPresent(String.self, forKey: .faceItem)) ?? ""
        collarItem = (try? c.decodeIfPresent(String.self, forKey: .collarItem)) ?? ""
        bowOn = (try? c.decodeIfPresent(Bool.self, forKey: .bowOn)) ?? bowOn
        bow = (try? c.decodeIfPresent(Int.self, forKey: .bow)) ?? bow
        collar = (try? c.decodeIfPresent(Int.self, forKey: .collar)) ?? collar
        outfit = (try? c.decodeIfPresent(Int.self, forKey: .outfit)) ?? outfit
        top = (try? c.decodeIfPresent(BunnyTop.self, forKey: .top)) ?? top
        face = (try? c.decodeIfPresent(BunnyFace.self, forKey: .face)) ?? face
        scene = (try? c.decodeIfPresent(BunnyScene.self, forKey: .scene)) ?? scene
        wear = (try? c.decodeIfPresent(String.self, forKey: .wear)) ?? wear
        head = (try? c.decodeIfPresent(String.self, forKey: .head)) ?? head
        accessory = (try? c.decodeIfPresent(Int.self, forKey: .accessory)) ?? accessory
        clothesLayers = (try? c.decodeIfPresent([BunnyClothingLayer].self, forKey: .clothesLayers)).map { Array($0.prefix(3)) }
        headLayers = (try? c.decodeIfPresent([BunnyClothingLayer].self, forKey: .headLayers)).map { Array($0.prefix(3)) }
        customColors = (try? c.decodeIfPresent([String: UInt32].self, forKey: .customColors)) ?? [:]
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
            BunnySnapshots.warm(saved)
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
        if name == "BunnyBodyCatFur" || name == "BunnyBodyCatInk" {
            return catLayer(ink: name == "BunnyBodyCatInk")
        }
        guard let full = UIImage(named: name) else { return UIImage() }
        return full.preparingThumbnail(of: pixels) ?? full
    }

    // The short-eared cat was supplied as one finished picture. Separate
    // its dark ink at decode time so fur uses the bunny's exact colour path.
    // This runs once per cached layer, never while animating the figure.
    nonisolated private static func catLayer(ink: Bool) -> UIImage {
        guard let source = UIImage(named: "BunnyBodyCat"),
              let image = (source.preparingThumbnail(of: pixels) ?? source).cgImage else { return UIImage() }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let output: CGImage? = bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags),
                  let pixels = storage.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            for i in stride(from: 0, to: width * height * 4, by: 4) {
                let alpha = Int(pixels[i + 3])
                let isInk = max(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])) * 100 < alpha * 68
                if alpha == 0 || isInk != ink {
                    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
                }
            }
            return context.makeImage()
        }
        return output.map { UIImage(cgImage: $0) } ?? UIImage()
    }

    static func prepare(_ look: BunnyLook) async {
        var names = ["BunnyFur", "BunnyOutline", "BunnyBow", "BunnyCollar", look.face.image, look.face.eyes]
        names += BunnyTop.allCases.compactMap { $0.piece?.rawValue }
        names += BunnyCatalog.shared.all.flatMap { [$0.asset, $0.outlineAsset] }.filter { !$0.isEmpty }
        let missing = names.filter { cache[$0] == nil }
        let ready = await Task.detached(priority: .userInitiated) {
            missing.map { ($0, load($0)) }
        }.value
        for (name, image) in ready { cache[name] = image }
        let ids = [look.bodyItem, look.faceItem, look.collarItem] + look.layers(.top).map(\.id) + look.layers(.head).map(\.id)
        for id in ids {
            if let item = BunnyCatalog.shared.item(id), !item.url.isEmpty { await BunnyRemoteImages.shared.fetch(item.url) }
        }
    }

    static func warmUp(_ look: BunnyLook = BunnyLook()) {
        var names = ["BunnyFur", "BunnyOutline", "BunnyBow", "BunnyCollar", look.face.image, look.face.eyes]
        if let piece = look.top.piece { names.append(piece.rawValue) }
        if let body = BunnyItem.builtIn.first(where: { $0.id == look.bodyItem }) {
            names += [body.asset, body.outlineAsset].filter { !$0.isEmpty }
        }
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
        GeometryReader { geometry in
            ZStack {
                if let item = BunnyCatalog.shared.item(look.bodyItem) {
                    BunnyItemLayer(item: item, tint: look.tint(.fur))
                } else {
                    BunnyLayer("BunnyFur", look.tint(.fur))
                    BunnyImages.image("BunnyOutline").resizable().interpolation(.high)
                }
                clothing(.top, size: geometry.size)
                if let item = BunnyCatalog.shared.item(look.faceItem) {
                    BunnyItemLayer(item: item)
                } else {
                    BunnyImages.image(look.face.image).resizable().interpolation(.high)
                    BunnyImages.image(look.face.eyes).resizable().interpolation(.high)
                }
                if let item = BunnyCatalog.shared.item(look.collarItem) {
                    BunnyItemLayer(item: item, tint: look.tint(.collar))
                }
                clothing(.head, size: geometry.size)
            }
        }
        .aspectRatio(BunnyArt.aspect, contentMode: .fit)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
    private func clothing(_ slot: BunnySlot, size: CGSize) -> some View {
        ForEach(look.layers(slot)) { layer in
            ZStack {
                if layer.id == "classic:bow" {
                    BunnyLayer("BunnyBow", look.tint(.bow))
                } else if layer.id.hasPrefix("classic:"), let top = BunnyTop(rawValue: String(layer.id.dropFirst(8))) {
                    if let piece = top.piece { BunnyLayer(piece, look.tint(.outfit)) }
                    if top == .sailor { BunnyLayer("BunnyCollar", look.tint(.collar)) }
                } else if let item = BunnyCatalog.shared.item(layer.id) {
                    BunnyItemLayer(item: item, tint: look.tint(slot == .top ? .outfit : .accessory))
                }
            }
            .rotationEffect(.degrees(layer.rotation))
            .offset(x: layer.x * size.width, y: layer.y * size.height)
        }
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
        ZStack(alignment: .bottom) {
            BunnySceneView(scene: look.scene, animated: false)
                .allowsHitTesting(false)
            BunnyBuddy(look: look, height: height * 0.8, lively: lively)
                .padding(.bottom, height * 0.04)
        }
        .modifier(BunnyTileFrame(height: height))
    }
}

// The tile's shape, edge and shadow.
private struct BunnyTileFrame: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        let tile = RoundedRectangle(cornerRadius: height * 0.24, style: .continuous)
        content
            .frame(width: height * 0.9, height: height)
            .clipShape(tile)
            .overlay(tile.strokeBorder(.white.opacity(0.75), lineWidth: 2))
            .softShadow(.black.opacity(0.08), radius: 6, y: 3)
    }
}

// The same tile as one still picture, made once per look and size and kept
// (the menu shows this: one picture is far lighter than her layers while it
// slides and scrolls). Show her static layers immediately on a cache miss.
struct BunnyStillTile: View {
    var look: BunnyLook
    var height: CGFloat = 76
    @Environment(\.displayScale) private var scale
    @State private var made: (key: String, image: UIImage)?

    var body: some View {
        let key = BunnySnapshots.key(look, height)
        let image = made?.key == key ? made?.image : BunnySnapshots.cached(key)
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                ZStack(alignment: .bottom) {
                    BunnySceneView(scene: look.scene, animated: false)
                    BunnyFigure(look: look)
                        .frame(height: height * 0.8)
                        .padding(.bottom, height * 0.04)
                }
                .transaction { $0.animation = nil }
            }
        }
        .modifier(BunnyTileFrame(height: height))
        .task(id: key) {
            BunnySnapshots.scale = scale
            guard BunnySnapshots.cached(key) == nil else { return }
            guard !Task.isCancelled, let fresh = BunnySnapshots.make(look, height) else { return }
            made = (key, fresh)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
enum BunnySnapshots {
    static var scale: CGFloat = 3
    private static var cache: [String: UIImage] = [:]

    static func key(_ look: BunnyLook, _ height: CGFloat) -> String {
        let data = (try? JSONEncoder().encode(look)) ?? Data()
        // Uploaded items count once their picture has arrived.
        return "\(Theme.mainHex)-\(Theme.lightHex)-\(UITraitCollection.current.userInterfaceStyle.rawValue)-\(Int(height))-\(BunnyRemoteImages.shared.images.count)-" + data.base64EncodedString()
    }

    static func cached(_ key: String) -> UIImage? { cache[key] }

    @discardableResult
    static func make(_ look: BunnyLook, _ height: CGFloat) -> UIImage? {
        let key = key(look, height)
        if let hit = cache[key] { return hit }
        let art = ZStack(alignment: .bottom) {
            BunnySceneView(scene: look.scene, animated: false)
            BunnyFigure(look: look).frame(height: height * 0.8).padding(.bottom, height * 0.04)
        }
        .frame(width: height * 0.9, height: height)
        let renderer = ImageRenderer(content: art)
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        if cache.count > 16 { cache.removeAll() }
        cache[key] = image
        return image
    }

    // Prepare the small still before the drawer is opened.
    static func warm(_ look: BunnyLook) {
        make(look, 76)
    }
}

struct BunnyHop {
    var squash: CGFloat = 1
    var lift: CGFloat = 0
}

// A puff of the artist's little gem hearts (and two gem sparkles) floating
// up when you tap her (clock-driven, plays on each tap). Each one has its own
// column and they all sway together, so none of them ever touch; each pops
// in, rises at its own pace and fades.
struct HeartPuff: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { ctx, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t < 1.2 else { return }
                let heart = ctx.resolve(Image("MimiHeart"))
                let sparkle = ctx.resolve(Image("MimiSparkle"))
                let count = 5
                let column = size.width / CGFloat(count)
                let sway = CGFloat(sin(t * 5)) * column * 0.05
                for i in 0..<count {
                    let seed = Double(i) * 1.7
                    // A small stagger, so they leave one after another.
                    let local = t - Double(i) * 0.035
                    guard local > 0 else { continue }
                    // At most 0.7 of a column wide, even when tilted.
                    let r = column * (i % 2 == 0 ? 0.28 : 0.24)
                    let x = column * (CGFloat(i) + 0.5) + sway
                    let rise = CGFloat(local / 1.2) * size.height * (0.35 + 0.15 * CGFloat(i % 3))
                    let y = size.height * 0.32 - rise
                    let pop = CGFloat(min(1, local / 0.16))
                    var c = ctx
                    c.opacity = max(0, 1 - local / 1.2)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(sin(seed * 2.3) * 12 + sin(local * 5 + seed) * 4))
                    c.scaleBy(x: pop, y: pop)
                    if i == 1 || i == 3 {
                        c.draw(sparkle, in: CGRect(x: -r * 0.8, y: -r * 0.9, width: r * 1.6, height: r * 1.8))
                    } else {
                        c.draw(heart, in: CGRect(x: -r, y: -r * 0.84, width: r * 2, height: r * 1.68))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            guard trigger > 0, !reduceMotion else { return }
            start = .now
            try? await Task.sleep(for: .seconds(1.45))
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
            LinearGradient(colors: [Palette.surface, Theme.soft, Theme.main.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            // The same fluffy clouds as the Clouds background, drifting
            // right at their own speeds. Each has its own band of the sky
            // (a cloud is about 0.6 of its width tall, so it's sized to fit
            // with room to spare), so they never touch; each one leaves the
            // tile completely before it comes back on the other side.
            let style = CloudArt.Style(fill: .white, shade: Color(hex: 0x8FB6F0).opacity(0.5))
            let clouds: [(size: CGFloat, start: CGFloat, speed: Double)] = [
                (0.42, 0.12, 5), (0.3, 0.64, 3.4), (0.36, 0.32, 4.2), (0.26, 0.86, 3),
            ]
            let band = h / CGFloat(clouds.count)
            for (i, cloud) in clouds.enumerated() {
                let cw = min(w * cloud.size, band * 1.25)
                let top = band * CGFloat(i) + (band - cw * 0.6) / 2
                let span = w + cw * 1.2
                let x = (cloud.start * span + CGFloat(t * cloud.speed)).truncatingRemainder(dividingBy: span) - cw * 0.6
                CloudArt.draw(&ctx, center: CGPoint(x: x, y: top + cw * 0.36), width: cw, style: style)
            }
        case .mint, .night:
            // One star per cell of a 4 × 4 grid (two cells left empty),
            // nudged a little inside its cell and never past it, so no two
            // stars ever touch. They only fade, they don't grow.
            let cellW = w / 4, cellH = h / 4
            let cell = min(cellW, cellH)
            for i in 0..<16 where i != 5 && i != 10 {
                let seed = Double(i) * 12.9898
                let fx = CGFloat(abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1))
                let fy = CGFloat(abs(sin(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1))
                let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.2 + seed))
                let s = cell * (0.2 + 0.1 * CGFloat(i % 3))
                let cx = (CGFloat(i % 4) + 0.5 + (fx - 0.5) * 0.5) * cellW
                let cy = (CGFloat(i / 4) + 0.5 + (fy - 0.5) * 0.5) * cellH
                var c = ctx
                c.opacity = twinkle
                c.fill(FourPointStar().path(in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)),
                       with: .color(scene == .night ? Color(hex: 0xFFF1A8) : .white))
            }
        case .sunset:
            for i in 0..<9 {
                let seed = Double(i) * 3.3
                let speed = 14 + Double(i % 3) * 6
                let y = h + 30 - CGFloat((t * speed + seed * 40).truncatingRemainder(dividingBy: Double(h + 60)))
                // Each in its own column, all swaying together (so they keep
                // their distance).
                let x = w * CGFloat(0.08 + 0.105 * Double(i)) + CGFloat(sin(t)) * 8
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
