import SwiftUI
import UIKit
import PhotosUI

// Clothes and accessories that are whole pictures on the bunny's canvas
// (878 × 1210, see BunnyArt), drawn as they were painted. Some come with the
// app; the team can add more from the bunny maker (they're kept in the
// BunnyItem table and the picture in Storage), and everyone sees them.

// Where an item goes: clothes (instead of a top) or on her head and face
// (instead of the bow).
enum BunnySlot: String, CaseIterable, Identifiable {
    case top, head, body, face, collar
    var id: String { rawValue }
    var label: String { switch self { case .top: return "Clothes"; case .head: return "Accessory"; case .body: return "Body"; case .face: return "Face"; case .collar: return "Collar" } }
}

struct BunnyItem: Identifiable, Equatable {
    let id: String
    var name: String
    var slot: BunnySlot
    // A picture in the app, or an uploaded one.
    var asset = ""
    var outlineAsset = ""
    var url = ""
    // The hue it was painted in (uploaded ones: worked out from the picture).
    var hue: Double? = nil
    var price: Int = 0

    var uploaded: Bool { asset.isEmpty }

    // How a choice tile zooms into the picture (the part she wears).
    var tileZoom: CGFloat { slot == .top ? 2.2 : 1.35 }
    var tileFocus: UnitPoint { slot == .top ? UnitPoint(x: 0.5, y: 0.7) : UnitPoint(x: 0.5, y: 0.3) }

    static let builtIn: [BunnyItem] = [
        BunnyItem(id: "body-fox", name: "Fox", slot: .body, asset: "BunnyBodyFox", outlineAsset: "BunnyBodyFoxOutline", hue: 340),
        BunnyItem(id: "body-monkey", name: "Monkey", slot: .body, asset: "BunnyBodyMonkey", outlineAsset: "BunnyBodyMonkeyOutline", hue: 340),
        BunnyItem(id: "body-lamb", name: "Lamb", slot: .body, asset: "BunnyBodyLamb", outlineAsset: "BunnyBodyLambOutline", hue: 340),
        BunnyItem(id: "body-bear", name: "Bear", slot: .body, asset: "BunnyBodyBear", outlineAsset: "BunnyBodyBearOutline", hue: 340),
        BunnyItem(id: "body-deer", name: "Deer", slot: .body, asset: "BunnyBodyDeer", outlineAsset: "BunnyBodyDeerOutline", hue: 340),
        BunnyItem(id: "body-cat", name: "Cat", slot: .body, asset: "BunnyBodyCatFur", outlineAsset: "BunnyBodyCatInk", hue: 340),

        BunnyItem(id: "maid", name: "Maid", slot: .top, asset: "BunnyItemMaid", hue: 245),
        BunnyItem(id: "frills", name: "Frills", slot: .top, asset: "BunnyItemFrills", hue: 194),
        BunnyItem(id: "stripes", name: "Stripes", slot: .top, asset: "BunnyItemStripes", hue: 236),
        BunnyItem(id: "shirt", name: "Áo dài", slot: .top, asset: "BunnyItemShirt", hue: 265),
        BunnyItem(id: "sweater", name: "Sweater", slot: .top, asset: "BunnyItemSweater", hue: 20),
        BunnyItem(id: "collar-top", name: "Peach", slot: .top, asset: "BunnyItemCollarTop", hue: 5),
        BunnyItem(id: "bow-top", name: "Bow top", slot: .top, asset: "BunnyItemBowTop", hue: 227),
        BunnyItem(id: "suit", name: "Suit", slot: .top, asset: "BunnyItemSuit", hue: 355),
        BunnyItem(id: "jacket", name: "Jacket", slot: .top, asset: "BunnyItemJacket", hue: 209),
        BunnyItem(id: "clips", name: "Clips", slot: .head, asset: "BunnyItemClips", hue: 265),
        BunnyItem(id: "headphones", name: "Headphones", slot: .head, asset: "BunnyItemHeadphones", hue: 237),
        BunnyItem(id: "headband", name: "Headband", slot: .head, asset: "BunnyItemHeadband", hue: 230),
        BunnyItem(id: "beret", name: "Beret", slot: .head, asset: "BunnyItemBeret", hue: 6),
        BunnyItem(id: "beanie", name: "Beanie", slot: .head, asset: "BunnyItemBeanie", hue: 19),
        BunnyItem(id: "straw-hat", name: "Straw hat", slot: .head, asset: "BunnyItemStrawHat", hue: 17),
        BunnyItem(id: "hood", name: "Hood", slot: .head, asset: "BunnyItemHood", hue: 347),
        BunnyItem(id: "paper-bag", name: "Paper bag", slot: .head, asset: "BunnyItemPaperBag", hue: 15),
    ]
}

extension BunnyItem {
    init?(doc: Doc) {
        let id = doc.str("id")
        let url = doc.str("image_url")
        guard !id.isEmpty, !url.isEmpty, let slot = BunnySlot(rawValue: doc.str("slot")) else { return nil }
        self.init(id: id, name: doc.str("name").isEmpty ? "Item" : doc.str("name"), slot: slot, url: url, price: max(0, doc.int("price_coins")))
    }
}

// Every item: ours, then the team's (loaded now and then).
@MainActor
@Observable
final class BunnyCatalog {
    static let shared = BunnyCatalog()
    private(set) var uploaded: [BunnyItem] = []
    @ObservationIgnored private var loadedAt = Date.distantPast

    var all: [BunnyItem] { BunnyItem.builtIn + uploaded }

    func items(_ slot: BunnySlot) -> [BunnyItem] { all.filter { $0.slot == slot } }

    func item(_ id: String) -> BunnyItem? {
        id.isEmpty ? nil : all.first { $0.id == id }
    }

    func load(force: Bool = false) async {
        guard force || Date().timeIntervalSince(loadedAt) > 300 else { return }
        guard let docs = try? await FS.query("BunnyItem", [], orderBy: "created_date", descending: false, limit: 300) else { return }
        uploaded = docs.compactMap(BunnyItem.init(doc:))
        loadedAt = Date()
    }

    // The team adds a picture for everyone.
    func add(name: String, slot: BunnySlot, png: Data, by email: String, price: Int = 0) async throws {
        guard (0...1000000).contains(price) else { throw APIError(message: "Enter a price from 0 to 1,000,000 coins.") }
        let url = try await StorageClient.upload(png, contentType: "image/png", fileExtension: "png")
        let doc = try await FS.create("BunnyItem", [
            "name": String(name.prefix(60)), "slot": slot.rawValue, "image_url": url, "price_coins": price,
            "created_by": email, "created_date": FS.nowISO(),
        ])
        if let item = BunnyItem(doc: doc) { uploaded.append(item) } else { await load(force: true) }
    }

    func edit(_ item: BunnyItem, name: String, price: Int) async throws {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !clean.isEmpty, (0...1000000).contains(price) else { throw APIError(message: "Enter a name and a price from 0 to 1,000,000 coins.") }
        try await FS.update("BunnyItem", item.id, ["name": clean, "price_coins": price])
        if let i = uploaded.firstIndex(where: { $0.id == item.id }) { uploaded[i].name = clean; uploaded[i].price = price }
    }

    func remove(_ item: BunnyItem) async throws {
        try await FS.delete("BunnyItem", item.id)
        uploaded.removeAll { $0.id == item.id }
    }
}

// Uploaded item pictures: fetched once, kept on the phone, decoded at the
// same size as the app's own layers.
@MainActor
@Observable
final class BunnyRemoteImages {
    static let shared = BunnyRemoteImages()
    private(set) var images: [String: UIImage] = [:]
    // The hue each uploaded picture was painted in.
    private(set) var hues: [String: Double] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("bunny-items", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static func file(_ url: String) -> URL {
        let name = url.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        return folder.appendingPathComponent("\(name).png")
    }

    func fetch(_ url: String) async {
        guard !url.isEmpty, images[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)
        defer { loading.remove(url) }
        let file = Self.file(url)
        var data = try? Data(contentsOf: file)
        if data == nil, let link = URL(string: url), let fresh = try? await URLSession.shared.data(from: link).0 {
            data = fresh
            try? fresh.write(to: file, options: .atomic)
        }
        guard let data else { return }
        let made = await Task.detached(priority: .utility) { () -> (UIImage, Double)? in
            guard let full = UIImage(data: data) else { return nil }
            let image = full.preparingThumbnail(of: CGSize(width: 653, height: 900)) ?? full
            return (image, BunnyRemoteImages.baseHue(image))
        }.value
        if let made {
            hues[url] = made.1
            images[url] = made.0
        }
    }

    // The main hue of a picture's coloured parts (weighted by how colourful
    // they are), in degrees.
    nonisolated static func baseHue(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let w = 66, h = 90
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var x = 0.0, y = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 128 {
            let a = Double(pixels[i + 3]) / 255
            let r = Double(pixels[i]) / 255 / a, g = Double(pixels[i + 1]) / 255 / a, b = Double(pixels[i + 2]) / 255 / a
            let hi = max(r, g, b), lo = min(r, g, b)
            guard hi > 0.2, hi - lo > 0.2 * hi else { continue }
            var hue: Double
            if hi == r { hue = (g - b) / (hi - lo) } else if hi == g { hue = 2 + (b - r) / (hi - lo) } else { hue = 4 + (r - g) / (hi - lo) }
            hue = hue * 60 * .pi / 180
            let weight = (hi - lo) / hi
            x += cos(hue) * weight
            y += sin(hue) * weight
        }
        guard x != 0 || y != 0 else { return 0 }
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

// One item drawn on the canvas, recoloured the same way as the bunny's own
// clothes: turned from the hue it was painted in to the colour's hue (see
// BunnyPiece), with the colour's strength and lightness.
struct BunnyItemLayer: View {
    let item: BunnyItem
    // nil or "Original": as it was painted.
    var tint: BunnyTint? = nil

    var body: some View {
        ZStack {
            if item.slot == .body, !item.uploaded, let tint {
                BunnyLayer(item.asset, tint)
            } else if item.slot == .top || item.slot == .head {
                // Clothes and accessories are dyed (see BunnyDye).
                picture.bunnyDye(tint, anchor: dyeAnchor)
            } else {
                picture
                    .hueRotation(.degrees(item.slot == .body ? (tint?.hue ?? 0) : turn))
                    .saturation(tint?.saturation ?? 1)
                    .brightness(tint?.brightness ?? 0)
            }
            if !item.outlineAsset.isEmpty {
                BunnyImages.image(item.outlineAsset).resizable().interpolation(.high)
            }
        }
    }

    private var dyeAnchor: Float {
        if !item.asset.isEmpty { return BunnyDye.anchor(item.asset, BunnyImages.uiImage(item.asset)) }
        guard let image = BunnyRemoteImages.shared.images[item.url] else { return 0.5 }
        return BunnyDye.anchor(item.url, image)
    }

    private var turn: Double {
        guard let tint, !tint.hue.isNaN else { return 0 }
        let base = item.hue ?? BunnyRemoteImages.shared.hues[item.url] ?? 0
        var d = (tint.hue - base).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    @ViewBuilder
    private var picture: some View {
        if !item.asset.isEmpty {
            BunnyImages.image(item.asset).resizable().interpolation(.high)
        } else {
            ZStack {
                if let image = BunnyRemoteImages.shared.images[item.url] {
                    Image(uiImage: image).resizable().interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .task(id: item.url) { await BunnyRemoteImages.shared.fetch(item.url) }
        }
    }
}

// MARK: - Adding an item (the team)

struct BunnyItemUploader: View {
    var slot: BunnySlot
    var look: BunnyLook
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var png: Data?
    @State private var preview: UIImage?
    @State private var name = ""
    @State private var price = "0"
    @State private var chosenSlot: BunnySlot = .top
    @State private var problem: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Draw the item on a transparent PNG the same size as the bunny (878 × 1210), in the same place you'd see it on her. It shows for everyone straight away.")
                        .font(.jakarta(13, .medium)).foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    stage
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label(png == nil ? "Choose the picture" : "Choose another", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                        SugarField(placeholder: "Like \"Witch hat\"", text: $name)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where it goes").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                        Picker("Where it goes", selection: $chosenSlot) {
                            ForEach(BunnySlot.allCases) { slot in Text(slot.label).tag(slot) }
                        }
                        .pickerStyle(.menu)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Price in coins · 0 is free").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                        TextField("0", text: $price).keyboardType(.numberPad)
                            .padding(14).frostedFill(in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button { Task { await upload() } } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) } else { Image(systemName: "icloud.and.arrow.up.fill") }
                            Text("Add for everyone")
                        }
                    }
                    .buttonStyle(GradientButtonStyle(height: 50))
                    .disabled(busy || png == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(18)
            }
            .sugarBackground()
            .navigationTitle("New bunny item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear { chosenSlot = slot }
        .onChange(of: pick) { _, next in Task { await load(next) } }
    }

    // Her with the new item on, as she'd wear it.
    private var stage: some View {
        var base = look
        switch chosenSlot {
        case .top: base.setLayers([], .top)
        case .head: base.setLayers([], .head)
        case .body: base.bodyItem = ""
        case .face: base.faceItem = ""
        case .collar: base.collarItem = ""
        }
        return ZStack {
            BunnySceneView(scene: look.scene, animated: false)
            ZStack {
                BunnyFigure(look: base)
                if let preview { Image(uiImage: preview).resizable().interpolation(.high) }
            }
            .aspectRatio(BunnyArt.aspect, contentMode: .fit)
            .padding(.vertical, 14)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.rim(0.7), lineWidth: 1.5))
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            if item != nil { problem = "Couldn't open that picture." }
            return
        }
        let ratio = image.size.width / max(image.size.height, 1)
        guard abs(ratio - BunnyArt.aspect) < 0.02 else {
            problem = "It needs the bunny's shape: 878 × 1210 (or the same shape, bigger)."
            png = nil
            preview = nil
            return
        }
        guard let cg = image.cgImage, [.first, .last, .premultipliedFirst, .premultipliedLast].contains(cg.alphaInfo) else {
            problem = "It needs a see-through background (a PNG with transparency)."
            png = nil
            preview = nil
            return
        }
        problem = nil
        // Kept at the app's own layer size, as a PNG (keeps the see-through parts).
        let fitted = image.size.width > 878 ? (image.preparingThumbnail(of: CGSize(width: 878, height: 1210)) ?? image) : image
        png = fitted.pngData()
        preview = fitted
    }

    private func upload() async {
        guard let png, let me = model.me else { return }
        guard let amount = Int(price), (0...1000000).contains(amount) else {
            problem = "Enter a price from 0 to 1,000,000 coins."; return
        }
        busy = true
        defer { busy = false }
        do {
            try await BunnyCatalog.shared.add(name: name.trimmingCharacters(in: .whitespaces), slot: chosenSlot, png: png, by: me.email, price: amount)
            model.showToast("Added for everyone", icon: "hare.fill")
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
