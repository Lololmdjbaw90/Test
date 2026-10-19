#if DEBUG
import SwiftUI

struct AppearanceUITestHost: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var shop = false
    @State private var dark = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                PageTitle(title: "Community", subtitle: "Little updates. Long conversations.",
                          icon: "person.2.fill", search: $search)
                PageTitle(title: "Fan Art", subtitle: "Drawings from the community", icon: "paintpalette.fill")
                HStack {
                    Button("Rose") { Theme.accent = .rose }
                    Button("Mint") { Theme.accent = .mint }
                    Button("Dark mode") { dark.toggle() }
                }
                Button("Open MimiPlus") { shop = true }
                Spacer()
            }
            .padding(16)
            .sugarBackground()
            .sheet(isPresented: $shop) { NitroShopView() }
        }
        .preferredColorScheme(dark ? .dark : .light)
        .onAppear {
            Theme.custom = nil
            Theme.accent = .rose
            model.me = UserProfile(["id": "appearance-fixture", "email": "fixture@example.invalid",
                                    "display_name": "Luna", "coins": 0])
        }
    }
}
#endif
