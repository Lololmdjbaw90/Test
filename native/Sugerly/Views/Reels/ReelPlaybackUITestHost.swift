#if DEBUG
import SwiftUI
import AVFoundation

struct ReelPlaybackUITestHost: View {
    @State private var player = Player()
    @State private var chats = ChatStore()
    @State private var path: [Route] = []
    @State private var tab = 1
    @State private var fixtures: [Reel] = []
    @State private var videos: [ReelVideo] = []
    @State private var problem = ""
    @State private var single = false

    var body: some View {
        TabView(selection: $tab) {
            VStack {
                SplashView()
                Button("Start test music") {
                    if let url = Bundle.main.url(forResource: "MusicFixture", withExtension: "m4a") {
                        let track = Track(["id": "music-fixture", "title": "Music test", "music_url": url.absoluteString])
                        player.play(track, in: [track])
                    }
                }.padding()
            }
            .safeAreaInset(edge: .bottom) { MiniPlayer() }
            .tabItem { Label("Home", systemImage: "house") }.tag(0)
            Group {
                if fixtures.isEmpty { Text(problem.isEmpty ? "Preparing clip" : problem) }
                else { ReelsView(visible: tab == 1 && !single, path: $path, create: {}, initialReels: fixtures) }
            }.tabItem { Label("Reels", systemImage: "play.rectangle") }.tag(1)
        }
        .compactTabBar(enabled: tab != 1)
        .environment(\.horizontalSizeClass, .compact)
        .environment(player)
        .environment(chats)
        .overlay(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack {
                    Text(player.widgetHidden ? "hidden" : player.playing ? "playing" : "paused").accessibilityIdentifier("music-state")
                    ForEach(Array(videos.enumerated()), id: \.offset) { i, video in
                        Text(video.failed ? "failed" : video.ready && video.player.rate > 0 && video.player.currentTime().seconds > 0.4 ? "playing" : "paused")
                            .accessibilityIdentifier("clip-\(i)-state")
                        Text("\(video.completedLoops)").accessibilityIdentifier("clip-\(i)-loops")
                        Text("\(video.restarts)").accessibilityIdentifier("clip-\(i)-restarts")
                    }
                }.font(.system(size: 10)).foregroundStyle(.white).padding(4).background(.black)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !fixtures.isEmpty { Button("Open single reel") { single = true }.padding(6).background(.white) }
        }
        .fullScreenCover(isPresented: $single) {
            if let reel = fixtures.first { SingleReelView(reel: reel, path: $path, loadContent: false).environment(player) }
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
        guard let url = Bundle.main.url(forResource: "PlaybackFixture", withExtension: "mp4") else {
            throw APIError(message: "The playback fixture is missing")
        }
        return url
    }
}
#endif
