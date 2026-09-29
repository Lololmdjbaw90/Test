import SwiftUI

enum MenuSheet: Identifiable {
    case settings, shop, status, legal(LegalDoc)
    var id: String {
        switch self {
        case .settings: return "settings"
        case .shop: return "shop"
        case .status: return "status"
        case .legal(let doc): return "legal-" + doc.rawValue
        }
    }
}

// The quick menu (your picture in the top bar): a panel that slides in from
// the side with its own scrolling, so nothing is squeezed or drawn on top of
// the page. Swipe it away, tap outside, or use the close button.
struct QuickMenu: View {
    var close: () -> Void
    var go: (Route) -> Void
    var open: (MenuSheet) -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @GestureState private var drag: CGFloat = 0

    private struct Item: Identifiable {
        var id: String { title }
        var title: String
        var detail: String
        var icon: String
        var colors: [UInt32]
        var run: () -> Void
    }

    private var explore: [Item] {
        [
            Item(title: "Music", detail: "Songs from the community", icon: "music.note", colors: [0xFF7AA2, 0xD9577F]) { go(.music) },
            Item(title: "Servers", detail: "Group chats and voice rooms", icon: "person.3.fill", colors: [0xFF9EC4, 0xE0508A]) { go(.servers) },
            Item(title: "People", detail: "Find friends to follow", icon: "person.crop.circle.badge.plus", colors: [0xFFD166, 0xF08A20]) { go(.people) },
            Item(title: "Top artists", detail: "The community's favourites", icon: "crown.fill", colors: [0xFFD166, 0xF0A020]) { go(.topArtists) },
        ]
    }

    private var shop: [Item] {
        [
            Item(title: "MimiPlus", detail: "Premium looks for your profile", icon: "sparkles", colors: [0xC084FC, 0x8B5CF6]) { open(.shop) },
            Item(title: "Commissions", detail: "Order art or sell yours", icon: "storefront.fill", colors: [0x5FD3B0, 0x16A37F]) { go(.commissions) },
        ]
    }

    private var yours: [Item] {
        var list = [
            Item(title: "Alerts", detail: "Likes, follows and mentions", icon: "bell.fill", colors: [0xB19CFF, 0x7C5CF0]) {
                close()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.showNotifications = true }
                }
            },
            Item(title: "Settings", detail: "Account, privacy and colours", icon: "gearshape.fill", colors: [0x7CBEFF, 0x2F80E0]) { open(.settings) },
            Item(title: "What's new", detail: "The latest updates", icon: "gift.fill", colors: [0xFF9EC4, 0xE0508A]) { go(.updates) },
            Item(title: "Help", detail: "Community rules and support", icon: "questionmark.circle.fill", colors: [0x5FD3B0, 0x16A37F]) { open(.legal(.guidelines)) },
        ]
        if model.me?.isAdmin == true {
            list.append(Item(title: "Admin", detail: "Manage Sugerly", icon: "shield.lefthalf.filled", colors: [0xFFD166, 0xF0A020]) { go(.admin) })
        }
        return list
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.86, 390)
            ZStack(alignment: .trailing) {
                Color.black.opacity(shown ? 0.4 : 0).ignoresSafeArea()
                    .onTapGesture(perform: close)
                panel
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 30, style: .continuous)
                            .fill(Palette.bg)
                            .shadow(color: .black.opacity(0.18), radius: 24, x: -6)
                            .ignoresSafeArea()
                    }
                    .offset(x: shown ? max(0, drag) : width + 40)
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .updating($drag) { value, state, _ in state = value.translation.width }
                            .onEnded { value in if value.translation.width > 80 || value.predictedEndTranslation.width > 200 { close() } }
                    )
            }
        }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { shown = true } }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Menu").font(.display(30)).foregroundStyle(Theme.gradient)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Palette.text2)
                        .frame(width: 38, height: 38).background(Palette.surface2, in: Circle())
                }
                .buttonStyle(BouncyStyle(scale: 0.88))
                .accessibilityLabel("Close menu")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let me = model.me { profile(me).appear(shown, 0) }
                    section("Explore", explore, from: 1)
                    section("Shop and work", shop, from: 1 + explore.count)
                    section("You", yours, from: 1 + explore.count + shop.count)
                    themeRow.appear(shown, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func section(_ title: String, _ items: [Item], from index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.jakarta(11, .heavy)).foregroundStyle(Palette.muted)
                .kerning(0.6).padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    Button(action: item.run) { row(item) }
                        .buttonStyle(RowPressStyle())
                        .appear(shown, index + i)
                    if i < items.count - 1 {
                        Divider().overlay(Palette.border).padding(.leading, 60)
                    }
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: item.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(item.detail).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.muted.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private var themeRow: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    let next = model.me?.theme == "dark" ? "light" : "dark"
                    try? await model.updateMe(["theme": next])
                }
            } label: {
                Label(model.me?.theme == "dark" ? "Light mode" : "Dark mode", systemImage: model.me?.theme == "dark" ? "sun.max.fill" : "moon.fill")
                    .font(.jakarta(13, .bold)).foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            }
            Button { open(.settings) } label: {
                Label("Colours", systemImage: "paintpalette.fill")
                    .font(.jakarta(13, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Theme.gradient, in: Capsule())
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.95))
    }

    private func profile(_ me: UserProfile) -> some View {
        let info = LevelInfo(xp: me.xp)
        return VStack(spacing: 12) {
            Button { go(.person(me.email)) } label: {
                HStack(spacing: 12) {
                    Avatar(url: me.picture, name: me.displayName, size: 54, ring: true, presence: Presence(rawValue: me.presence) ?? .online)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.displayName).font(.jakarta(18, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("Lv. \(info.level) · \(info.title)").font(.jakarta(12, .bold)).foregroundStyle(info.color).lineLimit(1)
                        Text("View profile").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.97))

            Button { open(.status) } label: {
                HStack(spacing: 8) {
                    PresenceDot(presence: Presence(rawValue: me.presence) ?? .online, size: 12)
                    Text(me.activeStatus.isEmpty ? (Presence(rawValue: me.presence) ?? .online).label + " · set a status" : me.activeStatus)
                        .font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 12).frame(height: 38)
                .background(Palette.surface2, in: Capsule())
            }
            .buttonStyle(BouncyStyle(scale: 0.97))

            HStack(spacing: 8) {
                stat("\(me.coins)", "Coins", "circle.hexagongrid.fill", Color(hex: 0xF0A020))
                stat("\(me.dailyStreak)", "Streak", "flame.fill", Color(hex: 0xF08A20))
                stat("\(me.following.count)", "Following", "heart.fill", Theme.main)
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(value).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(label).font(.jakarta(10, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// A menu row lights up softly while you press it.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.main.opacity(0.08) : .clear)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension View {
    // Rows slide in one after another when the menu opens.
    func appear(_ shown: Bool, _ index: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : 28)
            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.05 + Double(min(index, 14)) * 0.025), value: shown)
    }
}
