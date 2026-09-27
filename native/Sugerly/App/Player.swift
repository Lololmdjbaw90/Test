import SwiftUI
import AVFoundation
import MediaPlayer

// One music player for the whole app (Music tab, Home, profiles). Keeps
// playing while you browse, shows on the Lock Screen, and moves through the
// list you started from.
@MainActor
@Observable
final class Player {
    var track: Track?
    var queue: [Track] = []
    var playing = false
    var time: Double = 0
    var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func isCurrent(_ t: Track) -> Bool { track?.id == t.id }
    func isPlaying(_ t: Track) -> Bool { isCurrent(t) && playing }

    func play(_ t: Track, in list: [Track]) {
        if isCurrent(t) { toggle(); return }
        queue = list
        start(t)
    }

    private func start(_ t: Track) {
        guard let url = URL(string: t.audioURL), !t.audioURL.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        teardown()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        track = t
        time = 0
        duration = 0
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] now in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = now.seconds.isFinite ? now.seconds : 0
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        p.play()
        playing = true
        updateNowPlaying()
        setupRemote()
    }

    func toggle() {
        guard let player else { return }
        if playing { player.pause() } else { player.play() }
        playing.toggle()
        updateNowPlaying()
    }

    func next() {
        guard let t = track, let i = queue.firstIndex(where: { $0.id == t.id }) else { pause(); return }
        let rest = queue[(i + 1)...].filter { !$0.audioURL.isEmpty }
        if let n = rest.first { start(n) } else { pause(); player?.seek(to: .zero) }
    }

    func previous() {
        guard let t = track, let i = queue.firstIndex(where: { $0.id == t.id }) else { return }
        if time > 3 || i == 0 { seek(0); return }
        start(queue[i - 1])
    }

    func seek(_ seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        time = seconds
    }

    func pause() {
        player?.pause()
        playing = false
        updateNowPlaying()
    }

    func close() {
        teardown()
        track = nil
        playing = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func teardown() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
    }

    private func updateNowPlaying() {
        guard let track else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
    }

    private var remoteReady = false
    private func setupRemote() {
        guard !remoteReady else { return }
        remoteReady = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { if self?.playing == false { self?.toggle() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { if self?.playing == true { self?.toggle() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
    }
}

// The floating "now playing" card above the tab bar.
struct MiniPlayer: View {
    @Environment(Player.self) private var player
    @State private var spin = false

    var body: some View {
        if let track = player.track {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    RemoteImage(url: track.coverURL)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(player.playing ? .linear(duration: 8).repeatForever(autoreverses: false) : .default, value: spin)
                        .onAppear { spin = true }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(track.artist).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.gradient, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill").frame(width: 34, height: 40) }
                        .foregroundStyle(Palette.text2)
                    Button { withAnimation(.snappy) { player.close() } } label: { Image(systemName: "xmark").frame(width: 30, height: 40) }
                        .foregroundStyle(Palette.muted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.border)
                        Capsule().fill(Theme.gradient).frame(width: player.duration > 0 ? geo.size.width * min(1, player.time / player.duration) : 0)
                    }
                }
                .frame(height: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassPill(cornerRadius: 26)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sensoryFeedback(.impact(weight: .light), trigger: player.playing)
        }
    }
}
