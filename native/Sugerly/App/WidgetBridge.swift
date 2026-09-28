import SwiftUI
import UIKit
import WidgetKit

// Hands a small snapshot of your account (streak, coins, level, unread
// counts, a featured artwork) to the home-screen widgets through the shared
// app group, and asks iOS to redraw them.
enum WidgetBridge {
    static let group = "group.com.mimilocks.app"

    struct Snapshot: Codable, Equatable {
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
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
    private static var folder: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    nonisolated(unsafe) private static var last: Snapshot?
    nonisolated(unsafe) private static var artLoaded = Date.distantPast

    static func reload() { WidgetCenter.shared.reloadAllTimelines() }

    // Signed out: the widgets go back to their empty look.
    static func clear() {
        last = nil
        defaults?.removeObject(forKey: "snapshot")
        reload()
    }

    static func save(_ snapshot: Snapshot) {
        guard snapshot != last, let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        last = snapshot
        defaults.set(data, forKey: "snapshot")
        reload()
    }

    static func saveImage(_ image: UIImage, name: String) {
        guard let folder, let data = ImageTools.jpeg(image, maxSide: 700, quality: 0.8) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    // Everything the widgets show, from what the app already knows.
    @MainActor
    static func update(model: AppModel, unreadDMs: Int, unreadAlerts: Int) {
        guard let me = model.me else { return }
        let info = LevelInfo(xp: me.xp)
        let main = Theme.custom?.main ?? hex(model.accent.main)
        let light = Theme.custom?.light ?? hex(model.accent.light)
        var snap = last ?? Snapshot()
        snap.name = me.displayName
        snap.streak = me.dailyStreak
        snap.coins = me.coins
        snap.level = info.level
        snap.levelTitle = info.title
        snap.progress = info.progress
        snap.unreadDMs = unreadDMs
        snap.unreadAlerts = unreadAlerts
        snap.accentMain = main
        snap.accentLight = light
        snap.nitro = me.isNitro
        UserDefaults.standard.set(me.displayName, forKey: "sugerly.name")
        save(snap)
        if Date().timeIntervalSince(artLoaded) > 1800 {
            artLoaded = Date()
            Task { await loadFeatured(snap) }
        }
    }

    // The most-loved recent artwork becomes the art widget.
    @MainActor
    private static func loadFeatured(_ base: Snapshot) async {
        guard let docs = try? await FS.query("Artwork", orderBy: "created_date", limit: 30) else { return }
        let arts = docs.map(Artwork.init).filter { !$0.imageURL.isEmpty }
        guard let pick = arts.max(by: { $0.likes.count < $1.likes.count }),
              let image = await ImagePipeline.shared.load(pick.imageURL) else { return }
        saveImage(image, name: "featured.jpg")
        var snap = last ?? base
        snap.featuredTitle = pick.title
        snap.featuredArtist = pick.authorName
        last = nil
        save(snap)
    }

    private static func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(max(0, min(1, r)) * 255) << 16) | (UInt32(max(0, min(1, g)) * 255) << 8) | UInt32(max(0, min(1, b)) * 255)
    }
}
