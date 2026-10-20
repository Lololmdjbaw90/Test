import SwiftUI
import UIKit
import AVFoundation
import CoreImage

// The engine under the photo and video editor. Kept apart from the screens
// so that the parts that change many times a second (the playhead while a
// video plays, a slider being dragged, a finger drawing) only redraw the
// little bit of the screen that shows them.

// MARK: - The look on the live video

// The filter, adjustments and crop the video preview uses. The player's
// frame handler runs off the main thread and reads them from here on every
// frame, so changing a filter or dragging a slider never rebuilds the player
// (that rebuild was the stutter and the black flashes).
final class LiveLook: @unchecked Sendable {
    private let lock = NSLock()
    private var _look = ReelLook()
    private var _crop: CGRect?

    var look: ReelLook {
        get { lock.lock(); defer { lock.unlock() }; return _look }
        set { lock.lock(); _look = newValue; lock.unlock() }
    }

    var crop: CGRect? {
        get { lock.lock(); defer { lock.unlock() }; return _crop }
        set { lock.lock(); _crop = newValue; lock.unlock() }
    }

    // One frame of the reel: cropped, filled into the 9:16 frame (exactly as
    // the finished video will be), then the look.
    func frame(_ source: CIImage, size: CGSize) -> CIImage {
        lock.lock()
        let look = _look, crop = _crop
        lock.unlock()
        return Self.frame(source, size: size, look: look, crop: crop)
    }

    static func frame(_ source: CIImage, size: CGSize, look: ReelLook, crop: CGRect?) -> CIImage {
        var img = source
        if let crop { img = VideoCrop.cut(img, crop) }
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        img = VideoCrop.fit(img, size)
        if !look.isNeutral { img = look.apply(img) }
        return img
    }
}

// MARK: - The look on photos

// Draws the look onto photos in the background, one at a time and always the
// newest: dragging a slider shows the latest value instead of queueing up
// dozens of slow redraws.
final class PhotoLookRenderer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sugerly.editor.look", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var latest = 0

    func isLatest(_ job: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return job == latest
    }

    // `first` is drawn first (the photo on screen). `done` runs on the main
    // thread for each finished photo, only while this is still the newest job.
    func render(_ look: ReelLook, _ images: [UIImage], first: Int, done: @escaping (Int, UIImage) -> Void) {
        lock.lock()
        latest += 1
        let job = latest
        lock.unlock()
        let order = [first] + images.indices.filter { $0 != first }
        queue.async { [self] in
            for i in order where images.indices.contains(i) {
                guard isLatest(job) else { return }
                let out = look.isNeutral ? images[i] : draw(look, images[i])
                DispatchQueue.main.async { [self] in
                    if isLatest(job) { done(i, out) }
                }
            }
        }
    }

    private func draw(_ look: ReelLook, _ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let ci = CIImage(cgImage: cg)
        let out = look.apply(ci)
        return context.createCGImage(out, from: ci.extent).map { UIImage(cgImage: $0) } ?? image
    }
}

// MARK: - Playback

// Plays what's being edited: the trimmed video (at its speed, with the live
// look), or the slideshow, plus the song. `time` is seconds into the reel
// (from the trim start); only the bits of the screen that show it read it.
@MainActor
@Observable
final class EditorPlayer {
    let av = AVPlayer()
    private(set) var playing = false
    private(set) var time: Double = 0
    private(set) var slide = 0
    private(set) var completedLoops = 0

    @ObservationIgnored let live = LiveLook()
    @ObservationIgnored private let seeker = PreviewSeeker()
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var readiness: NSKeyValueObservation?
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    // Jumping back to the start of the trim: one jump at a time (asking again
    // 30 times a second while it was still on its way froze the picture).
    @ObservationIgnored private var looping = false
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var music: AVPlayer?
    @ObservationIgnored private var slideTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var repaintFlip = false
    @ObservationIgnored private(set) var scrubbing = false
    @ObservationIgnored private(set) var isVideo = false
    @ObservationIgnored private var trimStart = 0.0
    @ObservationIgnored private var trimEnd = 0.0
    @ObservationIgnored private var rate = 1.0
    @ObservationIgnored private var slideSeconds: [Double] = []

    private var length: Double {
        isVideo ? max(0.1, trimEnd - trimStart) : max(0.1, slideSeconds.reduce(0, +))
    }

    // MARK: what it plays

    // One frame handler for as long as the video is open: the look and crop
    // are read from `live` on every frame.
    func loadVideo(_ asset: AVAsset, trimStart: Double, trimEnd: Double, rate: Double) {
        reset()
        isVideo = true
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.rate = rate
        let item = AVPlayerItem(asset: asset)
        // Voices keep their normal pitch when sped up or slowed down.
        item.audioTimePitchAlgorithm = .spectral
        let live = self.live
        let composition = AVMutableVideoComposition(asset: asset) { request in
            request.finish(with: live.frame(request.sourceImage, size: request.renderSize), context: nil)
        }
        composition.renderSize = EditorModel.previewSize
        item.videoComposition = composition
        av.replaceCurrentItem(with: item)
        let currentGeneration = generation
        readiness = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let ready = item.status == .readyToPlay
            Task { @MainActor in
                guard ready, let self, self.generation == currentGeneration, !self.prepared else { return }
                self.prepared = true
                self.seek(self.time, precise: true)
            }
        }
        av.defaultRate = Float(rate)
        // At the very end the player keeps going and we loop it ourselves,
        // instead of it stopping on the last frame.
        av.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loopToStart() }
        }
        watch()
    }

    func loadSlides(_ seconds: [Double]) {
        reset()
        isVideo = false
        rate = 1
        slideSeconds = seconds
    }

    // Stops everything and lets go of the video (the song stays picked).
    func reset() {
        pause()
        readiness = nil
        prepared = false
        seeker.reset(av)
        if let observer {
            av.removeTimeObserver(observer)
            self.observer = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        generation = UUID()
        looping = false
        av.replaceCurrentItem(with: nil)
        isVideo = false
        scrubbing = false
        time = 0
        slide = 0
        completedLoops = 0
    }

    func teardown() {
        reset()
        music?.pause()
        music = nil
    }

    // MARK: changes from the editor

    func setTrim(_ start: Double, _ end: Double) {
        trimStart = start
        trimEnd = end
        if time > end - start { time = max(0, end - start) }
    }

    func setRate(_ value: Double) {
        rate = value
        av.defaultRate = Float(value)
        if av.rate != 0 { av.rate = Float(value) }
    }

    func setSlides(_ seconds: [Double]) {
        slideSeconds = seconds
        if time > length { time = 0 }
        let i = slideIndex(at: time)
        if i != slide { slide = i }
    }

    func setLook(_ look: ReelLook) {
        live.look = look
        repaint()
    }

    func setCrop(_ crop: CGRect?) {
        live.crop = crop
        repaint()
    }

    func setOriginalVolume(_ volume: Double) { av.volume = Float(volume) }

    func setMusic(_ track: Track?, volume: Double) {
        music?.pause()
        music = nil
        guard let track, let url = URL(string: track.audioURL) else { return }
        let p = AVPlayer(url: url)
        p.volume = Float(volume)
        music = p
        if playing {
            p.seek(to: CMTime(seconds: musicTime, preferredTimescale: 600))
            p.play()
        }
    }

    func setMusicVolume(_ volume: Double) { music?.volume = Float(volume) }

    // While paused, a changed look shows on the frame on screen straight away.
    private func repaint() {
        guard isVideo, prepared, !playing, av.currentItem != nil else { return }
        repaintFlip.toggle()
        seeker.seek(av, seconds: trimStart + time + (repaintFlip ? 0.001 : 0), precise: true)
    }

    // MARK: play, pause, seek

    func toggle() { playing ? pause() : play() }

    func play() {
        if isVideo {
            guard av.currentItem != nil else { return }
            wantsPlayback = true
            playing = true
            if time >= length - 0.05 { time = 0 }
            if prepared { seek(time, precise: true) }
        } else {
            guard !slideSeconds.isEmpty else { return }
            wantsPlayback = true
            playing = true
            startSlides()
            music?.seek(to: CMTime(seconds: musicTime, preferredTimescale: 600))
            music?.play()
        }
    }

    func pause() {
        wantsPlayback = false
        playing = false
        av.pause()
        music?.pause()
        slideTask?.cancel()
        slideTask = nil
    }

    // `t` is seconds into the reel.
    func seek(_ t: Double, precise: Bool = false) {
        let t = min(max(0, t), length)
        time = t
        if isVideo {
            guard prepared else { return }
            seeker.seek(av, seconds: trimStart + t, precise: precise) { [weak self] finished in
                guard let self, finished, self.wantsPlayback, !self.scrubbing else { return }
                self.av.playImmediately(atRate: Float(self.rate))
                self.music?.play()
            }
        } else {
            let i = slideIndex(at: t)
            if i != slide { slide = i }
        }
        music?.seek(to: CMTime(seconds: musicTime, preferredTimescale: 600))
    }

    // The trim handles show any moment of the whole video.
    func show(sourceSeconds: Double) {
        guard isVideo, prepared else { return }
        seeker.seek(av, seconds: sourceSeconds)
    }

    func beginScrub() {
        guard !scrubbing else { return }
        scrubbing = true
        resumeAfterScrub = playing
        if playing { pause() }
    }

    func endScrub() {
        guard scrubbing else { return }
        scrubbing = false
        if isVideo && prepared { seeker.seek(av, seconds: trimStart + time, precise: true) }
        if resumeAfterScrub {
            resumeAfterScrub = false
            play()
        }
    }

    // MARK: slideshow

    func slideIndex(at t: Double) -> Int {
        let b = ReelTimeline.bounds(slideSeconds)
        let i = b.lastIndex(where: { $0 <= t + 0.001 }) ?? 0
        return max(0, min(slideSeconds.count - 1, i))
    }

    func goToSlide(_ i: Int) {
        let b = ReelTimeline.bounds(slideSeconds)
        guard i >= 0, i < slideSeconds.count, b.indices.contains(i) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { seek(b[i]) }
    }

    func stepSlide(_ step: Int) {
        goToSlide(min(max(0, slide + step), slideSeconds.count - 1))
    }

    private func startSlides() {
        slideTask?.cancel()
        if time >= length - 0.05 {
            time = 0
            slide = 0
        }
        slideTask = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                var next = self.time + now.timeIntervalSince(last)
                last = now
                if next >= self.length {
                    next = 0
                    self.music?.seek(to: .zero, completionHandler: { _ in })
                }
                self.time = next
                let i = self.slideIndex(at: next)
                if i != self.slide { withAnimation(.easeInOut(duration: 0.3)) { self.slide = i } }
            }
        }
    }

    // MARK: video clock

    private func loopToStart() {
        guard isVideo, wantsPlayback, !looping, !scrubbing, av.currentItem != nil else { return }
        let currentGeneration = generation
        looping = true
        time = 0
        music?.seek(to: .zero, completionHandler: { _ in })
        av.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.looping = false
                if self.wantsPlayback && finished {
                    self.completedLoops += 1
                    self.playing = true
                    self.av.playImmediately(atRate: Float(self.rate))
                    self.music?.play()
                }
            }
        }
    }

    private var musicTime: Double { time / max(0.01, rate) }

    private func watch() {
        if let observer { av.removeTimeObserver(observer) }
        observer = av.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ seconds: Double) {
        guard isVideo, prepared, !scrubbing, !looping, !seeker.isSeeking, seconds.isFinite else { return }
        // A temporary zero rate while buffering or reaching the last frame
        // must not erase the user's intent to keep previewing in a loop.
        if wantsPlayback && (seconds >= trimEnd - 0.05 || seconds < trimStart - 0.25) {
            loopToStart()
            return
        }
        let t = min(max(0, seconds - trimStart), max(0, trimEnd - trimStart))
        if abs(t - time) > 0.02 { time = t }
    }
}
