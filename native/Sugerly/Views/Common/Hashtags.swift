import SwiftUI

// One set of #tags for everything: posts, reels, drawings and songs. Each
// thing saves its tags (small letters, no #) in a `tags` list, so a tag's
// page finds everything with it in one quick, indexed look-up, however many
// millions of things there are. The ranking job (scripts/rank.mjs) fills in
// tags for older things and ones made on the website, and picks the
// trending tags for everyone.
enum Hashtags {
    // #word, #word_2, #日本… : letters, numbers and _, 2 to 40 long. The
    // website and the ranking job use the same rule.
    private static let pattern = try! NSRegularExpression(pattern: "#([\\p{L}\\p{N}_]{2,40})")

    // The tags in some text, in order, without repeats (at most 10).
    static func tags(_ texts: String...) -> [String] { tags(in: texts) }

    static func tags(in texts: [String]) -> [String] {
        var out: [String] = []
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                let tag = text[r].lowercased()
                if !out.contains(tag) { out.append(tag) }
                if out.count >= 10 { return out }
            }
        }
        return out
    }

    static func find(_ text: String) -> [String] { tags(text) }

    // What someone typed ("#Cute ", "cute") as a tag ("cute"), if it is one.
    static func normalize(_ raw: String) -> String? {
        let tag = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "#" })
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }.lowercased()
        return (2...40).contains(tag.count) ? tag : nil
    }

    // Tapping a tag in any text opens its page (see MainShell).
    static func link(_ tag: String) -> URL? {
        URL(string: "sugerly://tag/" + (tag.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? tag))
    }

    static func tag(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "sugerly", url.host()?.lowercased() == "tag" else { return nil }
        return url.pathComponents.dropFirst().first.flatMap { normalize($0.removingPercentEncoding ?? $0) }
    }

    // Text with its #tags in your colour; tapping one opens its page.
    static func styled(_ text: String) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text),
                  whole.lowerBound >= cursor else { continue }
            out += AttributedString(String(text[cursor..<whole.lowerBound]))
            var piece = AttributedString(String(text[whole]))
            piece.foregroundColor = Theme.main
            piece.font = Font.jakarta(15, .bold)
            piece.link = link(text[inner].lowercased())
            out += piece
            cursor = whole.upperBound
        }
        out += AttributedString(String(text[cursor...]))
        return out
    }
}

// What's trending right now, worked out on the server from the last few
// days of posts, reels, drawings and songs (scripts/rank.mjs). One small
// read, shared by every page, refreshed at most every 10 minutes.
@MainActor
@Observable
final class TagTrends {
    static let shared = TagTrends()

    struct Item: Identifiable, Hashable {
        var tag: String
        var score: Double
        var uses: Int
        var people: Int
        var id: String { tag }
    }

    private(set) var items: [Item] = []
    @ObservationIgnored private var loadedAt: Date?

    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 600 { return }
        loadedAt = Date()
        guard let doc = try? await FS.get("SiteConfig", "trending_tags") else { return }
        // An old list (the job hasn't run for a while) isn't trending any
        // more: pages then count the tags they've loaded themselves.
        guard let updated = Dates.parse(doc.str("updated_date")), Date().timeIntervalSince(updated) < 2 * 86_400 else {
            items = []
            return
        }
        let rows = doc["tags"] as? [Any] ?? []
        items = rows.compactMap { (row: Any) -> Item? in
            guard let r = row as? [String: Any], let tag = r["tag"] as? String, !tag.isEmpty else { return nil }
            return Item(tag: tag, score: ReelText.num(r["score"]) ?? 0, uses: Int(ReelText.num(r["uses"]) ?? 0), people: Int(ReelText.num(r["people"]) ?? 0))
        }
    }
}
