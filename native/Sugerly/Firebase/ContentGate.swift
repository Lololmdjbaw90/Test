import Foundation

enum ContentPolicy {
    static let lexicon: Doc = {
        guard let url = Bundle.main.url(forResource: "moderationLexicon", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONSerialization.jsonObject(with: data) as? Doc else { preconditionFailure("Missing moderation policy") }
        return value
    }()
    static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
    static func normalize(_ text: String) -> String {
        var s = text.precomposedStringWithCompatibilityMapping.lowercased()
        for (a,b) in ["а":"a", "е":"e", "і":"i", "о":"o", "р":"p", "с":"c", "х":"x", "у":"y", "ј":"j", "’":" ", "'":" "] { s = s.replacingOccurrences(of: a, with: b) }
        s = s.replacingOccurrences(of: "[\\u200B-\\u200F\\u202A-\\u202E\\u2060\\uFEFF]", with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "\\b(?:[a-z]\\s+){2,}[a-z]\\b") {
            for match in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                if let r = Range(match.range, in: s) { s.replaceSubrange(r, with: s[r].replacingOccurrences(of: "\\s", with: "", options: .regularExpression)) }
            }
        }
        return s.replacingOccurrences(of: "([a-z])\\1{2,}", with: "$1$1", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    struct Verdict { var reason = ""; var review = false; var strike = false }
    static func analyze(_ text: String, field: String) -> Verdict {
        let normalized = normalize(text)
        var leet = normalized
        for (a,b) in ["0":"o","1":"i","3":"e","4":"a","5":"s","7":"t","@":"a","$":"s","!":"i"] { leet = leet.replacingOccurrences(of: a, with: b) }
        if text.utf16.count > (lexicon["maxLength"] as? Int ?? 12000) { return Verdict(reason: "This text is too long. Please shorten it.") }
        if ["bio", "caption"].contains(field), matches("[a-z][a-z0-9+.-]*://|mailto:|www\\.|\\b[a-z0-9][a-z0-9.-]*\\.[a-z]{2,63}\\b|\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b", normalized) { return Verdict(reason: "Links aren't allowed in bios or captions.") }
        for rule in lexicon["rules"] as? [Doc] ?? [] {
            if matches(rule.str("pattern"), normalized) || matches(rule.str("pattern"), leet) { return Verdict(reason: rule.str("reason"), strike: true) }
        }
        if let regex = try? NSRegularExpression(pattern: "\\+?\\d[\\d ().-]{7,}\\d") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) { let count = text[range].filter(\.isNumber).count; if (9...19).contains(count) { return Verdict(reason: "Remove phone numbers or payment details before sharing.") } }
            }
        }
        if matches("\\b(?:i live at|my address is|abito in)\\s+\\d+", normalized) { return Verdict(reason: "Please keep home addresses private.") }
        if matches("(.)\\1{15,}", text) { return Verdict(reason: "Please remove repeated text.") }
        let remainder = leet.replacingOccurrences(of: lexicon.str("benignPattern"), with: "", options: [.regularExpression, .caseInsensitive])
        return Verdict(review: !matches(lexicon.str("supportPattern"), normalized) && matches(lexicon.str("reviewPattern"), remainder))
    }
    static func entries(_ collection: String, _ data: Doc) -> [(String,String)] {
        let fields = (lexicon["fields"] as? [String: [String]])?[collection] ?? []
        var result = fields.compactMap { key -> (String,String)? in guard let text = data[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return (key,text) }
        if collection == "Reel", let edits = data["edits"] as? Doc { for sticker in edits["text"] as? [Doc] ?? [] { if let text = sticker["text"] as? String { result.append(("sticker",text)) } } }
        return result
    }
}

actor ContentGate {
    static let shared = ContentGate()
    struct State { var next: [String:Date] = [:]; var muted = Date.distantPast; var strikes: [Date] = []; var recent: [String:(String,Date)] = [:] }
    private var states: [String:State] = [:]
    func authorize(_ collection: String, _ data: Doc, create: Bool) async throws {
        let entries = ContentPolicy.entries(collection, data)
        guard !entries.isEmpty else { return }
        let account = await MainActor.run { AuthClient.shared.email ?? "anonymous" }
        var state = states[account] ?? State()
        let kind: String? = collection.hasSuffix("Message") ? "message" : collection.hasSuffix("Comment") ? "comment" : collection == "User" ? "profile" : ["CommunityPost","Artwork","Reel","MusicReview","Commission"].contains(collection) ? "post" : nil
        let now = Date(), wait = max(state.next[kind ?? ""] ?? .distantPast, state.muted).timeIntervalSince(now)
        guard wait <= 0 else { throw APIError(message: "Please wait \(Int(ceil(wait))) seconds before writing again.") }
        let fingerprint = ContentPolicy.normalize(entries.map(\.1).joined(separator: "\n"))
        if create, kind != nil, let previous = state.recent[collection], previous.0 == fingerprint, now.timeIntervalSince(previous.1) < 30 { throw APIError(message: "You just sent this. Please avoid duplicate posts.") }
        for (field,text) in entries {
            let verdict = ContentPolicy.analyze(text, field: field)
            if !verdict.reason.isEmpty {
                if verdict.strike {
                    state.strikes.removeAll { now.timeIntervalSince($0) > 600 }; state.strikes.append(now)
                    if state.strikes.count >= 3 { state.muted = now.addingTimeInterval(Double(min(300,30*(state.strikes.count-2)))) }
                    states[account] = state
                }
                throw APIError(message: verdict.reason)
            }
            if verdict.review { throw APIError(message: "This wording could target someone. Please rephrase it. No strike was added.") }
        }
        if let kind {
            let interval = (ContentPolicy.lexicon["cooldowns"] as? Doc)?[kind] as? NSNumber
            state.next[kind] = now.addingTimeInterval((interval?.doubleValue ?? 2500) / 1000)
        }
        state.recent[collection] = (fingerprint,now); states[account] = state
    }
}
