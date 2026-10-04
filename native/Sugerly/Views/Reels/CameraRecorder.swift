import SwiftUI
import UIKit
import AVFoundation

// MARK: - Camera engine

// The in-app camera: video in clips (tap to record, tap again to pause, or
// hold to film while you hold; keep adding clips, delete the last one or
// start over) and photos. Flash (a ring light on the screen for the front
// camera), front / back, tap to focus, pinch or slide to zoom, a 3 s / 10 s
// timer and "Align" to line the next clip up with the last one.
@MainActor
@Observable
final class RecorderModel: NSObject {
    struct Clip: Identifiable {
        let id = UUID()
        let url: URL
        let seconds: Double
        var speed: Double = 1
        // The clip's last moment, for "Align".
        var ghost: UIImage? = nil
        var effective: Double { seconds / speed }
    }

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var soundPlayer: AVPlayer?
    private var clipSpeed: Double = 1
    private var videoInput: AVCaptureDeviceInput?
    private var device: AVCaptureDevice?
    private var progressTask: Task<Void, Never>?
    private var configured = false

    var authorized: Bool?
    var position: AVCaptureDevice.Position = .back
    var clips: [Clip] = []
    var recording = false
    var current: Double = 0
    var flash = false
    var photoMode = false
    var zoom: CGFloat = 1
    var maxSeconds: Double = 60
    var speed: Double = 1
    var onPhoto: ((UIImage) -> Void)?
    var busy = false

    var total: Double { clips.reduce(0) { $0 + $1.effective } + (recording ? current / clipSpeed : 0) }
    var hasFlash: Bool { device?.hasTorch ?? false }

    func start() async {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        authorized = video
        guard video else { return }
        if !configured { configure() }
        let session = self.session
        await Task.detached { session.startRunning() }.value
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
        progressTask?.cancel()
        setTorch(false)
        soundPlayer?.pause()
    }

    // The sound plays while you film (slower or faster to match the speed).
    func setSound(_ track: Track?) {
        soundPlayer?.pause()
        soundPlayer = track.flatMap { URL(string: $0.audioURL) }.map { AVPlayer(url: $0) }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let cam = camera(position), let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            device = cam
        }
        if let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        fixConnections()
    }

    private func camera(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func fixConnections() {
        for output in [movieOutput as AVCaptureOutput, photoOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
    }

    func flip() {
        guard !recording else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let cam = camera(next), let input = try? AVCaptureDeviceInput(device: cam) else { return }
        setTorch(false)
        session.beginConfiguration()
        if let videoInput { session.removeInput(videoInput) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            device = cam
            position = next
        } else if let videoInput {
            session.addInput(videoInput)
        }
        session.commitConfiguration()
        fixConnections()
        zoom = 1
        applyTorch()
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let z = min(max(1, factor), min(device.activeFormat.videoMaxZoomFactor, 8))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = z
            device.unlockForConfiguration()
            zoom = z
        } catch {}
    }

    // Tap to focus: sharp and bright where you tapped.
    func focus(at point: CGPoint) {
        guard let device else { return }
        let p = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = p
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = p
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {}
    }

    func toggleFlash() {
        flash.toggle()
        applyTorch()
    }

    func setPhotoMode(_ on: Bool) {
        photoMode = on
        applyTorch()
    }

    // Back camera + flash: the light stays on while you line up and film
    // (like TikTok). Photos use the real flash instead.
    private func applyTorch() {
        setTorch(flash && position == .back && !photoMode)
    }

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchModeSupported(on ? .on : .off) else { return }
        if on && !device.isTorchAvailable { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: video clips

    func toggleRecording() {
        if recording { stopClip() } else { startClip() }
    }

    func startClip() {
        guard !recording, total < maxSeconds - 0.3, session.isRunning else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mov")
        applyTorch()
        movieOutput.startRecording(to: url, recordingDelegate: self)
        recording = true
        current = 0
        clipSpeed = speed
        if let soundPlayer {
            soundPlayer.seek(to: CMTime(seconds: total, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            soundPlayer.rate = Float(1 / speed)
        }
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.recording else { return }
                self.current = self.movieOutput.recordedDuration.seconds.isFinite ? self.movieOutput.recordedDuration.seconds : 0
                if self.total >= self.maxSeconds { self.stopClip() }
            }
        }
    }

    func stopClip() {
        guard recording else { return }
        movieOutput.stopRecording()
        soundPlayer?.pause()
    }

    fileprivate func finished(_ url: URL, _ seconds: Double) {
        recording = false
        progressTask?.cancel()
        current = 0
        if seconds > 0.2 {
            let clip = Clip(url: url, seconds: seconds, speed: clipSpeed)
            clips.append(clip)
            Task { await addGhost(to: clip.id, from: url) }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // Grabs the clip's last moment, shown see-through with "Align" so the
    // next clip can start exactly where this one stopped.
    private func addGhost(to id: UUID, from url: URL) async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1000, height: 1000)
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
        for c in clips { try? FileManager.default.removeItem(at: c.url) }
        clips = []
    }

    // Glue the clips into one video.
    func merge() async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw APIError(message: "Couldn't put the clips together.")
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if let v = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(range, of: v, at: cursor)
                if cursor == .zero { videoTrack.preferredTransform = try await v.load(.preferredTransform) }
            }
            var hasAudio = false
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                hasAudio = (try? audioTrack?.insertTimeRange(range, of: a, at: cursor)) != nil
            }
            // Speed: 2x makes the clip half as long, 0.5x twice as long.
            var length = duration
            if abs(clip.speed - 1) > 0.01 {
                length = CMTimeMultiplyByFloat64(duration, multiplier: 1 / clip.speed)
                let placed = CMTimeRange(start: cursor, duration: duration)
                videoTrack.scaleTimeRange(placed, toDuration: length)
                if hasAudio { audioTrack?.scaleTimeRange(placed, toDuration: length) }
            }
            cursor = CMTimeAdd(cursor, length)
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("reel-\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw APIError(message: "Couldn't put the clips together.")
        }
        export.outputURL = out
        export.outputFileType = .mp4
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { done.resume() }
        }
        guard export.status == .completed else { throw APIError(message: export.error?.localizedDescription ?? "Couldn't put the clips together.") }
        return out
    }

    // MARK: photos

    func takePhoto() {
        let settings = AVCapturePhotoSettings()
        if flash, photoOutput.supportedFlashModes.contains(.on), position == .back { settings.flashMode = .on }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    fileprivate func gotPhoto(_ image: UIImage) {
        onPhoto?(image)
    }
}

extension RecorderModel: AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let seconds = output.recordedDuration.seconds
        Task { @MainActor in self.finished(outputFileURL, seconds.isFinite ? seconds : 0) }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        Task { @MainActor in self.gotPhoto(image) }
    }
}

// Live camera picture. Tap it to focus there, tap twice to flip the camera.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    // Where you tapped on the screen, and the same spot for the camera.
    var onFocus: ((CGPoint, CGPoint) -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CameraPreview
        init(_ parent: CameraPreview) { self.parent = parent }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewView else { return }
            let point = gesture.location(in: view)
            parent.onFocus?(point, view.preview.captureDevicePointConverted(fromLayerPoint: point))
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap?()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        single.require(toFail: double)
        view.addGestureRecognizer(double)
        view.addGestureRecognizer(single)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.parent = self
    }
}

// The colour of the front camera's light.
enum FrontLightTone: String, CaseIterable, Identifiable {
    case warm, white, pink
    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: return "Warm"
        case .white: return "Cool"
        case .pink: return "Pink"
        }
    }

    var color: Color {
        switch self {
        case .warm: return Color(red: 1, green: 0.94, blue: 0.84)
        case .white: return Color(red: 0.96, green: 0.98, blue: 1)
        case .pink: return Color(red: 1, green: 0.87, blue: 0.92)
        }
    }
}

// The front camera's flash (like TikTok and Instagram): the whole screen
// around the picture becomes a soft, bright light panel that lights your
// face, and the camera sits in a rounded window in the middle.
struct FrontLight: View {
    var tone: FrontLightTone

    var body: some View {
        ZStack {
            tone.color
            RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 60, endRadius: 560)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Camera screen

// Opens straight away when you make a reel (like TikTok). Tap the big button
// to film and again to pause, or hold it to film while you hold (slide your
// finger up to zoom). Tap the picture to focus, tap twice to flip.
struct RecorderView: View {
    @Binding var sound: Track?
    var onVideo: (URL) -> Void
    var onPhotos: ([UIImage]) -> Void
    var onClose: () -> Void
    // Pick a video or photos from your library instead.
    var onUpload: (() -> Void)? = nil
    // Your saved drafts (none in chats).
    var draftCount = 0
    var onDrafts: (() -> Void)? = nil

    enum Mode: String { case short = "15s", video = "60s", photo = "Photo" }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sugerly.recorder.tip") private var tipShown = false
    @State private var camera = RecorderModel()
    @State private var mode: Mode = .video
    @State private var timer = 0
    @State private var countdown = 0
    @State private var shots: [UIImage] = []
    @State private var flashScreen = false
    @State private var merging = false
    @State private var error: String?
    @State private var pinchStart: CGFloat = 1
    @State private var confirmRestart = false
    @State private var grid = false
    @State private var align = false
    @State private var showSpeed = false
    @State private var pickingSound = false
    @State private var focusPoint: CGPoint?
    @State private var focusTick = 0
    @State private var hint: String?
    @State private var hintTick = 0
    // Holding the big button.
    @GestureState private var pressing = false
    @State private var pressStart: Date?
    @State private var heldClip = false
    @State private var holdZoom: CGFloat = 1
    @State private var savedBrightness: CGFloat?
    @AppStorage("sugerly.recorder.lightTone") private var lightTone: FrontLightTone = .warm

    // Front camera + flash on: the light panel.
    private var ringLight: Bool { camera.flash && camera.position == .front && camera.authorized == true }
    // How far in the camera window sits while the light is on.
    private var lightInset: CGFloat { ringLight ? 16 : 0 }
    private var windowCorner: CGFloat { 34 }

    var body: some View {
        watchers(screen)
            .sheet(isPresented: $pickingSound) {
                SoundPicker { track in sound = track }
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(30)
            }
            .confirmationDialog("Start over?", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("Delete all clips", role: .destructive) { withAnimation { camera.restart() } }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: countdown) { _, new in new > 0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: countdown)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: camera.recording)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: camera.clips.count)
            .animation(.easeInOut(duration: 0.25), value: ringLight)
            .animation(.easeInOut(duration: 0.25), value: align)
    }

    private var screen: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 0.75
            let previewWidth = wide ? min(geo.size.width, geo.size.height * 0.6) : geo.size.width
            ZStack {
                Color.black.ignoresSafeArea()
                if ringLight { FrontLight(tone: lightTone).transition(.opacity) }
                cameraWindow(wide: wide, width: previewWidth)
                if flashScreen { photoFlash }
                controls
                    .frame(width: previewWidth - lightInset * 2)
                    .padding(.vertical, ringLight ? 8 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    // The camera: the whole screen, or a rounded window inside the light.
    private func cameraWindow(wide: Bool, width: CGFloat) -> some View {
        let corner: CGFloat = wide || ringLight ? windowCorner : 0
        let edges: Edge.Set = wide || ringLight ? [] : .all
        return previewArea(wide: wide)
            .frame(width: width - lightInset * 2)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay { if ringLight { windowEdge } }
            .background { if ringLight { windowGlow } }
            .padding(.vertical, ringLight ? 8 : 0)
            .ignoresSafeArea(edges: edges)
    }

    // The quick burst of light for a selfie photo.
    private var photoFlash: some View {
        let color: Color = ringLight ? lightTone.color : .white
        return color.ignoresSafeArea().transition(.opacity)
    }

    // Starting and stopping the camera, and keeping it in step with the
    // sound, the ring light and the app going to the background.
    private func watchers<Content: View>(_ content: Content) -> some View {
        content
            .task {
                camera.setSound(sound)
                camera.onPhoto = { image in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { shots.append(image) }
                }
                await camera.start()
                if !tipShown && camera.authorized == true {
                    tipShown = true
                    showHint("Tap to film, or hold the button and slide up to zoom")
                }
            }
            .onDisappear {
                camera.stop()
                brighten(false)
            }
            .onChange(of: sound) { _, track in camera.setSound(track) }
            .onChange(of: ringLight) { _, on in brighten(on) }
            .onChange(of: scenePhase) { _, phase in brighten(phase == .active && ringLight) }
            .onChange(of: pressing) { _, now in
                // The touch was cut off (a call, an alert) without letting go:
                // a clip filmed by holding stops.
                guard !now else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    if pressStart != nil { pressCancelled() }
                }
            }
            .onChange(of: mode) { _, m in
                camera.maxSeconds = m == .short ? 15 : 60
                camera.setPhotoMode(m == .photo)
            }
    }

    // The camera picture with the ring light, the photo flash and the
    // countdown on top.
    private func previewArea(wide: Bool) -> some View {
        ZStack {
            cameraLayer
            if countdown > 0 {
                Text("\(countdown)")
                    .font(.display(140)).foregroundStyle(.white)
                    .shadow(color: Theme.main, radius: 20)
                    .id(countdown)
                    .transition(.scale(scale: 2).combined(with: .opacity))
            }
        }
    }

    // A thin bright edge around the camera window, and a soft glow behind
    // it (plain shapes, so the live camera itself is never blurred).
    private var windowEdge: some View {
        RoundedRectangle(cornerRadius: windowCorner, style: .continuous)
            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
            .allowsHitTesting(false)
    }

    private var windowGlow: some View {
        RoundedRectangle(cornerRadius: windowCorner, style: .continuous)
            .stroke(.white, lineWidth: 10)
            .blur(radius: 12)
            .allowsHitTesting(false)
    }

    // Warm, cool or pink light.
    private var lightTones: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
            ForEach(FrontLightTone.allCases) { t in
                let on = lightTone == t
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { lightTone = t }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(t.color).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                        Text(t.title).font(.jakarta(12, .heavy))
                    }
                    .foregroundStyle(on ? Color(hex: 0x2A1620) : .white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(on ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("\(t.title) light")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.5), in: Capsule())
        .sensoryFeedback(.selection, trigger: lightTone)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var cameraLayer: some View {
        if camera.authorized == true {
            livePreview
        } else if camera.authorized == false {
            accessOff
        }
    }

    private var livePreview: some View {
        CameraPreview(session: camera.session, onFocus: { point, spot in
            tapFocus(point, spot)
        }, onDoubleTap: { flip() })
            .overlay { alignGhost }
            .overlay { if grid { CameraGrid() } }
            .overlay { focusRing }
            .gesture(MagnifyGesture()
                .onChanged { v in camera.setZoom(pinchStart * v.magnification) }
                .onEnded { _ in pinchStart = camera.zoom })
    }

    @ViewBuilder
    private var alignGhost: some View {
        if align, !camera.recording, let ghost = camera.clips.last?.ghost {
            ghostView(ghost)
        }
    }

    private var accessOff: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Theme.gradient)
            Text("Camera access is off").font(.display(24)).foregroundStyle(.white)
            Text("Turn it on in Settings → Sugerly to film here.").font(.jakarta(14)).foregroundStyle(.white.opacity(0.7))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(GradientButtonStyle(fullWidth: false))
            if let onUpload {
                Button("Choose from library", action: onUpload)
                    .font(.jakarta(15, .bold)).foregroundStyle(.white)
                    .padding(.top, 4)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            topControls
            Spacer()
            if let error {
                Text(error).font(.jakarta(13, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Palette.danger, in: Capsule())
            }
            bottomControls
        }
    }

    // Clip progress (like TikTok / Discord): one segment per clip.
    private var progressBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 2) {
                ForEach(camera.clips) { clip in
                    Capsule().fill(Theme.gradient).frame(width: max(2, w * clip.effective / camera.maxSeconds - 2))
                }
                if camera.recording {
                    Capsule().fill(Color.white).frame(width: max(2, w * (camera.total - camera.clips.reduce(0) { $0 + $1.effective }) / camera.maxSeconds))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 5)
            .background(Capsule().fill(.white.opacity(0.22)))
        }
        .frame(height: 5)
    }

    private var topControls: some View {
        VStack(spacing: 10) {
            if mode != .photo { progressBar.padding(.horizontal, 14) }
            HStack(spacing: 10) {
                roundButton("xmark", label: "Close") { camera.stop(); onClose() }
                Spacer(minLength: 6)
                soundPill
                Spacer(minLength: 6)
                if mode != .photo && !camera.clips.isEmpty && !camera.recording {
                    roundButton("arrow.counterclockwise", label: "Start over") { confirmRestart = true }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 14)
            if ringLight && !camera.recording { lightTones }
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    roundButton("arrow.triangle.2.circlepath.camera.fill", label: "Flip camera") { flip() }
                    roundButton(camera.flash ? "bolt.fill" : "bolt.slash.fill", label: "Flash", active: camera.flash) {
                        camera.toggleFlash()
                        showHint(camera.flash ? (camera.position == .front ? "Front light on: pick warm, cool or pink" : "Flash on") : "Flash off")
                    }
                    Button {
                        timer = timer == 0 ? 3 : timer == 3 ? 10 : 0
                        showHint(timer == 0 ? "Timer off" : "\(timer)s timer: tap the button, then get ready")
                    } label: {
                        VStack(spacing: 0) {
                            Image(systemName: "timer").font(.system(size: 15, weight: .bold))
                            if timer > 0 { Text("\(timer)s").font(.jakarta(10, .heavy)) }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(timer > 0 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle())
                    .accessibilityLabel("Timer")
                    .accessibilityValue(timer == 0 ? "Off" : "\(timer) seconds")
                    if mode != .photo {
                        Button { withAnimation(.snappy) { showSpeed.toggle() } } label: {
                            Text(speedLabel(camera.speed)).font(.jakarta(13, .heavy)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(camera.speed != 1 || showSpeed ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(BouncyStyle())
                        .accessibilityLabel("Speed")
                    }
                    roundButton("grid", label: "Grid", active: grid) { grid.toggle() }
                    if mode != .photo && !camera.clips.isEmpty {
                        roundButton("square.on.square.dashed", label: "Align", active: align) {
                            align.toggle()
                            if align { showHint("Line up with the end of your last clip") }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .opacity(camera.recording ? 0 : 1)
            }
            .padding(.horizontal, 14)
            if camera.zoom > 1.05 {
                Text(String(format: "%.1fx", camera.zoom)).font(.jakarta(12, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.4), in: Capsule())
            }
            if let hint {
                Text(hint).font(.jakarta(13, .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.horizontal, 30)
                    .id(hintTick)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.top, 8)
    }

    private var soundPill: some View {
        Button { if !camera.recording { pickingSound = true } } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 13, weight: .bold))
                Text(sound?.title ?? "Add sound").font(.jakarta(13, .bold)).lineLimit(1)
                if sound != nil {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
                        .onTapGesture { sound = nil }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 36)
            .frame(maxWidth: 200)
            .background(.black.opacity(0.4), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle())
    }

    private func speedLabel(_ v: Double) -> String { v == 0.5 ? "0.5x" : "\(Int(v))x" }

    private var speedRow: some View {
        HStack(spacing: 4) {
            ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { v in
                Button { withAnimation(.snappy) { camera.speed = v } } label: {
                    Text(speedLabel(v)).font(.jakarta(13, .heavy))
                        .foregroundStyle(camera.speed == v ? Color(hex: 0x2A1620) : .white)
                        .frame(width: 58, height: 34)
                        .background(camera.speed == v ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(SoftPressStyle())
            }
        }
        .padding(4)
        .background(.black.opacity(0.45), in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if !camera.recording && showSpeed && mode != .photo { speedRow }
            if mode == .photo && !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shots.indices, id: \.self) { i in
                            Image(uiImage: shots[i]).resizable().scaledToFill()
                                .frame(width: 52, height: 70).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { withAnimation { _ = shots.remove(at: i) } } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 6)
                }
            }
            HStack(alignment: .center) {
                // Left: delete the last clip, or your drafts before you start.
                Group {
                    if mode != .photo && !camera.clips.isEmpty && !camera.recording {
                        roundButton("delete.backward.fill", size: 50, label: "Delete last clip") { withAnimation { camera.deleteLast() } }
                            .transition(.scale.combined(with: .opacity))
                    } else if draftCount > 0, let onDrafts, camera.clips.isEmpty, shots.isEmpty, !camera.recording {
                        sideTile("tray.full.fill", "Drafts", action: onDrafts)
                    } else {
                        Color.clear.frame(width: 50, height: 50)
                    }
                }
                .frame(maxWidth: .infinity)

                recordButton

                // Right: done, or pick from your library before you start.
                Group {
                    let ready = mode != .photo ? (!camera.clips.isEmpty && !camera.recording) : !shots.isEmpty
                    if ready {
                        Button { Task { await finish() } } label: {
                            Group {
                                if merging { ProgressView().tint(.white) } else { Image(systemName: "checkmark").font(.system(size: 20, weight: .heavy)) }
                            }
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Theme.gradient, in: Circle())
                            .shadow(color: Theme.main.opacity(0.5), radius: 10, y: 4)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.85))
                        .disabled(merging)
                        .accessibilityLabel("Done")
                        .transition(.scale.combined(with: .opacity))
                    } else if let onUpload, camera.clips.isEmpty, !camera.recording, countdown == 0 {
                        sideTile("photo.on.rectangle.angled", "Upload", action: onUpload)
                    } else {
                        Color.clear.frame(width: 54, height: 54)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 26) {
                ForEach([Mode.short, Mode.video, Mode.photo], id: \.self) { m in
                    Button {
                        guard !camera.recording else { return }
                        if m == .short && camera.total > 15 { error = "You've already filmed more than 15s"; return }
                        withAnimation(.snappy) { mode = m }
                    } label: {
                        VStack(spacing: 4) {
                            Text(m.rawValue).font(.jakarta(14, .heavy)).foregroundStyle(mode == m ? .white : .white.opacity(0.55))
                            Circle().fill(Theme.gradient).frame(width: 5, height: 5).opacity(mode == m ? 1 : 0)
                        }
                    }
                    .buttonStyle(SoftPressStyle())
                    .accessibilityAddTraits(mode == m ? .isSelected : [])
                }
            }
            .padding(.bottom, 10)
        }
        .padding(.bottom, 12)
        .background { bottomShade }
    }

    // Keeps the buttons easy to read over the picture (inside the window's
    // rounded corners while the front light is on).
    private var bottomShade: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: ringLight ? windowCorner : 0,
                                              bottomTrailingRadius: ringLight ? windowCorner : 0, style: .continuous))
            .ignoresSafeArea(edges: ringLight ? [] : .all)
    }

    // The big button: tap to start / pause, or hold to film while you hold
    // (it grows, and sliding up zooms in).
    private var recordButton: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 5).frame(width: 84, height: 84)
            if mode != .photo {
                Circle()
                    .trim(from: 0, to: camera.total / camera.maxSeconds)
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
                RoundedRectangle(cornerRadius: camera.recording ? 10 : 34, style: .continuous)
                    .fill(Theme.gradient)
                    .frame(width: camera.recording ? 34 : 68, height: camera.recording ? 34 : 68)
            } else {
                Circle().fill(.white).frame(width: 68, height: 68)
            }
        }
        .shadow(color: Theme.main.opacity(camera.recording ? 0.7 : 0.3), radius: camera.recording ? 18 : 8)
        .scaleEffect(heldClip ? 1.18 : (pressStart != nil ? 0.92 : 1))
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: heldClip)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressStart != nil)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { v in
                if pressStart == nil { pressDown() }
                // Holding: slide up to zoom in.
                if heldClip, v.translation.height < -12 {
                    camera.setZoom(holdZoom + (-v.translation.height - 12) / 70)
                }
            }
            .onEnded { _ in pressUp() })
        .allowsHitTesting(countdown == 0 && !merging)
        .opacity(merging ? 0.6 : 1)
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.recording)
        .accessibilityElement()
        .accessibilityLabel(mode == .photo ? "Take photo" : camera.recording ? "Stop filming" : "Film")
        .accessibilityHint(mode == .photo ? "" : "Tap to start and stop, or hold to film while you hold")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await shutter() } }
    }

    // Holding to film starts straight away (no timer); a quick tap does the
    // usual thing when you let go.
    private func pressDown() {
        pressStart = .now
        guard mode != .photo, timer == 0, !camera.recording, camera.total < camera.maxSeconds - 0.3 else { return }
        error = nil
        holdZoom = camera.zoom
        camera.startClip()
        heldClip = camera.recording
    }

    private func pressUp() {
        let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? 0
        pressStart = nil
        if heldClip {
            heldClip = false
            pinchStart = camera.zoom
            // Held: filming stops when you let go. A quick tap keeps filming
            // until you tap again.
            if held > 0.4 { camera.stopClip() }
            return
        }
        Task { await shutter() }
    }

    private func pressCancelled() {
        pressStart = nil
        if heldClip {
            heldClip = false
            camera.stopClip()
        }
    }

    private func flip() {
        guard !camera.recording else { return }
        camera.flip()
        pinchStart = 1
    }

    private func tapFocus(_ point: CGPoint, _ spot: CGPoint) {
        camera.focus(at: spot)
        focusTick += 1
        let tick = focusTick
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { focusPoint = point }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard focusTick == tick else { return }
            withAnimation(.easeOut(duration: 0.3)) { focusPoint = nil }
        }
    }

    // A little circle where you tapped to focus.
    private var focusRing: some View {
        ZStack {
            if let focusPoint {
                Circle().strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .position(focusPoint)
                    .id(focusTick)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // "Align": the end of your last clip, see-through over the camera.
    private func ghostView(_ image: UIImage) -> some View {
        Color.clear
            .overlay { Image(uiImage: image).resizable().scaledToFill() }
            .clipped()
            .opacity(0.38)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func showHint(_ text: String) {
        hintTick += 1
        let tick = hintTick
        withAnimation(.snappy(duration: 0.25)) { hint = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard hintTick == tick else { return }
            withAnimation(.easeOut(duration: 0.3)) { hint = nil }
        }
    }

    // The ring light turns the screen all the way up while it's on, and puts
    // your own brightness back after.
    private func brighten(_ on: Bool) {
        let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }
        guard let screen = screens.first else { return }
        if on {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1
        } else if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }

    private func roundButton(_ icon: String, size: CGFloat = 44, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // A square button with its name under it (Upload, Drafts).
    private func sideTile(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                Text(title).font(.jakarta(11, .heavy)).foregroundStyle(.white)
            }
        }
        .buttonStyle(BouncyStyle())
        .transition(.scale.combined(with: .opacity))
    }

    private func shutter() async {
        error = nil
        if mode != .photo && camera.recording {
            camera.stopClip()
            return
        }
        if timer > 0 {
            for n in stride(from: timer, through: 1, by: -1) {
                countdown = n
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = 0
        }
        if mode != .photo {
            if camera.total >= camera.maxSeconds - 0.3 { error = "\(Int(camera.maxSeconds)) seconds max — tap Done to continue."; return }
            camera.startClip()
        } else {
            if camera.flash && camera.position == .front {
                withAnimation(.easeIn(duration: 0.08)) { flashScreen = true }
                try? await Task.sleep(for: .milliseconds(150))
            }
            camera.takePhoto()
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.3)) { flashScreen = false }
        }
    }

    // The camera turns off by itself once this screen goes away.
    private func finish() async {
        if mode == .photo {
            onPhotos(shots)
            return
        }
        merging = true
        defer { merging = false }
        do {
            let url = try await camera.merge()
            onVideo(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Rule-of-thirds lines over the camera.
struct CameraGrid: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3
                    let y = g.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
