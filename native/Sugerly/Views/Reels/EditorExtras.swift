import SwiftUI
import UIKit
import CoreImage

// MARK: - Vector stickers (no emoji): cute SF Symbols with a white die-cut edge

enum VectorStickers {
    struct Item { let symbol: String; let color: UInt32; var multicolor = false }

    static let all: [Item] = [
        Item(symbol: "heart.fill", color: 0xFF6F91), Item(symbol: "sparkles", color: 0xFFD166),
        Item(symbol: "star.fill", color: 0xFFD166), Item(symbol: "crown.fill", color: 0xF0A020),
        Item(symbol: "bolt.heart.fill", color: 0xD9577F), Item(symbol: "moon.stars.fill", color: 0xB19CFF),
        Item(symbol: "sun.max.fill", color: 0xFFB347), Item(symbol: "cloud.fill", color: 0x9CCBFF),
        Item(symbol: "rainbow", color: 0xFF6F91, multicolor: true), Item(symbol: "camera.macro", color: 0xFF9EB8),
        Item(symbol: "leaf.fill", color: 0x5EC8B8), Item(symbol: "music.note", color: 0xB19CFF),
        Item(symbol: "pawprint.fill", color: 0xC98E6B), Item(symbol: "hare.fill", color: 0xFFB6C9),
        Item(symbol: "cat.fill", color: 0xB9A7B8), Item(symbol: "dog.fill", color: 0xC98E6B),
        Item(symbol: "birthday.cake.fill", color: 0xFF9EB8), Item(symbol: "gift.fill", color: 0xFF6F91),
        Item(symbol: "balloon.fill", color: 0x7CBEFF), Item(symbol: "paintpalette.fill", color: 0xFFAA80),
        Item(symbol: "paintbrush.pointed.fill", color: 0xB19CFF), Item(symbol: "flame.fill", color: 0xFF7A3D),
        Item(symbol: "hand.thumbsup.fill", color: 0xFFD166), Item(symbol: "face.smiling.inverse", color: 0xFFD166),
        Item(symbol: "heart.circle.fill", color: 0xD9577F), Item(symbol: "star.circle.fill", color: 0x7CBEFF),
    ]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Int: UIImage] = [:]

    // The finished sticker if it's been made already.
    static func cached(_ index: Int) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[index]
    }

    static var allReady: Bool { all.indices.allSatisfy { cached($0) != nil } }

    static func image(_ index: Int) -> UIImage {
        if let hit = cached(index) { return hit }
        let out = make(index)
        lock.lock()
        cache[index] = out
        lock.unlock()
        return out
    }

    // Makes them all in the background: opening the stickers used to make
    // every one at once and froze the editor for a moment.
    static func prepare() async {
        await Task.detached(priority: .userInitiated) {
            for i in VectorStickers.all.indices where VectorStickers.cached(i) == nil {
                _ = VectorStickers.image(i)
            }
        }.value
    }

    private static func make(_ index: Int) -> UIImage {
        let item = all[index]
        var config = UIImage.SymbolConfiguration(pointSize: 300, weight: .bold)
        if item.multicolor { config = config.applying(UIImage.SymbolConfiguration.preferringMulticolor()) }
        let symbol = UIImage(systemName: item.symbol, withConfiguration: config)
        let tinted = item.multicolor ? symbol : symbol?.withTintColor(UIColor(hex: item.color), renderingMode: .alwaysOriginal)
        guard let tinted else { return UIImage() }
        // Draw it flat first so the white edge follows its shape.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let flat = UIGraphicsImageRenderer(size: tinted.size, format: format).image { _ in tinted.draw(at: .zero) }
        return StickerKit.compose(flat, outline: true, rounded: false, caption: "", side: 360)
    }
}

// Stickers for the editors: vector ones, your own, and GIPHY stickers.
struct StickerTray: View {
    var onAdd: (UIImage) -> Void
    @Environment(AppModel.self) private var model
    @State private var giphy = false
    @State private var loading = false
    @State private var ready = VectorStickers.allReady

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(50)), GridItem(.fixed(50))], spacing: 8) {
                Button { giphy = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: loading ? "hourglass" : "magnifyingglass").font(.system(size: 15, weight: .bold))
                        Text("GIPHY").font(.jakarta(9, .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyStyle(scale: 0.85))
                ForEach(model.me?.stickers ?? [], id: \.self) { url in
                    Button { add(url) } label: {
                        AnimatedThumb(url: url, fill: false, maxPixel: 120, maxFrames: 1)
                            .padding(3)
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.8))
                }
                ForEach(VectorStickers.all.indices, id: \.self) { i in
                    Button { onAdd(VectorStickers.image(i)) } label: {
                        Group {
                            if ready, let made = VectorStickers.cached(i) {
                                Image(uiImage: made).resizable().scaledToFit()
                                    .transition(.opacity)
                            } else {
                                // A plain one until the die-cut sticker is ready.
                                Image(systemName: VectorStickers.all[i].symbol)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color(hex: VectorStickers.all[i].color))
                            }
                        }
                        .padding(3)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.8))
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $giphy) { GifPickerSheet { url in add(url) } }
        .task {
            guard !ready else { return }
            await VectorStickers.prepare()
            withMotion(Motion.fade) { ready = true }
        }
    }

    private func add(_ url: String) {
        loading = true
        Task {
            defer { loading = false }
            let image: UIImage?
            if AnimatedImages.looksAnimated(url) {
                let loaded = await AnimatedImages.load(url, maxPixel: 600, maxFrames: 1)
                image = loaded?.images?.first ?? loaded
            } else if let full = await ImagePipeline.shared.load(url) {
                // A sticker never needs more than this; bigger ones made the
                // editor slow to move them.
                image = await Task.detached(priority: .userInitiated) { StickerKit.normalized(full, maxSide: 720) }.value
            } else {
                image = nil
            }
            if let image { onAdd(image) }
        }
    }
}

// MARK: - Drawing

struct DrawStroke: Identifiable, Equatable {
    var id = UUID()
    var points: [CGPoint]   // 0…1 of the canvas
    var color: UInt32
    var width: CGFloat      // share of the canvas width
    var neon = false
}

enum Doodle {
    static let colors: [UInt32] = [0xFFFFFF, 0x2A1620, 0xFF6F91, 0xFFB6C9, 0xB19CFF, 0x7CBEFF, 0x5EC8B8, 0xFFD166, 0xFF7A3D]

    static func path(_ s: DrawStroke, in size: CGSize) -> Path {
        var p = Path()
        let pts = s.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count == 1 {
            p.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            return p
        }
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i - 1])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    // The drawing as a see-through picture the size of the video frame.
    static func render(_ strokes: [DrawStroke], size: CGSize) -> UIImage? {
        guard !strokes.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            c.setLineCap(.round)
            c.setLineJoin(.round)
            for s in strokes {
                let w = s.width * size.width
                let cg = path(s, in: size).cgPath
                if s.neon {
                    c.saveGState()
                    c.setShadow(offset: .zero, blur: w * 1.6, color: UIColor(hex: s.color).cgColor)
                    c.addPath(cg)
                    c.setStrokeColor(UIColor(hex: s.color).cgColor)
                    c.setLineWidth(w)
                    c.strokePath()
                    c.restoreGState()
                    c.addPath(cg)
                    c.setStrokeColor(UIColor.white.cgColor)
                    c.setLineWidth(w * 0.45)
                    c.strokePath()
                } else {
                    c.addPath(cg)
                    c.setStrokeColor(UIColor(hex: s.color).cgColor)
                    c.setLineWidth(w)
                    c.strokePath()
                }
            }
        }
    }
}

struct DrawingLayer: View {
    let strokes: [DrawStroke]
    var current: DrawStroke?

    var body: some View {
        Canvas { ctx, size in
            for s in strokes + (current.map { [$0] } ?? []) {
                let path = Doodle.path(s, in: size)
                let w = s.width * size.width
                if s.neon {
                    ctx.drawLayer { layer in
                        layer.addFilter(.budgetShadow(color: Color(hex: s.color), radius: w * 0.9))
                        layer.stroke(path, with: .color(Color(hex: s.color)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                    }
                    ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.45, lineCap: .round, lineJoin: .round))
                } else {
                    ctx.stroke(path, with: .color(Color(hex: s.color)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// Catches finger strokes while the Draw tool is open.
struct DrawCapture: View {
    @Binding var strokes: [DrawStroke]
    @Binding var current: DrawStroke?
    let color: UInt32
    let width: CGFloat
    let neon: Bool
    var onBegin: () -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = CGPoint(x: min(1, max(0, v.location.x / max(1, geo.size.width))), y: min(1, max(0, v.location.y / max(1, geo.size.height))))
                            if current == nil {
                                onBegin()
                                current = DrawStroke(points: [p], color: color, width: width, neon: neon)
                            } else if let last = current?.points.last, hypot((last.x - p.x) * geo.size.width, (last.y - p.y) * geo.size.height) > 1.5 {
                                current?.points.append(p)
                            }
                        }
                        .onEnded { _ in
                            if let current { strokes.append(current) }
                            current = nil
                        }
                )
        }
    }
}

// Colour, size and neon for the pen, plus undo-stroke and clear.
struct DrawPanel: View {
    @Binding var color: UInt32
    @Binding var width: CGFloat
    @Binding var neon: Bool
    var canUndo: Bool
    var onUndo: () -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { neon.toggle() } label: {
                        Label("Neon", systemImage: "wand.and.rays").font(.jakarta(12, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(neon ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
                    }
                    .buttonStyle(BouncyStyle())
                    ForEach(Doodle.colors, id: \.self) { c in
                        Button { color = c } label: {
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white, lineWidth: color == c ? 3 : 1))
                                .scaleEffect(color == c ? 1.12 : 1)
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 12) {
                Image(systemName: "scribble").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.pink)
                Slider(value: $width, in: 0.004...0.04).tint(Theme.pink)
                Circle().fill(Color(hex: color)).frame(width: max(6, width * 600), height: max(6, width * 600)).frame(width: 26)
                Button(action: onUndo) { Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(canUndo ? 0.9 : 0.3)) }
                    .disabled(!canUndo)
                Button(action: onClear) { Image(systemName: "trash.circle.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(canUndo ? 0.9 : 0.3)) }
                    .disabled(!canUndo)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Cropping video frames

enum VideoCrop {
    // Keep the full source visible in the portrait canvas. No stretch or crop.
    static func fit(_ image: CIImage, _ size: CGSize) -> CIImage {
        let e = image.extent
        let scale = min(size.width / max(1, e.width), size.height / max(1, e.height))
        let transform = CGAffineTransform(translationX: -e.minX, y: -e.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (size.width - e.width * scale) / 2, y: (size.height - e.height * scale) / 2))
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        return image.transformed(by: transform).composited(over: background).cropped(to: background.extent)
    }

    // The part of a frame inside `unit` (0…1, measured from the top-left), moved to 0,0.
    static func cut(_ img: CIImage, _ unit: CGRect) -> CIImage {
        let e = img.extent
        let r = CGRect(x: e.minX + unit.minX * e.width, y: e.minY + (1 - unit.maxY) * e.height,
                       width: unit.width * e.width, height: unit.height * e.height)
        return img.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }

    // Fills a size with a picture (the live preview keeps the video's size).
    static func fill(_ img: CIImage, _ size: CGSize) -> CIImage {
        let e = img.extent
        let k = max(size.width / max(1, e.width), size.height / max(1, e.height))
        let scaled = img.transformed(by: CGAffineTransform(scaleX: k, y: k))
        let dx = (size.width - e.width * k) / 2, dy = (size.height - e.height * k) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: CGRect(origin: .zero, size: size))
    }
}

struct EditorCrop: Identifiable {
    let id = UUID()
    let image: UIImage
    let slide: Int?   // nil = the video
}
