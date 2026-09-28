import SwiftUI
import UIKit
import AVFoundation
import CoreImage

// MARK: - Face filters (dog ears, bunny, crown…)

// Drawn with vector shapes (no emoji), follow faces live in the camera,
// and get baked into the video / photos when you post.
enum FaceFilter: String, CaseIterable, Identifiable {
    case none, dog, cat, bunny, bear, crown, hearts, blush, glasses
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .dog: return "Puppy"
        case .cat: return "Kitty"
        case .bunny: return "Bunny"
        case .bear: return "Bear"
        case .crown: return "Crown"
        case .hearts: return "Hearts"
        case .blush: return "Blush"
        case .glasses: return "Shades"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .dog: return "dog.fill"
        case .cat: return "cat.fill"
        case .bunny: return "hare.fill"
        case .bear: return "pawprint.fill"
        case .crown: return "crown.fill"
        case .hearts: return "heart.fill"
        case .blush: return "sparkles"
        case .glasses: return "eyeglasses"
        }
    }

    var tint: Color {
        switch self {
        case .none: return .white
        case .dog, .bear: return Color(hex: 0xC98E6B)
        case .cat: return Color(hex: 0xB9A7B8)
        case .bunny: return Color(hex: 0xFFB6C9)
        case .crown: return Color(hex: 0xFFD166)
        case .hearts, .glasses: return Color(hex: 0xFF6F91)
        case .blush: return Color(hex: 0xFF9EB8)
        }
    }
}

// The artwork for one filter, drawn around a face box. The face sits in the
// middle of a 400×440 canvas: x 100…300, y 158…358.
enum FaceArt {
    static let canvas = CGSize(width: 400, height: 440)
    static let face = CGRect(x: 100, y: 158.4, width: 200, height: 200)
    static let widthFactor: CGFloat = canvas.width / face.width
    static let faceCenterFromTop: CGFloat = face.midY / canvas.height
    static let aspect: CGFloat = canvas.height / canvas.width

    nonisolated(unsafe) private static var cache: [FaceFilter: UIImage] = [:]
    private static let lock = NSLock()

    static func image(_ filter: FaceFilter) -> UIImage? {
        guard filter != .none else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[filter] { return hit }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in draw(filter, ctx.cgContext) }
        cache[filter] = img
        return img
    }

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor { UIColor(hex: hex, alpha: alpha) }

    private static func ellipse(_ c: CGContext, center: CGPoint, size: CGSize, angle: CGFloat = 0, fill: UIColor, stroke: UIColor? = nil, width: CGFloat = 4) {
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: angle)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        c.setFillColor(fill.cgColor)
        c.fillEllipse(in: rect)
        if let stroke {
            c.setStrokeColor(stroke.cgColor)
            c.setLineWidth(width)
            c.strokeEllipse(in: rect.insetBy(dx: width / 2, dy: width / 2))
        }
        c.restoreGState()
    }

    static func heart(in r: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3),
                   controlPoint1: CGPoint(x: r.midX - r.width * 0.1, y: r.maxY - r.height * 0.15),
                   controlPoint2: CGPoint(x: r.minX, y: r.minY + r.height * 0.62))
        p.addArc(withCenter: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addArc(withCenter: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   controlPoint1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62),
                   controlPoint2: CGPoint(x: r.midX + r.width * 0.1, y: r.maxY - r.height * 0.15))
        p.close()
        return p
    }

    static func sparkle(at c: CGPoint, radius: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        let inner = radius * 0.28
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? radius : inner
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close()
        return p
    }

    private static func draw(_ filter: FaceFilter, _ c: CGContext) {
        let f = face
        let midX = f.midX
        let y = { (k: CGFloat) in f.minY + f.height * k }
        c.setLineJoin(.round)
        c.setLineCap(.round)
        switch filter {
        case .none:
            break
        case .dog:
            ellipse(c, center: CGPoint(x: f.minX + 6, y: y(0.14)), size: CGSize(width: 82, height: 158), angle: 0.38, fill: color(0x8B5A3C))
            ellipse(c, center: CGPoint(x: f.minX + 10, y: y(0.18)), size: CGSize(width: 46, height: 112), angle: 0.38, fill: color(0xC98E6B))
            ellipse(c, center: CGPoint(x: f.maxX - 6, y: y(0.14)), size: CGSize(width: 82, height: 158), angle: -0.38, fill: color(0x8B5A3C))
            ellipse(c, center: CGPoint(x: f.maxX - 10, y: y(0.18)), size: CGSize(width: 46, height: 112), angle: -0.38, fill: color(0xC98E6B))
            // tongue
            let tongue = UIBezierPath(roundedRect: CGRect(x: midX - 20, y: y(0.76), width: 40, height: 56), byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: 20, height: 20))
            color(0xFF6F91).setFill()
            tongue.fill()
            color(0xD94A6E).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: midX, y: y(0.78)))
            line.addLine(to: CGPoint(x: midX, y: y(0.95)))
            line.lineWidth = 3
            line.stroke()
            // nose
            ellipse(c, center: CGPoint(x: midX, y: y(0.6)), size: CGSize(width: 66, height: 44), fill: color(0x2B1B17))
            ellipse(c, center: CGPoint(x: midX - 12, y: y(0.56)), size: CGSize(width: 20, height: 11), fill: color(0xFFFFFF, 0.55))
        case .cat:
            for side in [-1.0, 1.0] as [CGFloat] {
                let outer = UIBezierPath()
                outer.move(to: CGPoint(x: midX + side * 98, y: y(0.2)))
                outer.addLine(to: CGPoint(x: midX + side * 92, y: y(-0.34)))
                outer.addLine(to: CGPoint(x: midX + side * 18, y: y(0.02)))
                outer.close()
                color(0xF5E6EC).setFill()
                outer.fill()
                color(0x9A8F99).setStroke()
                outer.lineWidth = 5
                outer.lineJoinStyle = .round
                outer.stroke()
                let inner = UIBezierPath()
                inner.move(to: CGPoint(x: midX + side * 84, y: y(0.12)))
                inner.addLine(to: CGPoint(x: midX + side * 82, y: y(-0.2)))
                inner.addLine(to: CGPoint(x: midX + side * 38, y: y(0.02)))
                inner.close()
                color(0xFF9EB8).setFill()
                inner.fill()
                // whiskers
                color(0x4A3B42).setStroke()
                for (i, dy) in ([-0.05, 0.02, 0.09] as [CGFloat]).enumerated() {
                    let w = UIBezierPath()
                    w.move(to: CGPoint(x: midX + side * 34, y: y(0.66)))
                    w.addLine(to: CGPoint(x: midX + side * (116 - CGFloat(i) * 4), y: y(0.66 + dy)))
                    w.lineWidth = 3
                    w.stroke()
                }
                ellipse(c, center: CGPoint(x: midX + side * 58, y: y(0.7)), size: CGSize(width: 40, height: 22), fill: color(0xFF8FAB, 0.45))
            }
            let nose = UIBezierPath()
            nose.move(to: CGPoint(x: midX - 16, y: y(0.57)))
            nose.addLine(to: CGPoint(x: midX + 16, y: y(0.57)))
            nose.addLine(to: CGPoint(x: midX, y: y(0.66)))
            nose.close()
            color(0xFF6F91).setFill()
            nose.fill()
        case .bunny:
            for side in [-1.0, 1.0] as [CGFloat] {
                ellipse(c, center: CGPoint(x: midX + side * 46, y: y(-0.36)), size: CGSize(width: 62, height: 182), angle: side * 0.16, fill: color(0xFFFFFF), stroke: color(0xE7D9DF), width: 4)
                ellipse(c, center: CGPoint(x: midX + side * 46, y: y(-0.33)), size: CGSize(width: 30, height: 132), angle: side * 0.16, fill: color(0xFFB6C9))
            }
            ellipse(c, center: CGPoint(x: midX, y: y(0.6)), size: CGSize(width: 30, height: 20), fill: color(0xFF8FAB))
            for side in [-1.0, 1.0] as [CGFloat] {
                let tooth = UIBezierPath(roundedRect: CGRect(x: midX + (side < 0 ? -15 : 1), y: y(0.7), width: 14, height: 22), cornerRadius: 4)
                UIColor.white.setFill()
                tooth.fill()
                color(0xD8CDD2).setStroke()
                tooth.lineWidth = 2
                tooth.stroke()
            }
        case .bear:
            for side in [-1.0, 1.0] as [CGFloat] {
                ellipse(c, center: CGPoint(x: midX + side * 84, y: y(0.02)), size: CGSize(width: 78, height: 78), fill: color(0x8B5A3C))
                ellipse(c, center: CGPoint(x: midX + side * 84, y: y(0.03)), size: CGSize(width: 40, height: 40), fill: color(0xD9A77F))
            }
            ellipse(c, center: CGPoint(x: midX, y: y(0.66)), size: CGSize(width: 92, height: 64), fill: color(0xE8C3A0, 0.85))
            ellipse(c, center: CGPoint(x: midX, y: y(0.6)), size: CGSize(width: 42, height: 28), fill: color(0x2B1B17))
            ellipse(c, center: CGPoint(x: midX - 8, y: y(0.57)), size: CGSize(width: 12, height: 7), fill: color(0xFFFFFF, 0.55))
        case .crown:
            let base = y(-0.08)
            let top = y(-0.52)
            let crown = UIBezierPath()
            crown.move(to: CGPoint(x: midX - 82, y: base))
            crown.addLine(to: CGPoint(x: midX - 92, y: top + 22))
            crown.addLine(to: CGPoint(x: midX - 46, y: top + 48))
            crown.addLine(to: CGPoint(x: midX, y: top))
            crown.addLine(to: CGPoint(x: midX + 46, y: top + 48))
            crown.addLine(to: CGPoint(x: midX + 92, y: top + 22))
            crown.addLine(to: CGPoint(x: midX + 82, y: base))
            crown.close()
            c.saveGState()
            crown.addClip()
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0xFFE08A).cgColor, color(0xF0A020).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: CGPoint(x: midX, y: top), end: CGPoint(x: midX, y: base), options: [])
            c.restoreGState()
            color(0xC98A10).setStroke()
            crown.lineWidth = 5
            crown.lineJoinStyle = .round
            crown.stroke()
            for (i, x) in ([-92, 0, 92] as [CGFloat]).enumerated() {
                let ty = i == 1 ? top : top + 22
                ellipse(c, center: CGPoint(x: midX + x, y: ty), size: CGSize(width: 18, height: 18), fill: color(i == 1 ? 0xFF6F91 : 0x7CBEFF))
            }
            ellipse(c, center: CGPoint(x: midX, y: base - 20), size: CGSize(width: 22, height: 22), fill: color(0xFF6F91), stroke: color(0xFFFFFF, 0.8), width: 3)
            color(0xFFFFFF).setFill()
            sparkle(at: CGPoint(x: midX - 128, y: top + 10), radius: 16).fill()
            sparkle(at: CGPoint(x: midX + 126, y: top - 4), radius: 12).fill()
        case .hearts:
            let colors: [UInt32] = [0xFF6F91, 0xFF9EB8, 0xD9577F, 0xFFB6C9, 0xFF6F91, 0xFF9EB8, 0xD9577F]
            for i in 0..<7 {
                let a = CGFloat.pi * (1.1 + 0.8 * CGFloat(i) / 6)
                let cx = midX + cos(a) * 128
                let cy = y(-0.14) + sin(a) * 58
                let s: CGFloat = i % 2 == 0 ? 34 : 26
                let path = heart(in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s * 0.9))
                color(colors[i]).setFill()
                path.fill()
                UIColor.white.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 2.5
                path.stroke()
            }
        case .blush:
            for side in [-1.0, 1.0] as [CGFloat] {
                let center = CGPoint(x: midX + side * 60, y: y(0.66))
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0xFF7A9C, 0.6).cgColor, color(0xFF7A9C, 0).cgColor] as CFArray, locations: [0, 1])!
                c.saveGState()
                c.translateBy(x: center.x, y: center.y)
                c.scaleBy(x: 1.5, y: 1)
                c.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 26, options: [])
                c.restoreGState()
                color(0xFFFFFF).setFill()
                sparkle(at: CGPoint(x: midX + side * 96, y: y(0.26)), radius: 14).fill()
                color(0xFFE08A).setFill()
                sparkle(at: CGPoint(x: midX + side * 112, y: y(0.08)), radius: 9).fill()
            }
        case .glasses:
            for side in [-1.0, 1.0] as [CGFloat] {
                let r = CGRect(x: midX + side * 46 - 38, y: y(0.3), width: 76, height: 66)
                let path = heart(in: r)
                color(0xFF6F91, 0.82).setFill()
                path.fill()
                color(0xD9577F).setStroke()
                path.lineWidth = 6
                path.stroke()
                ellipse(c, center: CGPoint(x: r.minX + 24, y: r.minY + 20), size: CGSize(width: 16, height: 9), angle: -0.5, fill: color(0xFFFFFF, 0.7))
                let arm = UIBezierPath()
                arm.move(to: CGPoint(x: midX + side * 82, y: y(0.38)))
                arm.addLine(to: CGPoint(x: midX + side * 104, y: y(0.36)))
                arm.lineWidth = 6
                arm.stroke()
            }
            let bridge = UIBezierPath()
            bridge.move(to: CGPoint(x: midX - 10, y: y(0.36)))
            bridge.addQuadCurve(to: CGPoint(x: midX + 10, y: y(0.36)), controlPoint: CGPoint(x: midX, y: y(0.31)))
            color(0xD9577F).setStroke()
            bridge.lineWidth = 6
            bridge.stroke()
        }
    }
}

// MARK: - Baking into frames (export + editor preview)

// Finds faces in a frame and draws the filter on each one. Positions are
// smoothed between frames so the ears don't jitter.
final class FaceFilterRenderer: @unchecked Sendable {
    let filter: FaceFilter
    private let detector: CIDetector?
    private let art: CIImage?
    private var last: [CGRect] = []
    private var misses = 0
    private let lock = NSLock()

    init(_ filter: FaceFilter, video: Bool = true) {
        self.filter = filter
        detector = filter == .none ? nil : CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [
            CIDetectorAccuracy: video ? CIDetectorAccuracyLow : CIDetectorAccuracyHigh,
            CIDetectorTracking: video,
        ])
        art = FaceArt.image(filter)?.cgImage.map { CIImage(cgImage: $0) }
    }

    func apply(_ image: CIImage) -> CIImage {
        guard let detector, let art else { return image }
        lock.lock()
        defer { lock.unlock() }
        let extent = image.extent
        let k = min(1, 540 / max(1, max(extent.width, extent.height)))
        let small = k < 1 ? image.transformed(by: CGAffineTransform(scaleX: k, y: k)) : image
        let found = (detector.features(in: small, options: [CIDetectorImageOrientation: 1]) as? [CIFaceFeature] ?? []).prefix(4)
        var faces: [(CGRect, CGFloat)] = found.map { f in
            let b = CGRect(x: f.bounds.minX / k, y: f.bounds.minY / k, width: f.bounds.width / k, height: f.bounds.height / k)
            return (b, f.hasFaceAngle ? CGFloat(f.faceAngle) * .pi / 180 : 0)
        }
        if faces.isEmpty {
            misses += 1
            if misses < 6 { faces = last.map { ($0, 0) } } else { last = [] }
        } else {
            misses = 0
            faces = faces.map { face in
                guard let near = last.min(by: { distance($0, face.0) < distance($1, face.0) }), distance(near, face.0) < face.0.width * 0.6 else { return face }
                return (lerp(near, face.0, 0.55), face.1)
            }
            last = faces.map(\.0)
        }
        var out = image
        let anchor = CGPoint(x: art.extent.width / 2, y: art.extent.height * (1 - FaceArt.faceCenterFromTop))
        for (b, angle) in faces {
            let scale = b.width * FaceArt.widthFactor / art.extent.width
            var t = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            t = t.concatenating(CGAffineTransform(rotationAngle: angle))
            t = t.concatenating(CGAffineTransform(translationX: b.midX, y: b.midY))
            out = art.transformed(by: t).composited(over: out)
        }
        return out.cropped(to: extent)
    }

    // One still picture (photo mode / slideshows).
    static func bake(_ image: UIImage, _ filter: FaceFilter) -> UIImage {
        guard filter != .none else { return image }
        let upright = StickerKit.normalized(image, maxSide: 2048)
        guard let cg = upright.cgImage else { return image }
        let out = FaceFilterRenderer(filter, video: false).apply(CIImage(cgImage: cg))
        guard let rendered = CIContext().createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: rendered)
    }

    private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat { hypot(a.midX - b.midX, a.midY - b.midY) }
    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}

// MARK: - Live camera tracking

@MainActor
@Observable
final class FaceTracker {
    var faces: [CGRect] = []
    @ObservationIgnored weak var layer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var lastSeen = Date.distantPast

    func update(_ objects: [AVMetadataObject]) {
        guard let layer else { return }
        let rects = objects.compactMap { $0 as? AVMetadataFaceObject }.prefix(4).compactMap { layer.transformedMetadataObject(for: $0)?.bounds }
        if rects.isEmpty {
            if Date().timeIntervalSince(lastSeen) > 0.35, !faces.isEmpty { faces = [] }
            return
        }
        lastSeen = Date()
        faces = rects.map { r in
            guard let near = faces.min(by: { hypot($0.midX - r.midX, $0.midY - r.midY) < hypot($1.midX - r.midX, $1.midY - r.midY) }),
                  hypot(near.midX - r.midX, near.midY - r.midY) < r.width * 0.6 else { return r }
            let t: CGFloat = 0.5
            return CGRect(x: near.minX + (r.minX - near.minX) * t, y: near.minY + (r.minY - near.minY) * t,
                          width: near.width + (r.width - near.width) * t, height: near.height + (r.height - near.height) * t)
        }
    }
}

// The filter drawn over the live camera, following each face.
struct FaceOverlayView: View {
    let tracker: FaceTracker
    let filter: FaceFilter

    var body: some View {
        if let art = FaceArt.image(filter) {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(tracker.faces.indices, id: \.self) { i in
                    let b = tracker.faces[i]
                    let w = b.width * FaceArt.widthFactor
                    let h = w * FaceArt.aspect
                    Image(uiImage: art).resizable()
                        .frame(width: w, height: h)
                        .position(x: b.midX, y: b.midY - (FaceArt.faceCenterFromTop - 0.5) * h)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

// A round picker of face filters, like the camera carousels in other apps.
struct FaceFilterPicker: View {
    @Binding var selection: FaceFilter
    var dark = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FaceFilter.allCases) { f in
                    let on = selection == f
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = f } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: f.icon)
                                .font(.system(size: on ? 22 : 18, weight: .bold))
                                .foregroundStyle(f == .none ? (dark ? Color.white : Palette.text2) : f.tint)
                                .frame(width: on ? 58 : 50, height: on ? 58 : 50)
                                .background(dark ? Color.black.opacity(0.35) : Palette.surface2, in: Circle())
                                .overlay(Circle().strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.25)), lineWidth: on ? 3 : 1))
                            Text(f.label).font(.jakarta(10, .bold)).foregroundStyle(dark ? .white.opacity(on ? 1 : 0.7) : Palette.text2)
                        }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.88))
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
