import SwiftUI
import UIKit

// Your 3D avatar for Sugar World: skin colours per body block, a shirt and
// pants (pictures painted on a template), a face and up to two accessories.
// Saved on your profile as JSON in `avatar_look`; what you own is in
// `avatar_items`.

enum BodyPart: String, CaseIterable, Identifiable {
    case head = "Head", torso = "Torso", rightArm = "RightArm", leftArm = "LeftArm", rightLeg = "RightLeg", leftLeg = "LeftLeg"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .head: return "Head"
        case .torso: return "Body"
        case .rightArm: return "Right arm"
        case .leftArm: return "Left arm"
        case .rightLeg: return "Right leg"
        case .leftLeg: return "Left leg"
        }
    }
}

struct AvatarLook: Equatable, Hashable {
    var skin: [BodyPart: UInt32] = Dictionary(uniqueKeysWithValues: BodyPart.allCases.map { ($0, 0xF6D2B8) })
    var shirt = ""      // catalog id ("" = none)
    var shirtURL = ""   // its picture (built-in ones are drawn here)
    var pants = ""
    var pantsURL = ""
    var face = "cute"
    var hat = ""        // head accessory id
    var extra = ""      // back accessory id

    static let starter: AvatarLook = {
        var look = AvatarLook()
        look.shirt = "b:tee-pink"
        look.pants = "b:jeans"
        return look
    }()

    func color(_ part: BodyPart) -> UInt32 { skin[part] ?? 0xF6D2B8 }

    // MARK: saving

    var json: String {
        var out: [String: Any] = [
            "shirt": shirt, "shirt_url": shirtURL, "pants": pants, "pants_url": pantsURL,
            "face": face, "hat": hat, "extra": extra,
        ]
        for part in BodyPart.allCases { out["c_" + part.rawValue] = Int(color(part)) }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    init() {}

    init(json: String) {
        self = .starter
        guard let data = json.data(using: .utf8),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for part in BodyPart.allCases {
            if let n = raw["c_" + part.rawValue] as? Int { skin[part] = UInt32(truncatingIfNeeded: n) & 0xFFFFFF }
        }
        shirt = raw["shirt"] as? String ?? ""
        shirtURL = raw["shirt_url"] as? String ?? ""
        pants = raw["pants"] as? String ?? ""
        pantsURL = raw["pants_url"] as? String ?? ""
        face = raw["face"] as? String ?? "cute"
        hat = raw["hat"] as? String ?? ""
        extra = raw["extra"] as? String ?? ""
    }

    static let skinTones: [UInt32] = [
        0xFDE3D0, 0xF6D2B8, 0xEBB894, 0xD69E76, 0xB57A55, 0x8D5A3B, 0x5E3A26,
        0xFFB7CF, 0xF27BA3, 0xC9B6FF, 0x9F86F0, 0xA8E6CF, 0x5FD3B0, 0xA9D6FF,
        0x6FA8F5, 0xFFD6A5, 0xFFE58A, 0xFFFFFF, 0xB8B8C8, 0x3B3B4F,
    ]
}

extension UserProfile {
    var avatar: AvatarLook { avatarLook.isEmpty ? .starter : AvatarLook(json: avatarLook) }
}

// MARK: - catalog items

struct CatalogItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case shirt, pants, hat, back, face
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shirt: return "Shirts"
            case .pants: return "Pants"
            case .hat: return "Hats"
            case .back: return "Back"
            case .face: return "Faces"
            }
        }
        var icon: String {
            switch self {
            case .shirt: return "tshirt.fill"
            case .pants: return "figure.walk"
            case .hat: return "crown.fill"
            case .back: return "bag.fill"
            case .face: return "face.smiling.inverse"
            }
        }
        var paintable: Bool { self == .shirt || self == .pants }
    }

    var id: String
    var name: String
    var kind: Kind
    var price: Int
    var imageURL = ""        // shirts and pants made by people
    var creatorEmail = ""    // "" = made by Sugerly
    var creatorName = ""
    var sales = 0
    var created = ""
    var onSale = true

    // Sugerly's own things have ids like "b:jeans", "h:bow", "f:wink".
    var builtIn: Bool { id.contains(":") }

    init(id: String, name: String, kind: Kind, price: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.price = price
    }

    init?(_ d: Doc) {
        guard let kind = Kind(rawValue: d.str("kind")), kind.paintable else { return nil }
        id = d.str("id")
        name = d.str("name")
        self.kind = kind
        price = max(0, d.int("price"))
        imageURL = d.str("image_url")
        creatorEmail = d.str("creator_email").lowercased()
        creatorName = d.str("creator_name")
        sales = d.int("sales")
        created = d.str("created_date")
        onSale = d["on_sale"] as? Bool ?? true
        guard !id.isEmpty, !imageURL.isEmpty else { return nil }
    }

    // What Sugerly sells itself (drawn in code, so nothing to download).
    static let builtIns: [CatalogItem] = [
        CatalogItem(id: "b:tee-pink", name: "Pink heart tee", kind: .shirt, price: 0),
        CatalogItem(id: "b:hoodie-lav", name: "Mimi hoodie", kind: .shirt, price: 120),
        CatalogItem(id: "b:stripes", name: "Sailor stripes", kind: .shirt, price: 40),
        CatalogItem(id: "b:stars", name: "Star sweater", kind: .shirt, price: 75),
        CatalogItem(id: "b:mint-dress", name: "Mint top", kind: .shirt, price: 30),
        CatalogItem(id: "b:jeans", name: "Blue jeans", kind: .pants, price: 0),
        CatalogItem(id: "b:shorts-pink", name: "Pink shorts", kind: .pants, price: 25),
        CatalogItem(id: "b:clouds", name: "Cloud pants", kind: .pants, price: 60),
        CatalogItem(id: "b:overalls", name: "Peach overalls", kind: .pants, price: 90),
        CatalogItem(id: "b:leggings", name: "Night leggings", kind: .pants, price: 35),
        CatalogItem(id: "h:bunny", name: "Bunny ears", kind: .hat, price: 50),
        CatalogItem(id: "h:cat", name: "Cat ears", kind: .hat, price: 50),
        CatalogItem(id: "h:bow", name: "Big bow", kind: .hat, price: 25),
        CatalogItem(id: "h:crown", name: "Candy crown", kind: .hat, price: 200),
        CatalogItem(id: "h:cap", name: "Comfy cap", kind: .hat, price: 40),
        CatalogItem(id: "h:halo", name: "Halo", kind: .hat, price: 120),
        CatalogItem(id: "h:phones", name: "Headphones", kind: .hat, price: 80),
        CatalogItem(id: "h:flower", name: "Daisy", kind: .hat, price: 20),
        CatalogItem(id: "x:wings", name: "Fairy wings", kind: .back, price: 250),
        CatalogItem(id: "x:backpack", name: "Bunny backpack", kind: .back, price: 60),
        CatalogItem(id: "x:cape", name: "Hero cape", kind: .back, price: 90),
        CatalogItem(id: "f:cute", name: "Cute", kind: .face, price: 0),
        CatalogItem(id: "f:smile", name: "Smile", kind: .face, price: 0),
        CatalogItem(id: "f:wink", name: "Wink", kind: .face, price: 15),
        CatalogItem(id: "f:sleepy", name: "Sleepy", kind: .face, price: 15),
        CatalogItem(id: "f:wow", name: "Wow", kind: .face, price: 15),
        CatalogItem(id: "f:love", name: "In love", kind: .face, price: 40),
        CatalogItem(id: "f:cat", name: "Kitty", kind: .face, price: 25),
        CatalogItem(id: "f:cool", name: "Cool shades", kind: .face, price: 60),
    ]

    static func builtIn(_ id: String) -> CatalogItem? { builtIns.first { $0.id == id } }

    // The id the look stores for faces / hats / back items.
    var lookValue: String { kind == .face ? String(id.dropFirst(2)) : id }
}

// MARK: - the clothes template

// One picture (1024 × 1024) holds a whole shirt or pair of pants. Each body
// block is unfolded like a box: its four sides in a row (right side, front,
// left side, back), the top above the front and the bottom below it.
// Shirts paint the body and both arms; pants the body (under the shirt) and
// both legs.
enum ClothTemplate {
    static let side: CGFloat = 1024
    static let unit: CGFloat = 128  // pixels per body unit

    enum Face: String, CaseIterable { case right, front, left, back, top, bottom }

    struct Block {
        let x: CGFloat, y: CGFloat      // where it starts, in units
        let w: CGFloat, h: CGFloat, d: CGFloat
        var width: CGFloat { 2 * d + 2 * w }
        var height: CGFloat { 2 * d + h }

        // A face inside the block, in units from the block's corner.
        func local(_ face: Face) -> CGRect {
            switch face {
            case .right: return CGRect(x: 0, y: d, width: d, height: h)
            case .front: return CGRect(x: d, y: d, width: w, height: h)
            case .left: return CGRect(x: d + w, y: d, width: d, height: h)
            case .back: return CGRect(x: 2 * d + w, y: d, width: w, height: h)
            case .top: return CGRect(x: d, y: 0, width: w, height: d)
            case .bottom: return CGRect(x: d, y: d + h, width: w, height: d)
            }
        }

        // A face on the template, in pixels.
        func rect(_ face: Face) -> CGRect {
            let r = local(face)
            return CGRect(x: (x + r.minX) * unit, y: (y + r.minY) * unit, width: r.width * unit, height: r.height * unit)
        }

        // The whole block on the template, in pixels.
        var frame: CGRect { CGRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit) }
    }

    static let body = Block(x: 1, y: 0, w: 2, h: 2, d: 1)
    static let rightLimb = Block(x: 0, y: 4, w: 1, h: 2, d: 1)
    static let leftLimb = Block(x: 4, y: 4, w: 1, h: 2, d: 1)
    static let blocks: [(String, Block)] = [("body", body), ("right", rightLimb), ("left", leftLimb)]

    // Which block of a shirt / pants picture dresses a body part.
    static func block(for part: BodyPart) -> Block? {
        switch part {
        case .torso: return body
        case .rightArm, .rightLeg: return rightLimb
        case .leftArm, .leftLeg: return leftLimb
        case .head: return nil
        }
    }

    // Every face of every block, for tapping and drawing guides.
    static var allFaces: [(block: String, face: Face, rect: CGRect)] {
        var out: [(block: String, face: Face, rect: CGRect)] = []
        for (name, block) in blocks {
            for face in Face.allCases { out.append((block: name, face: face, rect: block.rect(face))) }
        }
        return out
    }

    static func faceName(_ face: Face) -> String {
        switch face {
        case .right, .left: return "SIDE"
        default: return face.rawValue.uppercased()
        }
    }

    static func blockName(_ block: String, kind: CatalogItem.Kind) -> String {
        switch block {
        case "body": return "BODY"
        case "right": return kind == .pants ? "RIGHT LEG" : "RIGHT ARM"
        default: return kind == .pants ? "LEFT LEG" : "LEFT ARM"
        }
    }

    // The faint guide lines and names drawn under your painting (never saved
    // into the clothes).
    static func guides(kind: CatalogItem.Kind, dark: Bool = false) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let line = UIColor(white: dark ? 1 : 0, alpha: 0.28)
            let label = UIColor(white: dark ? 1 : 0, alpha: 0.32)
            for (name, block) in blocks {
                for face in Face.allCases {
                    let r = block.rect(face)
                    cg.setStrokeColor(line.cgColor)
                    cg.setLineWidth(3)
                    cg.setLineDash(phase: 0, lengths: [14, 10])
                    cg.stroke(r.insetBy(dx: 1.5, dy: 1.5))
                    let text = faceName(face) as NSString
                    let font = UIFont.systemFont(ofSize: face == .top || face == .bottom ? 22 : 26, weight: .heavy)
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: label]
                    let size = text.size(withAttributes: attrs)
                    text.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
                }
                let title = blockName(name, kind: kind) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30, weight: .black), .foregroundColor: label]
                let top = block.rect(.top)
                title.draw(at: CGPoint(x: top.maxX + 18, y: top.minY + 18), withAttributes: attrs)
            }
        }
    }
}

// MARK: - Sugerly's own clothes, drawn in code

enum BuiltInClothes {
    static func image(_ id: String) -> UIImage? {
        if let hit = cache[id] { return hit }
        guard let made = draw(id) else { return nil }
        cache[id] = made
        return made
    }

    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    private static func draw(_ id: String) -> UIImage? {
        let size = CGSize(width: ClothTemplate.side, height: ClothTemplate.side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let T = ClothTemplate.self
        let limbs = [T.rightLimb, T.leftLimb]
        func fill(_ r: CGRect, _ hex: UInt32, _ cg: CGContext) {
            cg.setFillColor(UIColor(hex: hex).cgColor)
            cg.fill(r)
        }
        // The upper part of each side of a limb (sleeves) or lower part of the body.
        func band(_ block: ClothTemplate.Block, from: CGFloat, to: CGFloat, _ hex: UInt32, _ cg: CGContext, top: Bool = false, bottom: Bool = false) {
            for face in [ClothTemplate.Face.right, .front, .left, .back] {
                let r = block.rect(face)
                fill(CGRect(x: r.minX, y: r.minY + r.height * from, width: r.width, height: r.height * (to - from)), hex, cg)
            }
            if top { fill(block.rect(.top), hex, cg) }
            if bottom { fill(block.rect(.bottom), hex, cg) }
        }
        func wholeBlock(_ block: ClothTemplate.Block, _ hex: UInt32, _ cg: CGContext) {
            for face in ClothTemplate.Face.allCases { fill(block.rect(face), hex, cg) }
        }
        func heart(in r: CGRect, _ hex: UInt32, _ cg: CGContext) {
            let s = min(r.width, r.height)
            let c = CGPoint(x: r.midX, y: r.midY)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: c.x, y: c.y + s * 0.32))
            p.addCurve(to: CGPoint(x: c.x - s * 0.42, y: c.y - s * 0.12), controlPoint1: CGPoint(x: c.x - s * 0.18, y: c.y + s * 0.16), controlPoint2: CGPoint(x: c.x - s * 0.42, y: c.y + s * 0.08))
            p.addArc(withCenter: CGPoint(x: c.x - s * 0.21, y: c.y - s * 0.14), radius: s * 0.21, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addArc(withCenter: CGPoint(x: c.x + s * 0.21, y: c.y - s * 0.14), radius: s * 0.21, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.32), controlPoint1: CGPoint(x: c.x + s * 0.42, y: c.y + s * 0.08), controlPoint2: CGPoint(x: c.x + s * 0.18, y: c.y + s * 0.16))
            cg.setFillColor(UIColor(hex: hex).cgColor)
            cg.addPath(p.cgPath)
            cg.fillPath()
        }
        func star(at c: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ cg: CGContext) {
            let p = UIBezierPath()
            for i in 0..<10 {
                let a = CGFloat(i) * .pi / 5 - .pi / 2
                let r = i % 2 == 0 ? radius : radius * 0.45
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.close()
            cg.setFillColor(UIColor(hex: hex).cgColor)
            cg.addPath(p.cgPath)
            cg.fillPath()
        }
        func stripes(_ r: CGRect, _ a: UInt32, _ b: UInt32, _ cg: CGContext, every: CGFloat = 32) {
            var y = r.minY
            var on = true
            while y < r.maxY {
                fill(CGRect(x: r.minX, y: y, width: r.width, height: min(every, r.maxY - y)), on ? a : b, cg)
                y += every
                on.toggle()
            }
        }
        func cloud(at c: CGPoint, _ s: CGFloat, _ cg: CGContext) {
            cg.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            for (dx, dy, r) in [(-0.5, 0.1, 0.32), (0, -0.12, 0.42), (0.5, 0.1, 0.3), (0.05, 0.2, 0.34)] as [(CGFloat, CGFloat, CGFloat)] {
                cg.fillEllipse(in: CGRect(x: c.x + dx * s - r * s, y: c.y + dy * s - r * s, width: 2 * r * s, height: 2 * r * s))
            }
        }

        switch id {
        case "b:tee-pink":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                wholeBlock(T.body, 0xF7A1C4, cg)
                for limb in limbs { band(limb, from: 0, to: 0.38, 0xF7A1C4, cg, top: true) }
                for limb in limbs { band(limb, from: 0.33, to: 0.38, 0xE8789F, cg) }
                heart(in: T.body.rect(.front).insetBy(dx: 70, dy: 70), 0xFFFFFF, cg)
                fill(CGRect(x: T.body.rect(.front).minX, y: T.body.rect(.front).maxY - 14, width: 256, height: 14), 0xE8789F, cg)
            }
        case "b:hoodie-lav":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                wholeBlock(T.body, 0xB9A4FF, cg)
                for limb in limbs { band(limb, from: 0, to: 1, 0xB9A4FF, cg, top: true, bottom: true) }
                for limb in limbs { band(limb, from: 0.88, to: 1, 0x9C84F2, cg) }
                let front = T.body.rect(.front)
                fill(CGRect(x: front.minX + 48, y: front.maxY - 92, width: front.width - 96, height: 64), 0x9C84F2, cg)
                if let mimi = UIImage(named: "MimiLavender") {
                    let h: CGFloat = 132
                    let w = h * mimi.size.width / max(mimi.size.height, 1)
                    mimi.draw(in: CGRect(x: front.midX - w / 2, y: front.minY + 22, width: w, height: h))
                }
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(8)
                cg.setLineCap(.round)
                cg.move(to: CGPoint(x: front.midX - 30, y: front.minY + 4)); cg.addLine(to: CGPoint(x: front.midX - 30, y: front.minY + 60))
                cg.move(to: CGPoint(x: front.midX + 30, y: front.minY + 4)); cg.addLine(to: CGPoint(x: front.midX + 30, y: front.minY + 60))
                cg.strokePath()
            }
        case "b:stripes":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                for face in ClothTemplate.Face.allCases { stripes(T.body.rect(face), 0x2F4A8A, 0xFFFFFF, cg) }
                for limb in limbs {
                    for face in [ClothTemplate.Face.right, .front, .left, .back] {
                        let r = limb.rect(face)
                        stripes(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.4), 0x2F4A8A, 0xFFFFFF, cg)
                    }
                    fill(limb.rect(.top), 0x2F4A8A, cg)
                }
                let front = T.body.rect(.front)
                cg.setFillColor(UIColor(hex: 0xF25C7A).cgColor)
                cg.fillEllipse(in: CGRect(x: front.midX - 22, y: front.minY + 30, width: 44, height: 44))
            }
        case "b:stars":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                wholeBlock(T.body, 0xFFD966, cg)
                for limb in limbs { band(limb, from: 0, to: 1, 0xFFD966, cg, top: true, bottom: true) }
                for (block, faces) in [(T.body, ClothTemplate.Face.allCases)] {
                    for face in faces {
                        let r = block.rect(face)
                        var i = 0
                        for y in stride(from: r.minY + 40, to: r.maxY, by: 80) {
                            for x in stride(from: r.minX + (i % 2 == 0 ? 36 : 76), to: r.maxX, by: 80) {
                                star(at: CGPoint(x: x, y: y), 20, 0xFFFFFF, cg)
                            }
                            i += 1
                        }
                    }
                }
                star(at: CGPoint(x: T.body.rect(.front).midX, y: T.body.rect(.front).midY), 70, 0xF59E0B, cg)
                for limb in limbs { band(limb, from: 0.86, to: 1, 0xF59E0B, cg) }
            }
        case "b:mint-dress":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                wholeBlock(T.body, 0x8EE3C8, cg)
                for limb in limbs { band(limb, from: 0, to: 0.22, 0x8EE3C8, cg, top: true) }
                let front = T.body.rect(.front)
                for i in 0..<4 {
                    cg.setFillColor(UIColor.white.cgColor)
                    cg.fillEllipse(in: CGRect(x: front.midX - 9, y: front.minY + 30 + CGFloat(i) * 52, width: 18, height: 18))
                }
                fill(CGRect(x: front.minX, y: front.minY + 150, width: front.width, height: 16), 0x3FB58F, cg)
            }
        case "b:jeans":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                band(T.body, from: 0.78, to: 1, 0x4A78C2, cg, bottom: true)
                band(T.body, from: 0.78, to: 0.86, 0x3A5E9C, cg)
                for limb in limbs {
                    band(limb, from: 0, to: 1, 0x5C8BD6, cg, top: true, bottom: true)
                    band(limb, from: 0.92, to: 1, 0x3A5E9C, cg)
                    let f = limb.rect(.front)
                    cg.setStrokeColor(UIColor(hex: 0xF2C14E).cgColor)
                    cg.setLineWidth(4)
                    cg.setLineDash(phase: 0, lengths: [10, 8])
                    cg.move(to: CGPoint(x: f.minX + 18, y: f.minY)); cg.addLine(to: CGPoint(x: f.minX + 18, y: f.maxY))
                    cg.strokePath()
                }
            }
        case "b:shorts-pink":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                band(T.body, from: 0.78, to: 1, 0xF27BA3, cg, bottom: true)
                for limb in limbs {
                    band(limb, from: 0, to: 0.42, 0xF7A1C4, cg, top: true)
                    band(limb, from: 0.36, to: 0.42, 0xE0508A, cg)
                }
            }
        case "b:clouds":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                band(T.body, from: 0.75, to: 1, 0x8CC8FF, cg, bottom: true)
                for limb in limbs {
                    band(limb, from: 0, to: 1, 0x8CC8FF, cg, top: true, bottom: true)
                    for face in [ClothTemplate.Face.right, .front, .left, .back] {
                        let r = limb.rect(face)
                        cloud(at: CGPoint(x: r.midX, y: r.minY + r.height * 0.3), 46, cg)
                        cloud(at: CGPoint(x: r.midX + 10, y: r.minY + r.height * 0.72), 40, cg)
                    }
                }
            }
        case "b:overalls":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                band(T.body, from: 0.55, to: 1, 0xFFB38A, cg, bottom: true)
                let front = T.body.rect(.front), back = T.body.rect(.back)
                fill(CGRect(x: front.minX + 40, y: front.minY + 60, width: front.width - 80, height: front.height * 0.6), 0xFFB38A, cg)
                for r in [front, back] {
                    fill(CGRect(x: r.minX + 40, y: r.minY, width: 24, height: r.height * 0.6), 0xF08C5A, cg)
                    fill(CGRect(x: r.maxX - 64, y: r.minY, width: 24, height: r.height * 0.6), 0xF08C5A, cg)
                }
                fill(T.body.rect(.top).insetBy(dx: 40, dy: 0).divided(atDistance: 24, from: .minXEdge).slice, 0xF08C5A, cg)
                heart(in: CGRect(x: front.midX - 40, y: front.minY + 100, width: 80, height: 80), 0xFFFFFF, cg)
                for limb in limbs { band(limb, from: 0, to: 1, 0xFFB38A, cg, top: true, bottom: true); band(limb, from: 0.85, to: 1, 0xF08C5A, cg) }
            }
        case "b:leggings":
            return renderer.image { ctx in
                let cg = ctx.cgContext
                band(T.body, from: 0.8, to: 1, 0x2E2A4A, cg, bottom: true)
                for limb in limbs {
                    band(limb, from: 0, to: 1, 0x3B3560, cg, top: true, bottom: true)
                    for face in [ClothTemplate.Face.right, .left] {
                        let r = limb.rect(face)
                        fill(CGRect(x: r.midX - 6, y: r.minY, width: 12, height: r.height), 0xB9A4FF, cg)
                    }
                }
            }
        default:
            return nil
        }
    }
}

// Clothes pictures, downloaded once and kept while the app is open.
@MainActor
enum ClothStore {
    private static var memory: [String: UIImage] = [:]
    private static var loading: [String: Task<UIImage?, Never>] = [:]

    static func image(id: String, url: String) async -> UIImage? {
        if id.isEmpty { return nil }
        if id.hasPrefix("b:") { return BuiltInClothes.image(id) }
        guard !url.isEmpty else { return nil }
        if let hit = memory[url] { return hit }
        if let running = loading[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            guard let u = URL(string: url), let result = try? await URLSession.shared.data(from: u) else { return nil }
            return UIImage(data: result.0)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { memory[url] = image }
        return image
    }

    static func remember(_ image: UIImage, url: String) { memory[url] = image }
}
