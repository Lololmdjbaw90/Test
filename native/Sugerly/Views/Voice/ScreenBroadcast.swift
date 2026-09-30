import CoreVideo
import Foundation
import ImageIO
import QuartzCore
import ReplayKit
import UIKit
import WebRTC

// The app's half of sharing your whole screen in a call. The other half is
// the SugerlyBroadcast extension, which iOS runs while you broadcast: it
// saves the newest frame of the phone screen in the shared app-group folder
// and signals here. Each frame goes into the call like a camera picture, so
// it keeps working while you use other apps (the call keeps Sugerly awake).
@MainActor
final class ScreenBroadcast {
    static let shared = ScreenBroadcast()
    static let group = "group.com.mimilocks.app"
    static let extensionId = "com.mimilocks.app.broadcast"

    let frames = BroadcastFrames()
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    private var listening = false

    func listen() {
        guard !listening else { return }
        listening = true
        BroadcastSignal.observe(BroadcastSignal.started) { Task { @MainActor in ScreenBroadcast.shared.onStarted?() } }
        BroadcastSignal.observe(BroadcastSignal.stopped) { Task { @MainActor in ScreenBroadcast.shared.onStopped?() } }
        let frames = frames
        BroadcastSignal.observe(BroadcastSignal.frame) { frames.newFrame() }
    }

    // The extension only broadcasts while you're in a call.
    func setInCall(_ on: Bool) {
        UserDefaults(suiteName: Self.group)?.set(on, forKey: "sugerly.broadcast.inCall")
    }

    func requestStop() {
        BroadcastSignal.post(BroadcastSignal.stop)
    }

    // iPhone's own "Start Broadcast" sheet, set to Sugerly.
    func showPicker() {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = Self.extensionId
        picker.showsMicrophoneButton = false
        picker.alpha = 0.01
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        window?.addSubview(picker)
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .touchUpInside)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { picker.removeFromSuperview() }
    }
}

// Reads each new frame off the main thread and hands it to the call.
// Frames that arrive while one is still being read are skipped.
final class BroadcastFrames: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sugerly.broadcast.frames", qos: .userInitiated)
    private let lock = NSLock()
    private var scheduled = false
    private var target: (source: RTCVideoSource, capturer: RTCVideoCapturer)?
    private let file = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: ScreenBroadcast.group)?
        .appendingPathComponent("broadcast-frame.jpg")

    func attach(_ source: RTCVideoSource?, _ capturer: RTCVideoCapturer?) {
        lock.lock()
        if let source, let capturer { target = (source, capturer) } else { target = nil }
        lock.unlock()
    }

    func newFrame() {
        lock.lock()
        guard !scheduled, target != nil else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            scheduled = false
            let target = target
            lock.unlock()
            guard let target, let file, let pixels = Self.pixelBuffer(file) else { return }
            let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels), rotation: ._0,
                                      timeStampNs: Int64(CACurrentMediaTime() * 1_000_000_000))
            target.source.capturer(target.capturer, didCapture: frame)
        }
    }

    private static func pixelBuffer(_ url: URL) -> CVPixelBuffer? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        // Even sizes, which video encoders need.
        let width = image.width & ~1, height = image.height & ~1
        guard width > 0, height > 0 else { return nil }
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var made: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &made) == kCVReturnSuccess,
              let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

// System-wide signals between the app and the broadcast extension (Darwin
// notifications; the extension has the same list).
enum BroadcastSignal {
    static let started = "com.mimilocks.app.broadcast.started"
    static let frame = "com.mimilocks.app.broadcast.frame"
    static let stopped = "com.mimilocks.app.broadcast.stopped"
    static let stop = "com.mimilocks.app.broadcast.stop"

    private final class Box {}
    private static let box = Box()
    nonisolated(unsafe) private static var handlers: [String: () -> Void] = [:]

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    static func observe(_ name: String, _ handler: @escaping () -> Void) {
        handlers[name] = handler
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(box).toOpaque(), { _, _, signal, _, _ in
            guard let signal else { return }
            let key = signal.rawValue as String
            BroadcastSignal.handlers[key]?()
        }, name as CFString, nil, .deliverImmediately)
    }
}
