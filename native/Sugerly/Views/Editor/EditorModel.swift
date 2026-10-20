import SwiftUI
import UIKit
import AVFoundation
import CoreImage

// Everything about the photo, video or slideshow being edited: the media,
// trim and speed, the look, text and stickers, the drawing, the crop and the
// song, with undo and redo. Screens read the bits they show; playback lives
// in `player` so the playhead ticking doesn't redraw the whole editor.
@MainActor
@Observable
final class EditorModel {
    enum Kind { case none, video, slides, photo }

    // The finished reel (and the live video preview): 9:16.
    nonisolated static let reelSize = CGSize(width: 1080, height: 1920)
    nonisolated static let previewSize = CGSize(width: 720, height: 1280)
    nonisolated static let slideSize = CGSize(width: 1080, height: 1920)
    static let reelAspect: CGFloat = 9.0 / 16.0

    private(set) var kind: Kind = .none
    private(set) var videoURL: URL?
    private(set) var asset: AVURLAsset?
    private(set) var duration: Double = 0
    var photos: [UIImage] = []
    var slideSeconds: [Double] = []
    var trimStart: Double = 0
    var trimEnd: Double = 0
    private(set) var speed: Double = 1
    var look = ReelLook()
    var stickers: [TextSticker] = []
    var strokes: [DrawStroke] = []
    private(set) var videoCrop: CGRect?
    private(set) var sound: Track?
    var soundVolume: Double = 1
    var originalVolume: Double = 1
    private(set) var thumbs: [UIImage] = []
    private(set) var stripThumbs: [UIImage] = []
    // The photos with the look, sized for the screen.
    private(set) var previews: [UIImage] = []
    var selectedOverlay: UUID?
    var selectedSlide: Int?
    var penColor: UInt32 = 0xFFFFFF
    var penWidth: CGFloat = 0.012
    var penNeon = false

    let player = EditorPlayer()

    @ObservationIgnored private var bases: [UIImage] = []
    @ObservationIgnored private let renderer = PhotoLookRenderer()
    @ObservationIgnored private var stripKey = ""
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    var isVideo: Bool { kind == .video }
    var isSlides: Bool { kind == .slides }
    var isPhoto: Bool { kind == .photo }
    var hasMedia: Bool { kind != .none }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var muteOriginal: Bool { originalVolume < 0.02 }

    // Seconds of the reel on the timeline (the trimmed video, or all slides).
    var length: Double {
        isVideo ? max(0.1, trimEnd - trimStart) : max(0.1, slideSeconds.reduce(0, +))
    }

    // How long the posted reel lasts (speed counted; 60 s at most).
    var finalLength: Double {
        isVideo ? min(trimEnd - trimStart, 60 * speed) / speed : length
    }

    // The canvas shape: 9:16 for reels, the photo's own for a photo.
    var aspect: CGFloat {
        if isPhoto, let p = photos.first { return max(0.25, min(4, p.size.width / max(1, p.size.height))) }
        return Self.reelAspect
    }

    // The picture the filter previews are made from (never one that
    // already has a filter on it).
    var filterBase: UIImage? { thumbs.first ?? bases.first }

    // MARK: opening

    func openVideo(_ url: URL) async -> Bool {
        let a = AVURLAsset(url: url)
        let seconds = (try? await a.load(.duration).seconds) ?? 0
        guard seconds.isFinite, seconds > 0.3 else { return false }
        resetEdits()
        kind = .video
        videoURL = url
        asset = a
        duration = seconds
        trimStart = 0
        trimEnd = min(seconds, 60)
        speed = 1
        photos = []
        slideSeconds = []
        bases = []
        previews = []
        thumbs = []
        stripThumbs = []
        stripKey = ""
        player.loadVideo(a, trimStart: trimStart, trimEnd: trimEnd, rate: 1)
        player.setLook(look)
        player.setCrop(nil)
        player.setOriginalVolume(originalVolume)
        player.setMusic(sound, volume: soundVolume)
        player.play()
        Task { await makeThumbs(a, seconds: seconds) }
        return true
    }

    func openSlides(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        let ready = await Self.ready(images, slides: true)
        resetEdits()
        kind = .slides
        videoURL = nil
        asset = nil
        duration = 0
        speed = 1
        thumbs = []
        stripThumbs = []
        photos = ready.photos
        bases = ready.screen
        previews = ready.screen
        slideSeconds = Array(repeating: 3, count: photos.count)
        player.loadSlides(slideSeconds)
        player.setMusic(sound, volume: soundVolume)
        player.play()
    }

    func openPhoto(_ image: UIImage) async {
        let ready = await Self.ready([image], slides: false)
        resetEdits()
        kind = .photo
        photos = ready.photos
        bases = ready.screen
        previews = ready.screen
        slideSeconds = []
        player.reset()
    }

    // Big photos are made ready in the background, so opening ten of them
    // doesn't freeze the screen.
    nonisolated private static func ready(_ images: [UIImage], slides: Bool) async -> (photos: [UIImage], screen: [UIImage]) {
        await Task.detached(priority: .userInitiated) {
            let photos = images.map { EditorModel.prepare($0) }
            return (photos, photos.map { EditorModel.screenBase($0, slide: slides) })
        }.value
    }

    // Back to nothing (the song stays picked).
    func clear() {
        player.reset()
        resetEdits()
        kind = .none
        videoURL = nil
        asset = nil
        photos = []
        slideSeconds = []
        bases = []
        previews = []
        thumbs = []
        stripThumbs = []
    }

    private func resetEdits() {
        look = ReelLook()
        stickers = []
        strokes = []
        videoCrop = nil
        selectedOverlay = nil
        selectedSlide = nil
        undoStack = []
        redoStack = []
    }

    // A saved draft's edits, on top of the opened media.
    func restoreDraft(look: ReelLook, stickers: [TextSticker], strokes: [DrawStroke], crop: CGRect?,
                      trim: (start: Double, end: Double)?, speed: Double?, slideSeconds: [Double]?) {
        self.look = look
        self.stickers = stickers
        self.strokes = strokes
        if isVideo {
            if let trim {
                trimStart = min(trim.start, max(0, duration - 1))
                trimEnd = min(duration, max(trimStart + 1, trim.end))
            }
            videoCrop = crop
            self.speed = speed ?? 1
            player.setTrim(trimStart, trimEnd)
            player.setRate(self.speed)
            player.setCrop(crop)
            player.setOriginalVolume(originalVolume)
        } else if isSlides, let slideSeconds, slideSeconds.count == photos.count {
            self.slideSeconds = slideSeconds
            player.setSlides(slideSeconds)
        }
        undoStack = []
        redoStack = []
        refreshLook()
    }

    // MARK: undo / redo

    struct Snapshot {
        var look: ReelLook
        var stickers: [TextSticker]
        var strokes: [DrawStroke]
        var photos: [UIImage]
        var slideSeconds: [Double]
        var videoCrop: CGRect?
        var trimStart: Double
        var trimEnd: Double
        var speed: Double
    }

    private var snapshot: Snapshot {
        Snapshot(look: look, stickers: stickers, strokes: strokes, photos: photos, slideSeconds: slideSeconds,
                 videoCrop: videoCrop, trimStart: trimStart, trimEnd: trimEnd, speed: speed)
    }

    // Call before each change that can be undone.
    func checkpoint() {
        undoStack.append(snapshot)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private func restore(_ s: Snapshot) {
        let photosChanged = s.photos.count != photos.count || !zip(s.photos, photos).allSatisfy { $0 === $1 }
        withMotion(Motion.standard) {
            look = s.look
            stickers = s.stickers
            strokes = s.strokes
            slideSeconds = s.slideSeconds
            videoCrop = s.videoCrop
            trimStart = s.trimStart
            trimEnd = s.trimEnd
            speed = s.speed
            if photosChanged { photos = s.photos }
        }
        if photosChanged { rebuildBases() }
        if isVideo {
            player.setTrim(trimStart, trimEnd)
            player.setRate(speed)
            player.setCrop(videoCrop)
        } else if isSlides {
            player.setSlides(slideSeconds)
        }
        selectedSlide = nil
        refreshLook()
    }

    // MARK: the look

    // On the video it shows straight away (no rebuild); on photos it's
    // redrawn in the background, the one on screen first.
    func refreshLook() {
        if isVideo {
            player.setLook(look)
            return
        }
        guard !bases.isEmpty else {
            previews = []
            return
        }
        if previews.count != bases.count { previews = bases }
        let first = isSlides ? min(player.slide, bases.count - 1) : 0
        let renderer = self.renderer
        renderer.render(look, bases, first: first) { [weak self] i, image in
            MainActor.assumeIsolated {
                guard let self, self.previews.indices.contains(i) else { return }
                self.previews[i] = image
            }
        }
    }

    // A filter picked on the camera: the edit starts with it on (not an undo
    // step, it's where the edit begins).
    func startWith(_ filter: ReelFilter) {
        guard filter != .none, filter != look.filter else { return }
        look.filter = filter
        refreshLook()
    }

    func setFilter(_ filter: ReelFilter) {
        guard filter != look.filter else { return }
        checkpoint()
        look.filter = filter
        refreshLook()
    }

    func resetAdjust() {
        guard !look.adjust.isNeutral else { return }
        checkpoint()
        look.adjust = ReelAdjust()
        refreshLook()
    }

    private func rebuildBases() {
        let slides = isSlides
        bases = photos.map { Self.screenBase($0, slide: slides) }
        previews = bases
    }

    // MARK: video: trim, speed, crop

    // After the trim handles move.
    func trimChanged() {
        // Reels stay 60 seconds at most, even in slow motion.
        if (trimEnd - trimStart) / speed > 60 { trimEnd = trimStart + 60 * speed }
        player.setTrim(trimStart, trimEnd)
        ReelTimeline.clamp(&stickers, length: length)
    }

    func setSpeed(_ value: Double) {
        guard abs(value - speed) > 0.001 else { return }
        checkpoint()
        withMotion(Motion.standard) { speed = value }
        if (trimEnd - trimStart) / value > 60 {
            trimEnd = trimStart + 60 * value
            player.setTrim(trimStart, trimEnd)
        }
        player.setRate(value)
    }

    // A frame to crop on: the video where it is now, or the photo on screen.
    func makeCropJob() async -> EditorCrop? {
        if isVideo, let asset {
            player.pause()
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1400, height: 1400)
            let at = CMTime(seconds: trimStart + player.time, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: at) else { return nil }
            return EditorCrop(image: UIImage(cgImage: frame.image), slide: nil)
        }
        let i = isSlides ? player.slide : 0
        guard photos.indices.contains(i) else { return nil }
        return EditorCrop(image: photos[i], slide: i)
    }

    func applyCrop(_ job: EditorCrop, _ rect: CGRect) {
        checkpoint()
        if let i = job.slide, photos.indices.contains(i) {
            photos[i] = Cropping.crop(photos[i], rect, maxSide: 2048)
            if bases.indices.contains(i) {
                bases[i] = Self.screenBase(photos[i], slide: isSlides)
                if previews.indices.contains(i) { previews[i] = bases[i] }
            }
            refreshLook()
        } else {
            videoCrop = rect
            player.setCrop(rect)
        }
    }

    func resetCrop() {
        guard videoCrop != nil else { return }
        checkpoint()
        videoCrop = nil
        player.setCrop(nil)
    }

    func rotatePhoto() {
        guard isPhoto, let p = photos.first else { return }
        checkpoint()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { photos[0] = PhotoBaker.rotate(p) }
        rebuildBases()
        refreshLook()
    }

    // MARK: slideshow

    func slidesChanged() { player.setSlides(slideSeconds) }

    func moveSlide(_ i: Int, _ j: Int) {
        guard photos.indices.contains(i), photos.indices.contains(j), slideSeconds.count == photos.count else { return }
        checkpoint()
        let old = ReelTimeline.bounds(slideSeconds)
        withMotion(Motion.standard) {
            photos.swapAt(i, j)
            if bases.count == photos.count { bases.swapAt(i, j) }
            if previews.count == photos.count { previews.swapAt(i, j) }
            slideSeconds.swapAt(i, j)
            ReelTimeline.remap(&stickers, from: old, to: ReelTimeline.bounds(slideSeconds))
        }
        selectedSlide = j
        player.setSlides(slideSeconds)
        player.goToSlide(j)
    }

    func deleteSlide(_ i: Int) {
        guard photos.count > 1, photos.indices.contains(i), slideSeconds.count == photos.count else { return }
        checkpoint()
        let b = ReelTimeline.bounds(slideSeconds)
        let newLength = (b.last ?? 0) - slideSeconds[i]
        withMotion(Motion.standard) {
            photos.remove(at: i)
            if bases.count == photos.count + 1 { bases.remove(at: i) }
            if previews.count == photos.count + 1 { previews.remove(at: i) }
            slideSeconds.remove(at: i)
            ReelTimeline.removeSlide(&stickers, from: b[i], to: b[i + 1], newLength: newLength)
        }
        selectedSlide = nil
        player.setSlides(slideSeconds)
        player.goToSlide(min(player.slide, photos.count - 1))
    }

    // MARK: text, stickers, photos on top

    // Is this overlay on screen now? (On a video: at the playhead; on a
    // slideshow: on the slide showing.)
    func isShown(_ s: TextSticker) -> Bool {
        if isVideo { return s.shows(at: player.time) }
        if isSlides {
            let b = ReelTimeline.bounds(slideSeconds)
            let i = player.slide
            guard slideSeconds.count == photos.count, b.count > i + 1 else { return true }
            return s.overlaps(b[i], b[i + 1])
        }
        return true
    }

    // Overlays added from the timeline: 3 seconds from the playhead, or the
    // slide on screen.
    func newOverlayTiming() -> (start: Double, end: Double?) {
        if isSlides {
            let b = ReelTimeline.bounds(slideSeconds)
            let i = player.slide
            guard slideSeconds.count == photos.count, b.count > i + 1 else { return (0, nil) }
            let end = b[i + 1]
            return (b[i], end >= (b.last ?? 0) - 0.01 ? nil : end)
        }
        guard isVideo else { return (0, nil) }
        let start = max(0, min(player.time, length - 3))
        let end = start + 3
        return (start, end >= length - 0.05 ? nil : end)
    }

    func saveText(_ sticker: TextSticker) {
        if let i = stickers.firstIndex(where: { $0.id == sticker.id }) {
            stickers[i] = sticker
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { stickers.append(sticker) }
        }
        selectedOverlay = sticker.id
    }

    func deleteSticker(_ id: UUID) {
        withMotion(Motion.standard) { stickers.removeAll { $0.id == id } }
        if selectedOverlay == id { selectedOverlay = nil }
    }

    func addSticker(_ image: UIImage) {
        checkpoint()
        let sticker = TextSticker(text: "", x: CGFloat.random(in: 0.35...0.65), y: CGFloat.random(in: 0.3...0.55), image: image)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { stickers.append(sticker) }
        selectedOverlay = sticker.id
    }

    func addPhotoOverlay(_ image: UIImage) {
        checkpoint()
        let timing = newOverlayTiming()
        let overlay = TextSticker(text: "", x: 0.5, y: 0.42, image: image, start: timing.start, end: timing.end, framed: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { stickers.append(overlay) }
        selectedOverlay = overlay.id
        selectedSlide = nil
    }

    // MARK: drawing

    func addStroke(_ stroke: DrawStroke) {
        checkpoint()
        strokes.append(stroke)
    }

    func undoStroke() {
        guard !strokes.isEmpty else { return }
        checkpoint()
        _ = strokes.popLast()
    }

    func clearStrokes() {
        guard !strokes.isEmpty else { return }
        checkpoint()
        withMotion { strokes.removeAll() }
    }

    // MARK: sound

    func setSound(_ track: Track?) {
        sound = track
        player.setMusic(track, volume: soundVolume)
    }

    func soundVolumeChanged() { player.setMusicVolume(soundVolume) }
    func originalVolumeChanged() { player.setOriginalVolume(originalVolume) }

    // MARK: film strips

    private func makeThumbs(_ a: AVURLAsset, seconds: Double) async {
        let generator = AVAssetImageGenerator(asset: a)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        var out: [UIImage] = []
        for i in 0..<8 {
            let t = CMTime(seconds: seconds * Double(i) / 8, preferredTimescale: 600)
            if let result = try? await generator.image(at: t) { out.append(UIImage(cgImage: result.image)) }
        }
        if a === asset { thumbs = out }
    }

    // Frames from just the trimmed part, for the timeline.
    func refreshStrip() async {
        guard let asset else { return }
        let key = "\(Int(trimStart * 10))-\(Int(trimEnd * 10))"
        guard key != stripKey else { return }
        stripKey = key
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let count = 10
        var out: [UIImage] = []
        for i in 0..<count {
            let t = trimStart + (trimEnd - trimStart) * (Double(i) + 0.5) / Double(count)
            if let result = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) { out.append(UIImage(cgImage: result.image)) }
        }
        if key == stripKey { stripThumbs = out }
    }
}

// MARK: - Finishing (what gets posted or sent)

extension EditorModel {
    // Every photo upright, solid (see-through parts turn white, like other
    // apps, instead of black once saved as JPEG) and no bigger than 2048 px.
    nonisolated static func prepare(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height, 1)
        let scale = min(1, 2048 / longest)
        let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // A screen-sized copy for the live preview (fast to filter).
    nonisolated static func screenCopy(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height, 1)
        guard longest > 1080 else { return image }
        let k = 1080 / longest
        let target = CGSize(width: max(1, (image.size.width * k).rounded()), height: max(1, (image.size.height * k).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // What the editor shows: a screen-sized copy, already framed for the
    // reel when it's a slide (so it looks exactly as it will be posted).
    nonisolated static func screenBase(_ image: UIImage, slide: Bool) -> UIImage {
        slide ? SlideFraming.frame(image, to: CGSize(width: 608, height: 1080)) : screenCopy(image)
    }

    // A picture filling a frame (cut at the sides or top).
    nonisolated static func fill(_ image: UIImage, to size: CGSize) -> UIImage {
        let k = max(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
        let drawn = CGSize(width: image.size.width * k, height: image.size.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
    }

    // Photos on top of the reel: upright and no bigger than they need to be
    // (see-through parts stay see-through).
    nonisolated static func overlayPicture(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height, 1)
        let scale = min(1, 1200 / longest)
        let target = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // The slides as posted: each photo framed for the 9:16 reel (exactly as
    // it looked in the editor) with the look, the drawing and the overlays
    // timed onto it. Made in the background.
    func bakedSlides() async -> [UIImage] {
        let pictures = photos
        let look = self.look
        let strokes = self.strokes
        let b = ReelTimeline.bounds(slideSeconds)
        let timed = slideSeconds.count == photos.count
        let perSlide: [[TextSticker]] = photos.indices.map { i in
            guard timed, b.count > i + 1 else { return stickers }
            return stickers.filter { $0.overlaps(b[i], b[i + 1]) }
        }
        return await Task.detached(priority: .userInitiated) {
            pictures.indices.map { i in
                PhotoBaker.bake(SlideFraming.frame(pictures[i], to: Self.slideSize), look: look, stickers: perSlide[i], strokes: strokes)
            }
        }.value
    }

    // The edited photo, full size (the photo editor).
    func bakedPhoto() async -> UIImage? {
        guard let picture = photos.first else { return nil }
        let look = self.look, stickers = self.stickers, strokes = self.strokes
        return await Task.detached(priority: .userInitiated) {
            PhotoBaker.bake(picture, look: look, stickers: stickers, strokes: strokes)
        }.value
    }

    // The reel's cover: its first moment, as it will look.
    func coverImage() async -> UIImage? {
        guard let asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        guard let result = try? await generator.image(at: CMTime(seconds: trimStart + 0.1, preferredTimescale: 600)) else { return nil }
        var frame = UIImage(cgImage: result.image)
        if let videoCrop { frame = Cropping.crop(frame, videoCrop, maxSide: 1920) }
        let filled = Self.fill(frame, to: Self.slideSize)
        return PhotoBaker.bake(filled, look: look, stickers: stickers.filter { $0.shows(at: 0.1) }, strokes: strokes)
    }

    // The finished video: trimmed, at its speed, cropped and filled into the
    // 9:16 frame like the preview, with the look, the drawing and the
    // overlays (each only in its time). The song isn't mixed in: reels play
    // it alongside.
    func exportVideo() async throws -> URL {
        guard let asset else { throw APIError(message: "There's no video to make.") }
        let box = RenderBox()
        box.look = look
        box.crop = videoCrop
        box.trimStart = trimStart
        let end = min(trimEnd, trimStart + 60 * speed)
        var range: CMTimeRange? = end > trimStart + 0.05
            ? CMTimeRange(start: CMTime(seconds: max(0, trimStart), preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
            : nil
        // Speed: the kept part goes into its own composition, stretched or
        // squeezed in time; the look and overlays then work on that.
        var source: AVAsset = asset
        if abs(speed - 1) > 0.01, let kept = range {
            source = try await Self.speedComposition(asset, range: kept, rate: speed)
            range = nil
            box.trimStart = 0
            box.rate = speed
        }
        let size = Self.reelSize
        let composition = AVMutableVideoComposition(asset: source) { request in
            var img = LiveLook.frame(request.sourceImage, size: request.renderSize, look: box.look, crop: box.crop)
            for overlay in box.overlays { img = overlay.composited(over: img) }
            // Timeline overlays: only while they're meant to show.
            let t = (request.compositionTime.seconds - box.trimStart) * box.rate
            for item in box.timed where t >= item.start - 0.01 && (item.end.map { t < $0 } ?? true) {
                img = item.image.composited(over: img)
            }
            request.finish(with: img, context: nil)
        }
        composition.renderSize = size
        box.overlays = doodleImage(size).map { [$0] } ?? []
        box.timed = stickers.compactMap { s in
            stickerImage(s, size).map { RenderBox.Timed(image: $0, start: s.start, end: s.end) }
        }

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard let session = AVAssetExportSession(asset: source, presetName: AVAssetExportPresetHighestQuality) else {
            throw APIError(message: "Couldn't make the video on this device.")
        }
        session.videoComposition = composition
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        // Voices keep their normal pitch at other speeds.
        session.audioTimePitchAlgorithm = .spectral
        // A start after the end is an invalid range, which AVFoundation throws on.
        if let range { session.timeRange = range }
        if originalVolume < 0.99 {
            let mix = AVMutableAudioMix()
            let tracks = (try? await source.loadTracks(withMediaType: .audio)) ?? []
            let volume = Float(muteOriginal ? 0 : originalVolume)
            mix.inputParameters = tracks.map { track in
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(volume, at: .zero)
                return p
            }
            session.audioMix = mix
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { done.resume() }
        }
        guard session.status == .completed else {
            throw APIError(message: session.error?.localizedDescription ?? "Couldn't make the video.")
        }
        return out
    }

    private func doodleImage(_ size: CGSize) -> CIImage? {
        Doodle.render(strokes, size: size)?.cgImage.map { CIImage(cgImage: $0) }
    }

    private func stickerImage(_ sticker: TextSticker, _ size: CGSize) -> CIImage? {
        guard !sticker.text.isEmpty || sticker.image != nil, let cg = sticker.render(width: size.width).cgImage else { return nil }
        let img = CIImage(cgImage: cg)
        let w = img.extent.width, h = img.extent.height
        // Centre on the origin, turn (Core Image's y axis points up, so the
        // angle flips), then move into place.
        let centred = CGAffineTransform(translationX: -w / 2, y: -h / 2)
        let turned = centred.concatenating(CGAffineTransform(rotationAngle: -CGFloat(sticker.rotation)))
        let placed = turned.concatenating(CGAffineTransform(translationX: sticker.x * size.width, y: (1 - sticker.y) * size.height))
        return img.transformed(by: placed)
    }

    // The kept part of the video (picture and sound), played `rate` times as
    // fast: 2 makes it half as long, 0.5 twice as long.
    nonisolated static func speedComposition(_ asset: AVURLAsset, range: CMTimeRange, rate: Double) async throws -> AVMutableComposition {
        let made = AVMutableComposition()
        guard let video = try await asset.loadTracks(withMediaType: .video).first,
              let track = made.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw APIError(message: "Couldn't change the speed of this video.")
        }
        try track.insertTimeRange(range, of: video, at: .zero)
        track.preferredTransform = try await video.load(.preferredTransform)
        for audio in try await asset.loadTracks(withMediaType: .audio) {
            guard let sound = made.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try? sound.insertTimeRange(range, of: audio, at: .zero)
        }
        made.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                            toDuration: CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / rate))
        return made
    }
}

// A slide for the 9:16 reel. A picture that's nearly that shape fills it;
// any other (a landscape drawing, a square one…) shows whole over a soft,
// blurred copy of itself instead of being cut off at the sides.
enum SlideFraming {
    private static let blur = CIContext(options: [.cacheIntermediates: false])

    static func frame(_ image: UIImage, to size: CGSize) -> UIImage {
        let aspect = image.size.width / max(1, image.size.height)
        let target = size.width / max(1, size.height)
        if abs(aspect - target) / target < 0.08 { return EditorModel.fill(image, to: size) }
        let k = min(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
        let shown = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
        let backdrop = blurred(image, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            backdrop?.draw(in: CGRect(origin: .zero, size: size))
            UIColor.black.withAlphaComponent(0.28).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: ((size.width - shown.width) / 2).rounded(), y: ((size.height - shown.height) / 2).rounded(),
                                  width: shown.width, height: shown.height))
        }
    }

    // The picture filling the frame, tiny and very blurred (it's only the
    // backdrop, so it costs next to nothing).
    private static func blurred(_ image: UIImage, size: CGSize) -> UIImage? {
        let small = CGSize(width: max(1, (size.width / 8).rounded()), height: max(1, (size.height / 8).rounded()))
        guard let cg = EditorModel.fill(image, to: small).cgImage else { return nil }
        let base = CIImage(cgImage: cg)
        let soft = base.clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: base.extent)
        return blur.createCGImage(soft, from: base.extent).map { UIImage(cgImage: $0) }
    }
}
