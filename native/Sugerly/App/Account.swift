import SwiftUI

// The menu: opens from your picture in the top left corner of every main
// page. You at the top (profile, level, status, coins), your wallet and
// MimiPlus, the places that aren't tabs as a tidy list, then Settings and
// help, and dark mode and Log out at the bottom. Swipe down or tap Done to close it.
struct AccountView: View {
    // Closes the menu and opens a page on the tab you're on.
    var go: (Route) -> Void
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shop = false
    @State private var wallet = false
    @State private var status = false
    @State private var confirmLogout = false
    @State private var shown = false

    private struct Place: Identifiable {
        let title: String
        let detail: String
        let icon: String
        let colors: [UInt32]
        let action: () -> Void
        var id: String { title }
    }

    // The places that aren't tabs.
    private var places: [Place] {
        [
            Place(title: "Music", detail: "Songs from the community", icon: "music.note", colors: [0xFF7AA2, 0xD9577F]) { go(.music) },
            Place(title: "Servers", detail: "Group chats with channels and voice", icon: "person.3.fill", colors: [0x7CBEFF, 0x2F80E0]) { go(.servers) },
            Place(title: "People", detail: "Find friends and artists", icon: "person.crop.circle.badge.plus", colors: [0xFFB86B, 0xF0802A]) { go(.people) },
            Place(title: "Top artists", detail: "This week's most loved", icon: "crown.fill", colors: [0xFFD166, 0xE9A100]) { go(.topArtists) },
            Place(title: "Commissions", detail: "Order art or sell yours", icon: "storefront.fill", colors: [0x5FD3B0, 0x16A37F]) { go(.commissions) },
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let me = model.me { profileCard(me) }
                    walletCard
                    placesGrid
                    youCard
                    endCard
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .sugarBackground()
            .roundTitle("Menu")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.jakarta(16, .bold))
                }
            }
        }
        .tint(Theme.main)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $shop) { NitroShopView() }
        .sheet(isPresented: $wallet) { WalletView() }
        .sheet(isPresented: $status) { StatusSheet().presentationCornerRadius(30) }
        .confirmationDialog("Log out of Sugerly?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { model.signOut() }
        }
        .onAppear { shown = true }
    }

    // Notifications, Settings, what's new and help.
    private var youCard: some View {
        card("YOU") {
            notificationsRow
            divider
            NavigationLink {
                SettingsView()
            } label: {
                rowLabel("Settings", "Account, privacy and colours", "gearshape.fill", [0x8FA3B8, 0x5B6B80])
            }
            .buttonStyle(RowPressStyle())
            divider
            row("What's new", "The latest updates", "gift.fill", [0xFF9EC4, 0xE0508A]) { go(.updates) }
            divider
            row("Help & support", "Chat with the Sugerly team", "questionmark.bubble.fill", [0x5FD3B0, 0x16A37F]) { go(.support) }
            if model.me?.isAdmin == true {
                divider
                row("Admin", "Manage Sugerly", "shield.lefthalf.filled", [0xFFD166, 0xF0A020]) { go(.admin) }
            }
        }
    }

    // With a pink count of the new ones.
    private var notificationsRow: some View {
        Button { go(.notifications) } label: {
            HStack(spacing: 8) {
                IconRow(title: "Notifications", detail: "Likes, follows and mentions", icon: "bell.fill", colors: [0xB19CFF, 0x7C5CF0])
                if notes.unread > 0 {
                    Text("\(notes.unread)")
                        .font(.jakarta(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(minWidth: 24, minHeight: 22)
                        .background(Theme.main, in: Capsule())
                }
                chevron
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityValue(notes.unread > 0 ? "\(notes.unread) new" : "")
    }

    // Dark mode and Log out.
    private var endCard: some View {
        card(nil) {
            Toggle(isOn: darkMode) {
                IconRow(title: "Dark mode", icon: "moon.fill", colors: [0x9D8CFF, 0x5B47D6])
            }
            .tint(Theme.main)
            .padding(.horizontal, 14).padding(.vertical, 9)
            divider
            Button { confirmLogout = true } label: {
                IconRow(title: "Log out", icon: "rectangle.portrait.and.arrow.right", colors: [0xF07A8E, 0xD9455F], danger: true)
                    .padding(.horizontal, 14).padding(.vertical, 9)
            }
            .buttonStyle(RowPressStyle())
        }
    }

    private var darkMode: Binding<Bool> {
        Binding(get: { model.me?.theme == "dark" }, set: { on in
            TapSound.play(on ? .toggle : .toggleOff)
            Task { try? await model.updateMe(["theme": on ? "dark" : "light"]) }
        })
    }

    // MARK: you

    // Your picture, name and level (opens your profile), how far you are to
    // the next level, your status, and your coins / streak / following.
    private func profileCard(_ me: UserProfile) -> some View {
        let info = LevelInfo(xp: me.xp)
        let presence = Presence(rawValue: me.presence) ?? .online
        return VStack(spacing: 14) {
            profileButton(me, info, presence)
            XPBar(info: info)
            statusButton(me, presence)
            HStack(spacing: 8) {
                Button { wallet = true } label: {
                    stat("\(me.coins)", "Coins", "circle.hexagongrid.fill", Color(hex: 0xE09A1A))
                }
                .buttonStyle(SoftPressStyle())
                stat("\(me.dailyStreak)", "Day streak", "flame.fill", Color(hex: 0xF08A20))
                stat("\(me.following.count)", "Following", "heart.fill", Theme.main)
            }
        }
        .sugarCard(radius: 26, padding: 16)
        .opacity(shown || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: shown)
    }

    private func profileButton(_ me: UserProfile, _ info: LevelInfo, _ presence: Presence) -> some View {
        Button { go(.person(me.email)) } label: {
            HStack(spacing: 14) {
                Avatar(url: me.picture, name: me.displayName, size: 64, nitro: me.isNitro, presence: presence)
                VStack(alignment: .leading, spacing: 6) {
                    Text(me.displayName)
                        .font(.display(26)).foregroundStyle(Palette.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Lv. \(info.level) · \(info.title)")
                        .font(.jakarta(12, .heavy)).foregroundStyle(info.color)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(info.color.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    Text("Profile").font(.jakarta(13, .bold))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(Theme.main)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(me.displayName), level \(info.level) \(info.title)")
        .accessibilityHint("Opens your profile")
        .accessibilityAddTraits(.isButton)
    }

    private func statusButton(_ me: UserProfile, _ presence: Presence) -> some View {
        let text = me.activeStatus.isEmpty ? "\(presence.label) · tap to set a status" : me.activeStatus
        return Button { status = true } label: {
            HStack(spacing: 10) {
                PresenceDot(presence: presence, size: 12)
                Text(text)
                    .font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Palette.surface2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
        .accessibilityLabel("Status")
        .accessibilityValue(me.activeStatus.isEmpty ? presence.label : me.activeStatus)
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(value).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(label).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: places

    // The places that aren't tabs, as a tidy list.
    private var placesGrid: some View {
        card("EXPLORE") {
            ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                if i > 0 { divider }
                Button(action: place.action) {
                    HStack(spacing: 8) {
                        IconRow(title: place.title, detail: place.detail, icon: place.icon, colors: place.colors)
                        chevron
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(place.title)
            }
        }
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : Motion.enter.delay(0.06), value: shown)
    }

    // Coins and MimiPlus together, with what they are in plain words.
    private var walletCard: some View {
        card("COINS & MIMIPLUS") {
            row("Wallet", "\(model.me?.coins ?? 0) coins · how to earn more", "circle.hexagongrid.fill", [0xFFD166, 0xE09A1A]) { wallet = true }
            divider
            row("MimiPlus", model.me?.isNitro == true ? "Active · extra looks for your profile" : "Extra looks for your profile, paid with coins", "sparkles", [0xC084FC, 0x8B5CF6]) { shop = true }
        }
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : Motion.enter.delay(0.1), value: shown)
    }

    // MARK: lists

    private func card<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { ListHeader(title: title).padding(.leading, 6) }
            VStack(spacing: 0) { content() }
                // Rows light up when pressed; keep that inside the round corners.
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .sugarCard(radius: 22)
        }
    }

    private func row(_ title: String, _ detail: String, _ icon: String, _ colors: [UInt32], action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, detail, icon, colors) }
            .buttonStyle(RowPressStyle())
    }

    private func rowLabel(_ title: String, _ detail: String, _ icon: String, _ colors: [UInt32]) -> some View {
        HStack(spacing: 8) {
            IconRow(title: title, detail: detail, icon: icon, colors: colors)
            chevron
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.muted.opacity(0.7))
    }

    private var divider: some View {
        Divider().padding(.leading, 58)
    }

    // Which version of the app this is (handy when checking TestFlight).
    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return Text(build.isEmpty ? "Sugerly \(version)" : "Sugerly \(version) · build \(build)")
            .font(.jakarta(12, .semibold))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}
