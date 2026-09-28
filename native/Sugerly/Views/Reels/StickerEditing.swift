import SwiftUI
import UIKit
import CoreImage

// Small filtered previews for the filter picker, and the slideshow look.
enum FilterThumbs {
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func make(_ base: UIImage, _ filter: ReelFilter) -> UIImage {
        let key = "\(ObjectIdentifier(base).hashValue)-\(filter.rawValue)"
        if let hit = cache[key] { return hit }
        let out = apply(ReelLook(filter: filter), to: base, maxSide: 180)
        cache[key] = out
        return out
    }

    static func apply(_ look: ReelLook, to image: UIImage, maxSide: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return image }
        var ci = CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(image.imageOrientation))
        let longest = max(ci.extent.width, ci.extent.height)
        if longest > maxSide {
            let k = maxSide / longest
            ci = ci.transformed(by: CGAffineTransform(scaleX: k, y: k))
        }
        let out = look.isNeutral ? ci : look.apply(ci)
        return context.createCGImage(out, from: out.extent).map { UIImage(cgImage: $0) } ?? image
    }

    static func applyAll(_ look: ReelLook, to images: [UIImage]) async -> [UIImage] {
        images.map { apply(look, to: $0, maxSide: 1280) }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// Where each sticker sits on the canvas (for finding the one under a finger).
struct StickerRectsKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// All the stickers plus one UIKit touch layer on top of the preview. One or
// two fingers move the sticker under them, and at the same time two fingers
// pinch to resize and twist to turn (like TikTok). Drop it on the bin to
// delete, tap to edit. Touching empty space taps / swipes the media instead.
struct StickerCanvas: View {
    @Binding var stickers: [TextSticker]
    let size: CGSize
    var onEdit: (TextSticker) -> Void
    var onTapEmpty: () -> Void
    var onSwipe: (Int) -> Void
    var onBegin: () -> Void

    @State private var rects: [UUID: CGRect] = [:]
    @State private var grabbed: UUID?
    @State private var selected: UUID?
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var twist: Double = 0
    @State private var overTrash = false

    var body: some View {
        ZStack {
            ForEach(stickers) { sticker in
                let live = grabbed == sticker.id
                StickerLabel(sticker: sticker, width: size.width)
                    .background {
                        GeometryReader { g in
                            Color.clear.preference(key: StickerRectsKey.self, value: [sticker.id: g.frame(in: .named("stickerCanvas"))])
                        }
                    }
                    .scaleEffect(live ? pinch * 1.04 : 1)
                    .rotationEffect(.radians(sticker.rotation + (live ? twist : 0)))
                    .opacity(live && overTrash ? 0.45 : 1)
                    .shadow(color: selected == sticker.id ? Theme.main.opacity(0.6) : .clear, radius: 10)
                    .position(x: sticker.x * size.width + (live ? drag.width : 0), y: sticker.y * size.height + (live ? drag.height : 0))
            }
            if grabbed != nil {
                VStack {
                    Spacer()
                    Image(systemName: "trash.fill")
                        .font(.system(size: overTrash ? 24 : 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: overTrash ? 66 : 50, height: overTrash ? 66 : 50)
                        .background(overTrash ? Palette.danger : Color.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: overTrash)
                        .padding(.bottom, 16)
                }
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
            }
            StickerTouchLayer(
                hit: { hit($0) },
                fallback: { selected ?? stickers.last?.id },
                onStart: { id in
                    grabbed = id
                    selected = id
                    onBegin()
                },
                onChange: { id, t, s, r in
                    drag = t
                    pinch = s
                    twist = r
                    let trash = isOverTrash(id, t)
                    if trash != overTrash { overTrash = trash }
                },
                onEnd: { id, t, s, r in commit(id, t, s, r) },
                onSwipe: { t in
                    if abs(t.width) > 50, abs(t.width) > abs(t.height) { onSwipe(t.width < 0 ? 1 : -1) }
                },
                onTap: { point in
                    if let id = hit(point), let sticker = stickers.first(where: { $0.id == id }) {
                        selected = id
                        onEdit(sticker)
                    } else {
                        selected = nil
                        onTapEmpty()
                    }
                }
            )
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "stickerCanvas")
        .onPreferenceChange(StickerRectsKey.self) { rects = $0 }
        .sensoryFeedback(.impact(weight: .medium), trigger: overTrash)
        .sensoryFeedback(.selection, trigger: grabbed)
    }

    private func hit(_ point: CGPoint) -> UUID? {
        for sticker in stickers.reversed() {
            if let rect = rects[sticker.id], rect.insetBy(dx: -22, dy: -22).contains(point) { return sticker.id }
        }
        return nil
    }

    private func isOverTrash(_ id: UUID, _ translation: CGSize) -> Bool {
        guard let sticker = stickers.first(where: { $0.id == id }) else { return false }
        let x = sticker.x * size.width + translation.width
        let y = sticker.y * size.height + translation.height
        return y > size.height - 100 && abs(x - size.width / 2) < 90
    }

    private func commit(_ id: UUID, _ t: CGSize, _ s: CGFloat, _ r: Double) {
        defer {
            grabbed = nil
            drag = .zero
            pinch = 1
            twist = 0
            overTrash = false
        }
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        if isOverTrash(id, t) {
            withAnimation(.snappy) { stickers.remove(at: i) }
            selected = nil
            return
        }
        var next = stickers[i]
        next.x = min(0.97, max(0.03, next.x + t.width / max(1, size.width)))
        next.y = min(0.97, max(0.03, next.y + t.height / max(1, size.height)))
        next.scale = min(5, max(0.3, next.scale * s))
        next.rotation += r
        // Snap near-straight angles so text lines up easily.
        let quarter = Double.pi / 2
        let nearest = (next.rotation / quarter).rounded() * quarter
        if abs(next.rotation - nearest) < 0.06 { next.rotation = nearest }
        stickers[i] = next
    }
}

// UIKit recognisers (pan with 1–2 fingers + pinch + rotate, all together)
// feel much smoother than SwiftUI gestures for moving stickers.
struct StickerTouchLayer: UIViewRepresentable {
    var hit: (CGPoint) -> UUID?
    var fallback: () -> UUID?
    var onStart: (UUID) -> Void
    var onChange: (UUID, CGSize, CGFloat, Double) -> Void
    var onEnd: (UUID, CGSize, CGFloat, Double) -> Void
    var onSwipe: (CGSize) -> Void
    var onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let c = context.coordinator
        c.view = view
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.rotate(_:)))
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        for g in [pan, pinch, rotate] as [UIGestureRecognizer] {
            g.delegate = c
            g.delaysTouchesEnded = false
            view.addGestureRecognizer(g)
        }
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: StickerTouchLayer
        weak var view: UIView?
        private var target: UUID?
        private var swiping = false
        private var active = 0
        private var translation = CGSize.zero
        private var panBase = CGPoint.zero
        private var scale: CGFloat = 1
        private var scaleBase: CGFloat = 1
        private var rotation: Double = 0
        private var rotationBase: Double = 0

        init(_ parent: StickerTouchLayer) { self.parent = parent }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(g is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
        }

        private func begin(_ g: UIGestureRecognizer) {
            active += 1
            let isPan = g is UIPanGestureRecognizer
            if target == nil {
                var id = parent.hit(g.location(in: view))
                if id == nil {
                    for i in 0..<g.numberOfTouches {
                        if let h = parent.hit(g.location(ofTouch: i, in: view)) { id = h; break }
                    }
                }
                if id == nil, !isPan || g.numberOfTouches > 1 { id = parent.fallback() }
                if let id {
                    // A second finger turned a swipe into a sticker move.
                    if swiping { swiping = false; panBase = CGPoint(x: translation.width, y: translation.height); translation = .zero }
                    target = id
                    parent.onStart(id)
                } else if isPan {
                    swiping = true
                }
            }
        }

        private func push() {
            guard let target else { return }
            parent.onChange(target, translation, scale, rotation)
        }

        private func end() {
            active = max(0, active - 1)
            guard active == 0 else { return }
            if let target {
                parent.onEnd(target, translation, scale, rotation)
            } else if swiping {
                parent.onSwipe(translation)
            }
            target = nil
            swiping = false
            translation = .zero
            panBase = .zero
            scale = 1
            scaleBase = 1
            rotation = 0
            rotationBase = 0
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                begin(g)
                move(g)
            case .changed:
                move(g)
            case .ended, .cancelled, .failed:
                move(g)
                end()
            default: break
            }
        }

        private func move(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: view)
            translation = CGSize(width: t.x - panBase.x, height: t.y - panBase.y)
            push()
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                begin(g)
                scaleBase = scale
                scale = scaleBase * g.scale
                push()
            case .changed:
                scale = scaleBase * g.scale
                push()
            case .ended, .cancelled, .failed:
                end()
            default: break
            }
        }

        @objc func rotate(_ g: UIRotationGestureRecognizer) {
            switch g.state {
            case .began:
                begin(g)
                rotationBase = rotation
                rotation = rotationBase + Double(g.rotation)
                push()
            case .changed:
                rotation = rotationBase + Double(g.rotation)
                push()
            case .ended, .cancelled, .failed:
                end()
            default: break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onTap(g.location(in: view))
        }
    }
}

// How a sticker looks (no touches — the canvas handles those).
struct StickerLabel: View {
    let sticker: TextSticker
    let width: CGFloat

    private var fontSize: CGFloat { width * sticker.baseSize * sticker.scale }

    var body: some View {
        if sticker.isEmoji {
            Text(sticker.text).font(.system(size: fontSize)).fixedSize()
        } else {
            let size = fontSize
            Text(sticker.text)
                .font(.custom(sticker.font.uiName, size: size))
                .foregroundStyle(Color(hex: sticker.inkColor))
                .multilineTextAlignment(sticker.textAlignment)
                .frame(maxWidth: width * 0.9)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(OutlineText(on: sticker.style == .outline, color: sticker.color == 0x2A1620 ? .white : Color(hex: 0x2A1620)))
                .padding(.horizontal, size * 0.45)
                .padding(.vertical, size * 0.25)
                .background {
                    if sticker.style == .label {
                        RoundedRectangle(cornerRadius: size * 0.5, style: .continuous).fill(Color(hex: sticker.color))
                    }
                }
                .shadow(color: shadowColor, radius: sticker.style == .glow ? size * 0.4 : 4)
                .fixedSize()
        }
    }

    private var shadowColor: Color {
        switch sticker.style {
        case .glow: return Color(hex: sticker.color)
        case .label: return .black.opacity(0.15)
        default: return .black.opacity(0.45)
        }
    }
}

extension TextSticker {
    var textAlignment: TextAlignment {
        switch align {
        case .left: return .leading
        case .right: return .trailing
        default: return .center
        }
    }
}

// Four hard shadows in the outline colour make an outline around the text.
struct OutlineText: ViewModifier {
    let on: Bool
    let color: Color
    func body(content: Content) -> some View {
        if on {
            content
                .shadow(color: color, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: color, radius: 0, x: -1.5, y: -1.5)
                .shadow(color: color, radius: 0, x: 1.5, y: -1.5)
                .shadow(color: color, radius: 0, x: -1.5, y: 1.5)
        } else {
            content
        }
    }
}

struct TextStickerEditor: View {
    @State var sticker: TextSticker
    var onSave: (TextSticker) -> Void
    var onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    private let colors: [UInt32] = [0xFFFFFF, 0x2A1620, 0xFFB3D1, 0xD9577F, 0xFF4F8B, 0xB19CFF, 0x7CBEFF, 0x5FD3B0, 0xFFD166, 0xFF8A5B]
    private let aligns: [(NSTextAlignment, String)] = [(.left, "text.alignleft"), (.center, "text.aligncenter"), (.right, "text.alignright")]

    private var fieldInk: UInt32 {
        if sticker.style == .label { return sticker.inkColor }
        return sticker.color == 0xFFFFFF ? 0x2A1620 : sticker.color
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Delete") { onDelete(sticker.id); dismiss() }.foregroundStyle(Palette.danger).font(.jakarta(15, .bold))
                Spacer()
                Button("Done") {
                    if !sticker.text.trimmingCharacters(in: .whitespaces).isEmpty { onSave(sticker) }
                    dismiss()
                }
                .buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
            }
            TextField("Type something cute…", text: $sticker.text, axis: .vertical)
                .font(.custom(sticker.font.uiName, size: 26))
                .multilineTextAlignment(sticker.textAlignment)
                .foregroundStyle(Color(hex: fieldInk))
                .focused($focused)
                .padding(14)
                .background(sticker.style == .label ? Color(hex: sticker.color) : Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StickerFont.allCases, id: \.self) { f in
                        Button { sticker.font = f } label: {
                            Text(f.rawValue).font(.custom(f.uiName, size: 16))
                                .foregroundStyle(sticker.font == f ? Color.white : Palette.text)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(sticker.font == f ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.surface), in: Capsule())
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(StickerStyle.allCases, id: \.self) { st in
                    Chip(title: st.rawValue, active: sticker.style == st) { sticker.style = st }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(aligns, id: \.1) { item in
                    Button { sticker.align = item.0 } label: {
                        Image(systemName: item.1).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(sticker.align == item.0 ? Color.white : Palette.text2)
                            .frame(width: 40, height: 36)
                            .background(sticker.align == item.0 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.surface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle())
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { c in
                        Button { sticker.color = c } label: {
                            Circle().fill(Color(hex: c)).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(sticker.color == c ? Theme.pink : Palette.border, lineWidth: sticker.color == c ? 3 : 1))
                                .scaleEffect(sticker.color == c ? 1.12 : 1)
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .sugarBackground()
        .animation(.snappy, value: sticker)
        .onAppear { focused = true }
    }
}
