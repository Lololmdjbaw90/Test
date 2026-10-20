import AVFoundation

// Serialize seeks; discard work from a previously imported player item.
@MainActor
final class PreviewSeeker {
    private var pending: (AVPlayer, Double, Bool, ((Bool) -> Void)?)?
    private var busy = false
    private var generation = UUID()
    var isSeeking: Bool { busy || pending != nil }

    func reset(_ player: AVPlayer) {
        generation = UUID()
        pending = nil
        busy = false
        player.currentItem?.cancelPendingSeeks()
    }

    func seek(_ player: AVPlayer, seconds: Double, precise: Bool = false, completion: ((Bool) -> Void)? = nil) {
        pending = (player, max(0, seconds), precise, completion)
        drain()
    }

    private func drain() {
        guard !busy, let (player, seconds, precise, completion) = pending else { return }
        pending = nil
        busy = true
        let current = generation
        let tolerance = CMTime(seconds: precise ? 0 : 1.0 / 30, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.busy = false
                if self.pending == nil { completion?(finished) }
                self.drain()
            }
        }
    }
}
