import SwiftUI
import UIKit

// Pages keep their content in a readable column. On wide screens (iPad,
// landscape) the empty space on the sides gets columns of useful cards, and
// Home shows the same cards on iPhone. They're built in (prompt, palette,
// tips, charts, your stats, invites), so pages look full even when only a
// few people are on the app.

extension View {
    /// Content in the middle; side columns when there's room.
    func sideRails(_ width: CGFloat, left: Bool = true, right: Bool = true) -> some View {
        modifier(SideRailsLayout(width: width, left: left, right: right))
    }
}

private struct SideRailsLayout: ViewModifier {
    let width: CGFloat
    let left: Bool
    let right: Bool
    @State private var available: CGFloat = 0
    private let rail: CGFloat = 270
    private let gap: CGFloat = 18

    func body(content: Content) -> some View {
        let showRight = right && available >= 980
        let showLeft = left && available >= 1300
        let rails = (showRight ? rail + gap : 0) + (showLeft ? rail + gap : 0)
        let column = max(320, min(width, available - rails - 32))
        HStack(alignment: .top, spacing: gap) {
            if showLeft { SideRail(kind: .explore).frame(width: rail).padding(.top, 12) }
            content
                .frame(maxWidth: showLeft || showRight ? column : width)
                .environment(\.railsShown, showRight)
            if showRight { SideRail(kind: showLeft ? .you : .both).frame(width: rail).padding(.top, 12) }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { available = $0 })
    }
}

// True inside a page whose side columns are showing (so it doesn't repeat
// the same cards inline).
private struct RailsShownKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var railsShown: Bool {
        get { self[RailsShownKey.self] }
        set { self[RailsShownKey.self] = newValue }
    }
}

struct SideRail: View {
    enum Kind { case explore, you, both }
    let kind: Kind

    var body: some View {
        VStack(spacing: 14) {
            switch kind {
            case .explore:
                PromptOfTheDay()
                PaletteOfTheDay()
                ArtTipCard()
                ChartsMini()
            case .you:
                YouCard()
                InviteCard(compact: true)
                TryThisCard()
                OnlineNowCard()
            case .both:
                YouCard()
                PromptOfTheDay()
                InviteCard(compact: true)
                PaletteOfTheDay()
                ArtTipCard()
                ChartsMini()
                OnlineNowCard()
            }
        }
    }
}

// MARK: - Cards

private struct RailTitle: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
            Spacer(minLength: 0)
        }
    }
}

enum DayPick {
    static var day: Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }
    static func pick<T>(_ list: [T], offset: Int = 0) -> T { list[(day + offset) % list.count] }
}

struct PromptOfTheDay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailTitle(icon: "paintbrush.pointed.fill", title: "Today's prompt")
            if let prompt = DailyContent.prompt {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: prompt.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.main)
                    Text(prompt.text).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Draw it, post it with #prompt, and see what others made.").font(.jakarta(12)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
    }
}

// Five colours that go together, new every day (tap one to copy it).
struct PaletteOfTheDay: View {
    @State private var copied: String?

    private static let palettes: [(String, [UInt32])] = [
        ("Strawberry milk", [0xFFE3EC, 0xFFB3C8, 0xF47B9E, 0xC94F72, 0x6B2E45]),
        ("Lavender dusk", [0xF1E9FF, 0xCDB8FF, 0xA38BF0, 0x6E5BC4, 0x33295E]),
        ("Mint soda", [0xE8FFF6, 0xB6F0DA, 0x6FD4B2, 0x2E9E80, 0x1B4F44]),
        ("Peach sunset", [0xFFF1E6, 0xFFCFA8, 0xFF9E6D, 0xE8655A, 0x7A2E3A]),
        ("Sky candy", [0xEAF6FF, 0xB9E0FF, 0x7CBEFF, 0x4A86D9, 0x23407A]),
        ("Lemon tart", [0xFFFBE3, 0xFFEFA3, 0xFFD166, 0xE0A128, 0x6B4A12]),
        ("Berry jam", [0xFCE4F4, 0xF3A6D6, 0xD65DB1, 0x9B2D83, 0x4A1440]),
        ("Forest picnic", [0xF0F7E6, 0xC9E3A6, 0x8FBF69, 0x557F3D, 0x2B4220]),
        ("Cotton candy", [0xFFF0FA, 0xFFC6EA, 0xC7B8FF, 0x9AD7FF, 0x6C8CD5]),
        ("Cocoa latte", [0xF7EFE6, 0xE3CBB0, 0xC19A73, 0x8A6246, 0x4A3326]),
    ]

    var body: some View {
        let palette = DayPick.pick(Self.palettes)
        VStack(alignment: .leading, spacing: 10) {
            RailTitle(icon: "swatchpalette.fill", title: "Palette of the day")
            HStack(spacing: 6) {
                ForEach(palette.1, id: \.self) { hex in
                    let code = String(format: "#%06X", hex)
                    Button {
                        UIPasteboard.general.string = code
                        withAnimation(.snappy) { copied = code }
                    } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: hex))
                            .frame(height: 44)
                            .overlay { if copied == code { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).shadow(radius: 2) } }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.9))
                    .accessibilityLabel("Copy \(code)")
                }
            }
            Text(copied.map { "Copied \($0)" } ?? palette.0).font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
    }
}

struct ArtTipCard: View {
    private static let tips: [(String, String)] = [
        ("hand.draw.fill", "Warm up with 5 minutes of loose circles and lines before you start."),
        ("sun.max.fill", "Pick one light source and keep every shadow on the opposite side."),
        ("circle.lefthalf.filled", "Squint at your drawing: if the shapes still read, your values work."),
        ("paintpalette.fill", "Use 3 main colours and let one of them lead."),
        ("arrow.triangle.2.circlepath", "Flip your canvas to spot mistakes you've stopped seeing."),
        ("person.fill", "Draw heads about 7 to 8 times into the body height for a real look."),
        ("scribble.variable", "Sketch big shapes first, details last."),
        ("eye.fill", "Look at your subject more than at your paper."),
        ("drop.fill", "Add a touch of the background colour into your shadows."),
        ("square.stack.3d.up.fill", "Overlap things to show which one is in front."),
        ("clock.fill", "Try a 1-minute sketch: speed teaches you what matters."),
        ("sparkles", "A little bright highlight makes eyes and shiny things pop."),
        ("leaf.fill", "Vary your line thickness: thick near you, thin far away."),
        ("heart.fill", "Post your work in progress too. People love seeing how art is made."),
    ]

    var body: some View {
        let tip = DayPick.pick(Self.tips, offset: 3)
        VStack(alignment: .leading, spacing: 10) {
            RailTitle(icon: "lightbulb.fill", title: "Art tip")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tip.0).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.main).frame(width: 24)
                Text(tip.1).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
    }
}

// The top 5 songs right now (Deezer previews), tap to play.
struct ChartsMini: View {
    @Environment(Player.self) private var player
    @State private var tracks: [Track] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RailTitle(icon: "chart.line.uptrend.xyaxis", title: "Top songs")
            if tracks.isEmpty {
                ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 10).fill(Palette.surface2).frame(height: 40) }
            }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                Button { player.play(t, in: tracks) } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.jakarta(12, .heavy)).foregroundStyle(i < 3 ? Theme.main : Palette.muted).frame(width: 16)
                        RemoteImage(url: t.coverURL).frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.jakarta(13, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                            Text(t.artist).font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: player.isPlaying(t) ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.main)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
        .task {
            guard tracks.isEmpty else { return }
            tracks = (try? await Deezer.page(genre: 0, query: "", index: 0, limit: 5))?.tracks ?? []
        }
    }
}

struct YouCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let me = model.me {
            let info = LevelInfo(xp: me.xp)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Avatar(url: me.picture, name: me.displayName, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(me.displayName).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("Level \(info.level) · \(info.title)").font(.jakarta(11, .bold)).foregroundStyle(info.color)
                    }
                    Spacer(minLength: 0)
                }
                XPBar(info: info)
                HStack(spacing: 8) {
                    stat("\(me.coins)", "coins", "circle.hexagongrid.fill")
                    stat("\(me.dailyStreak)", "day streak", "flame.fill")
                    stat("\(me.following.count)", "following", "person.2.fill")
                }
            }
            .sugarCard(radius: 22, padding: 14)
        }
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.main)
            Text(value).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
            Text(label).font(.jakarta(10, .semibold)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// Little ideas of things to try in the app.
struct TryThisCard: View {
    private static let ideas: [(String, String, String)] = [
        ("film.stack.fill", "Make a reel", "Film clips, add a song, stickers and text in Reels."),
        ("paintpalette.fill", "Dress up your profile", "Name styles, frames, banner patterns and effects in Edit profile."),
        ("person.3.fill", "Start a server", "A cosy place for your art friends, with channels and roles."),
        ("music.note", "Share a track", "Upload a song or a beat in Music."),
        ("photo.on.rectangle.angled", "Post in the gallery", "Show your best piece where everyone can see it."),
        ("bubble.left.and.bubble.right.fill", "Say hi", "Comment on someone's art today: it makes their day."),
        ("trophy.fill", "Join the challenge", "This week's challenge is on Home and in Community."),
    ]

    var body: some View {
        let idea = DayPick.pick(Self.ideas, offset: 1)
        let second = DayPick.pick(Self.ideas, offset: 4)
        VStack(alignment: .leading, spacing: 10) {
            RailTitle(icon: "wand.and.stars", title: "Try this")
            ForEach([idea, second], id: \.1) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.0).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.main).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.1).font(.jakarta(13, .heavy)).foregroundStyle(Palette.text)
                        Text(item.2).font(.jakarta(12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
    }
}

struct OnlineNowCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let me = model.me?.email ?? ""
        let people = model.people.values
            .filter { $0.email != me && $0.isOnline }
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(6)
        VStack(alignment: .leading, spacing: 10) {
            RailTitle(icon: "dot.radiowaves.left.and.right", title: "Around now")
            if people.isEmpty {
                Text("It's quiet right now. Invite a friend and draw together!").font(.jakarta(12)).foregroundStyle(Palette.muted)
            } else {
                ForEach(Array(people), id: \.email) { person in
                    HStack(spacing: 10) {
                        Avatar(url: person.picture, name: person.displayName, size: 32)
                            .overlay(alignment: .bottomTrailing) { PresenceDot(presence: person.presenceNow, size: 11) }
                        Text(person.displayName).font(.jakarta(13, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 22, padding: 14)
    }
}

// The same cards inside a page's own column, when its side columns aren't
// showing (iPhone, iPad portrait).
struct InlineExtras: View {
    enum Part { case top, bottom }
    let part: Part
    @Environment(\.railsShown) private var railsShown

    var body: some View {
        if !railsShown {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], spacing: 14) {
                switch part {
                case .top:
                    PaletteOfTheDay()
                    ArtTipCard()
                case .bottom:
                    InviteCard()
                    ChartsMini()
                    TryThisCard()
                    OnlineNowCard()
                }
            }
        }
    }
}
