import SwiftUI
import UIKit
import PhotosUI

// Server settings (the website's ServerSettingsModal): overview, roles with
// colours and permissions, channels, @everyone permissions, delete.
struct ServerSettingsView: View {
    let store: ServerStore
    var onDeleted: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var name = ""
    @State private var about = ""
    @State private var welcome = ""
    @State private var emoji = ""
    @State private var iconItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var iconImage: UIImage?
    @State private var bannerImage: UIImage?
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var editingRole: RoleDraft?
    @State private var editingChannel: ServerChannel?
    @State private var newChannelType: String?

    private var me: String { model.me?.email ?? "" }
    private var access: Access { store.access(me, siteAdmin: model.me?.isAdmin ?? false) }

    private var tabs: [(String, String)] {
        var out: [(String, String)] = []
        if access.can(.manage_server) { out.append(("Overview", "slider.horizontal.3")) }
        if access.can(.manage_roles) { out.append(("Roles", "tag.fill")) }
        if access.can(.manage_channels) { out.append(("Channels", "number")) }
        if access.can(.manage_roles) { out.append(("Everyone", "person.3.fill")) }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tabs.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tabs.indices, id: \.self) { i in
                                    Chip(title: tabs[i].0, icon: tabs[i].1, active: tab == i) { withMotion(Motion.standard) { tab = i } }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    switch tabs.indices.contains(tab) ? tabs[tab].0 : "" {
                    case "Overview": overview
                    case "Roles": roles
                    case "Channels": channels
                    case "Everyone": everyone
                    default: EmptyCard(icon: "lock.fill", title: "No settings for you", text: "Ask the owner for a role that can manage the server.")
                    }
                }
                .padding(16)
            }
            .sugarBackground()
            .navigationTitle("Server settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            name = store.server.name
            about = store.server.description
            welcome = store.server.welcome
            emoji = store.server.emoji
        }
        .onChange(of: iconItem) { _, item in load(item) { iconImage = $0 } }
        .onChange(of: bannerItem) { _, item in load(item) { bannerImage = $0 } }
        .sheet(item: $editingRole) { draft in
            RoleEditor(store: store, draft: draft).presentationCornerRadius(24)
        }
        .sheet(item: $editingChannel) { channel in
            ChannelEditor(store: store, channel: channel, type: channel.type).presentationCornerRadius(24)
        }
        .sheet(item: Binding(get: { newChannelType.map { NewChannelKind(type: $0) } }, set: { newChannelType = $0?.type })) { kind in
            ChannelEditor(store: store, channel: nil, type: kind.type).presentationCornerRadius(24)
        }
        .confirmationDialog("Delete \(store.server.name)? This can't be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete server", role: .destructive) {
                Task {
                    try? await FS.delete("Community", store.server.id)
                    model.showToast("Server deleted", icon: "trash.fill")
                    dismiss()
                    onDeleted()
                }
            }
        }
    }

    // MARK: overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $bannerItem, matching: .images) {
                ZStack {
                    if let bannerImage { Image(uiImage: bannerImage).resizable().scaledToFill() }
                    else if !store.server.bannerURL.isEmpty { RemoteImage(url: store.server.bannerURL, live: true) }
                    else { Theme.gradient }
                    Label("Change banner", systemImage: "photo").font(.jakarta(12, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 30).background(.black.opacity(0.35), in: Capsule())
                }
                .frame(height: 110).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            HStack(alignment: .top, spacing: 12) {
                PhotosPicker(selection: $iconItem, matching: .images) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.soft)
                        if let iconImage { Image(uiImage: iconImage).resizable().scaledToFill() }
                        else if !store.server.iconURL.isEmpty { RemoteImage(url: store.server.iconURL) }
                        else { LinearGradient(colors: [Theme.light, Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(Text(ServerIcon.initials(name)).font(.display(26)).foregroundStyle(.white)) }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                Text("Tap to upload an icon").font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            SugarField(placeholder: "Server name", text: $name)
            SugarField(placeholder: "Description", text: $about, lines: 2...4)
            SugarField(placeholder: "Welcome message", text: $welcome)
            Button { Task { await saveOverview() } } label: {
                if busy { ProgressView().tint(.white) } else { Label("Save changes", systemImage: "checkmark") }
            }
            .buttonStyle(GradientButtonStyle(height: 48))
            .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            if access.isOwner || model.me?.isAdmin == true {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete server", systemImage: "trash").foregroundStyle(Palette.danger)
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
                .padding(.top, 10)
            }
        }
    }

    private func load(_ item: PhotosPickerItem?, into: @escaping (UIImage) -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { into(image) }
        }
    }

    private func saveOverview() async {
        guard await TextGuard.clear([name], kind: .name, model: model, cooldown: false),
              await TextGuard.clear([about, welcome], kind: .profile, model: model) else { return }
        busy = true
        defer { busy = false }
        var fields: Doc = [
            "name": String(name.trimmingCharacters(in: .whitespaces).prefix(40)),
            "description": String(about.prefix(160)), "welcome_message": String(welcome.prefix(160)),
            "icon_emoji": emoji, "updated_date": FS.nowISO(),
        ]
        do {
            if let iconImage, let jpeg = ImageTools.jpeg(iconImage, maxSide: 512) {
                fields["icon_url"] = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            }
            if let bannerImage, let jpeg = ImageTools.jpeg(bannerImage, maxSide: 1600) {
                fields["banner_url"] = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            }
            try await FS.update("Community", store.server.id, fields)
            await store.load()
            model.showToast("Server updated", icon: "sparkles")
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }

    // MARK: roles

    private var roles: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Roles decide what people can do. Higher roles come first.").font(.jakarta(13)).foregroundStyle(Palette.muted)
                Spacer()
            }
            ForEach(store.sortedRoles) { role in
                let editable = store.canEditRole(access, role)
                Button { editingRole = RoleDraft(role) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(role.tint).frame(width: 16, height: 16)
                            .shadow(color: role.tint.opacity(0.5), radius: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(role.name).font(.jakarta(15, .bold)).foregroundStyle(role.tint)
                            Text("\(store.members.filter { $0.roles.contains(role.id) }.count) members · \(role.permissions.filter(\.value).count) permissions")
                                .font(.jakarta(11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: editable ? "chevron.right" : "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                    .sugarCard(radius: 18, padding: 12)
                }
                .buttonStyle(BouncyStyle(scale: 0.98))
                .disabled(!editable)
            }
            Button { editingRole = RoleDraft(position: (store.roles.map(\.position).max() ?? -1) + 1) } label: {
                Label("New role", systemImage: "plus")
            }
            .buttonStyle(GradientButtonStyle(height: 46))
        }
    }

    // MARK: channels

    private var channels: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.channels) { channel in
                Button { editingChannel = channel } label: {
                    HStack(spacing: 10) {
                        Image(systemName: channel.isVoice ? "speaker.wave.2.fill" : "number").foregroundStyle(Theme.main).frame(width: 24)
                        Text(channel.name).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                        if channel.isPrivate { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                    .sugarCard(radius: 16, padding: 12)
                }
                .buttonStyle(BouncyStyle(scale: 0.98))
            }
            HStack(spacing: 10) {
                Button { newChannelType = "text" } label: { Label("Text channel", systemImage: "number") }
                    .buttonStyle(GradientButtonStyle(height: 44))
                Button { newChannelType = "voice" } label: { Label("Voice channel", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            }
        }
    }

    // MARK: @everyone

    private var everyone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What every member can do, before any roles.").font(.jakarta(13)).foregroundStyle(Palette.muted)
            ForEach([ServerPerm.create_invite, .send_messages, .attach_files, .add_reactions, .mention_roles, .connect, .speak, .video], id: \.self) { perm in
                let on = (ServerPerm.everyoneDefaults.merging(store.server.everyone, uniquingKeysWith: { $1 }))[perm.rawValue] ?? false
                PermissionToggle(perm: perm, on: on) { value in
                    var next = ServerPerm.everyoneDefaults.merging(store.server.everyone, uniquingKeysWith: { $1 })
                    next[perm.rawValue] = value
                    store.server.everyone = next
                    let payload: [String: Any] = next.mapValues { $0 as Any }
                    Task { try? await FS.update("Community", store.server.id, ["everyone_permissions": payload, "updated_date": FS.nowISO()]) }
                }
            }
        }
    }
}

struct PermissionToggle: View {
    let perm: ServerPerm
    let on: Bool
    var set: (Bool) -> Void

    // The iPhone's own switch, in your colour.
    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { set($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(perm.label).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                Text(perm.detail).font(.jakarta(11)).foregroundStyle(Palette.muted).multilineTextAlignment(.leading)
            }
        }
        .tint(Theme.main)
        .sugarCard(radius: 16, padding: 12)
        .sensoryFeedback(.selection, trigger: on)
    }
}

// MARK: - Role editor

struct RoleDraft: Identifiable {
    var id: String
    var name: String
    var color: String
    var permissions: [String: Bool]
    var position: Int
    var isNew: Bool

    init(_ role: ServerRole) {
        id = role.id
        name = role.name
        color = role.color.isEmpty ? "#d9577f" : role.color
        permissions = role.permissions
        position = role.position
        isNew = false
    }

    init(position: Int) {
        id = UUID().uuidString
        name = "New role"
        color = "#b19cff"
        permissions = [:]
        self.position = position
        isNew = true
    }
}

struct RoleEditor: View {
    let store: ServerStore
    @State var draft: RoleDraft
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var confirmDelete = false

    static let colors = ["#d9577f", "#ff4d7d", "#ff9f6b", "#f0a020", "#ffd35c", "#5fd3b0", "#16a37f", "#7cbeff", "#2f80e0", "#b19cff", "#7c5cf0", "#94a3b8"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: ReelText.hex(draft.color))).frame(width: 40, height: 40)
                            .shadow(color: Color(hex: ReelText.hex(draft.color)).opacity(0.5), radius: 8)
                        Text(draft.name.isEmpty ? "Role" : draft.name).font(.display(28)).foregroundStyle(Color(hex: ReelText.hex(draft.color)))
                    }
                    SugarField(placeholder: "Role name", text: $draft.name)
                    Text("COLOUR").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(Self.colors, id: \.self) { c in
                            Button { draft.color = c } label: {
                                Circle().fill(Color(hex: ReelText.hex(c))).frame(height: 40)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: draft.color == c ? 3 : 0))
                                    .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: draft.color == c ? 1 : 0).padding(-2))
                                    .scaleEffect(draft.color == c ? 1.1 : 1)
                            }
                            .buttonStyle(BouncyStyle())
                        }
                    }
                    ForEach(ServerPerm.groups, id: \.0) { group in
                        Text(group.0.uppercased()).font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted).padding(.top, 6)
                        ForEach(group.1, id: \.self) { perm in
                            PermissionToggle(perm: perm, on: draft.permissions[perm.rawValue] ?? false) { value in
                                draft.permissions[perm.rawValue] = value
                            }
                        }
                    }
                    Button { Task { await save() } } label: {
                        if busy { ProgressView().tint(.white) } else { Label(draft.isNew ? "Create role" : "Save role", systemImage: "checkmark") }
                    }
                    .buttonStyle(GradientButtonStyle(height: 48))
                    .disabled(busy || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !draft.isNew {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete role", systemImage: "trash").foregroundStyle(Palette.danger) }
                            .buttonStyle(OutlineButtonStyle(fullWidth: true))
                    }
                }
                .padding(16)
            }
            .sugarBackground()
            .navigationTitle(draft.isNew ? "New role" : "Edit role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .confirmationDialog("Delete this role?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await remove() } }
        }
    }

    private func save() async {
        guard await TextGuard.clear([draft.name], kind: .name, model: model) else { return }
        busy = true
        defer { busy = false }
        let perms: [String: Any] = draft.permissions.mapValues { $0 as Any }
        do {
            if draft.isNew {
                _ = try await FS.create("ServerRole", ["community_id": store.server.id, "name": draft.name.trimmingCharacters(in: .whitespaces), "color": draft.color, "permissions": perms, "position": draft.position])
            } else {
                try await FS.update("ServerRole", draft.id, ["name": draft.name.trimmingCharacters(in: .whitespaces), "color": draft.color, "permissions": perms, "updated_date": FS.nowISO()])
            }
            await store.load()
            await store.syncPermIndex()
            model.showToast(draft.isNew ? "Role created" : "Role saved", icon: "tag.fill")
            dismiss()
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }

    private func remove() async {
        try? await FS.delete("ServerRole", draft.id)
        for m in store.members where m.roles.contains(draft.id) && !m.id.isEmpty {
            try? await FS.update("ServerMember", m.id, ["roles": m.roles.filter { $0 != draft.id }])
        }
        await store.load()
        await store.syncPermIndex()
        model.showToast("Role deleted", icon: "trash.fill")
        dismiss()
    }
}

// MARK: - Channel editor

struct ChannelEditor: View {
    let store: ServerStore
    let channel: ServerChannel?
    let type: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var about = ""
    @State private var isPrivate = false
    @State private var allowed: Set<String> = []
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: type == "voice" ? "speaker.wave.2.fill" : "number").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(type == "voice" ? "Voice channel" : "Text channel").font(.display(26)).foregroundStyle(Palette.text)
                    }
                    SugarField(placeholder: type == "voice" ? "Lounge" : "new-channel", text: $name)
                    SugarField(placeholder: "Topic (optional)", text: $about)
                    Button { withMotion(Motion.standard) { isPrivate.toggle() } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Private channel", systemImage: "lock.fill").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                                Text("Only chosen roles can see it (and people who manage channels).").font(.jakarta(11)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: isPrivate ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(isPrivate ? Theme.main : Palette.muted)
                        }
                        .sugarCard(radius: 16, padding: 12)
                    }
                    .buttonStyle(SoftPressStyle())
                    if isPrivate || !allowed.isEmpty {
                        Text(isPrivate ? "WHO CAN SEE IT" : "WHO CAN POST").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                        FlowLayout(spacing: 6) {
                            ForEach(store.sortedRoles) { role in
                                let on = allowed.contains(role.id)
                                Button { if on { allowed.remove(role.id) } else { allowed.insert(role.id) } } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(role.tint).frame(width: 9, height: 9)
                                        Text(role.name).font(.jakarta(12, .bold)).foregroundStyle(on ? .white : Palette.text2)
                                    }
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(on ? AnyShapeStyle(role.tint) : AnyShapeStyle(Palette.surface), in: Capsule())
                                    .overlay(Capsule().strokeBorder(role.tint.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(BouncyStyle())
                            }
                        }
                    }
                    Button { Task { await save() } } label: {
                        if busy { ProgressView().tint(.white) } else { Label(channel == nil ? "Create channel" : "Save", systemImage: "checkmark") }
                    }
                    .buttonStyle(GradientButtonStyle(height: 48))
                    .disabled(busy || Servers.slug(name, voice: type == "voice").isEmpty)
                    if let channel {
                        Button(role: .destructive) {
                            Task {
                                try? await FS.delete("ServerChannel", channel.id)
                                await store.load()
                                model.showToast("Channel deleted", icon: "trash.fill")
                                dismiss()
                            }
                        } label: { Label("Delete channel", systemImage: "trash").foregroundStyle(Palette.danger) }
                            .buttonStyle(OutlineButtonStyle(fullWidth: true))
                    }
                }
                .padding(16)
            }
            .sugarBackground()
            .navigationTitle(channel == nil ? "New channel" : "Edit channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            if let channel {
                name = channel.name
                about = channel.description
                isPrivate = channel.isPrivate
                allowed = Set(channel.allowedRoles)
            }
        }
    }

    private func save() async {
        guard await TextGuard.clear([name], kind: .name, model: model),
              await TextGuard.clear([about], kind: .profile, model: model, cooldown: false) else { return }
        busy = true
        defer { busy = false }
        let clean = Servers.slug(name, voice: type == "voice")
        let fields: Doc = [
            "name": clean, "description": about.trimmingCharacters(in: .whitespaces),
            "private": isPrivate && !allowed.isEmpty, "allowed_roles": Array(allowed),
        ]
        do {
            if let channel {
                var update = fields
                update["updated_date"] = FS.nowISO()
                try await FS.update("ServerChannel", channel.id, update)
            } else {
                var create = fields
                create["community_id"] = store.server.id
                create["type"] = type
                create["position"] = store.channels.count
                _ = try await FS.create("ServerChannel", create)
            }
            await store.load()
            model.showToast(channel == nil ? "Channel created" : "Channel saved", icon: "number")
            dismiss()
        } catch {
            model.showToast("Couldn't save — \(error.localizedDescription)", error: true)
        }
    }
}
