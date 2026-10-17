import SwiftUI
import UIKit
import PhotosUI

// MARK: - A text channel

struct ChannelChatView: View {
    let server: Server
    let channel: ServerChannel
    @Environment(AppModel.self) private var model
    @State private var store: ServerStore
    @State private var messages: [ChannelMessage] = []
    @State private var draft = ""
    @State private var replyTo: ChannelMessage?
    @State private var editing: ChannelMessage?
    @State private var photo: PhotosPickerItem?
    @State private var gifs = false
    @State private var loaded = false
    @State private var hasOlder = false
    @State private var loadingOlder = false
    @State private var failed: String?
    @State private var reporting: ReportSheet.Target?
    @State private var pinsShown = false
    @State private var membersShown = false
    @State private var profile: String?
    @State private var confirmDelete: ChannelMessage?
    @FocusState private var focused: Bool

    init(server: Server, channel: ServerChannel) {
        self.server = server
        self.channel = channel
        _store = State(initialValue: ServerStore(server))
    }

    private var me: String { model.me?.email ?? "" }
    private var access: Access { store.access(me, siteAdmin: model.me?.isAdmin ?? false) }
    private var isMember: Bool { store.server.members.contains(me) }
    private var canPost: Bool { isMember && store.canPost(channel, access) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if loaded {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "number").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 64, height: 64).background(Theme.gradient, in: Circle())
                                .shadow(color: Palette.shadow, radius: 12, y: 6)
                            Text("Welcome to #\(channel.name)!").font(.display(28)).foregroundStyle(Palette.text)
                            Text(channel.description.isEmpty ? "This is the start of the #\(channel.name) channel." : channel.description)
                                .font(.jakarta(14)).foregroundStyle(Palette.muted)
                        }
                        .padding(.vertical, 20)
                    } else {
                        ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                    }
                    if loaded && hasOlder {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Theme.main)
                            Text("Loading earlier messages").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .onAppear { Task { await loadOlder(proxy) } }
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let grouped = previous != nil && previous!.authorEmail == message.authorEmail && previous!.kind != "join" && !gap(previous!, message) && message.replyPreview.isEmpty
                        ChannelMessageRow(message: message, grouped: grouped, mine: message.authorEmail == me,
                                          nameColor: store.nameColor(message.authorEmail), roleName: store.topRole(message.authorEmail)?.name,
                                          me: me, onReact: { react(message, $0) }, onProfile: { profile = message.authorEmail })
                            .id(message.id)
                            // Long-press lifts the message on a soft card
                            // of its own shape.
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contextMenu { menu(message) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // On iPad the channel stays a readable width.
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withMotion(Motion.standard) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .sugarBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ServerIcon(server: store.server, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("#\(channel.name)").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                        Text(store.server.name).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { pinsShown = true } label: { Image(systemName: "pin.fill") }.accessibilityLabel("Pinned messages")
                Button { membersShown = true } label: { Image(systemName: "person.2.fill") }.accessibilityLabel("Members")
            }
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $gifs) { GifPickerSheet { url in Task { await sendMedia(url) } } }
        .sheet(isPresented: $pinsShown) {
            PinsSheet(messages: messages.filter(\.pinned), store: store).presentationDetents([.medium, .large]).presentationCornerRadius(32)
        }
        .sheet(isPresented: $membersShown) {
            MembersSheet(store: store) { _ in membersShown = false }
                .presentationDetents([.medium, .large]).presentationCornerRadius(32)
        }
        .sheet(item: Binding(get: { profile.map { EmailBox(email: $0) } }, set: { profile = $0?.email })) { box in
            MemberSheet(store: store, email: box.email) { _ in profile = nil }
                .presentationDetents([.medium, .large]).presentationCornerRadius(32)
        }
        .confirmationDialog("Delete this message?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible, presenting: confirmDelete) { message in
            Button("Delete message", role: .destructive) { delete(message) }
            Button("Cancel", role: .cancel) {}
        } message: { message in
            Text(message.text.isEmpty ? "This can't be undone." : "\"\(message.text.prefix(80))\" will be removed for everyone.")
        }
        .onAppear { Alerts.shared.openChannel = channel.id }
        .onDisappear { if Alerts.shared.openChannel == channel.id { Alerts.shared.openChannel = nil } }
        .task {
            await store.load()
            await poll()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
    }

    @ViewBuilder
    private func menu(_ message: ChannelMessage) -> some View {
        if access.can(.add_reactions) {
            ControlGroup {
                ForEach(["❤️", "😂", "😮", "😢", "👍", "🔥"], id: \.self) { e in Button(e) { react(message, e) } }
            }
            .controlGroupStyle(.compactMenu)
        }
        if canPost { Button { replyTo = message; editing = nil; focused = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") } }
        if !message.text.isEmpty { Button { UIPasteboard.general.string = message.text; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy", systemImage: "doc.on.doc") } }
        if message.authorEmail == me && !message.text.isEmpty {
            Button { editing = message; replyTo = nil; draft = message.text; focused = true } label: { Label("Edit", systemImage: "pencil") }
        }
        if access.can(.pin_messages) || access.can(.manage_messages) {
            Button { pin(message) } label: { Label(message.pinned ? "Unpin" : "Pin", systemImage: message.pinned ? "pin.slash" : "pin") }
        }
        if message.authorEmail == me || access.can(.manage_messages) || model.me?.isAdmin == true {
            Button(role: .destructive) { confirmDelete = message } label: { Label("Delete message", systemImage: "trash") }
        }
        if message.authorEmail != me {
            Button { reporting = ReportSheet.Target(id: message.id, type: "server message", ownerEmail: message.authorEmail, preview: message.text, link: "/CommunityChat?id=\(server.id)", collection: "ChannelMessage", media: message.imageURL) } label: { Label("Report", systemImage: "flag") }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let failed { Text(failed).font(.jakarta(12, .semibold)).foregroundStyle(Palette.danger) }
            if let target = replyTo ?? editing {
                HStack {
                    Image(systemName: editing != nil ? "pencil" : "arrowshape.turn.up.left.fill").foregroundStyle(Theme.main)
                    Text(editing != nil ? "Editing your message" : "Replying to \(model.name(target.authorEmail, target.authorName))").font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                    Spacer()
                    Button { replyTo = nil; if editing != nil { editing = nil; draft = "" } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                }
                .padding(.horizontal, 6)
            }
            if canPost {
                HStack(alignment: .bottom, spacing: 10) {
                    if access.can(.attach_files) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.main)
                                .frame(width: 42, height: 42)
                                .background(Theme.soft, in: Circle())
                        }
                        .buttonStyle(BouncyStyle())
                    }
                    GifButton { gifs = true }
                    TextField("Message #\(channel.name)", text: $draft, axis: .vertical)
                        .font(.jakarta(15))
                        .focused($focused)
                        .lineLimit(1...6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    SendButton(enabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { Task { await send() } }
                }
            } else if store.loaded && !isMember {
                Button {
                    guard let meProfile = model.me else { return }
                    Task {
                        try? await Servers.join(store.server, me: meProfile)
                        await store.load()
                        model.showToast("Welcome to \(store.server.name)!", icon: "party.popper.fill")
                    }
                } label: { Label("Join \(store.server.name) to chat", systemImage: "person.badge.plus") }
                    .buttonStyle(GradientButtonStyle(height: 44))
            } else if store.loaded {
                Label("You can't send messages in this channel.", systemImage: "lock.fill")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted).padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .background {
            Palette.surface
                .shadow(color: Palette.shadow, radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func gap(_ a: ChannelMessage, _ b: ChannelMessage) -> Bool {
        guard let x = Dates.parse(a.created), let y = Dates.parse(b.created) else { return false }
        return y.timeIntervalSince(x) > 7 * 60
    }

    private func poll() async {
        var tick = 0
        while !Task.isCancelled {
            await load(full: tick % 10 == 9)
            tick += 1
            let slow = FS.missingIndex.contains("ChannelMessage")
            try? await Task.sleep(for: .seconds(slow ? 4 : 2.5))
        }
    }

    // New messages often; every so often the whole recent history (so edits,
    // reactions, pins and deletions from others show up too).
    private func load(full: Bool = false) async {
        var filters: [FS.Filter] = [.equals("channel_id", channel.id)]
        let newest = messages.last(where: { !$0.pending })?.created ?? ""
        let incremental = loaded && !full && !newest.isEmpty
        if incremental { filters.append(.after("created_date", ChatStore.minus(newest, seconds: 60))) }
        let page = incremental ? 60 : 150
        guard let docs = try? await FS.query("ChannelMessage", filters, orderBy: "created_date", limit: page) else {
            loaded = true
            return
        }
        let blocked = Set(model.me?.blocked ?? [])
        let incoming = docs.map(ChannelMessage.init).filter { !blocked.contains($0.authorEmail) }
        if !loaded { hasOlder = docs.count >= page }
        if incremental && docs.count < page {
            let known = Set(messages.map(\.id))
            let fresh = incoming.filter { !known.contains($0.id) }
            if !fresh.isEmpty { withMotion(Motion.standard) { messages = (messages + fresh).sorted { $0.created < $1.created } } }
        } else {
            // Refresh the newest page (edits, reactions, pins, deletions) but
            // keep any older history you've already scrolled back to.
            let cutoff = docs.map { $0.str("created_date") }.filter { !$0.isEmpty }.min() ?? ""
            let older = messages.filter { !$0.pending && !cutoff.isEmpty && $0.created < cutoff }
            let pending = messages.filter(\.pending)
            let next = (older + incoming + pending).sorted { $0.created < $1.created }
            if incremental { hasOlder = true }
            if next != messages { withAnimation(loaded ? .snappy : nil) { messages = next } }
        }
        loaded = true
    }

    // The page before the oldest message on screen, keeping your place.
    private func loadOlder(_ proxy: ScrollViewProxy) async {
        guard !loadingOlder, let oldest = messages.first(where: { !$0.pending }) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        let filters: [FS.Filter] = [.equals("channel_id", channel.id), .before("created_date", oldest.created)]
        guard let docs = try? await FS.query("ChannelMessage", filters, orderBy: "created_date", limit: 100) else { return }
        hasOlder = docs.count >= 100
        let blocked = Set(model.me?.blocked ?? [])
        let known = Set(messages.map(\.id))
        let page = docs.map(ChannelMessage.init).filter { !known.contains($0.id) && !blocked.contains($0.authorEmail) }
        guard !page.isEmpty else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { messages = (page + messages).sorted { $0.created < $1.created } }
        DispatchQueue.main.async { proxy.scrollTo(oldest.id, anchor: .top) }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let meProfile = model.me else { return }
        if Moderation.hasLink(text) && !meProfile.isAdmin {
            failed = "Links aren't allowed in server chats."
            return
        }
        guard await TextGuard.clear([text], kind: .message, model: model, cooldown: editing == nil) else { return }
        failed = nil
        draft = ""
        TapSound.play(.send)
        if let editing {
            self.editing = nil
            if let i = messages.firstIndex(where: { $0.id == editing.id }) { messages[i].text = text; messages[i].edited = true }
            Task { try? await FS.update("ChannelMessage", editing.id, ["content": text, "is_edited": true, "updated_date": FS.nowISO()]) }
            return
        }
        let data = Servers.message(channel: channel.id, server: server.id, me: meProfile, text: text, imageURL: "", reply: replyTo)
        replyTo = nil
        var pending = ChannelMessage(data)
        pending.id = "pending-\(UUID().uuidString)"
        pending.created = FS.nowISO()
        pending.pending = true
        withMotion(Motion.standard) { messages.append(pending) }
        do {
            let doc = try await FS.create("ChannelMessage", data)
            let created = ChannelMessage(doc)
            if let i = messages.firstIndex(where: { $0.id == pending.id }) { messages[i] = created }
            mentions(text, me: meProfile)
        } catch {
            withMotion { messages.removeAll { $0.id == pending.id } }
            draft = text
            failed = "Couldn't send — \(error.localizedDescription)"
        }
    }

    // @name pings people in the server (like the website).
    private func mentions(_ text: String, me: UserProfile) {
        let names = text.split(separator: " ").filter { $0.hasPrefix("@") }.map { $0.dropFirst().lowercased() }
        guard !names.isEmpty else { return }
        for m in store.members where m.email != me.email {
            let compact = m.name.lowercased().replacingOccurrences(of: " ", with: "")
            if names.contains(compact) {
                Notify.send(to: m.email, from: me, type: "mention", message: "\(me.displayName) mentioned you in #\(channel.name)", link: "/CommunityChat?id=\(server.id)")
            }
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard await TextGuard.clear([], kind: .message, model: model) else { return }
        guard let meProfile = model.me,
              let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw), let jpeg = ImageTools.jpeg(image, maxSide: 1600) else { return }
        do {
            let url = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            let doc = try await FS.create("ChannelMessage", Servers.message(channel: channel.id, server: server.id, me: meProfile, text: "", imageURL: url))
            withMotion(Motion.standard) { messages.append(ChannelMessage(doc)) }
        } catch {
            failed = "Couldn't send the photo — \(error.localizedDescription)"
        }
    }

    private func sendMedia(_ url: String) async {
        guard let meProfile = model.me else { return }
        guard await TextGuard.clear([], kind: .message, model: model) else { return }
        do {
            let doc = try await FS.create("ChannelMessage", Servers.message(channel: channel.id, server: server.id, me: meProfile, text: "", imageURL: url, reply: replyTo))
            replyTo = nil
            withMotion(Motion.standard) { messages.append(ChannelMessage(doc)) }
        } catch {
            failed = "Couldn't send — \(error.localizedDescription)"
        }
    }

    private func react(_ message: ChannelMessage, _ emoji: String) {
        guard !message.pending, access.can(.add_reactions), let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        var reactions = messages[i].reactions
        var people = reactions[emoji] ?? []
        if people.contains(me) { people.removeAll { $0 == me } } else { people.append(me) }
        reactions[emoji] = people.isEmpty ? nil : people
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { messages[i].reactions = reactions }
        let payload: [String: Any] = reactions.mapValues { $0 as Any }
        Task { try? await FS.update("ChannelMessage", message.id, ["reactions": payload, "updated_date": FS.nowISO()]) }
    }

    private func pin(_ message: ChannelMessage) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].pinned.toggle()
        let now = messages[i].pinned
        model.showToast(now ? "Pinned to #\(channel.name)" : "Unpinned", icon: "pin.fill")
        Task { try? await FS.update("ChannelMessage", message.id, ["is_pinned": now, "updated_date": FS.nowISO()]) }
    }

    private func delete(_ message: ChannelMessage) {
        withMotion { messages.removeAll { $0.id == message.id } }
        Task { try? await FS.delete("ChannelMessage", message.id) }
    }
}

struct ChannelMessageRow: View {
    let message: ChannelMessage
    let grouped: Bool
    let mine: Bool
    var nameColor: Color? = nil
    var roleName: String? = nil
    var me = ""
    var onReact: (String) -> Void = { _ in }
    var onProfile: () -> Void = {}
    @Environment(AppModel.self) private var model

    var body: some View {
        if message.kind == "join" {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.success)
                Text(message.text).font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                Text(Dates.time(message.created)).font(.jakarta(11)).foregroundStyle(Palette.muted.opacity(0.7))
            }
            .padding(.vertical, 6)
            .padding(.leading, 12)
        } else {
            HStack(alignment: .top, spacing: 10) {
                if grouped {
                    Color.clear.frame(width: 40, height: 1)
                } else {
                    Button(action: onProfile) {
                        Avatar(url: model.person(message.authorEmail)?.picture ?? message.authorPicture, name: message.authorName, size: 40, online: model.person(message.authorEmail)?.isOnline ?? false)
                    }
                    .buttonStyle(BouncyStyle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !message.replyPreview.isEmpty {
                        Label(message.replyPreview, systemImage: "arrowshape.turn.up.left.fill")
                            .font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if !grouped {
                        HStack(spacing: 6) {
                            Button(action: onProfile) {
                                Text(model.person(message.authorEmail)?.displayName ?? message.authorName)
                                    .font(.jakarta(14, .heavy))
                                    .foregroundStyle(nameColor.map { AnyShapeStyle($0) } ?? (mine ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.text)))
                            }
                            .buttonStyle(SoftPressStyle())
                            if let roleName {
                                Text(roleName).font(.jakarta(9, .heavy)).foregroundStyle(nameColor ?? Palette.muted)
                                    .padding(.horizontal, 6).frame(height: 16)
                                    .background((nameColor ?? Palette.muted).opacity(0.12), in: Capsule())
                            }
                            Text(Dates.ago(message.created)).font(.jakarta(11)).foregroundStyle(Palette.muted)
                            if message.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.main) }
                        }
                    }
                    if !message.text.isEmpty {
                        (Text(message.text).font(.jakarta(15)).foregroundColor(Palette.text)
                         + Text(message.edited ? "  (edited)" : "").font(.jakarta(11)).foregroundColor(Palette.muted))
                    }
                    if !message.imageURL.isEmpty {
                        MessageMedia(url: message.imageURL, width: 260, widest: 1.8)
                    }
                    if !message.reactions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(message.reactions.keys.sorted(), id: \.self) { emoji in
                                let people = message.reactions[emoji] ?? []
                                let mineToo = people.contains(me)
                                Button { onReact(emoji) } label: {
                                    HStack(spacing: 3) {
                                        Text(emoji).font(.system(size: 13))
                                        Text("\(people.count)").font(.jakarta(11, .heavy)).foregroundStyle(mineToo ? Theme.main : Palette.text2)
                                    }
                                    .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 8).frame(height: 26)
                                    .background(mineToo ? Theme.soft : Palette.surface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(mineToo ? Theme.main.opacity(0.4) : Palette.border, lineWidth: 1))
                                }
                                .buttonStyle(BouncyStyle(scale: 0.85))
                            }
                        }
                    }
                }
                .opacity(message.pending ? 0.55 : 1)
                Spacer(minLength: 0)
            }
            .padding(.top, grouped ? 0 : 10)
            .padding(.vertical, message.pinned ? 4 : 0)
            .background(message.pinned ? Theme.soft.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct PinsSheet: View {
    let messages: [ChannelMessage]
    let store: ServerStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Pinned", systemImage: "pin.fill").font(.display(26)).foregroundStyle(Palette.text).padding(.top, 20)
                if messages.isEmpty {
                    EmptyCard(icon: "pin.fill", title: "No pins yet", text: "Long-press a message and tap Pin to keep it here.")
                }
                ForEach(messages) { m in
                    ChannelMessageRow(message: m, grouped: false, mine: false, nameColor: store.nameColor(m.authorEmail), roleName: store.topRole(m.authorEmail)?.name)
                        .padding(10)
                        .sugarCard(radius: 18)
                }
            }
            .padding(16)
        }
        .sugarBackground()
    }
}

// MARK: - Members (grouped by role, with colours)

struct MembersSheet: View {
    let store: ServerStore
    var open: (Route) -> Void
    @Environment(AppModel.self) private var model
    @State private var selected: String?

    private var groups: [(String, Color?, [String])] {
        var used = Set<String>()
        var out: [(String, Color?, [String])] = []
        let online = { (e: String) -> Bool in model.person(e)?.isOnline == true }
        for role in store.sortedRoles {
            let list = store.server.members.filter { !used.contains($0) && store.topRole($0)?.id == role.id }
            guard !list.isEmpty else { continue }
            used.formUnion(list)
            out.append((role.name, role.tint, list.sorted { online($0) && !online($1) }))
        }
        let rest = store.server.members.filter { !used.contains($0) }
        if !rest.isEmpty { out.append(("Members", nil, rest.sorted { online($0) && !online($1) })) }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("Members · \(store.server.members.count)").font(.display(26)).foregroundStyle(Palette.text).padding(.top, 20)
                ForEach(groups, id: \.0) { group in
                    HStack(spacing: 6) {
                        if let color = group.1 { Circle().fill(color).frame(width: 8, height: 8) }
                        Text("\(group.0.uppercased()) — \(group.2.count)").font(.jakarta(11, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 10)
                    ForEach(group.2, id: \.self) { email in
                        row(email)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .sugarBackground()
        .sheet(item: Binding(get: { selected.map { EmailBox(email: $0) } }, set: { selected = $0?.email })) { box in
            MemberSheet(store: store, email: box.email, open: { route in
                selected = nil
                open(route)
            })
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
        }
    }

    private func row(_ email: String) -> some View {
        let person = model.person(email)
        let member = store.member(email)
        let nick = member?.nickname ?? ""
        let shownName = nick.isEmpty ? (person?.displayName ?? member?.name ?? email) : nick
        return Button { selected = email } label: {
            HStack(spacing: 12) {
                Avatar(url: person?.picture ?? member?.picture ?? "", name: shownName, size: 42, online: person?.isOnline ?? false)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(shownName).font(.jakarta(15, .bold)).foregroundStyle(store.nameColor(email) ?? Palette.text).lineLimit(1)
                        if email == store.server.ownerEmail { Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(Palette.warning) }
                    }
                    Text(person?.isOnline == true ? "Online" : "Offline").font(.jakarta(11)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .opacity(person?.isOnline == true ? 1 : 0.7)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }
}

// One member: profile preview, roles you can give, kick.
struct MemberSheet: View {
    let store: ServerStore
    let email: String
    var open: (Route) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmKick = false
    @State private var busy = false

    private var me: String { model.me?.email ?? "" }
    private var actor: Access { store.access(me, siteAdmin: model.me?.isAdmin ?? false) }

    var body: some View {
        let person = model.person(email)
        let member = store.member(email)
        let roleIds = member?.roles ?? []
        let name = person?.displayName ?? member?.name ?? email
        ScrollView {
            VStack(spacing: 14) {
                Avatar(url: person?.picture ?? member?.picture ?? "", name: name, size: 88, online: person?.isOnline ?? false, ring: true)
                    .padding(.top, 24)
                VStack(spacing: 4) {
                    Text(name).font(.display(28)).foregroundStyle(store.nameColor(email) ?? Palette.text)
                    if let bio = person?.bio, !bio.isEmpty { Text(bio).font(.jakarta(13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center) }
                }
                FlowLayout(spacing: 6) {
                    if email == store.server.ownerEmail {
                        Label("Owner", systemImage: "crown.fill").font(.jakarta(12, .bold)).foregroundStyle(Palette.warning)
                            .padding(.horizontal, 10).frame(height: 28).background(Palette.warning.opacity(0.12), in: Capsule())
                    }
                    ForEach(store.sortedRoles.filter { roleIds.contains($0.id) }) { role in
                        HStack(spacing: 5) {
                            Circle().fill(role.tint).frame(width: 9, height: 9)
                            Text(role.name).font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                        }
                        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 28)
                        .background(role.tint.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 10) {
                    Button { dismiss(); open(.person(email)) } label: { Label("Profile", systemImage: "person.fill") }
                        .buttonStyle(OutlineButtonStyle(fullWidth: true))
                    if email != me {
                        Button {
                            let convo = Conversation(id: Social.dmId(me, email), members: [me, email], isGroup: false, groupName: "", last: nil, unread: 0)
                            dismiss()
                            open(.chat(convo))
                        } label: { Label("Message", systemImage: "paperplane.fill") }
                            .buttonStyle(GradientButtonStyle(height: 44))
                    }
                }
                if actor.can(.manage_roles) && store.canActOn(actor, email) && !store.roles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROLES").font(.jakarta(11, .heavy)).tracking(1.1).foregroundStyle(Palette.muted)
                        ForEach(store.sortedRoles) { role in
                            let has = roleIds.contains(role.id)
                            let editable = store.canEditRole(actor, role)
                            Button { Task { await toggle(role, on: !has) } } label: {
                                HStack {
                                    Circle().fill(role.tint).frame(width: 12, height: 12)
                                    Text(role.name).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                                    Spacer()
                                    Image(systemName: has ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(has ? role.tint : Palette.muted)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(BouncyStyle(scale: 0.98))
                            .disabled(!editable || busy)
                            .opacity(editable ? 1 : 0.5)
                        }
                    }
                }
                if actor.can(.kick_members) && store.canActOn(actor, email) && email != me {
                    Button(role: .destructive) { confirmKick = true } label: { Label("Kick from server", systemImage: "person.fill.xmark").foregroundStyle(Palette.danger) }
                        .buttonStyle(OutlineButtonStyle(fullWidth: true))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .sugarBackground()
        .confirmationDialog("Kick this member?", isPresented: $confirmKick, titleVisibility: .visible) {
            Button("Kick", role: .destructive) { Task { await kick() } }
        }
    }

    private func toggle(_ role: ServerRole, on: Bool) async {
        busy = true
        defer { busy = false }
        let current = store.member(email)
        var roles = current?.roles ?? []
        if on { roles.append(role.id) } else { roles.removeAll { $0 == role.id } }
        do {
            if let current, !current.id.isEmpty {
                try await FS.update("ServerMember", current.id, ["roles": roles, "updated_date": FS.nowISO()])
            } else {
                let person = model.person(email)
                _ = try await FS.create("ServerMember", ["community_id": store.server.id, "user_email": email, "user_display_name": person?.displayName ?? "", "user_profile_picture": person?.picture ?? "", "roles": roles, "nickname": ""])
            }
            await store.load()
            await store.syncPermIndex()
            model.showToast(on ? "Gave \(role.name)" : "Removed \(role.name)", icon: "tag.fill")
        } catch {
            model.showToast("Couldn't change roles", error: true)
        }
    }

    private func kick() async {
        do {
            try await FS.update("Community", store.server.id, ["member_emails": store.server.members.filter { $0 != email }, "updated_date": FS.nowISO()])
            if let row = store.member(email), !row.id.isEmpty { try? await FS.delete("ServerMember", row.id) }
            await store.load()
            model.showToast("Kicked from the server", icon: "person.fill.xmark")
            dismiss()
        } catch {
            model.showToast("Couldn't kick — \(error.localizedDescription)", error: true)
        }
    }
}
