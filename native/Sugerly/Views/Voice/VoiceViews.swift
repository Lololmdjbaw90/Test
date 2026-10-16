import SwiftUI
import WebRTC

// A server voice channel, looking like a call: a dark stage with a tile for
// everyone in it (their camera or screen when they show it, otherwise their
// picture with a green ring that breathes as they talk), and one floating
// bar to mute, deafen, show your camera, share your screen or leave. Before
// you join you see who's inside and a big Join button.
struct VoiceRoomView: View {
    let server: Server
    let channel: ServerChannel
    @Environment(AppModel.self) private var model
    @Environment(VoiceEngine.self) private var voice
    @Environment(\.dismiss) private var dismiss
    @State private var store: ServerStore
    @State private var joining = false

    init(server: Server, channel: ServerChannel) {
        self.server = server
        self.channel = channel
        _store = State(initialValue: ServerStore(server))
    }

    private var here: Bool { voice.room?.id == channel.id }
    private var access: Access { store.access(model.me?.email ?? "", siteAdmin: model.me?.isAdmin ?? false) }
    private var others: [VoicePresenceInfo] { store.voice[channel.id] ?? [] }

    var body: some View {
        ZStack {
            CallBackdrop()
            VStack(spacing: 12) {
                topBar
                ScrollView {
                    VStack(spacing: 14) {
                        if here { liveGrid } else { lobby }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                notices
                controls
            }
            .padding(.bottom, 14)
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .motion(.spring(response: 0.4, dampingFraction: 0.86), value: here)
        .motion(.spring(response: 0.4, dampingFraction: 0.86), value: voice.participants.map(\.id))
        .task {
            await store.load()
            while !Task.isCancelled && !here {
                try? await Task.sleep(for: .seconds(4))
                await store.loadVoice()
            }
        }
    }

    // MARK: top

    private var topBar: some View {
        HStack(spacing: 12) {
            CallTopButton(icon: "chevron.left", label: "Back") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.light)
                        .symbolEffect(.variableColor.iterative, isActive: here && !Motion.reduced)
                    Text(channel.name).font(.display(21)).foregroundStyle(.white).lineLimit(1)
                }
                Text(server.name).font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 6)
            status
            if here { CallAudioButton() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // Connected · 02:14 (with the line quality), or how many are inside.
    @ViewBuilder
    private var status: some View {
        if here, let since = voice.joinedAt {
            HStack(spacing: 6) {
                Circle().fill(Palette.success).frame(width: 7, height: 7)
                TimelineView(.periodic(from: since, by: 1)) { t in
                    Text(Self.clock(t.date.timeIntervalSince(since))).monospacedDigit()
                }
                if let ping = voice.ping {
                    Image(systemName: "cellularbars", variableValue: ping < 180 ? 1 : ping < 400 ? 0.66 : 0.33)
                        .foregroundStyle(ping < 180 ? Palette.success : ping < 400 ? Palette.warning : Palette.danger)
                        .accessibilityLabel(ping < 180 ? "Good connection" : ping < 400 ? "OK connection" : "Poor connection")
                }
            }
            .font(.jakarta(12, .bold)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 30)
            .background(.white.opacity(0.1), in: Capsule())
            .transition(.pop)
        } else if !here {
            Label("\(others.count)", systemImage: "person.2.fill")
                .font(.jakarta(12, .bold)).foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10).frame(height: 30)
                .background(.white.opacity(0.1), in: Capsule())
                .accessibilityLabel("\(others.count) in the channel")
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: people

    // Everyone in the room: one big tile on your own, two stacked, then two
    // columns.
    private var liveGrid: some View {
        let list = voice.participants
        let columns = list.count <= 2 ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let height: CGFloat = list.count <= 1 ? 320 : list.count == 2 ? 220 : 190
        return VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(list) { p in
                    tile(p).frame(height: height).transition(.pop)
                }
            }
            if list.count <= 1 {
                Text("Waiting for others to hop in…")
                    .font(.jakarta(13, .semibold)).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
        }
    }

    private func tile(_ p: VoiceEngine.Participant) -> some View {
        let track: RTCVideoTrack? = p.isSelf ? (voice.cameraOn ? voice.localVideo : nil) : (p.video.isEmpty ? nil : voice.remoteVideo[p.id])
        return CallTile(name: p.isSelf ? "You" : (model.person(p.email)?.displayName ?? p.name),
                        picture: model.person(p.email)?.picture ?? p.picture,
                        muted: p.muted, deafened: p.deafened, speaking: p.speaking, level: p.level,
                        connecting: !p.isSelf && !p.connected, video: track,
                        session: p.isSelf ? voice.cameraSession : nil,
                        mirror: p.isSelf && voice.frontCamera, isScreen: p.video == "screen")
    }

    // Before joining: who's in there.
    @ViewBuilder
    private var lobby: some View {
        if others.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 84, height: 84).background(Theme.gradient, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                Text("Nobody's here yet").font(.display(24)).foregroundStyle(.white)
                Text("Hop in and your friends will see you're waiting.")
                    .font(.jakarta(14)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
            }
            .padding(.top, 50)
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(others) { p in
                    CallTile(name: model.person(p.email)?.displayName ?? p.name,
                             picture: model.person(p.email)?.picture ?? p.picture,
                             muted: p.muted, deafened: p.deafened, isScreen: p.video == "screen", avatarSize: 70)
                        .frame(height: 170)
                }
            }
        }
    }

    // MARK: bottom

    @ViewBuilder
    private var notices: some View {
        if let error = voice.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.jakarta(13, .semibold)).foregroundStyle(Color(hex: 0xFFD166))
                .multilineTextAlignment(.center)
                .padding(12).frame(maxWidth: .infinity)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
        }
        if here && voice.sharingScreen {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.light)
                Text("You're sharing your screen").font(.jakarta(13, .bold)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Button("Stop") { voice.stopScreenShare() }
                    .font(.jakarta(13, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Palette.danger, in: Capsule())
                    .buttonStyle(BouncyStyle(scale: 0.9))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .transition(.slideIn(from: .bottom))
        }
    }

    @ViewBuilder
    private var controls: some View {
        if here {
            CallBar {
                CallButton(icon: voice.muted ? "mic.slash.fill" : "mic.fill", label: voice.muted ? "Unmute" : "Mute", on: voice.muted) { voice.toggleMute() }
                    .disabled(!access.can(.speak))
                CallButton(icon: voice.deafened ? "speaker.slash.fill" : "headphones", label: voice.deafened ? "Undeafen" : "Deafen", on: voice.deafened) { voice.toggleDeafen() }
                CallButton(icon: voice.cameraOn ? "video.fill" : "video.slash.fill", label: "Camera", on: voice.cameraOn) { Task { await voice.toggleCamera() } }
                CallButton(icon: "rectangle.on.rectangle", label: voice.sharingScreen ? "Stop share" : "Share", on: voice.sharingScreen) { voice.toggleScreenShare() }
                CallButton(icon: "phone.down.fill", label: "Leave", danger: true) { Task { await voice.leave() } }
            }
            .transition(.slideIn(from: .bottom))
        } else {
            Button {
                guard let me = model.me else { return }
                joining = true
                Task {
                    await voice.join(.init(id: channel.id, name: channel.name, serverId: server.id, serverName: server.name), me: me, canSpeak: access.can(.speak))
                    joining = false
                }
            } label: {
                if joining || voice.connecting {
                    ProgressView().tint(.white)
                } else {
                    Label("Join voice", systemImage: "phone.fill")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 58))
            .padding(.horizontal, 24)
            .disabled(!access.can(.connect) || joining)
            .transition(.slideIn(from: .bottom))
        }
    }
}

// The little bar above the tab bar while you're in a voice channel.
struct VoiceDock: View {
    @Environment(VoiceEngine.self) private var voice
    @Environment(CallCenter.self) private var calls
    @State private var expanded = false

    var body: some View {
        if let room = voice.room {
            HStack(spacing: 10) {
                Button { if room.isCall { calls.showScreen = true } else { expanded = true } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(Palette.success, in: Circle())
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(voice.connecting ? "Connecting…" : voice.sharingScreen ? "Sharing your screen" : room.isCall ? "In a call · tap to open" : "Voice connected").font(.jakarta(12, .heavy)).foregroundStyle(voice.sharingScreen ? Theme.main : Palette.success)
                            Text(room.isCall ? room.name : "\(room.name) · \(room.serverName)").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: -6) {
                            ForEach(voice.participants.prefix(4)) { p in
                                Avatar(url: p.picture, name: p.name, size: 24)
                                    .overlay(Circle().strokeBorder(p.speaking ? Palette.success : Palette.surface, lineWidth: p.speaking ? 2.5 : 2))
                                    .scaleEffect(p.speaking ? 1.12 : 1)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: p.speaking)
                                    .zIndex(p.speaking ? 1 : 0)
                            }
                        }
                    }
                }
                .buttonStyle(SoftPressStyle())
                if voice.sharingScreen {
                    Button { voice.stopScreenShare() } label: {
                        Image(systemName: "rectangle.on.rectangle.slash").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(Theme.main, in: Circle())
                    }
                    .buttonStyle(BouncyStyle())
                    .accessibilityLabel("Stop sharing")
                    .transition(.pop)
                }
                Button { voice.toggleMute() } label: {
                    Image(systemName: voice.muted ? "mic.slash.fill" : "mic.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(voice.muted ? Palette.danger : Palette.text2)
                        .frame(width: 36, height: 36).background(Palette.surface2, in: Circle())
                }
                .buttonStyle(BouncyStyle())
                Button { Task { await voice.leave() } } label: {
                    Image(systemName: "phone.down.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Palette.danger, in: Circle())
                }
                .buttonStyle(BouncyStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassPill(cornerRadius: 26)
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: voice.sharingScreen)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(isPresented: $expanded) {
                NavigationStack {
                    VoiceRoomView(server: Server(["id": room.serverId, "name": room.serverName]),
                                  channel: ServerChannel(["id": room.id, "name": room.name, "type": "voice", "community_id": room.serverId]))
                }
                .presentationDetents([.large])
                .presentationCornerRadius(24)
            }
        }
    }
}
