#if DEBUG
import SwiftUI
import UIKit

// The real shared controls, without an account or network writes.
struct ColorHarmonyUITestHost: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dark = false
    @State private var selected = true
    @State private var checks = "Checking contrast"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageTitle(title: "Your colors", subtitle: "Calm surfaces. Colorful details.", icon: "paintpalette.fill")
                    HStack {
                        Button("Rose") { Theme.custom = nil; Theme.accent = .rose }
                        Button("Mint") { Theme.custom = nil; Theme.accent = .mint }.accessibilityIdentifier("harmony-mint")
                        Button("Pale yellow") { Theme.custom = (0xFFF7B0, 0xFFFBE1) }
                        Button("Dark") { dark.toggle() }
                    }.font(.jakarta(13, .semibold)).tint(Theme.main)
                    PageHero(title: "Made for your community", subtitle: "A clear heading, readable details, and one obvious next step.", icon: "heart.fill", candy: .berry)
                    CandyShortcutGrid(items: [
                        .init(title: "Music", icon: "music.note", candy: .sky, route: .music),
                        .init(title: "People", icon: "person.2.fill", candy: .grape, route: .people),
                        .init(title: "Rewards", icon: "gift.fill", candy: .lemon, route: .people),
                    ]) { _ in }
                    VStack(spacing: 12) {
                        Button("Publish post") {}.buttonStyle(GradientButtonStyle()).accessibilityIdentifier("harmony-primary")
                        Button("Save draft") {}.buttonStyle(OutlineButtonStyle(fullWidth: true)).accessibilityIdentifier("harmony-secondary")
                        Button("Unavailable") {}.buttonStyle(GradientButtonStyle()).disabled(true).accessibilityIdentifier("harmony-disabled")
                        HStack {
                            Chip(title: "For you", icon: "sparkles", active: selected) { selected = true }
                            Chip(title: "Following", active: !selected) { selected = false }
                        }
                    }
                    Text(checks).font(.jakarta(12, .medium)).foregroundStyle(Palette.text2).accessibilityIdentifier("contrast-result")
                }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.sugarBackground().navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(dark ? .dark : .light)
        .onAppear { checks = verifyContrast() }
    }

    private func verifyContrast() -> String {
        let savedAccent = Theme.accent, savedCustom = Theme.custom
        defer { Theme.accent = savedAccent; Theme.custom = savedCustom }
        var failures: [String] = []
        let samples = Accent.allCases.map { ($0, Optional<(main: UInt32, light: UInt32)>.none) } +
            [(Accent.rose, (main: UInt32(0xFFF7B0), light: UInt32(0xFFFBE1))),
             (Accent.rose, (main: UInt32(0xFFFFFF), light: UInt32(0xFFFFFF))),
             (Accent.rose, (main: UInt32(0x000000), light: UInt32(0x111111))),
             (Accent.rose, (main: UInt32(0xFFFFFF), light: UInt32(0x111111)))]
        for (accent, custom) in samples {
            Theme.accent = accent; Theme.custom = custom
            for stop in Theme.buttonStops where Palette.contrast(stop, 0xFFFFFF) < 4.5 { failures.append("button") }
            for mode in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: mode)
                func hex(_ color: Color) -> UInt32 { UIColor(color).resolvedColor(with: traits).rgbHex }
                if Palette.contrast(hex(Theme.solid), 0xFFFFFF) < 4.5 { failures.append("solid fill") }
                for background in [Palette.surface, Palette.surface2] {
                    if Palette.contrast(hex(Theme.main), hex(background)) < 4.5 { failures.append("link") }
                    if Palette.contrast(hex(Palette.muted), hex(background)) < 4.5 { failures.append("muted") }
                }
            }
        }
        return failures.isEmpty ? "Contrast checks passed: \(samples.count) palettes, light and dark" : "Contrast failures: " + failures.joined(separator: ", ")
    }
}
#endif
