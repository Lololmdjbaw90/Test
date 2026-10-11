import SwiftUI
import UIKit

// Your 3D avatar for Sugar World: a skin colour per body block, plus a shirt
// and pants that people make from the template and sell in the catalog.
// Saved on your profile as JSON in `avatar_look`; what you own is in
// `avatar_items`.

enum BodyPart: String, CaseIterable, Identifiable {
    case head = "Head", torso = "Torso", rightArm = "RightArm", leftArm = "LeftArm", rightLeg = "RightLeg", leftLeg = "LeftLeg"
    var id: String { rawValue }
}

struct AvatarLook: Equatable, Hashable {
    var skin: [BodyPart: UInt32] = Dictionary(uniqueKeysWithValues: BodyPart.allCases.map { ($0, 0xF6D2B8) })
    var shirt = ""      // catalog id ("" = none)
    var shirtURL = ""   // its picture
    var pants = ""
    var pantsURL = ""

    static let starter = AvatarLook()

    func color(_ part: BodyPart) -> UInt32 { skin[part] ?? 0xF6D2B8 }

    // MARK: saving

    var json: String {
        var out: [String: Any] = ["shirt": shirt, "shirt_url": shirtURL, "pants": pants, "pants_url": pantsURL]
        for part in BodyPart.allCases { out["c_" + part.rawValue] = Int(color(part)) }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    init() {}

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for part in BodyPart.allCases {
            if let n = raw["c_" + part.rawValue] as? Int { skin[part] = UInt32(truncatingIfNeeded: n) & 0xFFFFFF }
        }
        // Only people-made clothes exist (older looks may name removed ones).
        let shirtId = raw["shirt"] as? String ?? ""
        let pantsId = raw["pants"] as? String ?? ""
        if !shirtId.contains(":") {
            shirt = shirtId
            shirtURL = raw["shirt_url"] as? String ?? ""
        }
        if !pantsId.contains(":") {
            pants = pantsId
            pantsURL = raw["pants_url"] as? String ?? ""
        }
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

// MARK: - catalog items (shirts and pants people upload)

struct CatalogItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case shirt, pants
        var id: String { rawValue }
        var label: String { self == .shirt ? "Shirts" : "Pants" }
        var one: String { self == .shirt ? "shirt" : "pants" }
        var icon: String { self == .shirt ? "tshirt.fill" : "figure.walk" }
    }

    var id: String
    var name: String
    var kind: Kind
    var price: Int
    var imageURL = ""
    var creatorEmail = ""
    var creatorName = ""
    var sales = 0
    var created = ""
    var onSale = true

    init?(_ d: Doc) {
        guard let kind = Kind(rawValue: d.str("kind")) else { return nil }
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
}

// MARK: - the clothes template

// Shirts and pants use the classic 585 × 559 clothing template (the one many
// creators already have): the body's six sides at the top, the right arm or
// leg bottom left and the left one bottom right, each with its front next to
// the middle, the top above that front and the bottom below it. Pictures 2×
// or 3× that size work too.
enum ClothTemplate {
    static let size = CGSize(width: 585, height: 559)

    enum Face: String, CaseIterable { case right, front, left, back, top, bottom }
    enum Region: String, CaseIterable { case body, right, left }

    // Where each side sits on the template, in pixels.
    static func rect(_ region: Region, _ face: Face) -> CGRect {
        switch region {
        case .body:
            switch face {
            case .front: return CGRect(x: 231, y: 74, width: 128, height: 128)
            case .back: return CGRect(x: 427, y: 74, width: 128, height: 128)
            case .right: return CGRect(x: 165, y: 74, width: 64, height: 128)
            case .left: return CGRect(x: 361, y: 74, width: 64, height: 128)
            case .top: return CGRect(x: 231, y: 8, width: 128, height: 64)
            case .bottom: return CGRect(x: 231, y: 204, width: 128, height: 64)
            }
        case .right:
            switch face {
            case .left: return CGRect(x: 19, y: 355, width: 64, height: 128)
            case .back: return CGRect(x: 85, y: 355, width: 64, height: 128)
            case .right: return CGRect(x: 151, y: 355, width: 64, height: 128)
            case .front: return CGRect(x: 217, y: 355, width: 64, height: 128)
            case .top: return CGRect(x: 217, y: 289, width: 64, height: 64)
            case .bottom: return CGRect(x: 217, y: 485, width: 64, height: 64)
            }
        case .left:
            switch face {
            case .front: return CGRect(x: 308, y: 355, width: 64, height: 128)
            case .left: return CGRect(x: 374, y: 355, width: 64, height: 128)
            case .back: return CGRect(x: 440, y: 355, width: 64, height: 128)
            case .right: return CGRect(x: 506, y: 355, width: 64, height: 128)
            case .top: return CGRect(x: 308, y: 289, width: 64, height: 64)
            case .bottom: return CGRect(x: 308, y: 485, width: 64, height: 64)
            }
        }
    }

    static func region(for part: BodyPart) -> Region? {
        switch part {
        case .torso: return .body
        case .rightArm, .rightLeg: return .right
        case .leftArm, .leftLeg: return .left
        case .head: return nil
        }
    }

    // Inside the app each block's picture is unfolded the same simple way
    // (right side, front, left side, back in a row; top above the front,
    // bottom below it), which is what the 3D blocks are mapped to.
    struct Net {
        let w: CGFloat, h: CGFloat, d: CGFloat
        var width: CGFloat { 2 * d + 2 * w }
        var height: CGFloat { 2 * d + h }

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
    }

    static func net(for part: BodyPart) -> Net? {
        switch part {
        case .torso: return Net(w: 2, h: 2, d: 1)
        case .head: return nil
        default: return Net(w: 1, h: 2, d: 1)
        }
    }

    static func faceName(_ face: Face) -> String {
        switch face {
        case .front: return "FRONT"
        case .back: return "BACK"
        case .right: return "R"
        case .left: return "L"
        case .top: return "UP"
        case .bottom: return "DOWN"
        }
    }

    static func regionName(_ region: Region, kind: CatalogItem.Kind) -> String {
        switch region {
        case .body: return "TORSO"
        case .right: return kind == .pants ? "RIGHT LEG" : "RIGHT ARM"
        case .left: return kind == .pants ? "LEFT LEG" : "LEFT ARM"
        }
    }

    // The blank template to download: every side outlined and named on a
    // transparent background, at 585 × 559.
    static func blank(kind: CatalogItem.Kind) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            for region in Region.allCases {
                for face in Face.allCases {
                    let r = rect(region, face)
                    let shade: UInt32 = face == .front ? 0xF3E4EC : (face == .back ? 0xE8E1F2 : 0xEDEDF2)
                    UIColor(hex: shade).setFill()
                    cg.fill(r)
                    cg.setStrokeColor(UIColor(hex: 0xB9A9B6).cgColor)
                    cg.setLineWidth(1)
                    cg.stroke(r.insetBy(dx: 0.5, dy: 0.5))
                    let text = faceName(face) as NSString
                    let big = face == .front || face == .back
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: big ? 14 : 11, weight: .heavy),
                        .foregroundColor: UIColor(hex: 0x9C8A93),
                    ]
                    let s = text.size(withAttributes: attrs)
                    text.draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2), withAttributes: attrs)
                }
                let title = regionName(region, kind: kind) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .black), .foregroundColor: UIColor(hex: 0x6B5560)]
                let top = rect(region, .top)
                let s = title.size(withAttributes: attrs)
                let x = region == .right ? top.minX - s.width - 12 : top.maxX + 12
                title.draw(at: CGPoint(x: x, y: top.midY - s.height / 2), withAttributes: attrs)
            }
        }
    }

    // Does a picture look like a template (the right shape)?
    static func fits(_ image: UIImage) -> Bool {
        let w = image.size.width * image.scale, h = image.size.height * image.scale
        guard w > 0, h > 0 else { return false }
        return abs(w / h - size.width / size.height) < 0.02 && w >= size.width * 0.9
    }

    // Ready to upload: exactly 585 × 559 (or 2× / 3× of it), transparency kept.
    static func normalized(_ image: UIImage) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let multiple = max(1, min(3, (w / size.width).rounded()))
        let target = CGSize(width: size.width * multiple, height: size.height * multiple)
        if abs(w - target.width) < 0.5 && abs(h - target.height) < 0.5 { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// Clothes pictures, downloaded once and kept while the app is open.
@MainActor
enum ClothStore {
    private static var memory: [String: UIImage] = [:]
    private static var loading: [String: Task<UIImage?, Never>] = [:]

    static func image(url: String) async -> UIImage? {
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
