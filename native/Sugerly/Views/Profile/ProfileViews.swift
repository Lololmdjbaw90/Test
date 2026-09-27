import SwiftUI
import UIKit
import PhotosUI

// Your own profile (the Profile tab).
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var store = PostsStore()
    @State private var editing = false
    @State private var settings = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let me = model.me {
                    ProfileContent(person: me, isMe: true, store: store, path: $path, onEdit: { editing = true })
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(model.me?.displayName ?? "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { NativeWordmark() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in RouteView(route: route, store: store, path: $path) }
            .sheet(isPresented: $editing) { EditProfileView() }
            .sheet(isPresented: $settings) { SettingsView() }
        }
    }
}

// Someone else's profile.
struct PersonView: View {
    let email: String
    var store: PostsStore
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var loaded: UserProfile?
    @State private var reporting: ReportSheet.Target?
    @State private var confirmBlock = false

    private var person: UserProfile? { model.person(email) ?? loaded }
    private var isMe: Bool { model.me?.email == email.lowercased() }

    var body: some View {
        Group {
            if let person {
                ProfileContent(person: person, isMe: isMe, store: store, path: $path, onEdit: nil)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(person?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isMe, let person {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { reporting = ReportSheet.Target(id: person.email, type: "user", ownerEmail: person.email, preview: person.displayName, link: "/Profile?email=\(person.email)") } label: { Label("Report", systemImage: "flag") }
                        Button(role: .destructive) { confirmBlock = true } label: {
                            Label(isBlocked ? "Unblock" : "Block", systemImage: "hand.raised")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
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
            if model.person(email) == nil, let docs = try? await FS.query("User", [.equals("email", email.lowercased())], limit: 1), let doc = docs.first {
                loaded = UserProfile(doc)
            }
        }
    }

    private var isBlocked: Bool { model.me?.blocked.contains(email.lowercased()) ?? false }

    private func toggleBlock() {
        guard let me = model.me else { return }
        var next = me.blocked
        if next.contains(email.lowercased()) { next.removeAll { $0 == email.lowercased() } } else { next.append(email.lowercased()) }
        var following = me.following
        if !isBlocked { following.removeAll { $0 == email.lowercased() } }
        Task { try? await model.updateMe(["blocked": next, "following": following]) }
    }
}

struct ProfileContent: View {
    let person: UserProfile
    let isMe: Bool
    var store: PostsStore
    @Binding var path: [Route]
    var onEdit: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var posts: [Post] = []
    @State private var loading = true

    private var following: Bool { model.me?.following.contains(person.email) ?? false }
    private var followers: Int { model.people.values.filter { $0.following.contains(person.email) }.count }
    private let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if person.banner.isEmpty {
                            Theme.gradient
                        } else {
                            RemoteImage(url: person.banner)
                        }
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Avatar(url: person.picture, name: person.displayName, size: 96, online: person.isOnline && !isMe)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
                        .offset(x: 20, y: 48)
                }
                .padding(.bottom, 56)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(person.displayName).font(.custom("CuteHereRegular", size: 29))
                        if person.isAdmin {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.pink).accessibilityLabel("Admin")
                        }
                        Spacer()
                        Text("Lv. \(person.level)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.pink.opacity(0.14), in: Capsule())
                            .foregroundStyle(Theme.pink)
                    }
                    if !person.bio.isEmpty { Text(person.bio).font(.body) }

                    HStack(spacing: 24) {
                        stat(posts.count, "Posts")
                        stat(followers, "Followers")
                        stat(person.following.count, "Following")
                    }
                    .padding(.vertical, 6)

                    HStack(spacing: 10) {
                        if isMe {
                            Button { onEdit?() } label: { Text("Edit profile").frame(maxWidth: .infinity) }
                                .buttonStyle(PrimaryButtonStyle())
                        } else {
                            Button { toggleFollow() } label: {
                                Text(following ? "Following" : "Follow").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .tint(following ? Color(.systemGray3) : Theme.pink)
                            .sensoryFeedback(.success, trigger: following)
                            Button { openChat() } label: { Text("Message").frame(maxWidth: .infinity) }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                if loading {
                    ProgressView().padding(40)
                } else if posts.isEmpty {
                    ContentUnavailableView(isMe ? "Share your first post" : "No posts yet", systemImage: "photo.on.rectangle.angled")
                        .padding(.top, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(posts) { post in
                            Button { path.append(.post(post)) } label: {
                                Rectangle()
                                    .fill(Theme.card)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        if post.imageURL.isEmpty {
                                            Text(post.title.isEmpty ? post.text : post.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(5)
                                                .padding(8)
                                        } else {
                                            RemoteImage(url: post.imageURL)
                                        }
                                    }
                                    .clipped()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .refreshable { await load() }
        .task(id: person.email) { await load() }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("CommunityPost", [.equals("user_email", person.email)], orderBy: "created_date", limit: 60) else { return }
        posts = docs.map(Post.init)
        for post in posts where !store.posts.contains(where: { $0.id == post.id }) { store.posts.append(post) }
    }

    private func toggleFollow() {
        guard let me = model.me else { return }
        var next = me.following
        if next.contains(person.email) { next.removeAll { $0 == person.email } } else { next.append(person.email) }
        Task { try? await model.updateMe(["following": next]) }
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
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                if let avatar {
                                    Image(uiImage: avatar).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                                } else {
                                    Avatar(url: model.me?.picture ?? "", name: name, size: 96)
                                }
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 28))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Theme.pink)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Display name") {
                    TextField("Your name", text: $name).textContentType(.nickname)
                }
                Section {
                    TextField("A few words about you and your art", text: $bio, axis: .vertical).lineLimit(3...6)
                } header: { Text("Bio") } footer: { Text("Links aren't allowed in bios.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save").bold() } }.disabled(saving)
                }
            }
            .onAppear {
                name = model.me?.displayName ?? ""
                bio = model.me?.bio ?? ""
            }
            .onChange(of: avatarItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        withAnimation { avatar = image }
                    }
                }
            }
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
            try await model.updateMe(fields)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
