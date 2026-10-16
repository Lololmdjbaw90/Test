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

// Shown only if something takes a moment (a quick load never flashes a
// spinner): the dots in a dark pill, over a picture or video.
struct BufferingDots: View {
    var delay: Double = 0.35
    @State private var shown = false

    var body: some View {
        MorphDots(dot: 8)
            .tint(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.35), in: Capsule())
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.85)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(Motion.pick(Motion.playful)) { shown = true }
            }
            .allowsHitTesting(false)
    }
}

// A reel-shaped placeholder while the feed loads: a soft glowing page with
// the caption and buttons sketched in where they'll be.
struct ReelSkeleton: View {
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x1C1519), Color(hex: 0x0E0B0D)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.main.opacity(glow ? 0.28 : 0.12), .clear], center: .center, startRadius: 10, endRadius: 320)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: glow)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle().fill(.white.opacity(0.14)).frame(width: 36, height: 36)
                        Capsule().fill(.white.opacity(0.14)).frame(width: 110, height: 12)
                    }
                    Capsule().fill(.white.opacity(0.12)).frame(width: 220, height: 10)
                    Capsule().fill(.white.opacity(0.1)).frame(width: 160, height: 10)
                }
                .shimmer()
                Spacer(minLength: 0)
                VStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(.white.opacity(0.13)).frame(width: 40, height: 40)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
            MorphDots(dot: 8)
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { glow = true }
        .accessibilityElement()
        .accessibilityLabel("Loading reels")
    }
}
