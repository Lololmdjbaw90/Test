#if DEBUG
import SwiftUI
import AVFoundation
import CoreImage

struct EditorLoopUITestHost: View {
    @State private var doc = EditorModel()
    @State private var status = "Loading editor"
    @State private var exporting = false
    var body: some View {
        VStack {
            Text(status).accessibilityIdentifier("editor-export-result")
            Text(Self.fullFrameFits ? "Whole frame visible" : "Framing failed").accessibilityIdentifier("editor-framing-result")
            Button("Import again") {
                Task {
                    if let url = Bundle.main.url(forResource: "LandscapeFixture", withExtension: "mp4"), await doc.openVideo(url) { status = "Imported again" }
                }
            }
            Text(doc.player.completedLoops >= 2 && doc.player.playing ? "looping" : "waiting")
                .accessibilityIdentifier("editor-loop-state")
            Text("\(doc.player.completedLoops)").accessibilityIdentifier("editor-loop-count")
            MediaEditor(doc: doc, primaryTitle: "Export portrait", onBack: {}, onPrimary: { Task { await export() } })
        }
        .task {
            guard let url = Bundle.main.url(forResource: "LandscapeFixture", withExtension: "mp4"), await doc.openVideo(url) else { status = "Cannot open fixture"; return }
            status = "Landscape ready"
        }
        .onDisappear { doc.player.teardown() }
    }
    private static let fullFrameFits: Bool = {
        let size = CGSize(width: 108, height: 192)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let framed = VideoCrop.fit(source, size)
        var pixels = [UInt8](repeating: 0, count: 108 * 192 * 4)
        pixels.withUnsafeMutableBytes { buffer in
            CIContext().render(framed, toBitmap: buffer.baseAddress!, rowBytes: 108 * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        return pixels[(96 * 108 + 54) * 4] > 200 && pixels[(2 * 108 + 54) * 4] < 20
    }()

    private func export() async {
        guard !exporting else { return }
        exporting = true
        doc.player.pause()
        do {
            let out = try await doc.exportVideo()
            let asset = AVURLAsset(url: out)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { status = "No output video"; return }
            let size = try await track.load(.naturalSize)
            status = Int(size.width) == 1080 && Int(size.height) == 1920 ? "1080x1920 passed" : "Wrong output size"
            try? FileManager.default.removeItem(at: out)
        } catch { status = error.localizedDescription }
        exporting = false
    }
}
#endif
