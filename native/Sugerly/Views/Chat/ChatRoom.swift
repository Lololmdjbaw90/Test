import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

// MARK: - One conversation (WhatsApp-style)

// Doodle wallpaper, bubbles with little tails, time and read ticks inside
// the bubble, day pills, swipe right to reply, voice notes, GIFs, photos,
// shared reels and call buttons in the header.
struct ChatView: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var chats
    @Environment(CallCenter.self) private var calls
    @Environment(VoiceEngine.self) private var voice
    @Environment(\.dismiss) private var dismissChat
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var photo: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var gifs = false
    @State private var loaded = false
    @State private var reporting: ReportSheet.Target?
    @State private var failed: String?
    @State private var replyTo: Message?
    @State private var recorder = VoiceNoteRecorder()
    @FocusState private var typing: Bool

    private var me: String { model.me?.email ?? "" }
    private var members: [String] { conversation.members.isEmpty ? [me] : conversation.members }
    private var other: UserProfile? { conversation.others(me).first.flatMap { model.person($0) } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if loaded && messages.isEmpty { emptyState }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if previous == nil || !sameDay(previous!, message) {
                            DayPill(date: Dates.parse(message.created) ?? Date()).padding(.vertical, 8)
                        }
                        row(message, previous: previous)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .background(ChatWallpaper().ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if voice.room?.isCall == true { calls.showScreen = true } else { Task { await calls.start(conversation, model: model) } }
                } label: { Image(systemName: "phone.fill") }
                .accessibilityLabel(conversation.isGroup ? "Group call" : "Voice call")
                Menu {
                    Button(role: .destructive) {
                        chats.close(conversation.id)
                        dismissChat()
                    } label: { Label(conversation.isGroup ? "Hide chat" : "Close DM", systemImage: "xmark.circle") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $gifs) { GifPickerSheet { url in Task { await sendMedia(url) } } }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onAppear {
            chats.reopen(conversation.id)
            Alerts.shared.openConversation = conversation.id
        }
        .onDisappear {
            if Alerts.shared.openConversation == conversation.id { Alerts.shared.openConversation = nil }
            recorder.cancel()
        }
        .task { await poll() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
    }

    // MARK: header

    private var header: some View {
        NavigationLink(value: conversation.isGroup ? nil : conversation.others(me).first.map { Route.person($0) }) {
            HStack(spacing: 10) {
                Avatar(url: conversation.picture(model), name: conversation.title(model), size: 36, online: other?.isOnline ?? false, nitro: other?.isNitro ?? false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(conversation.title(model)).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(status).font(.jakarta(11, .semibold)).foregroundStyle(other?.isOnline == true ? Palette.success : Palette.muted).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var status: String {
        if conversation.isGroup {
            let names = conversation.members.filter { $0 != me }.prefix(4).map { model.person($0)?.displayName.split(separator: " ").first.map(String.init) ?? String($0.split(separator: "@").first ?? "") }
            return (["You"] + names).joined(separator: ", ")
        }
        guard let other else { return "tap for profile" }
        if other.isOnline { return "online" }
        guard let seen = Dates.parse(other.lastSeen) else { return "tap for profile" }
        let time = seen.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(seen) { return "last seen today at \(time)" }
        if Calendar.current.isDateInYesterday(seen) { return "last seen yesterday at \(time)" }
        return "last seen \(seen.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Avatar(url: conversation.picture(model), name: conversation.title(model), size: 88)
                .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 3))
                .shadow(color: Theme.pink.opacity(0.3), radius: 14, y: 6)
            Text(conversation.title(model)).font(.display(28)).foregroundStyle(Palette.text)
            Label("Messages here are just between you\(conversation.isGroup ? " all" : " two")", systemImage: "lock.fill")
                .font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(hex: 0xFFF3C4).opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Label("Say hi", systemImage: "hand.wave.fill").font(.jakarta(15)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: rows

    @ViewBuilder
    private func row(_ message: Message, previous: Message?) -> some View {
        if message.kind == "call" {
            CallMessageRow(message: message, me: me) { Task { await calls.start(conversation, model: model) } }
                .padding(.vertical, 6)
        } else {
            let mine = message.authorEmail == me
            let first = previous == nil || previous?.authorEmail != message.authorEmail || previous?.kind == "call" || gap(previous!, message) || !sameDay(previous!, message)
            SwipeToReply(onReply: { withAnimation(.snappy) { replyTo = message }; typing = true }) {
                ChatBubble(message: message, mine: mine, tail: first,
                           showName: conversation.isGroup && !mine && first,
                           read: mine && message.readBy.contains { $0 != me },
                           me: me,
                           onReact: { react(message, $0) },
                           onQuote: { scrollTarget in _ = scrollTarget })
            }
            .padding(.top, first ? 6 : 0)
            .contextMenu { menu(message) }
        }
    }

    @ViewBuilder
    private func menu(_ message: Message) -> some View {
        ControlGroup {
            ForEach(["❤️", "😂", "😮", "😢", "👍"], id: \.self) { e in
                Button(e) { react(message, e) }
            }
        }
        .controlGroupStyle(.compactMenu)
        Button { withAnimation(.snappy) { replyTo = message }; typing = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        if !message.displayText.isEmpty {
            Button { UIPasteboard.general.string = message.displayText; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        if message.authorEmail == me {
            Button(role: .destructive) { delete(message) } label: { Label("Delete", systemImage: "trash") }
        } else {
            Button { reporting = ReportSheet.Target(id: message.id, type: "message", ownerEmail: message.authorEmail, preview: message.text, link: "/DirectMessages") } label: { Label("Report", systemImage: "flag") }
        }
    }

    // MARK: composer

    private var composer: some View {
        VStack(spacing: 6) {
            if let failed { Text(failed).font(.jakarta(12, .semibold)).foregroundStyle(Palette.danger) }
            if let replyTo { replyBar(replyTo).transition(.move(edge: .bottom).combined(with: .opacity)) }
            if recorder.recording {
                recordingBar.transition(.opacity)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Menu {
                            Button { pickingPhoto = true } label: { Label("Photo", systemImage: "photo.on.rectangle") }
                            Button { gifs = true } label: { Label("GIFs & stickers", systemImage: "photo.stack") }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.text2)
                                .frame(width: 36, height: 36)
                        }
                        TextField("Message", text: $draft, axis: .vertical)
                            .font(.jakarta(16))
                            .lineLimit(1...6)
                            .focused($typing)
                            .padding(.vertical, 8)
                        Button { gifs = true } label: {
                            Text("GIF").font(.jakarta(11, .heavy)).foregroundStyle(Palette.text2)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.text2, lineWidth: 1.4))
                                .frame(width: 34, height: 36)
                        }
                        .accessibilityLabel("GIFs and stickers")
                        if draft.isEmpty {
                            Button { pickingPhoto = true } label: {
                                Image(systemName: "camera.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text2)
                                    .frame(width: 34, height: 36)
                            }
                            .accessibilityLabel("Send a photo")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 6)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))

                    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        if hasText { Task { await send() } } else { Task { await startRecording() } }
                    } label: {
                        Image(systemName: hasText ? "paperplane.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Theme.gradient, in: Circle())
                            .shadow(color: Theme.main.opacity(0.35), radius: 8, y: 3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.88))
                    .accessibilityLabel(hasText ? "Send" : "Record a voice message")
                    .sensoryFeedback(.impact(weight: .medium), trigger: messages.count)
                }
            }
        }
        .animation(.snappy, value: draft.isEmpty)
        .animation(.snappy, value: replyTo?.id)
        .animation(.snappy, value: recorder.recording)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            Palette.bg.opacity(0.96)
                .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func replyBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.main).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.authorEmail == me ? "You" : message.authorName).font(.jakarta(13, .heavy)).foregroundStyle(Theme.main)
                Text(ChatBubble.preview(message)).font(.jakarta(13)).foregroundStyle(Palette.text2).lineLimit(1)
            }
            Spacer()
            Button { withAnimation(.snappy) { replyTo = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30).background(Palette.surface2, in: Circle())
            }
        }
        .frame(height: 46)
        .padding(.horizontal, 10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.danger)
                    .frame(width: 44, height: 44).background(Palette.surface, in: Circle())
            }
            .accessibilityLabel("Delete recording")
            HStack(spacing: 8) {
                Circle().fill(Palette.danger).frame(width: 10, height: 10)
                    .opacity(Int(recorder.seconds * 2) % 2 == 0 ? 1 : 0.3)
                Text(VoiceNoteRecorder.clock(recorder.seconds)).font(.jakarta(15, .bold)).monospacedDigit().foregroundStyle(Palette.text)
                LevelBars(level: recorder.level)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.surface, in: Capsule())
            Button { Task { await sendVoiceNote() } } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Theme.gradient, in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .accessibilityLabel("Send voice message")
        }
    }

    // MARK: data

    private func gap(_ a: Message, _ b: Message) -> Bool {
        guard let x = Dates.parse(a.created), let y = Dates.parse(b.created) else { return false }
        return y.timeIntervalSince(x) > 5 * 60
    }

    private func sameDay(_ a: Message, _ b: Message) -> Bool {
        guard let x = Dates.parse(a.created), let y = Dates.parse(b.created) else { return true }
        return Calendar.current.isDate(x, inSameDayAs: y)
    }

    private func react(_ message: Message, _ emoji: String) {
        guard !message.pending, let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        var reactions = messages[i].reactions
        var people = reactions[emoji] ?? []
        if people.contains(me) { people.removeAll { $0 == me } } else { people.append(me) }
        reactions[emoji] = people.isEmpty ? nil : people
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { messages[i].reactions = reactions }
        let payload: [String: Any] = reactions.mapValues { $0 as Any }
        Task { try? await FS.update("DirectMessage", message.id, ["reactions": payload, "updated_date": FS.nowISO()]) }
    }

    private func poll() async {
        while !Task.isCancelled {
            await load()
            let slow = FS.missingIndex.contains("DirectMessage")
            try? await Task.sleep(for: .seconds(slow ? 4 : 2))
        }
    }

    private func load() async {
        guard !me.isEmpty else { return }
        var filters: [FS.Filter] = [.equals("conversation_id", conversation.id), .contains("member_emails", me)]
        let newest = messages.last(where: { !$0.pending })?.created ?? ""
        if loaded, !newest.isEmpty { filters.append(.after("created_date", ChatStore.minus(newest, seconds: 60))) }
        guard let docs = try? await FS.query("DirectMessage", filters, orderBy: "created_date", limit: loaded ? 100 : 200) else {
            loaded = true
            return
        }
        let incoming = docs.map(Message.init)
        let known = Set(messages.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }.sorted { $0.created < $1.created }
        if !fresh.isEmpty || !loaded {
            withAnimation(loaded ? .snappy : nil) {
                messages = (messages + fresh).sorted { $0.created < $1.created }
            }
        }
        // Read ticks turn blue when the other side reads.
        for m in incoming where known.contains(m.id) {
            if let i = messages.firstIndex(where: { $0.id == m.id }), messages[i].readBy != m.readBy || messages[i].reactions != m.reactions {
                messages[i].readBy = m.readBy
                messages[i].reactions = m.reactions
            }
        }
        loaded = true
        markRead(messages)
    }

    private func markRead(_ list: [Message]) {
        let unread = list.filter { $0.authorEmail != me && !$0.readBy.contains(me) && !$0.pending }
        guard !unread.isEmpty else { return }
        chats.markRead(conversation.id)
        for m in unread.suffix(30) {
            if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i].readBy.append(me) }
            Task { try? await FS.update("DirectMessage", m.id, ["read_by": m.readBy + [me], "updated_date": FS.nowISO()]) }
        }
    }

    private func payload(text: String, imageURL: String, extra: Doc = [:]) -> Doc? {
        guard let meProfile = model.me else { return nil }
        let now = FS.nowISO()
        var doc: Doc = [
            "conversation_id": conversation.id,
            "conversation_type": conversation.isGroup ? "group" : "dm",
            "group_name": conversation.isGroup ? conversation.groupName : "",
            "content": text, "image_url": imageURL,
            "user_email": meProfile.email, "user_display_name": meProfile.displayName,
            "user_profile_picture": meProfile.picture,
            "member_emails": members, "read_by": [meProfile.email],
            "reactions": [String: Any](), "is_edited": false,
            "created_by": meProfile.email, "created_date": now, "updated_date": now,
        ]
        if let replyTo {
            doc["reply_to_id"] = replyTo.id
            doc["reply_to_name"] = replyTo.authorEmail == me ? meProfile.displayName : replyTo.authorName
            doc["reply_to_preview"] = String(ChatBubble.preview(replyTo).prefix(90))
        }
        for (k, v) in extra { doc[k] = v }
        return doc
    }

    private func post(_ data: Doc) async {
        failed = nil
        var pending = Message(data)
        pending.id = "pending-\(UUID().uuidString)"
        pending.pending = true
        withAnimation(.snappy) { messages.append(pending); replyTo = nil }
        do {
            let doc = try await FS.create("DirectMessage", data)
            let created = Message(doc)
            if let i = messages.firstIndex(where: { $0.id == pending.id }) { messages[i] = created }
            chats.upsert(created, me: me)
        } catch {
            withAnimation { messages.removeAll { $0.id == pending.id } }
            failed = "Couldn't send — \(error.localizedDescription)"
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = payload(text: text, imageURL: "") else { return }
        draft = ""
        await post(data)
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let jpeg = ImageTools.jpeg(image, maxSide: 1600) else { return }
        do {
            let url = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            await sendMedia(url)
        } catch {
            failed = "Couldn't send the photo — \(error.localizedDescription)"
        }
    }

    private func sendMedia(_ url: String) async {
        guard let data = payload(text: "", imageURL: url) else { return }
        await post(data)
    }

    private func startRecording() async {
        if voice.room != nil { model.showToast("You can't record during a call", icon: "mic.slash.fill", error: true); return }
        if !(await recorder.start()) { model.showToast("Microphone access is off — turn it on in Settings", icon: "mic.slash.fill", error: true) }
    }

    private func sendVoiceNote() async {
        guard let result = recorder.stop() else { return }
        let (url, seconds) = result
        guard seconds >= 0.8, let data = try? Data(contentsOf: url) else { return }
        do {
            let link = try await StorageClient.upload(data, contentType: "audio/mp4", fileExtension: "m4a")
            guard let doc = payload(text: "Voice message", imageURL: "", extra: ["audio_url": link, "audio_duration": (seconds * 10).rounded() / 10]) else { return }
            await post(doc)
        } catch {
            failed = "Couldn't send the voice message — \(error.localizedDescription)"
        }
    }

    private func delete(_ message: Message) {
        withAnimation { messages.removeAll { $0.id == message.id } }
        Task { try? await FS.delete("DirectMessage", message.id) }
    }
}

// MARK: - Pieces

struct DayPill: View {
    let date: Date
    var body: some View {
        Text(label).font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Palette.surface, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
    }
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}

// The bubble shape with WhatsApp's little tail at the top corner.
struct BubbleShape: Shape {
    var mine: Bool
    var tail: Bool

    func path(in r: CGRect) -> Path {
        var p = UnevenRoundedRectangle(topLeadingRadius: tail && !mine ? 4 : 16, bottomLeadingRadius: 16,
                                       bottomTrailingRadius: 16, topTrailingRadius: tail && mine ? 4 : 16, style: .continuous).path(in: r)
        guard tail else { return p }
        if mine {
            p.move(to: CGPoint(x: r.maxX - 6, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX + 7, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 12), control: CGPoint(x: r.maxX + 1, y: r.minY + 2))
        } else {
            p.move(to: CGPoint(x: r.minX + 6, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX - 7, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + 12), control: CGPoint(x: r.minX - 1, y: r.minY + 2))
        }
        p.closeSubpath()
        return p
    }
}

struct ChatBubble: View {
    let message: Message
    let mine: Bool
    let tail: Bool
    let showName: Bool
    let read: Bool
    var me = ""
    var onReact: (String) -> Void = { _ in }
    var onQuote: (String) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    static func preview(_ m: Message) -> String {
        if !m.audioURL.isEmpty { return "Voice message" }
        if m.sharedReel != nil { return "Reel" }
        if !m.displayText.isEmpty { return m.displayText }
        if !m.imageURL.isEmpty { return Media.label(m.imageURL).replacingOccurrences(of: "Sent a ", with: "").capitalized }
        return "Message"
    }

    private var isSticker: Bool { Media.isSticker(message.imageURL) && message.displayText.isEmpty }
    private var time: String { Dates.parse(message.created).map { $0.formatted(date: .omitted, time: .shortened) } ?? "" }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            HStack {
                if mine { Spacer(minLength: 54) }
                if isSticker {
                    VStack(alignment: .trailing, spacing: 2) {
                        MessageMedia(url: message.imageURL)
                        meta.padding(.horizontal, 8).padding(.vertical, 3).background(Palette.surface.opacity(0.9), in: Capsule())
                    }
                } else {
                    content
                        .padding(4)
                        .background { bubbleFill }
                        .opacity(message.pending ? 0.7 : 1)
                }
                if !mine { Spacer(minLength: 54) }
            }
            if !message.reactions.isEmpty { reactions }
        }
    }

    @ViewBuilder
    private var bubbleFill: some View {
        let shape = BubbleShape(mine: mine, tail: tail)
        if mine {
            shape.fill(Palette.surface)
                .overlay(shape.fill(Theme.light.opacity(scheme == .dark ? 0.3 : 0.4)))
                .shadow(color: .black.opacity(0.07), radius: 1, y: 1)
        } else {
            shape.fill(Palette.surface).shadow(color: .black.opacity(0.07), radius: 1, y: 1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showName {
                Text(message.authorName).font(.jakarta(13, .heavy)).foregroundStyle(Self.nameColor(message.authorEmail))
                    .padding(.horizontal, 8).padding(.top, 2)
            }
            if !message.replyPreview.isEmpty {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.main).frame(width: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.replyName.isEmpty ? "Reply" : message.replyName).font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                        Text(message.replyPreview).font(.jakarta(12)).foregroundStyle(Palette.text2).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(Palette.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(minWidth: 160)
            }
            if let reel = message.sharedReel {
                SharedReelCard(reel: reel)
            }
            if !message.imageURL.isEmpty {
                MessageMedia(url: message.imageURL, width: 230)
            }
            if !message.audioURL.isEmpty {
                VoiceNoteBubble(id: message.id, url: message.audioURL, seconds: message.audioSeconds, mine: mine)
                    .overlay(alignment: .bottomTrailing) { meta.padding(.trailing, 6).padding(.bottom, 2) }
            } else if !message.displayText.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    (Text(message.displayText) + Text(verbatim: mine ? "\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}" : "\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}"))
                        .font(.jakarta(15.5))
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 6)
                        .textSelection(.enabled)
                    meta.padding(.trailing, 7).padding(.bottom, 4)
                }
            } else {
                HStack { Spacer(minLength: 0); meta }.padding(.horizontal, 6).padding(.bottom, 3)
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var meta: some View {
        HStack(spacing: 3) {
            if message.edited { Text("edited").font(.jakarta(10)).foregroundStyle(Palette.muted) }
            Text(time).font(.jakarta(10.5, .medium)).foregroundStyle(Palette.muted)
            if mine { Ticks(pending: message.pending, read: read) }
        }
    }

    private var reactions: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions.keys.sorted(), id: \.self) { emoji in
                let people = message.reactions[emoji] ?? []
                let mineToo = people.contains(me)
                Button { onReact(emoji) } label: {
                    HStack(spacing: 3) {
                        Text(emoji).font(.system(size: 13))
                        if people.count > 1 { Text("\(people.count)").font(.jakarta(11, .heavy)).foregroundStyle(mineToo ? Theme.main : Palette.text2) }
                    }
                    .padding(.horizontal, 7).frame(height: 24)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(mineToo ? Theme.main.opacity(0.5) : Palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                }
                .buttonStyle(BouncyStyle(scale: 0.85))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .offset(y: -4)
    }

    // Each person in a group gets their own name colour.
    static func nameColor(_ email: String) -> Color {
        let palette: [UInt32] = [0xD9577F, 0x7C5CF0, 0x16A37F, 0xEE6E40, 0x2F80E0, 0xB8438A, 0x0E9AA7, 0xC77D10]
        let sum = email.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }
}

// Clock (sending), grey double tick (sent) or blue double tick (read).
struct Ticks: View {
    let pending: Bool
    let read: Bool
    var body: some View {
        if pending {
            Image(systemName: "clock").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
        } else {
            ZStack(alignment: .leading) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark").offset(x: 4.5)
            }
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(read ? Color(hex: 0x34B7F1) : Palette.muted)
            .frame(width: 16, alignment: .leading)
            .animation(.easeOut(duration: 0.25), value: read)
        }
    }
}

// Drag a message right to reply to it.
struct SwipeToReply<Content: View>: View {
    var onReply: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var dx: CGFloat = 0
    @State private var armed = false

    var body: some View {
        content()
            .offset(x: dx)
            .background(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.main)
                    .frame(width: 32, height: 32).background(Palette.surface, in: Circle())
                    .scaleEffect(armed ? 1.1 : max(0.3, dx / 60))
                    .opacity(dx > 8 ? 1 : 0)
                    .padding(.leading, 4)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.4, v.translation.width > 0 else { return }
                        dx = min(80, v.translation.width * 0.7)
                        let now = dx > 55
                        if now != armed { armed = now }
                    }
                    .onEnded { _ in
                        if armed { onReply() }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dx = 0 }
                        armed = false
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
    }
}

// A call summary line in the chat, with "call back".
struct CallMessageRow: View {
    let message: Message
    let me: String
    var onCallBack: () -> Void

    private var mine: Bool { message.authorEmail == me }
    private var missed: Bool { message.callOutcome == "missed" || message.callOutcome == "declined" }

    private var title: String {
        switch message.callOutcome {
        case "missed": return mine ? "Voice call · No answer" : "Missed voice call"
        case "declined": return mine ? "Voice call · Declined" : "Declined voice call"
        default:
            let s = Int(message.callDuration / 1000)
            return "Voice call · \(s / 60):\(String(format: "%02d", s % 60))"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: missed ? "phone.arrow.down.left.fill" : (mine ? "phone.arrow.up.right.fill" : "phone.arrow.down.left.fill"))
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(missed ? Palette.danger : Palette.success, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                Text(Dates.parse(message.created).map { $0.formatted(date: .omitted, time: .shortened) } ?? "").font(.jakarta(11)).foregroundStyle(Palette.muted)
            }
            Button("Call back", action: onCallBack)
                .font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Theme.soft, in: Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .frame(maxWidth: .infinity)
    }
}

// A reel someone sent: its cover, who made it and the caption. Tap to watch.
struct SharedReelCard: View {
    let reel: Message.SharedReel
    @State private var loaded: Reel?

    var body: some View {
        Group {
            if let loaded {
                NavigationLink(value: Route.reel(loaded)) { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
        .task(id: reel.id) {
            if loaded == nil, let doc = try? await FS.get("Reel", reel.id) { loaded = Reel(doc) }
        }
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: reel.cover)
                .frame(width: 170, height: 240)
                .background(Palette.surface2)
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Label("Reel", systemImage: "play.rectangle.fill").font(.jakarta(11, .heavy)).foregroundStyle(.white)
                if !reel.by.isEmpty { Text("@\(reel.by)").font(.jakarta(13, .heavy)).foregroundStyle(.white).lineLimit(1) }
                if !reel.caption.isEmpty { Text(reel.caption).font(.jakarta(11)).foregroundStyle(.white.opacity(0.9)).lineLimit(2) }
            }
            .padding(10)
            Image(systemName: "play.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 170, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Chat wallpaper

// WhatsApp-like doodles: little hearts, stars, notes and brushes, very faint.
struct ChatWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    private static let symbols = ["heart", "star", "music.note", "paintbrush.pointed", "sparkle", "cloud", "moon", "camera", "leaf", "gift", "cup.and.saucer", "pawprint"]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scheme == .dark ? Color(hex: 0x120910) : Color(hex: 0xFFF1F6)))
            let gap: CGFloat = 64
            var row = 0
            var y: CGFloat = 10
            while y < size.height + gap {
                var x: CGFloat = row % 2 == 0 ? 12 : 12 + gap / 2
                var col = 0
                while x < size.width + gap {
                    let index = (row * 7 + col * 3) % Self.symbols.count
                    if let symbol = context.resolveSymbol(id: index) {
                        var c = context
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .degrees(Double((row * 37 + col * 53) % 50) - 25))
                        c.draw(symbol, at: .zero)
                    }
                    x += gap
                    col += 1
                }
                y += gap * 0.8
                row += 1
            }
        } symbols: {
            ForEach(Self.symbols.indices, id: \.self) { i in
                Image(systemName: Self.symbols[i])
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle((scheme == .dark ? Theme.light : Theme.main).opacity(scheme == .dark ? 0.09 : 0.1))
                    .tag(i)
            }
        }
        .drawingGroup()
    }
}

// MARK: - Voice notes

@MainActor
@Observable
final class VoiceNoteRecorder: NSObject {
    var recording = false
    var seconds: Double = 0
    var level: Double = 0
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meter: Task<Void, Never>?

    static func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        r.isMeteringEnabled = true
        guard r.record() else { return false }
        recorder = r
        seconds = 0
        recording = true
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let r = self.recorder, r.isRecording else { return }
                r.updateMeters()
                let db = Double(r.averagePower(forChannel: 0))
                self.level = max(0, min(1, (db + 50) / 50))
                self.seconds = r.currentTime
                if r.currentTime > 180 { _ = self.stop() }
            }
        }
        return true
    }

    func stop() -> (URL, Double)? {
        guard let r = recorder else { return nil }
        let length = r.currentTime
        r.stop()
        finish()
        return (r.url, length)
    }

    func cancel() {
        guard let r = recorder else { return }
        r.stop()
        r.deleteRecording()
        finish()
    }

    private func finish() {
        meter?.cancel()
        recorder = nil
        recording = false
        level = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }
}

// Plays one voice note at a time.
@MainActor
@Observable
final class VoiceNotePlayer {
    static let shared = VoiceNotePlayer()
    var playingId: String?
    var progress: Double = 0
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observer: Any?

    func toggle(_ id: String, url: String) {
        if playingId == id {
            stop()
            return
        }
        stop()
        guard let link = URL(string: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let p = AVPlayer(url: link)
        player = p
        playingId = id
        progress = 0
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = self.player?.currentItem else { return }
                let total = item.duration.seconds
                if total.isFinite, total > 0 {
                    self.progress = min(1, time.seconds / total)
                    if time.seconds >= total - 0.05 { self.stop() }
                }
            }
        }
        p.play()
    }

    func stop() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        playingId = nil
        progress = 0
    }
}

struct VoiceNoteBubble: View {
    let id: String
    let url: String
    let seconds: Double
    let mine: Bool
    private var notes = VoiceNotePlayer.shared

    init(id: String, url: String, seconds: Double, mine: Bool) {
        self.id = id
        self.url = url
        self.seconds = seconds
        self.mine = mine
    }

    private var playing: Bool { notes.playingId == id }

    var body: some View {
        HStack(spacing: 10) {
            Button { notes.toggle(id, url: url) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.gradient, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            VStack(alignment: .leading, spacing: 4) {
                waveform
                Text(VoiceNoteRecorder.clock(seconds)).font(.jakarta(11, .semibold)).monospacedDigit().foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .padding(.trailing, 40)
        .frame(width: 250, alignment: .leading)
    }

    private var waveform: some View {
        let bars = 26
        let seed = id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return HStack(spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                let h = 5 + CGFloat((seed >> (i % 12)) & 0xF) * 1.3 + CGFloat(abs(sin(Double(i) * 0.7))) * 6
                Capsule()
                    .fill(Double(i) / Double(bars) <= (playing ? notes.progress : 0) ? Theme.main : Palette.muted.opacity(0.45))
                    .frame(width: 3, height: h)
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.05), value: notes.progress)
    }
}

struct LevelBars: View {
    let level: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<14, id: \.self) { i in
                let wave = abs(sin(Double(i) * 0.9 + level * 6))
                Capsule().fill(Theme.main.opacity(0.8))
                    .frame(width: 3, height: 4 + CGFloat(level * 18 * (0.4 + wave * 0.6)))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}
