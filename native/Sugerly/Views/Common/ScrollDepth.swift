import SwiftUI
import UIKit

private struct AmbientPausedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ambientPaused: Bool { get { self[AmbientPausedKey.self] } set { self[AmbientPausedKey.self] = newValue } }
}

// Scroll-driven depth, with no frame timer or animation work while idle.
struct ScrollDepth: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.ambientPaused) private var paused
    @AppStorage("sugerly.background.still") private var still = false
    @AppStorage(AppBackground.storageKey) private var choice = AppBackground.dots.rawValue
    @State private var step = 0
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), choice != AppBackground.off.rawValue {
            content.onScrollGeometryChange(for: Int.self) { geometry in
                Int(min(1600, max(-1600, geometry.contentOffset.y)) / 12)
            } action: { _, next in if !reduce && !still && !paused { step = next } }
            .background {
                GeometryReader { g in
                    let shift = reduce || still ? 0 : CGFloat(step)
                    ZStack {
                        Circle().fill(Theme.light.opacity(0.18)).frame(width: 210, height: 210).offset(x: g.size.width * 0.28, y: -140 - shift * 0.3)
                        Image(systemName: "heart.fill").font(.system(size: 85)).foregroundStyle(Theme.main.opacity(0.1)).rotation3DEffect(.degrees(Double(shift) * 0.12), axis: (x: 1, y: 0.5, z: 0)).offset(x: -g.size.width * 0.3, y: 190 - shift * 0.6)
                    }.frame(width: g.size.width, height: g.size.height).clipped()
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        } else { content }
    }
}

struct PatternThumbnail: View {
    let kind: AppBackground
    @Environment(\.colorScheme) private var scheme
    @State private var snapshot: UIImage?
    private var key: String { "\(kind.rawValue)-\(scheme)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)" }
    var body: some View {
        Group {
            if let snapshot { Image(uiImage: snapshot).resizable() }
            else { Palette.bg.overlay(Image(systemName: kind.icon).foregroundStyle(Theme.main)) }
        }.task(id: key) {
            let renderer = ImageRenderer(content: PatternBackground(kind: kind, animated: false).frame(width: 74, height: 104).environment(\.colorScheme, scheme))
            renderer.scale = 2
            snapshot = renderer.uiImage
        }
    }
}
