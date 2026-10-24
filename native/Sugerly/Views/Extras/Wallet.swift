import SwiftUI

// Your MimiCoins in one place: how many you have, how to get more, and what
// they're for. Coins are free: you earn them by using Sugerly and spend them
// on MimiPlus and XP boosts. They can't be bought or cashed out.
@MainActor
enum Coins {
    struct Way: Identifiable {
        let icon: String
        let title: String
        let detail: String
        let amount: String
        var id: String { title }
    }

    static let earn: [Way] = [
        Way(icon: "gift.fill", title: "Daily reward", detail: "Open Sugerly every day. Your streak makes it bigger.", amount: "+\(DailyReward.amount(1))–\(DailyReward.amount(7))"),
        Way(icon: "square.and.pencil", title: "Share a post", detail: "Post something in Community.", amount: "+5"),
        Way(icon: "paintbrush.pointed.fill", title: "Upload a drawing", detail: "Add your art to the Gallery.", amount: "+5"),
        Way(icon: "play.rectangle.fill", title: "Post a reel", detail: "Make a reel in the studio.", amount: "+5"),
        Way(icon: "person.2.fill", title: "Invite a friend", detail: "When they join with your code.", amount: "+\(Referrals.reward)"),
        Way(icon: "checkmark.seal.fill", title: "Finish setting up", detail: "Once, when you make your account.", amount: "+50"),
    ]
}

// The wallet as a sheet (from Home and the menu).
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shop = false

    var body: some View {
        NavigationStack {
            WalletPage(openShop: { shop = true })
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.font(.jakarta(16, .bold))
                    }
                }
        }
        .tint(Theme.main)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $shop) { NitroShopView() }
    }
}

struct WalletPage: View {
    // nil inside the MimiPlus page itself (you're already there).
    var openShop: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var shown = false
    @State private var burst = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var coins: Int { model.me?.coins ?? 0 }
    private var month: NitroStyle.Plan { NitroStyle.plans[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                balance.entrance(shown, 0)
                DailyRewardButton().entrance(shown, 1)
                section("Ways to earn", 2) {
                    ForEach(Array(Coins.earn.enumerated()), id: \.element.id) { i, way in
                        if i > 0 { Divider().padding(.leading, 56) }
                        earnRow(way)
                    }
                }
                section("Spend them on", 3) {
                    mimiPlusRow
                    Divider().padding(.leading, 56)
                    boostRow
                }
                Text("MimiCoins are free and just for fun. They can't be bought with money or turned into money.")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 6)
                    .entrance(shown, 4)
            }
            .padding(16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .overlay { ConfettiBurst(trigger: burst) }
        .roundTitle("Wallet")
        .onAppear { shown = true }
    }

    // MARK: balance

    private var balance: some View {
        let part = min(1, Double(coins) / Double(max(1, month.cost)))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CoinIcon(size: 46)
                    .symbolEffect(.bounce, value: coins)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(coins)")
                        .font(.display(38)).foregroundStyle(Palette.text).monospacedDigit()
                        .contentTransition(.numericText(value: Double(coins)))
                        .motion(Motion.standard, value: coins)
                    Text("MimiCoins").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(coins >= month.cost ? "Enough for a month of MimiPlus" : "\(month.cost - coins) more for a month of MimiPlus")
                        .font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2)
                    Spacer(minLength: 4)
                    Text("\(Int(part * 100))%").font(.jakarta(12, .bold)).foregroundStyle(Theme.main).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.surface.opacity(0.7))
                        Capsule().fill(Theme.progress)
                            .frame(width: max(8, geo.size.width * (shown || reduceMotion ? part : 0)))
                            .animation(reduceMotion ? nil : Motion.drawer.delay(0.15), value: shown)
                    }
                }
                .frame(height: 8)
            }
        }
        // Coins live on cream: the palette's warm side.
        .padding(18)
        .background {
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            shape.fill(LinearGradient(colors: [Palette.cream, Palette.ivory, Palette.blush], startPoint: .top, endPoint: .bottom))
                .overlay(shape.fill(LinearGradient(colors: [Palette.rim(0.35), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: Palette.gold.opacity(0.16), radius: 14, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.rim(0.6), lineWidth: 1))
    }

    // MARK: rows

    private func earnRow(_ way: Coins.Way) -> some View {
        HStack(spacing: 12) {
            tile(way.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(way.title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                Text(way.detail).font(.jakarta(12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(way.amount).font(.jakarta(14, .bold)).foregroundStyle(Palette.success).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var mimiPlusRow: some View {
        HStack(spacing: 12) {
            tile("sparkles")
            VStack(alignment: .leading, spacing: 2) {
                Text("MimiPlus").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                Text(planSummary)
                    .font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if let openShop {
                Button("See perks", action: openShop).buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var planSummary: String {
        NitroStyle.plans.map { plan in plan.title + " · " + String(plan.cost) }.joined(separator: "   ")
    }

    private var boostRow: some View {
        let cost = NitroStyle.xpBoostCost
        return HStack(spacing: 12) {
            tile("bolt.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("XP boost").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                Text("+100 XP to level up faster · \(cost)").font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Button { buyBoost() } label: {
                if busy { ProgressView() } else { Text("Buy") }
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(busy || coins < cost)
            .opacity(coins < cost ? 0.5 : 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func tile(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.main)
            .frame(width: 32, height: 32)
            .background(Palette.blush.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func section<Content: View>(_ title: String, _ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ListHeader(title: title.uppercased()).padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .sugarCard(radius: 20)
        }
        .entrance(shown, index)
    }

    private func buyBoost() {
        let cost = NitroStyle.xpBoostCost
        guard let me = model.me, me.coins >= cost, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.updateMe(["coins": me.coins - cost, "xp": me.xp + 100])
                burst += 1
                model.showToast("+100 XP", icon: "bolt.fill")
            } catch {
                model.showToast("Couldn't buy it right now. Try again.", icon: "exclamationmark.triangle", error: true)
            }
        }
    }
}

extension View {
    /// Rises and fades in, one block after another, the first time a page
    /// opens.
    func entrance(_ shown: Bool, _ index: Int) -> some View {
        modifier(Entrance(shown: shown, index: index))
    }
}

private struct Entrance: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .scaleEffect(visible ? 1 : 0.98, anchor: .top)
            .animation(reduceMotion ? nil : Motion.enter.delay(Double(min(index, 8)) * 0.05), value: shown)
    }
}
