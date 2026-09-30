import CoreImage
import Foundation
import ReplayKit

// Sugerly's screen broadcast. While you share your screen in a call, iOS
// runs this little extension and hands it every frame of the whole phone
// screen (other apps and the home screen too). About ten times a second it
// saves the newest frame as a small JPEG in the shared app-group folder and
// signals Sugerly, which sends it into the call (ScreenBroadcast.swift).
final class SampleHandler: RPBroadcastSampleHandler {
    private static let group = "group.com.mimilocks.app"
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastFrame: CFAbsoluteTime = 0
    private lazy var file: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: Self.group)?
        .appendingPathComponent("broadcast-frame.jpg")

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard UserDefaults(suiteName: Self.group)?.bool(forKey: "sugerly.broadcast.inCall") == true else {
            stop("Start a Sugerly call first, then share your screen.")
            return
        }
        // "Stop" pressed inside Sugerly.
        DispatchQueue.main.async {
            BroadcastSignal.observe(BroadcastSignal.stop) { [weak self] in
                self?.stop("You stopped sharing your screen in Sugerly.")
            }
        }
        BroadcastSignal.post(BroadcastSignal.started)
    }

    override func broadcastFinished() {
        BroadcastSignal.post(BroadcastSignal.stopped)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame >= 0.09, let file, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        var image = CIImage(cvPixelBuffer: pixels)
        // Turned the right way up when the phone is sideways.
        if let raw = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value), orientation != .up {
            image = image.oriented(orientation)
        }
        // Small enough to stay quick and within the extension's memory.
        let longest = max(image.extent.width, image.extent.height)
        if longest > 1280 {
            let scale = 1280 / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(of: image, colorSpace: space,
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.55])
        else { return }
        // Written whole, then swapped in, so Sugerly never reads half a picture.
        guard (try? jpeg.write(to: file, options: .atomic)) != nil else { return }
        BroadcastSignal.post(BroadcastSignal.frame)
    }

    private func stop(_ message: String) {
        finishBroadcastWithError(NSError(domain: "Sugerly", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
    }
}

// System-wide signals between this extension and the app (Darwin notifications).
enum BroadcastSignal {
    static let started = "com.mimilocks.app.broadcast.started"
    static let frame = "com.mimilocks.app.broadcast.frame"
    static let stopped = "com.mimilocks.app.broadcast.stopped"
    static let stop = "com.mimilocks.app.broadcast.stop"

    private final class Box {}
    private static let box = Box()
    private static var handlers: [String: () -> Void] = [:]

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
