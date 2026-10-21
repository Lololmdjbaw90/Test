#if DEBUG
import SwiftUI

struct AppearanceUITestHost: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var shop = false
    @State private var dark = false
    @State private var bunny = false
    @State private var creatorShop = false

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
                Button("Open bunny") { BunnyStore.shared.save(BunnyLook()); bunny = true }
                Button("Open creator shop") { creatorShop = true }
                Spacer()
            }
            .padding(16)
            .sugarBackground()
            .sheet(isPresented: $creatorShop) { BunnySaleEditor(item: BunnyItem(id: "personal-fixture", name: "My little bow", slot: .head, asset: "BunnyItemClips")) }
            .sheet(isPresented: $shop) { NitroShopView() }
            .sheet(isPresented: $bunny) { NavigationStack { BunnyMakerView() } }
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
