import Foundation

// Chats kept on the phone (per account): the latest messages of each chat
// and your whole chat list. Opening a chat is instant and only asks the
// server for what's new, and old chats never drop off the list however long
// the history gets.
enum ChatCache {
    private static var root: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(Drafts.owner, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ name: String) -> URL {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return root.appendingPathComponent(String(safe) + ".json")
    }

    static func read(_ name: String) -> [Doc] {
        guard let data = try? Data(contentsOf: file(name)),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list
    }

    static func write(_ name: String, _ docs: [Doc]) {
        let clean = docs.filter { JSONSerialization.isValidJSONObject($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: clean) else { return }
        let target = file(name)
        DispatchQueue.global(qos: .utility).async { try? data.write(to: target, options: .atomic) }
    }

    // Messages of one chat: the newest ones (enough to open instantly).
    static func messages(_ conversationId: String) -> [Message] {
        read("dm-" + conversationId).map(Message.init).sorted { $0.created < $1.created }
    }

    static func save(_ conversationId: String, _ messages: [Message]) {
        let keep = messages.filter { !$0.pending }.suffix(400)
        write("dm-" + conversationId, keep.map(\.cacheDoc))
    }
}
