import SwiftUI

// Daily login reward (same rules as the website): 20 coins + 5 per streak day
// (up to 7), +10 XP, once a day.
enum DailyReward {
    static func todayKey() -> String { String(Dates.iso(Date()).prefix(10)) }
    static func yesterdayKey() -> String { String(Dates.iso(Date().addingTimeInterval(-86400)).prefix(10)) }

    @MainActor
    static func status(_ me: UserProfile?) -> (claimed: Bool, streak: Int) {
        guard let me else { return (false, 0) }
        let claimed = me.lastDailyClaim == todayKey()
        let alive = claimed || me.lastDailyClaim == yesterdayKey()
        return (claimed, alive ? max(1, me.dailyStreak) : 0)
    }

    @MainActor
    static func claim(_ model: AppModel) async throws -> Int {
        guard let me = model.me else { return 0 }
        let next = me.lastDailyClaim == yesterdayKey() ? me.dailyStreak + 1 : 1
        let reward = 20 + min(next, 7) * 5
        try await model.updateMe(["last_daily_claim": todayKey(), "daily_streak": next, "coins": me.coins + reward, "xp": me.xp + 10])
        return reward
    }
}

struct DailyRewardButton: View {
    @Environment(AppModel.self) private var model
    @State private var confetti = false
    @State private var wiggle = false

    var body: some View {
        let status = DailyReward.status(model.me)
        Button {
            guard !status.claimed else { return }
            Task {
                if (try? await DailyReward.claim(model)) != nil {
                    confetti = true
                    try? await Task.sleep(for: .seconds(2))
                    confetti = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(status.claimed ? AnyShapeStyle(Theme.pink) : AnyShapeStyle(Color.white))
                    .frame(width: 42, height: 42)
                    .background(status.claimed ? Theme.pink.opacity(0.12) : Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .rotationEffect(.degrees(wiggle && !status.claimed ? 8 : -8))
                    .animation(status.claimed ? .default : .easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: wiggle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.claimed ? "Daily reward claimed" : "Claim daily reward").font(.jakarta(15, .bold))
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 11))
                        Text(status.streak > 0 ? "\(status.streak)-day streak" : "Start a streak today").font(.jakarta(12, .medium))
                    }
                    .opacity(0.85)
                }
                .foregroundStyle(status.claimed ? Palette.text : .white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                if status.claimed {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.gradient)
                        .shadow(color: Theme.pink.opacity(0.45), radius: 16, y: 8)
                }
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
        .overlay { if confetti { ConfettiView() } }
        .sensoryFeedback(.success, trigger: status.claimed)
        .onAppear { wiggle = true }
    }
}

// Pops up once a day when you open the app.
struct DailyRewardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reward: Int?
    @State private var bounce = false

    var body: some View {
        let status = DailyReward.status(model.me)
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 130, height: 130).blur(radius: 30).opacity(0.6)
                Image(systemName: reward == nil ? "gift.fill" : "sparkles")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 118, height: 118)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .shadow(color: Theme.pink.opacity(0.5), radius: 20, y: 10)
                    .scaleEffect(bounce ? 1.06 : 0.96)
                    .rotationEffect(.degrees(bounce ? 4 : -4))
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bounce)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.top, 34)
            .overlay { if reward != nil { ConfettiView() } }

            Text(reward == nil ? "Daily reward!" : "+\(reward ?? 0) coins").font(.display(38)).foregroundStyle(Theme.gradient)
            Text(reward == nil ? "Log in every day to grow your streak and earn more coins." : "See you tomorrow — your streak is \(max(1, DailyReward.status(model.me).streak)) days!")
                .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).padding(.horizontal, 30)

            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    let done = day <= status.streak
                    VStack(spacing: 4) {
                        Text("\(20 + day * 5)").font(.jakarta(11, .bold))
                        Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted").font(.system(size: 18))
                        Text("D\(day)").font(.jakarta(10, .semibold))
                    }
                    .foregroundStyle(done ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(done ? Theme.pink.opacity(0.1) : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 20)

            Button {
                if reward != nil || status.claimed { dismiss(); return }
                Task { reward = try? await DailyReward.claim(model) }
            } label: {
                Text(reward != nil || status.claimed ? "Yay!" : "Claim reward")
            }
            .buttonStyle(GradientButtonStyle(height: 54))
            .padding(.horizontal, 24)
            .sensoryFeedback(.success, trigger: reward)
            Spacer(minLength: 0)
        }
        .sugarBackground()
        .onAppear { bounce = true }
    }
}

// MARK: - Home

struct HomeView: View {
    @Binding var path: [Route]
    var compose: (Composer) -> Void
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var posts
    @Environment(Player.self) private var player
    @State private var artworks: [Artwork] = []
    @State private var tracks: [Track] = []

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                if !artworks.isEmpty { featured }
                if !communityPicks.isEmpty { community }
                if !tracks.isEmpty { freshTracks }
                if !topArtists.isEmpty { artists }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .sugarTopBar($path)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        async let art = try? FS.query("Artwork", orderBy: "created_date", limit: 40)
        async let music = try? FS.query("MusicReview", orderBy: "created_date", limit: 8)
        if posts.posts.isEmpty { await posts.load() }
        artworks = (await art ?? []).map(Artwork.init)
        tracks = (await music ?? []).map(Track.init)
    }

    // MARK: sections

    private var hero: some View {
        let me = model.me
        let info = LevelInfo(xp: me?.xp ?? 0)
        let friends = mutualFriends
        return VStack(alignment: .leading, spacing: 16) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.jakarta(12, .bold))
                .tracking(1.4)
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting),").font(.display(40)).foregroundStyle(Palette.text)
                Text(me?.displayName ?? "").font(.display(40)).foregroundStyle(Theme.gradient)
                    .shadow(color: Theme.pink.opacity(0.25), radius: 10, y: 4)
            }
            Text("Here's what's happening across Sugerly today — fresh art, new tracks and friends online.")
                .font(.jakarta(15)).foregroundStyle(Palette.text2)
            DailyRewardButton()
            Button { compose(.post) } label: { Label("Share something", systemImage: "photo.on.rectangle.angled") }
                .buttonStyle(OutlineButtonStyle())
            HStack(spacing: 10) {
                stat("\(info.level)", "LEVEL", info.title, info.color)
                stat(Self.compact(me?.coins ?? 0), "COINS", "MimiCoins", Palette.text)
                stat("\(friends.count)", "FRIENDS", "\(friends.filter { model.person($0)?.isOnline == true }.count) online", Palette.text)
            }
            XPBar(info: info)
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(colors: [Theme.light.opacity(0.38), Theme.main.opacity(0.14), Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Theme.light.opacity(0.5)).frame(width: 220).blur(radius: 60).offset(x: 60, y: -80)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .shadow(color: Theme.pink.opacity(0.18), radius: 24, y: 12)
        }
    }

    private func stat(_ value: String, _ label: String, _ sub: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.display(28)).foregroundStyle(color)
            Text(label).font(.jakarta(10, .bold)).tracking(0.8).foregroundStyle(Palette.muted)
            Text(sub).font(.jakarta(11)).foregroundStyle(Palette.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private var featured: some View {
        let list = artworks.sorted { a, b in
            if a.featured != b.featured { return a.featured }
            return a.likes.count > b.likes.count
        }.prefix(10)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "star.fill", title: "Featured art") { path.append(.gallery) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(list)) { art in
                        Button { path.append(.artwork(art)) } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: art.imageURL).frame(width: 220, height: 280)
                                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(art.title).font(.display(20)).foregroundStyle(.white).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                        Text("\(art.likes.count)")
                                        if !art.medium.isEmpty { Text("· \(art.medium.capitalized)") }
                                    }
                                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.9))
                                }
                                .padding(14)
                            }
                            .frame(width: 220, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: Palette.shadow, radius: 12, y: 6)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    private var communityPicks: [Post] {
        let blocked = Set(model.me?.blocked ?? [])
        return posts.posts.filter { !$0.imageURL.isEmpty && !blocked.contains($0.authorEmail) }
            .sorted { $0.likes.count > $1.likes.count }
            .prefix(6).map { $0 }
    }

    private var community: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "flame.fill", title: "For you in the community")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(communityPicks) { post in
                    Button { path.append(.post(post)) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle().fill(Palette.surface2)
                                .aspectRatio(0.85, contentMode: .fit)
                                .overlay { RemoteImage(url: post.imageURL) }
                                .clipped()
                            HStack(spacing: 8) {
                                Avatar(url: model.person(post.authorEmail)?.picture ?? post.authorPicture, name: post.authorName, size: 26)
                                Text(post.authorName).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Theme.pink)
                                Text("\(post.likes.count)").font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                            }
                            .padding(10)
                        }
                        .sugarCard(radius: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.96))
                }
            }
        }
    }

    private var freshTracks: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "music.note", title: "Fresh tracks") { path.append(.music) }
            VStack(spacing: 4) {
                ForEach(tracks.prefix(5)) { track in
                    TrackRow(track: track, list: tracks)
                }
            }
            .sugarCard(radius: 26, padding: 8)
        }
    }

    private var topArtists: [(String, Int)] {
        var score: [String: Int] = [:]
        for a in artworks { score[a.authorEmail, default: 0] += a.likes.count }
        for p in posts.posts { score[p.authorEmail, default: 0] += p.likes.count }
        return score.filter { $0.value > 0 && model.person($0.key) != nil }.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var artists: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "crown.fill", title: "Top artists")
            VStack(spacing: 2) {
                ForEach(Array(topArtists.enumerated()), id: \.offset) { index, entry in
                    let person = model.person(entry.0)
                    Button { path.append(.person(entry.0)) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.display(20)).foregroundStyle(index == 0 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted)).frame(width: 24)
                            Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 46)
                                .overlay(alignment: .top) {
                                    if index == 0 {
                                        Image(systemName: "crown.fill").font(.system(size: 14)).foregroundStyle(Color(hex: 0xF0A020)).offset(y: -12)
                                    }
                                }
                            Text(person?.displayName ?? "").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                            Spacer()
                            Label("\(entry.1)", systemImage: "heart.fill").font(.jakarta(13, .bold)).foregroundStyle(Theme.pink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.97))
                }
            }
            .sugarCard(radius: 26, padding: 6)
        }
    }

    private var mutualFriends: [String] {
        guard let me = model.me else { return [] }
        return me.following.filter { model.person($0)?.following.contains(me.email) == true }
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return "\(n / 1000)k" }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

// A song row (cover with play button, title, artist) used on Home and Music.
struct TrackRow: View {
    let track: Track
    let list: [Track]
    var rank: Int? = nil
    var onFull: (() -> Void)? = nil
    @Environment(Player.self) private var player

    var body: some View {
        let current = player.isCurrent(track)
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)").font(.jakarta(13, .bold)).foregroundStyle(rank <= 3 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.muted)).frame(width: 22)
            }
            Button { player.play(track, in: list) } label: {
                ZStack {
                    RemoteImage(url: track.coverURL)
                    if track.coverURL.isEmpty { Theme.gradient }
                    Color.black.opacity(0.25)
                    Image(systemName: player.isPlaying(track) ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: current ? Theme.pink.opacity(0.4) : .clear, radius: 8, y: 4)
            }
            .buttonStyle(BouncyStyle())
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.jakarta(15, .bold)).foregroundStyle(current ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text)).lineLimit(1)
                Text([track.artist, track.genre].filter { !$0.isEmpty }.joined(separator: " · ")).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.isPlaying(track) {
                Image(systemName: "waveform").foregroundStyle(Theme.pink).symbolEffect(.variableColor.iterative, isActive: true)
            }
            if let onFull {
                Button(action: onFull) {
                    Text("Full").font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Theme.pink.opacity(0.12), in: Capsule())
                }
                .buttonStyle(BouncyStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(current ? Theme.pink.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
