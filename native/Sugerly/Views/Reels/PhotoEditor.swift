import SwiftUI
import UIKit
import CoreImage

// Filters, adjustments, drawing, text and stickers drawn onto a photo, full size.
enum PhotoBaker {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func bake(_ image: UIImage, look: ReelLook, stickers: [TextSticker], strokes: [DrawStroke] = []) -> UIImage {
        guard !look.isNeutral || !stickers.isEmpty || !strokes.isEmpty, let cg = image.cgImage else { return image }
        var ci = CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(image.imageOrientation))
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        if !look.isNeutral { ci = look.apply(ci) }
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

// The photo editor for posts and artworks: the same editor as reels, made
// for one photo (its own shape, no timeline or sound), with Done giving the
// finished photo back at full size.
struct PhotoEditorView: View {
    let original: UIImage
    var onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var doc = EditorModel()
    @State private var saving = false

    init(image: UIImage, onDone: @escaping (UIImage) -> Void) {
        original = image
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            EditorPalette.backdrop.ignoresSafeArea()
            if doc.hasMedia {
                MediaEditor(doc: doc, primaryTitle: "Done", primaryIcon: "checkmark", busy: saving, backIcon: "xmark",
                            onBack: { dismiss() }, onPrimary: { save() })
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.25), value: doc.hasMedia)
        .task { if !doc.hasMedia { await doc.openPhoto(original) } }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            let baked = await doc.bakedPhoto()
            saving = false
            if let baked { onDone(baked) }
            dismiss()
        }
    }
}
