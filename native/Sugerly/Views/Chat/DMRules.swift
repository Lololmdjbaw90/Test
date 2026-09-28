import SwiftUI

// Who can message and call whom.
//  - Friends (you follow each other) can chat, call and send voice messages.
//  - Anyone else can send you one message: a request. Until you accept it
//    they can't send more, and you only see Accept / Decline / Block.
//  - Blocking stops messages both ways.
@MainActor
enum DMRules {
    enum State: Equatable { case open, new, requestSent, requestReceived, blocked, blockedMe }

    static func friends(_ model: AppModel, _ other: String) -> Bool {
        guard let me = model.me else { return false }
        let o = other.lowercased()
        return me.following.contains(o) && (model.person(o)?.following.contains(me.email) ?? false)
    }

    static func otherEmail(_ c: Conversation, _ model: AppModel) -> String? {
        guard !c.isGroup, let me = model.me?.email else { return nil }
        return c.others(me).first
    }

    static func state(_ c: Conversation, model: AppModel, chats: ChatStore, messages: [Message] = []) -> State {
        guard let me = model.me, let other = otherEmail(c, model), other != me.email else { return .open }
        if me.blocked.contains(other) { return .blocked }
        if model.person(other)?.blocked.contains(me.email) == true { return .blockedMe }
        if friends(model, other) { return .open }
        if me.acceptedChats.contains(other) || model.person(other)?.acceptedChats.contains(me.email) == true { return .open }
        let theyWrote = chats.heard.contains(c.id) || messages.contains { $0.authorEmail == other && $0.kind != "call" }
        let iWrote = chats.wrote.contains(c.id) || messages.contains { $0.authorEmail == me.email && $0.kind != "call" }
        if theyWrote && iWrote { return .open } // a chat from before requests existed
        if theyWrote { return .requestReceived }
        if iWrote { return .requestSent }
        return .new
    }

    // Calls and voice messages: friends only (groups are always fine).
    static func canCall(_ c: Conversation, model: AppModel) -> Bool {
        guard let other = otherEmail(c, model) else { return true }
        return friends(model, other)
    }

    static let friendsOnly = "Calls and voice messages are for friends. Follow each other first."
}
