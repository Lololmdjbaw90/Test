import CoreVideo
import Foundation
import ImageIO
import Network
import QuartzCore
import ReplayKit
import UIKit
import WebRTC

// The app's half of sharing your whole screen in a call. The other half is
// the SugerlyBroadcast extension, which iOS runs while you broadcast: it
// sends the newest frame of the phone screen to a private link inside the
// phone (127.0.0.1) that Sugerly opens only during a call. Each frame goes
// into the call like a camera picture, so it keeps working while you use
// other apps (the call keeps Sugerly awake).
@MainActor
final class ScreenBroadcast {
    static let shared = ScreenBroadcast()
    static let extensionId = "com.mimilocks.app.broadcast"

    let frames = BroadcastFrames()
    private lazy var link = BroadcastLink(
        started: { Task { @MainActor in ScreenBroadcast.shared.onStarted?() } },
        stopped: { Task { @MainActor in ScreenBroadcast.shared.onStopped?() } },
        frame: { [frames] data in frames.show(data) })
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?

    // In a call: the extension can connect.
    func open() { link.open() }
    // Call over: nothing to connect to (a running broadcast ends).
    func close() { link.close() }
    // Stop pressed in Sugerly: the broadcast ends.
    func requestStop() { link.dropBroadcast() }

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

// The private link: listens on 127.0.0.1 only, takes one broadcast at a
// time and splits the stream into frames (4-byte length, then a JPEG).
final class BroadcastLink: @unchecked Sendable {
    static let port: NWEndpoint.Port = 47_318
    private let queue = DispatchQueue(label: "sugerly.broadcast.link")
    private let started: () -> Void
    private let stopped: () -> Void
    private let frame: (Data) -> Void
    // Only touched on `queue`.
    private var listener: NWListener?
    private var connection: NWConnection?
    private var buffer = Data()

    init(started: @escaping () -> Void, stopped: @escaping () -> Void, frame: @escaping (Data) -> Void) {
        self.started = started
        self.stopped = stopped
        self.frame = frame
    }

    func open() {
        queue.async { [self] in
            guard listener == nil else { return }
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            guard let made = try? NWListener(using: parameters, on: Self.port) else { return }
            made.newConnectionHandler = { [weak self] link in self?.accept(link) }
            made.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .failed = state {
                    self.dropLocked()
                    self.listener?.cancel()
                    self.listener = nil
                }
            }
            made.start(queue: queue)
            listener = made
        }
    }

    func close() {
        queue.async { [self] in
            dropLocked()
            listener?.cancel()
            listener = nil
        }
    }

    func dropBroadcast() {
        queue.async { [self] in dropLocked() }
    }

    private func dropLocked() {
        guard let connection else { return }
        self.connection = nil
        buffer = Data()
        connection.cancel()
        stopped()
    }

    private func accept(_ link: NWConnection) {
        connection?.cancel()
        connection = link
        buffer = Data()
        link.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link else { return }
            switch state {
            case .ready:
                self.started()
            case .failed, .cancelled:
                if self.connection === link {
                    self.connection = nil
                    self.buffer = Data()
                    self.stopped()
                }
            default:
                break
            }
        }
        link.start(queue: queue)
        receive(link)
    }

    private func receive(_ link: NWConnection) {
        link.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === link else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            guard self.connection === link else { return }
            if isComplete || error != nil {
                link.cancel()
            } else {
                self.receive(link)
            }
        }
    }

    // Whole frames out of the stream; only the newest is shown.
    private func drain() {
        var newest: Data?
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length < 8_000_000 else {
                // A malformed stream must close; clearing and continuing
                // loses packet boundaries and can grow a buffer forever.
                dropLocked()
                return
            }
            guard buffer.count >= 4 + length else { break }
            newest = buffer.subdata(in: start + 4..<start + 4 + length)
            buffer.removeSubrange(start..<start + 4 + length)
        }
        if let newest { frame(newest) }
    }
}

// Turns each frame into a video picture and hands it to the call. Frames
// that arrive while one is still being turned are skipped.
final class BroadcastFrames: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sugerly.broadcast.frames", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var target: (source: RTCVideoSource, capturer: RTCVideoCapturer)?

    func attach(_ source: RTCVideoSource?, _ capturer: RTCVideoCapturer?) {
        lock.lock()
        if let source, let capturer { target = (source, capturer) } else { target = nil }
        lock.unlock()
    }

    func show(_ jpeg: Data) {
        lock.lock()
        guard !busy, target != nil else { lock.unlock(); return }
        busy = true
        lock.unlock()
        queue.async { [self] in
            defer {
                lock.lock()
                busy = false
                lock.unlock()
            }
            lock.lock()
            let target = target
            lock.unlock()
            guard let target, let pixels = Self.pixelBuffer(jpeg) else { return }
            let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels), rotation: ._0,
                                      timeStampNs: Int64(CACurrentMediaTime() * 1_000_000_000))
            target.source.capturer(target.capturer, didCapture: frame)
        }
    }

    private static func pixelBuffer(_ jpeg: Data) -> CVPixelBuffer? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
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
