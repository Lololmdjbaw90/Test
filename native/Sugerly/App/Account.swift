import SwiftUI

// The menu: opens from your picture in the top left corner of every main
// page. You at the top (your bunny, level, status, coins), your wallet and
// MimiPlus as two bright cards, the places that aren't tabs as candy tiles,
// then Settings and help, and dark mode and Log out at the bottom. Swipe down
// or tap Done to close it.
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
    @State private var bunny = BunnyStore.shared

    // The places that aren't tabs.
    private var places: [CandyShortcutGrid.Item] {
        [
            .init(title: "Music", icon: "music.note", candy: .sky, route: .music),
            .init(title: "Servers", icon: "bubble.left.and.bubble.right.fill", candy: .mint, route: .servers),
            .init(title: "People", icon: "person.2.fill", candy: .grape, route: .people),
            .init(title: "Top artists", icon: "crown.fill", candy: .lemon, route: .topArtists),
            .init(title: "Commissions", icon: "paintbrush.pointed.fill", candy: .peach, route: .commissions),
            .init(title: "Bunny", icon: "hare.fill", candy: .berry, route: .bunny),
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
                rowLabel("Settings", "Account, privacy and colours", "gearshape.fill", .accent)
            }
            .buttonStyle(RowPressStyle())
            divider
            row("What's new", "The latest updates", "gift.fill") { go(.updates) }
            divider
            row("Help & support", "Chat with the Sugerly team", "questionmark.bubble.fill") { go(.support) }
            if model.me?.isAdmin == true {
                divider
                row("Admin", "Manage Sugerly", "shield.lefthalf.filled", .neutral) { go(.admin) }
            }
        }
    }

    // With a pink count of the new ones.
    private var notificationsRow: some View {
        Button { go(.notifications) } label: {
            HStack(spacing: 8) {
                IconRow(title: "Notifications", detail: "Likes, follows and mentions", icon: "bell.fill")
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
                IconRow(title: "Dark mode", icon: "moon.fill")
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

    // MARK: you

    // Your picture, name and level (opens your profile), how far you are to
    // the next level, your status, and your coins / streak / following.
    private func profileCard(_ me: UserProfile) -> some View {
        let info = LevelInfo(xp: me.xp)
        let presence = Presence(rawValue: me.presence) ?? .online
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                profileButton(me, info, presence)
                // Your bunny says hi (tap her; hold to dress her up).
                BunnyBuddy(look: bunny.look, height: 92)
                    .padding(.top, -12)
                    .padding(.trailing, -4)
                    .onLongPressGesture { go(.bunny) }
            }
            XPBar(info: info)
            statusButton(me, presence)
            HStack(spacing: 8) {
                Button { wallet = true } label: {
                    stat("\(me.coins)", "Coins", "circle.hexagongrid.fill", .lemon)
                }
                .buttonStyle(SoftPressStyle())
                stat("\(me.dailyStreak)", "Day streak", "flame.fill", .peach)
                stat("\(me.following.count)", "Following", "heart.fill", .berry)
            }
        }
        .pastelCard(radius: 26, padding: 16)
        .overlay {
            SparkleEmitter(colors: [.white, UIColor(Theme.main), UIColor(hex: 0xFFC53D)], rate: 1)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .opacity(0.8)
                .allowsHitTesting(false)
        }
        .overlay {
            ShineSweep(every: 6, strength: 0.28)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .opacity(shown || reduceMotion ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : 0.96, anchor: .top)
        .animation(reduceMotion ? nil : Motion.settle, value: shown)
        .onAppear { bunny.use(me.email) }
    }

    private func profileButton(_ me: UserProfile, _ info: LevelInfo, _ presence: Presence) -> some View {
        Button { go(.person(me.email)) } label: {
            HStack(spacing: 14) {
                Avatar(url: me.picture, name: me.displayName, size: 64, nitro: me.isNitro, presence: presence)
                VStack(alignment: .leading, spacing: 6) {
                    Text(me.displayName)
                        .font(.display(26)).foregroundStyle(Palette.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Text("Lv. \(info.level) · \(info.title)")
                            .font(.jakarta(12, .heavy)).foregroundStyle(info.color)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Palette.surface.opacity(0.85), in: Capsule())
                        HStack(spacing: 2) {
                            Text("Profile")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
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
            .background(Palette.surface.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.rim(0.6), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
        .accessibilityLabel("Status")
        .accessibilityValue(me.activeStatus.isEmpty ? presence.label : me.activeStatus)
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ candy: Candy) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                CandyTile(icon: icon, candy: candy, size: 22)
                Text(value).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            Text(label).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rim(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: places

    // The places that aren't tabs, as candy tiles (like Home).
    private var placesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ListHeader(title: "EXPLORE").padding(.leading, 6)
            CandyShortcutGrid(items: places, shown: shown) { route in go(route) }
        }
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : Motion.enter.delay(0.06), value: shown)
    }

    // Coins and MimiPlus as two bright cards side by side.
    private var walletCard: some View {
        HStack(spacing: 10) {
            Button { wallet = true } label: {
                brightCard(.lemon, icon: "circle.hexagongrid.fill", title: "Wallet", value: "\(model.me?.coins ?? 0) coins")
            }
            .buttonStyle(BouncyStyle(scale: 0.95))
            .accessibilityLabel("Wallet, \(model.me?.coins ?? 0) coins")
            Button { shop = true } label: {
                brightCard(.grape, icon: "sparkles", title: "MimiPlus", value: model.me?.isNitro == true ? "Active" : "Extra looks")
            }
            .buttonStyle(BouncyStyle(scale: 0.95))
            .accessibilityLabel("MimiPlus")
        }
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : Motion.enter.delay(0.03), value: shown)
    }

    private func brightCard(_ candy: Candy, icon: String, title: String, value: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.jakarta(15, .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.88)).lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background {
            shape.fill(candy.gradient)
                .overlay {
                    GeometryReader { geo in
                        Circle().fill(.white.opacity(0.16)).frame(width: geo.size.height * 1.4)
                            .offset(x: geo.size.width * 0.62, y: -geo.size.height * 0.3)
                    }
                    .clipShape(shape)
                }
                .overlay { ShineSweep(every: 5, strength: 0.3).clipShape(shape) }
                .shadow(color: candy.color.softGlow(0.35), radius: 8, y: 4)
        }
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

    private func row(_ title: String, _ detail: String, _ icon: String, _ tone: Tone = .accent, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, detail, icon, tone) }
            .buttonStyle(RowPressStyle())
    }

    private func rowLabel(_ title: String, _ detail: String, _ icon: String, _ tone: Tone) -> some View {
        HStack(spacing: 8) {
            IconRow(title: title, detail: detail, icon: icon, tone: tone)
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
