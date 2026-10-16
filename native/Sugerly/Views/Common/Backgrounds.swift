import SwiftUI

// MARK: - Page backgrounds

// Every page sits on the same plain, warm paper colour. The moving
// wallpapers (dots, clouds, hearts and the rest) and the coloured glows are
// gone: they fought with the cards and made every page look busy.

extension View {
    // Home and the menu: the plain page background.
    func patternBackground() -> some View {
        background { Palette.bg.ignoresSafeArea() }
    }

    // Page background: plain paper.
    func sugarBackground() -> some View { background { GlowLayer().ignoresSafeArea() } }
}

// Used to be a moving wallpaper at the top of Home; now draws nothing, so
// the header is calm.
struct HeaderWallpaper: View {
    var body: some View { EmptyView() }
}

// The plain page background (the name stayed from when it had glows).
struct GlowLayer: View {
    var body: some View { Palette.bg }
}

// Nothing moves behind a sheet or menu.
private struct BackgroundPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var backgroundPaused: Bool {
        get { self[BackgroundPausedKey.self] }
        set { self[BackgroundPausedKey.self] = newValue }
    }
}
