import SwiftUI
import Observation

@Observable final class Appearance {
    static let shared = Appearance()
    var hex = UserDefaults.standard.string(forKey: "sugerly.accent") ?? "D9577F" { didSet { UserDefaults.standard.set(hex, forKey: "sugerly.accent") } }
    var mode = UserDefaults.standard.string(forKey: "sugerly.mode") ?? "system" { didSet { UserDefaults.standard.set(mode, forKey: "sugerly.mode") } }
    var motion = UserDefaults.standard.object(forKey: "sugerly.motion") as? Bool ?? true { didSet { UserDefaults.standard.set(motion, forKey: "sugerly.motion") } }
    var color: Color { Color(hex: hex) }
    var scheme: ColorScheme? { mode == "dark" ? .dark : mode == "light" ? .light : nil }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xD9577F
        self.init(red: Double(value >> 16 & 255)/255, green: Double(value >> 8 & 255)/255, blue: Double(value & 255)/255)
    }
}

struct CandyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce && Appearance.shared.motion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduce || !Appearance.shared.motion ? nil : .spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct CandyCard<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.white).frame(width: 34, height: 34).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12))
                Text(title).font(.custom("CuteHereRegular", size: 23))
            }
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.pink.opacity(0.2), lineWidth: 1))
            .shadow(color: Theme.pink.opacity(0.09), radius: 12, y: 5)
    }
}

struct CandyHero: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("made for you").font(.custom("CuteHereRegular", size: 19)); Spacer(); Image(systemName: "sparkles").font(.title2) }
            Text(title).font(.custom("Bubbly-Regular", size: 38, relativeTo: .largeTitle))
            Text(subtitle).font(.custom("PlusJakartaSans-Regular", size: 13)).opacity(0.9)
        }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Theme.pink, Color(hex: "F283BE"), Color(hex: "BC85E9")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
            .overlay(alignment: .bottomTrailing) { Image(systemName: "heart.fill").font(.system(size: 100)).rotationEffect(.degrees(-20)).foregroundStyle(.white.opacity(0.1)).padding(8).allowsHitTesting(false) }
            .shadow(color: Theme.pink.opacity(0.25), radius: 18, y: 8)
    }
}

struct DailyRewardCard: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var message: String?
    @State private var today = String(FS.nowISO().prefix(10))
    private var claimed: Bool { model.me?.lastDaily == today }
    var body: some View {
        CandyCard(title: "A little daily sugar", icon: "gift.fill") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(claimed ? "You're all set for today!" : "Your daily treat is ready.").font(.headline)
                    Text("\(model.me?.dailyStreak ?? 0)-day streak · \(model.me?.coins ?? 0) coins").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Text("✦").font(.system(size: 36)).foregroundStyle(Theme.pink)
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    VStack(spacing: 5) { Image(systemName: day <= min(model.me?.dailyStreak ?? 0, 7) ? "heart.fill" : "star"); Text("\(day)").font(.caption2) }
                        .frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(Theme.pink).background(Theme.soft, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.pink) }
            Button {
                Task {
                    busy = true
                    defer { busy = false }
                    do { let reward = try await model.claimDaily(); today = String(FS.nowISO().prefix(10)); message = reward > 0 ? "+\(reward) coins · +10 XP. See you tomorrow!" : "Already claimed today." }
                    catch { message = error.localizedDescription }
                }
            } label: { Text(claimed ? "Claimed with love ♥" : busy ? "Opening your treat…" : "Claim 25–55 coins + 10 XP") }.buttonStyle(PrimaryButtonStyle()).disabled(claimed || busy)
        }.onAppear { today = String(FS.nowISO().prefix(10)) }
    }
}
