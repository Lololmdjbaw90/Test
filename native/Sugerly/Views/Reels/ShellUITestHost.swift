#if DEBUG
import SwiftUI

// The real tab bar, top bar, route wrapper and chat controls, without
// logging in or loading anything.
struct ShellUITestHost: View {
    @Environment(AppModel.self) private var model
    @State private var nav = Navigator()
    @State private var chats = ChatStore()
    @State private var notes = NotificationsStore()
    @State private var posts = PostsStore()
    @State private var player = Player()
    private let conversation = Conversation(id: "fixture-chat", members: ["test@example.invalid", "friend@example.invalid"], isGroup: true, groupName: "Navigation test", last: nil, unread: 0)
    private let otherTabs: [(AppTab, String, String)] = [(.home, "Home", "house"), (.community, "Community", "person.2"), (.gallery, "Fan Art", "paintpalette"), (.reels, "Reels", "play.rectangle")]

    init() {
        let navigator = Navigator()
        navigator.tab = .chat
        _nav = State(initialValue: navigator)
    }

    var body: some View {
        TabView(selection: Binding(get: { nav.tab }, set: { nav.tab = $0 })) {
            ForEach(otherTabs, id: \.0) { entry in
                NavigationStack(path: nav.path(entry.0)) {
                    VStack(spacing: 20) {
                        Text("\(entry.1) page").font(.display(38))
                        Button("Open settings") { nav.push(.settings) }
                        Button("Open saved profile") { nav.push(.person("saved@example.invalid")) }
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .sugarBackground()
                        .navigationTitle(entry.1)
                        .navigationBarTitleDisplayMode(.inline)
                        .rootBar()
                        .navigationDestination(for: Route.self) { route in
                            destination(route, on: entry.0)
                        }
                }
                .tabPageEntrance(active: nav.tab == entry.0)
                .tabItem { Label(entry.1, systemImage: entry.2) }
                .tag(entry.0)
            }
            NavigationStack(path: nav.path(.chat)) {
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
                    destination(route, on: .chat)
                }
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            .badge(3)
            .tag(AppTab.chat)
        }
        .overlay {
            MenuDrawer(open: Binding(get: { model.showMenu }, set: { model.showMenu = $0 })) { route in
                model.showMenu = false
                nav.push(route)
            }
        }
        .compactTabBar()
        .tint(Theme.main)
        .sheet(isPresented: createShown) {
            CreateSheet { _ in model.showCreate = false }
                .presentationDetents([.height(460)])
                .presentationCornerRadius(34)
        }
        .environment(chats).environment(notes).environment(posts).environment(player)
        .environment(VoiceEngine.shared).environment(CallCenter.shared)
        .onChange(of: model.showNotifications) { _, show in
            guard show else { return }
            model.showNotifications = false
            nav.push(.notifications)
        }
        .onAppear {
            model.me = UserProfile(["id": "fixture-user", "email": "test@example.invalid", "display_name": "Mimi"])
            notes.items = [AppNotification([
                "id": "fixture-notification", "type": "mention", "message": "Navigation notification",
                "from_display_name": "Luna", "from_email": "friend@example.invalid",
                "link": "/profile?email=notification@example.invalid", "is_read": true,
                "created_date": Dates.iso(Date())
            ])]
        }
    }

    @ViewBuilder
    private func destination(_ route: Route, on tab: AppTab) -> some View {
        if case .person(let email) = route {
            // Keep profile destinations local; Settings, its nested Hidden
            // words link, Notifications and the Navigator are the real views.
            VStack(spacing: 20) {
                Text(email == "saved@example.invalid" ? "Saved profile page" : "Notification profile page")
                Button("Open settings") { nav.push(.settings) }
                Button("Switch to Home") { nav.tab = .home }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sugarBackground()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .rootBar()
        } else {
            RouteView(route: route, path: nav.path(tab), loadContent: false)
        }
    }

    private var createShown: Binding<Bool> {
        Binding(get: { model.showCreate }, set: { model.showCreate = $0 })
    }
}
#endif
