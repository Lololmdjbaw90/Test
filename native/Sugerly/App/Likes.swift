import Foundation
import Observation

// Likes that scale to any number of people: one Like record per person per
// post/artwork/reel ("<Collection>_<id>_<uid>") plus a like_count on the
// thing itself, changed together in one commit (the database rules check
// they match). The thing's `likes` list is only a small sample of likers,
// for faces and "liked by". Older things without a like_count yet still use
// the plain list until scripts/rank.mjs moves them over.
// Likers kept on the thing itself (faces, "liked by").
let likeSampleSize = 200

protocol Likeable {
    static var likeCollection: String { get }
    var id: String { get }
    var likes: [String] { get set }
    var likeCount: Int? { get set }
}

extension Likeable {
    var likeTotal: Int { max(likeCount ?? likes.count, 0) }

    // Flip my like locally (for instant feedback).
    mutating func setLiked(_ liking: Bool, me: String) {
        if liking {
            if !likes.contains(me), likeCount == nil || likes.count < likeSampleSize { likes.append(me) }
            if let n = likeCount { likeCount = n + 1 }
        } else {
            likes.removeAll { $0 == me }
            if let n = likeCount { likeCount = max(0, n - 1) }
        }
    }

    mutating func restoreLikes(from old: Self) {
        likes = old.likes
        likeCount = old.likeCount
    }
}

extension Post: Likeable { static let likeCollection = "CommunityPost" }
extension Artwork: Likeable { static let likeCollection = "Artwork" }
extension Reel: Likeable { static let likeCollection = "Reel" }

@MainActor
@Observable
final class LikeBook {
    static let shared = LikeBook()

    // What the database told us about things whose sample doesn't show me.
    private(set) var known: [String: Bool] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    private init() {
        NotificationCenter.default.addObserver(forName: AppModel.signingOut, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                LikeBook.shared.known = [:]
                LikeBook.shared.asked = []
            }
        }
    }

    private static func key<T: Likeable>(_ item: T) -> String { "\(T.likeCollection)_\(item.id)" }

    func isLiked<T: Likeable>(_ item: T, me: String) -> Bool {
        guard !me.isEmpty else { return false }
        // A recent unlike must win over the sample on another open screen.
        if let known = known[Self.key(item)] { return known }
        return item.likes.contains(me)
    }

    // Things liked by more people than their sample holds: ask the Like table
    // whether I'm one of them (one request for the lot).
    func prime<T: Likeable>(_ items: [T]) async {
        let me = (AuthClient.shared.email ?? "").lowercased()
        guard !me.isEmpty, let uid = AuthClient.shared.uid else { return }
        let unknown = items.filter { item in
            let key = Self.key(item)
            return known[key] == nil && !asked.contains(key) && !item.likes.contains(me) && (item.likeCount ?? 0) > item.likes.count
        }
        guard !unknown.isEmpty else { return }
        for chunk in stride(from: 0, to: unknown.count, by: 100).map({ Array(unknown[$0..<min($0 + 100, unknown.count)]) }) {
            chunk.forEach { asked.insert(Self.key($0)) }
            guard let found = try? await FS.getMany("Like", chunk.map { "\(Self.key($0))_\(uid)" }) else { continue }
            for item in chunk { known[Self.key(item)] = found["\(Self.key(item))_\(uid)"] != nil }
        }
    }

    // Save a like or unlike. `before` is the thing as it was before the tap.
    func write<T: Likeable>(_ before: T, liking: Bool, me: String, owner: String) async throws {
        let key = Self.key(before)
        let old = known[key]
        known[key] = liking
        do {
            guard before.likeCount != nil else {
                do {
                    // Not moved to the Like table yet: the list is every liker.
                    try await FS.change(T.likeCollection, before.id, [liking ? .add("likes", me) : .remove("likes", me)], set: ["updated_date": FS.nowISO()])
                } catch {
                    // Moved since this screen loaded: do it the new way.
                    guard let fresh = try? await FS.get(T.likeCollection, before.id), fresh.optInt("like_count") != nil else { throw error }
                    try await commitLike(T.likeCollection, id: before.id, sample: fresh.strs("likes").count, liking: liking, me: me, owner: owner)
                }
                return
            }
            try await commitLike(T.likeCollection, id: before.id, sample: before.likes.count, liking: liking, me: me, owner: owner)
        } catch {
            known[key] = old
            throw error
        }
    }

    // The Like record and the count, together (the rules check they match).
    private func commitLike(_ collection: String, id: String, sample: Int, liking: Bool, me: String, owner: String) async throws {
        guard let uid = AuthClient.shared.uid else { throw APIError(message: "Please log in again.") }
        let now = FS.nowISO()
        let likeId = "\(collection)_\(id)_\(uid)"
        var changes: [FS.Change] = [.increment("like_count", liking ? 1 : -1)]
        if !liking {
            changes.append(.remove("likes", me))
        } else if sample < likeSampleSize {
            changes.append(.add("likes", me))
        }
        let record: FS.Write = liking
            ? .create("Like", likeId, ["target_id": id, "target_type": collection, "user_email": me, "owner_email": owner, "created_date": now])
            : .delete("Like", likeId)
        try await FS.commit([record, .change(collection, id, changes, set: ["updated_date": now])])
    }
}
