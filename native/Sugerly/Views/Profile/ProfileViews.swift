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
                ProfileContent(person: person, isMe: isMe, path: $path)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).sugarBackground()
            }
        }
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
    enum Tab: String, CaseIterable { case posts = "Posts", reels = "Reels", saved = "Saved" }

    let person: UserProfile
    let isMe: Bool
    @Binding var path: [Route]

    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var store
    @State private var posts: [Post] = []
    @State private var reels: [Reel] = []
    @State private var savedPosts: [Post] = []
    @State private var savedReels: [Reel] = []
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
    private var totalLikes: Int { posts.reduce(0) { $0 + $1.likes.count } }
    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

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
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            if let accent {
                LinearGradient(colors: [accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 420).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .sugarBackground()
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .refreshable { await load() }
        .task(id: person.email) { await load() }
        .sheet(isPresented: $editing) { EditProfileView() }
        .sheet(isPresented: $settings) { SettingsView() }
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
                    RemoteImage(url: person.banner)
                }
                if person.isNitro && !person.profileEffect.isEmpty { ProfileEffectLayer(effect: person.profileEffect) }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 12)

            Avatar(url: person.picture, name: person.displayName, size: 104, ring: true, nitro: person.isNitro,
                   presence: isMe ? (Presence(rawValue: person.presence) ?? .online) : person.presenceNow)
                .padding(4)
                .background(Palette.bg, in: Circle())
                .shadow(color: (accent ?? Theme.pink).opacity(0.3), radius: 16, y: 8)
                .offset(x: 26, y: 58)
        }
        .padding(.top, 8)
        .padding(.bottom, 54)
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
                NameText(name: person.displayName, style: person.nameStyle, size: 34, display: true, nitro: person.isNitro)
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
                    .accessibilityLabel("MimiNitro")
                Button { settings = true } label: { Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .bold)) }
                    .buttonStyle(OutlineButtonStyle())
            } else {
                Button { toggleFollow() } label: {
                    Label(following ? "Following" : "Follow", systemImage: following ? "checkmark" : "person.badge.plus")
                }
                .buttonStyle(GradientButtonStyle(height: 44))
                .opacity(following ? 0.75 : 1)
                .sensoryFeedback(.success, trigger: following)
                Button { openChat() } label: { Label("Message", systemImage: "paperplane.fill") }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
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
            (t.rawValue, t == .posts ? "square.grid.2x2.fill" : t == .reels ? "play.rectangle.fill" : "bookmark.fill")
        }
        return SectionSwitch(options: options, selection: Binding(get: { list.firstIndex(of: tab) ?? 0 }, set: { i in withAnimation(.snappy) { tab = list[i] } }))
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
            case .reels:
                if reels.isEmpty { EmptyCard(icon: "play.rectangle.fill", title: "No reels yet", text: isMe ? "Tap + → Create a reel." : "Nothing to see here yet.") }
                reelGrid(reels)
            case .saved:
                if savedPosts.isEmpty && savedReels.isEmpty { EmptyCard(icon: "bookmark.fill", title: "Nothing saved", text: "Tap the bookmark on any post or reel to keep it here.") }
                if !savedReels.isEmpty {
                    Label("Reels", systemImage: "play.rectangle.fill").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2)
                    reelGrid(savedReels)
                }
                if !savedPosts.isEmpty {
                    Label("Posts", systemImage: "square.grid.2x2.fill").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text2).padding(.top, 6)
                    postGrid(savedPosts)
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
        posts = (await postDocs ?? []).map(Post.init)
        reels = (await reelDocs ?? []).map(Reel.init)
        if let n = await followerCount { followers = n }
        for post in posts where !store.posts.contains(where: { $0.id == post.id }) { store.posts.append(post) }
        if isMe { await loadSaved() }
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

    // Your saved posts and reels (fetched by id, newest saves first).
    private func loadSaved() async {
        var foundPosts: [Post] = []
        for id in person.savedPosts.reversed().prefix(30) {
            if let hit = store.posts.first(where: { $0.id == id }) { foundPosts.append(hit) }
            else if let doc = try? await FS.get("CommunityPost", id) { foundPosts.append(Post(doc)) }
        }
        var foundReels: [Reel] = []
        for id in person.savedReels.reversed().prefix(30) {
            if let doc = try? await FS.get("Reel", id) { foundReels.append(Reel(doc)) }
        }
        savedPosts = foundPosts
        savedReels = foundReels
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
        ComposerScaffold(title: "Edit profile", actionTitle: "Save", busy: saving, canPost: true, onClose: { dismiss() }, onPost: { Task { await save() } }) {
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

            styleSection
            colorSection("Banner colour", selection: $bannerColor)
            colorSection("Profile colour", selection: $profileColor)
            effectSection

            if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
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
                withAnimation(.snappy) {
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
                Button { nitroOnly { gifFor = false } } label: { Label(nitro ? "Choose a GIF" : "Choose a GIF (Nitro)", systemImage: "photo.stack") }
                if hasBanner { Button(role: .destructive) { withAnimation { banner = nil; removeBanner = true } } label: { Label("Remove banner", systemImage: "trash") } }
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
                Button { nitroOnly { gifFor = true } } label: { Label(nitro ? "Choose a GIF" : "Choose a GIF (Nitro)", systemImage: "photo.stack") }
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
        case .gif(_, let img)?: LoadedImage(image: img)
        case .link(let url)?: RemoteImage(url: url)
        case nil:
            if !removeBanner, let url = model.me?.banner, !url.isEmpty { RemoteImage(url: url) } else { bannerGradient }
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
            case .gif(_, let img)?: LoadedImage(image: img).frame(width: 104, height: 104).clipShape(Circle())
            case .link(let url)?: Avatar(url: url, name: name, size: 104)
            case nil: Avatar(url: model.me?.picture ?? "", name: name, size: 104)
            }
        }
        .padding(nitro ? 5 : 4)
        .background { if nitro { NitroRing() } else { Circle().fill(Palette.bg) } }
    }

    private func nitroOnly(_ action: () -> Void) {
        if nitro { action() } else { shop = true }
    }

    private func picked(_ item: PhotosPickerItem, avatar forAvatar: Bool) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let isGIF = data.prefix(4) == Data("GIF8".utf8)
        if isGIF && !nitro { model.showToast("GIF pictures are a Nitro perk — using the first frame", icon: "sparkles") }
        let still = isGIF ? AnimatedImages.decode(data, maxPixel: 1400, maxFrames: 1)?.images?.first ?? UIImage(data: data) : UIImage(data: data)
        guard let still else { return }
        cropping = CropJob(image: still, gif: isGIF && nitro ? data : nil, avatar: forAvatar)
    }

    private func applyCrop(_ job: CropJob, _ rect: CGRect) async {
        let side: CGFloat = job.avatar ? 600 : 1500
        if let gif = job.gif {
            let gifSide: CGFloat = job.avatar ? 320 : 720
            if let data = await Task.detached(priority: .userInitiated, operation: { Cropping.cropGIF(gif, rect, maxSide: gifSide) }).value,
               let preview = AnimatedImages.decode(data, maxPixel: gifSide) {
                withAnimation(.snappy) { if job.avatar { avatar = .gif(data, preview) } else { banner = .gif(data, preview); removeBanner = false } }
                return
            }
        }
        let image = job.image
        let cropped = await Task.detached(priority: .userInitiated) { Cropping.crop(image, rect, maxSide: side) }.value
        withAnimation(.snappy) { if job.avatar { avatar = .image(cropped) } else { banner = .image(cropped); removeBanner = false } }
    }

    // MARK: Nitro + style

    private var nitroCard: some View {
        Button { shop = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(nitro ? "MimiNitro is on" : "Get MimiNitro").font(.jakarta(15, .heavy)).foregroundStyle(.white)
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
                            if locked { shop = true } else { withAnimation(.snappy) { nameStyle = style.id } }
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
                    Button { withAnimation(.snappy) { selection.wrappedValue = "" } } label: {
                        Image(systemName: "circle.slash").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.muted)
                            .frame(width: 38, height: 38).background(Palette.surface2, in: Circle())
                            .overlay(Circle().strokeBorder(selection.wrappedValue.isEmpty ? Theme.main : Palette.border, lineWidth: 2))
                    }
                    ForEach(ProfileColors.swatches.indices, id: \.self) { i in
                        let swatch = ProfileColors.swatches[i]
                        let on = selection.wrappedValue.lowercased() == swatch.0
                        Button { withAnimation(.snappy) { selection.wrappedValue = swatch.0 } } label: {
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
                        if nitro || item.id.isEmpty { withAnimation(.snappy) { effect = item.id } } else { shop = true }
                    }
                }
            }
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Pick a display name."; return }
        guard !Moderation.hasLink(bio), !Moderation.hasLink(status) else { error = "Links aren't allowed in your bio or status — use the Website box."; return }
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
            ]
            if let avatar { fields["profile_picture"] = try await upload(avatar, maxSide: 800) }
            if let banner { fields["banner_url"] = try await upload(banner, maxSide: 1800) } else if removeBanner { fields["banner_url"] = "" }
            try await model.updateMe(fields)
            dismiss()
            model.showToast("Profile updated", icon: "sparkles")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var legal: LegalDoc?
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?
    @AppStorage("sugerly.haptics") private var haptics = true
    @AppStorage(TapSound.settingKey) private var clickSounds = true
    @State private var statusSheet = false
    @State private var peopleList: PeopleListSheet.Kind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Settings").font(.display(34)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text2)
                            .frame(width: 38, height: 38).background(Palette.surface, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle())
                }
                .padding(.top, 20)

                if let me = model.me {
                    HStack(spacing: 14) {
                        Avatar(url: me.picture, name: me.displayName, size: 58).overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 2.5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(me.displayName).font(.display(22)).foregroundStyle(Palette.text)
                            Text(me.email).font(.jakarta(13)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\(me.coins)").font(.display(22)).foregroundStyle(Theme.gradient)
                            Text("COINS").font(.jakarta(9, .bold)).foregroundStyle(Palette.muted)
                        }
                    }
                    .sugarCard(radius: 26, padding: 16)
                }

                section("Appearance", icon: "paintpalette.fill") {
                    Text("Theme").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                    HStack(spacing: 8) {
                        themeOption("light", "Light", "sun.max.fill")
                        themeOption("dark", "Dark", "moon.fill")
                        themeOption("system", "Auto", "circle.lefthalf.filled")
                    }
                    Text("Accent colour").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2).padding(.top, 6)
                    HStack(spacing: 12) {
                        ForEach(Accent.allCases) { accent in
                            Button { Task { try? await model.updateMe(["accent": accent.rawValue]) } } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(accent.gradient)
                                        .frame(width: 46, height: 46)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: model.accent == accent ? 3 : 0))
                                        .overlay { if model.accent == accent { Image(systemName: "checkmark").font(.system(size: 16, weight: .black)).foregroundStyle(.white) } }
                                        .shadow(color: accent.main.opacity(model.accent == accent ? 0.6 : 0.2), radius: model.accent == accent ? 10 : 4, y: 3)
                                    Text(accent.label).font(.jakarta(11, .semibold)).foregroundStyle(Palette.text2)
                                }
                            }
                            .buttonStyle(BouncyStyle(scale: 0.88))
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("The logo changes colour to match.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                    Text("Background").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2).padding(.top, 6)
                    BackgroundPicker()
                    Text("Shown behind Home. It follows your colour and dark mode.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }

                section("Notifications", icon: "bell.badge.fill") {
                    AlertSettings()
                    Text("Sugerly checks for new things while it's open and every so often in the background.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }

                section("Sounds & haptics", icon: "hand.tap.fill") {
                    toggleRow("Haptics", "Little taps when you like, send and switch tabs", isOn: $haptics)
                    toggleRow("Click sounds", "A soft pop when you tap buttons (quiet when your phone is on silent)", isOn: $clickSounds)
                }

                section("Privacy & status", icon: "lock.shield.fill") {
                    row(statusLine, icon: "bubble.left.fill") { statusSheet = true }
                    toggleRow("Show when I'm online", "Off makes you look offline (invisible), like Discord", isOn: Binding(
                        get: { model.me?.presence != "invisible" },
                        set: { on in Task { await Privacy.setPresence(on ? .online : .invisible, model: model) } }))
                    row("Blocked people (\(model.me?.blocked.count ?? 0))", icon: "hand.raised.fill") { peopleList = .blocked }
                    row("Ignored people (\(model.me?.ignored.count ?? 0))", icon: "bell.slash.fill") { peopleList = .ignored }
                    Text("Only friends (people who follow you back) can call you or send voice messages. Anyone else's first message arrives as a request.")
                        .font(.jakarta(12)).foregroundStyle(Palette.muted)
                }

                section("Help & legal", icon: "questionmark.circle.fill") {
                    ForEach(LegalDoc.allCases) { doc in
                        row(doc.title, icon: doc == .terms ? "doc.text.fill" : doc == .privacy ? "lock.fill" : "heart.text.square.fill") { legal = doc }
                    }
                }

                section("Account", icon: "person.crop.circle.fill") {
                    row("Log out", icon: "rectangle.portrait.and.arrow.right") { model.signOut() }
                    row("Delete account", icon: "trash.fill", danger: true) { confirmDelete = true }
                    Text("Deleting your account removes your profile. This can't be undone.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                    if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
                }

                Text("Sugerly for iPhone & iPad").font(.cute(18)).foregroundStyle(Theme.gradient).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .sugarBackground()
        .sheet(isPresented: $statusSheet) { StatusSheet().presentationCornerRadius(30) }
        .sheet(item: $peopleList) { kind in PeopleListSheet(kind: kind).presentationCornerRadius(30) }
        .sheet(item: $legal) { doc in LegalView(doc: doc) }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
        } message: { Text("Your profile will be deleted. This can't be undone.") }
        .disabled(deleting)
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.display(21)).foregroundStyle(Palette.text)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 26, padding: 16)
    }

    private func themeOption(_ value: String, _ title: String, _ icon: String) -> some View {
        let active = (model.me?.theme.isEmpty == false ? model.me?.theme : "light") == value
        return Button { Task { try? await model.updateMe(["theme": value]) } } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(title).font(.jakarta(12, .bold))
            }
            .foregroundStyle(active ? .white : Palette.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.gradient).shadow(color: Theme.pink.opacity(0.35), radius: 10, y: 5)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface2)
                }
            }
        }
        .buttonStyle(BouncyStyle())
    }

    private func row(_ title: String, icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(danger ? Palette.danger : Theme.pink).frame(width: 24)
                Text(title).font(.jakarta(15, .semibold)).foregroundStyle(danger ? Palette.danger : Palette.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private var statusLine: String {
        guard let me = model.me else { return "Status" }
        let presence = Presence(rawValue: me.presence) ?? .online
        let text = me.activeStatus
        return text.isEmpty ? "Status: \(presence.label)" : "\(presence.label) · \(text)"
    }

    private func toggleRow(_ title: String, _ sub: String, isOn: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { isOn.wrappedValue.toggle() } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                    Text(sub).font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Capsule().fill(isOn.wrappedValue ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border))
                    .frame(width: 52, height: 32)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 26, height: 26).padding(3).shadow(radius: 2, y: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            try await model.deleteAccount()
        } catch {
            self.error = error.localizedDescription + " (Log out and back in, then try again.)"
        }
    }
}
