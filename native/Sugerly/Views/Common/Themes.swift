import SwiftUI

// Whole-app themes. Each one recolours everything from one main colour and
// its soft sub tone: buttons, pages, cards, fields, text, the icon tiles,
// Reels, the camera and calls, the logo and Mimi. The first five are the
// classic colours (with their own drawings and app icons); the others are
// saved as your own colours, so the website, the logo and Mimi follow them
// too.
struct SugarTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let main: UInt32
    let light: UInt32
    var accent: Accent?

    static let all: [SugarTheme] = [
        SugarTheme(id: "strawberry", name: "Strawberry Milk", main: Accent.rose.mainHex, light: Accent.rose.lightHex, accent: .rose),
        SugarTheme(id: "lavender", name: "Lavender Dream", main: Accent.lavender.mainHex, light: Accent.lavender.lightHex, accent: .lavender),
        SugarTheme(id: "mint", name: "Mint Soda", main: Accent.mint.mainHex, light: Accent.mint.lightHex, accent: .mint),
        SugarTheme(id: "peach", name: "Peach Sorbet", main: Accent.peach.mainHex, light: Accent.peach.lightHex, accent: .peach),
        SugarTheme(id: "sky", name: "Blue Sky", main: Accent.sky.mainHex, light: Accent.sky.lightHex, accent: .sky),
        SugarTheme(id: "cotton", name: "Cotton Candy", main: 0xDE5E9C, light: 0xA9D5F7),
        SugarTheme(id: "grape", name: "Grape Jelly", main: 0x8A4FD6, light: 0xE0C6F7),
        SugarTheme(id: "cherry", name: "Cherry Cola", main: 0xC9384F, light: 0xF4B8B4),
        SugarTheme(id: "lemon", name: "Lemon Tart", main: 0xB97A0E, light: 0xFAE29A),
        SugarTheme(id: "matcha", name: "Matcha", main: 0x4E8C3E, light: 0xCFE6B8),
        SugarTheme(id: "ocean", name: "Ocean", main: 0x1D84A0, light: 0x9FDAE6),
        SugarTheme(id: "sunset", name: "Sunset", main: 0xDF6255, light: 0xCBA8F0),
    ]

    // The theme your own colours are, if they're one of the presets.
    static func matching(_ colors: (main: UInt32, light: UInt32)?) -> SugarTheme? {
        guard let colors else { return nil }
        return all.first { $0.accent == nil && $0.main == colors.main && $0.light == colors.light }
    }

    // Whether it's the one in use (a classic colour only counts when no own
    // colours are set over it).
    func isPicked(accent current: Accent, mine: (main: UInt32, light: UInt32)?) -> Bool {
        if let accent { return mine == nil && current == accent }
        guard let mine else { return false }
        return mine.main == main && mine.light == light
    }

    // The profile fields that switch to it.
    var fields: Doc {
        if let accent { return ["accent": accent.rawValue, "accent_main": "", "accent_sub": ""] }
        return ["accent_main": SiteTheme.string(main), "accent_sub": SiteTheme.string(light)]
    }
}

// A theme in the picker: its colours, with Mimi in them.
struct ThemeCard: View {
    let theme: SugarTheme
    let picked: Bool

    var body: some View {
        AccentCard(title: theme.name, main: Color(hex: theme.main), light: Color(hex: theme.light), picked: picked, height: 84) {
            art
        }
    }

    @ViewBuilder
    private var art: some View {
        if let accent = theme.accent {
            AccentMimi(name: accent.mimi, picked: picked)
        } else {
            AccentMimi(name: Accent.rose.mimi, picked: picked)
                .tintShift(TintShift(from: 0xD9577F, to: theme.main))
        }
    }
}

// The icon tiles as a family of your theme: each kind of place keeps its
// own spot on the colour wheel next to your colour (so Music and Servers
// still look different), all at the same softness. "Rainbow" in Settings
// brings back the classic fixed colours.
enum CandyFamily {
    nonisolated(unsafe) private static var made: [Int: (UInt32, UInt32)] = [:]
    private static let lock = NSLock()

    static func stops(turn degrees: Double, index: Int, around main: UInt32) -> (UInt32, UInt32) {
        let key = Int(main) * 8 + index
        lock.lock()
        defer { lock.unlock() }
        if let hit = made[key] { return hit }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: main).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = Double(h) + degrees / 360
        hue -= floor(hue)
        // Yellows and greens look much lighter than blues at the same
        // strength: take them a little deeper so the family looks even.
        let distance = min(abs(hue * 360 - 95), 360 - abs(hue * 360 - 95))
        let bright = max(0, 1 - distance / 70)
        let top = UIColor(hue: hue, saturation: 0.4 + 0.08 * bright, brightness: 1 - 0.06 * bright, alpha: 1).rgbHex
        let bottom = UIColor(hue: hue, saturation: 0.64 + 0.14 * bright, brightness: 0.92 - 0.2 * bright, alpha: 1).rgbHex
        made[key] = (top, bottom)
        return (top, bottom)
    }
}
