import SwiftUI

// Sugerly's loading sign: three little hearts in your colour that hop one
// after another (instead of the grey iPhone spinner). With Reduce Motion
// they only glow softly in turn.
struct SugarLoader: View {
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.55) {
                ForEach(0..<3, id: \.self) { i in
                    let raw = t * 2.2 - Double(i) * 0.18
                    let phase = raw - raw.rounded(.down)
                    let hop = phase < 0.5 ? sin(phase * 2 * .pi) : 0
                    Image(systemName: "heart.fill")
                        .font(.system(size: size, weight: .bold))
                        .foregroundStyle(Theme.gradient)
                        .offset(y: reduceMotion ? 0 : -size * 0.7 * hop)
                        .scaleEffect(reduceMotion ? 1 : 1 + 0.15 * hop)
                        .opacity(reduceMotion ? 0.45 + 0.55 * hop : 1)
                }
            }
            .padding(.top, size * 0.7)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

// Little bars that dance while a song plays.
struct EqualizerBars: View {
    var color: Color = .white
    var height: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let level = reduceMotion ? 0.6 : 0.3 + 0.7 * abs(sin(t * (4.5 + Double(i) * 1.3) + Double(i) * 0.9))
                    Capsule().fill(color)
                        .frame(width: 4, height: max(4, height * level))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
