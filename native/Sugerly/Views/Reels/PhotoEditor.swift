import SwiftUI
import UIKit
import CoreImage

// Filters, face filters, adjustments, drawing, text and stickers drawn onto a photo, full size.
enum PhotoBaker {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func bake(_ image: UIImage, look: ReelLook, stickers: [TextSticker], face: FaceFilter = .none, strokes: [DrawStroke] = []) -> UIImage {
        guard !look.isNeutral || !stickers.isEmpty || face != .none || !strokes.isEmpty, let cg = image.cgImage else { return image }
        var ci = CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(image.imageOrientation))
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        if !look.isNeutral { ci = look.apply(ci) }
        if face != .none { ci = FaceFilterRenderer(face, video: false).apply(ci) }
        let width = ci.extent.width, height = ci.extent.height
        if let doodle = Doodle.render(strokes, size: CGSize(width: width, height: height))?.cgImage {
            ci = CIImage(cgImage: doodle).composited(over: ci)
        }
        for sticker in stickers where !sticker.text.isEmpty || sticker.image != nil {
            guard let sc = sticker.render(width: width).cgImage else { continue }
            let img = CIImage(cgImage: sc)
            let w = img.extent.width, h = img.extent.height
            let centred = CGAffineTransform(translationX: -w / 2, y: -h / 2)
            let turned = centred.concatenating(CGAffineTransform(rotationAngle: -CGFloat(sticker.rotation)))
            let placed = turned.concatenating(CGAffineTransform(translationX: sticker.x * width, y: (1 - sticker.y) * height))
            ci = img.transformed(by: placed).composited(over: ci)
        }
        guard let out = context.createCGImage(ci, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return image }
        return UIImage(cgImage: out)
    }

    static func rotate(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}

// The website's image editor, for posts and artworks: filters, adjust,
// face filters, text, stickers, drawing, rotate, undo.
struct PhotoEditorView: View {
    let original: UIImage
    var onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable {
        case filters = "Filters", face = "Face", adjust = "Adjust", text = "Text", stickers = "Stickers", draw = "Draw", rotate = "Rotate"
        var icon: String {
            switch self {
            case .filters: return "camera.filters"
            case .face: return "face.dashed.fill"
            case .adjust: return "slider.horizontal.3"
            case .text: return "textformat"
            case .stickers: return "star.square.on.square.fill"
            case .draw: return "scribble.variable"
            case .rotate: return "rotate.right"
            }
        }
    }

    struct Snapshot { var base: UIImage; var look: ReelLook; var stickers: [TextSticker]; var strokes: [DrawStroke] = []; var face: FaceFilter = .none }

    @State private var base: UIImage
    @State private var preview: UIImage?
    @State private var look = ReelLook()
    @State private var stickers: [TextSticker] = []
    @State private var tool: Tool = .filters
    @State private var history: [Snapshot] = []
    @State private var editingText: TextSticker?
    @State private var saving = false
    @State private var face: FaceFilter = .none
    @State private var strokes: [DrawStroke] = []
    @State private var drawing: DrawStroke?
    @State private var penColor: UInt32 = 0xFFFFFF
    @State private var penWidth: CGFloat = 0.012
    @State private var penNeon = false

    init(image: UIImage, onDone: @escaping (UIImage) -> Void) {
        original = image
        self.onDone = onDone
        _base = State(initialValue: image)
    }

    private var aspect: CGFloat { max(0.2, base.size.width / max(1, base.size.height)) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.font(.jakarta(15, .bold)).foregroundStyle(.white.opacity(0.85))
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(history.isEmpty ? 0.35 : 1))
                        .frame(width: 40, height: 40).background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(BouncyStyle())
                .disabled(history.isEmpty)
                Spacer()
                Text("Edit photo").font(.display(22)).foregroundStyle(.white)
                Spacer()
                Button { save() } label: {
                    if saving { ProgressView().tint(.white) } else { Text("Done") }
                }
                .buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
                .disabled(saving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            GeometryReader { geo in
                let fit = fitted(in: geo.size)
                ZStack {
                    Image(uiImage: preview ?? base).resizable().frame(width: fit.width, height: fit.height)
                    DrawingLayer(strokes: strokes, current: drawing)
                    StickerCanvas(stickers: $stickers, size: fit, onEdit: { sticker in
                        guard sticker.image == nil else { return }
                        checkpoint()
                        editingText = sticker
                    }, onTapEmpty: {}, onSwipe: { _ in }, onBegin: { checkpoint() })
                    if tool == .draw {
                        DrawCapture(strokes: $strokes, current: $drawing, color: penColor, width: penWidth, neon: penNeon) { checkpoint() }
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.main.opacity(0.3), radius: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)

            panel.frame(height: 118)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tool.allCases, id: \.self) { t in
                        Button {
                            if t == .rotate {
                                checkpoint()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { base = PhotoBaker.rotate(base) }
                                refreshPreview()
                                return
                            }
                            withAnimation(.snappy) { tool = t }
                            if t == .text { checkpoint(); editingText = TextSticker(text: "") }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: t.icon).font(.system(size: 18, weight: .bold))
                                Text(t.rawValue).font(.jakarta(11, .bold))
                            }
                            .foregroundStyle(tool == t ? .white : .white.opacity(0.65))
                            .frame(width: 66, height: 56)
                            .background(tool == t ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.1)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.9))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)
        }
        .background(Color(hex: 0x140A11).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: look) { _, _ in refreshPreview() }
        .onChange(of: face) { _, _ in refreshPreview() }
        .sheet(item: $editingText) { sticker in
            TextStickerEditor(sticker: sticker) { updated in
                if let i = stickers.firstIndex(where: { $0.id == updated.id }) { stickers[i] = updated } else { stickers.append(updated) }
            } onDelete: { id in stickers.removeAll { $0.id == id } }
            .presentationDetents([.height(470), .large])
            .presentationCornerRadius(30)
        }
    }

    private func fitted(in size: CGSize) -> CGSize {
        let w = min(size.width, size.height * aspect)
        return CGSize(width: w, height: w / aspect)
    }

    @ViewBuilder
    private var panel: some View {
        switch tool {
        case .filters:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ReelFilter.allCases) { f in
                        Button { checkpoint(); look.filter = f } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: FilterThumbs.make(base, f)).resizable().scaledToFill()
                                    .frame(width: 58, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: look.filter == f ? 3 : 0))
                                Text(f.rawValue).font(.jakarta(11, .bold)).foregroundStyle(.white.opacity(look.filter == f ? 1 : 0.7))
                            }
                        }
                        .buttonStyle(BouncyStyle(scale: 0.88))
                    }
                }
                .padding(.horizontal, 16)
            }
        case .adjust:
            ScrollView {
                VStack(spacing: 6) {
                    slider("Brightness", "sun.max.fill", $look.adjust.brightness, -1...1)
                    slider("Contrast", "circle.lefthalf.filled", $look.adjust.contrast, -1...1)
                    slider("Saturation", "drop.fill", $look.adjust.saturation, -1...1)
                    slider("Warmth", "thermometer.sun.fill", $look.adjust.warmth, -1...1)
                    slider("Vignette", "camera.aperture", $look.adjust.vignette, 0...1)
                }
                .padding(.horizontal, 16)
            }
        case .text:
            VStack(spacing: 10) {
                Text("Drag · pinch · twist · tap to edit · drop on the bin to delete").font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                Button { checkpoint(); editingText = TextSticker(text: "") } label: { Label("Add text", systemImage: "plus") }
                    .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
            }
            .frame(maxWidth: .infinity)
        case .face:
            VStack(spacing: 8) {
                Text("Cute filters on every face in your photo").font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                FaceFilterPicker(selection: Binding(get: { face }, set: { checkpoint(); face = $0 }))
            }
        case .draw:
            DrawPanel(color: $penColor, width: $penWidth, neon: $penNeon, canUndo: !strokes.isEmpty, onUndo: {
                checkpoint()
                _ = strokes.popLast()
            }, onClear: {
                checkpoint()
                withAnimation { strokes.removeAll() }
            })
        case .stickers, .rotate:
            StickerTray { image in
                checkpoint()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    stickers.append(TextSticker(text: "", x: CGFloat.random(in: 0.3...0.7), y: CGFloat.random(in: 0.3...0.7), image: image))
                }
            }
        }
    }

    private func slider(_ title: String, _ icon: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.pink).frame(width: 20)
            Text(title).font(.jakarta(12, .bold)).foregroundStyle(.white).frame(width: 78, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { checkpoint() } }).tint(Theme.pink)
        }
    }

    private func refreshPreview() {
        let chosen = look
        let image = base
        let chosenFace = face
        guard !chosen.isNeutral || chosenFace != .none else { preview = nil; return }
        Task {
            var out = chosen.isNeutral ? image : (await FilterThumbs.applyAll(chosen, to: [image])).first ?? image
            if chosenFace != .none {
                let faced = out
                out = await Task.detached(priority: .userInitiated) { FaceFilterRenderer.bake(faced, chosenFace) }.value
            }
            if chosen == look, chosenFace == face, image === base { preview = out }
        }
    }

    private func checkpoint() {
        history.append(Snapshot(base: base, look: look, stickers: stickers, strokes: strokes, face: face))
        if history.count > 40 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        withAnimation(.snappy) {
            base = last.base
            look = last.look
            stickers = last.stickers
            strokes = last.strokes
            face = last.face
        }
        refreshPreview()
    }

    private func save() {
        saving = true
        let image = base, chosen = look, marks = stickers, chosenFace = face, doodles = strokes
        Task {
            let baked = await Task.detached(priority: .userInitiated) { PhotoBaker.bake(image, look: chosen, stickers: marks, face: chosenFace, strokes: doodles) }.value
            saving = false
            onDone(baked)
            dismiss()
        }
    }
}
