import SwiftUI

// Sugerly's own spinner: three soft dots where one at a time stretches into
// a little pill and melts back, passing along the row. Every plain
// ProgressView() in the app uses it (see .sugarProgress() at the root), and
// it follows .tint, so white on pink buttons and pink on pages.
struct MorphDots: View {
    var dot: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                row(active: -1)
            } else {
                PhaseAnimator([0, 1, 2]) { active in
                    row(active: active)
                } animation: { _ in .spring(response: 0.34, dampingFraction: 0.72) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func row(active: Int) -> some View {
        HStack(spacing: dot * 0.55) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(.tint)
                    .frame(width: i == active ? dot * 2.6 : dot, height: dot)
                    .opacity(active < 0 || i == active ? 1 : 0.4)
                    .offset(y: i == active ? -dot * 0.25 : 0)
            }
        }
        .frame(height: dot * 2)
    }
}

struct SugarProgressStyle: ProgressViewStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let fraction = configuration.fractionCompleted {
            SugarBar(value: fraction)
        } else if let label = configuration.label {
            VStack(spacing: 10) {
                MorphDots()
                label.font(.jakarta(13, .medium)).foregroundStyle(Palette.muted)
            }
        } else {
            MorphDots()
        }
    }
}

// A rounded progress bar that glides to its value.
struct SugarBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2)
                Capsule().fill(.tint)
                    .frame(width: max(6, geo.size.width * min(1, max(0, value))))
                    .motion(Motion.standard, value: value)
            }
        }
        .frame(height: 6)
    }
}

extension View {
    /// Use Sugerly's spinner for every ProgressView below this view.
    func sugarProgress() -> some View {
        progressViewStyle(SugarProgressStyle())
    }
}
