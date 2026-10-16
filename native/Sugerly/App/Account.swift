import SwiftUI

// The menu: opens from your picture in the top left corner of every main
// page. You at the top (profile, level, status), then your coins and
// MimiPlus explained in one place, the places that aren't tabs, Settings and
// help, and dark mode and Log out at the bottom. Swipe down or tap Done to
// close it.
struct AccountView: View {
    // Closes the menu and opens a page on the tab you're on.
    var go: (Route) -> Void
    @Environment(AppModel.self) private var model
    @Environment(NotificationsStore.self) private var notes
    @Environment(\.dismiss) private var dismiss
    @State private var shop = false
    @State private var status = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let me = model.me {
                        profileCard(me)
                        walletCard(me)
                    }
                    exploreCard
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
            .background { Palette.bg.ignoresSafeArea() }
            .roundTitle("Menu")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.jakarta(16, .semibold))
                }
            }
        }
        .tint(Theme.main)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $shop) { NitroShopView() }
        .sheet(isPresented: $status) { StatusSheet().presentationCornerRadius(24) }
        .confirmationDialog("Log out of Sugerly?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { model.signOut() }
        }
    }

    // MARK: you

    // Your picture, name and level (opens your profile), how far you are to
    // the next level, your status, and your streak / following.
    private func profileCard(_ me: UserProfile) -> some View {
        let info = LevelInfo(xp: me.xp)
        let presence = Presence(rawValue: me.presence) ?? .online
        return VStack(spacing: 14) {
            profileButton(me, info, presence)
            XPBar(info: info)
            statusButton(me, presence)
            HStack(spacing: 0) {
                stat("\(me.dailyStreak)", "Day streak")
                Divider().frame(height: 28)
                stat("\(me.following.count)", "Following")
                Divider().frame(height: 28)
                stat("\(info.level)", "Level")
            }
            .padding(.vertical, 8)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .sugarCard(radius: 16, padding: 16)
    }

    private func profileButton(_ me: UserProfile, _ info: LevelInfo, _ presence: Presence) -> some View {
        Button { go(.person(me.email)) } label: {
            HStack(spacing: 14) {
                Avatar(url: me.picture, name: me.displayName, size: 56, nitro: me.isNitro, presence: presence)
                VStack(alignment: .leading, spacing: 3) {
                    Text(me.displayName)
                        .font(.jakarta(20, .semibold)).foregroundStyle(Palette.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Level \(info.level) · \(info.title)")
                        .font(.jakarta(13)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    Text("Profile").font(.jakarta(13, .medium))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle(scale: 0.99))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(me.displayName), level \(info.level) \(info.title)")
        .accessibilityHint("Opens your profile")
        .accessibilityAddTraits(.isButton)
    }

    private func statusButton(_ me: UserProfile, _ presence: Presence) -> some View {
        let text = me.activeStatus.isEmpty ? "\(presence.label) · set a status" : me.activeStatus
        return Button { status = true } label: {
            HStack(spacing: 10) {
                PresenceDot(presence: presence, size: 10)
                Text(text)
                    .font(.jakarta(14)).foregroundStyle(Palette.text2).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel("Status")
        .accessibilityValue(me.activeStatus.isEmpty ? presence.label : me.activeStatus)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.jakarta(16, .semibold)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.jakarta(11)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: coins & MimiPlus

    // What you have and what it's for, in plain words. Both rows open the
    // same page, which explains how to earn coins and what MimiPlus gives you.
    private func walletCard(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            card("COINS & MIMIPLUS") {
                Button { shop = true } label: {
                    HStack(spacing: 12) {
                        CoinIcon(size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coins").font(.jakarta(16, .medium)).foregroundStyle(Palette.text)
                            Text("Earned in the app, spent on MimiPlus").font(.jakarta(12)).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 6)
                        Text(me.coins.formatted()).font(.jakarta(16, .semibold)).foregroundStyle(Palette.text)
                            .contentTransition(.numericText())
                        chevron
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel("Coins, \(me.coins)")
                .accessibilityHint("Shows how to earn and spend coins")
                divider
                Button { shop = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NitroStyle.tint)
                            .frame(width: 30, height: 30)
                            .background(NitroStyle.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MimiPlus").font(.jakarta(16, .medium)).foregroundStyle(Palette.text)
                            Text(nitroDetail(me)).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        Text(me.isNitro ? "Active" : "\(NitroStyle.cost) coins")
                            .font(.jakarta(13, .medium))
                            .foregroundStyle(me.isNitro ? Palette.success : Palette.muted)
                        chevron
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(me.isNitro ? "MimiPlus, active" : "MimiPlus")
            }
            Text("Coins can't be bought with money. You get them from the daily reward, posting and inviting friends.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nitroDetail(_ me: UserProfile) -> String {
        guard me.isNitro else { return "Extra profile looks, paid with coins" }
        if let until = Dates.parse(me.nitroUntil) {
            return "Until \(until.formatted(date: .abbreviated, time: .omitted)), then it simply ends"
        }
        return "Your extra profile looks are on"
    }

    // MARK: places

    // The places that aren't tabs.
    private var exploreCard: some View {
        card("EXPLORE") {
            row("Music", "Songs from the community", "music.note") { go(.music) }
            divider
            row("Servers", "Group chats with voice rooms", "person.3") { go(.servers) }
            divider
            row("People", "Find people to follow", "person.crop.circle.badge.plus") { go(.people) }
            divider
            row("Top artists", "This month's most liked", "crown") { go(.topArtists) }
            divider
            row("Commissions", "Order art from artists", "storefront") { go(.commissions) }
        }
    }

    // Notifications, Settings, what's new and help.
    private var youCard: some View {
        card("YOU") {
            notificationsRow
            divider
            NavigationLink {
                SettingsView()
            } label: {
                rowLabel("Settings", "Account, privacy and colours", "gearshape")
            }
            .buttonStyle(RowPressStyle())
            divider
            row("What's new", "The latest updates", "gift") { go(.updates) }
            divider
            row("Help & support", "Chat with the Sugerly team", "questionmark.bubble") { go(.support) }
            if model.me?.isAdmin == true {
                divider
                row("Admin", "Manage Sugerly", "shield.lefthalf.filled") { go(.admin) }
            }
        }
    }

    // With a count of the new ones.
    private var notificationsRow: some View {
        Button { go(.notifications) } label: {
            HStack(spacing: 8) {
                IconRow(title: "Notifications", detail: "Likes, follows and mentions", icon: "bell")
                if notes.unread > 0 {
                    Text("\(notes.unread)")
                        .font(.jakarta(12, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 20)
                        .background(Palette.danger, in: Capsule())
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
                IconRow(title: "Dark mode", icon: "moon")
            }
            .tint(Theme.main)
            .padding(.horizontal, 14).padding(.vertical, 9)
            divider
            Button { confirmLogout = true } label: {
                IconRow(title: "Log out", icon: "rectangle.portrait.and.arrow.right", danger: true)
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

    // MARK: lists

    private func card<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { ListHeader(title: title).padding(.leading, 6) }
            VStack(spacing: 0) { content() }
                // Rows light up when pressed; keep that inside the round corners.
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .sugarCard(radius: 16)
        }
    }

    private func row(_ title: String, _ detail: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, detail, icon) }
            .buttonStyle(RowPressStyle())
    }

    private func rowLabel(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            IconRow(title: title, detail: detail, icon: icon)
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
        Divider().padding(.leading, 56)
    }

    // Which version of the app this is (handy when checking TestFlight).
    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return Text(build.isEmpty ? "Sugerly \(version)" : "Sugerly \(version) · build \(build)")
            .font(.jakarta(12))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}
