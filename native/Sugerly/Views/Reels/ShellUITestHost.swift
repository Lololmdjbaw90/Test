#if DEBUG
import SwiftUI

// Real dock, route wrapper and chat controls without authentication or polling.
struct ShellUITestHost: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .chat
    @State private var chatPath: [Route] = []
    @State private var chats = ChatStore()
    @State private var notes = NotificationsStore()
    @State private var typing = false
    @State private var creating = false
    private let conversation = Conversation(id: "fixture-chat", members: ["test@example.invalid", "friend@example.invalid"], isGroup: true, groupName: "Navigation test", last: nil, unread: 0)
    private let otherTabs: [(AppTab, String)] = [(.home, "Home"), (.community, "Community"), (.gallery, "Fan Art"), (.reels, "Reels"), (.me, "Profile")]

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $chatPath) {
                VStack(spacing: 20) {
                    Text("Messages").font(.display(38))
                    NavigationLink("Open test chat", value: Route.chat(conversation))
                        .buttonStyle(GradientButtonStyle(fullWidth: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sugarBackground()
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.inline)
                .sugarTopBar($chatPath)
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route, path: $chatPath, loadContent: false)
                }
            }
            .tag(AppTab.chat)
            .toolbar(.hidden, for: .tabBar)
            ForEach(otherTabs, id: \.0) { entry in
                NavigationStack {
                    Text("\(entry.1) page").font(.display(38))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).sugarBackground()
                        .toolbar(.hidden, for: .navigationBar)
                }
                .tag(entry.0)
                .toolbar(.hidden, for: .tabBar)
            }
        }
        .overlay(alignment: .bottom) {
            if !typing && (tab != .chat || chatPath.isEmpty) {
                SugarTabBar(tab: $tab, unread: 3, dark: tab == .reels) { creating = true }
                    .padding(.bottom, 2)
            }
        }
        .environment(chats).environment(notes)
        .environment(VoiceEngine.shared).environment(CallCenter.shared)
        .tint(Theme.main)
        .onAppear {
            model.me = UserProfile(["id": "fixture-user", "email": "test@example.invalid", "display_name": "Mimi"])
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
        .onChange(of: chatPath.isEmpty) { _, atRoot in if atRoot { typing = false } }
        .onChange(of: tab) { _, _ in typing = false }
        .sheet(isPresented: $creating) {
            CreateSheet { _ in creating = false }
                .presentationDetents([.height(430)]).presentationCornerRadius(34)
        }
    }
}
#endif
