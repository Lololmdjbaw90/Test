import SwiftUI

// Chat streaks, like TikTok's: how many days in a row you and a friend have
// both written to each other in your one-to-one chat. It's worked out on the
// phone from the messages the chat list and your chats already load, keeping
// the days each side wrote (saved on the phone, per account). A streak shows
// from 3 days. Until you've both written today it waits with an hourglass;
// miss a whole day and it starts again.
@MainActor
@Observable
final class ChatStreaks {
    static let shared = ChatStreaks()

    struct Streak: Equatable {
        let days: Int
        // You've both written today (otherwise it ends at midnight).
        let today: Bool
    }

    // Shown from this many days in a row.
    static let shows = 3

    // Bumped whenever a day is added, so the badges redraw.
    private(set) var version = 0

    // Per chat: the days you wrote, the days they wrote ("2026-10-18"), and
    // the day from which every message is known (older ones are fetched
    // once when a streak might go back further).
    @ObservationIgnored private var mine: [String: Set<String>] = [:]
    @ObservationIgnored private var theirs: [String: Set<String>] = [:]
    @ObservationIgnored private var fullFrom: [String: String] = [:]
    @ObservationIgnored private var runs: [String: (key: String, run: Run?)] = [:]
    @ObservationIgnored private var owner = ""
    @ObservationIgnored private var saving = false
    @ObservationIgnored private var deepened = Set<String>()

    private struct Run {
        let days: Int
        let today: Bool
        let start: String
    }

    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ date: Date) -> String { format.string(from: date) }

    private static func shift(_ day: String, by days: Int) -> String {
        guard let date = format.date(from: day),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: date) else { return day }
        return Self.day(moved)
    }

    // MARK: reading

    func streak(_ id: String) -> Streak? {
        _ = version
        guard let run = run(id), run.days >= Self.shows else { return nil }
        return Streak(days: run.days, today: run.today)
    }

    private func run(_ id: String) -> Run? {
        load()
        let today = Self.day(Date())
        let key = "\(today)|\(version)"
        if let hit = runs[id], hit.key == key { return hit.run }
        var result: Run?
        if let a = mine[id], let b = theirs[id] {
            let both = { (d: String) in a.contains(d) && b.contains(d) }
            let done = both(today)
            var day = done ? today : Self.shift(today, by: -1)
            var count = 0
            var start = day
            while both(day) && count < 5000 {
                count += 1
                start = day
                day = Self.shift(day, by: -1)
            }
            if count > 0 { result = Run(days: count, today: done, start: start) }
        }
        runs[id] = (key, result)
        return result
    }

    // MARK: writing

    // Messages seen anywhere (the chat list, a chat): one-to-one chats only,
    // not call logs or ones still sending.
    func note(_ messages: [Message], me: String) {
        guard !me.isEmpty else { return }
        load()
        var changed = false
        for m in messages where !m.isGroup && m.kind != "call" && !m.pending && !m.conversationId.isEmpty {
            guard let date = Dates.parse(m.created) else { continue }
            let d = Self.day(date)
            let id = m.conversationId
            if m.authorEmail == me {
                if !(mine[id]?.contains(d) ?? false) { mine[id, default: []].insert(d); changed = true }
            } else if !(theirs[id]?.contains(d) ?? false) {
                theirs[id, default: []].insert(d)
                changed = true
            }
        }
        guard changed else { return }
        version += 1
        scheduleSave()
    }

    // A fresh phone only has the newest messages, so a long streak would
    // look short: for chats whose streak reaches back to the oldest day we
    // know, fetch older messages (a few pages at most, once per launch).
    func deepen(_ conversations: [Conversation], me: String) async {
        for c in conversations.filter({ !$0.isGroup }).prefix(12) {
            await deepen(c, me: me)
        }
    }

    func deepen(_ c: Conversation, me: String) async {
        guard !c.isGroup, !me.isEmpty, !deepened.contains(c.id) else { return }
        deepened.insert(c.id)
        var cutoff: String?
        for _ in 0..<4 {
            guard let run = run(c.id) else { return }
            if let full = fullFrom[c.id], full < run.start { return }
            let before = cutoff ?? Self.format.date(from: run.start).map(Dates.iso) ?? FS.nowISO()
            let page = 300
            guard let docs = try? await FS.query("DirectMessage", [.equals("conversation_id", c.id), .contains("member_emails", me), .before("created_date", before)],
                                                 orderBy: "created_date", limit: page) else { return }
            let batch = docs.map(Message.init)
            note(batch, me: me)
            if docs.count < page {
                fullFrom[c.id] = "0000-00-00"
                scheduleSave()
                return
            }
            // Everything after the oldest day fetched is now known.
            guard let oldest = batch.map(\.created).filter({ !$0.isEmpty }).min(), let date = Dates.parse(oldest) else { return }
            fullFrom[c.id] = Self.shift(Self.day(date), by: 1)
            cutoff = oldest
            version += 1
            scheduleSave()
        }
    }

    // MARK: saving

    private func load() {
        guard owner != Drafts.owner else { return }
        owner = Drafts.owner
        mine = [:]
        theirs = [:]
        fullFrom = [:]
        runs = [:]
        deepened = []
        for d in ChatCache.read("streaks") {
            guard let id = d["id"] as? String else { continue }
            let a = d.strs("mine"), b = d.strs("theirs")
            if !a.isEmpty { mine[id] = Set(a) }
            if !b.isEmpty { theirs[id] = Set(b) }
            if let full = d["full"] as? String { fullFrom[id] = full }
        }
    }

    private func scheduleSave() {
        guard !saving else { return }
        saving = true
        let account = owner
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            saving = false
            guard account == owner, owner == Drafts.owner else { return }
            save()
        }
    }

    // Only what a streak can still need: the last two weeks, or back to a
    // week before the current streak began.
    private func save() {
        let floor = Self.shift(Self.day(Date()), by: -14)
        var list: [Doc] = []
        for id in Set(mine.keys).union(theirs.keys) {
            var keep = floor
            if let run = run(id) { keep = min(floor, Self.shift(run.start, by: -7)) }
            let a = (mine[id] ?? []).filter { $0 >= keep }
            let b = (theirs[id] ?? []).filter { $0 >= keep }
            if a.isEmpty && b.isEmpty { continue }
            var d: Doc = ["id": id, "mine": Array(a), "theirs": Array(b)]
            if let full = fullFrom[id] { d["full"] = max(full, keep) }
            list.append(d)
        }
        ChatCache.write("streaks", list)
    }
}

// The streak by a chat's name: a flame and the days, or an hourglass when
// you haven't both written today yet.
struct StreakBadge: View {
    let streak: ChatStreaks.Streak
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: size + 1, weight: .bold))
                .foregroundStyle(streak.today
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFC14D), Color(hex: 0xFF6A3D), Color(hex: 0xF0447F)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Palette.muted.opacity(0.7)))
            Text("\(streak.days)")
                .font(.jakarta(size, .heavy))
                .foregroundStyle(streak.today ? Color(hex: 0xF0602F) : Palette.muted)
                .monospacedDigit()
                .contentTransition(.numericText())
            if !streak.today {
                Image(systemName: "hourglass")
                    .font(.system(size: size - 1, weight: .bold))
                    .foregroundStyle(Color(hex: 0xF0A020))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.days)-day chat streak\(streak.today ? "" : ", write today to keep it")")
    }
}

// The little celebration in a chat when today's streak day is done.
struct StreakCheer: View {
    let days: Int

    var body: some View {
        HStack(spacing: 8) {
            Image("MimiSparkle").resizable().scaledToFit().frame(width: 20, height: 22)
            Image(systemName: "flame.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFC14D), Color(hex: 0xFF6A3D), Color(hex: 0xF0447F)], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, value: days)
            Text("\(days)-day streak!").font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
            Text("See you tomorrow").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Palette.surface.opacity(0.8)))
                .shadow(color: Color(hex: 0xFF6A3D).opacity(0.22), radius: 12, y: 4)
        }
        .overlay(Capsule().strokeBorder(Color(hex: 0xFFB487).opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// In an open chat: notes messages as they arrive (just the newest ones for
// a new message, all of them after a page loads), fetches older days for a
// long streak, and cheers when today's streak day gets done right then.
struct StreakWatch: ViewModifier {
    let conversation: Conversation
    let messages: [Message]
    let me: String
    var enabled = true
    @State private var cheer: Int?
    // Settled enough that a finished day is news (not just loading in).
    @State private var settled = false

    private var streak: ChatStreaks.Streak? {
        conversation.isGroup ? nil : ChatStreaks.shared.streak(conversation.id)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let cheer {
                    StreakCheer(days: cheer)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.success, trigger: cheer) { _, new in new != nil }
            .onChange(of: messages.count) { old, new in
                ChatStreaks.shared.note(old == 0 || new - old > 20 ? messages : Array(messages.suffix(20)), me: me)
            }
            .onChange(of: streak) { old, new in celebrate(old, new) }
            .task {
                guard enabled, !conversation.isGroup else { return }
                try? await Task.sleep(for: .seconds(3))
                settled = true
                await ChatStreaks.shared.deepen(conversation, me: me)
            }
    }

    private func celebrate(_ old: ChatStreaks.Streak?, _ new: ChatStreaks.Streak?) {
        guard settled, let new, new.today, !(old?.today ?? false) else { return }
        guard let last = messages.last.flatMap({ Dates.parse($0.created) }), Date().timeIntervalSince(last) < 30 else { return }
        withAnimation(Motion.pick(.spring(response: 0.45, dampingFraction: 0.75))) { cheer = new.days }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            withAnimation(Motion.pick(Motion.settle)) { cheer = nil }
        }
    }
}
