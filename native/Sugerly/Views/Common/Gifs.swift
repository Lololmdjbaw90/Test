import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// MARK: - GIPHY + media helpers

struct GifItem: Identifiable, Hashable {
    let id: String
    let url: String      // what gets sent
    let preview: String  // small version for the grid
    let ratio: CGFloat   // width / height
    var sticker = false
}

// Same GIPHY search the website uses (key from Admin → Site → GIFs).
enum Giphy {
    static let fallbackKey = "8Du0ujD2XK22FRjQZ49uboICk5ywMAtr"

    @MainActor static var key: String {
        let k = SiteTheme.shared.giphyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return k.isEmpty ? fallbackKey : k
    }

    static func fetch(stickers: Bool, query: String, offset: Int, key: String) async -> [GifItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: "https://api.giphy.com/v1/\(stickers ? "stickers" : "gifs")/\(q.isEmpty ? "trending" : "search")") else { return [] }
        var items = [URLQueryItem(name: "api_key", value: key), URLQueryItem(name: "limit", value: "30"),
                     URLQueryItem(name: "offset", value: "\(offset)"), URLQueryItem(name: "rating", value: "pg-13")]
        if !stickers { items.append(URLQueryItem(name: "bundle", value: "messaging_non_clips")) }
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        comps.queryItems = items
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in parse(entry, sticker: stickers) }
    }

    private static func parse(_ entry: [String: Any], sticker: Bool) -> GifItem? {
        guard let id = entry["id"] as? String,
              let images = entry["images"] as? [String: Any],
              let fixed = images["fixed_width"] as? [String: Any] else { return nil }
        let fixedURL = (fixed["webp"] as? String) ?? (fixed["url"] as? String) ?? ""
        guard !fixedURL.isEmpty else { return nil }
        // What gets sent: the sharpest version that's still light enough to
        // load quickly (the full original when it's small, else GIPHY's
        // medium one), instead of the 200px-wide thumbnail.
        func size(_ rendition: [String: Any]?, _ key: String) -> Int { Int(rendition?[key] as? String ?? "") ?? .max }
        let original = images["original"] as? [String: Any]
        let medium = images["downsized_medium"] as? [String: Any]
        var full = fixedURL
        if let webp = original?["webp"] as? String, size(original, "webp_size") <= 3_500_000 {
            full = webp
        } else if let gif = original?["url"] as? String, size(original, "size") <= 3_000_000 {
            full = gif
        } else if let gif = medium?["url"] as? String {
            full = gif
        }
        // The grid shows the 200px version (not the tiny 100px one).
        let preview = fixedURL
        let w = Double(fixed["width"] as? String ?? "") ?? 200
        let h = Double(fixed["height"] as? String ?? "") ?? 200
        return GifItem(id: id, url: sticker ? Media.stickerURL(full) : full, preview: preview, ratio: CGFloat(w / max(1, h)), sticker: sticker)
    }
}

enum Media {
    // Stickers are sent like pictures, marked so they show without a bubble.
    static func stickerURL(_ url: String) -> String { isSticker(url) ? url : url + "#sticker" }
    static func isSticker(_ url: String) -> Bool { url.hasSuffix("#sticker") }
    static func label(_ url: String) -> String {
        if isSticker(url) { return "Sent a sticker" }
        return AnimatedImages.looksAnimated(url) ? "Sent a GIF" : "Sent a photo"
    }
}

// Loads a still or moving picture from a link.
struct AnimatedThumb: View {
    let url: String
    var fill = true
    var maxPixel: CGFloat = 240
    var maxFrames = 36
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                LoadedImage(image: image, fill: fill).transition(.opacity)
            } else {
                Color.clear.overlay(ProgressView().tint(Theme.main).scaleEffect(0.8))
            }
        }
        .task(id: url) {
            if AnimatedImages.looksAnimated(url) {
                if let loaded = await AnimatedImages.load(url, maxPixel: maxPixel, maxFrames: maxFrames) { withAnimation(.easeOut(duration: 0.2)) { image = loaded } }
            } else if let loaded = await ImagePipeline.shared.load(url) {
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        }
    }
}

// A picture inside a message: stickers float free, GIFs and photos get a card.
struct MessageMedia: View {
    let url: String
    var width: CGFloat = 240
    var tallest: CGFloat = 0.6
    var widest: CGFloat = 1.6

    var body: some View {
        if Media.isSticker(url) {
            AnimatedThumb(url: url, fill: false, maxPixel: 480, maxFrames: 90)
                .frame(width: 140, height: 140)
                .shadow(color: Palette.shadow, radius: 6, y: 3)
        } else {
            ArtImage(url: url, tallest: tallest, widest: widest)
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Palette.shadow, radius: 8, y: 3)
        }
    }
}

// The round "GIF" button that sits next to a message box.
struct GifButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("GIF").font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                .frame(width: 42, height: 42)
                .background(Theme.soft, in: Circle())
                .overlay(Circle().strokeBorder(Theme.main.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle())
        .accessibilityLabel("GIFs and stickers")
    }
}

// MARK: - Picker

struct GifPickerSheet: View {
    var onPick: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = 0
    @State private var query = ""
    @State private var items: [GifItem] = []
    @State private var loading = false
    @State private var exhausted = false
    @State private var maker: Maker?

    enum Maker: String, Identifiable { case sticker, gif; var id: String { rawValue } }

    private var columnCount: Int { sizeClass == .regular ? 4 : 2 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SectionSwitch(options: [("GIFs", "photo.stack.fill"), ("Stickers", "face.smiling.inverse"), ("Mine", "heart.fill")], selection: $tab)
                if tab < 2 { SearchField(text: $query, placeholder: tab == 0 ? "Search GIPHY" : "Search stickers") }
                ScrollView {
                    if tab == 2 { mine } else { results }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .sugarBackground()
            .navigationTitle("GIFs & stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                }
            }
        }
        .task(id: "\(tab)|\(query)") {
            guard tab < 2 else { return }
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .sheet(item: $maker) { kind in
            switch kind {
            case .sticker: StickerMakerView { url in pick(url) }
            case .gif: GifMakerView { url in pick(url) }
            }
        }
    }

    // MARK: GIPHY results

    private var results: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(columns(items).enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: 8) {
                        ForEach(column) { item in cell(item) }
                    }
                }
            }
            if loading {
                ProgressView().tint(Theme.main).padding(20)
            } else if items.isEmpty {
                Text("Nothing found — try another word").font(.jakarta(14, .semibold)).foregroundStyle(Palette.muted).padding(30)
            }
            Color.clear.frame(height: 1).onAppear { Task { await more() } }
            Text("Powered by GIPHY").font(.jakarta(11, .bold)).foregroundStyle(Palette.muted).padding(.bottom, 20)
        }
    }

    private func columns(_ list: [GifItem]) -> [[GifItem]] {
        var cols = Array(repeating: [GifItem](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)
        for item in list {
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            cols[i].append(item)
            heights[i] += 1 / max(0.3, item.ratio)
        }
        return cols
    }

    private func cell(_ item: GifItem) -> some View {
        Button { pick(item.url) } label: {
            Color.clear
                .aspectRatio(max(0.4, min(2.5, item.ratio)), contentMode: .fit)
                .overlay { AnimatedThumb(url: item.preview, fill: !item.sticker, maxPixel: 320, maxFrames: 40) }
                .padding(item.sticker ? 6 : 0)
                .background(Palette.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.95))
        .contextMenu {
            Button { save(item.url, sticker: item.sticker) } label: {
                Label(item.sticker ? "Save to my stickers" : "Save to my GIFs", systemImage: "heart")
            }
        }
    }

    private func reload() async {
        loading = true
        exhausted = false
        let fresh = await Giphy.fetch(stickers: tab == 1, query: query, offset: 0, key: Giphy.key)
        items = fresh
        exhausted = fresh.count < 30
        loading = false
    }

    private func more() async {
        guard tab < 2, !loading, !exhausted, !items.isEmpty else { return }
        loading = true
        let next = await Giphy.fetch(stickers: tab == 1, query: query, offset: items.count, key: Giphy.key)
        let known = Set(items.map(\.id))
        items += next.filter { !known.contains($0.id) }
        exhausted = next.count < 30
        loading = false
    }

    // MARK: Mine

    private var mine: some View {
        let stickers = model.me?.stickers ?? []
        let gifs = model.me?.myGifs ?? []
        let grid = [GridItem(.adaptive(minimum: sizeClass == .regular ? 110 : 90), spacing: 8)]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                makerTile("Make a sticker", "Cut yourself or your art out of a photo", "scissors") { maker = .sticker }
                makerTile("Make a GIF", "From photos or a short video", "film.stack.fill") { maker = .gif }
            }
            Text("My stickers").font(.display(22)).foregroundStyle(Palette.text)
            if stickers.isEmpty {
                Text("Stickers you make or save show up here.").font(.jakarta(13)).foregroundStyle(Palette.muted)
            } else {
                LazyVGrid(columns: grid, spacing: 8) {
                    ForEach(stickers, id: \.self) { url in
                        savedCell(url, fill: false) { remove(url, sticker: true) }
                    }
                }
            }
            Text("My GIFs").font(.display(22)).foregroundStyle(Palette.text)
            if gifs.isEmpty {
                Text("Long-press any GIF to save it, or make your own.").font(.jakarta(13)).foregroundStyle(Palette.muted)
            } else {
                LazyVGrid(columns: grid, spacing: 8) {
                    ForEach(gifs, id: \.self) { url in
                        savedCell(url, fill: true) { remove(url, sticker: false) }
                    }
                }
            }
        }
        .padding(.bottom, 30)
    }

    private func makerTile(_ title: String, _ text: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(title).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                Text(text).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sugarCard(radius: 22, padding: 14)
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
    }

    private func savedCell(_ url: String, fill: Bool, onRemove: @escaping () -> Void) -> some View {
        Button { pick(url) } label: {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay { AnimatedThumb(url: url, fill: fill, maxPixel: 220, maxFrames: 30) }
                .padding(fill ? 0 : 6)
                .background(Palette.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.95))
        .contextMenu {
            Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
        }
    }

    // MARK: Actions

    private func pick(_ url: String) {
        onPick(url)
        maker = nil
        dismiss()
    }

    private func save(_ url: String, sticker: Bool) {
        guard let me = model.me else { return }
        var list = sticker ? me.stickers : me.myGifs
        guard !list.contains(url) else { model.showToast("Already saved", icon: "heart.fill"); return }
        list.insert(url, at: 0)
        let capped = Array(list.prefix(60))
        Task { try? await model.updateMe([sticker ? "stickers" : "my_gifs": capped]) }
        model.showToast(sticker ? "Saved to my stickers" : "Saved to my GIFs", icon: "heart.fill")
    }

    private func remove(_ url: String, sticker: Bool) {
        guard let me = model.me else { return }
        let list = (sticker ? me.stickers : me.myGifs).filter { $0 != url }
        Task { try? await model.updateMe([sticker ? "stickers" : "my_gifs": list]) }
    }
}

// MARK: - Sticker maker

enum StickerKit {
    // Upright, at most maxSide, scale 1 — ready for Vision and drawing.
    nonisolated static func normalized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(1, max(size.width, size.height)))
        let target = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    // Lifts the people/pets/objects out of a photo (iOS 17 subject lifting).
    nonisolated static func cutout(_ image: UIImage) -> UIImage? {
        guard let cg = normalized(image, maxSide: 1024).cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        } catch {
            return nil
        }
    }

    // The shape of a picture, filled with one colour.
    nonisolated static func silhouette(_ image: UIImage, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            image.draw(at: .zero)
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size), blendMode: .sourceIn)
        }
    }

    // Final 512×512 sticker: the picture, a white die-cut edge and a caption.
    nonisolated static func compose(_ base: UIImage, outline: Bool, rounded: Bool, caption: String, side: CGFloat = 512) -> UIImage {
        let edge: CGFloat = outline ? 12 : 0
        let pad: CGFloat = edge + 10
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionHeight: CGFloat = text.isEmpty ? 0 : side * 0.2
        let box = CGRect(x: pad, y: pad, width: side - pad * 2, height: side - pad * 2 - captionHeight)
        let fit = min(box.width / max(1, base.size.width), box.height / max(1, base.size.height))
        let size = CGSize(width: base.size.width * fit, height: base.size.height * fit)
        let rect = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        var picture = base
        if rounded {
            picture = UIGraphicsImageRenderer(size: base.size, format: format).image { _ in
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: base.size), cornerRadius: min(base.size.width, base.size.height) * 0.12).addClip()
                base.draw(at: .zero)
            }
        }
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            if outline {
                let white = silhouette(picture, color: .white)
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.18).cgColor)
                for i in 0..<24 {
                    let a = Double(i) / 24 * .pi * 2
                    white.draw(in: rect.offsetBy(dx: CGFloat(cos(a)) * edge, dy: CGFloat(sin(a)) * edge))
                }
                ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            }
            picture.draw(in: rect)
            if !text.isEmpty { drawCaption(text, in: CGRect(x: 8, y: side - captionHeight - 6, width: side - 16, height: captionHeight), fill: UIColor(red: 0.93, green: 0.36, blue: 0.56, alpha: 1)) }
        }
    }

    // Bubbly text with a thick white edge (sticker style) or black edge (GIF style).
    nonisolated static func drawCaption(_ text: String, in rect: CGRect, fill: UIColor, stroke: UIColor = .white) {
        var size = rect.height * 0.62
        let font: (CGFloat) -> UIFont = { UIFont(name: "Bubbly-Regular", size: $0) ?? .systemFont(ofSize: $0, weight: .black) }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        while size > 12, (text as NSString).size(withAttributes: [.font: font(size)]).width > rect.width - 8 { size -= 2 }
        let base: [NSAttributedString.Key: Any] = [.font: font(size), .paragraphStyle: style]
        let height = (text as NSString).size(withAttributes: base).height
        let line = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        var outer = base
        outer[.strokeColor] = stroke
        outer[.strokeWidth] = 22
        (text as NSString).draw(in: line, withAttributes: outer)
        var inner = base
        inner[.foregroundColor] = fill
        (text as NSString).draw(in: line, withAttributes: inner)
    }
}

struct StickerMakerView: View {
    var onDone: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var source: UIImage?
    @State private var cut: UIImage?
    @State private var liftSubject = true
    @State private var outline = true
    @State private var caption = ""
    @State private var preview: UIImage?
    @State private var working = false
    @State private var saving = false
    @State private var note: String?

    var body: some View {
        ComposerScaffold(title: "New sticker", actionTitle: "Save", busy: saving, canPost: preview != nil && !working, onClose: { dismiss() }, onPost: { Task { await save() } }) {
            ZStack {
                Checkerboard().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit().padding(12)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    PhotosPicker(selection: $item, matching: .images) {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.main)
                            Text("Pick a photo").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                            Text("We'll cut out the subject for you").font(.jakarta(12)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if working {
                    VStack(spacing: 8) {
                        ProgressView().tint(Theme.main)
                        Text("Cutting out…").font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                    }
                    .padding(16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(height: 300)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: preview)

            if source != nil {
                FlowLayout(spacing: 8) {
                    Chip(title: "Cut out", icon: "scissors", active: liftSubject) { liftSubject.toggle() }
                    Chip(title: "White edge", icon: "circle.dashed", active: outline) { outline.toggle() }
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Change photo", systemImage: "photo").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                    }
                }
            }
            Text("Caption").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            SugarField(placeholder: "Optional — like \"so cute\"", text: $caption)
            if let note { Text(note).font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted) }
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                guard let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                source = image
                cut = nil
                await rebuild()
            }
        }
        .onChange(of: liftSubject) { _, _ in Task { await rebuild() } }
        .onChange(of: outline) { _, _ in Task { await rebuild() } }
        .task(id: caption) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, source != nil else { return }
            await rebuild()
        }
    }

    private func rebuild() async {
        guard let source else { return }
        working = liftSubject && cut == nil
        var base = StickerKit.normalized(source, maxSide: 1024)
        note = nil
        if liftSubject {
            if cut == nil {
                let original = source
                cut = await Task.detached(priority: .userInitiated) { StickerKit.cutout(original) }.value
            }
            if let cut { base = cut } else { note = "Couldn't find a subject — using the whole photo." }
        }
        let edge = outline, text = caption, rounded = !(liftSubject && cut != nil)
        let final = base
        preview = await Task.detached(priority: .userInitiated) { StickerKit.compose(final, outline: edge, rounded: rounded, caption: text) }.value
        working = false
    }

    private func save() async {
        guard let preview, let png = preview.pngData() else { return }
        saving = true
        defer { saving = false }
        do {
            let uploaded = try await StorageClient.upload(png, contentType: "image/png", fileExtension: "png")
            let url = Media.stickerURL(uploaded)
            if let me = model.me { try? await model.updateMe(["stickers": Array(([url] + me.stickers).prefix(60))]) }
            model.showToast("Sticker saved", icon: "scissors")
            onDone(url)
            dismiss()
        } catch {
            note = "Couldn't save — \(error.localizedDescription)"
        }
    }
}

// The grey-and-white squares that mean "see-through".
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 14
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.surface))
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Palette.surface2))
                }
            }
        }
    }
}

// MARK: - GIF maker

enum GifKit {
    // Frames from the start of a video (up to `seconds`, `fps` per second).
    static func videoFrames(_ url: URL, seconds: Double = 4, fps: Double = 10) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 540, height: 540)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let length = min(seconds, max(0.2, duration.isFinite ? duration : 0))
        let count = max(1, Int(length * fps))
        var out: [UIImage] = []
        for i in 0..<count {
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let frame = try? await generator.image(at: time) { out.append(UIImage(cgImage: frame.image)) }
        }
        return out
    }

    // Same size frames with the caption burned in.
    nonisolated static func render(_ frames: [UIImage], square: Bool, caption: String, side: CGFloat = 360) -> [UIImage] {
        guard let first = frames.first else { return [] }
        let ratio = first.size.width / max(1, first.size.height)
        let size: CGSize = square ? CGSize(width: side, height: side)
            : (ratio >= 1 ? CGSize(width: side, height: floor(side / ratio)) : CGSize(width: floor(side * ratio), height: side))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return frames.map { frame in
            renderer.image { _ in
                UIColor.black.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
                let fill = max(size.width / max(1, frame.size.width), size.height / max(1, frame.size.height))
                let drawn = CGSize(width: frame.size.width * fill, height: frame.size.height * fill)
                frame.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
                if !text.isEmpty {
                    let h = size.height * 0.2
                    StickerKit.drawCaption(text, in: CGRect(x: 6, y: size.height - h - 4, width: size.width - 12, height: h), fill: .white, stroke: .black)
                }
            }
        }
    }

    nonisolated static func encode(_ frames: [UIImage], delay: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        let fileProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProps as CFDictionary)
        let frameProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]]
        for frame in frames {
            if let cg = frame.cgImage { CGImageDestinationAddImage(destination, cg, frameProps as CFDictionary) }
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

struct GifMakerView: View {
    var onDone: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var frames: [UIImage] = []
    @State private var rendered: [UIImage] = []
    @State private var preview: UIImage?
    @State private var speed: Double = 0.14
    @State private var boomerang = false
    @State private var square = true
    @State private var caption = ""
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?

    private var sequence: [UIImage] { boomerang && rendered.count > 2 ? rendered + rendered.reversed().dropFirst().dropLast() : rendered }

    var body: some View {
        ComposerScaffold(title: "New GIF", actionTitle: "Save", busy: saving, canPost: !rendered.isEmpty && !loading, onClose: { dismiss() }, onPost: { Task { await save() } }) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.surface2)
                if let preview {
                    AnimatedImageView(image: preview, fill: false)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(10)
                } else {
                    PhotosPicker(selection: $picked, maxSelectionCount: 30, matching: .any(of: [.images, .videos])) {
                        VStack(spacing: 10) {
                            Image(systemName: "film.stack.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.main)
                            Text("Pick photos or a video").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                            Text("Photos become frames · videos use the first 4 seconds").font(.jakarta(12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if loading { ProgressView().tint(Theme.main).padding(16).background(Palette.surface, in: Circle()) }
            }
            .frame(height: 300)

            if !frames.isEmpty {
                HStack {
                    Label("Speed", systemImage: "hare.fill").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                    Slider(value: $speed, in: 0.04...0.5) { editing in if !editing { refreshPreview() } }
                        .tint(Theme.main)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                FlowLayout(spacing: 8) {
                    Chip(title: "Boomerang", icon: "arrow.left.arrow.right", active: boomerang) { boomerang.toggle(); refreshPreview() }
                    Chip(title: "Square", icon: "square", active: square) { square.toggle() }
                    PhotosPicker(selection: $picked, maxSelectionCount: 30, matching: .any(of: [.images, .videos])) {
                        Label("Change", systemImage: "photo.on.rectangle").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                    }
                }
            }
            Text("Caption").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            SugarField(placeholder: "Optional text on the GIF", text: $caption)
            if let error { Text(error).font(.jakarta(12, .semibold)).foregroundStyle(Palette.danger) }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
        .onChange(of: square) { _, _ in Task { await rerender() } }
        .task(id: caption) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !frames.isEmpty else { return }
            await rerender()
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        loading = true
        defer { loading = false }
        var out: [UIImage] = []
        if let video = items.first(where: { $0.supportedContentTypes.contains { $0.conforms(to: .movie) } }),
           let movie = try? await video.loadTransferable(type: PickedMovie.self) {
            out = await GifKit.videoFrames(movie.url)
            speed = 0.1
        } else {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    out.append(StickerKit.normalized(image, maxSide: 720))
                }
            }
            speed = 0.35
        }
        guard !out.isEmpty else { error = "Couldn't read those files."; return }
        error = nil
        frames = out
        await rerender()
    }

    private func rerender() async {
        let source = frames, sq = square, text = caption
        rendered = await Task.detached(priority: .userInitiated) { GifKit.render(source, square: sq, caption: text) }.value
        refreshPreview()
    }

    private func refreshPreview() {
        let list = sequence
        guard !list.isEmpty else { preview = nil; return }
        preview = UIImage.animatedImage(with: list, duration: speed * Double(list.count))
    }

    private func save() async {
        let list = sequence, delay = speed
        guard !list.isEmpty else { return }
        saving = true
        defer { saving = false }
        guard let data = await Task.detached(priority: .userInitiated, operation: { GifKit.encode(list, delay: delay) }).value else {
            error = "Couldn't make the GIF."
            return
        }
        do {
            let url = try await StorageClient.upload(data, contentType: "image/gif", fileExtension: "gif")
            if let me = model.me { try? await model.updateMe(["my_gifs": Array(([url] + me.myGifs).prefix(60))]) }
            model.showToast("GIF saved", icon: "film.stack.fill")
            onDone(url)
            dismiss()
        } catch {
            self.error = "Couldn't upload — \(error.localizedDescription)"
        }
    }
}
