import SwiftUI
import UIKit
import AVFoundation
import CoreImage

// MARK: - Lens stops

// A zoom stop the camera can jump to, as shown on its button (0.5×, 1×, 2×,
// 3×…), and the device zoom factor behind it.
struct CameraLens: Identifiable, Equatable, Sendable {
    let shown: CGFloat
    let factor: CGFloat
    var id: CGFloat { shown }

    // ".5", "1", "2", "3" (like the iPhone's own camera).
    var label: String {
        if shown < 1 { return "." + String(Int((shown * 10).rounded())) }
        return shown == shown.rounded() ? String(Int(shown)) : String(format: "%.1f", shown)
    }
}

// What the camera turned out to be able to do once it's set up.
struct CameraSetup: Sendable {
    var position: AVCaptureDevice.Position
    var lenses: [CameraLens]
    var wide: CGFloat       // the device zoom factor that's 1×
    var maxShown: CGFloat   // the furthest zoom, as shown on the buttons
    var hasTorch: Bool
}

// MARK: - The camera hardware

// Everything that talks to the camera, on one queue of its own, so starting,
// flipping and zooming never make the screen wait.
final class CaptureCore: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    let movie = AVCaptureMovieFileOutput()
    let photo = AVCapturePhotoOutput()
    let frames = AVCaptureVideoDataOutput()
    let queue = DispatchQueue(label: "sugerly.camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "sugerly.camera.frames", qos: .userInitiated)
    // Only touched on `queue`.
    private var device: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var configured = false
    private var framesOn = false

    // Runs on the camera's queue and hands back the answer.
    func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { done in
            queue.async { done.resume(returning: work()) }
        }
    }

    // The best camera on that side: on the back, the one that switches
    // between ultra wide, wide and telephoto by itself (like the Camera app).
    static func camera(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let kinds: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: kinds, mediaType: .video, position: position).devices
        for kind in kinds {
            if let device = found.first(where: { $0.deviceType == kind }) { return device }
        }
        return found.first
    }

    // Builds the session the first time: the camera, the microphone, and
    // outputs for clips, photos and the live filter.
    func configure(position: AVCaptureDevice.Position, microphone: Bool,
                   frameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) -> CameraSetup? {
        if configured { return setup() }
        guard let camera = Self.camera(position), let input = try? AVCaptureDeviceInput(device: camera) else { return nil }
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return nil
        }
        session.addInput(input)
        videoInput = input
        device = camera
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        if microphone, let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        if session.canAddOutput(movie) { session.addOutput(movie) }
        if session.canAddOutput(photo) { session.addOutput(photo) }
        frames.alwaysDiscardsLateVideoFrames = true
        frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        frames.setSampleBufferDelegate(frameDelegate, queue: frameQueue)
        if session.canAddOutput(frames) { session.addOutput(frames) }
        session.commitConfiguration()
        configured = true
        orient()
        let ready = setup()
        if let ready { setZoom(ready.wide, smooth: false) }
        return ready
    }

    // The zoom stops this camera has and how far it zooms.
    func setup() -> CameraSetup? {
        guard let device else { return nil }
        let switches = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let parts = device.constituentDevices.map(\.deviceType)
        let ultraWide = parts.contains(.builtInUltraWideCamera)
        let tele = parts.contains(.builtInTelephotoCamera)
        let wide: CGFloat = ultraWide ? (switches.first ?? 2) : 1
        var lenses: [CameraLens] = []
        if device.position == .back {
            if ultraWide { lenses.append(CameraLens(shown: (10 / wide).rounded() / 10, factor: 1)) }
            lenses.append(CameraLens(shown: 1, factor: wide))
            let teleShown = tele ? (switches.last ?? 0) / wide : 0
            // 2× is a crop of the main camera when there's no telephoto
            // (or the telephoto zooms further than that).
            if teleShown < 1.5 || teleShown > 2.5 { lenses.append(CameraLens(shown: 2, factor: wide * 2)) }
            if teleShown >= 1.5 { lenses.append(CameraLens(shown: (teleShown * 10).rounded() / 10, factor: teleShown * wide)) }
        }
        let furthest = min(device.maxAvailableVideoZoomFactor, wide * 10)
        return CameraSetup(position: device.position, lenses: lenses, wide: wide,
                           maxShown: max(1, furthest / wide), hasTorch: device.hasTorch)
    }

    // Upright (portrait) pictures everywhere, and the front camera mirrored
    // like a mirror.
    private func orient() {
        let front = device?.position == .front
        for output in [movie, photo, frames] as [AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
        }
        if let connection = movie.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        frames.connection(with: .video)?.isEnabled = framesOn
    }

    func start() {
        if configured && !session.isRunning { session.startRunning() }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    func switchCamera(to position: AVCaptureDevice.Position) -> CameraSetup? {
        guard let camera = Self.camera(position), let input = try? AVCaptureDeviceInput(device: camera) else { return nil }
        setTorch(false)
        session.beginConfiguration()
        if let videoInput { session.removeInput(videoInput) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            device = camera
        } else if let videoInput, session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        session.commitConfiguration()
        orient()
        let ready = setup()
        if let ready { setZoom(ready.wide, smooth: false) }
        return ready
    }

    // The live filter's frames only flow while a filter is on.
    func setFrames(_ on: Bool) {
        framesOn = on
        frames.connection(with: .video)?.isEnabled = on
    }

    func setZoom(_ factor: CGFloat, smooth: Bool) {
        guard let device else { return }
        let value = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            if smooth {
                device.ramp(toVideoZoomFactor: value, withRate: 10)
            } else {
                if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
                device.videoZoomFactor = value
            }
            device.unlockForConfiguration()
        } catch {}
    }

    // Sharp and bright where you tapped. Locked: it stays that way even if
    // the picture changes; otherwise the camera takes over again when the
    // scene changes a lot.
    func focus(at point: CGPoint, lock: Bool, watch: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            let focusMode: AVCaptureDevice.FocusMode = lock ? .autoFocus : .continuousAutoFocus
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
            if device.isFocusModeSupported(focusMode) { device.focusMode = focusMode }
            let exposureMode: AVCaptureDevice.ExposureMode = lock ? .autoExpose : .continuousAutoExposure
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
            if device.isExposureModeSupported(exposureMode) { device.exposureMode = exposureMode }
            device.setExposureTargetBias(0, completionHandler: nil)
            device.isSubjectAreaChangeMonitoringEnabled = watch && !lock
            device.unlockForConfiguration()
        } catch {}
    }

    // Brighter or darker (in stops of light).
    func setExposure(_ bias: Float) {
        guard let device else { return }
        let value = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(value, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = on && device.isTorchAvailable ? .on : .off
        guard device.isTorchModeSupported(mode), device.torchMode != mode else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {}
    }

    func startRecording(to url: URL, delegate: AVCaptureFileOutputRecordingDelegate) -> Bool {
        guard session.isRunning, !movie.isRecording, movie.connection(with: .video) != nil else { return false }
        movie.startRecording(to: url, recordingDelegate: delegate)
        return true
    }

    // (Does nothing if it isn't filming.)
    func stopRecording() {
        movie.stopRecording()
    }

    func capturePhoto(flash: Bool, delegate: AVCapturePhotoCaptureDelegate) {
        guard session.isRunning, photo.connection(with: .video) != nil else { return }
        let settings = AVCapturePhotoSettings()
        if flash, photo.supportedFlashModes.contains(.on) { settings.flashMode = .on }
        photo.capturePhoto(with: settings, delegate: delegate)
    }
}

// MARK: - Live filter

// The camera with a filter on: frames come in on the camera's frame queue,
// get the filter in Core Image and go straight to a display layer (the
// clip itself is filmed clean; the editor puts the same filter on).
final class FilterRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var filter = ReelFilter.none
    // A frame is already on its way to the screen (the next one waits).
    private var sending = false
    // Only touched on the frame queue.
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    // Set and called on the main thread.
    var deliver: ((CMSampleBuffer) -> Void)?

    func show(_ filter: ReelFilter) {
        lock.lock()
        self.filter = filter
        lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let filter = self.filter
        let busy = sending
        lock.unlock()
        guard filter != .none, !busy, let input = CMSampleBufferGetImageBuffer(sampleBuffer),
              let output = buffer(width: CVPixelBufferGetWidth(input), height: CVPixelBufferGetHeight(input)) else { return }
        context.render(filter.apply(CIImage(cvPixelBuffer: input)), to: output)
        guard let sample = Self.sample(output) else { return }
        lock.lock()
        sending = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliver?(sample)
            self.lock.lock()
            self.sending = false
            self.lock.unlock()
        }
    }

    private func buffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard width > 0, height > 0 else { return nil }
        let size = CGSize(width: width, height: height)
        if pool == nil || poolSize != size {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            ]
            var made: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &made)
            pool = made
            poolSize = size
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess else { return nil }
        return out
    }

    private static func sample(_ pixels: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        // Show it the moment it arrives.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

// MARK: - The camera, for the screen

// The in-app camera: video in clips (tap to start and stop, or hold), each
// at its own speed, and photos. Lens stops, tap to focus (hold to lock),
// brighter / darker, flash or the front light, live filters and the song
// playing in time while you film.
@MainActor
@Observable
final class CameraEngine: NSObject {
    struct Clip: Identifiable {
        let id = UUID()
        let url: URL
        let seconds: Double
        let speed: Double
        // The clip's last moment, for "Align".
        var ghost: UIImage? = nil
        var effective: Double { seconds / speed }
    }

    enum Access { case unknown, granted, denied, unavailable }

    @ObservationIgnored let core = CaptureCore()
    @ObservationIgnored let renderer = FilterRenderer()
    @ObservationIgnored var onPhoto: ((UIImage) -> Void)?
    @ObservationIgnored private var soundPlayer: AVPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var clipSpeed = 1.0
    @ObservationIgnored private var wide: CGFloat = 1
    // The finished video, if it's one of the clips itself (kept for the editor).
    @ObservationIgnored private var handedOut: URL?

    private(set) var access = Access.unknown
    private(set) var microphone = true
    private(set) var running = false
    // Cut off for a moment (a call, another app using the camera).
    private(set) var paused = false
    private(set) var switching = false
    private(set) var position = AVCaptureDevice.Position.back
    private(set) var lenses: [CameraLens] = []
    private(set) var zoom: CGFloat = 1
    private(set) var maxZoom: CGFloat = 1
    private(set) var hasTorch = false
    private(set) var flash = false
    private(set) var clips: [Clip] = []
    private(set) var recording = false
    // Stop was tapped; the camera is finishing the clip's file.
    private(set) var stopping = false
    private(set) var current: Double = 0
    private(set) var filter = ReelFilter.none
    private(set) var photoMode = false
    private(set) var focusLocked = false
    private(set) var exposure: Float = 0
    // Goes up when the camera takes focus back (the scene changed).
    private(set) var refocused = 0
    private(set) var joinProgress = 0.0
    var maxSeconds: Double = 60
    var speed: Double = 1

    // Filming, as far as the screen is concerned (it ends the moment you
    // tap stop, without waiting for the file).
    var live: Bool { recording && !stopping }
    var filmed: Double { clips.reduce(0) { $0 + $1.effective } }
    var total: Double { filmed + (recording ? current / clipSpeed : 0) }
    var canFilm: Bool { running && !paused && total < maxSeconds - 0.3 }

    // MARK: on and off

    func start() async {
        if access == .unknown {
            let video = await AVCaptureDevice.requestAccess(for: .video)
            access = video ? .granted : .denied
            if video { microphone = await AVCaptureDevice.requestAccess(for: .audio) }
        }
        guard access == .granted else { return }
        let core = self.core, renderer = self.renderer, position = self.position, mic = microphone
        let setup = await core.run { () -> CameraSetup? in
            let ready = core.configure(position: position, microphone: mic, frameDelegate: renderer)
            core.start()
            return ready
        }
        guard let setup else {
            access = .unavailable
            return
        }
        apply(setup)
        applyTorch()
        watch()
        running = true
    }

    func stop() {
        progressTask?.cancel()
        soundPlayer?.pause()
        running = false
        unwatch()
        let core = self.core
        core.queue.async {
            core.stopRecording()
            core.setTorch(false)
            core.stop()
        }
        // Clips nobody needs any more (one that became the video stays for
        // the editor).
        for clip in clips where clip.url != handedOut { try? FileManager.default.removeItem(at: clip.url) }
    }

    private func apply(_ setup: CameraSetup) {
        position = setup.position
        lenses = setup.lenses
        wide = setup.wide
        maxZoom = setup.maxShown
        hasTorch = setup.hasTorch
        zoom = 1
    }

    // MARK: camera controls

    func flip() {
        guard !recording, !switching, access == .granted else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        switching = true
        let core = self.core
        let torch = flash && next == .back && !photoMode
        Task {
            let setup = await core.run { () -> CameraSetup? in
                let ready = core.switchCamera(to: next)
                if torch { core.setTorch(true) }
                return ready
            }
            if let setup { apply(setup) }
            focusLocked = false
            exposure = 0
            switching = false
        }
    }

    // Zoom as shown on the buttons (0.5×, 1×…); smoothly for a lens button.
    func setZoom(_ shown: CGFloat, smooth: Bool) {
        let low = lenses.first?.shown ?? 1
        let value = min(max(shown, low), max(low, maxZoom))
        zoom = value
        let factor = value * wide
        let core = self.core
        core.queue.async { core.setZoom(factor, smooth: smooth) }
    }

    // `point` is in the camera's own 0…1 space.
    func focus(at point: CGPoint, lock: Bool) {
        focusLocked = lock
        exposure = 0
        let core = self.core
        core.queue.async { core.focus(at: point, lock: lock, watch: true) }
    }

    func setExposure(_ value: Float) {
        exposure = min(max(value, -2), 2)
        let bias = exposure
        let core = self.core
        core.queue.async { core.setExposure(bias) }
    }

    func toggleFlash() {
        flash.toggle()
        applyTorch()
    }

    func setPhotoMode(_ on: Bool) {
        photoMode = on
        applyTorch()
    }

    // The back camera's light stays on while you line up and film (like
    // TikTok); photos use the real flash instead.
    private func applyTorch() {
        let on = flash && position == .back && !photoMode && access == .granted
        let core = self.core
        core.queue.async { core.setTorch(on) }
    }

    func setFilter(_ next: ReelFilter) {
        filter = next
        renderer.show(next)
        let on = next != .none
        let core = self.core
        core.queue.async { core.setFrames(on) }
    }

    // The song plays while you film (slower or faster to match the speed).
    func setSound(_ track: Track?) {
        soundPlayer?.pause()
        soundPlayer = track.flatMap { URL(string: $0.audioURL) }.map { AVPlayer(url: $0) }
    }

    // MARK: clips

    func startClip() {
        guard !recording, canFilm else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mov")
        recording = true
        stopping = false
        current = 0
        clipSpeed = speed
        if let soundPlayer {
            soundPlayer.seek(to: CMTime(seconds: filmed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            soundPlayer.rate = Float(1 / speed)
        }
        let core = self.core
        core.queue.async { [weak self] in
            guard let self else { return }
            if !core.startRecording(to: url, delegate: self) {
                Task { @MainActor in self.clipEnded() }
            }
        }
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.recording else { return }
                let seconds = self.core.movie.recordedDuration.seconds
                if seconds.isFinite { self.current = seconds }
                if self.total >= self.maxSeconds { self.stopClip() }
            }
        }
    }

    func stopClip() {
        guard recording, !stopping else { return }
        stopping = true
        soundPlayer?.pause()
        let core = self.core
        core.queue.async { core.stopRecording() }
        // If the camera never answers (it was cut off), don't stay stuck.
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.stopping else { return }
            self.clipEnded()
        }
    }

    private func clipEnded() {
        watchdog?.cancel()
        progressTask?.cancel()
        recording = false
        stopping = false
        current = 0
        soundPlayer?.pause()
    }

    fileprivate func finished(_ url: URL, seconds: Double) {
        let speed = clipSpeed
        clipEnded()
        guard seconds > 0.25 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let clip = Clip(url: url, seconds: seconds, speed: speed)
        clips.append(clip)
        Task { await addGhost(clip.id, url) }
    }

    // Grabs the clip's last moment, shown see-through with "Align" so the
    // next clip can start exactly where this one stopped.
    private func addGhost(_ id: UUID, _ url: URL) async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        guard let duration = try? await asset.load(.duration) else { return }
        let at = CMTime(seconds: max(0, duration.seconds - 0.1), preferredTimescale: 600)
        guard let frame = try? await generator.image(at: at) else { return }
        if let i = clips.firstIndex(where: { $0.id == id }) { clips[i].ghost = UIImage(cgImage: frame.image) }
    }

    func deleteLast() {
        guard !recording, let last = clips.popLast() else { return }
        try? FileManager.default.removeItem(at: last.url)
    }

    func restart() {
        guard !recording else { return }
        for clip in clips { try? FileManager.default.removeItem(at: clip.url) }
        clips = []
    }

    // All the clips as one video.
    func makeVideo() async throws -> URL {
        joinProgress = 0
        let pieces = clips.map { ClipStitcher.Piece(url: $0.url, speed: $0.speed) }
        let url = try await ClipStitcher.join(pieces) { [weak self] value in
            Task { @MainActor [weak self] in self?.joinProgress = value }
        }
        handedOut = url
        return url
    }

    // MARK: photos

    func takePhoto() {
        guard running, !paused else { return }
        let core = self.core
        let flashOn = flash && position == .back
        core.queue.async { [weak self] in
            guard let self else { return }
            core.capturePhoto(flash: flashOn, delegate: self)
        }
    }

    // Exactly what the camera window showed: the middle 9:16 of the photo,
    // at most 2160 tall.
    nonisolated static func reelFrame(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let shape: CGFloat = 9.0 / 16.0
        var crop = size
        if size.width / size.height > shape { crop.width = size.height * shape } else { crop.height = size.width / shape }
        let scale = min(1, 2160 / crop.height)
        let out = CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(x: (out.width - drawn.width) / 2, y: (out.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
    }

    // MARK: interruptions

    private func watch() {
        unwatch()
        let center = NotificationCenter.default
        let session = core.session
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.interrupted(true) }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.interrupted(false) }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recover() }
            },
            center.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sceneChanged() }
            },
        ]
    }

    private func unwatch() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func interrupted(_ on: Bool) {
        paused = on
        if on && recording { stopClip() }
    }

    // The camera hit a problem: start it again.
    private func recover() {
        guard access == .granted, running else { return }
        let core = self.core
        core.queue.async { core.start() }
    }

    // The picture changed a lot since you tapped to focus: the camera takes
    // over again, sharp and bright in the middle.
    private func sceneChanged() {
        guard !focusLocked, running else { return }
        exposure = 0
        refocused += 1
        let core = self.core
        core.queue.async { core.focus(at: CGPoint(x: 0.5, y: 0.5), lock: false, watch: false) }
    }
}

extension CameraEngine: AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // Cut off by a call or the app closing: the clip up to then is fine.
        var usable = error == nil
        if let error = error as NSError?, let finished = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
            usable = finished
        }
        let seconds = output.recordedDuration.seconds
        let length = usable && seconds.isFinite ? seconds : 0
        Task { @MainActor in self.finished(outputFileURL, seconds: length) }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let framed = CameraEngine.reelFrame(image)
        Task { @MainActor in self.onPhoto?(framed) }
    }
}
