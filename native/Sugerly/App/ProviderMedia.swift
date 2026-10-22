import Foundation

// First release: catalog providers stay unavailable until their integration is approved.
// This is a build policy, identical for every account and region.
enum ProviderMedia {
    static let catalogMusicEnabled = false
    static let giphyEnabled = false
    static func allows(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return true }
        let blocked = ["deezer.com", "dzcdn.net", "giphy.com", "giphyusercontent.com", "tenor.com"]
        return !blocked.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func allows(_ track: Track) -> Bool {
        !track.id.lowercased().hasPrefix("deezer_") && allows(track.audioURL) && allows(track.coverURL)
    }
    static func allowsReelMusic(source: String, url: String) -> Bool {
        !source.lowercased().hasPrefix("deezer:") && allows(url)
    }
}
