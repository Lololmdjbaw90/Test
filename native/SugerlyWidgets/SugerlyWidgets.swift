import WidgetKit
import SwiftUI
import UIKit

// Home-screen and lock-screen widgets for Sugerly. The app writes a small
// snapshot (streak, coins, level, unread counts, a featured artwork) into
// the shared app group; the widgets read it and redraw every half hour or
// whenever the app asks.

private let appGroup = "group.com.mimilocks.app"

struct Snapshot: Codable {
    var name = ""
    var streak = 0
    var coins = 0
    var level = 1
    var levelTitle = ""
    var progress = 0.0
    var unreadDMs = 0
    var unreadAlerts = 0
    var accentMain: UInt32 = 0xD9577F
    var accentLight: UInt32 = 0xEE8FAE
    var featuredTitle = ""
    var featuredArtist = ""
    var nitro = false

    static func load() -> Snapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static let sample = Snapshot(name: "Mimi", streak: 7, coins: 420, level: 5, levelTitle: "Sketcher", progress: 0.6, unreadDMs: 3, unreadAlerts: 5, featuredTitle: "Strawberry dreams", featuredArtist: "Mimi")
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }
}

struct SugerlyEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let art: UIImage?
}

struct SugerlyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SugerlyEntry { SugerlyEntry(date: Date(), snapshot: .sample, art: nil) }

    func getSnapshot(in context: Context, completion: @escaping (SugerlyEntry) -> Void) {
        completion(entry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SugerlyEntry>) -> Void) {
        completion(Timeline(entries: [entry(preview: false)], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func entry(preview: Bool) -> SugerlyEntry {
        let snap = Snapshot.load() ?? (preview ? .sample : nil)
        var art: UIImage?
        if let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let data = try? Data(contentsOf: folder.appendingPathComponent("featured.jpg")) {
            art = UIImage(data: data)
        }
        return SugerlyEntry(date: Date(), snapshot: snap, art: art)
    }
}

// Pink polka-dot card background like the app.
struct DotsBackground: View {
    let main: Color
    let light: Color
    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, light.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let gap: CGFloat = 16
                var y: CGFloat = 6
                var row = 0
                while y < size.height + gap {
                    var x: CGFloat = row % 2 == 0 ? 4 : 4 + gap / 2
                    let depth = y / max(1, size.height)
                    while x < size.width + gap {
                        context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(main.opacity(0.06 + depth * 0.14)))
                        x += gap
                    }
                    y += gap * 0.86
                    row += 1
                }
            }
        }
    }
}

private struct SignInHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.circle.fill").font(.system(size: 28)).foregroundStyle(Color(rgb: 0xD9577F))
            Text("Open Sugerly").font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Color(rgb: 0x2A1620))
            Text("to fill this widget").font(.system(.caption2, design: .rounded)).foregroundStyle(Color(rgb: 0x6B5560))
        }
    }
}

// MARK: - Streak & coins

struct StreakView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SugerlyEntry

    var body: some View {
        if let s = entry.snapshot {
            let main = Color(rgb: s.accentMain), light = Color(rgb: s.accentLight)
            switch family {
            case .accessoryCircular:
                Gauge(value: s.progress) {
                    Image(systemName: "flame.fill")
                } currentValueLabel: {
                    Text("\(s.streak)").font(.system(.title3, design: .rounded, weight: .heavy))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(s.streak)-day streak", systemImage: "flame.fill").font(.system(.headline, design: .rounded))
                    Text("\(s.coins) coins · Lv.\(s.level)").font(.system(.caption, design: .rounded))
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "flame.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(LinearGradient(colors: [Color(rgb: 0xFFB347), Color(rgb: 0xF08A20)], startPoint: .top, endPoint: .bottom), in: Circle())
                        Spacer()
                        if s.nitro { Image(systemName: "sparkles").foregroundStyle(Color(rgb: 0x8B5CF6)) }
                    }
                    Text("\(s.streak)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(main)
                        .contentTransition(.numericText())
                    Text("day streak").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Color(rgb: 0x6B5560))
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(Color(rgb: 0xF0A020))
                        Text("\(s.coins)").font(.system(.caption, design: .rounded, weight: .heavy)).foregroundStyle(Color(rgb: 0x2A1620))
                        Spacer()
                        Text("Lv.\(s.level)").font(.system(.caption2, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(LinearGradient(colors: [light, main], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    }
                    ProgressView(value: s.progress).tint(main)
                }
                .widgetURL(URL(string: "sugerly://home"))
            }
        } else {
            SignInHint()
        }
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SugerlyStreak", provider: SugerlyProvider()) { entry in
            StreakView(entry: entry)
                .containerBackground(for: .widget) {
                    let s = entry.snapshot ?? .sample
                    DotsBackground(main: Color(rgb: s.accentMain), light: Color(rgb: s.accentLight))
                }
        }
        .configurationDisplayName("Streak & coins")
        .description("Your daily streak, coins and level.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Inbox

struct InboxView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SugerlyEntry

    var body: some View {
        if let s = entry.snapshot {
            let main = Color(rgb: s.accentMain), light = Color(rgb: s.accentLight)
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(s.unreadDMs) messages", systemImage: "bubble.left.fill").font(.system(.headline, design: .rounded))
                    Label("\(s.unreadAlerts) alerts", systemImage: "bell.fill").font(.system(.caption, design: .rounded))
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "bubble.left.fill").font(.system(size: 12, weight: .bold))
                        Text("\(s.unreadDMs + s.unreadAlerts)").font(.system(.title3, design: .rounded, weight: .heavy))
                    }
                }
            case .systemMedium:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hi \(s.name.split(separator: " ").first.map(String.init) ?? "")").font(.system(.title3, design: .rounded, weight: .heavy)).foregroundStyle(Color(rgb: 0x2A1620)).lineLimit(1)
                        Text(s.unreadDMs + s.unreadAlerts == 0 ? "You're all caught up" : "Something new is waiting").font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(Color(rgb: 0x6B5560))
                        Spacer(minLength: 0)
                        Text("Lv.\(s.level) · \(s.levelTitle)").font(.system(.caption2, design: .rounded, weight: .heavy)).foregroundStyle(main)
                    }
                    Spacer(minLength: 0)
                    counter("bubble.left.and.bubble.right.fill", s.unreadDMs, "Messages", main, light, url: "sugerly://chat")
                    counter("bell.fill", s.unreadAlerts, "Alerts", main, light, url: "sugerly://alerts")
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inbox").font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(Color(rgb: 0x2A1620))
                    row("bubble.left.fill", s.unreadDMs, "messages", main)
                    row("bell.fill", s.unreadAlerts, "alerts", main)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "sugerly://chat"))
            }
        } else {
            SignInHint()
        }
    }

    private func counter(_ icon: String, _ n: Int, _ label: String, _ main: Color, _ light: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [light, main], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if n > 0 {
                            Text("\(min(n, 99))").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color(rgb: 0xE0526B), in: Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(label).font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(Color(rgb: 0x6B5560))
            }
        }
    }

    private func row(_ icon: String, _ n: Int, _ label: String, _ main: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(main)
                .frame(width: 26, height: 26).background(main.opacity(0.12), in: Circle())
            Text("\(n)").font(.system(.title3, design: .rounded, weight: .heavy)).foregroundStyle(Color(rgb: 0x2A1620))
            Text(label).font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(Color(rgb: 0x6B5560))
        }
    }
}

struct InboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SugerlyInbox", provider: SugerlyProvider()) { entry in
            InboxView(entry: entry)
                .containerBackground(for: .widget) {
                    let s = entry.snapshot ?? .sample
                    DotsBackground(main: Color(rgb: s.accentMain), light: Color(rgb: s.accentLight))
                }
        }
        .configurationDisplayName("Inbox")
        .description("Unread messages and alerts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Featured art

struct ArtView: View {
    let entry: SugerlyEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if entry.art == nil {
                VStack(spacing: 6) {
                    Image(systemName: "paintpalette.fill").font(.system(size: 30)).foregroundStyle(Color(rgb: entry.snapshot?.accentMain ?? 0xD9577F))
                    Text("Featured art").font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Color(rgb: 0x2A1620))
                    Text("Open Sugerly to load it").font(.system(.caption2, design: .rounded)).foregroundStyle(Color(rgb: 0x6B5560))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let s = entry.snapshot, !s.featuredTitle.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.featuredTitle).font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                    Text("by \(s.featuredArtist)").font(.system(.caption2, design: .rounded, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .widgetURL(URL(string: "sugerly://gallery"))
    }
}

struct ArtWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SugerlyArt", provider: SugerlyProvider()) { entry in
            ArtView(entry: entry)
                .containerBackground(for: .widget) {
                    if let art = entry.art {
                        Image(uiImage: art).resizable().scaledToFill()
                    } else {
                        let s = entry.snapshot ?? .sample
                        DotsBackground(main: Color(rgb: s.accentMain), light: Color(rgb: s.accentLight))
                    }
                }
        }
        .configurationDisplayName("Featured art")
        .description("A loved artwork from the Sugerly gallery.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct SugerlyWidgets: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        InboxWidget()
        ArtWidget()
    }
}
