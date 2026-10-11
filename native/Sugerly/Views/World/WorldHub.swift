import SwiftUI

// Sugar World's front door: your avatar, a big Play button, and the ways to
// dress up, shop and make clothes.
struct WorldHubView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var playing = false
    @State private var creating: CatalogItem.Kind?
    @State private var online = 0
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                tiles
                howTo
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { Palette.bg.ignoresSafeArea() }
        .roundTitle("Sugar World")
        .fullScreenCover(isPresented: $playing) { WorldPlayView() }
        .fullScreenCover(item: $creating) { kind in ClothingStudioView(kind: kind) }
        .task {
            appeared = true
            await CatalogShop.collect(model: model)
            await countPlayers()
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0xBFE3FF), Color(hex: 0xFFE3F0)], startPoint: .top, endPoint: .bottom)
            Circle().fill(.white.opacity(0.5)).frame(width: 220).blur(radius: 30).offset(y: -40)
            AvatarStage(look: model.me?.avatar ?? .starter, spin: true)
                .padding(.bottom, 70)
            VStack(spacing: 10) {
                if online > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0x37D67A)).frame(width: 8, height: 8)
                        Text("\(online) playing now").font(.jakarta(13, .bold)).foregroundStyle(Color(hex: 0x3A2440))
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(.white.opacity(0.8), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                }
                Button { playing = true } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(GradientButtonStyle(height: 56))
            }
            .padding(16)
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
        .shadow(color: Palette.shadow, radius: 16, y: 6)
        .stagger(appeared, 0)
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("Avatar", "Skin, clothes, faces", "figure.stand", [0xF7A1C4, 0xE0508A]) { path.append(.avatar) }
            tile("Catalog", "Clothes and hats for coins", "bag.fill", [0xB19CFF, 0x7C5CF0]) { path.append(.catalog) }
            tile("Make a shirt", "Paint your own and sell it", "tshirt.fill", [0x7CBEFF, 0x2F80E0]) { creating = .shirt }
            tile("Make pants", "Paint your own and sell it", "figure.walk", [0x5FD3B0, 0x16A37F]) { creating = .pants }
        }
    }

    private func tile(_ title: String, _ detail: String, _ icon: String, _ colors: [UInt32], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                    Text(detail).font(.jakarta(12.5)).foregroundStyle(Palette.muted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.95))
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to play").font(.display(24)).foregroundStyle(Palette.text)
            row("circle.circle.fill", "Drag the pink stick to walk")
            row("arrow.up.circle.fill", "Tap the big button to jump")
            row("hand.draw.fill", "Drag anywhere else to look around, pinch to zoom")
            row("bubble.left.fill", "Chat bubbles pop up over your head")
            row("star.fill", "Climb the candy tower for a daily star: +\(WorldRewards.coins) coins")
            row("figure.jumprope", "Bounce on the trampolines up to the cloud island")
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.main)
                .frame(width: 34, height: 34)
                .background(Theme.soft, in: Circle())
            Text(text).font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countPlayers() async {
        let now = Date().timeIntervalSince1970 * 1000
        let docs = (try? await FS.query("WorldPresence", [.equals("world", WorldNet.world)], limit: 400)) ?? []
        let live = Set(docs.filter { now - (ReelText.num($0["last_active"]) ?? 0) < 35_000 }.map { $0.str("user_email") })
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { online = live.count }
    }
}
