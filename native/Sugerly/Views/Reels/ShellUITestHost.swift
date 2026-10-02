#if DEBUG
import SwiftUI

// The real tab bar, top bar, route wrapper and chat controls, without
// logging in or loading anything.
struct ShellUITestHost: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .chat
    @State private var chatPath: [Route] = []
    @State private var chats = ChatStore()
    @State private var notes = NotificationsStore()
    @State private var posts = PostsStore()
    @State private var player = Player()
    private let conversation = Conversation(id: "fixture-chat", members: ["test@example.invalid", "friend@example.invalid"], isGroup: true, groupName: "Navigation test", last: nil, unread: 0)
    private let otherTabs: [(AppTab, String, String)] = [(.home, "Home", "house"), (.community, "Community", "person.2"), (.gallery, "Fan Art", "paintpalette"), (.reels, "Reels", "play.rectangle")]

    var body: some View {
        TabView(selection: $tab) {
            ForEach(otherTabs, id: \.0) { entry in
                NavigationStack {
                    Text("\(entry.1) page").font(.display(38))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .sugarBackground()
                        .navigationTitle(entry.1)
                        .navigationBarTitleDisplayMode(.inline)
                        .rootBar()
                }
                .tabItem { Label(entry.1, systemImage: entry.2) }
                .tag(entry.0)
            }
            NavigationStack(path: $chatPath.once) {
                VStack(spacing: 20) {
                    Text("Messages").font(.display(38))
                    NavigationLink("Open test chat", value: Route.chat(conversation))
                        .buttonStyle(GradientButtonStyle(fullWidth: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sugarBackground()
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.inline)
                .rootBar()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route, path: $chatPath.once, loadContent: false)
                }
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            .badge(3)
            .tag(AppTab.chat)
        }
        .tint(Theme.main)
        .sheet(isPresented: createShown) {
            CreateSheet { _ in model.showCreate = false }
                .presentationDetents([.height(460)])
                .presentationCornerRadius(34)
        }
        .environment(chats).environment(notes).environment(posts).environment(player)
        .environment(VoiceEngine.shared).environment(CallCenter.shared)
        .onAppear {
            model.me = UserProfile(["id": "fixture-user", "email": "test@example.invalid", "display_name": "Mimi"])
        }
    }

    private var createShown: Binding<Bool> {
        Binding(get: { model.showCreate }, set: { model.showCreate = $0 })
    }
}
#endif
