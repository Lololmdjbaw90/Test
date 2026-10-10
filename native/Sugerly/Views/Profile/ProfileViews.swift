import SwiftUI
import UIKit
import PhotosUI

// Anyone's profile — yours too (with Edit and Settings).
struct PersonView: View {
    let email: String
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var loaded: UserProfile?
    @State private var reporting: ReportSheet.Target?
    @State private var confirmBlock = false

    private var person: UserProfile? {
        if model.me?.email == email.lowercased() { return model.me }
        return model.person(email) ?? loaded
    }
    private var isMe: Bool { model.me?.email == email.lowercased() }
    private var isBlocked: Bool { model.me?.blocked.contains(email.lowercased()) ?? false }

    var body: some View {
        Group {
            if let person {
                ProfileContent(person: person, isMe: isMe, path: $path,
                               onReport: { reporting = ReportSheet.Target(id: person.email, type: "user", ownerEmail: person.email, preview: person.displayName, link: "/Profile?email=\(person.email)") },
                               onBlock: { confirmBlock = true }, isBlocked: isBlocked)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).sugarBackground()
            }
        }
        .navigationTitle(person?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isMe, let person {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { reporting = ReportSheet.Target(id: person.email, type: "user", ownerEmail: person.email, preview: person.displayName, link: "/Profile?email=\(person.email)") } label: { Label("Report", systemImage: "flag") }
                        let ignoring = model.me?.ignored.contains(person.email) ?? false
                        Button { Task { await Privacy.setIgnored(person.email, !ignoring, model: model) } } label: {
                            Label(ignoring ? "Stop ignoring" : "Ignore", systemImage: ignoring ? "bell.fill" : "bell.slash.fill")
                        }
                        Button(role: .destructive) { confirmBlock = true } label: { Label(isBlocked ? "Unblock" : "Block", systemImage: "hand.raised") }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .confirmationDialog(isBlocked ? "Unblock \(person?.displayName ?? "")?" : "Block \(person?.displayName ?? "")?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button(isBlocked ? "Unblock" : "Block", role: .destructive) { toggleBlock() }
        } message: {
            Text(isBlocked ? "You'll see their posts and messages again." : "You won't see their posts, comments or messages, and they can't message you. They won't be told.")
        }
        .task {
            if person == nil, let docs = try? await FS.query("User", [.equals("email", email.lowercased())], limit: 1), let doc = docs.first {
                loaded = UserProfile(doc)
            }
        }
    }

    private func toggleBlock() {
        guard let me = model.me else { return }
        let target = email.lowercased()
        var next = me.blocked
        var following = me.following
        if next.contains(target) { next.removeAll { $0 == target } } else { next.append(target); following.removeAll { $0 == target } }
        Task { try? await model.updateMe(["blocked": next, "following": following]) }
    }
}

struct ProfileContent: View {
    enum Tab: String, CaseIterable { case posts = "Posts", art = "Art", reels = "Reels", saved = "Saved" }

    let person: UserProfile
    let isMe: Bool
    @Binding var path: [Route]
    // Someone else's profile: Report and Block right next to Follow, so
    // they're easy to find (App Store rule for user content).
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var isBlocked = false

    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var posts: [Post] = []
    @State private var reels: [Reel] = []
    @State private var art: [Artwork] = []
    @State private var savedPosts: [Post] = []
    @State private var savedReels: [Reel] = []
    @State private var savedArt: [Artwork] = []
    @State private var loading = true
    @State private var tab: Tab = .posts
    @State private var editing = false
    @State private var settings = false
    @State private var shop = false
    @State private var appeared = false
    @State private var statusSheet = false
    @State private var loadingMore = false

    private var following: Bool { model.me?.following.contains(person.email) ?? false }
    // Counted by the database, so it's right however many people there are.
    @State private var followers = 0
    private var totalLikes: Int { posts.reduce(0) { $0 + $1.likeTotal } }
    // Three across on iPhone, four on iPad.
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: sizeClass == .regular ? 4 : 3) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner.stagger(appeared, 0)
                VStack(alignment: .leading, spacing: 14) {
                    identity.stagger(appeared, 1)
                    if !person.bio.isEmpty { Text(person.bio).font(.jakarta(15)).foregroundStyle(Palette.text).stagger(appeared, 2) }
                    buttons.stagger(appeared, 2)
                    stats.stagger(appeared, 3)
                    if isMe { XPBar(info: LevelInfo(xp: person.xp)).sugarCard(radius: 22, padding: 14).stagger(appeared, 4) }
                    tabs.stagger(appeared, 4)
                    grid.stagger(appeared, 5)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
            .sideRails(720)
        }
        .background(alignment: .top) {
            if let accent {
                LinearGradient(colors: [accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 420).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .sugarBackground()
        .onAppear { appeared = true }
        .refreshable { await load(); await loadSaved() }
        .task(id: person.email) { await load() }
        .task(id: savedKey) { await loadSaved() }
        .dropRemoved($posts)
        .dropRemoved($reels)
        .dropRemoved($art)
        .sheet(isPresented: $editing) { EditProfileView() }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView(closable: true) } }
        .sheet(isPresented: $shop) { NitroShopView() }
        .sheet(isPresented: $statusSheet) { StatusSheet().presentationCornerRadius(30) }
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                if person.banner.isEmpty {
                    bannerGradient
                    Circle().fill(.white.opacity(0.25)).frame(width: 180).blur(radius: 40).offset(x: 120, y: -40)
                    Circle().fill(Theme.lavender.opacity(0.5)).frame(width: 160).blur(radius: 50).offset(x: -120, y: 40)
                } else {
                    RemoteImage(url: person.banner, live: true)
                }
                if !person.bannerPattern.isEmpty { BannerPatternView(pattern: person.bannerPattern) }
                if person.isNitro && !person.profileEffect.isEmpty {
                    ProfileEffectLayer(effect: person.profileEffect, color: person.effectColor, amount: person.effectAmount,
                                       paused: settings || editing || shop || statusSheet)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 12)

            // One ring at a time: a chosen frame replaces the plain / MimiPlus
            // ring (both at once used to draw over each other).
            let framed = !person.avatarFrame.isEmpty && (person.isNitro || !AvatarFrame.isPremium(person.avatarFrame))
            Avatar(url: person.picture, name: person.displayName, size: 104, ring: !framed && !person.isNitro, nitro: !framed && person.isNitro)
                .padding(4)
                .background(Circle().fill(Palette.bg).shadow(color: (accent ?? Theme.pink).opacity(0.3), radius: 16, y: 8))
                .overlay {
                    if framed { AvatarFrameView(frame: person.avatarFrame, color: accent ?? Theme.main, size: 104) }
                }
                // The status dot goes on top of the frame, not under it.
                .overlay(alignment: .bottomTrailing) {
                    PresenceBadge(presence: isMe ? (Presence(rawValue: person.presence) ?? .online) : person.presenceNow, size: 104)
                        .padding(4)
                }
                .offset(x: 26, y: 56)
        }
        .padding(.top, 8)
        // Room for the picture that hangs below the banner, so it never
        // covers the name.
        .padding(.bottom, 72)
    }

    private var accent: Color? { ProfileColors.color(person.profileColor) }

    @ViewBuilder private var bannerGradient: some View {
        if let c = ProfileColors.color(person.bannerColor) {
            LinearGradient(colors: [c, accent ?? Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if person.isNitro {
            LinearGradient(colors: [Color(hex: 0x8B5CF6), Color(hex: 0xC084FC), Color(hex: 0xEE8FAE), Color(hex: 0x7CBEFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Theme.gradient
        }
    }

    private var identity: some View {
        let info = LevelInfo(xp: person.xp)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NameText(name: person.displayName, style: person.nameStyle, size: 34, display: true, nitro: person.isNitro, tint: person.nameColor)
                if !person.pronouns.isEmpty { Text(person.pronouns).font(.jakarta(14, .semibold)).foregroundStyle(Palette.muted) }
            }
            statusBubble
            FlowLayout(spacing: 8) {
                if person.isNitro { NitroBadge() }
                if person.isAdmin {
                    Label("Admin", systemImage: "shield.fill").font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.pink.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.pink.opacity(0.3), lineWidth: 1))
                }
                Label("Lv.\(info.level) · \(info.title)", systemImage: "bolt.fill").font(.jakarta(12, .bold)).foregroundStyle(info.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(info.color.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(info.color.opacity(0.3), lineWidth: 1))
                if person.dailyStreak > 1 {
                    Label("\(person.dailyStreak)-day streak", systemImage: "flame.fill").font(.jakarta(12, .bold)).foregroundStyle(Color(hex: 0xF08A20))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(hex: 0xF08A20).opacity(0.12), in: Capsule())
                }
                if let joined = Dates.parse(person.joined) {
                    Label("Joined \(joined.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "calendar").font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                }
            }
            if !person.interests.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(person.interests, id: \.self) { tag in
                        Text(tag).font(.jakarta(12, .bold)).foregroundStyle(accent ?? Theme.main)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((accent ?? Theme.main).opacity(0.1), in: Capsule())
                    }
                }
            }
            if !person.website.isEmpty, let url = URL(string: person.website.hasPrefix("http") ? person.website : "https://\(person.website)") {
                Link(destination: url) {
                    Label(person.website.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""), systemImage: "link")
                        .font(.jakarta(13, .bold)).foregroundStyle(accent ?? Theme.main).lineLimit(1)
                }
            }
        }
    }

    // Presence + custom status, like Discord. Tap your own to change it.
    @ViewBuilder private var statusBubble: some View {
        let presence: Presence = isMe ? (Presence(rawValue: person.presence) ?? .online) : person.presenceNow
        let text = person.activeStatus
        if isMe || !text.isEmpty || presence != .offline {
            Button { if isMe { statusSheet = true } } label: {
                HStack(spacing: 8) {
                    PresenceDot(presence: presence == .offline && isMe ? .online : presence, size: 14)
                    Text(text.isEmpty ? (isMe ? "Set a status" : presence.label) : text)
                        .font(.jakarta(13, .semibold)).foregroundStyle(text.isEmpty && isMe ? Palette.muted : Palette.text2)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if isMe { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted) }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            }
            .buttonStyle(BouncyStyle(scale: 0.97))
            .allowsHitTesting(isMe)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if isMe {
                Button { editing = true } label: { Label("Edit profile", systemImage: "pencil") }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
                Button { shop = true } label: { Image(systemName: "sparkles").font(.system(size: 17, weight: .bold)) }
                    .buttonStyle(OutlineButtonStyle())
                    .accessibilityLabel("MimiPlus")
                Button { settings = true } label: { Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .bold)) }
                    .buttonStyle(OutlineButtonStyle())
            } else {
                MorphPill(on: following, offTitle: "Follow", onTitle: "Following", offIcon: "person.badge.plus",
                          size: .large, fullWidth: true) { toggleFollow() }
                Button { openChat() } label: { Label("Message", systemImage: "paperplane.fill") }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
                if onReport != nil || onBlock != nil {
                    Menu {
                        if let onReport { Button(action: onReport) { Label("Report", systemImage: "flag") } }
                        if let onBlock {
                            Button(role: .destructive, action: onBlock) { Label(isBlocked ? "Unblock" : "Block", systemImage: "hand.raised") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                            .foregroundStyle(Palette.text2)
                    }
                    .accessibilityLabel("More: report or block")
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(posts.count, "POSTS")
            divider
            stat(totalLikes, "LIKES")
            divider
            stat(followers, "FOLLOWERS")
            divider
            stat(person.following.count, "FOLLOWING")
        }
        .padding(.vertical, 14)
        .sugarCard(radius: 24)
    }

    private var divider: some View { Rectangle().fill(Palette.border).frame(width: 1, height: 34) }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(n)").font(.display(26)).foregroundStyle(Palette.text).monospacedDigit()
            Text(label).font(.jakarta(10, .bold)).tracking(0.6).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var tabs: some View {
        let list = Tab.allCases.filter { isMe || $0 != .saved }
        let options: [(String, String)] = list.map { t in
            switch t {
            case .posts: return (t.rawValue, "square.grid.2x2.fill")
            case .art: return (t.rawValue, "paintpalette.fill")
            case .reels: return (t.rawValue, "play.rectangle.fill")
            case .saved: return (t.rawValue, "bookmark.fill")
            }
        }
        return SectionSwitch(options: options, selection: Binding(get: { list.firstIndex(of: tab) ?? 0 }, set: { i in withMotion(Motion.standard) { tab = list[i] } }))
    }

    @ViewBuilder
    private var grid: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(30)
        } else {
            switch tab {
            case .posts:
                if posts.isEmpty { EmptyCard(icon: "photo.on.rectangle.angled", title: isMe ? "Share your first post" : "No posts yet", text: isMe ? "Tap + to post to the community." : "Nothing to see here yet.") }
                postGrid(posts)
            case .art:
                if art.isEmpty { EmptyCard(icon: "paintpalette.fill", title: isMe ? "Hang up your first drawing" : "No fan art yet", text: isMe ? "Tap + → Fan art to share a drawing." : "Nothing on the wall yet.") }
                artGrid(art)
            case .reels:
                if reels.isEmpty { EmptyCard(icon: "play.rectangle.fill", title: "No reels yet", text: isMe ? "Tap + → Create a reel." : "Nothing to see here yet.") }
                reelGrid(reels)
            case .saved:
                if savedPosts.isEmpty && savedReels.isEmpty && savedArt.isEmpty { EmptyCard(icon: "bookmark.fill", title: "Nothing saved", text: "Tap the bookmark on any post, reel or fan art to keep it here.") }
                if !savedReels.isEmpty {
                    Label("Reels", systemImage: "play.rectangle.fill").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2)
                    reelGrid(savedReels)
                }
                if !savedPosts.isEmpty {
                    Label("Posts", systemImage: "square.grid.2x2.fill").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2).padding(.top, 6)
                    postGrid(savedPosts)
                }
                if !savedArt.isEmpty {
                    Label("Fan art", systemImage: "paintpalette.fill").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2).padding(.top, 6)
                    artGrid(savedArt)
                }
            }
        }
    }

    private func reelGrid(_ list: [Reel]) -> some View {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(list) { reel in
                        Button { path.append(.reel(reel)) } label: {
                            Rectangle().fill(Palette.surface2)
                                .aspectRatio(9 / 16, contentMode: .fit)
                                .overlay { RemoteImage(url: reel.coverURL.isEmpty ? (reel.isVideo ? "" : reel.pictures.first ?? "") : reel.coverURL) }
                                .overlay(alignment: .bottomLeading) {
                                    Label("\(reel.views)", systemImage: "play.fill").font(.jakarta(11, .bold)).foregroundStyle(.white).shadow(radius: 3).padding(6)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.95))
                        .onAppear { if reel.id == list.last?.id && tab == .reels { Task { await moreReels() } } }
                    }
                }
    }

    private func artGrid(_ list: [Artwork]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(list) { art in
                Button { path.append(.artwork(art)) } label: {
                    Rectangle().fill(Palette.surface2)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { RemoteImage(url: art.imageURL) }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(BouncyStyle(scale: 0.95))
            }
        }
    }

    private func postGrid(_ list: [Post]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(list) { post in
                Button { path.append(.post(post)) } label: {
                    Rectangle()
                        .fill(post.imageURL.isEmpty ? AnyShapeStyle(Theme.gradient.opacity(0.85)) : AnyShapeStyle(Palette.surface2))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if post.imageURL.isEmpty {
                                Text(post.title.isEmpty ? post.text : post.title)
                                    .font(.jakarta(12, .bold)).foregroundStyle(.white).lineLimit(5).padding(8)
                            } else {
                                RemoteImage(url: post.imageURL)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(BouncyStyle(scale: 0.95))
                .onAppear { if post.id == list.last?.id && tab == .posts { Task { await morePosts() } } }
            }
        }
    }

    private func load() async {
        defer { loading = false }
        async let followerCount = try? FS.count("User", [.contains("following", person.email)])
        async let postDocs = try? FS.query("CommunityPost", [.equals("user_email", person.email)], orderBy: "created_date", limit: 90)
        async let reelDocs = try? FS.query("Reel", [.equals("user_email", person.email)], orderBy: "created_date", limit: 60)
        async let artDocs = Self.artworks(by: person.email)
        posts = (await postDocs ?? []).map(Post.init)
        reels = (await reelDocs ?? []).map(Reel.init)
        art = await artDocs
        if let n = await followerCount { followers = n }
        for post in posts where !store.posts.contains(where: { $0.id == post.id }) { store.posts.append(post) }
    }

    // Someone's fan art, newest first. (Without the sorted search's index
    // yet, it asks for all of theirs and sorts them here.)
    static func artworks(by email: String) async -> [Artwork] {
        let newest = try? await FS.query("Artwork", [.equals("user_email", email)], orderBy: "created_date", limit: 90)
        if let newest { return newest.map(Artwork.init) }
        let docs = (try? await FS.query("Artwork", [.equals("user_email", email)], limit: 200)) ?? []
        return docs.map(Artwork.init).sorted { $0.created > $1.created }
    }

    // Changes whenever you save or unsave something, so the Saved tab follows along.
    private var savedKey: String {
        guard isMe, let me = model.me else { return "" }
        return [me.savedPosts.joined(separator: ","), me.savedReels.joined(separator: ","), me.savedArtworks.joined(separator: ",")].joined(separator: "|")
    }

    // Older posts and reels load as you reach the end of the grid.
    private func morePosts() async {
        guard !loadingMore, let oldest = posts.last?.created, posts.count >= 30 else { return }
        loadingMore = true
        defer { loadingMore = false }
        let docs = (try? await FS.query("CommunityPost", [.equals("user_email", person.email), .before("created_date", oldest)], orderBy: "created_date", limit: 60)) ?? []
        let known = Set(posts.map(\.id))
        posts += docs.map(Post.init).filter { !known.contains($0.id) }
    }

    private func moreReels() async {
        guard !loadingMore, let oldest = reels.last?.created, reels.count >= 30 else { return }
        loadingMore = true
        defer { loadingMore = false }
        let docs = (try? await FS.query("Reel", [.equals("user_email", person.email), .before("created_date", oldest)], orderBy: "created_date", limit: 60)) ?? []
        let known = Set(reels.map(\.id))
        reels += docs.map(Reel.init).filter { !known.contains($0.id) }
    }

    // Your saved posts, reels and fan art (newest saves first). Unsaved ones
    // go at once; new ones are fetched together in one request per kind.
    private func loadSaved() async {
        guard isMe, let me = model.me else { return }
        let postIds = Array(me.savedPosts.reversed().prefix(60))
        let reelIds = Array(me.savedReels.reversed().prefix(60))
        let artIds = Array(me.savedArtworks.reversed().prefix(60))
        withMotion(Motion.standard) {
            savedPosts = savedPosts.filter { postIds.contains($0.id) }
            savedReels = savedReels.filter { reelIds.contains($0.id) }
            savedArt = savedArt.filter { artIds.contains($0.id) }
        }
        func missing(_ ids: [String], _ have: [String]) -> [String] { ids.filter { !have.contains($0) } }
        let knownPosts = store.posts.filter { postIds.contains($0.id) }
        async let postFetch = try? FS.getMany("CommunityPost", missing(postIds, (savedPosts + knownPosts).map(\.id)))
        async let reelFetch = try? FS.getMany("Reel", missing(reelIds, savedReels.map(\.id)))
        async let artFetch = try? FS.getMany("Artwork", missing(artIds, savedArt.map(\.id)))
        let postDocs: [String: Doc] = (await postFetch) ?? [:]
        let reelDocs: [String: Doc] = (await reelFetch) ?? [:]
        let artDocs: [String: Doc] = (await artFetch) ?? [:]
        var postsById: [String: Post] = [:]
        for post in savedPosts + knownPosts { postsById[post.id] = post }
        for (id, doc) in postDocs { postsById[id] = Post(doc) }
        var reelsById: [String: Reel] = [:]
        for reel in savedReels { reelsById[reel.id] = reel }
        for (id, doc) in reelDocs { reelsById[id] = Reel(doc) }
        var artById: [String: Artwork] = [:]
        for art in savedArt { artById[art.id] = art }
        for (id, doc) in artDocs { artById[id] = Artwork(doc) }
        withMotion(Motion.standard) {
            savedPosts = postIds.compactMap { postsById[$0] }
            savedReels = reelIds.compactMap { reelsById[$0] }
            savedArt = artIds.compactMap { artById[$0] }
        }
    }

    private func toggleFollow() {
        guard let me = model.me else { return }
        var next = me.following
        let starting = !next.contains(person.email)
        if starting { next.append(person.email) } else { next.removeAll { $0 == person.email } }
        Task {
            try? await model.updateMe(["following": next])
            if starting { Notify.send(to: person.email, from: me, type: "follow", message: "\(me.displayName) started following you", link: "/Profile?email=\(me.email)") }
        }
    }

    private func openChat() {
        guard let me = model.me?.email else { return }
        let c = Conversation(id: Social.dmId(me, person.email), members: [me, person.email], isGroup: false, groupName: "", last: nil, unread: 0)
        path.append(.chat(c))
    }
}

// MARK: - Edit profile

// A new picture waiting to be uploaded: a photo, a GIF file or a GIF link.
enum PendingPicture: Equatable {
    case image(UIImage)
    case gif(Data, UIImage)
    case link(String)

    static func == (a: PendingPicture, b: PendingPicture) -> Bool {
        switch (a, b) {
        case let (.image(x), .image(y)): return x === y
        case let (.gif(x, _), .gif(y, _)): return x == y
        case let (.link(x), .link(y)): return x == y
        default: return false
        }
    }
}

struct CropJob: Identifiable {
    let id = UUID()
    let image: UIImage
    let gif: Data?
    let avatar: Bool
}

struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pronouns = ""
    @State private var status = ""
    @State private var bio = ""
    @State private var website = ""
    @State private var interests = ""
    @State private var nameStyle = "default"
    @State private var bannerColor = ""
    @State private var profileColor = ""
    @State private var effect = ""
    @State private var effectColor = ""
    @State private var effectAmount = 16
    @State private var nameColor = ""
    @State private var frame = ""
    @State private var pattern = ""
    @State private var avatar: PendingPicture?
    @State private var banner: PendingPicture?
    @State private var removeBanner = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickingFor: Bool?          // true = avatar, false = banner
    @State private var showPicker = false
    @State private var gifFor: Bool?
    @State private var cropping: CropJob?
    @State private var shop = false
    @State private var saving = false
    @State private var error: String?

    private var nitro: Bool { model.me?.isNitro ?? false }

    var body: some View {
        ComposerScaffold(title: "Edit profile", actionTitle: "Save", busy: saving, canPost: true, status: "Saving your profile…", error: error,
                         onClose: { dismiss() }, onPost: { Task { await save() } }) {
            pictures
            nitroCard

            field("Display name") { SugarField(placeholder: "Your name", text: $name) }
            HStack(alignment: .top, spacing: 10) {
                field("Pronouns") { SugarField(placeholder: "she/her", text: $pronouns) }
                field("Status") { SugarField(placeholder: "Drawing cats today", text: $status) }
            }
            field("Bio") { SugarField(placeholder: "A few words about you and your art", text: $bio, lines: 3...6) }
            field("Interests") { SugarField(placeholder: "anime, watercolor, cats", text: $interests) }
            field("Website") { SugarField(placeholder: "yoursite.com", text: $website) }

            lookPreview
            styleSection
            colorSection("Name colour", selection: $nameColor)
            colorSection("Banner colour", selection: $bannerColor)
            colorSection("Profile colour (buttons, frame)", selection: $profileColor)
            patternSection
            frameSection
            effectSection
        }
        .onAppear(perform: fill)
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item, let forAvatar = pickingFor else { return }
            pickerItem = nil
            Task { await picked(item, avatar: forAvatar) }
        }
        .sheet(item: Binding(get: { gifFor.map { GifTarget(avatar: $0) } }, set: { gifFor = $0?.avatar })) { target in
            GifPickerSheet { url in
                withMotion(Motion.standard) {
                    if target.avatar { avatar = .link(url) } else { banner = .link(url); removeBanner = false }
                }
            }
        }
        .fullScreenCover(item: $cropping) { job in
            ImageCropper(image: job.image, circle: job.avatar, aspect: job.avatar ? 1 : 3, onDone: { rect in
                cropping = nil
                Task { await applyCrop(job, rect) }
            }, onCancel: { cropping = nil })
        }
        .sheet(isPresented: $shop) { NitroShopView() }
    }

    struct GifTarget: Identifiable { let avatar: Bool; var id: Bool { avatar } }

    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pictures

    private var pictures: some View {
        VStack(spacing: 0) {
            Menu {
                Button { pickingFor = false; showPicker = true } label: { Label("Choose a photo", systemImage: "photo") }
                Button { nitroOnly { gifFor = false } } label: { Label(nitro ? "Choose a GIF" : "Choose a GIF (MimiPlus)", systemImage: "photo.stack") }
                if hasBanner { Button(role: .destructive) { withMotion { banner = nil; removeBanner = true } } label: { Label("Remove banner", systemImage: "trash") } }
            } label: {
                ZStack {
                    bannerPreview
                    if nitro && !effect.isEmpty { ProfileEffectLayer(effect: effect) }
                    Label("Change banner", systemImage: "camera.fill").font(.jakarta(13, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.35), in: Capsule())
                }
                .frame(height: 140).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }

            Menu {
                Button { pickingFor = true; showPicker = true } label: { Label("Choose a photo", systemImage: "photo") }
                Button { nitroOnly { gifFor = true } } label: { Label(nitro ? "Choose a GIF" : "Choose a GIF (MimiPlus)", systemImage: "photo.stack") }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarPreview
                    Image(systemName: "camera.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Theme.gradient, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 3))
                }
            }
            .padding(.top, -52)
        }
    }

    private var hasBanner: Bool { banner != nil || (!removeBanner && !(model.me?.banner ?? "").isEmpty) }

    @ViewBuilder private var bannerPreview: some View {
        switch banner {
        case .image(let img)?: Image(uiImage: img).resizable().scaledToFill()
        case .gif(let data, _)?: LiveGIF(data: data)
        case .link(let url)?: RemoteImage(url: url, live: true)
        case nil:
            if !removeBanner, let url = model.me?.banner, !url.isEmpty { RemoteImage(url: url, live: true) } else { bannerGradient }
        }
    }

    private var bannerGradient: some View {
        let c = ProfileColors.color(bannerColor)
        return Group {
            if let c { LinearGradient(colors: [c, Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing) }
            else if nitro { NitroStyle.gradient }
            else { Theme.gradient }
        }
    }

    @ViewBuilder private var avatarPreview: some View {
        Group {
            switch avatar {
            case .image(let img)?: Image(uiImage: img).resizable().scaledToFill().frame(width: 104, height: 104).clipShape(Circle())
            case .gif(let data, _)?: LiveGIF(data: data).frame(width: 104, height: 104).clipShape(Circle())
            case .link(let url)?: Avatar(url: url, name: name, size: 104)
            case nil: Avatar(url: model.me?.picture ?? "", name: name, size: 104)
            }
        }
        .padding(4)
        .background(Circle().fill(Palette.bg))
    }

    private func nitroOnly(_ action: () -> Void) {
        if nitro { action() } else { shop = true }
    }

    private func picked(_ item: PhotosPickerItem, avatar forAvatar: Bool) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let isGIF = data.prefix(4) == Data("GIF8".utf8)
        if isGIF && !nitro { model.showToast("GIF pictures are a MimiPlus perk — using the first frame", icon: "sparkles") }
        let still = isGIF ? AnimatedImages.decode(data, maxPixel: 1400, maxFrames: 1)?.images?.first ?? UIImage(data: data) : UIImage(data: data)
        guard let still else { return }
        cropping = CropJob(image: still, gif: isGIF && nitro ? data : nil, avatar: forAvatar)
    }

    private func applyCrop(_ job: CropJob, _ rect: CGRect) async {
        let side: CGFloat = job.avatar ? 600 : 1500
        if let gif = job.gif {
            let gifSide: CGFloat = job.avatar ? 512 : 1200
            if let data = await Task.detached(priority: .userInitiated, operation: { Cropping.cropGIF(gif, rect, maxSide: gifSide) }).value,
               let preview = AnimatedImages.decode(data, maxPixel: gifSide) {
                withMotion(Motion.standard) { if job.avatar { avatar = .gif(data, preview) } else { banner = .gif(data, preview); removeBanner = false } }
                return
            }
        }
        let image = job.image
        let cropped = await Task.detached(priority: .userInitiated) { Cropping.crop(image, rect, maxSide: side) }.value
        withMotion(Motion.standard) { if job.avatar { avatar = .image(cropped) } else { banner = .image(cropped); removeBanner = false } }
    }

    // MARK: Nitro + style

    private var nitroCard: some View {
        Button { shop = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(nitro ? "MimiPlus is on" : "Get MimiPlus").font(.jakarta(15, .heavy)).foregroundStyle(.white)
                    Text(nitro ? "GIF pictures, premium styles and effects unlocked" : "GIF profile picture, GIF banner, effects and more").font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(NitroStyle.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name style").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NameStyles.all) { style in
                        let locked = style.premium && !nitro
                        Button {
                            if locked { shop = true } else { withMotion(Motion.standard) { nameStyle = style.id } }
                        } label: {
                            VStack(spacing: 6) {
                                NameText(name: name.isEmpty ? "Name" : name, style: style.id, size: 18, display: true, nitro: true)
                                    .lineLimit(1)
                                    .frame(maxWidth: 130)
                                    .padding(.vertical, 12).padding(.horizontal, 14)
                                    .background(style.id == "neon" ? Color(hex: 0x2A1830) : Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                HStack(spacing: 4) {
                                    if style.premium { Image(systemName: locked ? "lock.fill" : "sparkles").font(.system(size: 9, weight: .bold)) }
                                    Text(style.label).font(.jakarta(11, .bold))
                                }
                                .foregroundStyle(style.premium ? Color(hex: 0xA67CF7) : Palette.muted)
                            }
                            .padding(6)
                            .background(nameStyle == style.id ? Theme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(nameStyle == style.id ? Theme.main.opacity(0.5) : Palette.border, lineWidth: 1.2))
                            .opacity(locked ? 0.6 : 1)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.95))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func colorSection(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { withMotion(Motion.standard) { selection.wrappedValue = "" } } label: {
                        Image(systemName: "circle.slash").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.muted)
                            .frame(width: 38, height: 38).background(Palette.surface2, in: Circle())
                            .overlay(Circle().strokeBorder(selection.wrappedValue.isEmpty ? Theme.main : Palette.border, lineWidth: 2))
                    }
                    ForEach(ProfileColors.swatches.indices, id: \.self) { i in
                        let swatch = ProfileColors.swatches[i]
                        let on = selection.wrappedValue.lowercased() == swatch.0
                        Button { withMotion(Motion.standard) { selection.wrappedValue = swatch.0 } } label: {
                            Circle().fill(Color(hex: swatch.1)).frame(width: 38, height: 38)
                                .overlay { if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white) } }
                                .overlay(Circle().strokeBorder(.white, lineWidth: on ? 3 : 0))
                                .shadow(color: Color(hex: swatch.1).opacity(on ? 0.5 : 0.2), radius: on ? 6 : 3, y: 2)
                                .scaleEffect(on ? 1.08 : 1)
                        }
                        .buttonStyle(BouncyStyle())
                    }
                }
                .padding(4)
            }
        }
    }

    private var effectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Profile effect").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                if !nitro { NitroBadge(compact: true) }
            }
            FlowLayout(spacing: 8) {
                ForEach(ProfileEffect.all) { item in
                    Chip(title: item.label, icon: item.icon, active: effect == item.id) {
                        if nitro || item.id.isEmpty { withMotion(Motion.standard) { effect = item.id } } else { shop = true }
                    }
                }
            }
            if !effect.isEmpty {
                colorSection("Effect colour", selection: $effectColor)
                Text("How many").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                HStack(spacing: 8) {
                    ForEach(ProfileEffect.amounts, id: \.0) { amount, label in
                        Chip(title: label, active: effectAmount == amount) { withMotion(Motion.standard) { effectAmount = amount } }
                    }
                }
            }
        }
    }

    // What your profile top will look like, as you change things.
    private var lookPreview: some View {
        let bannerTint = ProfileColors.color(bannerColor)
        let accentTint = ProfileColors.color(profileColor)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    LinearGradient(colors: [bannerTint ?? Theme.light, accentTint ?? Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if !pattern.isEmpty { BannerPatternView(pattern: pattern) }
                    if !effect.isEmpty && nitro { ProfileEffectLayer(effect: effect, color: effectColor, amount: effectAmount) }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                HStack(alignment: .bottom, spacing: 10) {
                    Avatar(url: model.me?.picture ?? "", name: name, size: 58, ring: frame.isEmpty && !nitro, nitro: frame.isEmpty && nitro)
                        .padding(3)
                        .background(Palette.bg, in: Circle())
                        .overlay { if !frame.isEmpty { AvatarFrameView(frame: frame, color: accentTint ?? Theme.main, size: 58) } }
                    NameText(name: name.isEmpty ? "Your name" : name, style: nameStyle, size: 20, display: true, nitro: nitro, tint: nameColor)
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Palette.surface, in: Capsule())
                }
                .offset(x: 12, y: 30)
            }
            .padding(.bottom, 30)
        }
    }

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Banner pattern").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            BannerPatternPicker(selection: $pattern,
                                tint: ProfileColors.color(profileColor) ?? Theme.main,
                                light: ProfileColors.color(bannerColor) ?? Theme.light)
        }
    }

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Picture frame").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            AvatarFramePicker(selection: $frame, picture: model.me?.picture ?? "", name: name,
                              tint: ProfileColors.color(profileColor) ?? Theme.main, nitro: nitro) { shop = true }
        }
    }

    // MARK: Load + save

    private func fill() {
        guard let me = model.me else { return }
        name = me.displayName
        pronouns = me.pronouns
        status = me.status
        bio = me.bio
        website = me.website
        interests = me.interests.joined(separator: ", ")
        nameStyle = me.nameStyle.isEmpty ? "default" : me.nameStyle
        bannerColor = me.bannerColor
        profileColor = me.profileColor
        effect = me.profileEffect
        effectColor = me.effectColor
        effectAmount = me.effectAmount > 0 ? me.effectAmount : 16
        nameColor = me.nameColor
        frame = me.avatarFrame
        pattern = me.bannerPattern
    }

    private func upload(_ picture: PendingPicture, maxSide: CGFloat) async throws -> String {
        switch picture {
        case .link(let url): return url
        case .gif(let data, _): return try await StorageClient.upload(data, contentType: "image/gif", fileExtension: "gif")
        case .image(let img):
            guard let data = ImageTools.jpeg(img, maxSide: maxSide) else { throw APIError(message: "Couldn't read that picture.") }
            return try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
        }
    }

    private func save() async {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Pick a display name."; return }
        guard !Moderation.hasLink(bio), !Moderation.hasLink(status) else { error = "Links aren't allowed in your bio or status — use the Website box."; return }
        guard await TextGuard.clear([trimmed, pronouns], kind: .name, model: model, cooldown: false),
              await TextGuard.clear([bio, status, interests], kind: .profile, model: model) else { return }
        saving = true
        defer { saving = false }
        let tags = interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        do {
            var fields: Doc = [
                "display_name": trimmed, "full_name": trimmed,
                "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
                "pronouns": String(pronouns.trimmingCharacters(in: .whitespaces).prefix(24)),
                "custom_status": String(status.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                "website": website.trimmingCharacters(in: .whitespacesAndNewlines),
                "interests": Array(tags.prefix(12)),
                "name_style": nameStyle, "banner_color": bannerColor, "profile_color": profileColor, "profile_effect": effect,
                "effect_color": effectColor, "effect_amount": effectAmount, "name_color": nameColor,
                "avatar_frame": frame, "banner_pattern": pattern,
            ]
            if let avatar { fields["profile_picture"] = try await upload(avatar, maxSide: 800) }
            if let banner { fields["banner_url"] = try await upload(banner, maxSide: 1800) } else if removeBanner { fields["banner_url"] = "" }
            try await model.updateMe(fields)
            dismiss()
            model.showToast("Profile updated", icon: "sparkles")
        } catch {
            self.error = PostProblem.message(error)
        }
    }
}

// MARK: - Settings

// Your own colours: a main colour plus a sub tone (the other end of the
// gradient). Buttons, backgrounds, the logo and Mimi all follow.
struct MyColorsPicker: View {
    @Environment(AppModel.self) private var model
    @State private var main = Color(hex: 0xD9577F)
    @State private var sub = Color(hex: 0xEE8FAE)
    @State private var saving = false

    private var mine: (main: UInt32, light: UInt32)? { model.myColors }
    private var inUse: Bool {
        guard let mine else { return false }
        return mine.main == main.rgbHex && mine.light == sub.rgbHex
    }

    // Sub tones that go with the main colour: lighter, the neighbours on
    // the colour wheel, a soft opposite and a deeper shade.
    private var ideas: [Color] {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(main).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        func tone(_ dh: CGFloat, _ ds: CGFloat, _ db: CGFloat) -> Color {
            var hue = (h + dh).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            return Color(hue: Double(hue), saturation: Double(max(0, min(1, s * ds))), brightness: Double(max(0, min(1, b + db))))
        }
        return [tone(0, 0.5, 0.15), tone(0.07, 0.8, 0.1), tone(-0.07, 0.8, 0.1), tone(0.5, 0.45, 0.12), tone(0, 1, -0.22)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your own colours").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2).padding(.top, 6)
            HStack(spacing: 14) {
                Circle().fill(LinearGradient(colors: [sub, main], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(.white, lineWidth: inUse ? 3 : 0))
                    .overlay { if inUse { Image(systemName: "checkmark").font(.system(size: 17, weight: .black)).foregroundStyle(.white) } }
                    .overlay(Circle().strokeBorder(main.opacity(inUse ? 0.9 : 0), lineWidth: 2).padding(-4))
                VStack(spacing: 4) {
                    ColorPicker(selection: $main, supportsOpacity: false) { Text("Main").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text) }
                    ColorPicker(selection: $sub, supportsOpacity: false) { Text("Sub tone").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text) }
                }
            }
            .padding(12)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 8) {
                Text("Sub tones").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                ForEach(0..<ideas.count, id: \.self) { i in
                    let tone = ideas[i]
                    Button { withMotion(Motion.standard) { sub = tone } } label: {
                        Circle().fill(tone).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1).padding(-1))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.85))
                    .accessibilityLabel("Sub tone \(i + 1)")
                }
            }

            HStack(spacing: 10) {
                Button { Task { await save() } } label: {
                    Label(inUse ? "In use" : "Use my colours", systemImage: inUse ? "checkmark.circle.fill" : "paintbrush.pointed.fill")
                }
                .buttonStyle(GradientButtonStyle(height: 42))
                .disabled(saving || inUse)
                if mine != nil {
                    Button { Task { await reset() } } label: {
                        Text("Reset").font(.jakarta(14, .bold)).foregroundStyle(Palette.text2)
                            .padding(.horizontal, 18).frame(height: 42)
                            .background(Palette.surface2, in: Capsule())
                    }
                    .buttonStyle(BouncyStyle())
                    .disabled(saving)
                }
            }
        }
        .onAppear {
            if let mine { main = Color(hex: mine.main); sub = Color(hex: mine.light) } else { main = Theme.main; sub = Theme.light }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        try? await model.updateMe(["accent_main": SiteTheme.string(main.rgbHex), "accent_sub": SiteTheme.string(sub.rgbHex)])
    }

    private func reset() async {
        saving = true
        defer { saving = false }
        try? await model.updateMe(["accent_main": "", "accent_sub": ""])
    }
}


// Settings: your profile card, then iPhone-style groups of rows (a coloured
// icon, a title, and a switch or an arrow). Inside your account it's a page
// you go back from; opened from your profile it has a Done button.
struct SettingsView: View {
    var closable = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var legal: LegalDoc?
    @State private var contacting = false
    @State private var confirmDelete = false
    @State private var deletePassword = ""
    @State private var backupCodes = false
    @State private var approvingLogin = false
    @State private var confirmLogout = false
    @State private var deleting = false
    @State private var error: String?
    @AppStorage("sugerly.haptics") private var haptics = true
    @AppStorage(TapSound.settingKey) private var clickSounds = true
    @AppStorage(Alerts.Kind.dms.key) private var alertDMs = true
    @AppStorage(Alerts.Kind.servers.key) private var alertServers = true
    @AppStorage(Alerts.Kind.social.key) private var alertSocial = true
    @AppStorage(Alerts.Kind.reels.key) private var alertReels = true
    @State private var statusSheet = false
    @State private var peopleList: PeopleListSheet.Kind?
    @State private var editing = false
    @State private var ownColours = false
    private var alerts: Alerts { Alerts.shared }

    var body: some View {
        List {
            if let me = model.me {
                Section {
                    profileCard(me)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                InviteCard()
                    .buttonStyle(.borderless)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            lookGroup
            alertsGroup
            privacyGroup
            soundsGroup
            helpGroup
            securityGroup
            accountGroup
            Section {
                VStack(spacing: 6) {
                    BrandLogo(height: 30)
                    Text("Sugerly for iPhone & iPad").font(.cute(16)).foregroundStyle(Theme.main)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .sugarList()
        .roundTitle("Settings")
        .toolbar {
            if closable {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.jakarta(16, .bold))
                }
            }
        }
        .tint(Theme.main)
        .sheet(isPresented: $statusSheet) { StatusSheet().presentationCornerRadius(30) }
        .sheet(item: $peopleList) { kind in PeopleListSheet(kind: kind).presentationCornerRadius(30) }
        .sheet(item: $legal) { doc in LegalView(doc: doc) }
        .sheet(isPresented: $contacting) { NavigationStack { SupportView() }.presentationCornerRadius(30) }
        .sheet(isPresented: $editing) { EditProfileView() }
        .sheet(isPresented: $backupCodes) { BackupCodesSheet() }
        .sheet(isPresented: $approvingLogin) { QuickApproveSheet() }
        .confirmationDialog("Log out of Sugerly?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { model.signOut() }
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            SecureField("Password", text: $deletePassword)
            Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) { deletePassword = "" }
        } message: { Text("Enter your password to confirm. Your profile, posts, reels, comments and messages will be deleted. This can't be undone.") }
        .disabled(deleting)
        .onAppear { ownColours = model.myColors != nil }
    }

    // MARK: top

    private func profileCard(_ me: UserProfile) -> some View {
        let level = LevelInfo(xp: me.xp)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Avatar(url: me.picture, name: me.displayName, size: 64)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                VStack(alignment: .leading, spacing: 3) {
                    Text(me.displayName).font(.display(24)).foregroundStyle(.white).lineLimit(1)
                    Text(me.email).font(.jakarta(13, .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                stat("\(level.level)", "Level", "star.fill")
                stat("\(me.coins)", "Coins", "circle.hexagongrid.fill")
                stat("\(me.dailyStreak)", "Day streak", "flame.fill")
            }
            Button { editing = true } label: {
                Label("Edit profile", systemImage: "pencil")
                    .font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(BouncyStyle(scale: 0.96))
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.gradient)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.12)).frame(width: 170).offset(x: 60, y: -70)
                }
                .overlay(alignment: .bottomLeading) {
                    Circle().fill(.white.opacity(0.08)).frame(width: 120).offset(x: -40, y: 50)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(value).font(.jakarta(17, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(label).font(.jakarta(10, .bold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 54)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: groups

    private var themeChoice: Binding<String> {
        Binding(get: {
            let theme = model.me?.theme ?? ""
            return theme.isEmpty ? "light" : theme
        }, set: { value in
            Task { try? await model.updateMe(["theme": value]) }
        })
    }

    private var lookGroup: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                IconRow(title: "Theme", icon: "moon.stars.fill", colors: [0xB19CFF, 0x7C5CF0])
                Picker("Theme", selection: themeChoice) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Auto").tag("system")
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 12) {
                IconRow(title: "Colour", detail: "The logo and Mimi change colour to match.", icon: "drop.fill", colors: [0xF27BA3, 0xE8457C])
                HStack(spacing: 0) {
                    ForEach(Accent.allCases) { accent in
                        let picked = model.accent == accent && model.myColors == nil
                        Button {
                            ownColours = false
                            Task { try? await model.updateMe(["accent": accent.rawValue, "accent_main": "", "accent_sub": ""]) }
                        } label: {
                            swatch(accent.gradient, picked: picked, ring: accent.main)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.86))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(accent.label)
                    }
                    Button { withMotion(Motion.standard) { ownColours.toggle() } } label: {
                        swatch(AngularGradient(colors: [Color(hex: 0xFF7AA2), Color(hex: 0xFFD166), Color(hex: 0x5FD3B0), Color(hex: 0x7CBEFF), Color(hex: 0xB19CFF), Color(hex: 0xFF7AA2)], center: .center),
                               picked: model.myColors != nil, ring: Theme.main, icon: model.myColors == nil ? "plus" : nil)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.86))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Your own colours")
                }
                if ownColours {
                    MyColorsPicker()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 4)
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 12) {
                IconRow(title: "Background", detail: "Shown at the top of Home.", icon: "sparkles", colors: [0xFFD166, 0xF0A020])
                BackgroundPicker()
            }
            .padding(.vertical, 4)
            .buttonStyle(.borderless)
        } header: { ListHeader(title: "APPEARANCE") }
    }

    private var alertsGroup: some View {
        Section {
            if alerts.permission == .denied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    IconRow(title: "Notifications are off", detail: "Tap to turn them on in iPhone Settings", icon: "bell.slash.fill", colors: [0xF07A8E, 0xE0526B], chevron: true)
                }
            }
            toggle(Alerts.Kind.dms.title, icon: Alerts.Kind.dms.icon, colors: [0x7CBEFF, 0x2F80E0], isOn: $alertDMs)
            toggle(Alerts.Kind.servers.title, icon: Alerts.Kind.servers.icon, colors: [0xB19CFF, 0x7C5CF0], isOn: $alertServers)
            toggle(Alerts.Kind.social.title, icon: Alerts.Kind.social.icon, colors: [0xF27BA3, 0xE8457C], isOn: $alertSocial)
            toggle(Alerts.Kind.reels.title, icon: Alerts.Kind.reels.icon, colors: [0xFFAA80, 0xEE6E40], isOn: $alertReels)
        } header: { ListHeader(title: "NOTIFICATIONS") }
        .task { await alerts.requestPermission() }
    }

    private var privacyGroup: some View {
        Section {
            Button { statusSheet = true } label: {
                IconRow(title: "Status", detail: statusLine, icon: "bubble.left.fill", colors: [0x5FD3B0, 0x16A37F], chevron: true)
            }
            Toggle(isOn: Binding(
                get: { model.me?.presence != "invisible" },
                set: { on in Task { await Privacy.setPresence(on ? .online : .invisible, model: model) } })) {
                IconRow(title: "Show when I'm online", detail: "Off makes you look offline", icon: "circle.fill", colors: [0x4CC795, 0x17A673])
            }
            Button { peopleList = .blocked } label: {
                IconRow(title: "Blocked people", icon: "hand.raised.fill", colors: [0xF07A8E, 0xE0526B], value: "\(model.me?.blocked.count ?? 0)", chevron: true)
            }
            Button { peopleList = .ignored } label: {
                IconRow(title: "Ignored people", icon: "bell.slash.fill", colors: [0xB8A3AE, 0x86707C], value: "\(model.me?.ignored.count ?? 0)", chevron: true)
            }
        } header: {
            ListHeader(title: "PRIVACY & STATUS")
        } footer: {
            Text("Only friends (people who follow you back) can call you or send voice messages. Anyone else's first message arrives as a request.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
        }
    }

    private var soundsGroup: some View {
        Section {
            toggle("Haptics", detail: "Little taps when you like, send and switch tabs", icon: "iphone.radiowaves.left.and.right", colors: [0x7CBEFF, 0x2F80E0], isOn: $haptics)
            toggle("App sounds", detail: "Soft pops, likes, sends and little chimes (quiet on silent)", icon: "speaker.wave.2.fill", colors: [0xFFAA80, 0xEE6E40], isOn: $clickSounds)
        } header: { ListHeader(title: "SOUNDS & HAPTICS") }
    }

    private var helpGroup: some View {
        Section {
            ForEach(LegalDoc.allCases) { doc in
                Button { legal = doc } label: {
                    IconRow(title: doc.title,
                            icon: doc == .terms ? "doc.text.fill" : doc == .privacy ? "lock.fill" : "heart.text.square.fill",
                            colors: doc == .terms ? [0xB19CFF, 0x7C5CF0] : doc == .privacy ? [0x5FD3B0, 0x16A37F] : [0xF27BA3, 0xE8457C],
                            chevron: true)
                }
            }
            Button { contacting = true } label: {
                IconRow(title: "Help & support chat", detail: "Chat with the team, follow your reports", icon: "bubble.left.and.bubble.right.fill", colors: [0x7CB2FF, 0x3B82F6], chevron: true)
            }
        } header: { ListHeader(title: "HELP & LEGAL") }
    }

    // Other ways into your account (see Views/Auth/AccountAccess.swift).
    private var securityGroup: some View {
        Section {
            Button { approvingLogin = true } label: {
                IconRow(title: "Log in another device", detail: "Scan the QR code on a new iPhone or iPad", icon: "qrcode.viewfinder", colors: [0xB19CFF, 0x7C5CF0], chevron: true)
            }
            Button { backupCodes = true } label: {
                IconRow(title: "Backup codes", detail: "Log in even if you can't get your emails", icon: "key.horizontal.fill", colors: [0xFFC46B, 0xF0A020], chevron: true)
            }
        } header: {
            ListHeader(title: "LOGIN & SECURITY")
        }
    }

    private var accountGroup: some View {
        Section {
            Button { confirmLogout = true } label: {
                IconRow(title: "Log out", icon: "rectangle.portrait.and.arrow.right", colors: [0xB8A3AE, 0x86707C])
            }
            Button { confirmDelete = true } label: {
                IconRow(title: "Delete account", detail: "Removes your profile and everything you posted. This can't be undone.", icon: "trash.fill", colors: [0xF07A8E, 0xE0526B], danger: true)
            }
        } header: {
            ListHeader(title: "ACCOUNT")
        } footer: {
            if let error { Text(error).font(.jakarta(12)).foregroundStyle(Palette.danger) }
        }
    }

    // MARK: building blocks

    private func toggle(_ title: String, detail: String? = nil, icon: String, colors: [UInt32], isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            IconRow(title: title, detail: detail, icon: icon, colors: colors)
        }
        .tint(Theme.main)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
        .onChange(of: isOn.wrappedValue) { _, on in TapSound.play(on ? .toggle : .toggleOff) }
    }

    private func swatch<S: ShapeStyle>(_ fill: S, picked: Bool, ring: Color, icon: String? = nil) -> some View {
        Circle().fill(fill)
            .frame(width: 40, height: 40)
            .overlay(Circle().strokeBorder(.white, lineWidth: picked ? 3 : 0))
            .overlay {
                if picked {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                }
            }
            .overlay(Circle().strokeBorder(ring.opacity(picked ? 0.9 : 0), lineWidth: 2).padding(-4))
            .padding(4)
    }

    private var statusLine: String {
        guard let me = model.me else { return "" }
        let presence = Presence(rawValue: me.presence) ?? .online
        let text = me.activeStatus
        return text.isEmpty ? presence.label : "\(presence.label) · \(text)"
    }

    private func deleteAccount() async {
        let password = deletePassword
        deletePassword = ""
        guard !password.isEmpty else { error = "Enter your password to delete your account."; return }
        deleting = true
        defer { deleting = false }
        do {
            try await model.deleteAccount(password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
