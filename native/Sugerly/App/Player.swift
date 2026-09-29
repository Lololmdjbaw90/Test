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

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusWatch: NSKeyValueObservation?
    @ObservationIgnored private var itemWatch: NSKeyValueObservation?
    @ObservationIgnored private var interruptions: NSObjectProtocol?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var refreshed: Set<String> = []

    func isCurrent(_ t: Track) -> Bool { track?.id == t.id }
    func isPlaying(_ t: Track) -> Bool { isCurrent(t) && playing }

    func play(_ t: Track, in list: [Track]) {
        queue = list
        if isCurrent(t), player != nil { toggle(); return }
        start(t)
    }

    private func activateSession() {
        // During a call the song plays through the call's audio as it is.
        if VoiceEngine.live { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func start(_ t: Track) {
        guard let url = URL(string: t.audioURL), !t.audioURL.isEmpty else { return }
        AppleMusic.shared.stop()
        activateSession()
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
        // The button always shows what's really happening (iOS can pause us
        // for a call, another app or a video with sound).
        statusWatch = p.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.playing = status != .paused }
        }
        // Chart previews are links that expire: fetch a fresh one and retry.
        itemWatch = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in await self?.recover(t) }
        }
        watchInterruptions()
        p.play()
        playing = true
        updateNowPlaying()
        setupRemote()
    }

    private func recover(_ t: Track) async {
        guard isCurrent(t), t.id.hasPrefix("deezer_"), !refreshed.contains(t.id) else { pause(); return }
        refreshed.insert(t.id)
        let id = t.id.replacingOccurrences(of: "deezer_", with: "")
        guard let json = try? await HTTP.json(URL(string: "https://api.deezer.com/track/\(id)")!) as? [String: Any],
              let preview = json["preview"] as? String, !preview.isEmpty else { pause(); return }
        var fresh = t
        fresh.audioURL = preview
        if let i = queue.firstIndex(where: { $0.id == t.id }) { queue[i] = fresh }
        start(fresh)
    }

    private func watchInterruptions() {
        guard interruptions == nil else { return }
        interruptions = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began {
                    self.resumeAfterInterruption = self.playing
                    self.playing = false
                } else if type == .ended, options.contains(.shouldResume), self.resumeAfterInterruption {
                    self.resumeAfterInterruption = false
                    self.resume()
                }
            }
        }
    }

    // Plays from where it is, or from the start if the song had finished.
    private func resume() {
        guard let player else { return }
        activateSession()
        AppleMusic.shared.stop()
        let at = player.currentTime().seconds
        let total = player.currentItem?.duration.seconds ?? duration
        if total.isFinite, total > 0, at.isFinite, at >= total - 0.3 {
            player.seek(to: .zero)
            time = 0
        }
        player.play()
        playing = true
        updateNowPlaying()
    }

    func toggle() {
        guard player != nil else {
            if let track { start(track) }
            return
        }
        if playing { pause() } else { resume() }
    }

    func next() {
        guard let t = track, let i = queue.firstIndex(where: { $0.id == t.id }) else { finish(); return }
        let rest = queue[(i + 1)...].filter { !$0.audioURL.isEmpty }
        if let n = rest.first { start(n) } else { finish() }
    }

    // End of the list: stop at the start of the song, ready to play again.
    private func finish() {
        pause()
        player?.seek(to: .zero)
        time = 0
    }

    func previous() {
        guard let t = track else { return }
        let i = queue.firstIndex(where: { $0.id == t.id })
        if time > 3 || i == nil || i == 0 {
            seek(0)
            if !playing { resume() }
            return
        }
        start(queue[i! - 1])
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
        statusWatch?.invalidate()
        itemWatch?.invalidate()
        statusWatch = nil
        itemWatch = nil
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

    @ObservationIgnored private var remoteReady = false
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
