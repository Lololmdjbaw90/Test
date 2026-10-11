import SwiftUI
import SceneKit

// Playing in Sugar World: the 3D world fills the screen, the stick (left)
// walks, the button (right) jumps, dragging anywhere else turns the camera
// and pinching zooms. Chat bubbles float over heads; tap someone to see who
// they are.
struct WorldPlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var net = WorldNet()
    @State private var game: WorldGame?
    @State private var joining = true
    @State private var chatting = false
    @State private var draft = ""
    @State private var lines: [Line] = []
    @State private var showPlayers = false
    @State private var picked: WorldNet.Player?
    @State private var dressing = false
    @State private var starBurst = false
    @State private var reporting: ReportSheet.Target?
    @FocusState private var typing: Bool

    struct Line: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var text: String
        var system = false
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFFE3F0).ignoresSafeArea()
            if let game {
                GameSurface(game: game).ignoresSafeArea()
            }
            if !joining { hud.transition(.opacity) }
            if starBurst { starBanner.transition(.scale(scale: 0.7).combined(with: .opacity)) }
            if joining { loading.transition(.opacity) }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .onDisappear {
            game?.stop()
            let net = net
            Task { await net.leave() }
        }
        .sheet(isPresented: $showPlayers) { playersSheet.presentationDetents([.medium, .large]).presentationCornerRadius(30) }
        .sheet(item: $picked) { player in playerCard(player).presentationDetents([.height(330)]).presentationCornerRadius(30) }
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
        made.onTapPlayer = { id in picked = net.players[id] }
        made.onChatLine = { id, text in
            let name = net.players[id]?.name ?? "Someone"
            // Their phone checked it already; a quick local check too.
            let clean = ModEngine.analyze(text, kind: .message).blocked ? "•••" : text
            add(Line(name: name, text: clean))
        }
        game = made
        made.start()
        let began = Date()
        await net.join(me: me, look: look)
        let waited = Date().timeIntervalSince(began)
        if waited < 0.9 { try? await Task.sleep(for: .seconds(0.9 - waited)) }
        withAnimation(.easeOut(duration: 0.45)) { joining = false }
        if let problem = net.problem { add(Line(name: "", text: problem, system: true)) }
        else { add(Line(name: "", text: "Welcome to Sugar World, room \(net.roomNumber)! Climb the tower for today's star.", system: true)) }
    }

    private func add(_ line: Line) {
        withMotion(.spring(response: 0.35, dampingFraction: 0.85)) {
            lines.append(line)
            if lines.count > 5 { lines.removeFirst(lines.count - 5) }
        }
        let id = line.id
        Task {
            try? await Task.sleep(for: .seconds(12))
            withAnimation(.easeOut(duration: 0.4)) { lines.removeAll { $0.id == id } }
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
        guard !text.isEmpty else { chatting = false; return }
        guard await TextGuard.clear([text], kind: .message, model: model) else {
            // The reason is a toast, hidden behind this screen: show it here.
            let reason = model.toast.flatMap { $0.error ? $0.text : nil } ?? "That message can't be sent."
            model.toast = nil
            add(Line(name: "", text: reason, system: true))
            return
        }
        net.chat(text)
        game?.say(text, from: nil)
        add(Line(name: model.me?.displayName ?? "You", text: text))
        draft = ""
        typing = false
        chatting = false
    }

    // MARK: on screen

    private var hud: some View {
        VStack(spacing: 0) {
            topBar
            chatLog
            Spacer(minLength: 0)
            if chatting { chatBar } else { controls }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            roundButton("xmark", label: "Leave") { dismiss() }
            HStack(spacing: 7) {
                Circle().fill(net.online ? Color(hex: 0x37D67A) : Palette.muted).frame(width: 8, height: 8)
                Text("Sugar World").font(.jakarta(14, .heavy))
                Text("·").foregroundStyle(.secondary)
                Text(net.online ? "Room \(net.roomNumber) · \(net.count) here" : "Solo").font(.jakarta(13, .semibold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Color(hex: 0x3A2440))
            .padding(.horizontal, 14).frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            Spacer(minLength: 0)
            roundButton("person.2.fill", label: "Players") { showPlayers = true }
            roundButton("tshirt.fill", label: "Change outfit") { dressing = true }
        }
    }

    private var chatLog: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(lines) { line in
                Group {
                    if line.system {
                        Text(line.text).font(.jakarta(12.5, .semibold)).foregroundStyle(Color(hex: 0x6B4A5C))
                    } else {
                        (Text(line.name + "  ").font(.jakarta(12.5, .heavy)).foregroundColor(Color(hex: 0xD9577F))
                            + Text(line.text).font(.jakarta(12.5, .medium)).foregroundColor(Color(hex: 0x2A1620)))
                    }
                }
                .lineLimit(3)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(alignment: .bottom) {
            Joystick { v in game?.stick = v }
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                roundButton("bubble.left.fill", label: "Chat", size: 50) {
                    withMotion(.spring(response: 0.3, dampingFraction: 0.85)) { chatting = true }
                    typing = true
                }
                JumpButton { game?.jump() }
            }
        }
    }

    private var chatBar: some View {
        HStack(spacing: 8) {
            TextField("Say something nice…", text: $draft)
                .font(.jakarta(16))
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }
                .padding(.horizontal, 16).frame(height: 48)
                .background(.white, in: Capsule())
                .onChange(of: draft) { _, v in if v.count > 140 { draft = String(v.prefix(140)) } }
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.gradient, in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.9))
            .accessibilityLabel("Send")
            Button { typing = false; withMotion { chatting = false } } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x6B4A5C))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close chat")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func roundButton(_ icon: String, label: String, size: CGFloat = 42, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(Color(hex: 0x3A2440))
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private var loading: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xBFE3FF), Color(hex: 0xFFE3F0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                AvatarStage(look: model.me?.avatar ?? .starter, spin: true)
                    .frame(width: 200, height: 240)
                Text("Sugar World").font(.display(40)).foregroundStyle(Theme.main)
                HStack(spacing: 10) {
                    SugarLoader(size: 12)
                    Text("Finding your friends…").font(.jakarta(15, .semibold)).foregroundStyle(Color(hex: 0x6B4A5C))
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

    // MARK: sheets

    private var playersSheet: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    playerRow(name: me.displayName + " (you)", picture: me.picture, connected: true)
                }
                ForEach(net.players.values.sorted { $0.name < $1.name }) { p in
                    Button { showPlayers = false; picked = p } label: {
                        playerRow(name: p.name, picture: p.picture, connected: p.connected)
                    }
                }
                if net.players.isEmpty {
                    Text(net.online ? "No one else here yet. Invite a friend to play together!" : "You're playing solo right now.")
                        .font(.jakarta(14)).foregroundStyle(Palette.muted)
                }
            }
            .roundTitle("In this room")
        }
    }

    private func playerRow(name: String, picture: String, connected: Bool) -> some View {
        HStack(spacing: 12) {
            Avatar2D(url: picture, name: name)
            Text(name).font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
            Spacer()
            Circle().fill(connected ? Color(hex: 0x37D67A) : Palette.border).frame(width: 9, height: 9)
        }
    }

    private func playerCard(_ p: WorldNet.Player) -> some View {
        VStack(spacing: 14) {
            AvatarStage(look: p.look, spin: true).frame(height: 150)
            Text(p.name).font(.display(26)).foregroundStyle(Palette.text)
            HStack(spacing: 10) {
                Button {
                    let target = ReportSheet.Target(id: p.email, type: "user", ownerEmail: p.email, preview: p.name,
                                                    link: "/Profile?email=\(p.email)", collection: "User")
                    picked = nil
                    Task { try? await Task.sleep(for: .milliseconds(400)); reporting = target }
                } label: { Label("Report", systemImage: "flag.fill") }
                    .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
                Button(role: .destructive) {
                    let email = p.email
                    picked = nil
                    net.hide(email)
                    Task { await Privacy.setBlocked(email, true, model: model) }
                } label: { Label("Block", systemImage: "hand.raised.fill") }
                    .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
            }
        }
        .padding(22)
    }
}

// The small round picture used in the player list.
private struct Avatar2D: View {
    let url: String
    let name: String
    var body: some View { Avatar(url: url, name: name, size: 36) }
}

// The SceneKit view the game draws into.
private struct GameSurface: UIViewRepresentable {
    let game: WorldGame
    func makeUIView(context: Context) -> SCNView { game.view }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// Drag the pink knob to walk; it springs back when you let go.
struct Joystick: View {
    var onChange: (SIMD2<Float>) -> Void
    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 56
    private let area: CGFloat = 170

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.65), lineWidth: 2))
                .frame(width: radius * 2 + 20, height: radius * 2 + 20)
            Circle().fill(Theme.gradient)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2.5))
                .frame(width: 56, height: 56)
                .shadow(color: Theme.main.opacity(0.35), radius: 8, y: 3)
                .offset(knob)
        }
        .frame(width: area, height: area)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let dx = v.location.x - area / 2
                    let dy = v.location.y - area / 2
                    let length = max(0.001, sqrt(dx * dx + dy * dy))
                    let k = min(1, radius / length)
                    knob = CGSize(width: dx * k, height: dy * k)
                    onChange(SIMD2<Float>(Float(knob.width / radius), Float(-knob.height / radius)))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { knob = .zero }
                    onChange(SIMD2<Float>(0, 0))
                }
        )
        .accessibilityLabel("Walk")
    }
}

struct JumpButton: View {
    var onJump: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(Theme.gradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
            .shadow(color: Theme.main.opacity(0.4), radius: 10, y: 4)
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
