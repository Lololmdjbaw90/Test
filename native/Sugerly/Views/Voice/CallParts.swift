import SwiftUI
import WebRTC

// Pieces shared by chat calls and server voice rooms, so both look and move
// the same: a dark stage, a tile per person (their camera or screen when
// they show it, otherwise their picture with a green ring that breathes with
// their voice), and one floating bar of round buttons with their names.

struct CallBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A1320), Color(hex: 0x12080E)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.main.opacity(0.3), .clear], center: .init(x: 0.5, y: 0.3), startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

// One person in a call.
struct CallTile: View {
    let name: String
    let picture: String
    var muted = false
    var deafened = false
    var speaking = false
    var level: Double = 0
    var connecting = false
    var video: RTCVideoTrack? = nil
    var mirror = false
    var isScreen = false
    var avatarSize: CGFloat = 84

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            shape.fill(.white.opacity(speaking ? 0.1 : 0.06))
            if let video {
                VideoTrackView(track: video, fill: !isScreen, mirror: mirror)
                    .clipShape(shape)
            } else {
                SpeakingAvatar(picture: picture, name: name, speaking: speaking, level: level, size: avatarSize)
                    .opacity(connecting ? 0.55 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            nameTag.padding(8)
        }
        .overlay(shape.strokeBorder(speaking ? Palette.success : Color.white.opacity(0.08), lineWidth: speaking ? 2.5 : 1))
        .animation(Motion.fade, value: speaking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)\(muted ? ", muted" : "")\(speaking ? ", talking" : "")")
    }

    private var nameTag: some View {
        HStack(spacing: 5) {
            if muted || deafened {
                Image(systemName: deafened ? "speaker.slash.fill" : "mic.slash.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.danger)
            } else if speaking {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.success)
            }
            if isScreen {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 10, weight: .bold))
            }
            Text(connecting ? "\(name) · connecting…" : name)
                .font(.jakarta(12, .bold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.42), in: Capsule())
    }
}

// Their picture; while they talk, a green ring and a soft circle that grows
// with how loud they are.
struct SpeakingAvatar: View {
    let picture: String
    let name: String
    let speaking: Bool
    let level: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Palette.success.opacity(0.22))
                .frame(width: size + 22, height: size + 22)
                .scaleEffect(speaking && !Motion.reduced ? 1 + level * 0.22 : 0.9)
                .opacity(speaking ? 1 : 0)
            Circle().strokeBorder(Palette.success, lineWidth: 3)
                .frame(width: size + 10, height: size + 10)
                .opacity(speaking ? 1 : 0)
            Avatar(url: picture, name: name, size: size)
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(Motion.standard, value: speaking)
    }
}

// A round call button with its name under it. White when it's on (camera
// on, microphone off…), red for leaving.
struct CallButton: View {
    let icon: String
    let label: String
    var on = false
    var danger = false
    var size: CGFloat = 54
    var action: () -> Void

    private var fill: Color {
        if danger { return Palette.danger }
        return on ? Color.white : Color.white.opacity(0.14)
    }

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(on && !danger ? Color(hex: 0x1A0E15) : .white)
                    .frame(width: size, height: size)
                    .background(fill, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .accessibilityLabel(label)
            .sensoryFeedback(.impact(weight: .light), trigger: on)
            Text(label)
                .font(.jakarta(11, .bold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .motion(Motion.standard, value: on)
    }
}

// The floating bar the call buttons sit in.
struct CallBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) { content() }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 12)
    }
}

// A small round button for the top of a call screen.
struct CallTopButton: View {
    let icon: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

// Where the sound goes (speaker, earpiece, headphones…), as a top button.
struct CallAudioButton: View {
    var body: some View {
        RoutePicker()
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.12), in: Circle())
            .accessibilityLabel("Audio output")
    }
}
