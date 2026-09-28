import Foundation
import NaturalLanguage

// The For You brain. It runs on the phone and learns what you like from how
// you watch: finishing or re-watching a reel, likes, saves, comments and
// follows push its topics and creator up; quick skips push them down.
//
// Ranking mixes:
//  - meaning: a sentence embedding (Apple's on-device language model) of each
//    caption, compared with the average of the reels you enjoyed
//  - topics: learned weights for hashtags, words, sounds and artists
//  - creator affinity and who you follow
//  - popularity (like rate, views) and freshness
//  - a little exploration, a penalty for things you've already seen, and
//    variety (never the same creator back to back)
//
// Reels are fetched page by page (newest first, with a cursor), so the feed
// never loads the whole collection however many videos there are.
actor ReelBrain {
    static let shared = ReelBrain()

    private var topics: [String: Double] = [:]
    private var authors: [String: Double] = [:]
    private var profile: [Double] = []
    private var seen: [String: Double] = [:]
    private var vectors: [String: [Double]] = [:]
    private var embedder: NLEmbedding?
    private var embedderLoaded = false
    private var saveTask: Task<Void, Never>?

    private static let key = "sugerly.reelbrain.v1"
    private static let stop: Set<String> = ["this", "that", "with", "have", "just", "from", "your", "what", "when", "they", "them", "then", "there", "their", "about", "would", "could", "should", "really", "very", "been", "were", "will", "into", "like", "more", "some", "here", "also", "only", "over", "such", "than", "much", "make", "made"]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            topics = saved.topics
            authors = saved.authors
            profile = saved.profile
            seen = saved.seen
        }
    }

    private struct Saved: Codable {
        var topics: [String: Double]
        var authors: [String: Double]
        var profile: [Double]
        var seen: [String: Double]
    }

    // MARK: Learning

    func watched(_ reel: Reel, seconds: Double) {
        let length = reel.duration > 0 ? reel.duration : (reel.isVideo ? 15 : Double(max(1, reel.pictures.count)) * 3)
        let ratio = seconds / max(1, length)
        let signal: Double
        if seconds < 1.5 { signal = -0.5 }
        else if ratio >= 1.8 { signal = 1.1 }           // watched it twice
        else if ratio >= 0.9 { signal = 0.7 }           // finished
        else { signal = ratio * 0.6 - 0.15 }
        seen[reel.id] = Date().timeIntervalSince1970
        learn(reel, signal)
    }

    func liked(_ reel: Reel, _ on: Bool) { learn(reel, on ? 1.2 : -0.6) }
    func saved(_ reel: Reel, _ on: Bool) { learn(reel, on ? 1.4 : -0.4) }
    func commented(_ reel: Reel) { learn(reel, 0.8) }
    func notInterested(_ reel: Reel) {
        seen[reel.id] = Date().timeIntervalSince1970
        learn(reel, -1.6)
    }
    func followed(_ email: String) {
        authors[email] = min(5, (authors[email] ?? 0) + 1.5)
        scheduleSave()
    }

    private func learn(_ reel: Reel, _ signal: Double) {
        let rate = 0.18
        for t in Self.tokens(reel) {
            topics[t] = max(-3, min(4, (topics[t] ?? 0) + rate * signal))
        }
        authors[reel.authorEmail] = max(-3, min(5, (authors[reel.authorEmail] ?? 0) + rate * signal * 1.4))
        if signal > 0, let v = vector(reel) {
            if profile.count != v.count { profile = v } else {
                let w = min(0.35, 0.12 * signal)
                profile = zip(profile, v).map { $0 * (1 - w) + $1 * w }
            }
        }
        // Keep the memory small: forget the weakest topics and oldest views.
        if topics.count > 600 {
            let keep = topics.sorted { abs($0.value) > abs($1.value) }.prefix(450)
            topics = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if seen.count > 4000 {
            let keep = seen.sorted { $0.value > $1.value }.prefix(3000)
            seen = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() {
        let saved = Saved(topics: topics, authors: authors, profile: profile, seen: seen)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: Ranking

    func rank(_ reels: [Reel], me: String, following: Set<String>, recent: [String] = []) -> [Reel] {
        let now = Date()
        var pool = reels.map { ($0, score($0, now: now, me: me, following: following)) }.sorted { $0.1 > $1.1 }
        var out: [Reel] = []
        var lastAuthors = recent.suffix(2)
        while !pool.isEmpty {
            let recentSet = Set(lastAuthors)
            let pick = pool.prefix(8).firstIndex { !recentSet.contains($0.0.authorEmail) } ?? 0
            let reel = pool.remove(at: pick).0
            out.append(reel)
            lastAuthors.append(reel.authorEmail)
            lastAuthors = lastAuthors.suffix(2)
        }
        return out
    }

    private func score(_ r: Reel, now: Date, me: String, following: Set<String>) -> Double {
        let hours = max(0, now.timeIntervalSince(Dates.parse(r.created) ?? now) / 3600)
        let likes = Double(r.likeTotal)
        let views = Double(r.views)
        var s = log1p(likes * 4 + views) * 0.55
        s += (likes + 1) / (views + 4) * 2.5
        // What everyone else thought, scored on the server with comments too
        // (its score minus its newness part, which is added below).
        if let rank = r.rankScore, let made = Dates.parse(r.created) {
            s += max(0, rank - (made.timeIntervalSince1970 - 1.7e9) / 45_000) * 0.45
        }
        s += 4 / pow(hours + 2, 0.4)
        // Brand-new reels get a push so they reach people quickly.
        if hours < 6 { s += 2.5 * (1 - hours / 6) }

        let topicScore = Self.tokens(r).reduce(0) { $0 + (topics[$1] ?? 0) }
        s += tanh(topicScore / 2) * 2.6
        if !profile.isEmpty, let v = vector(r), v.count == profile.count {
            s += Self.cosine(v, profile) * 3.2
        }
        s += tanh((authors[r.authorEmail] ?? 0) / 2) * 2.2
        if following.contains(r.authorEmail) { s += 1.1 }
        if r.authorEmail == me && hours > 1 { s -= 3 } // your own, unless you just posted it
        if let last = seen[r.id] {
            let ago = (now.timeIntervalSince1970 - last) / 3600
            s -= ago < 24 ? 7 : 3.5
        }
        s += Double.random(in: 0...0.9)
        return s
    }

    // MARK: Features

    private func vector(_ r: Reel) -> [Double]? {
        if let hit = vectors[r.id] { return hit.isEmpty ? nil : hit }
        let text = (r.caption + " " + r.musicTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { vectors[r.id] = []; return nil }
        if !embedderLoaded {
            embedderLoaded = true
            embedder = NLEmbedding.sentenceEmbedding(for: .english)
        }
        let v = embedder?.vector(for: text) ?? []
        if vectors.count > 3000 { vectors.removeAll() }
        vectors[r.id] = v
        return v.isEmpty ? nil : v
    }

    static func tokens(_ r: Reel) -> [String] {
        var out: [String] = []
        for raw in r.caption.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "." || $0 == "!" || $0 == "?" }) {
            let word = String(raw)
            if word.hasPrefix("#") && word.count > 1 { out.append(word) }
            else {
                let clean = word.filter { $0.isLetter }
                if clean.count >= 4 && !stop.contains(clean) { out.append(clean) }
            }
            if out.count >= 12 { break }
        }
        if !r.musicArtist.isEmpty { out.append("artist:" + r.musicArtist.lowercased()) }
        if !r.musicTitle.isEmpty { out.append("sound:" + r.musicTitle.lowercased()) }
        out.append(r.isVideo ? "kind:video" : "kind:photos")
        return out
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }
}
