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

// All the stickers plus one gesture layer on top of the preview. One finger
// drags the sticker under it (drop it on the bin to delete), two fingers
// pinch to resize and twist to turn, a tap edits it. Touching empty space
// taps / swipes the media underneath instead.
struct StickerCanvas: View {
    @Binding var stickers: [TextSticker]
    let size: CGSize
    var onEdit: (TextSticker) -> Void
    var onTapEmpty: () -> Void
    var onSwipe: (Int) -> Void
    var onBegin: () -> Void

    private enum Mode { case sticker, swipe }
    @State private var rects: [UUID: CGRect] = [:]
    @State private var mode: Mode?
    @State private var grabbed: UUID?
    @State private var selected: UUID?
    @State private var drag: CGSize = .zero
    @State private var transformTarget: UUID?
    @State private var pinch: CGFloat = 1
    @State private var twist: Angle = .zero
    @State private var overTrash = false

    var body: some View {
        ZStack {
            ForEach(stickers) { sticker in
                let isGrabbed = grabbed == sticker.id
                let isTransformed = transformTarget == sticker.id
                StickerLabel(sticker: sticker, width: size.width)
                    .background {
                        GeometryReader { g in
                            Color.clear.preference(key: StickerRectsKey.self, value: [sticker.id: g.frame(in: .named("stickerCanvas"))])
                        }
                    }
                    .scaleEffect((isTransformed ? pinch : 1) * (isGrabbed ? 1.06 : 1))
                    .rotationEffect(.radians(sticker.rotation) + (isTransformed ? twist : .zero))
                    .opacity(isGrabbed && overTrash ? 0.45 : 1)
                    .shadow(color: selected == sticker.id ? Theme.main.opacity(0.6) : .clear, radius: 10)
                    .position(x: sticker.x * size.width + (isGrabbed ? drag.width : 0), y: sticker.y * size.height + (isGrabbed ? drag.height : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isGrabbed)
            }
            if mode == .sticker {
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
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "stickerCanvas")
        .onPreferenceChange(StickerRectsKey.self) { rects = $0 }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(rotateGesture)
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("stickerCanvas")).onEnded { v in
                if let id = hit(v.location), let sticker = stickers.first(where: { $0.id == id }) {
                    selected = id
                    onEdit(sticker)
                } else {
                    selected = nil
                    onTapEmpty()
                }
            }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: overTrash)
        .sensoryFeedback(.selection, trigger: grabbed)
    }

    private func hit(_ point: CGPoint) -> UUID? {
        for sticker in stickers.reversed() {
            if let rect = rects[sticker.id], rect.insetBy(dx: -18, dy: -18).contains(point) { return sticker.id }
        }
        return nil
    }

    private func isOverTrash(_ id: UUID, _ translation: CGSize) -> Bool {
        guard let sticker = stickers.first(where: { $0.id == id }) else { return false }
        let x = sticker.x * size.width + translation.width
        let y = sticker.y * size.height + translation.height
        return y > size.height - 100 && abs(x - size.width / 2) < 90
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("stickerCanvas"))
            .onChanged { v in
                if mode == nil {
                    if let id = hit(v.startLocation) {
                        mode = .sticker
                        grabbed = id
                        selected = id
                        onBegin()
                    } else {
                        mode = .swipe
                    }
                }
                guard mode == .sticker, let id = grabbed else { return }
                drag = v.translation
                let trash = isOverTrash(id, v.translation)
                if trash != overTrash { overTrash = trash }
            }
            .onEnded { v in
                defer {
                    mode = nil
                    grabbed = nil
                    drag = .zero
                    overTrash = false
                }
                if mode == .swipe {
                    if abs(v.translation.width) > 50, abs(v.translation.width) > abs(v.translation.height) {
                        onSwipe(v.translation.width < 0 ? 1 : -1)
                    }
                    return
                }
                guard let id = grabbed, let i = stickers.firstIndex(where: { $0.id == id }) else { return }
                if isOverTrash(id, v.translation) {
                    withAnimation(.snappy) { stickers.remove(at: i) }
                    selected = nil
                } else {
                    stickers[i].x = min(0.97, max(0.03, stickers[i].x + v.translation.width / size.width))
                    stickers[i].y = min(0.97, max(0.03, stickers[i].y + v.translation.height / size.height))
                }
            }
    }

    private func target() -> UUID? {
        transformTarget ?? grabbed ?? selected ?? stickers.last?.id
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if transformTarget == nil {
                    transformTarget = target()
                    if transformTarget != nil { onBegin() }
                }
                pinch = v.magnification
            }
            .onEnded { v in
                if let id = transformTarget, let i = stickers.firstIndex(where: { $0.id == id }) {
                    stickers[i].scale = min(4, max(0.35, stickers[i].scale * v.magnification))
                }
                pinch = 1
                if twist == .zero { transformTarget = nil }
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { v in
                if transformTarget == nil {
                    transformTarget = target()
                    if transformTarget != nil { onBegin() }
                }
                twist = v.rotation
            }
            .onEnded { v in
                if let id = transformTarget, let i = stickers.firstIndex(where: { $0.id == id }) {
                    stickers[i].rotation += v.rotation.radians
                }
                twist = .zero
                if pinch == 1 { transformTarget = nil }
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
