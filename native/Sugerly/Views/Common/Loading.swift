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
            if reduceMotion || RenderingBudget.shared.limited {
                HStack(spacing: dot * 0.55) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(.tint).frame(width: dot, height: dot) }
                }
            } else {
                // Fixed-size platform animation; no spring-driven SwiftUI
                // layout loop for every loading picture and button.
                ProgressView().progressViewStyle(.circular).controlSize(.small)
            }
        }
        .frame(width: dot * 6, height: dot * 2)
        .accessibilityElement()
        .accessibilityLabel("Loading")
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

// A video that's still loading: a soft light sweeps out from the middle of
// the bar at the bottom, over and over (like TikTok's loading line). Shown
// only if it takes a moment, so a quick load never flashes it. Drawn from the
// clock inside its own bar, so the line can never drift away from it.
struct BufferingSweep: View {
    var delay: Double = 0.3
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || RenderingBudget.shared.limited)) { context in
            Canvas { gc, size in
                let bar = size.height
                if reduceMotion || RenderingBudget.shared.limited {
                    gc.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: bar / 2), with: .color(.white.opacity(0.55)))
                    return
                }
                let elapsed = context.date.timeIntervalSince(start) - delay
                guard elapsed > 0 else { return }
                let t = (elapsed / 0.9).truncatingRemainder(dividingBy: 1)
                let grown = 1 - pow(1 - t, 3)
                let width = max(bar, size.width * (0.05 + 0.95 * grown))
                let rect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: bar)
                // Fades in once, then each sweep fades as it widens.
                gc.opacity = min(1, elapsed / 0.25) * (1 - grown)
                gc.fill(Path(roundedRect: rect, cornerRadius: bar / 2),
                        with: .linearGradient(Gradient(colors: [.white.opacity(0), .white, .white.opacity(0)]),
                                              startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

// A reel-shaped placeholder while the feed loads: a dark page with the
// caption and buttons sketched in where they'll be, gently breathing, and the
// loading line where the video's bar will be.
struct ReelSkeleton: View {
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || RenderingBudget.shared.limited)) { context in
            // One slow breath every 2.4 s, worked out from the clock.
            let breath = reduceMotion ? 0.5 : (1 - cos(context.date.timeIntervalSince(start) * .pi * 2 / 2.4)) / 2
            let sketch = Color.white.opacity(0.1 + 0.06 * breath)
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0x1C1519), Color(hex: 0x0E0B0D)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.main.opacity(0.06 + 0.1 * breath), .clear], center: .center, startRadius: 10, endRadius: 320)
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle().frame(width: 36, height: 36)
                            Capsule().frame(width: 110, height: 12)
                        }
                        Capsule().frame(width: 220, height: 10)
                        Capsule().frame(width: 160, height: 10)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        ForEach(0..<4, id: \.self) { _ in
                            Circle().frame(width: 40, height: 40)
                        }
                    }
                }
                .foregroundStyle(sketch)
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
                ZStack {
                    Capsule().fill(.white.opacity(0.18))
                    BufferingSweep(delay: 0)
                }
                .frame(height: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 92)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Loading reels")
    }
}
