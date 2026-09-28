import SwiftUI

// A voice channel: who's in it (glowing when they talk), and big round
// controls to join, mute, deafen and hang up.
struct VoiceRoomView: View {
    let server: Server
    let channel: ServerChannel
    @Environment(AppModel.self) private var model
    @Environment(VoiceEngine.self) private var voice
    @State private var store: ServerStore
    @State private var joining = false

    init(server: Server, channel: ServerChannel) {
        self.server = server
        self.channel = channel
        _store = State(initialValue: ServerStore(server))
    }

    private var here: Bool { voice.room?.id == channel.id }
    private var access: Access { store.access(model.me?.email ?? "", siteAdmin: model.me?.isAdmin ?? false) }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(Theme.gradient, in: Circle())
                    .shadow(color: Theme.main.opacity(0.45), radius: 14, y: 6)
                    .symbolEffect(.variableColor.iterative, isActive: here)
                Text(channel.name).font(.display(30)).foregroundStyle(Palette.text)
                Text(here ? "Connected · \(voice.participants.count) here" : "\(others.count) in the channel")
                    .font(.jakarta(13, .semibold)).foregroundStyle(here ? Palette.success : Palette.muted)
            }
            .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                    if here {
                        ForEach(voice.participants) { p in
                            tile(name: p.isSelf ? "You" : p.name, picture: model.person(p.email)?.picture ?? p.picture, muted: p.muted, deafened: p.deafened, speaking: p.speaking, connecting: !p.isSelf && !p.connected)
                        }
                    } else {
                        ForEach(others) { p in
                            tile(name: model.person(p.email)?.displayName ?? p.name, picture: model.person(p.email)?.picture ?? p.picture, muted: p.muted, deafened: p.deafened, speaking: false, connecting: false)
                        }
                    }
                }
                .padding(.horizontal, 16)
                if !here && others.isEmpty {
                    Text("Nobody's here yet — hop in and wait for friends").font(.jakarta(14)).foregroundStyle(Palette.muted).padding(.top, 30)
                }
            }

            if let error = voice.error {
                Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger).multilineTextAlignment(.center).padding(.horizontal, 20)
            }

            controls
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .sugarBackground()
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
            while !Task.isCancelled && !here {
                try? await Task.sleep(for: .seconds(4))
                await store.loadVoice()
            }
        }
    }

    private var others: [VoicePresenceInfo] { store.voice[channel.id] ?? [] }

    private func tile(name: String, picture: String, muted: Bool, deafened: Bool, speaking: Bool, connecting: Bool) -> some View {
        VStack(spacing: 8) {
            Avatar(url: picture, name: name, size: 78)
                .padding(4)
                .overlay(Circle().strokeBorder(speaking ? AnyShapeStyle(Palette.success) : AnyShapeStyle(Color.clear), lineWidth: 3))
                .shadow(color: speaking ? Palette.success.opacity(0.6) : .clear, radius: 12)
                .scaleEffect(speaking ? 1.05 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: speaking)
                .overlay(alignment: .bottomTrailing) {
                    if muted || deafened {
                        Image(systemName: deafened ? "speaker.slash.fill" : "mic.slash.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Palette.danger, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    }
                }
            Text(name).font(.jakarta(13, .bold)).foregroundStyle(Palette.text).lineLimit(1)
            if connecting { Text("connecting…").font(.jakarta(10)).foregroundStyle(Palette.muted) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(speaking ? Palette.success.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(speaking ? Palette.success.opacity(0.4) : Palette.border, lineWidth: 1))
    }

    @ViewBuilder
    private var controls: some View {
        if here {
            HStack(spacing: 18) {
                round(voice.muted ? "mic.slash.fill" : "mic.fill", active: voice.muted, label: voice.muted ? "Unmute" : "Mute") { voice.toggleMute() }
                    .disabled(!access.can(.speak))
                round(voice.deafened ? "speaker.slash.fill" : "speaker.wave.2.fill", active: voice.deafened, label: voice.deafened ? "Undeafen" : "Deafen") { voice.toggleDeafen() }
                Button { Task { await voice.leave() } } label: {
                    Image(systemName: "phone.down.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(Palette.danger, in: Circle())
                        .shadow(color: Palette.danger.opacity(0.5), radius: 12, y: 5)
                }
                .buttonStyle(BouncyStyle(scale: 0.88))
                .accessibilityLabel("Leave voice")
            }
        } else {
            Button {
                guard let me = model.me else { return }
                joining = true
                Task {
                    await voice.join(.init(id: channel.id, name: channel.name, serverId: server.id, serverName: server.name), me: me, canSpeak: access.can(.speak))
                    joining = false
                }
            } label: {
                if joining || voice.connecting { ProgressView().tint(.white) } else { Label("Join voice", systemImage: "phone.fill") }
            }
            .buttonStyle(GradientButtonStyle(height: 58))
            .padding(.horizontal, 30)
            .disabled(!access.can(.connect) || joining)
        }
    }

    private func round(_ icon: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 22, weight: .bold))
                .foregroundStyle(active ? .white : Theme.main)
                .frame(width: 64, height: 64)
                .background(active ? AnyShapeStyle(Palette.danger) : AnyShapeStyle(Theme.soft), in: Circle())
                .overlay(Circle().strokeBorder(active ? Color.clear : Theme.main.opacity(0.2), lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: active)
    }
}

// The little bar above the tab bar while you're in a voice channel.
struct VoiceDock: View {
    @Environment(VoiceEngine.self) private var voice
    @State private var expanded = false

    var body: some View {
        if let room = voice.room {
            HStack(spacing: 10) {
                Button { expanded = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(Palette.success, in: Circle())
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(voice.connecting ? "Connecting…" : "Voice connected").font(.jakarta(12, .heavy)).foregroundStyle(Palette.success)
                            Text("\(room.name) · \(room.serverName)").font(.jakarta(12, .semibold)).foregroundStyle(Palette.text2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: -8) {
                            ForEach(voice.participants.prefix(3)) { p in
                                Avatar(url: p.picture, name: p.name, size: 24).overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
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
            .padding(.horizontal, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(isPresented: $expanded) {
                NavigationStack {
                    VoiceRoomView(server: Server(["id": room.serverId, "name": room.serverName]),
                                  channel: ServerChannel(["id": room.id, "name": room.name, "type": "voice", "community_id": room.serverId]))
                }
                .presentationDetents([.large])
                .presentationCornerRadius(34)
            }
        }
    }
}
