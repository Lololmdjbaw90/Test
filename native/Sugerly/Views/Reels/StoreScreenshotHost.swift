#if DEBUG
import SwiftUI

// Local-only marketing data, rendered by the shipping pages and controls.
// No real accounts, private conversations, or backend writes are used.
struct StoreScreenshotHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [Route] = []
    @State private var posts = PostsStore()
    @State private var chats = ChatStore()
    @State private var notes = NotificationsStore()
    @State private var player = Player()
    @State private var selection = 0
    @State private var ready = false
    static let me = "mimi@example.invalid"
    static let friend = "luna@example.invalid"
    static let conversation = Conversation(id: "store-chat", members: [me, friend], isGroup: false, groupName: "", last: nil, unread: 0)
    static var messages: [Message] {
        let lines: [(String, String)] = [
            (friend, "Hey! Did you finish your little bunny drawing?"),
            (me, "Almost!! I’m trying a softer colour palette today 🌷"),
            (friend, "Pink and peach would look so cute together"),
            (me, "That’s exactly what I was thinking ♡"),
            (friend, "Want to do a sketchbook challenge this weekend?"),
            (me, "Yes please! One tiny drawing every day?"),
            (friend, "Deal ✨ I’ll share mine in the community too"),
            (me, "Can’t wait to see it! 🎨")
        ]
        return lines.enumerated().map { i, line in
            Message(["id": "store-message-\(i)", "content": line.1, "user_email": line.0,
                     "user_display_name": line.0 == me ? "Mimi" : "Luna",
                     "created_date": Dates.iso(Date().addingTimeInterval(-Double(lines.count - i) * 90)),
                     "member_emails": [me, friend]])
        }
    }
    var body: some View {
        Group {
            if ready {
                if ProcessInfo.processInfo.arguments.contains("--store-conversation") {
                    NavigationStack {
                        ChatView(conversation: Self.conversation, loadMessages: false)
                            .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "chevron.left").foregroundStyle(Theme.main) } }
                    }
                } else if ProcessInfo.processInfo.arguments.contains("--store-bunny") {
                    NavigationStack { BunnyMakerView() }
                } else {
                    TabView(selection: $selection) {
                        NavigationStack { HomeView(path: $path, compose: { _ in }, loadContent: false) }
                            .environment(\.horizontalSizeClass, sizeClass)
                            .tabItem { Label("Home", systemImage: "house") }.tag(0)
                        NavigationStack { CommunityView(path: $path, compose: {}) }
                            .environment(\.horizontalSizeClass, sizeClass)
                            .tabItem { Label("Community", systemImage: "person.2") }.tag(1)
                        Color.clear.tabItem { Label("Fan Art", systemImage: "paintpalette") }.tag(2)
                        Color.clear.tabItem { Label("Reels", systemImage: "play.rectangle") }.tag(3)
                        NavigationStack { ChatListView(path: $path) }
                            .environment(\.horizontalSizeClass, sizeClass)
                            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(4)
                    }
                    .compactTabBar().tint(Theme.main)
                    .environment(\.horizontalSizeClass, .compact)
                }
            } else {
                ProgressView("Preparing demo")
            }
        }
        .sugarBackground()
        .preferredColorScheme(.light)
        .environment(posts).environment(chats).environment(notes).environment(player)
        .environment(VoiceEngine.shared).environment(CallCenter.shared)
        .onAppear {
            guard !ready else { return }
            Theme.accent = .rose
            model.me = UserProfile(["id": "store-mimi", "email": Self.me, "display_name": "Mimi", "coins": 1280, "xp": 340, "following": [Self.friend]])
            for name in ["Luna", "Kai", "Bea", "Milo"] {
                let email = name.lowercased() + "@example.invalid"
                model.people[email] = UserProfile(["id": "store-" + name, "email": email, "display_name": name])
            }
            posts.hasMore = false
            posts.posts = [
                Post(["id": "store-post-1", "user_email": Self.friend, "user_display_name": "Luna", "title": "Sketchbook check-in 🌷", "content": "Made time to draw today! Pink skies or peach skies? Help me choose ♡ #sketchbook", "created_date": FS.nowISO()]),
                Post(["id": "store-post-2", "user_email": "kai@example.invalid", "user_display_name": "Kai", "title": "A little progress counts", "content": "Finally finished the character sketch I’ve been working on. What are you making this week? 🎨", "created_date": FS.nowISO()]),
                Post(["id": "store-post-3", "user_email": "bea@example.invalid", "user_display_name": "Bea", "title": "Weekend art club", "content": "Anyone up for a tiny drawing challenge? One colour palette, lots of different ideas ✨", "created_date": FS.nowISO()])
            ]
            chats.conversations = ["Luna", "Kai", "Art friends", "Bea", "Milo"].enumerated().map { i, name in
                let email = name.lowercased().replacingOccurrences(of: " ", with: "") + "@example.invalid"
                let last = Message(["id": "store-last-\(i)", "user_email": email, "user_display_name": name,
                                    "content": ["Can’t wait to see your drawing! ♡", "Want to sketch together later?", "Bea: I just shared my new palette 🎨", "Thank you!! That means a lot", "Your bunny looks so cute ✨"][i],
                                    "created_date": Dates.iso(Date().addingTimeInterval(-Double(i + 1) * 180)), "member_emails": [Self.me, email]])
                return Conversation(id: "store-list-\(i)", members: [Self.me, email], isGroup: i == 2, groupName: i == 2 ? name : "", last: last, unread: i == 0 ? 2 : 0)
            }
            selection = ProcessInfo.processInfo.arguments.contains("--store-community") ? 1 : ProcessInfo.processInfo.arguments.contains("--store-chats") ? 4 : 0
            ready = true
        }
    }
}
#endif
