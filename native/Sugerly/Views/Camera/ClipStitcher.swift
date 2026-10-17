import Foundation
import AVFoundation
import UIKit

// Joins the clips you filmed into one video.
// - One clip at normal speed already is the video (instant).
// - Clips filmed the same way at normal speed are copied into one file
//   without being re-encoded (a second or two).
// - Otherwise (front and back camera mixed, or slow / fast clips) every clip
//   is drawn upright into one 1080×1920 video, so none of them comes out
//   sideways or mirrored the wrong way.
enum ClipStitcher {
    struct Piece: Sendable {
        let url: URL
        let speed: Double
    }

    // How a clip's picture is stored (clips that match can be copied as is).
    private struct Shape: Equatable {
        let size: CGSize
        let transform: CGAffineTransform
    }

    static func join(_ pieces: [Piece], progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let first = pieces.first else { throw APIError(message: "Film something first.") }
        if pieces.count == 1, abs(first.speed - 1) < 0.01 {
            progress(1)
            return first.url
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw APIError(message: "Couldn't put the clips together.")
        }
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let render = CGSize(width: 1080, height: 1920)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        var shapes: [Shape] = []
        var cursor = CMTime.zero
        for piece in pieces {
            let asset = AVURLAsset(url: piece.url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = try await track.load(.timeRange)
            guard range.duration.seconds > 0.05 else { continue }
            try video.insertTimeRange(range, of: track, at: cursor)
            var hasSound = false
            let sounds = try await asset.loadTracks(withMediaType: .audio)
            if let audio, let sound = sounds.first {
                let soundRange = try await sound.load(.timeRange)
                let shared = CMTimeRangeGetIntersection(range, otherRange: soundRange)
                if shared.duration.seconds > 0 {
                    let at = CMTimeAdd(cursor, CMTimeSubtract(shared.start, range.start))
                    hasSound = (try? audio.insertTimeRange(shared, of: sound, at: at)) != nil
                }
            }
            // Speed: 2× makes the clip half as long, 0.5× twice as long.
            var length = range.duration
            if abs(piece.speed - 1) > 0.01 {
                length = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / piece.speed)
                let placed = CMTimeRange(start: cursor, duration: range.duration)
                video.scaleTimeRange(placed, toDuration: length)
                if hasSound { audio?.scaleTimeRange(placed, toDuration: length) }
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            layer.setTransform(upright(natural, transform, filling: render), at: cursor)
            shapes.append(Shape(size: natural, transform: transform))
            cursor = CMTimeAdd(cursor, length)
        }
        guard cursor.seconds > 0.1, let firstShape = shapes.first else {
            throw APIError(message: "Couldn't put the clips together.")
        }
        let plain = pieces.allSatisfy { abs($0.speed - 1) < 0.01 } && shapes.allSatisfy { $0 == firstShape }
        if plain { video.preferredTransform = firstShape.transform }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("reel-\(UUID().uuidString).\(plain ? "mov" : "mp4")")
        guard let export = AVAssetExportSession(asset: composition, presetName: plain ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality) else {
            throw APIError(message: "Couldn't put the clips together.")
        }
        export.outputURL = out
        export.outputFileType = plain ? .mov : .mp4
        if !plain {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
            instruction.layerInstructions = [layer]
            let drawing = AVMutableVideoComposition()
            drawing.renderSize = render
            drawing.frameDuration = CMTime(value: 1, timescale: 30)
            drawing.instructions = [instruction]
            export.videoComposition = drawing
        }
        let watcher = Task {
            while !Task.isCancelled {
                progress(Double(export.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { done.resume() }
        }
        watcher.cancel()
        guard export.status == .completed else {
            throw APIError(message: export.error?.localizedDescription ?? "Couldn't put the clips together.")
        }
        progress(1)
        return out
    }

    // Turns a clip's stored picture (whatever way round it was filmed) into
    // an upright one filling the frame, cut evenly at the edges if needed.
    private static func upright(_ natural: CGSize, _ transform: CGAffineTransform, filling frame: CGSize) -> CGAffineTransform {
        let placed = CGRect(origin: .zero, size: natural).applying(transform)
        let shown = CGSize(width: abs(placed.width), height: abs(placed.height))
        guard shown.width > 0, shown.height > 0 else { return transform }
        let k = max(frame.width / shown.width, frame.height / shown.height)
        return transform
            .concatenating(CGAffineTransform(translationX: -placed.minX, y: -placed.minY))
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(translationX: (frame.width - shown.width * k) / 2, y: (frame.height - shown.height * k) / 2))
    }
}
