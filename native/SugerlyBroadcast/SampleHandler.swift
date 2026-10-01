import CoreImage
import Foundation
import Network
import ReplayKit

// Sugerly's screen broadcast. While you share your screen in a call, iOS
// runs this little extension and hands it every frame of the whole phone
// screen (other apps and the home screen too). At most fifteen times a second it
// sends the newest frame as a small JPEG to Sugerly over a private link
// inside the phone (127.0.0.1), and Sugerly sends it into the call
// (ScreenBroadcast.swift). Sugerly only listens during a call, so there's
// nothing to connect to otherwise.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let port: NWEndpoint.Port = 47_318
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "sugerly.broadcast.link")
    private let lock = NSLock()
    private var connection: NWConnection?
    private var lastFrame: CFAbsoluteTime = 0
    // The admission gate is shared with ReplayKit's sample callbacks. Reserve
    // one frame BEFORE encoding so a slow socket cannot queue JPEGs/buffers.
    private var ready = false
    private var sending = false
    private var finished = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let link = NWConnection(host: "127.0.0.1", port: Self.port, using: .tcp)
        connection = link
        link.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.lock()
                self.ready = true
                self.lock.unlock()
                self.watchForEnd(link)
            case .waiting, .failed:
                self.stop("Start a Sugerly call first, then share your screen.")
            default:
                break
            }
        }
        link.start(queue: queue)
    }

    override func broadcastFinished() {
        lock.lock()
        finished = true
        ready = false
        lock.unlock()
        queue.async { [self] in
            connection?.cancel()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        guard ready, !finished, !sending, now - lastFrame >= 1.0 / 15 else { lock.unlock(); return }
        sending = true
        lastFrame = now
        lock.unlock()
        queue.async { [self] in
            autoreleasepool { sendFrame(sampleBuffer) }
        }
    }

    private func releaseFrame() {
        lock.lock()
        sending = false
        lock.unlock()
    }

    // Runs away from ReplayKit's callback; only one retained sample at a time.
    private func sendFrame(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let active = ready && !finished
        lock.unlock()
        guard active, let connection, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { releaseFrame(); return }
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
        else { releaseFrame(); return }
        var length = UInt32(jpeg.count).bigEndian
        let packet = Data(bytes: &length, count: 4) + jpeg
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.releaseFrame()
            if error != nil { self.stop("Sugerly stopped receiving your screen.") }
        })
    }

    // Sugerly closes the link when you press Stop there or the call ends.
    private func watchForEnd(_ link: NWConnection) {
        link.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.stop("You stopped sharing your screen in Sugerly.")
            } else {
                self.watchForEnd(link)
            }
        }
    }

    private func stop(_ message: String) {
        queue.async { [self] in
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            ready = false
            lock.unlock()
            connection?.cancel()
            finishBroadcastWithError(NSError(domain: "Sugerly", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}
