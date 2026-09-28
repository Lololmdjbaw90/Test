import Foundation
import MusicKit
import Observation

// Apple Music (MusicKit): connect your account and, with a subscription,
// play whole songs inside Sugerly instead of 30-second previews.
//
// One-time setup outside the app: turn on the MusicKit App Service for the
// app's ID (com.mimilocks.app) at developer.apple.com → Certificates, IDs &
// Profiles → Identifiers → App Services. Until then Apple refuses catalog
// requests and the Music tab says so.
@MainActor
@Observable
final class AppleMusic {
    static let shared = AppleMusic()

    enum State: Equatable {
        case notConnected, connecting, denied
        case connected(fullSongs: Bool)
        case unavailable(String)
    }

    var state: State = .notConnected
    var nowPlaying: String?

    private init() {
        if MusicAuthorization.currentStatus == .authorized { Task { await refresh() } }
    }

    var isConnected: Bool { if case .connected = state { return true } else { return false } }
    var canPlayFull: Bool { if case .connected(let full) = state { return full } else { return false } }

    var summary: String {
        switch state {
        case .notConnected: return "Connect to play whole songs if you subscribe."
        case .connecting: return "Connecting…"
        case .denied: return "Sugerly isn't allowed to use Apple Music. Turn it on in Settings → Sugerly → Media & Apple Music."
        case .connected(let full): return full ? "Connected. Whole songs play right here." : "Connected, but whole songs need an Apple Music subscription."
        case .unavailable(let why): return why
        }
    }

    func connect() async {
        state = .connecting
        switch await MusicAuthorization.request() {
        case .authorized: await refresh()
        case .denied, .restricted: state = .denied
        default: state = .notConnected
        }
    }

    private func refresh() async {
        do {
            let subscription = try await MusicSubscription.current
            state = .connected(fullSongs: subscription.canPlayCatalogContent)
        } catch {
            state = .unavailable(Self.explain(error))
        }
    }

    // Finds the song on Apple Music and plays all of it. Returns why not, if
    // it couldn't.
    func playFull(title: String, artist: String) async -> String? {
        guard canPlayFull else { return summary }
        do {
            var request = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Song.self])
            request.limit = 5
            let response = try await request.response()
            guard let song = response.songs.first else { return "Couldn't find that song on Apple Music." }
            let player = ApplicationMusicPlayer.shared
            player.queue = [song]
            try await player.play()
            nowPlaying = "\(song.title) · \(song.artistName)"
            return nil
        } catch {
            return Self.explain(error)
        }
    }

    // Our own player is starting: stop Apple Music so they don't overlap.
    func stop() {
        guard nowPlaying != nil else { return }
        ApplicationMusicPlayer.shared.pause()
        nowPlaying = nil
    }

    static func explain(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("developertoken") || text.contains("developer token") {
            return "Apple Music isn't switched on for this app yet (turn on MusicKit for com.mimilocks.app at developer.apple.com)."
        }
        return error.localizedDescription
    }
}
