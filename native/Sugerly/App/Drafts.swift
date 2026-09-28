import SwiftUI
import UIKit

// MARK: - Drafts (kept on this phone)

// Unfinished posts and reels, saved in the app's Documents folder: the text,
// the picture / video and every edit (filters, crop, text, stickers,
// drawing, sound, trim), so you can pick up where you left off.
enum Drafts {
    // Each account has its own drafts folder, so a new account never sees
    // another account's unfinished posts.
    nonisolated(unsafe) static var owner = "guest"

    private static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Drafts", isDirectory: true).appendingPathComponent(owner, isDirectory: true)
    }

    // Drafts from before accounts had their own folders go to whoever is
    // signed in when the app first updates (once).
    static func adoptLegacy() {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Drafts", isDirectory: true)
        for kind in ["posts", "reels"] {
            let old = base.appendingPathComponent(kind, isDirectory: true)
            guard fm.fileExists(atPath: old.path) else { continue }
            let target = root.appendingPathComponent(kind, isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                for id in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] {
                    try? fm.moveItem(at: old.appendingPathComponent(id), to: target.appendingPathComponent(id))
                }
                try? fm.removeItem(at: old)
            } else {
                try? fm.moveItem(at: old, to: target)
            }
        }
    }

    private static func folder(_ kind: String, _ id: String) -> URL {
        let url = root.appendingPathComponent(kind, isDirectory: true).appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func list<T: Decodable>(_ kind: String, as type: T.Type) -> [T] {
        let dir = root.appendingPathComponent(kind, isDirectory: true)
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return ids.compactMap { id in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(id).appendingPathComponent("draft.json")) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    }

    private static func write<T: Encodable>(_ value: T, kind: String, id: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: folder(kind, id).appendingPathComponent("draft.json"), options: .atomic)
        }
    }

    static func delete(_ kind: String, _ id: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(kind).appendingPathComponent(id))
    }

    static func image(_ kind: String, _ id: String, _ name: String) -> UIImage? {
        UIImage(contentsOfFile: root.appendingPathComponent(kind).appendingPathComponent(id).appendingPathComponent(name).path)
    }

    private static func saveJPEG(_ image: UIImage, kind: String, id: String, name: String, maxSide: CGFloat = 2048) {
        if let data = ImageTools.jpeg(image, maxSide: maxSide, quality: 0.9) {
            try? data.write(to: folder(kind, id).appendingPathComponent(name), options: .atomic)
        }
    }

    // MARK: posts

    struct Post: Codable, Identifiable {
        var id: String
        var title: String
        var text: String
        var gif: String
        var hasImage: Bool
        var saved: Date
    }

    static func posts() -> [Post] { list("posts", as: Post.self).sorted { $0.saved > $1.saved } }

    @discardableResult
    static func savePost(id: String?, title: String, text: String, gif: String, image: UIImage?) -> String {
        let id = id ?? UUID().uuidString
        if let image { saveJPEG(image, kind: "posts", id: id, name: "image.jpg") }
        write(Post(id: id, title: title, text: text, gif: gif, hasImage: image != nil, saved: Date()), kind: "posts", id: id)
        return id
    }

    // MARK: reels

    struct Sticker: Codable {
        var text: String
        var color: UInt32
        var font: String
        var style: String
        var align: Int
        var x: Double
        var y: Double
        var scale: Double
        var rotation: Double
        var isEmoji: Bool
        var imageFile: String?
        var start: Double? = nil
        var end: Double? = nil
        var framed: Bool? = nil
    }

    struct Stroke: Codable {
        var points: [[Double]]
        var color: UInt32
        var width: Double
        var neon: Bool
    }

    struct Reel: Codable, Identifiable {
        var id: String
        var saved: Date
        var caption: String
        var allowComments: Bool
        var filter: String
        var adjust: [Double]
        var face: String
        var trimStart: Double
        var trimEnd: Double
        var soundId: String
        var soundTitle: String
        var soundArtist: String
        var soundURL: String
        var soundCover: String
        var soundVolume: Double
        var originalVolume: Double
        var videoFile: String?
        var photoCount: Int
        var stickers: [Sticker]
        var strokes: [Stroke]
        var crop: [Double]? = nil
        var slideSeconds: [Double]? = nil
    }

    static func reels() -> [Reel] { list("reels", as: Reel.self).sorted { $0.saved > $1.saved } }

    static func reelVideo(_ draft: Reel) -> URL? {
        guard let name = draft.videoFile else { return nil }
        let url = root.appendingPathComponent("reels").appendingPathComponent(draft.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func reelPhotos(_ draft: Reel) -> [UIImage] {
        (0..<draft.photoCount).compactMap { image("reels", draft.id, "photo-\($0).jpg") }
    }

    static func reelCover(_ draft: Reel) -> UIImage? { image("reels", draft.id, "cover.jpg") }

    // Everything the reel maker is holding right now.
    struct ReelState {
        var caption: String
        var allowComments: Bool
        var look: ReelLook
        var trimStart: Double
        var trimEnd: Double
        var sound: Track?
        var soundVolume: Double
        var originalVolume: Double
        var video: URL?
        var photos: [UIImage]
        var cover: UIImage?
        var stickers: [TextSticker]
        var strokes: [DrawStroke]
        var videoCrop: CGRect? = nil
        var slideSeconds: [Double] = []
    }

    @discardableResult
    static func saveReel(id: String?, _ state: ReelState) -> String {
        let id = id ?? UUID().uuidString
        let dir = folder("reels", id)
        var videoFile: String?
        if let video = state.video {
            let name = "video.\(video.pathExtension.isEmpty ? "mov" : video.pathExtension)"
            let dest = dir.appendingPathComponent(name)
            if video.standardizedFileURL != dest.standardizedFileURL {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: video, to: dest)
            }
            videoFile = name
        }
        for (i, photo) in state.photos.enumerated() { saveJPEG(photo, kind: "reels", id: id, name: "photo-\(i).jpg") }
        if let cover = state.cover ?? state.photos.first { saveJPEG(cover, kind: "reels", id: id, name: "cover.jpg", maxSide: 480) }
        var stickers: [Sticker] = []
        for (i, s) in state.stickers.enumerated() {
            var file: String?
            if let image = s.image, let png = image.pngData() {
                file = "sticker-\(i).png"
                try? png.write(to: dir.appendingPathComponent(file!), options: .atomic)
            }
            stickers.append(Sticker(text: s.text, color: s.color, font: s.font.rawValue, style: s.style.rawValue, align: s.align.rawValue,
                                    x: Double(s.x), y: Double(s.y), scale: Double(s.scale), rotation: s.rotation, isEmoji: s.isEmoji, imageFile: file,
                                    start: s.start, end: s.end, framed: s.framed))
        }
        let strokes = state.strokes.map { s in
            Stroke(points: s.points.map { [Double($0.x), Double($0.y)] }, color: s.color, width: Double(s.width), neon: s.neon)
        }
        let a = state.look.adjust
        let draft = Reel(id: id, saved: Date(), caption: state.caption, allowComments: state.allowComments,
                         filter: state.look.filter.rawValue, adjust: [a.brightness, a.contrast, a.saturation, a.warmth, a.vignette],
                         face: "", trimStart: state.trimStart, trimEnd: state.trimEnd,
                         soundId: state.sound?.id ?? "", soundTitle: state.sound?.title ?? "", soundArtist: state.sound?.artist ?? "",
                         soundURL: state.sound?.audioURL ?? "", soundCover: state.sound?.coverURL ?? "",
                         soundVolume: state.soundVolume, originalVolume: state.originalVolume,
                         videoFile: videoFile, photoCount: state.photos.count, stickers: stickers, strokes: strokes,
                         crop: state.videoCrop.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] },
                         slideSeconds: state.slideSeconds.isEmpty ? nil : state.slideSeconds)
        write(draft, kind: "reels", id: id)
        return id
    }

    // Back to the editor's own types.
    static func restore(_ d: Reel) -> (look: ReelLook, sound: Track?, stickers: [TextSticker], strokes: [DrawStroke]) {
        let a = d.adjust + Array(repeating: 0, count: max(0, 5 - d.adjust.count))
        let look = ReelLook(filter: ReelFilter(rawValue: d.filter) ?? .none,
                            adjust: ReelAdjust(brightness: a[0], contrast: a[1], saturation: a[2], warmth: a[3], vignette: a[4]))
        let sound = d.soundURL.isEmpty ? nil : Track(["id": d.soundId, "title": d.soundTitle, "user_display_name": d.soundArtist, "music_url": d.soundURL, "cover_url": d.soundCover])
        let stickers = d.stickers.map { s in
            TextSticker(text: s.text, color: s.color, font: StickerFont(rawValue: s.font) ?? .bubbly, style: StickerStyle(rawValue: s.style) ?? .label,
                        align: NSTextAlignment(rawValue: s.align) ?? .center, x: CGFloat(s.x), y: CGFloat(s.y), scale: CGFloat(s.scale),
                        rotation: s.rotation, isEmoji: s.isEmoji, image: s.imageFile.flatMap { image("reels", d.id, $0) },
                        start: s.start ?? 0, end: s.end, framed: s.framed ?? false)
        }
        let strokes = d.strokes.map { s in
            DrawStroke(points: s.points.map { CGPoint(x: $0.first ?? 0, y: $0.count > 1 ? $0[1] : 0) }, color: s.color, width: CGFloat(s.width), neon: s.neon)
        }
        return (look, sound, stickers, strokes)
    }
}

// A row of saved drafts to tap and continue.
struct DraftStrip<Item: Identifiable>: View {
    let title: String
    let items: [Item]
    var dark = false
    let thumb: (Item) -> UIImage?
    let label: (Item) -> String
    var onOpen: (Item) -> Void
    var onDelete: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(title) · \(items.count)", systemImage: "tray.full.fill")
                .font(.jakarta(13, .heavy))
                .foregroundStyle(dark ? .white.opacity(0.85) : Palette.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button { onOpen(item) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack {
                                    if let img = thumb(item) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                    } else {
                                        Theme.gradient
                                        Image(systemName: "text.alignleft").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 76, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Text(label(item)).font(.jakarta(11, .bold)).lineLimit(1)
                                    .foregroundStyle(dark ? .white.opacity(0.8) : Palette.text2)
                                    .frame(width: 76, alignment: .leading)
                            }
                        }
                        .buttonStyle(BouncyStyle(scale: 0.94))
                        .contextMenu {
                            Button(role: .destructive) { onDelete(item) } label: { Label("Delete draft", systemImage: "trash") }
                        }
                    }
                }
            }
        }
    }
}
