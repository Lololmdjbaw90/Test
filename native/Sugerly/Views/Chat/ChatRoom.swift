import SwiftUI
import AVKit
import UIKit
import PhotosUI
import AVFoundation

// MARK: - One conversation (WhatsApp-style)

// Doodle wallpaper, bubbles with little tails, time and read ticks inside
// the bubble, day pills, swipe right to reply, voice notes, GIFs, photos,
// shared reels and call buttons in the header.
struct ChatView: View {
    let conversation: Conversation
    var loadMessages = true
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var chats
    @Environment(CallCenter.self) private var calls
    @Environment(VoiceEngine.self) private var voice
    @Environment(\.dismiss) private var dismissChat
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var validating = false
    @State private var gifs = false
    @State private var loaded = false
    @State private var reporting: ReportSheet.Target?
    @State private var failed: String?
    @State private var replyTo: Message?
    @State private var confirmDelete: Message?
    @State private var recorder = VoiceNoteRecorder()
    @State private var studio = false
    @State private var uploading: String?
    @State private var hasOlder = false
    @State private var loadingOlder = false
    @FocusState private var typing: Bool

    private var me: String { model.me?.email ?? "" }
    private var members: [String] { conversation.members.isEmpty ? [me] : conversation.members }
    private var other: UserProfile? { conversation.others(me).first.flatMap { model.person($0) } }
    private var otherEmail: String { conversation.others(me).first ?? "" }
    private var dmState: DMRules.State { DMRules.state(conversation, model: model, chats: chats, messages: messages) }
    private var canCall: Bool { DMRules.canCall(conversation, model: model) }
    private var streak: ChatStreaks.Streak? { conversation.isGroup ? nil : ChatStreaks.shared.streak(conversation.id) }

    private func startCall() {
        guard canCall else { model.showToast(DMRules.friendsOnly, icon: "person.2.fill", error: true); return }
        Task { await calls.start(conversation, model: model) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Scrolling up to the top loads the next older page.
                    if loaded && hasOlder {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Theme.main)
                            Text("Loading earlier messages").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .onAppear { Task { await loadOlder(proxy) } }
                    }
                    if loaded && messages.isEmpty { emptyState }
                    ForEach(Array(messages.enumerated()), id: \.element.key) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if previous == nil || !sameDay(previous!, message) {
                            DayPill(date: Dates.parse(message.created) ?? Date()).padding(.vertical, 8)
                        }
                        row(message, previous: previous)
                            .id(message.key)
                            .transition(Self.arrival(mine: message.authorEmail == me))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                // On iPad the conversation stays a readable width.
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.key) { _, key in
                guard let key else { return }
                // After the new bubble is laid out, so the scroll lands once.
                DispatchQueue.main.async {
                    proxy.scrollTo(key, anchor: .bottom)
                }
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .modifier(StreakWatch(conversation: conversation, messages: messages, me: me, enabled: loadMessages))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if voice.room?.isCall == true { calls.showScreen = true } else { startCall() }
                } label: { Image(systemName: "phone.fill").opacity(canCall ? 1 : 0.35) }
                .accessibilityLabel(conversation.isGroup ? "Group call" : "Voice call")
                Menu {
                    Button(role: .destructive) {
                        chats.close(conversation.id)
                        dismissChat()
                    } label: { Label(conversation.isGroup ? "Hide chat" : "Close DM", systemImage: "xmark.circle") }
                    if !conversation.isGroup && !otherEmail.isEmpty {
                        Button {
                            reporting = ReportSheet.Target(id: otherEmail, type: "user", ownerEmail: otherEmail, preview: model.name(otherEmail, otherEmail), link: "/Profile?email=\(otherEmail)")
                        } label: { Label("Report", systemImage: "flag") }
                        let ignoring = model.me?.ignored.contains(otherEmail) ?? false
                        Button { Task { await Privacy.setIgnored(otherEmail, !ignoring, model: model) } } label: {
                            Label(ignoring ? "Stop ignoring" : "Ignore", systemImage: ignoring ? "bell.fill" : "bell.slash.fill")
                        }
                        let blocked = model.me?.blocked.contains(otherEmail) ?? false
                        Button(role: .destructive) { Task { await Privacy.setBlocked(otherEmail, !blocked, model: model) } } label: {
                            Label(blocked ? "Unblock" : "Block", systemImage: "hand.raised.fill")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
        .sheet(isPresented: $gifs) { GifPickerSheet { url in Task { if await TextGuard.clear([], kind: .message, model: model) { await sendMedia(url) } } } }
        .fullScreenCover(isPresented: $studio) {
            ReelStudioView(chatName: conversation.title(model)) { media in
                Task { await sendStudio(media) }
            }
        }
        .confirmationDialog("Delete this message?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible, presenting: confirmDelete) { message in
            Button("Delete for everyone", role: .destructive) { delete(message) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("This can't be undone.") }
        .onAppear {
            Alerts.shared.openConversation = conversation.id
        }
        .onDisappear {
            typing = false
            if Alerts.shared.openConversation == conversation.id { Alerts.shared.openConversation = nil }
            recorder.cancel()
        }
        .task {
            guard loadMessages else { loaded = true; return }
            restoreCache()
            await poll()
        }
    }

    // MARK: header

    private var header: some View {
        NavigationLink(value: conversation.isGroup ? nil : conversation.others(me).first.map { Route.person($0) }) {
            HStack(spacing: 10) {
                Avatar(url: conversation.picture(model), name: conversation.title(model), size: 36, nitro: other?.isNitro ?? false, presence: other?.presenceNow)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(conversation.title(model)).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        if let streak { StreakBadge(streak: streak, size: 11) }
                    }
                    Text(status).font(.jakarta(11, .semibold)).foregroundStyle(other?.isOnline == true ? Palette.success : Palette.muted).lineLimit(1)
                }
            }
        }
        .buttonStyle(SoftPressStyle())
    }

    private var status: String {
        if conversation.isGroup {
            let names = conversation.members.filter { $0 != me }.prefix(4).map { model.person($0)?.displayName.split(separator: " ").first.map(String.init) ?? String($0.split(separator: "@").first ?? "") }
            return (["You"] + names).joined(separator: ", ")
        }
        guard let other else { return "tap for profile" }
        if !other.activeStatus.isEmpty && other.isOnline { return other.activeStatus }
        if other.isOnline { return other.presenceNow == .online ? "online" : other.presenceNow.label.lowercased() }
        if other.presence == "invisible" { return "offline" }
        guard let seen = Dates.parse(other.lastSeen) else { return "tap for profile" }
        let time = seen.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(seen) { return "last seen today at \(time)" }
        if Calendar.current.isDateInYesterday(seen) { return "last seen yesterday at \(time)" }
        return "last seen \(seen.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Avatar(url: conversation.picture(model), name: conversation.title(model), size: 80)
            Text(conversation.title(model)).font(.display(24)).foregroundStyle(Palette.text)
            Label("Messages here are just between you\(conversation.isGroup ? " all" : " two")", systemImage: "lock.fill")
                .font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Palette.surface2, in: Capsule())
            Label("Say hi", systemImage: "hand.wave.fill").font(.jakarta(15)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // A new message springs up out of its own side, from a little smaller,
    // like it was just sent (or just arrived).
    static func arrival(mine: Bool) -> AnyTransition {
        guard !Motion.reduced else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.6, anchor: mine ? .bottomTrailing : .bottomLeading)
                .combined(with: .offset(y: 14))
                .combined(with: .opacity),
            removal: .opacity.animation(Motion.exit))
    }

    // How a message arrives: a quick spring with a little bounce.
    static var arrive: Animation {
        Motion.pick(.spring(response: 0.38, dampingFraction: 0.72))
    }

    // MARK: rows

    @ViewBuilder
    private func row(_ message: Message, previous: Message?) -> some View {
        if message.kind == "call" {
            CallMessageRow(message: message, me: me) { startCall() }
                .padding(.vertical, 6)
        } else {
            let mine = message.authorEmail == me
            let first = previous == nil || previous?.authorEmail != message.authorEmail || previous?.kind == "call" || gap(previous!, message) || !sameDay(previous!, message)
            SwipeToReply(onReply: { withMotion(Motion.standard) { replyTo = message }; typing = true }) {
                ChatBubble(message: message, mine: mine, tail: first,
                           showName: conversation.isGroup && !mine && first,
                           read: mine && message.readBy.contains { $0 != me },
                           me: me,
                           onReact: { react(message, $0) },
                           onQuote: { scrollTarget in _ = scrollTarget },
                           menuItems: { AnyView(menu(message)) })
            }
            .padding(.top, first ? 6 : 0)
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
        Button { withMotion(Motion.standard) { replyTo = message }; typing = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        if !message.displayText.isEmpty {
            Button { UIPasteboard.general.string = message.displayText; model.showToast("Copied", icon: "doc.on.doc.fill") } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        if message.authorEmail == me {
            Button(role: .destructive) { confirmDelete = message } label: { Label("Delete message", systemImage: "trash") }
        } else {
            Button { reporting = ReportSheet.Target(id: message.id, type: "message", ownerEmail: message.authorEmail, preview: message.text, link: "/DirectMessages", collection: "DirectMessage", media: [message.imageURL, message.audioURL, message.videoURL].first(where: { !$0.isEmpty }) ?? "") } label: { Label("Report", systemImage: "flag") }
        }
    }

    // MARK: composer

    // Composer, or a request / blocked card when you can't chat (yet).
    @ViewBuilder
    private var bottomBar: some View {
        switch dmState {
        case .open, .new:
            composer
        case .requestSent:
            gateCard(icon: "paperplane.fill", title: "Message request sent", text: "You can keep chatting once \(conversation.title(model)) accepts.") { EmptyView() }
        case .requestReceived:
            gateCard(icon: "envelope.open.fill", title: "\(conversation.title(model)) wants to message you", text: "Accept to chat. They won't know if you decline.") {
                HStack(spacing: 8) {
                    Button { Task { await Privacy.accept(otherEmail, model: model) } } label: { Text("Accept").frame(maxWidth: .infinity) }
                        .buttonStyle(GradientButtonStyle(height: 42))
                    Button {
                        chats.close(conversation.id)
                        dismissChat()
                    } label: { Text("Decline").frame(maxWidth: .infinity) }
                        .buttonStyle(OutlineButtonStyle(height: 42, fullWidth: true))
                    Button { Task { await Privacy.setBlocked(otherEmail, true, model: model); dismissChat() } } label: {
                        Image(systemName: "hand.raised.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.danger)
                            .frame(width: 42, height: 42).background(Palette.danger.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(BouncyStyle())
                    .accessibilityLabel("Block")
                }
            }
        case .blocked:
            gateCard(icon: "hand.raised.fill", title: "You blocked \(conversation.title(model))", text: "Unblock them to chat again.") {
                Button { Task { await Privacy.setBlocked(otherEmail, false, model: model) } } label: { Text("Unblock").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle(height: 42, fullWidth: true))
            }
        case .blockedMe:
            gateCard(icon: "lock.fill", title: "You can't message \(conversation.title(model))", text: "They aren't taking messages from you.") { EmptyView() }
        }
    }

    private func gateCard<Actions: View>(icon: String, title: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.main)
                    .frame(width: 38, height: 38).background(Theme.soft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.jakarta(15, .semibold)).foregroundStyle(Palette.text).lineLimit(2)
                    Text(text).font(.jakarta(12, .medium)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            actions()
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background {
            Palette.bg.opacity(0.96)
                .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if dmState == .new {
                Label("Your first message is a request. \(conversation.title(model)) can accept it to chat.", systemImage: "envelope.fill")
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let uploading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Theme.main)
                    Text(uploading).font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2)
                }
                .transition(.opacity)
            }
            if let failed { Text(failed).font(.jakarta(12, .semibold)).foregroundStyle(Palette.danger) }
            if let replyTo { replyBar(replyTo).transition(.move(edge: .bottom).combined(with: .opacity)) }
            if recorder.recording {
                recordingBar.transition(.opacity)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        TextField("Message", text: $draft, axis: .vertical)
                            .accessibilityIdentifier("chat-message-input")
                            .font(.jakarta(16))
                            .lineLimit(1...6)
                            .focused($typing)
                            .padding(.vertical, 8)
                            .padding(.leading, 10)
                        Button { gifs = true } label: {
                            Text("GIF").font(.jakarta(11, .bold)).foregroundStyle(Palette.muted)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.muted, lineWidth: 1.3))
                                .frame(width: 34, height: 36)
                        }
                        .accessibilityLabel("GIFs and stickers")
                        if draft.isEmpty {
                            Button { studio = true } label: {
                                Image(systemName: "camera").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.muted)
                                    .frame(width: 34, height: 36)
                            }
                            .accessibilityLabel("Send a photo or video")
                            .transition(.pop)
                        }
                    }
                    .padding(.horizontal, 6)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(typing ? Theme.main.opacity(0.45) : Palette.border, lineWidth: 1))
                    .motion(Motion.fade, value: typing)

                    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        if hasText { Task { await send() } }
                        else if canCall { Task { await startRecording() } }
                        else { model.showToast(DMRules.friendsOnly, icon: "person.2.fill", error: true) }
                    } label: {
                        Image(systemName: hasText ? "arrow.up" : "mic.fill")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Theme.main, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                            .motion(Motion.playful, value: hasText)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.88))
                    .accessibilityLabel(hasText ? "Send" : "Record a voice message")
                    .disabled(validating)
                    .sensoryFeedback(.impact(weight: .medium), trigger: messages.count)
                }
            }
        }
        .motion(Motion.standard, value: draft.isEmpty)
        .motion(Motion.standard, value: replyTo?.id)
        .motion(Motion.standard, value: recorder.recording)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
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
                Text(message.authorEmail == me ? "You" : model.name(message.authorEmail, message.authorName)).font(.jakarta(13, .semibold)).foregroundStyle(Theme.main)
                Text(ChatBubble.preview(message)).font(.jakarta(13)).foregroundStyle(Palette.text2).lineLimit(1)
            }
            Spacer()
            Button { withMotion(Motion.standard) { replyTo = nil } } label: {
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
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Theme.main, in: Circle())
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

    @State private var lastDeletionCheck = Date.distantPast

    private func poll() async {
        while !Task.isCancelled {
            if chats.wasRemoved(conversation.id) { messages = []; dismissChat(); return }
            await load()
            let slow = FS.missingIndex.contains("DirectMessage")
            try? await Task.sleep(for: .seconds(slow ? 4 : 2))
        }
    }

    // Open instantly from what's saved on the phone, then only ask for newer.
    private func restoreCache() {
        guard messages.isEmpty else { return }
        let cached = ChatCache.messages(conversation.id)
        guard !cached.isEmpty else { return }
        messages = cached
        hasOlder = true
        loaded = true
    }

    private func load() async {
        guard !me.isEmpty else { return }
        var filters: [FS.Filter] = [.equals("conversation_id", conversation.id), .contains("member_emails", me)]
        let newest = messages.last(where: { !$0.pending })?.created ?? ""
        let incremental = loaded && !newest.isEmpty
        if incremental { filters.append(.after("created_date", ChatStore.minus(newest, seconds: 60))) }
        let page = incremental ? 100 : 200
        guard let docs = try? await FS.query("DirectMessage", filters, orderBy: "created_date", limit: page) else {
            loaded = true
            return
        }
        if Date().timeIntervalSince(lastDeletionCheck) > 30 {
            let checked = Array(messages.filter { !$0.pending }.suffix(50))
            if let current = try? await FS.getMany("DirectMessage", checked.map(\.id)) {
                let gone = Set(checked.filter { current[$0.id] == nil }.map(\.id))
                messages.removeAll { gone.contains($0.id) }
                for id in gone { chats.removedMessage(id, in: conversation.id, remaining: messages) }
                if !gone.isEmpty { ChatCache.save(conversation.id, messages) }
                lastDeletionCheck = Date()
            }
        }
        let incoming = docs.map(Message.init)
        let known = Set(messages.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }.sorted { $0.created < $1.created }
        if incremental && docs.count >= page {
            // A lot happened while you were away: start from the newest page
            // (older ones load as you scroll up).
            let pending = messages.filter(\.pending)
            let keys = Dictionary(messages.filter { !$0.localKey.isEmpty }.map { ($0.id, $0.localKey) }, uniquingKeysWith: { a, _ in a })
            let kept = incoming.map { m -> Message in
                var m = m
                if let key = keys[m.id] { m.localKey = key }
                return m
            }
            messages = (kept + pending).sorted { $0.created < $1.created }
            hasOlder = true
            ChatCache.save(conversation.id, messages)
        } else if !fresh.isEmpty || !loaded {
            if !loaded { hasOlder = docs.count >= page }
            withAnimation(loaded ? Self.arrive : nil) {
                messages = (messages + fresh).sorted { $0.created < $1.created }
            }
            ChatCache.save(conversation.id, messages)
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

    // The page before the oldest message on screen, keeping your place.
    private func loadOlder(_ proxy: ScrollViewProxy) async {
        guard !loadingOlder, let oldest = messages.first(where: { !$0.pending }) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        let filters: [FS.Filter] = [.equals("conversation_id", conversation.id), .contains("member_emails", me), .before("created_date", oldest.created)]
        guard let docs = try? await FS.query("DirectMessage", filters, orderBy: "created_date", limit: 100) else { return }
        hasOlder = docs.count >= 100
        let known = Set(messages.map(\.id))
        let page = docs.map(Message.init).filter { !known.contains($0.id) }
        guard !page.isEmpty else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { messages = (page + messages).sorted { $0.created < $1.created } }
        DispatchQueue.main.async { proxy.scrollTo(oldest.key, anchor: .top) }
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
        messages.append(pending)
        replyTo = nil
        do {
            let doc = try await FS.create("DirectMessage", data)
            var created = Message(doc)
            created.localKey = pending.id
            // Swap in the saved copy quietly: same bubble, no second pop-in.
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                if messages.contains(where: { $0.id == created.id }) {
                    // A refresh already brought it in: drop the sending copy.
                    messages.removeAll { $0.id == pending.id }
                } else if let i = messages.firstIndex(where: { $0.id == pending.id }) {
                    messages[i] = created
                }
            }
            chats.upsert(created, me: me)
        } catch {
            withMotion { messages.removeAll { $0.id == pending.id } }
            failed = "Couldn't send — \(error.localizedDescription)"
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validating, !text.isEmpty, let data = payload(text: text, imageURL: "") else { return }
        let original = draft
        validating = true
        let allowed = await TextGuard.clear([text], kind: .message, model: model)
        validating = false
        guard allowed else { return }
        if draft == original { draft = "" }
        TapSound.play(.send)
        await post(data)
    }

    // Photos and videos made in the in-app camera + editor.
    private func sendStudio(_ media: ChatMedia) async {
        failed = nil
        guard await TextGuard.clear([], kind: .message, model: model) else { return }
        switch media {
        case .photos(let images):
            for (i, image) in images.enumerated() {
                withMotion { uploading = images.count > 1 ? "Sending photo \(i + 1) of \(images.count)…" : "Sending photo…" }
                guard let jpeg = ImageTools.jpeg(image, maxSide: 1600) else { continue }
                do {
                    let url = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
                    await sendMedia(url)
                } catch {
                    failed = "Couldn't send the photo — \(error.localizedDescription)"
                }
            }
        case .video(let file, let cover):
            withMotion { uploading = "Sending video…" }
            do {
                let data = try Data(contentsOf: file)
                guard data.count < 58 * 1024 * 1024 else { throw APIError(message: "That video is too big — trim it a little shorter.") }
                let link = try await StorageClient.upload(data, contentType: "video/mp4", fileExtension: "mp4")
                var coverURL = ""
                if let cover, let jpeg = ImageTools.jpeg(cover, maxSide: 900) {
                    coverURL = (try? await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")) ?? ""
                }
                if let doc = payload(text: "", imageURL: coverURL, extra: ["video_url": link]) { await post(doc) }
            } catch {
                failed = "Couldn't send the video — \(error.localizedDescription)"
            }
        }
        withMotion { uploading = nil }
    }

    private func sendMedia(_ url: String) async {
        guard let data = payload(text: "", imageURL: url) else { return }
        guard await TextGuard.clear([], kind: .message, model: model, cooldown: false) else { return }
        await post(data)
    }

    private func startRecording() async {
        if voice.room != nil { model.showToast("You can't record during a call", icon: "mic.slash.fill", error: true); return }
        if !(await recorder.start()) { model.showToast("Microphone access is off — turn it on in Settings", icon: "mic.slash.fill", error: true) }
    }

    private func sendVoiceNote() async {
        guard let result = recorder.stop() else { return }
        guard await TextGuard.clear([], kind: .message, model: model) else { return }
        let (url, seconds) = result
        guard seconds >= 0.8, let data = try? Data(contentsOf: url) else { return }
        do {
            let link = try await StorageClient.upload(data, contentType: "audio/mp4", fileExtension: "m4a")
            VoiceNoteCache.store(url, for: link)
            guard let doc = payload(text: "Voice message", imageURL: "", extra: ["audio_url": link, "audio_duration": (seconds * 10).rounded() / 10]) else { return }
            await post(doc)
        } catch {
            failed = "Couldn't send the voice message — \(error.localizedDescription)"
        }
    }

    private func delete(_ message: Message) {
        Task {
            do {
                try await FS.delete("DirectMessage", message.id)
                withMotion { messages.removeAll { $0.id == message.id } }
                ChatCache.save(conversation.id, messages)
                chats.removedMessage(message.id, in: conversation.id, remaining: messages)
            } catch {
                model.showToast("Couldn't delete the message. Please try again.", error: true)
            }
        }
    }
}

// MARK: - Pieces

// A video in a chat: its cover with a play button; tap to watch full screen.
struct ChatVideoThumb: View {
    let cover: String
    let video: String
    @State private var watching = false

    var body: some View {
        Button { watching = true } label: {
            ZStack {
                if cover.isEmpty {
                    LinearGradient(colors: [Theme.light, Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    RemoteImage(url: cover)
                }
                Color.black.opacity(0.18)
                Image(systemName: "play.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 54, height: 54).background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            }
            .frame(width: 210, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
        .accessibilityLabel("Play video")
        .fullScreenCover(isPresented: $watching) { ChatVideoPlayer(url: video) }
    }
}

struct ChatVideoPlayer: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.black.opacity(0.45), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .onAppear {
            guard player == nil, let link = URL(string: url) else { return }
            if !VoiceEngine.live { try? AVAudioSession.sharedInstance().setCategory(.playback) }
            let p = AVPlayer(url: link)
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

struct DayPill: View {
    let date: Date
    var body: some View {
        Text(label).font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
            .padding(.horizontal, 10).padding(.vertical, 4)
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

// A soft rounded bubble; the first in a run gets a tighter corner on the
// sender's side so a group of bubbles reads as one thought.
struct BubbleShape: Shape {
    var mine: Bool
    var tail: Bool

    func path(in r: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: tail && !mine ? 6 : 18, bottomLeadingRadius: 18,
                               bottomTrailingRadius: 18, topTrailingRadius: tail && mine ? 6 : 18, style: .continuous).path(in: r)
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
    // Long-press menu. Only the bubble itself lifts (in its own shape), not
    // the whole width of the chat.
    var menuItems: (() -> AnyView)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    static func preview(_ m: Message) -> String {
        if !m.audioURL.isEmpty { return "Voice message" }
        if !m.videoURL.isEmpty { return "Video" }
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
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .modifier(BubbleMenu(items: menuItems))
                } else {
                    content
                        .padding(4)
                        .background { bubbleFill }
                        .contentShape(.contextMenuPreview, BubbleShape(mine: mine, tail: tail))
                        .modifier(BubbleMenu(items: menuItems))
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
            // Yours: the palette's blush (your own pastel with another accent).
            shape.fill(Palette.blush)
                .overlay(shape.fill(Theme.main.opacity(scheme == .dark ? 0.16 : 0.04)))
        } else {
            shape.fill(Palette.surface)
                .overlay(shape.stroke(Palette.border, lineWidth: 1))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showName {
                Text(model.name(message.authorEmail, message.authorName)).font(.jakarta(13, .semibold)).foregroundStyle(Self.nameColor(message.authorEmail))
                    .padding(.horizontal, 8).padding(.top, 2)
            }
            if !message.replyPreview.isEmpty {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.main).frame(width: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.replyName.isEmpty ? "Reply" : message.replyName).font(.jakarta(12, .semibold)).foregroundStyle(Theme.main)
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
            if !message.videoURL.isEmpty {
                ChatVideoThumb(cover: message.imageURL, video: message.videoURL)
            } else if !message.imageURL.isEmpty {
                MessageMedia(url: message.imageURL, width: 230)
            }
            if !message.audioURL.isEmpty {
                VoiceNoteBubble(id: message.id, url: message.audioURL, seconds: message.audioSeconds, mine: mine)
                    .overlay(alignment: .bottomTrailing) { meta.padding(.trailing, 6).padding(.bottom, 2) }
            } else if !message.displayText.isEmpty {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(message.displayText)
                        .font(.jakarta(15.5))
                        .foregroundStyle(Palette.text)
                        .padding(.leading, 8).padding(.top, 4).padding(.bottom, 6)
                        .modifier(IncomingFilterCover(text: message.displayText, mine: mine))
                    meta.fixedSize().padding(.trailing, 7)
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
                        if people.count > 1 { Text("\(people.count)").font(.jakarta(11, .semibold)).foregroundStyle(mineToo ? Theme.main : Palette.text2).contentTransition(.numericText()) }
                    }
                    .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 7).frame(height: 24)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(mineToo ? Theme.main.opacity(0.5) : Palette.border, lineWidth: 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.85))
                .transition(.pop)
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

// The long-press menu on a message bubble, when it has one.
private struct BubbleMenu: ViewModifier {
    let items: (() -> AnyView)?

    func body(content: Content) -> some View {
        if let items {
            content.contextMenu { items() }
        } else {
            content
        }
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
                .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 12).frame(height: 30)
                .background(Theme.soft, in: Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                NavigationLink(value: Route.reel(loaded)) { card }.buttonStyle(SoftPressStyle())
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
        // In a call the microphone is already set up for talking; keep it.
        if !VoiceEngine.live {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try? session.setActive(true)
        }
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
        if !VoiceEngine.live { try? AVAudioSession.sharedInstance().setCategory(.playback) }
    }
}

// Voice notes are small, so each one is downloaded once (as soon as its
// bubble shows up) and then plays straight from the phone: no waiting for a
// stream to buffer.
enum VoiceNoteCache {
    private static var folder: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(for url: String) -> URL {
        var hash: UInt64 = 1469598103934665603
        for byte in url.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return folder.appendingPathComponent(String(hash, radix: 36) + ".m4a")
    }

    static func local(_ url: String) -> URL? {
        let f = file(for: url)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    // Your own just-recorded note is already on the phone.
    static func store(_ local: URL, for url: String) {
        try? FileManager.default.copyItem(at: local, to: file(for: url))
    }

    // Keep the cache small: only the most recent notes stay on the phone.
    nonisolated(unsafe) private static var pruned = false
    private static func pruneOnce() {
        guard !pruned else { return }
        pruned = true
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        guard files.count > 300 else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(300) { try? fm.removeItem(at: file) }
    }

    @discardableResult
    static func fetch(_ url: String) async -> URL? {
        pruneOnce()
        if let hit = local(url) { return hit }
        guard let link = URL(string: url), let (temp, response) = try? await URLSession.shared.download(from: link),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        let target = file(for: url)
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.moveItem(at: temp, to: target) } catch { return nil }
        return target
    }
}

// Plays one voice note at a time.
@MainActor
@Observable
final class VoiceNotePlayer {
    static let shared = VoiceNotePlayer()
    var playingId: String?
    var loadingId: String?
    var progress: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var finisher = Finisher()
    @ObservationIgnored private var request = 0

    private final class Finisher: NSObject, AVAudioPlayerDelegate {
        var done: () -> Void = {}
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            DispatchQueue.main.async { self.done() }
        }
    }

    func toggle(_ id: String, url: String) {
        if playingId == id || loadingId == id {
            stop()
            return
        }
        stop()
        request += 1
        let mine = request
        if let file = VoiceNoteCache.local(url) {
            start(id, file)
            return
        }
        loadingId = id
        Task {
            let file = await VoiceNoteCache.fetch(url)
            guard mine == request else { return }
            loadingId = nil
            if let file { start(id, file) }
        }
    }

    private func start(_ id: String, _ file: URL) {
        let session = AVAudioSession.sharedInstance()
        // Don't touch the audio setup during a call.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .spokenAudio)
        }
        try? session.setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: file) else { return }
        finisher.done = { [weak self] in self?.stop() }
        p.delegate = finisher
        p.prepareToPlay()
        guard p.play() else { return }
        player = p
        playingId = id
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = min(1, p.currentTime / p.duration)
            }
        }
    }

    func stop() {
        request += 1
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playingId = nil
        loadingId = nil
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
                ZStack {
                    if notes.loadingId == id {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 38, height: 38).background(Theme.main, in: Circle())
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
        // Download it now so play starts instantly.
        .task(id: url) { await VoiceNoteCache.fetch(url) }
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
