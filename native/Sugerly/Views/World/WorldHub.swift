import SwiftUI

// Sugar World's front door: your avatar, a big Play button, friends who are
// playing right now (tap Join to land in their room), and the ways to dress
// up, shop and upload clothes.
struct WorldHubView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var playing = false
    @State private var joinRoom: String?
    @State private var uploading: CatalogItem.Kind?
    @State private var online = 0
    @State private var friends: [FriendPlaying] = []
    @State private var appeared = false

    struct FriendPlaying: Identifiable, Equatable {
        var id: String { email }
        var email: String
        var name: String
        var picture: String
        var room: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                friendsSection
                tiles
                howTo
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 110)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { Palette.bg.ignoresSafeArea() }
        .roundTitle("Sugar World")
        .fullScreenCover(isPresented: $playing) { WorldPlayView(room: joinRoom) }
        .fullScreenCover(item: $uploading) { kind in ClothingStudioView(kind: kind) }
        .onChange(of: playing) { _, now in if !now { joinRoom = nil } }
        .task {
            appeared = true
            await CatalogShop.collect(model: model)
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(20))
            }
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
                Button { joinRoom = nil; playing = true } label: {
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

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Friends playing").font(.display(24)).foregroundStyle(Palette.text)
                if !friends.isEmpty {
                    Text("\(friends.count)").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Color(hex: 0x37D67A), in: Capsule())
                }
            }
            if friends.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.main)
                        .frame(width: 44, height: 44)
                        .background(Theme.soft, in: Circle())
                    Text("None of the people you follow are playing right now. When they are, they show up here with a Join button.")
                        .font(.jakarta(13)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(friends) { f in
                    HStack(spacing: 12) {
                        Avatar(url: f.picture, name: f.name, size: 46, online: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                            Text("In Sugar World · Room \(f.room.split(separator: "-").last.map(String.init) ?? "1")")
                                .font(.jakarta(12.5, .semibold)).foregroundStyle(Color(hex: 0x17A673))
                        }
                        Spacer(minLength: 6)
                        Button {
                            joinRoom = f.room
                            playing = true
                        } label: {
                            Label("Join", systemImage: "arrow.right.circle.fill")
                                .font(.jakarta(14, .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 38)
                                .background(Theme.gradient, in: Capsule())
                        }
                        .buttonStyle(BouncyStyle(scale: 0.92))
                    }
                    .padding(10)
                    .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: friends)
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("Avatar", "Skin colours, shirts, pants", "figure.stand", [0xF7A1C4, 0xE0508A]) { path.append(.avatar) }
            tile("Catalog", "Clothes people made", "bag.fill", [0xB19CFF, 0x7C5CF0]) { path.append(.catalog) }
            tile("Upload a shirt", "From the template", "tshirt.fill", [0x7CBEFF, 0x2F80E0]) { uploading = .shirt }
            tile("Upload pants", "From the template", "figure.walk", [0x5FD3B0, 0x16A37F]) { uploading = .pants }
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
            row("iphone.landscape", "Turn your phone sideways")
            row("circle.circle.fill", "Touch the left side to walk, the big button to jump")
            row("hand.draw.fill", "Drag on the right to look around, pinch to zoom")
            row("hand.wave.fill", "Wave, dance, cheer or sit with the hand button")
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

    // Who's playing now, and which of them you follow.
    private func refresh() async {
        guard let me = model.me else { return }
        let now = Date().timeIntervalSince1970 * 1000
        let docs = (try? await FS.query("WorldPresence", [.equals("world", WorldNet.world)], limit: 400)) ?? []
        let live = docs.filter { now - (ReelText.num($0["last_active"]) ?? 0) < 35_000 }
        var seen: [String: FriendPlaying] = [:]
        for d in live {
            let email = d.str("user_email").lowercased()
            guard email != me.email, me.following.contains(email), !me.blocked.contains(email) else { continue }
            seen[email] = FriendPlaying(email: email, name: d.str("name"), picture: d.str("picture"), room: d.str("room"))
        }
        let everyone = Set(live.map { $0.str("user_email").lowercased() }).count
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            online = everyone
            friends = seen.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
