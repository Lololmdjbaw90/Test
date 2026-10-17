import SwiftUI
import UIKit
import AVKit
import AVFoundation
import CoreMedia
import WebRTC

// The call in a small floating window when you leave Sugerly, like FaceTime:
// the other person's camera (or screen) keeps playing over your other apps,
// and tapping the window brings you back to the call. Your own camera keeps
// going in there where iOS allows it (iOS 18 and later); otherwise the
// others see your picture until you're back.
@MainActor
final class CallPiP: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = CallPiP()

    private var controller: AVPictureInPictureController?
    private let picture = CallPiPView()
    private let frames = PiPFrames()
    private let floating = AVPictureInPictureVideoCallViewController()
    // Where the window grows out of: the call screen, or the call bar while
    // the call is minimised (the newest one still on screen).
    private struct Anchor { weak var view: UIView? }
    private var anchors: [Anchor] = []
    private weak var source: UIView?
    private var track: RTCVideoTrack?
    private var name = ""
    private var backInApp: NSObjectProtocol?

    private override init() {
        super.init()
        floating.preferredContentSize = CGSize(width: 720, height: 1280)
        floating.view.backgroundColor = .black
        picture.frame = floating.view.bounds
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        floating.view.addSubview(picture)
        frames.deliver = { [weak self] sample, rotation in self?.picture.show(sample, rotation: rotation) }
        picture.onSize = { [weak self] size in self?.floating.preferredContentSize = size }
        // Back in Sugerly: the window goes back into the call.
        backInApp = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let controller = self?.controller, controller.isPictureInPictureActive else { return }
                controller.stopPictureInPicture()
            }
        }
    }

    func attach(_ view: UIView) {
        anchors.removeAll { $0.view == nil || $0.view === view }
        anchors.append(Anchor(view: view))
        update()
    }

    func detach(_ view: UIView) {
        anchors.removeAll { $0.view == nil || $0.view === view }
        update()
    }

    // Whose picture floats when you leave Sugerly (nil: nobody's showing one).
    func show(_ track: RTCVideoTrack?, name: String) {
        if name != self.name {
            self.name = name
            picture.name = name
        }
        guard track !== self.track else { return }
        if let old = self.track { VideoRelay.existing(for: old)?.detach(frames) }
        self.track = track
        if let track {
            VideoRelay.relay(for: track).attach(frames)
        } else {
            picture.clear()
        }
        update()
    }

    // The call is over: close the window.
    func end() {
        show(nil, name: "")
        frames.setFast(false)
        guard let controller else { return }
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
        self.controller = nil
        source = nil
    }

    private func update() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let onScreen = anchors.last { $0.view?.window != nil }?.view
        if let controller {
            if let onScreen, onScreen !== source {
                source = onScreen
                controller.contentSource = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: onScreen, contentViewController: floating)
            }
            controller.canStartPictureInPictureAutomaticallyFromInline = track != nil && onScreen != nil
        } else if track != nil, let onScreen {
            source = onScreen
            let made = AVPictureInPictureController(contentSource: AVPictureInPictureController.ContentSource(activeVideoCallSourceView: onScreen, contentViewController: floating))
            made.delegate = self
            made.canStartPictureInPictureAutomaticallyFromInline = true
            controller = made
        }
    }

    // MARK: AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.frames.setFast(true) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.frames.setFast(false) }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.frames.setFast(false) }
    }

    // Tapped the window: back to the call screen.
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            if VoiceEngine.shared.room?.isCall == true { CallCenter.shared.showScreen = true }
            completionHandler(true)
        }
    }
}

// Marks where the floating call window grows out of and shrinks back into.
struct CallPiPAnchor: UIViewRepresentable {
    final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { CallPiP.shared.attach(self) } else { CallPiP.shared.detach(self) }
        }
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {}
}

// What the floating window shows: the picture, turned the right way up, or
// their name while their camera is off.
final class CallPiPView: UIView {
    private let display = AVSampleBufferDisplayLayer()
    private let placeholder = UIStackView()
    private let nameLabel = UILabel()
    private var rotation = 0
    private var size = CGSize.zero
    private var hasPicture = false
    var onSize: ((CGSize) -> Void)?

    var name = "" {
        didSet { nameLabel.text = name }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.1, green: 0.05, blue: 0.08, alpha: 1)
        clipsToBounds = true
        display.videoGravity = .resizeAspectFill
        layer.addSublayer(display)
        let icon = UIImageView(image: UIImage(systemName: "video.slash.fill"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.7)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        nameLabel.font = .systemFont(ofSize: 17, weight: .heavy)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.6
        placeholder.axis = .vertical
        placeholder.alignment = .center
        placeholder.spacing = 8
        placeholder.addArrangedSubview(icon)
        placeholder.addArrangedSubview(nameLabel)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ sample: CMSampleBuffer, rotation: Int) {
        if display.status == .failed { display.flush() }
        guard display.isReadyForMoreMediaData else { return }
        display.enqueue(sample)
        if !hasPicture {
            hasPicture = true
            placeholder.isHidden = true
        }
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        let turned = rotation == 90 || rotation == 270
        let shown = CGSize(width: CGFloat(turned ? dims.height : dims.width), height: CGFloat(turned ? dims.width : dims.height))
        guard rotation != self.rotation || shown != size, shown.width > 0, shown.height > 0 else { return }
        self.rotation = rotation
        size = shown
        setNeedsLayout()
        onSize?(shown)
    }

    // Their camera went off: their name instead of a frozen picture.
    func clear() {
        display.flushAndRemoveImage()
        hasPicture = false
        placeholder.isHidden = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let turned = rotation == 90 || rotation == 270
        display.setAffineTransform(.identity)
        display.bounds = CGRect(x: 0, y: 0, width: turned ? bounds.height : bounds.width, height: turned ? bounds.width : bounds.height)
        display.position = CGPoint(x: bounds.midX, y: bounds.midY)
        display.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(rotation) * .pi / 180))
        CATransaction.commit()
    }
}

// Turns a call's frames into ones the floating window can show. Until the
// window opens it only keeps a fresh one now and then (a couple a second),
// so it costs next to nothing while you're in the app.
final class PiPFrames: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var fast = false
    private var last = 0.0
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    // Called on the main thread with each frame and how far to turn it.
    var deliver: ((CMSampleBuffer, Int) -> Void)?

    func setFast(_ value: Bool) {
        lock.lock()
        fast = value
        lock.unlock()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        lock.lock()
        defer { lock.unlock() }
        let now = CACurrentMediaTime()
        guard fast || now - last >= 0.5 else { return }
        last = now
        guard let pixels = pixelBuffer(frame.buffer), let sample = Self.sample(pixels) else { return }
        let rotation = Int(frame.rotation.rawValue)
        DispatchQueue.main.async { [weak self] in self?.deliver?(sample, rotation) }
    }

    // Phones send ready-made pictures; browsers often send I420, which the
    // window can't show, so it's repacked as NV12.
    private func pixelBuffer(_ buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        if let native = buffer as? RTCCVPixelBuffer { return native.pixelBuffer }
        let i420 = buffer.toI420()
        let width = Int(i420.width), height = Int(i420.height)
        guard width > 0, height > 0 else { return nil }
        if pool == nil || poolSize.width != width || poolSize.height != height {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            ]
            var made: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &made)
            pool = made
            poolSize = (width, height)
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess, let pixels = out else { return nil }
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixels, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixels, 1) else { return nil }
        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 1)
        let srcY = i420.dataY, srcU = i420.dataU, srcV = i420.dataV
        let strideY = Int(i420.strideY), strideU = Int(i420.strideU), strideV = Int(i420.strideV)
        for row in 0..<height {
            memcpy(luma + row * lumaStride, srcY + row * strideY, width)
        }
        let chromaWidth = Int(i420.chromaWidth), chromaHeight = Int(i420.chromaHeight)
        for row in 0..<chromaHeight {
            let line = chroma + row * chromaStride
            let u = srcU + row * strideU, v = srcV + row * strideV
            for column in 0..<chromaWidth {
                line[column * 2] = u[column]
                line[column * 2 + 1] = v[column]
            }
        }
        return pixels
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
        // Show each frame as soon as it arrives (there's no clock to follow).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
