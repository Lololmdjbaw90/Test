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

// The icon tiles all in your theme's colour (pink with Strawberry Milk,
// lilac with Lavender Dream…): each kind of place keeps a slightly different
// shade of it (a small turn round the colour wheel and its own lightness)
// so Music and Servers still look apart, but everything reads as one
// colour, kept soft so it isn't too much. "Rainbow" in Settings brings back
// the classic fixed colours.
enum CandyFamily {
    nonisolated(unsafe) private static var made: [UInt32: [Double]] = [:]
    private static let lock = NSLock()
    // Each tile's small turn from your colour and how much lighter or deeper
    // it is, in Candy's index order (berry, peach, lemon, mint, sky, grape).
    private static let turns: [Double] = [0, 9, 16, -9, -16, -4]
    private static let lift: [Double] = [0, 0.05, 0.08, -0.03, -0.05, 0.03]

    static func stops(turn _: Double, index: Int, around main: UInt32) -> (UInt32, UInt32) {
        let hue = hues(main)[index]
        // Golds need a little more light and colour not to look olive.
        let gold = max(0, 1 - abs(hue - 46) / 30)
        let up = lift[index]
        let top = ColorTone.tone(hue: hue, saturation: 0.3 + 0.12 * gold, luminance: 0.6 + 0.08 * gold + up)
        let bottom = ColorTone.tone(hue: hue, saturation: 0.5 + 0.2 * gold, luminance: 0.32 + 0.12 * gold + up * 0.6)
        return (top, bottom)
    }

    private static func hues(_ main: UInt32) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        if let hit = made[main] { return hit }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: main).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let chosen = turns.map { wrap(Double(h) * 360 + $0) }
        made[main] = chosen
        return chosen
    }

    private static func wrap(_ hue: Double) -> Double {
        let w = hue.truncatingRemainder(dividingBy: 360)
        return w < 0 ? w + 360 : w
    }
}

// Lightness as the eye sees it (yellow looks far lighter than blue at the
// same strength), for colours that never glare.
enum ColorTone {
    nonisolated(unsafe) private static var calmed: [Int: UInt32] = [:]
    private static let lock = NSLock()

    static func luminance(_ hex: UInt32) -> Double {
        func lin(_ v: UInt32) -> Double {
            let c = Double(v & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(hex >> 16) + 0.7152 * lin(hex >> 8) + 0.0722 * lin(hex)
    }

    // The colour at this hue and strength that's about this light.
    static func tone(hue: Double, saturation: Double, luminance target: Double) -> UInt32 {
        var low = 0.15, high = 1.0
        for _ in 0..<16 {
            let mid = (low + high) / 2
            let hex = UIColor(hue: hue / 360, saturation: saturation, brightness: mid, alpha: 1).rgbHex
            if luminance(hex) < target { low = mid } else { high = mid }
        }
        return UIColor(hue: hue / 360, saturation: saturation, brightness: (low + high) / 2, alpha: 1).rgbHex
    }

    // Contrast between two colours (1 to 21), as WCAG measures it.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    // The colour as it is if it reads on `background` at `ratio`; otherwise
    // the nearest shade that does: deeper (or lighter, for dark pages)
    // while keeping its hue and a little more of its colour, so a rose stays
    // a rich rose instead of going dusty.
    static func readable(_ hex: UInt32, on background: UInt32, ratio: Double = 4.5, lighter: Bool = false) -> UInt32 {
        let key = ReadableKey(hex: hex, background: background, ratio: Int(ratio * 100), lighter: lighter)
        lock.lock()
        defer { lock.unlock() }
        if let hit = readableMade[key] { return hit }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var out = hex
        var step = 0
        while contrast(out, background) < ratio && step < 60 {
            step += 1
            let t = CGFloat(step)
            if lighter {
                out = UIColor(hue: h, saturation: max(0, s * (1 - 0.012 * t)), brightness: min(1, b + (1 - b) * 0.04 * t + 0.004 * t), alpha: 1).rgbHex
            } else {
                out = UIColor(hue: h, saturation: min(1, s * (1 + 0.01 * t)), brightness: max(0, b * (1 - 0.012 * t)), alpha: 1).rgbHex
            }
        }
        readableMade[key] = out
        return out
    }
    private struct ReadableKey: Hashable {
        let hex: UInt32, background: UInt32, ratio: Int, lighter: Bool
    }
    nonisolated(unsafe) private static var readableMade: [ReadableKey: UInt32] = [:]

    // The colour as it is, or a deeper shade of it if it's lighter than
    // `brightest` (so a very light colour doesn't glare on a button).
    static func calm(_ hex: UInt32, brightest: Double) -> UInt32 {
        let key = Int(hex) * 100 + Int(brightest * 100)
        lock.lock()
        defer { lock.unlock() }
        if let hit = calmed[key] { return hit }
        var out = hex
        var step = 0
        while luminance(out) > brightest && step < 20 {
            out = Palette.mix(hex, 0x000000, Double(step + 1) * 0.04)
            step += 1
        }
        calmed[key] = out
        return out
    }
}
