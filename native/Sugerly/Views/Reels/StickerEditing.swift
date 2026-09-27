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

// A text or emoji sticker on the preview: drag to move, pinch to resize,
// twist to turn, tap to edit, drop on the bin to delete.
struct StickerView: View {
    @Binding var sticker: TextSticker
    let frame: CGSize
    var onEdit: () -> Void
    var onDragging: (Bool, Bool) -> Void
    var onDrop: (Bool) -> Void
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var twist: Angle = .zero
    @State private var active = false

    private var fontSize: CGFloat { frame.width * sticker.baseSize * sticker.scale }

    private func overTrash(_ translation: CGSize) -> Bool {
        let y = sticker.y * frame.height + translation.height
        let x = sticker.x * frame.width + translation.width
        return y > frame.height - 90 && abs(x - frame.width / 2) < 80
    }

    var body: some View {
        if !sticker.text.isEmpty {
            label
                .scaleEffect(pinch * (active ? 1.06 : 1))
                .rotationEffect(.radians(sticker.rotation) + twist)
                .opacity(active && overTrash(drag) ? 0.5 : 1)
                .contentShape(Rectangle())
                .highPriorityGesture(moveGesture)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { pinch = $0.magnification }
                        .onEnded { v in
                            sticker.scale = min(4, max(0.35, sticker.scale * v.magnification))
                            pinch = 1
                        }
                )
                .simultaneousGesture(
                    RotateGesture()
                        .onChanged { twist = $0.rotation }
                        .onEnded { v in
                            sticker.rotation += v.rotation.radians
                            twist = .zero
                        }
                )
                .onTapGesture(perform: onEdit)
                .position(x: sticker.x * frame.width + drag.width, y: sticker.y * frame.height + drag.height)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if !active { withAnimation(.spring(response: 0.25)) { active = true } }
                drag = v.translation
                onDragging(true, overTrash(v.translation))
            }
            .onEnded { v in
                let trash = overTrash(v.translation)
                if !trash {
                    sticker.x = min(0.97, max(0.03, sticker.x + v.translation.width / frame.width))
                    sticker.y = min(0.97, max(0.03, sticker.y + v.translation.height / frame.height))
                }
                drag = .zero
                withAnimation(.spring(response: 0.25)) { active = false }
                onDragging(false, false)
                onDrop(trash)
            }
    }

    @ViewBuilder
    private var label: some View {
        if sticker.isEmoji {
            Text(sticker.text).font(.system(size: fontSize)).fixedSize()
        } else {
            let size = fontSize
            Text(sticker.text)
                .font(.custom(sticker.font.uiName, size: size))
                .foregroundStyle(Color(hex: sticker.inkColor))
                .multilineTextAlignment(sticker.textAlignment)
                .frame(maxWidth: frame.width * 0.9)
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
