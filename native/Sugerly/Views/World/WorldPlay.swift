import SwiftUI
import SceneKit

// Playing in Sugar World, sideways: touch anywhere on the left to walk (the
// stick appears under your thumb), the big button jumps, the hand opens
// emotes, and dragging on the right turns the camera (pinch to zoom). Chat
// sits top left, the menu and players top right.
struct WorldPlayView: View {
    var room: String? = nil        // a friend's room to join
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var net = WorldNet()
    @State private var game: WorldGame?
    @State private var joining = true
    @State private var chatOpen = false
    @State private var draft = ""
    @State private var lines: [Line] = []
    @State private var unread = 0
    @State private var menuOpen = false
    @State private var playersOpen = false
    @State private var emotesOpen = false
    @State private var picked: WorldNet.Player?
    @State private var dressing = false
    @State private var starBurst = false
    @State private var reporting: ReportSheet.Target?
    @State private var notices: [Notice] = []
    @State private var fadeTick = 0
    @FocusState private var typing: Bool

    struct Line: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var text: String
        var system = false
        var at = Date()
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var picture: String
        var text: String
    }

    private let ink = Color(hex: 0x3A2440)

    var body: some View {
        ZStack {
            Color(hex: 0xFFE3F0).ignoresSafeArea()
            if let game {
                GameSurface(game: game).ignoresSafeArea()
            }
            if !joining {
                GeometryReader { geo in
                    StickZone { v in game?.stick = v }
                        .frame(width: geo.size.width * 0.45, height: geo.size.height * 0.72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .ignoresSafeArea(.keyboard)
                hud
                    .ignoresSafeArea(.keyboard)
                    .transition(.opacity)
                if chatOpen { chatInput.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if playersOpen { playersPanel.transition(.move(edge: .trailing).combined(with: .opacity)) }
            if let picked { playerCard(picked).transition(.scale(scale: 0.92).combined(with: .opacity)) }
            if menuOpen { pauseMenu.transition(.opacity) }
            if starBurst { starBanner.transition(.scale(scale: 0.7).combined(with: .opacity)) }
            if joining { loading.transition(.opacity) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: playersOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: picked)
        .animation(.easeOut(duration: 0.25), value: menuOpen)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { OrientationLock.set(landscape: true) }
        .task { await start() }
        .onDisappear {
            OrientationLock.set(landscape: false)
            game?.stop()
            let net = net
            Task { await net.leave() }
        }
        .sheet(isPresented: $dressing) {
            AvatarEditorView { look in game?.wear(look) }
                .presentationCornerRadius(30)
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
    }

    // MARK: starting

    private func start() async {
        guard game == nil, let me = model.me else { return }
        let look = me.avatar
        let made = WorldGame(net: net, look: look)
        made.onStar = { rewardStar() }
        made.onBounce = { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        made.onTapPlayer = { id in withMotion { playersOpen = false; picked = net.players[id] } }
        made.onChatLine = { id, text in
            let name = net.players[id]?.name ?? "Someone"
            // Their phone checked it already; a quick local check too.
            let clean = ModEngine.analyze(text, kind: .message).blocked ? "•••" : text
            add(Line(name: name, text: clean))
        }
        made.onJoined = { player in
            let friend = model.me?.following.contains(player.email) == true
            notice(Notice(name: player.name, picture: player.picture, text: friend ? "Your friend \(player.name) joined" : "\(player.name) joined"))
        }
        game = made
        made.start()
        let began = Date()
        await net.join(me: me, look: look, prefer: room)
        let waited = Date().timeIntervalSince(began)
        if waited < 1.0 { try? await Task.sleep(for: .seconds(1.0 - waited)) }
        withAnimation(.easeOut(duration: 0.45)) { joining = false }
        if let problem = net.problem {
            add(Line(name: "", text: problem, system: true))
        } else {
            add(Line(name: "", text: "Welcome to room \(net.roomNumber)! Climb the candy tower for today's star.", system: true))
        }
    }

    private func add(_ line: Line) {
        lines.append(line)
        if lines.count > 50 { lines.removeFirst(lines.count - 50) }
        if !chatOpen && !line.system { unread += 1 }
        // Closed chat: lines fade away after a while.
        Task {
            try? await Task.sleep(for: .seconds(12.2))
            withAnimation(.easeOut(duration: 0.4)) { fadeTick += 1 }
        }
    }

    private func notice(_ n: Notice) {
        withMotion(.spring(response: 0.35, dampingFraction: 0.8)) {
            notices.append(n)
            if notices.count > 3 { notices.removeFirst() }
        }
        let id = n.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.3)) { notices.removeAll { $0.id == id } }
        }
    }

    private func rewardStar() {
        guard !WorldRewards.claimedToday else { return }
        WorldRewards.claim()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        RewardSound.play()
        Task { try? await model.addToMe(["coins": WorldRewards.coins, "xp": 5]) }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { starBurst = true }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.35)) { starBurst = false }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard await TextGuard.clear([text], kind: .message, model: model) else {
            // The reason is a toast, hidden behind this screen: show it here.
            let reason = model.toast.flatMap { $0.error ? $0.text : nil } ?? "That message can't be sent."
            model.toast = nil
            add(Line(name: "", text: reason, system: true))
            return
        }
        draft = ""
        net.chat(text)
        game?.say(text, from: nil)
        add(Line(name: model.me?.displayName ?? "You", text: text))
        typing = true
    }

    private func toggleChat() {
        withMotion(.spring(response: 0.3, dampingFraction: 0.85)) {
            chatOpen.toggle()
            unread = 0
        }
        typing = chatOpen
    }

    // MARK: on screen

    private var hud: some View {
        VStack(spacing: 10) {
            topBar
            HStack(alignment: .top, spacing: 12) {
                chatPanel
                Spacer(minLength: 0)
                noticeStack
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            glassButton("line.3.horizontal", label: "Menu") { withMotion { menuOpen = true; emotesOpen = false } }
            glassButton("bubble.left.and.bubble.right.fill", label: "Chat", on: chatOpen) { toggleChat() }
                .overlay(alignment: .topTrailing) {
                    if unread > 0 && !chatOpen {
                        Text("\(min(unread, 9))\(unread > 9 ? "+" : "")")
                            .font(.jakarta(11, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                            .background(Palette.danger, in: Capsule())
                            .offset(x: 4, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Spacer(minLength: 0)
            roomPill
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                CoinIcon(size: 22)
                Text("\(model.me?.coins ?? 0)").font(.jakarta(15, .heavy)).foregroundStyle(ink)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.65), lineWidth: 1))
            glassButton("person.2.fill", label: "Players", on: playersOpen) {
                withMotion { playersOpen.toggle(); picked = nil }
            }
        }
    }

    private var roomPill: some View {
        HStack(spacing: 8) {
            Circle().fill(net.online ? Color(hex: 0x37D67A) : Palette.muted).frame(width: 8, height: 8)
            Text("Sugar World").font(.jakarta(14, .heavy)).foregroundStyle(ink)
            Text(net.online ? "Room \(net.roomNumber)" : "Solo").font(.jakarta(13, .semibold)).foregroundStyle(ink.opacity(0.7))
            if net.online {
                HStack(spacing: -8) {
                    ForEach(Array(net.players.values.prefix(3))) { p in
                        Avatar(url: p.picture, name: p.name, size: 22)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    }
                }
                Text("\(net.count)").font(.jakarta(13, .heavy)).foregroundStyle(ink)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.65), lineWidth: 1))
    }

    // The chat history, top left. Closed: the last few lines, fading away.
    // Open: everything so far, scrollable, always resting on the newest line.
    @ViewBuilder
    private var chatPanel: some View {
        if chatOpen {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(lines) { line in
                            lineView(line).id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
                .frame(width: 330, height: 118)
                .onAppear { if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: lines.last?.id) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .transition(.opacity)
        } else if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(recent) { line in
                    lineView(line).transition(.opacity)
                }
            }
            .padding(10)
            .frame(width: 330, alignment: .leading)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // Lines still fresh enough to show while the chat is closed.
    private var recent: [Line] {
        _ = fadeTick   // redraws when a line gets old enough to fade
        return Array(lines.filter { Date().timeIntervalSince($0.at) < 12 }.suffix(4))
    }

    // Typing sits just above the keyboard (the history stays at the top).
    private var chatInput: some View {
        HStack(spacing: 8) {
            TextField("Say something nice…", text: $draft)
                .font(.jakarta(15))
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }
                .padding(.horizontal, 16).frame(height: 44)
                .background(.white, in: Capsule())
                .onChange(of: draft) { _, v in if v.count > 140 { draft = String(v.prefix(140)) } }
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.gradient, in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.9))
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
            Button { toggleChat() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close chat")
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func lineView(_ line: Line) -> some View {
        Group {
            if line.system {
                Text(line.text).font(.jakarta(12.5, .semibold)).foregroundStyle(Color(hex: 0xFFE3F0))
            } else {
                (Text(line.name + ": ").font(.jakarta(13, .heavy)).foregroundColor(Color(hex: 0xFFB3CB))
                    + Text(line.text).font(.jakarta(13, .medium)).foregroundColor(.white))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var noticeStack: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(notices) { n in
                HStack(spacing: 8) {
                    Avatar(url: n.picture, name: n.name, size: 24)
                    Text(n.text).font(.jakarta(13, .bold)).foregroundStyle(ink).lineLimit(1)
                }
                .padding(.leading, 6).padding(.trailing, 12).frame(height: 34)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.65), lineWidth: 1))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if emotesOpen {
                HStack(spacing: 10) {
                    ForEach(Avatar3D.Emote.allCases) { e in
                        Button {
                            game?.emote(e)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withMotion { emotesOpen = false }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: e.icon).font(.system(size: 18, weight: .bold))
                                Text(e.label).font(.jakarta(10.5, .heavy))
                            }
                            .foregroundStyle(ink)
                            .frame(width: 58, height: 58)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.65), lineWidth: 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.9))
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 14) {
                glassButton("hand.wave.fill", label: "Emotes", size: 56, on: emotesOpen) {
                    withMotion(.spring(response: 0.3, dampingFraction: 0.8)) { emotesOpen.toggle() }
                }
                JumpButton { game?.jump() }
            }
        }
    }

    private func glassButton(_ icon: String, label: String, size: CGFloat = 44, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(on ? .white : ink)
                .frame(width: size, height: size)
                .background {
                    if on { Circle().fill(Theme.gradient) } else { Circle().fill(.ultraThinMaterial) }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    // MARK: panels

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { withMotion { menuOpen = false } }
            HStack(spacing: 22) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xBFE3FF), Color(hex: 0xFFE3F0)], startPoint: .top, endPoint: .bottom)
                    AvatarStage(look: model.me?.avatar ?? .starter, spin: true)
                }
                .frame(width: 190)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paused").font(.display(30)).foregroundStyle(Palette.text)
                        Text(net.online ? "Room \(net.roomNumber) · \(net.count) playing" : "Playing solo")
                            .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                            .padding(.bottom, 4)
                        menuRow("play.fill", "Resume") { withMotion { menuOpen = false } }
                        menuRow("tshirt.fill", "Change outfit") { menuOpen = false; dressing = true }
                        menuRow("person.2.fill", "Players") { withMotion { menuOpen = false; playersOpen = true } }
                        menuRow("arrow.counterclockwise", "Back to the start") { game?.respawn(); withMotion { menuOpen = false } }
                        menuRow("rectangle.portrait.and.arrow.right", "Leave game", danger: true) { dismiss() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(width: 270)
            }
            .padding(18)
            .frame(maxHeight: 340)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
            .padding(16)
        }
    }

    private func menuRow(_ icon: String, _ title: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(danger ? Palette.danger : Theme.main)
                    .frame(width: 34, height: 34)
                    .background((danger ? Palette.danger : Theme.main).opacity(0.12), in: Circle())
                Text(title).font(.jakarta(15, .bold)).foregroundStyle(danger ? Palette.danger : Palette.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 44)
            .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private var playersPanel: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Players").font(.display(24)).foregroundStyle(Palette.text)
                    Text("\(net.count)").font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
                    Spacer()
                    Button { withMotion { playersOpen = false } } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text2)
                            .frame(width: 32, height: 32)
                            .background(Palette.surface2, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                ScrollView {
                    VStack(spacing: 6) {
                        if let me = model.me {
                            playerRow(name: me.displayName, picture: me.picture, note: "You", connected: true, friend: false)
                        }
                        ForEach(sortedPlayers) { p in
                            Button { withMotion { picked = p } } label: {
                                playerRow(name: p.name, picture: p.picture, note: status(p),
                                          connected: p.connected, friend: isFriend(p.email))
                            }
                            .buttonStyle(BouncyStyle(scale: 0.97))
                        }
                        if net.players.isEmpty {
                            Text(net.online ? "No one else here yet. Tell your friends to tap Join on Sugar World!" : "You're playing solo right now.")
                                .font(.jakarta(13)).foregroundStyle(Palette.muted)
                                .padding(.top, 6)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(16)
            .frame(width: 300)
            .frame(maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 18, x: -4)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
        }
    }

    private func isFriend(_ email: String) -> Bool { model.me?.following.contains(email) == true }

    private func status(_ p: WorldNet.Player) -> String? {
        if p.trouble { return "Can't connect yet, still trying…" }
        if !p.connected { return "Connecting…" }
        return isFriend(p.email) ? "Friend" : nil
    }

    // Friends first, then by name.
    private var sortedPlayers: [WorldNet.Player] {
        net.players.values.sorted { (a: WorldNet.Player, b: WorldNet.Player) -> Bool in
            let fa = isFriend(a.email)
            let fb = isFriend(b.email)
            if fa != fb { return fa }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    private func playerRow(name: String, picture: String, note: String?, connected: Bool, friend: Bool) -> some View {
        HStack(spacing: 10) {
            Avatar(url: picture, name: name, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                if let note {
                    Text(note).font(.jakarta(11.5, .semibold)).foregroundStyle(connected && friend ? Theme.main : Palette.muted)
                }
            }
            Spacer(minLength: 0)
            if friend { Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(Theme.main) }
            Circle().fill(connected ? Color(hex: 0x37D67A) : Palette.border).frame(width: 9, height: 9)
        }
        .padding(8)
        .background(Palette.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func playerCard(_ p: WorldNet.Player) -> some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { withMotion { picked = nil } }
            HStack(spacing: 18) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xBFE3FF), Color(hex: 0xFFE3F0)], startPoint: .top, endPoint: .bottom)
                    AvatarStage(look: p.look, spin: true)
                }
                .frame(width: 160, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 10) {
                    Text(p.name).font(.display(26)).foregroundStyle(Palette.text).lineLimit(1)
                    if isFriend(p.email) {
                        Label("Following", systemImage: "heart.fill").font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                    } else {
                        Button { follow(p) } label: { Label("Follow", systemImage: "person.badge.plus") }
                            .buttonStyle(GradientButtonStyle(height: 42))
                    }
                    HStack(spacing: 8) {
                        Button {
                            let target = ReportSheet.Target(id: p.email, type: "user", ownerEmail: p.email, preview: p.name,
                                                            link: "/Profile?email=\(p.email)", collection: "User")
                            withMotion { picked = nil }
                            reporting = target
                        } label: { Label("Report", systemImage: "flag.fill") }
                            .buttonStyle(OutlineButtonStyle(height: 40, fullWidth: true))
                        Button(role: .destructive) {
                            let email = p.email
                            withMotion { picked = nil }
                            net.hide(email)
                            Task { await Privacy.setBlocked(email, true, model: model) }
                        } label: { Label("Block", systemImage: "hand.raised.fill") }
                            .buttonStyle(OutlineButtonStyle(height: 40, fullWidth: true))
                    }
                }
                .frame(width: 250)
            }
            .padding(18)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 22, y: 8)
        }
    }

    private func follow(_ p: WorldNet.Player) {
        guard let me = model.me, !me.following.contains(p.email) else { return }
        Task {
            try? await model.updateMe(["following": me.following + [p.email]])
            Notify.send(to: p.email, from: me, type: "follow", message: "\(me.displayName) started following you", link: "/Profile?email=\(me.email)")
        }
        notice(Notice(name: p.name, picture: p.picture, text: "Following \(p.name)"))
    }

    private var loading: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xBFE3FF), Color(hex: 0xFFE3F0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HStack(spacing: 30) {
                AvatarStage(look: model.me?.avatar ?? .starter, spin: true)
                    .frame(width: 180, height: 230)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sugar World").font(.display(44)).foregroundStyle(Theme.main)
                    HStack(spacing: 10) {
                        SugarLoader(size: 12)
                        Text(room == nil ? "Finding a room…" : "Joining your friend…")
                            .font(.jakarta(15, .semibold)).foregroundStyle(ink.opacity(0.75))
                    }
                    Text("Tip: turn your phone sideways").font(.jakarta(12.5, .semibold)).foregroundStyle(ink.opacity(0.5))
                }
            }
        }
    }

    private var starBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "star.fill").font(.system(size: 54, weight: .bold)).foregroundStyle(Color(hex: 0xFFC83D))
                .shadow(color: Color(hex: 0xFFB800).opacity(0.6), radius: 16)
            Text("You reached the top!").font(.display(30)).foregroundStyle(.white)
            HStack(spacing: 8) {
                CoinIcon(size: 26)
                Text("+\(WorldRewards.coins)").font(.display(30)).foregroundStyle(.white)
            }
        }
        .padding(28)
        .background(Theme.gradient.opacity(0.92), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .allowsHitTesting(false)
    }
}

// The SceneKit view the game draws into.
private struct GameSurface: UIViewRepresentable {
    let game: WorldGame
    func makeUIView(context: Context) -> SCNView { game.view }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// Touch anywhere in this area to walk: the stick appears under your thumb
// and springs away when you let go (a faint one shows where to start).
struct StickZone: View {
    var onChange: (SIMD2<Float>) -> Void
    @State private var origin: CGPoint?
    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let rest = CGPoint(x: 110, y: geo.size.height - 100)
            let center = origin ?? rest
            ZStack {
                Color.clear.contentShape(Rectangle())
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                    .frame(width: radius * 2 + 22, height: radius * 2 + 22)
                    .position(center)
                    .opacity(origin == nil ? 0.55 : 1)
                Circle().fill(Theme.gradient)
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2.5))
                    .frame(width: 58, height: 58)
                    .shadow(color: Theme.main.opacity(0.35), radius: 8, y: 3)
                    .position(x: center.x + knob.width, y: center.y + knob.height)
                    .opacity(origin == nil ? 0.6 : 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if origin == nil { origin = v.startLocation }
                        let start = origin ?? v.startLocation
                        let dx = v.location.x - start.x
                        let dy = v.location.y - start.y
                        let length = max(0.001, sqrt(dx * dx + dy * dy))
                        let k = min(1, radius / length)
                        knob = CGSize(width: dx * k, height: dy * k)
                        onChange(SIMD2<Float>(Float(knob.width / radius), Float(-knob.height / radius)))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            knob = .zero
                            origin = nil
                        }
                        onChange(SIMD2<Float>(0, 0))
                    }
            )
        }
        .accessibilityLabel("Walk")
    }
}

struct JumpButton: View {
    var onJump: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 32, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .background(Theme.gradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 3))
            .shadow(color: Theme.main.opacity(0.4), radius: 12, y: 4)
            .scaleEffect(pressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onJump()
                    }
                    .onEnded { _ in pressed = false }
            )
            .accessibilityLabel("Jump")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onJump() }
    }
}
