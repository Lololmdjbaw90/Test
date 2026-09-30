import CoreImage
import Foundation
import Network
import ReplayKit

// Sugerly's screen broadcast. While you share your screen in a call, iOS
// runs this little extension and hands it every frame of the whole phone
// screen (other apps and the home screen too). About ten times a second it
// sends the newest frame as a small JPEG to Sugerly over a private link
// inside the phone (127.0.0.1), and Sugerly sends it into the call
// (ScreenBroadcast.swift). Sugerly only listens during a call, so there's
// nothing to connect to otherwise.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let port: NWEndpoint.Port = 47_318
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "sugerly.broadcast.link")
    private var connection: NWConnection?
    private var lastFrame: CFAbsoluteTime = 0
    // Only touched on `queue`.
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
                self.ready = true
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
        queue.async { [self] in
            finished = true
            connection?.cancel()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame >= 0.09, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
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
        queue.async { [self] in
            // One frame on its way at a time; newer ones replace waiting ones.
            guard ready, !sending, let connection else { return }
            sending = true
            var length = UInt32(jpeg.count).bigEndian
            let packet = Data(bytes: &length, count: 4) + jpeg
            connection.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.sending = false
                if error != nil { self.stop("Sugerly stopped receiving your screen.") }
            })
        }
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
            guard !finished else { return }
            finished = true
            connection?.cancel()
            finishBroadcastWithError(NSError(domain: "Sugerly", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}
