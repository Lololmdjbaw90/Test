import AVFoundation

// Keep only the newest finger position while AVPlayer decodes a seek.
// Repeated zero-tolerance seeks otherwise cancel each other on every move.
@MainActor
final class PreviewSeeker {
    private var pending: (AVPlayer, Double, Bool)?
    private var busy = false

    func seek(_ player: AVPlayer, seconds: Double, precise: Bool = false) {
        pending = (player, max(0, seconds), precise)
        drain()
    }

    private func drain() {
        guard !busy, let (player, seconds, precise) = pending else { return }
        pending = nil
        busy = true
        let tolerance = CMTime(seconds: precise ? 0 : 1.0 / 30, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                self?.busy = false
                self?.drain()
            }
        }
    }
}
