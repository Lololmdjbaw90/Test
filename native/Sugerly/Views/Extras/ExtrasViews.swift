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
    @State private var loaded = false
    @State private var burst = 0
    @State private var range = 0
    @Namespace private var chip

    struct RankEntry: Hashable { var email: String; var likes: Int; var works: Int }

    static let gold = Palette.gold
    static let silver = Color(hex: 0x94A3B8)
    static let bronze = Color(hex: 0xC2773A)

    private func ranking(_ range: Int) -> [RankEntry] {
        let since = range == 0 ? "" : Dates.iso(Date().addingTimeInterval(range == 1 ? -7 * 86_400 : -30 * 86_400))
        var likes: [String: Int] = [:]
        var works: [String: Int] = [:]
        for a in artworks where a.created > since { likes[a.authorEmail, default: 0] += a.likeTotal; works[a.authorEmail, default: 0] += 1 }
        for p in posts.posts where p.created > since { likes[p.authorEmail, default: 0] += p.likeTotal; works[p.authorEmail, default: 0] += 1 }
        return likes.keys.filter { model.person($0) != nil }
            .map { RankEntry(email: $0, likes: likes[$0] ?? 0, works: works[$0] ?? 0) }
            .sorted { $0.likes != $1.likes ? $0.likes > $1.likes : ($0.works != $1.works ? $0.works > $1.works : $0.email < $1.email) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero.stagger(appeared, 0)
                rangeSwitch.stagger(appeared, 1)
                if loaded {
                    // Each range is its own board: switching fades the old
                    // one out and the new one rises in fresh, so nothing
                    // half-animates in between.
                    RankBoard(list: ranking(range), path: $path)
                        .id(range)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(Motion.exit)))
                } else {
                    VStack(spacing: 12) {
                        SkeletonBlock(height: 230, radius: 22)
                        SkeletonBlock(height: 70, radius: 18)
                        SkeletonBlock(height: 180, radius: 20)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
            .sideRails(720)
        }
        .overlay(alignment: .top) { ConfettiBurst(trigger: burst).frame(height: 420).allowsHitTesting(false) }
        .sugarBackground()
        .navigationTitle("Top artists")
        .dropRemoved($artworks)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            if posts.posts.isEmpty { await posts.load() }
            artworks = ((try? await FS.query("Artwork", orderBy: "created_date", limit: 200)) ?? []).map(Artwork.init)
            withAnimation(Motion.pick(Motion.standard)) { loaded = true }
            try? await Task.sleep(for: .milliseconds(700))
            burst += 1
        }
        .onAppear { appeared = true }
    }

    // All time / This week / This month, with a sliding pill.
    private var rangeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(Array(["All time", "This week", "This month"].enumerated()), id: \.offset) { i, title in
                let on = range == i
                Button {
                    guard range != i else { return }
                    withAnimation(Motion.pick(Motion.standard)) { range = i }
                } label: {
                    Text(title).font(.jakarta(14, .semibold))
                        .foregroundStyle(on ? Palette.text : Palette.muted)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background {
                            if on {
                                Capsule().fill(Palette.surface)
                                    .shadow(color: Palette.shadow, radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "range", in: chip)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SoftPressStyle())
            }
        }
        .padding(3)
        .background(Palette.surface2, in: Capsule())
        .sensoryFeedback(.selection, trigger: range)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Self.gold)
                    .frame(width: 30, height: 30)
                    .background(Self.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .symbolEffect(.bounce, value: burst)
                Text("Top artists").font(.display(28)).foregroundStyle(Palette.text)
            }
            Text("The most loved artists on Sugerly. Post, get likes and climb the board.")
                .font(.jakarta(14)).foregroundStyle(Palette.muted)
        }
    }
}

// One board (for one time range): podium, your spot and everyone else. It
// plays its own rise once, when it appears.
private struct RankBoard: View {
    let list: [TopArtistsView.RankEntry]
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var risen = false

    var body: some View {
        let top = max(1, list.first?.likes ?? 1)
        let podiumCount = list.count >= 3 ? 3 : 0
        VStack(alignment: .leading, spacing: 20) {
            if podiumCount == 3 { podium(Array(list.prefix(3))) }
            if let me = model.me?.email, let mine = list.firstIndex(where: { $0.email == me }) {
                yourSpot(mine)
                    .opacity(risen ? 1 : 0)
                    .offset(y: risen ? 0 : 12)
                    .animation(Motion.reduced ? nil : Motion.enter.delay(0.3), value: risen)
            }
            let rest = Array(list.enumerated().dropFirst(podiumCount))
            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rest, id: \.element.email) { i, entry in
                        if i > podiumCount { Divider().padding(.leading, 96) }
                        row(entry, rank: i + 1, top: top)
                            .opacity(risen ? 1 : 0)
                            .offset(y: risen ? 0 : 14)
                            .animation(Motion.reduced ? nil : Motion.enter.delay(0.35 + Double(min(i, 14)) * 0.035), value: risen)
                    }
                }
                .sugarCard(radius: 20)
            }
            if list.isEmpty {
                EmptyCard(icon: "crown.fill", title: "No artists yet", text: "Nobody posted in this time yet. Post art to get on the board!", compact: true)
            }
        }
        .task {
            // One frame later, so the starting look is drawn first.
            try? await Task.sleep(for: .milliseconds(30))
            risen = true
        }
    }

    private func podium(_ top: [TopArtistsView.RankEntry]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            place(top[1], rank: 2, height: 84, color: TopArtistsView.silver, delay: 0.08)
            place(top[0], rank: 1, height: 116, color: TopArtistsView.gold, delay: 0.16)
            place(top[2], rank: 3, height: 64, color: TopArtistsView.bronze, delay: 0)
        }
        .padding(.top, 26)
        .padding(.horizontal, 12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func place(_ entry: TopArtistsView.RankEntry, rank: Int, height: CGFloat, color: Color, delay: Double) -> some View {
        let person = model.person(entry.email)
        let size: CGFloat = rank == 1 ? 72 : 58
        return Button { path.append(.person(entry.email)) } label: {
            VStack(spacing: 6) {
                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: size)
                    .padding(3)
                    .overlay(Circle().strokeBorder(color, lineWidth: rank == 1 ? 2.5 : 2))
                    .overlay(alignment: .top) {
                        if rank == 1 {
                            Image(systemName: "crown.fill").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(TopArtistsView.gold)
                                .offset(y: risen ? -22 : -40)
                                .opacity(risen ? 1 : 0)
                                .animation(Motion.reduced ? nil : Motion.playful.delay(delay + 0.42), value: risen)
                        }
                    }
                    .scaleEffect(risen ? 1 : 0.6)
                    .opacity(risen ? 1 : 0)
                    .animation(Motion.reduced ? nil : Motion.playful.delay(delay + 0.2), value: risen)
                Text(person?.displayName ?? "").font(.jakarta(13, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(11, .medium)).foregroundStyle(Palette.muted)
                // The pillar grows from the floor (a scale, so the text
                // inside never jumps around).
                Text("\(rank)").font(.display(rank == 1 ? 30 : 24)).foregroundStyle(color)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: height, alignment: .top)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                            .fill(color.opacity(0.16))
                    }
                    .scaleEffect(x: 1, y: risen ? 1 : 0.05, anchor: .bottom)
                    .animation(Motion.reduced ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(delay), value: risen)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
        .accessibilityLabel("Number \(rank), \(person?.displayName ?? ""), \(entry.likes) likes")
    }

    // Where you are on the board and how far to the next spot.
    private func yourSpot(_ index: Int) -> some View {
        let entry = list[index]
        let gap = index > 0 ? list[index - 1].likes - entry.likes + 1 : 0
        return HStack(spacing: 12) {
            Text("#\(index + 1)").font(.display(20)).foregroundStyle(Theme.main)
                .frame(width: 52, height: 52)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your spot").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                Text(index == 0 ? "You're the top artist. Keep that crown!" : "\(gap) more like\(gap == 1 ? "" : "s") to reach #\(index)")
                    .font(.jakarta(13)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(14, .semibold)).foregroundStyle(Theme.main)
        }
        .sugarCard(radius: 18, padding: 12)
    }

    private func row(_ entry: TopArtistsView.RankEntry, rank: Int, top: Int) -> some View {
        let person = model.person(entry.email)
        let share = CGFloat(entry.likes) / CGFloat(top)
        return Button { path.append(.person(entry.email)) } label: {
            HStack(spacing: 12) {
                Text("\(rank)").font(.jakarta(15, .semibold)).foregroundStyle(Palette.muted).monospacedDigit().frame(width: 28)
                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 40, online: person?.isOnline ?? false)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(person?.displayName ?? "").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("\(entry.works) works").font(.jakarta(12)).foregroundStyle(Palette.muted)
                    }
                    Capsule().fill(Palette.surface2)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(Theme.main.opacity(0.7))
                                    .frame(width: max(6, geo.size.width * share))
                                    .scaleEffect(x: risen ? 1 : 0, anchor: .leading)
                                    .animation(Motion.reduced ? nil : Motion.drawer.delay(0.45 + Double(min(rank, 14)) * 0.035), value: risen)
                            }
                        }
                }
                Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(13, .medium)).foregroundStyle(Palette.muted)
                FollowButton(email: entry.email, compact: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
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
        AppRelease(id: "ios-3.4", icon: "wand.and.stars", title: "The real bunny, a brighter menu and Community", date: "2026-10-18T10:00:00Z", items: [
            "Your bunny is now drawn from the artist's own layers: crisp outlines, nine faces (cute, happy, silly, shy, smug, worried, dreamy, meh, grumpy) that blink, and clothes you mix and match: a sailor top, a skirt, a pinafore, bloomers, or both layered.",
            "The bow can come off, and every piece of clothing changes colour together.",
            "A brighter menu: your bunny says hi next to your name, your wallet and MimiPlus are colourful cards, and places are big candy tiles.",
            "Community has a bright hello card with who's online and how many posts there were today, feed tabs that always fit the screen (the chosen one shows its name), colourful hashtags, and likes and saves in colour.",
            "The + menu's choices are bright candy cards, and Chats shows the friends who are online right now.",
        ]),
        AppRelease(id: "ios-3.3", icon: "hare.fill", title: "Your own bunny, and a livelier app", date: "2026-10-18T02:00:00Z", items: [
            "Bunny maker: dress up your own bunny. Pick her fur, bow, collar and outfit colours, her face (wink, sleepy, love eyes…), a little extra (crown, daisy, heart specs, halo…) and a scene. Save her to Photos or make her your profile picture.",
            "Your bunny lives on Home: she bobs, blinks, and jumps with a puff of hearts when you tap her. Hold her to dress her up.",
            "Colour is back: soft glows of colour drift behind every page, your moving pattern is back at the top of Home (pick it in Settings → Background), and buttons, chips and cards have juicy gradients again.",
            "Home shortcuts are big colourful tiles in two rows, so every name fits.",
            "Lots of new little animations: sparkles in your hello card, a shine across buttons, hopping icons, a wiggling present when your daily reward is waiting.",
        ]),
        AppRelease(id: "ios-3.2", icon: "paintpalette.fill", title: "A cleaner, juicier look", date: "2026-10-17T23:30:00Z", items: [
            "Calmer pages: a clean off-white background with crisp white cards, instead of pink on pink.",
            "Colourful candy icons for places and actions: music is sky blue, servers mint, people grape, rewards lemon, posts berry and reels peach, everywhere in the app.",
            "Home is tidier: your coins, level and friends online sit in three even tiles, shortcuts are one neat row that fits the screen, and the \"What are you making today?\" bar has a button for each thing you can make.",
            "With bigger text turned on in iPhone Settings, words no longer get cut off or pushed off the screen.",
        ]),
        AppRelease(id: "ios-3.1", icon: "camera.fill", title: "A brand-new camera", date: "2026-10-17T22:00:00Z", items: [
            "The camera has been rebuilt from scratch: it opens faster, and the window is exactly the shape of your reel, so what you see is what you get.",
            "Switch lenses with the .5, 1, 2 and 3 buttons (ultra wide and zoom on iPhones that have them), or pinch.",
            "Live filters: tap Filters, or swipe sideways on the camera. The filter you pick is already on when the editor opens.",
            "Tap to focus and slide up or down for brighter or darker. Hold to lock focus and light.",
            "A new record button and clip bar. Tap delete once to see which clip goes, twice to delete it.",
            "Mixing front and back camera clips, or slow and fast ones, always comes out the right way round.",
        ]),
        AppRelease(id: "ios-3.0", icon: "video.fill", title: "Better calls", date: "2026-10-17T20:00:00Z", items: [
            "Leave Sugerly during a video call and it keeps going in a small floating window, like FaceTime. Tap it to come back.",
            "Video calls fill the whole screen. Tap the picture to hide or show the buttons, and drag your own little camera to any corner.",
            "Sharper video (HD), and calls reconnect by themselves when you switch between Wi-Fi and mobile data. You'll see \"Reconnecting…\" while it happens.",
            "Turning your camera on switches to the speaker, and the buttons follow your AirPods. Holding the phone to your ear turns the screen off, like a normal call.",
            "Calls use much less data in the background.",
            "Editor: names on the timeline are never cut off, and stickers are much smoother (no more lag).",
            "Reels: photo slides stay put until you swipe, and landscape drawings show whole instead of being cut off.",
        ]),
        AppRelease(id: "ios-2.9", icon: "person.crop.circle", title: "New profiles", date: "2026-10-17T15:00:00Z", items: [
            "A fresh look for profiles: your picture in the middle, your name, level and status under it, your numbers in one card, and Posts, Art, Reels and Saved tabs that always fit on the screen.",
            "No more rings or frames around profile pictures, on profiles or in the menu button.",
            "The menu, search and bell buttons at the top stay light in light mode, even over dark pictures.",
            "Collecting your daily reward bursts with little coins and sparkles.",
            "Reels: the loading line stays in its place at the bottom instead of floating around.",
            "Video calls fill the screen like FaceTime. Double-tap to see the whole picture.",
        ]),
        AppRelease(id: "ios-2.8", icon: "server.rack", title: "A new home for Sugerly's server", date: "2026-10-17T12:00:00Z", items: [
            "Login codes, card payments and calls now go to Sugerly's new server, with the old one as a backup, so they keep working even if one of them is down.",
        ]),
        AppRelease(id: "ios-2.7", icon: "number", title: "Hashtags everywhere", date: "2026-10-17T08:00:00Z", items: [
            "One set of #hashtags for posts, reels, drawings and songs. Tap any #tag to see everything with it in one place, newest or most loved.",
            "Trending tags from all of Sugerly on Home and in Community, and search finds hashtags too.",
            "A smarter For You: what you like in reels, posts and drawings teaches it your favourite tags, and it brings you more of them.",
            "Calls show iPhone's own call screen with Accept and Decline, your ringtone and vibration, even while the app is open.",
            "Calmer, tidier colours: one pink for everything, gold only for coins, crowns and stars, green for online and red for delete.",
            "The bell and menu buttons at the top no longer turn black when you scroll in light mode.",
        ]),
        AppRelease(id: "ios-2.6", icon: "wand.and.stars", title: "Steadier and comfier", date: "2026-10-16T22:00:00Z", items: [
            "Tapping the camera button quickly during a call no longer freezes the app.",
            "Stickers and GIFs use far less memory, so chats and the editor's sticker picker don't crash any more.",
            "Dark mode is calmer: no more white shine and pink glow on cards and buttons.",
            "No more black flashes when opening and closing drawings, posts and reels.",
            "Reels show a thin light along the bottom while a video loads, instead of the dots bubble.",
            "Cleaner upload pages: a big button at the bottom, a tidy photo picker, and a progress bar while it uploads.",
        ]),
        AppRelease(id: "ios-2.5", icon: "paintpalette.fill", title: "A pastel Sugerly", date: "2026-10-16T21:00:00Z", items: [
            "A whole new pastel look from one palette: cream, ivory, blush, pink and rose. Pick another colour and the pinks follow it.",
            "Juicier buttons, chips and cards, with soft rosy shadows and springy taps.",
            "Every page redesigned: Home, Community, Fan art, chats, profiles, Music, Servers, People, Commissions, Wallet, MimiPlus and What's new.",
            "Smoother animations everywhere: pages rise in, feeds and filters crossfade instead of jumping, posts glide in as you scroll, and the Top artists podium grows up when you switch between all time, week and month.",
            "Reels load with a soft placeholder and only show the loading dots if a video takes a moment.",
            "The weekly challenge and this week's top creators are back at the top of Community.",
        ]),
        AppRelease(id: "ios-2.4", icon: "sparkles", title: "A calmer, cleaner Sugerly", date: "2026-10-16T12:00:00Z", items: [
            "New Wallet: see your coins, every way to earn more, and what you can spend them on.",
            "MimiPlus explained simply: what you get, what it costs in coins, and how close you are.",
            "Drawings, posts and reels grow right out of the card you tap, and shrink back when you go back.",
            "Stickers have a smooth white edge and no more grey box behind them.",
            "Chat no longer jumps around while you send messages.",
        ]),
        AppRelease(id: "ios-2.2", icon: "key.horizontal.fill", title: "New ways to log in", date: "2026-10-10T12:00:00Z", items: [
            "Log in with a code sent to your email, no password needed. Forgot your password? Get a code and pick a new one right in the app.",
            "Quick login: a new iPhone or iPad shows a QR code; scan it from Settings → Log in another device on a phone where you're logged in.",
            "Backup codes in Settings → Login & security, for when you can't get your emails.",
            "A cleaner reel timeline with an iPhone-style trim frame, and a tidier front light with colour swatches by the flash button.",
            "Going back from the editor to the camera fades in softly instead of a black screen. Chat messages pop in from their side.",
        ]),
        AppRelease(id: "ios-2.1", icon: "sparkles", title: "New MimiPlus & a smoother editor", date: "2026-09-29T15:00:00Z", items: [
            "MimiPlus is all new: see yourself with the perks before you get it, pick 1 or 3 months, and see how close you are.",
            "Trimming videos is smoother: drag the ends without jumps, slide the whole selection, and see the exact times.",
            "The timeline has a time ruler, a clearer playhead and bars that show how long each overlay lasts.",
            "Artists add their payout details before taking paid requests, so every payment has somewhere to go.",
        ]),
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

// The newest release sits on the palette; older ones on plain cards.
private struct ReleaseCard: ViewModifier {
    let highlight: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if highlight {
            content.pastelCard(radius: 22, padding: 14)
        } else {
            content.sugarCard(radius: 22, padding: 14)
        }
    }
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
                        Image(systemName: r.icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.main).frame(width: 46, height: 46)
                            .background(Palette.blush, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.rim(0.6), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(r.title).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                                if i == 0 {
                                    Text("New").font(.jakarta(11, .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).frame(height: 20)
                                        .background(Theme.candy, in: Capsule())
                                }
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
                        .modifier(ReleaseCard(highlight: i == 0))
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
