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

// The quick menu under your picture in the top bar. It's a light card drawn
// right in the app (no sheet, no big blurs or stacked shadows), so it pops
// open instantly even while music and animations are running.
struct QuickMenu: View {
    var close: () -> Void
    var go: (Route) -> Void
    var open: (MenuSheet) -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false

    private struct Item: Identifiable {
        var id: String { title }
        var title: String
        var icon: String
        var colors: [UInt32]
        var run: () -> Void
    }

    private var items: [Item] {
        var list: [Item] = [
            Item(title: "MimiPlus", icon: "sparkles", colors: [0xC084FC, 0x8B5CF6]) { open(.shop) },
            Item(title: "Music", icon: "music.note", colors: [0xFF7AA2, 0xD9577F]) { go(.music) },
            Item(title: "Servers", icon: "person.3.fill", colors: [0xFF9EC4, 0xE0508A]) { go(.servers) },
            Item(title: "People", icon: "person.crop.circle.badge.plus", colors: [0xFFD166, 0xF08A20]) { go(.people) },
            Item(title: "Top artists", icon: "crown.fill", colors: [0xFFD166, 0xF0A020]) { go(.topArtists) },
            Item(title: "Commissions", icon: "storefront.fill", colors: [0x5FD3B0, 0x16A37F]) { go(.commissions) },
            Item(title: "What's new", icon: "gift.fill", colors: [0xFF9EC4, 0xE0508A]) { go(.updates) },
            Item(title: "Alerts", icon: "bell.fill", colors: [0xB19CFF, 0x7C5CF0]) {
                close()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.showNotifications = true }
                }
            },
            Item(title: "Settings", icon: "gearshape.fill", colors: [0x7CBEFF, 0x2F80E0]) { open(.settings) },
            Item(title: "Help", icon: "questionmark.circle.fill", colors: [0x5FD3B0, 0x16A37F]) { open(.legal(.guidelines)) },
        ]
        if model.me?.isAdmin == true {
            list.append(Item(title: "Admin", icon: "shield.lefthalf.filled", colors: [0xFFD166, 0xF0A020]) { go(.admin) })
        }
        return list
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.22).ignoresSafeArea()
                .onTapGesture(perform: close)
            card
                .frame(maxWidth: 390)
                .padding(.horizontal, 12)
                .padding(.top, 58)
                .scaleEffect(shown ? 1 : 0.82, anchor: .topTrailing)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { shown = true } }
    }

    private var card: some View {
        VStack(spacing: 14) {
            if let me = model.me { profile(me) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    Button(action: item.run) {
                        VStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(LinearGradient(colors: item.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            Text(item.title).font(.jakarta(11, .bold)).foregroundStyle(Palette.text2)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.88))
                    .scaleEffect(shown ? 1 : 0.5)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.7).delay(0.04 + Double(i) * 0.022), value: shown)
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task {
                        let next = model.me?.theme == "dark" ? "light" : "dark"
                        try? await model.updateMe(["theme": next])
                    }
                } label: {
                    Label(model.me?.theme == "dark" ? "Light mode" : "Dark mode", systemImage: model.me?.theme == "dark" ? "sun.max.fill" : "moon.fill")
                        .font(.jakarta(13, .bold)).foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Palette.surface2, in: Capsule())
                }
                Button { open(.settings) } label: {
                    Label("Colours", systemImage: "paintpalette.fill")
                        .font(.jakarta(13, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Theme.gradient, in: Capsule())
                }
            }
            .buttonStyle(BouncyStyle(scale: 0.95))
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Theme.main.opacity(0.2), radius: 22, y: 12)
    }

    private func profile(_ me: UserProfile) -> some View {
        let info = LevelInfo(xp: me.xp)
        return Button { go(.person(me.email)) } label: {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Avatar(url: me.picture, name: me.displayName, size: 50, ring: true, presence: Presence(rawValue: me.presence) ?? .online)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.displayName).font(.jakarta(17, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("Lv. \(info.level) · \(info.title)").font(.jakarta(12, .bold)).foregroundStyle(info.color)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.muted)
                }
                Button { open(.status) } label: {
                    HStack(spacing: 8) {
                        PresenceDot(presence: Presence(rawValue: me.presence) ?? .online, size: 14)
                        Text(me.activeStatus.isEmpty ? (Presence(rawValue: me.presence) ?? .online).label + " · set a status" : me.activeStatus)
                            .font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Palette.surface, in: Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.97))
                HStack(spacing: 6) {
                    stat("\(me.coins)", "Coins", "circle.hexagongrid.fill", Color(hex: 0xF0A020))
                    stat("\(me.dailyStreak)", "Streak", "flame.fill", Color(hex: 0xF08A20))
                    stat("\(me.following.count)", "Following", "heart.fill", Theme.main)
                }
            }
            .padding(12)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.jakarta(13, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                Text(label).font(.jakarta(9, .semibold)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
