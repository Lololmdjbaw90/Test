import SwiftUI

// Sugerly's loading sign: three small dots that brighten one after another.
// Nothing jumps; with Reduce Motion they brighten more slowly.
struct SugarLoader: View {
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            hearts(at: context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func hearts(at t: Double) -> some View {
        HStack(spacing: size * 0.5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Palette.text2)
                    .frame(width: size * 0.62, height: size * 0.62)
                    .opacity(0.25 + 0.65 * Self.hop(t * (reduceMotion ? 0.5 : 1), i))
            }
        }
        .frame(height: size)
    }

    // 0…1…0 for the first half of each beat, resting for the second half.
    private static func hop(_ t: Double, _ i: Int) -> Double {
        let raw: Double = t * 1.6 - Double(i) * 0.2
        let phase: Double = raw - raw.rounded(.down)
        return phase < 0.5 ? sin(phase * 2 * Double.pi) : 0
    }
}

// Little bars that dance while a song plays.
struct EqualizerBars: View {
    var color: Color = .white
    var height: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            bars(at: context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func bars(at t: Double) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 4, height: max(4, height * CGFloat(level(t, i))))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func level(_ t: Double, _ i: Int) -> Double {
        guard !reduceMotion else { return 0.6 }
        let speed: Double = 4.5 + Double(i) * 1.3
        let wave: Double = sin(t * speed + Double(i) * 0.9)
        return 0.3 + 0.7 * abs(wave)
    }
}
