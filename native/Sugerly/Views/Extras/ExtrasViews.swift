import SwiftUI
import UIKit
import PhotosUI

// MARK: - Top artists (the website's TopArtists page)

struct TopArtistsView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var posts
    @State private var artworks: [Artwork] = []
    @State private var appeared = false
    @State private var risen = false
    @State private var spin = false
    @State private var burst = 0
    @State private var range = 0
    @Namespace private var chip

    struct RankEntry: Hashable { var email: String; var likes: Int; var works: Int }

    private static let gold = Color(hex: 0xF0A020)
    private static let goldLight = Color(hex: 0xFFD166)
    private static let silver = Color(hex: 0x94A3B8)
    private static let bronze = Color(hex: 0xC2773A)

    private var ranking: [RankEntry] {
        let since = range == 0 ? "" : Dates.iso(Date().addingTimeInterval(range == 1 ? -7 * 86_400 : -30 * 86_400))
        var likes: [String: Int] = [:]
        var works: [String: Int] = [:]
        for a in artworks where a.created > since { likes[a.authorEmail, default: 0] += a.likeTotal; works[a.authorEmail, default: 0] += 1 }
        for p in posts.posts where p.created > since { likes[p.authorEmail, default: 0] += p.likeTotal; works[p.authorEmail, default: 0] += 1 }
        return likes.keys.filter { model.person($0) != nil }
            .map { RankEntry(email: $0, likes: likes[$0] ?? 0, works: works[$0] ?? 0) }
            .sorted { $0.likes != $1.likes ? $0.likes > $1.likes : $0.works > $1.works }
    }

    var body: some View {
        let list = ranking
        let top = max(1, list.first?.likes ?? 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero.stagger(appeared, 0)
                HStack(spacing: 6) {
                    ForEach(Array(["All time", "This week", "This month"].enumerated()), id: \.offset) { i, title in
                        let on = range == i
                        Button { pick(i) } label: {
                            Text(title).font(.jakarta(13, .bold))
                                .foregroundStyle(on ? .white : Palette.text2)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background {
                                    if on { Capsule().fill(LinearGradient(colors: [Self.goldLight, Self.gold], startPoint: .topLeading, endPoint: .bottomTrailing)).matchedGeometryEffect(id: "range", in: chip) }
                                    else { Capsule().fill(Palette.surface) }
                                }
                                .overlay(Capsule().strokeBorder(on ? Color.clear : Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.94))
                    }
                }
                .sensoryFeedback(.selection, trigger: range)
                .stagger(appeared, 1)
                if list.count >= 3 { podium(Array(list.prefix(3))).stagger(appeared, 2) }
                if let me = model.me?.email, let mine = list.firstIndex(where: { $0.email == me }) {
                    yourSpot(list, mine).stagger(appeared, 3)
                }
                VStack(spacing: 8) {
                    ForEach(Array(list.enumerated()).dropFirst(list.count >= 3 ? 3 : 0), id: \.element.email) { i, entry in
                        row(entry, rank: i + 1, top: top)
                            .opacity(risen ? 1 : 0)
                            .offset(x: risen ? 0 : 70)
                            .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.5 + Double(min(i, 14)) * 0.05), value: risen)
                    }
                }
                if list.isEmpty { EmptyCard(icon: "crown.fill", title: "No artists yet", text: "Post art to get on the board!") }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .sideRails(720)
        }
        .overlay(alignment: .top) { ConfettiBurst(trigger: burst).frame(height: 520).allowsHitTesting(false) }
        .sugarBackground()
        .navigationTitle("Top artists")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if posts.posts.isEmpty { await posts.load() }
            artworks = ((try? await FS.query("Artwork", orderBy: "created_date", limit: 200)) ?? []).map(Artwork.init)
            try? await Task.sleep(for: .milliseconds(150))
            risen = true
            burst += 1
        }
        .onAppear {
            appeared = true
            spin = true
            if !artworks.isEmpty || !posts.posts.isEmpty { risen = true }
        }
    }

    private func pick(_ i: Int) {
        guard range != i else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { range = i }
        // Replay the podium rise for the new board.
        risen = false
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            risen = true
            burst += 1
        }
    }

    // A big gold crown (still: no bouncing or circling sparkles).
    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Self.goldLight.opacity(0.55), .clear], center: .center, startRadius: 4, endRadius: 52))
                    .frame(width: 104, height: 104)
                Image(systemName: "crown.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Self.goldLight, Self.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Self.gold.opacity(0.5), radius: 10, y: 4)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text("Top artists").font(.display(36))
                    .foregroundStyle(LinearGradient(colors: [Self.gold, Theme.main], startPoint: .leading, endPoint: .trailing))
                Text("The most loved artists on Sugerly. Post, get likes, climb the board!").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 6)
    }

    private func podium(_ top: [RankEntry]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            place(top[1], rank: 2, height: 112, color: Self.silver, delay: 0.15)
            place(top[0], rank: 1, height: 156, color: Self.gold, delay: 0.3)
            place(top[2], rank: 3, height: 90, color: Self.bronze, delay: 0)
        }
        .padding(.top, 30)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func place(_ entry: RankEntry, rank: Int, height: CGFloat, color: Color, delay: Double) -> some View {
        let person = model.person(entry.email)
        let size: CGFloat = rank == 1 ? 78 : 62
        return Button { path.append(.person(entry.email)) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: size)
                        .padding(4)
                        .overlay {
                            if rank == 1 {
                                Circle().strokeBorder(AngularGradient(colors: [Self.goldLight, Self.gold, .white, Self.gold, Self.goldLight], center: .center), lineWidth: 4)
                            } else {
                                Circle().strokeBorder(color, lineWidth: 3)
                            }
                        }
                        .shadow(color: color.opacity(0.55), radius: rank == 1 ? 16 : 8)
                    if rank == 1 {
                        Image(systemName: "crown.fill").font(.system(size: 26, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [Self.goldLight, Self.gold], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Self.gold.opacity(0.6), radius: 6)
                            .offset(y: -30)
                            .rotationEffect(.degrees(-6))
                    } else {
                        Text("\(rank)").font(.jakarta(12, .black)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(color, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                            .offset(x: size * 0.36, y: size * 0.72)
                    }
                }
                .scaleEffect(risen ? 1 : 0.3)
                .opacity(risen ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(delay + 0.35), value: risen)
                Text(person?.displayName ?? "").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                VStack(spacing: 2) {
                    Text("\(rank)").font(.display(rank == 1 ? 36 : 28)).foregroundStyle(.white)
                    Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(11, .heavy)).foregroundStyle(.white.opacity(0.92))
                }
                .opacity(risen ? 1 : 0)
                .frame(maxWidth: .infinity)
                .frame(height: risen ? height : 14, alignment: .top)
                .padding(.top, 4)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
                }
                .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(delay), value: risen)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
    }

    // Where you are on the board and how far to the next spot.
    private func yourSpot(_ list: [RankEntry], _ index: Int) -> some View {
        let entry = list[index]
        let gap = index > 0 ? list[index - 1].likes - entry.likes + 1 : 0
        return HStack(spacing: 12) {
            Text("#\(index + 1)").font(.display(26)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Your spot").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                Text(index == 0 ? "You're the top artist. Keep that crown!" : "\(gap) more like\(gap == 1 ? "" : "s") to reach #\(index)")
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
        }
        .sugarCard(radius: 22, padding: 12)
    }

    private func row(_ entry: RankEntry, rank: Int, top: Int) -> some View {
        let person = model.person(entry.email)
        let share = CGFloat(entry.likes) / CGFloat(top)
        return Button { path.append(.person(entry.email)) } label: {
            HStack(spacing: 12) {
                Text("\(rank)").font(.display(20)).foregroundStyle(rank <= 10 ? Theme.main : Palette.muted).frame(width: 30)
                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 44, online: person?.isOnline ?? false)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(person?.displayName ?? "").font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("\(entry.works) works").font(.jakarta(11)).foregroundStyle(Palette.muted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surface2)
                            Capsule().fill(Theme.gradient).frame(width: max(6, geo.size.width * (risen ? share : 0)))
                                .animation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.6 + Double(min(rank, 14)) * 0.05), value: risen)
                        }
                    }
                    .frame(height: 6)
                }
                Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(13, .heavy)).foregroundStyle(Theme.main)
                FollowButton(email: entry.email, compact: true)
            }
            .sugarCard(radius: 20, padding: 10)
        }
        .buttonStyle(BouncyStyle(scale: 0.98))
    }
}

// A soft white glint that sweeps across now and then, like the logo shine.
// The band is much taller than the view and starts/ends well outside it, so
// no sliver is ever left showing at the edge while it waits.
struct Glint: View {
    var pause: Double = 2.2
    var strength: Double = 0.75

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let band = max(20, min(w, h) * 0.55)
            let reach = band + h * 0.5
            LinearGradient(colors: [.white.opacity(0), .white.opacity(strength), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: band, height: h * 3 + band)
                .rotationEffect(.degrees(20))
                .phaseAnimator([false, true]) { v, go in
                    v.position(x: go ? w + reach : -reach, y: h / 2)
                } animation: { go in go ? .easeInOut(duration: 0.9).delay(pause) : nil }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - What's new (release notes + updates admins post)

struct AppRelease: Identifiable {
    var id: String
    var icon: String
    var title: String
    var date: String
    var items: [String]
    var author: String = ""
    var docId: String? = nil
}

enum AppReleases {
    static let native: [AppRelease] = [
        AppRelease(id: "ios-2.0", icon: "storefront.fill", title: "Commissions with real payments", date: "2026-09-29T12:00:00Z", items: [
            "A new Commissions: explore shops, open your own, and follow every order in My orders and My shop.",
            "Request art in a few taps, the artist accepts and sets the price, then pay by card or Apple Pay, secured by Stripe.",
            "Track each order from request to delivery, get the finished art right in the app, and approve it with a star review.",
            "Artists see their earnings and get paid out after the buyer approves. Refunds are there if something goes wrong.",
        ]),
        AppRelease(id: "ios-1.9", icon: "film.stack", title: "Timeline editor & your colours", date: "2026-09-28T22:00:00Z", items: [
            "A timeline in the reel editor: scrub the film strip, and every text, sticker and photo gets a bar you drag to choose when it shows.",
            "Photo overlays: put pictures on top of your video or slideshow, with a cute white edge.",
            "Slideshows: make each photo longer or shorter, move it or remove it, right on the timeline.",
            "Your own colours in Settings: a main colour and a sub tone. The logo and Mimi turn to match any colour.",
            "A brand-new Settings (your profile up top, quick jumps, tidy groups) and a fresh Community with new post cards and comments.",
            "Names, pictures and who's online update live everywhere within seconds, including your own changes and after switching accounts.",
        ]),
        AppRelease(id: "ios-1.8", icon: "lock.shield.fill", title: "Status, requests & privacy", date: "2026-09-28T13:00:00Z", items: [
            "Set your status: Online, Idle, Do not disturb or Invisible, plus a custom status that can clear itself.",
            "Messages from people you aren't friends with arrive as requests you can accept, decline or block.",
            "Calls and voice messages are for friends (people who follow each other).",
            "Ignore people to stop hearing from them, or block them. Manage both in Settings → Privacy & status.",
            "Logging out closes everything, and a new account starts completely fresh.",
            "Voice messages play instantly, and photos and videos in chats go through the in-app camera and editor.",
            "Pull down on the first reel to refresh the feed. GIFs show up in comments again.",
            "Built for huge amounts: chats keep every old conversation, scroll up to load older messages (DMs and servers), comments load in pages, and For You also digs up older reels.",
            "Everything else loads in pages too (Community, Gallery, profiles, notifications). Search, follower counts, likes and views now run on the server.",
            "Likes have no limit anymore: each like is its own record with a count kept by the database, on the app and the website.",
            "For You now also mixes in reels ranked on the server by likes, views and comments for their age.",
            "Music always restarts: after a call, a voice note, another app or the end of a song. Music and Settings scroll smoothly, and the charts load all at once.",
            "Connect Apple Music in the Music tab to play whole songs if you subscribe.",
            "Pages open instantly (no sliding) and Settings is smooth.",
            "Smart safety: everything you write is checked on your phone (and by AI when it's unsure), with a slow mode and cooldowns for spam.",
            "Invite friends with your code: 400 coins for each friend who joins.",
            "More profile looks: name colours and styles, picture frames, banner patterns, and effect colours with how many.",
            "Sharper GIFs, see-through photos work in the editor, calmer logo and Top Artists, and fuller pages on iPad.",
        ]),
        AppRelease(id: "ios-1.7", icon: "person.2.wave.2.fill", title: "More social & smoother", date: "2026-09-28T11:00:00Z", items: [
            "Home has stories, today's art prompt, Happening now, people you might like and trending tags.",
            "Community has a weekly challenge, top creators this week and you can send posts to chats.",
            "Top artists has a bouncing crown, a rising podium and confetti.",
            "Changing colours is smooth and keeps your music playing.",
            "A big, crisp white shine sweeps over the whole screen when you switch pages, and pages pop in again each time.",
            "Soft click sounds when you tap (Settings → Sounds & haptics).",
            "Empty pages have Mimi, the Sugerly bunny, in your accent colour.",
            "The animated background keeps moving after you change it.",
            "Your picture opens a quick menu that pops open instantly.",
            "Admins can add, remove and pin weekly challenges and daily art prompts.",
            "A new notifications card, and long-press on server messages to reply, edit or delete.",
        ]),
        AppRelease(id: "ios-1.6", icon: "bell.badge.fill", title: "Widgets, notifications & calls", date: "2026-09-28T06:00:00Z", items: [
            "Home-screen and lock-screen widgets: streak & coins, inbox and featured art.",
            "Notifications for DMs, servers, likes, comments, follows and new reels.",
            "Drafts for posts and reels, and you can close DMs.",
            "Animated backgrounds — polka dots, clouds, stripes, hearts or stars — in Settings.",
            "Voice channels ring like real calls, with a green circle that grows while you talk.",
        ]),
        AppRelease(id: "ios-1.5", icon: "sparkles", title: "MimiPlus, GIFs & stickers", date: "2026-09-28T05:00:00Z", items: [
            "A better camera: speed 0.5x–3x, 15s or 60s, a grid and your sound while you film.",
            "GIFs and stickers in chats, servers, comments and posts. Make your own stickers and GIFs.",
            "MimiPlus: GIF profile picture and banner, premium name styles and profile effects.",
            "Crop your picture and banner, add pronouns, a status, interests and colours.",
            "Use any reel's sound, draw on reels and photos, and smoother two-finger text.",
            "A smarter For You feed that learns what you like, right on your phone.",
        ]),
        AppRelease(id: "ios-1.4", icon: "waveform.circle.fill", title: "Servers, voice & admin", date: "2026-09-27T20:00:00Z", items: [
            "Servers: a rail of your servers, channels, roles with colours and permissions, pins and reactions.",
            "Voice channels right in the app — talk with people on the app and the website.",
            "The full admin panel, commissions, top artists and a photo editor for posts.",
        ]),
        AppRelease(id: "ios-1.3", icon: "camera.aperture", title: "Camera & editor", date: "2026-09-27T19:30:00Z", items: [
            "Film in clips: pause, delete the last clip or start over, with flash, timer and flip.",
            "Text you can drag, pinch and twist, stickers, filters and adjustments.",
            "Reels and Community look just like the website.",
        ]),
        AppRelease(id: "ios-1.2", icon: "heart.circle.fill", title: "Cuter everywhere", date: "2026-09-27T19:00:00Z", items: [
            "Gallery is a main tab, notifications pop up, a pinker look and snappier tabs.",
            "Search, People, toasts and shimmer loading.",
        ]),
    ]
}

struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @State private var posted: [AppRelease] = []
    @State private var title = ""
    @State private var text = ""
    @State private var busy = false
    @State private var appeared = false
    @AppStorage("sugerly.updatesSeen") private var seen = ""

    private var all: [AppRelease] { (posted + AppReleases.native).sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new").font(.display(38)).foregroundStyle(Palette.text)
                    Text("Everything new in Sugerly, newest first.").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                }
                if model.me?.isAdmin == true { composer }
                ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: r.icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.gradient).frame(width: 46, height: 46)
                            .background(Theme.soft, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.main.opacity(0.25), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(r.title).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                                Spacer()
                                if let docId = r.docId, model.me?.isAdmin == true {
                                    Button { Task { try? await FS.delete("AppUpdate", docId); posted.removeAll { $0.docId == docId } } } label: {
                                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Palette.danger)
                                    }
                                }
                            }
                            Text(Dates.parse(r.date)?.formatted(date: .long, time: .omitted) ?? "").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                            ForEach(r.items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Theme.gradient).frame(width: 6, height: 6).padding(.top, 7)
                                    Text(item).font(.jakarta(14)).foregroundStyle(Palette.text2)
                                }
                            }
                        }
                        .sugarCard(radius: 22, padding: 14)
                    }
                    .stagger(appeared, i)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear { appeared = true; seen = FS.nowISO() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("POST AN UPDATE (ADMINS)").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
            SugarField(placeholder: "Title — e.g. New stickers in Reels", text: $title)
            SugarField(placeholder: "What changed? One line per point.", text: $text, lines: 3...8)
            Button { Task { await post() } } label: {
                if busy { ProgressView().tint(.white) } else { Label("Post update", systemImage: "paperplane.fill") }
            }
            .buttonStyle(GradientButtonStyle(height: 44))
            .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .sugarCard(radius: 22, padding: 14)
    }

    private func load() async {
        let docs = (try? await FS.query("AppUpdate", orderBy: "created_date", limit: 50)) ?? []
        posted = docs.map { d in
            AppRelease(id: "post-\(d.str("id"))", icon: "megaphone.fill", title: d.str("title"), date: d.str("created_date"),
                       items: d.str("body").split(separator: "\n").map(String.init).filter { !$0.isEmpty }, author: d.str("author_name"), docId: d.str("id"))
        }
    }

    private func post() async {
        guard let me = model.me else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await FS.create("AppUpdate", ["title": title.trimmingCharacters(in: .whitespaces), "body": text.trimmingCharacters(in: .whitespacesAndNewlines), "emoji": "", "author_name": me.displayName])
            title = ""
            text = ""
            model.showToast("Update posted", icon: "megaphone.fill")
            await load()
        } catch {
            model.showToast("Couldn't post — \(error.localizedDescription)", error: true)
        }
    }
}
