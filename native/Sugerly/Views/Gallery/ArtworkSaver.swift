import Photos
import UIKit

// Saving a drawing to your photos. Someone else's drawing gets the artist's
// @name written on it: small, white and see-through, in the bottom right
// corner, with a soft shadow so it reads on light and dark pictures alike.
// The picture is downloaded and drawn off the main thread.
enum ArtworkSaver {
    static func save(_ url: String, credit: String?) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw APIError(message: "Allow Sugerly to add to Photos in Settings.")
        }
        guard let link = URL(string: url) else { throw APIError(message: "This drawing can't be saved.") }
        let (data, _) = try await URLSession.shared.data(from: link)
        let output: Data = try await Task.detached(priority: .userInitiated) {
            guard let credit else { return data }
            guard let picture = UIImage(data: data) else { throw APIError(message: "This drawing can't be saved.") }
            guard let marked = signed(picture, credit: credit).jpegData(compressionQuality: 0.92) else {
                throw APIError(message: "This drawing can't be saved.")
            }
            return marked
        }.value
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: output, options: nil)
        }
    }

    // The picture with the credit drawn on it, at the picture's own size.
    nonisolated static func signed(_ picture: UIImage, credit: String) -> UIImage {
        let size = picture.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = picture.scale
        format.opaque = false
        let short = min(size.width, size.height)
        let fontSize = max(12, short * 0.04)
        let base = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: fontSize) } ?? base
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = fontSize * 0.25
        shadow.shadowOffset = CGSize(width: 0, height: fontSize * 0.05)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            .shadow: shadow,
        ]
        let text = NSAttributedString(string: credit, attributes: attributes)
        let bounds = text.boundingRect(with: CGSize(width: size.width * 0.9, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin], context: nil)
        let margin = short * 0.035
        let origin = CGPoint(x: size.width - bounds.width - margin, y: size.height - bounds.height - margin)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            picture.draw(in: CGRect(origin: .zero, size: size))
            text.draw(with: CGRect(origin: origin, size: bounds.size), options: [.usesLineFragmentOrigin], context: nil)
        }
    }
}
