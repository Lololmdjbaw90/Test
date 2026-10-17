import SwiftUI
import UIKit

// How Sugerly moves. One set of timings for the whole app, so everything
// feels like the same quick, soft thing:
// - What you press answers the instant your finger lands (a small squish)
//   and springs back when you let go.
// - What arrives starts fast and settles (a strong ease-out); what leaves
//   goes quicker than it came, back the way it came.
// - What moves around on screen speeds up and slows down gently.
// - Bounce only where there's a reason: a like, a reward, a flick.
// - Most motion is over in about a quarter of a second.
// - Nothing grows out of nothing: things start a little smaller, not at 0.
// - With Reduce Motion on, slides and springs become short fades.
enum Motion {
    /// Finger down: quick, fast start.
    static let press = Animation.easeOut(duration: 0.11)
    /// Finger up: a quick spring with a tiny overshoot.
    static let release = Animation.spring(response: 0.3, dampingFraction: 0.62)
    /// Routine changes (tabs, chips, switches, panels): settles, no overshoot.
    static let standard = Animation.spring(response: 0.32, dampingFraction: 1)
    /// Something growing, shrinking or moving on screen.
    static let move = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.32)
    /// Something appearing.
    static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)
    /// Something leaving: the same curve, quicker.
    static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    /// Bars, drawers and cards sliding in (the iPhone's own sheet curve).
    static let drawer = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.4)
    /// A little life where it's earned: likes, rewards, a flick.
    static let playful = Animation.spring(response: 0.35, dampingFraction: 0.6)
    /// Sections arriving: a soft spring that settles with the barest bounce.
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.82)
    /// Colour and see-through changes.
    static let fade = Animation.easeOut(duration: 0.2)
    /// Items arriving together: each one this long after the one before.
    static let staggerStep = 0.04

    /// Reduce Motion is on (Settings → Accessibility → Motion). Safe to ask
    /// from anywhere; off the main thread it answers "no".
    static var reduced: Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated { UIAccessibility.isReduceMotionEnabled }
    }

    /// Things that keep moving on their own (drifting backgrounds, a
    /// bobbing bunny, twinkles): off with Reduce Motion, and off during the
    /// automatic UI tests (which wait for the screen to be still).
    static let ambient: Bool = !ProcessInfo.processInfo.arguments.contains { $0.hasSuffix("-ui-test") }

    /// The animation to use, or a short fade with Reduce Motion on.
    static func pick(_ animation: Animation) -> Animation { reduced ? fade : animation }

    /// Items in a list arriving one after another (capped, so long lists
    /// never keep you waiting).
    static func staggered(_ animation: Animation, _ index: Int, cap: Int = 8) -> Animation {
        pick(animation).delay(reduced ? 0 : Double(min(max(index, 0), cap)) * staggerStep)
    }
}

/// `withAnimation` that becomes a short fade with Reduce Motion on.
@discardableResult
func withMotion<Result>(_ animation: Animation = Motion.standard, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.pick(animation), body)
}

extension AnyTransition {
    /// Grows in from a little smaller and fades in; leaves quicker. (A
    /// cross-fade with Reduce Motion on.)
    static var pop: AnyTransition {
        guard !Motion.reduced else { return .opacity }
        return .asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                           removal: .scale(scale: 0.96).combined(with: .opacity).animation(Motion.exit))
    }

    /// Rises a few points and fades in; fades out quicker.
    static var rise: AnyTransition {
        guard !Motion.reduced else { return .opacity }
        return .asymmetric(insertion: .offset(y: 8).combined(with: .opacity),
                           removal: .opacity.animation(Motion.exit))
    }

    /// Slides in from an edge and leaves the same way, quicker.
    static func slideIn(from edge: Edge) -> AnyTransition {
        guard !Motion.reduced else { return .opacity }
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: edge).combined(with: .opacity).animation(Motion.exit))
    }
}

extension AnyTransition {
    /// One thing turning into another in the same spot (a word changing):
    /// the old one blurs and fades out as the new one sharpens in, so the eye
    /// sees a single change rather than two things overlapping.
    static var blurSwap: AnyTransition {
        guard !Motion.reduced else { return .opacity }
        return .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
    }
}

struct BlurFade: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 4 * amount)
            .opacity(1 - amount)
            .scaleEffect(1 - 0.08 * amount)
    }
}

extension View {
    /// `.animation(_:value:)` that becomes a short fade with Reduce Motion on.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.fade : animation, value: value)
    }
}
