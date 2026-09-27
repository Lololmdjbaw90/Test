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
    @State private var loading = true
    @State private var tab: Tab = .posts
    @State private var editing = false
    @State private var settings = false

    private var following: Bool { model.me?.following.contains(person.email) ?? false }
    private var followers: Int { model.people.values.filter { $0.following.contains(person.email) }.count }
    private var totalLikes: Int { posts.reduce(0) { $0 + $1.likes.count } }
    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner
                VStack(alignment: .leading, spacing: 14) {
                    identity
                    if !person.bio.isEmpty { Text(person.bio).font(.jakarta(15)).foregroundStyle(Palette.text) }
                    buttons
                    stats
                    if isMe { XPBar(info: LevelInfo(xp: person.xp)).sugarCard(radius: 22, padding: 14) }
                    tabs
                    grid
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .refreshable { await load() }
        .task(id: person.email) { await load() }
        .sheet(isPresented: $editing) { EditProfileView() }
        .sheet(isPresented: $settings) { SettingsView() }
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if person.banner.isEmpty {
                    ZStack {
                        Theme.gradient
                        Circle().fill(.white.opacity(0.25)).frame(width: 180).blur(radius: 40).offset(x: 120, y: -40)
                        Circle().fill(Theme.lavender.opacity(0.5)).frame(width: 160).blur(radius: 50).offset(x: -120, y: 40)
                    }
                } else {
                    RemoteImage(url: person.banner)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 12)

            Avatar(url: person.picture, name: person.displayName, size: 104, online: person.isOnline && !isMe, ring: true)
                .padding(4)
                .background(Palette.bg, in: Circle())
                .shadow(color: Theme.pink.opacity(0.3), radius: 16, y: 8)
                .offset(x: 26, y: 58)
        }
        .padding(.top, 8)
        .padding(.bottom, 54)
    }

    private var identity: some View {
        let info = LevelInfo(xp: person.xp)
        return VStack(alignment: .leading, spacing: 8) {
            Text(person.displayName).font(.display(34)).foregroundStyle(Palette.text)
            FlowLayout(spacing: 8) {
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
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if isMe {
                Button { editing = true } label: { Label("Edit profile", systemImage: "pencil") }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
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
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(reels) { reel in
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
                    }
                }
            case .saved:
                let saved = store.posts.filter { person.savedPosts.contains($0.id) }
                if saved.isEmpty { EmptyCard(icon: "bookmark.fill", title: "Nothing saved", text: "Tap the bookmark on any post to keep it here.") }
                postGrid(saved)
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
            }
        }
    }

    private func load() async {
        defer { loading = false }
        async let postDocs = try? FS.query("CommunityPost", [.equals("user_email", person.email)], orderBy: "created_date", limit: 90)
        async let reelDocs = try? FS.query("Reel", [.equals("user_email", person.email)], orderBy: "created_date", limit: 60)
        posts = (await postDocs ?? []).map(Post.init)
        reels = (await reelDocs ?? []).map(Reel.init)
        for post in posts where !store.posts.contains(where: { $0.id == post.id }) { store.posts.append(post) }
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

struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatar: UIImage?
    @State private var bannerItem: PhotosPickerItem?
    @State private var banner: UIImage?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "Edit profile", actionTitle: "Save", busy: saving, canPost: true, onClose: { dismiss() }, onPost: { Task { await save() } }) {
            PhotosPicker(selection: $bannerItem, matching: .images) {
                ZStack {
                    if let banner { Image(uiImage: banner).resizable().scaledToFill() }
                    else if let url = model.me?.banner, !url.isEmpty { RemoteImage(url: url) }
                    else { Theme.gradient }
                    Label("Change banner", systemImage: "photo").font(.jakarta(13, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.35), in: Capsule())
                }
                .frame(height: 130).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(BouncyStyle(scale: 0.98))

            HStack {
                Spacer()
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let avatar {
                            Image(uiImage: avatar).resizable().scaledToFill().frame(width: 104, height: 104).clipShape(Circle())
                        } else {
                            Avatar(url: model.me?.picture ?? "", name: name, size: 104)
                        }
                        Image(systemName: "camera.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.gradient, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 3))
                    }
                }
                .buttonStyle(BouncyStyle())
                Spacer()
            }
            .padding(.top, -50)

            Text("Display name").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            SugarField(placeholder: "Your name", text: $name)
            Text("Bio").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
            SugarField(placeholder: "A few words about you and your art", text: $bio, lines: 3...6)
            Text("Links aren't allowed in bios.").font(.jakarta(12)).foregroundStyle(Palette.muted)
            if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
        }
        .onAppear {
            name = model.me?.displayName ?? ""
            bio = model.me?.bio ?? ""
        }
        .onChange(of: avatarItem) { _, item in
            Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { withAnimation { avatar = image } } }
        }
        .onChange(of: bannerItem) { _, item in
            Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { withAnimation { banner = image } } }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Pick a display name."; return }
        guard !Moderation.hasLink(bio) else { error = "Links aren't allowed in bios."; return }
        saving = true
        defer { saving = false }
        do {
            var fields: Doc = ["display_name": trimmed, "full_name": trimmed, "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines)]
            if let avatar, let data = ImageTools.jpeg(avatar, maxSide: 800) {
                fields["profile_picture"] = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
            if let banner, let data = ImageTools.jpeg(banner, maxSide: 1800) {
                fields["banner_url"] = try await StorageClient.upload(data, contentType: "image/jpeg", fileExtension: "jpg")
            }
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
                }

                section("Sounds & haptics", icon: "hand.tap.fill") {
                    toggleRow("Haptics", "Little taps when you like, send and switch tabs", isOn: $haptics)
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
