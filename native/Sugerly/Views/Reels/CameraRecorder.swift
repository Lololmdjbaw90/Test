import SwiftUI
import UIKit
import AVFoundation

// MARK: - Camera engine

// The in-app camera: video in clips (tap to record, tap again to pause, keep
// adding clips, delete the last one or start over) and photos. Flash, front
// / back, pinch to zoom and a 3 s / 10 s timer.
@MainActor
@Observable
final class RecorderModel: NSObject {
    struct Clip: Identifiable { let id = UUID(); let url: URL; let seconds: Double }

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
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
    var zoom: CGFloat = 1
    let maxSeconds: Double = 60
    var onPhoto: ((UIImage) -> Void)?
    var busy = false

    var total: Double { clips.reduce(0) { $0 + $1.seconds } + (recording ? current : 0) }
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

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { return }
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
        if flash && position == .back { setTorch(true) }
        movieOutput.startRecording(to: url, recordingDelegate: self)
        recording = true
        current = 0
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
        setTorch(false)
    }

    fileprivate func finished(_ url: URL, _ seconds: Double) {
        recording = false
        progressTask?.cancel()
        current = 0
        if seconds > 0.2 {
            clips.append(Clip(url: url, seconds: seconds))
        } else {
            try? FileManager.default.removeItem(at: url)
        }
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
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack?.insertTimeRange(range, of: a, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
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

// Live camera picture.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

// MARK: - Camera screen

struct RecorderView: View {
    var onVideo: (URL) -> Void
    var onPhotos: ([UIImage]) -> Void
    var onClose: () -> Void

    enum Mode: String { case video = "Video", photo = "Photo" }

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

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 0.75
            let previewWidth = wide ? min(geo.size.width, geo.size.height * 0.6) : geo.size.width
            ZStack {
                Color.black.ignoresSafeArea()
                ZStack {
                    if camera.authorized == true {
                        CameraPreview(session: camera.session)
                            .gesture(MagnifyGesture()
                                .onChanged { v in camera.setZoom(pinchStart * v.magnification) }
                                .onEnded { _ in pinchStart = camera.zoom })
                            .onTapGesture(count: 2) { camera.flip() }
                    } else if camera.authorized == false {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Theme.gradient)
                            Text("Camera access is off").font(.display(24)).foregroundStyle(.white)
                            Text("Turn it on in Settings → Sugerly to film here.").font(.jakarta(14)).foregroundStyle(.white.opacity(0.7))
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                            .buttonStyle(GradientButtonStyle(fullWidth: false))
                        }
                    }
                    if flashScreen { Color.white.ignoresSafeArea().transition(.opacity) }
                    if countdown > 0 {
                        Text("\(countdown)")
                            .font(.display(140)).foregroundStyle(.white)
                            .shadow(color: Theme.main, radius: 20)
                            .id(countdown)
                            .transition(.scale(scale: 2).combined(with: .opacity))
                    }
                }
                .frame(width: previewWidth)
                .clipShape(RoundedRectangle(cornerRadius: wide ? 30 : 0, style: .continuous))
                .ignoresSafeArea(edges: wide ? [] : .all)

                VStack(spacing: 0) {
                    topControls
                    Spacer()
                    if let error {
                        Text(error).font(.jakarta(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Palette.danger, in: Capsule())
                    }
                    bottomControls
                }
                .frame(width: previewWidth)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            camera.onPhoto = { image in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { shots.append(image) }
            }
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .confirmationDialog("Start over?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Delete all clips", role: .destructive) { withAnimation { camera.restart() } }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: countdown)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: camera.recording)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: camera.clips.count)
    }

    // Clip progress (like TikTok / Discord): one segment per clip.
    private var progressBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 2) {
                ForEach(camera.clips) { clip in
                    Capsule().fill(Theme.gradient).frame(width: max(2, w * clip.seconds / camera.maxSeconds - 2))
                }
                if camera.recording {
                    Capsule().fill(Color.white).frame(width: max(2, w * camera.current / camera.maxSeconds))
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
            if mode == .video { progressBar.padding(.horizontal, 14) }
            HStack(spacing: 10) {
                roundButton("xmark") { camera.stop(); onClose() }
                Spacer()
                if mode == .video && !camera.clips.isEmpty && !camera.recording {
                    roundButton("arrow.counterclockwise") { confirmRestart = true }
                }
                roundButton(camera.flash ? "bolt.fill" : "bolt.slash.fill", active: camera.flash) { camera.flash.toggle() }
                Button {
                    timer = timer == 0 ? 3 : timer == 3 ? 10 : 0
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "timer").font(.system(size: 15, weight: .bold))
                        if timer > 0 { Text("\(timer)s").font(.jakarta(12, .heavy)) }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, timer > 0 ? 12 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(timer > 0 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.black.opacity(0.35)), in: Capsule())
                }
                .buttonStyle(BouncyStyle())
                roundButton("arrow.triangle.2.circlepath.camera.fill") { camera.flip() }
            }
            .padding(.horizontal, 14)
            if camera.zoom > 1.05 {
                Text(String(format: "%.1fx", camera.zoom)).font(.jakarta(12, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.4), in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
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
                // Left: delete the last clip (video) or nothing.
                Group {
                    if mode == .video && !camera.clips.isEmpty && !camera.recording {
                        roundButton("delete.backward.fill", size: 50) { withAnimation { camera.deleteLast() } }
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Color.clear.frame(width: 50, height: 50)
                    }
                }
                .frame(maxWidth: .infinity)

                recordButton

                // Right: done.
                Group {
                    let ready = mode == .video ? (!camera.clips.isEmpty && !camera.recording) : !shots.isEmpty
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
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Color.clear.frame(width: 54, height: 54)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 26) {
                ForEach([Mode.video, Mode.photo], id: \.self) { m in
                    Button { if !camera.recording { withAnimation(.snappy) { mode = m } } } label: {
                        VStack(spacing: 4) {
                            Text(m.rawValue).font(.jakarta(14, .heavy)).foregroundStyle(mode == m ? .white : .white.opacity(0.55))
                            Circle().fill(Theme.gradient).frame(width: 5, height: 5).opacity(mode == m ? 1 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
        }
        .padding(.bottom, 12)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var recordButton: some View {
        Button { Task { await shutter() } } label: {
            ZStack {
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 5).frame(width: 84, height: 84)
                if mode == .video {
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
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.recording)
        .disabled(countdown > 0 || merging)
    }

    private func roundButton(_ icon: String, size: CGFloat = 44, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle())
    }

    private func shutter() async {
        error = nil
        if mode == .video && camera.recording {
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
        if mode == .video {
            if camera.total >= camera.maxSeconds - 0.3 { error = "60 seconds max — tap ✓ to continue."; return }
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

    private func finish() async {
        if mode == .photo {
            camera.stop()
            onPhotos(shots)
            return
        }
        merging = true
        defer { merging = false }
        do {
            let url = try await camera.merge()
            camera.stop()
            onVideo(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
