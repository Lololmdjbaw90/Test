#if DEBUG
import SwiftUI
import AVFoundation

struct ReelPlaybackUITestHost: View {
    @State private var player = Player()
    @State private var path: [Route] = []
    @State private var tab = 1
    @State private var fixtures: [Reel] = []
    @State private var videos: [ReelVideo] = []
    @State private var problem = ""

    var body: some View {
        TabView(selection: $tab) {
            SplashView().tabItem { Label("Home", systemImage: "house") }.tag(0)
            Group {
                if fixtures.isEmpty { Text(problem.isEmpty ? "Preparing clip" : problem) }
                else { ReelsView(visible: tab == 1, path: $path, create: {}, initialReels: fixtures) }
            }.tabItem { Label("Reels", systemImage: "play.rectangle") }.tag(1)
        }
        .compactTabBar()
        .environment(\.horizontalSizeClass, .compact)
        .environment(player)
        .overlay(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack {
                    ForEach(Array(videos.enumerated()), id: \.offset) { i, video in
                        Text(video.failed ? "failed" : video.ready && video.player.rate > 0 && video.player.currentTime().seconds > 0.4 ? "playing" : "paused")
                            .accessibilityIdentifier("clip-\(i)-state")
                    }
                }.font(.system(size: 10)).foregroundStyle(.white).padding(4).background(.black)
            }
        }
        .task {
            do {
                let url = try await Task.detached { try await Self.makeClip() }.value
                fixtures = (0..<2).map { Reel(["id": "playback-\($0)", "kind": "video", "media_url": url.absoluteString, "caption": "Playback test \($0)", "user_display_name": "Sugerly", "comments_off": true, "edits": ["trim_start": $0 == 0 ? 0.0 : 0.5]]) }
                videos = fixtures.map { ReelVideo.get($0.id, url: url, start: $0.trimStart) }
            } catch { problem = error.localizedDescription }
        }
    }

    nonisolated private static func makeClip() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 180, AVVideoHeightKey: 320])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 180, kCVPixelBufferHeightKey as String: 320])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? APIError(message: "Cannot create fixture") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 180, 320, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard let buffer else { throw APIError(message: "Cannot create pixels") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<320 { for x in 0..<180 {
                let at = y * stride + x * 4
                bytes[at] = 255; bytes[at + 1] = UInt8(frame * 4); bytes[at + 2] = UInt8(y % 255); bytes[at + 3] = 160
            } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 20)) else { throw writer.error ?? APIError(message: "Cannot append pixels") }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? APIError(message: "Cannot finish clip") }
        return url
    }
}
#endif
