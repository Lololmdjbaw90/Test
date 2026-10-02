import SwiftUI

// Your account: opens from your picture in the top left corner of every
// main page. Your profile and status, the places that aren't tabs, and
// Settings. A plain iPhone list (it scrolls, swipes down to close, and
// nothing is drawn on top of the page behind it).
struct AccountView: View {
    // Closes this sheet and opens a page on the tab you're on.
    var go: (Route) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var shop = false
    @State private var status = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    Section { profile(me) }
                }
                Section {
                    row("Music", "Songs from the community", "music.note", [0xFF7AA2, 0xD9577F]) { go(.music) }
                    row("Servers", "Group chats and voice rooms", "person.3.fill", [0xFF9EC4, 0xE0508A]) { go(.servers) }
                    row("People", "Find friends to follow", "person.crop.circle.badge.plus", [0xFFD166, 0xF08A20]) { go(.people) }
                    row("Top artists", "The community's favourites", "crown.fill", [0xFFD166, 0xF0A020]) { go(.topArtists) }
                } header: { ListHeader(title: "EXPLORE") }
                Section {
                    row("MimiPlus", "Premium looks for your profile", "sparkles", [0xC084FC, 0x8B5CF6]) { shop = true }
                    row("Commissions", "Order art or sell yours", "storefront.fill", [0x5FD3B0, 0x16A37F]) { go(.commissions) }
                } header: { ListHeader(title: "SHOP AND WORK") }
                Section {
                    row("Notifications", "Likes, follows and mentions", "bell.fill", [0xB19CFF, 0x7C5CF0]) { go(.notifications) }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        IconRow(title: "Settings", detail: "Account, privacy and colours", icon: "gearshape.fill", colors: [0x7CBEFF, 0x2F80E0])
                    }
                    row("What's new", "The latest updates", "gift.fill", [0xFF9EC4, 0xE0508A]) { go(.updates) }
                    row("Help & support", "Chat with the Sugerly team", "questionmark.bubble.fill", [0x5FD3B0, 0x16A37F]) { go(.support) }
                    if model.me?.isAdmin == true {
                        row("Admin", "Manage Sugerly", "shield.lefthalf.filled", [0xFFD166, 0xF0A020]) { go(.admin) }
                    }
                } header: { ListHeader(title: "YOU") }
                Section {
                    Toggle(isOn: darkMode) {
                        IconRow(title: "Dark mode", icon: "moon.fill", colors: [0x9D8CFF, 0x5B47D6])
                    }
                    .tint(Theme.main)
                    Button { confirmLogout = true } label: {
                        IconRow(title: "Log out", icon: "rectangle.portrait.and.arrow.right", colors: [0xB8A3AE, 0x86707C])
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sugarList()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.jakarta(16, .bold))
                }
            }
        }
        .tint(Theme.main)
        .sheet(isPresented: $shop) { NitroShopView() }
        .sheet(isPresented: $status) { StatusSheet().presentationCornerRadius(30) }
        .confirmationDialog("Log out of Sugerly?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { model.signOut() }
        }
    }

    private var darkMode: Binding<Bool> {
        Binding(get: { model.me?.theme == "dark" }, set: { on in
            Task { try? await model.updateMe(["theme": on ? "dark" : "light"]) }
        })
    }

    private func row(_ title: String, _ detail: String, _ icon: String, _ colors: [UInt32], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconRow(title: title, detail: detail, icon: icon, colors: colors, chevron: true)
        }
    }

    // You at the top: picture, name and level (opens your profile), your
    // status, and your coins / streak / following.
    @ViewBuilder
    private func profile(_ me: UserProfile) -> some View {
        let info = LevelInfo(xp: me.xp)
        let presence = Presence(rawValue: me.presence) ?? .online
        Button { go(.person(me.email)) } label: {
            HStack(spacing: 14) {
                Avatar(url: me.picture, name: me.displayName, size: 58, nitro: me.isNitro, presence: presence)
                VStack(alignment: .leading, spacing: 3) {
                    Text(me.displayName).font(.display(24)).foregroundStyle(Palette.text).lineLimit(1)
                    Text("Lv. \(info.level) · \(info.title)").font(.jakarta(12, .bold)).foregroundStyle(info.color).lineLimit(1)
                    Text("View your profile").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted.opacity(0.7))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        Button { status = true } label: {
            HStack(spacing: 10) {
                PresenceDot(presence: presence, size: 14)
                Text(me.activeStatus.isEmpty ? "\(presence.label) · set a status" : me.activeStatus)
                    .font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
            }
            .contentShape(Rectangle())
        }
        HStack(spacing: 8) {
            stat("\(me.coins)", "Coins", "circle.hexagongrid.fill", Color(hex: 0xF0A020))
            stat("\(me.dailyStreak)", "Streak", "flame.fill", Color(hex: 0xF08A20))
            stat("\(me.following.count)", "Following", "heart.fill", Theme.main)
        }
        .padding(.vertical, 4)
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
