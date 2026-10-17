import SwiftUI
import UIKit

// MARK: - Layout

// Where everything goes. The camera window is the reel's own shape (9:16)
// right under the status bar, with the modes under it, so what you see is
// exactly what gets filmed. On a phone that's about 9:16 itself, the camera
// fills the screen and the modes sit on it. With the front light on, the
// window shrinks a little so the light shows all round it.
struct RecorderFrame {
    let card: CGRect
    let strip: CGRect
    let roomy: Bool
    // Room the controls leave inside the window for the status bar and the
    // home bar (when the window reaches the screen's edges).
    let top: CGFloat
    let bottom: CGFloat
    let corner: CGFloat

    init(size: CGSize, insets: EdgeInsets, light: Bool) {
        let stripHeight: CGFloat = 52
        let room = size.height - insets.top - insets.bottom - stripHeight
        let width = min(size.width, room * 9 / 16)
        let pad: CGFloat = light ? 14 : 0
        if width >= size.width * 0.94 || size.width >= 600 {
            let full = width * 16 / 9
            let w = width - pad * 2
            let h = w * 16 / 9
            card = CGRect(x: (size.width - w) / 2, y: insets.top + (full - h) / 2, width: w, height: h)
            let stripTop = insets.top + full
            strip = CGRect(x: 0, y: stripTop, width: size.width, height: max(stripHeight, size.height - insets.bottom - stripTop))
            roomy = true
            top = 0
            bottom = 0
            corner = light ? 30 : 24
        } else if light {
            card = CGRect(x: pad, y: insets.top + pad, width: size.width - pad * 2,
                          height: size.height - insets.top - insets.bottom - pad * 2)
            strip = .zero
            roomy = false
            top = 0
            bottom = 0
            corner = 30
        } else {
            card = CGRect(origin: .zero, size: size)
            strip = .zero
            roomy = false
            top = insets.top
            bottom = insets.bottom
            corner = 0
        }
    }
}

// MARK: - Front light

// The colour of the front camera's light.
enum FrontLightTone: String, CaseIterable, Identifiable {
    case warm, white, pink
    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: return "Warm"
        case .white: return "Cool"
        case .pink: return "Pink"
        }
    }

    var color: Color {
        switch self {
        case .warm: return Color(red: 1, green: 0.94, blue: 0.84)
        case .white: return Color(red: 0.96, green: 0.98, blue: 1)
        case .pink: return Color(red: 1, green: 0.87, blue: 0.92)
        }
    }
}

// The front camera's flash (like TikTok and Instagram): the screen around
// the camera window becomes a soft, bright light that lights your face.
struct FrontLight: View {
    var tone: FrontLightTone

    var body: some View {
        ZStack {
            tone.color
            RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 60, endRadius: 560)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Warm, cool or pink: three swatches that spring out of the flash button
// while the front light is on.
struct ToneTray: View {
    let tone: FrontLightTone
    let pick: (FrontLightTone) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FrontLightTone.allCases) { t in
                let on = tone == t
                Button { pick(t) } label: {
                    Circle().fill(t.color)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(.white, lineWidth: on ? 2.5 : 0))
                        .scaleEffect(on ? 1.06 : 0.9)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BouncyStyle(scale: 0.85))
                .accessibilityLabel("\(t.title) light")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .background(.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .motion(Motion.release, value: tone)
        .sensoryFeedback(.selection, trigger: tone)
    }
}

// MARK: - Buttons

// The big button. Filming, it grows, its middle turns into a rounded square
// and the ring fills up with the reel's length, with a tick where each clip
// ends. It answers your finger straight away (the middle squishes).
struct RecordButton: View {
    let photo: Bool
    let filming: Bool
    let pressed: Bool
    let held: Bool
    let progress: Double
    let marks: [Double]

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(filming ? 0.18 : 0.1))
            Circle().strokeBorder(.white.opacity(filming ? 0.35 : 0.95), lineWidth: 5)
            if !photo {
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2.5)
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    Capsule().fill(.white)
                        .frame(width: 2.5, height: 7)
                        .offset(y: -39.5)
                        .rotationEffect(.degrees(mark * 360))
                }
            }
            middle
        }
        .frame(width: 84, height: 84)
        .scaleEffect(filming ? 1.16 : 1)
        .scaleEffect(held ? 1.06 : 1)
        .frame(width: 104, height: 104)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .animation(Motion.press, value: pressed)
        .animation(Motion.standard, value: filming)
        .animation(Motion.standard, value: held)
    }

    @ViewBuilder
    private var middle: some View {
        if photo {
            Circle().fill(.white)
                .frame(width: 66, height: 66)
                .scaleEffect(pressed ? 0.86 : 1)
        } else {
            RoundedRectangle(cornerRadius: filming ? 8 : 33, style: .continuous)
                .fill(Theme.gradient)
                .frame(width: filming ? 28 : 66, height: filming ? 28 : 66)
                .scaleEffect(pressed && !filming ? 0.88 : 1)
        }
    }
}

// A round button at the top of the camera.
struct RoundIcon: View {
    let icon: String
    let label: String
    var size: CGFloat = 44
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle())
        .accessibilityLabel(label)
    }
}

// One of the tools down the right side: a round icon with its name under it
// (just the icon when there's no room).
struct RailButton: View {
    let icon: String
    let title: String
    var active = false
    var badge: String? = nil
    var labeled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.black.opacity(0.3)), in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        if let badge {
                            Text(badge)
                                .font(.jakarta(9, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.black.opacity(0.75), in: Capsule())
                                .fixedSize()
                                .offset(x: 6, y: 4)
                        }
                    }
                if labeled {
                    // One line, smaller if the name doesn't fit (larger
                    // text sizes made long names spill or wrap).
                    Text(title)
                        .font(.jakarta(10, .bold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .accessibilityLabel(title)
        .accessibilityValue(badge ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// A square button with its name under it (Upload, Drafts).
struct SideTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                Text(title).font(.jakarta(11, .heavy)).foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(BouncyStyle())
        .transition(.pop)
    }
}

// MARK: - Bars and pickers

// The reel's length along the top: a piece per clip (the last one turns red
// when it's about to be deleted), the clip being filmed in white, and a
// small line at 15 seconds.
struct SegmentBar: View {
    let clips: [Double]
    let current: Double
    let limit: Double
    let armed: Bool
    let marker: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = max(1, limit)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                HStack(spacing: 2) {
                    ForEach(clips.indices, id: \.self) { i in
                        Rectangle()
                            .fill(armed && i == clips.count - 1 ? Palette.danger : Theme.main)
                            .frame(width: max(1, w * clips[i] / span - 2))
                    }
                    if current > 0 {
                        Rectangle().fill(.white).frame(width: max(1, w * current / span))
                    }
                }
                .frame(width: w, alignment: .leading)
                .clipShape(Capsule())
                if let marker, marker < span {
                    Rectangle().fill(.white.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: w * marker / span - 1)
                }
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("Filmed")
        .accessibilityValue("\(Int(clips.reduce(0, +) + current)) of \(Int(limit)) seconds")
    }
}

// The camera's zoom stops (.5, 1, 2, 3). The one you're on shows the exact
// zoom, like the iPhone's camera.
struct LensPicker: View {
    let lenses: [CameraLens]
    let zoom: CGFloat
    let pick: (CameraLens) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(lenses) { lens in
                let on = lens == current
                Button { pick(lens) } label: {
                    // Always one line: a long zoom ("2.2×") makes the
                    // round button a little wider instead of wrapping.
                    Text(on ? readout : lens.label)
                        .font(.system(size: on ? 13 : 12, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Color(hex: 0xFFD166) : Color.white)
                        .padding(.horizontal, on ? 8 : 0)
                        .frame(minWidth: on ? 38 : 30, minHeight: on ? 38 : 30)
                        .background(.black.opacity(on ? 0.55 : 0.3), in: Capsule())
                        .frame(minWidth: 42, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("Zoom \(String(format: "%g", Double(lens.shown))) times")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .background(.black.opacity(0.18), in: Capsule())
        .animation(Motion.standard, value: current?.shown)
    }

    // The stop the zoom is at (the nearest one at or under it).
    private var current: CameraLens? { lenses.last { zoom >= $0.shown - 0.04 } ?? lenses.first }

    // "1×", "1.4×", ".5×".
    private var readout: String {
        let value = (zoom * 10).rounded() / 10
        if value < 1 { return "." + String(Int((value * 10).rounded())) + "×" }
        return (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", Double(value))) + "×"
    }
}

// Filming speed: slow motion (0.5x) to fast (3x).
struct SpeedPicker: View {
    let speed: Double
    let pick: (Double) -> Void
    static let options: [Double] = [0.5, 1, 2, 3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.options, id: \.self) { value in
                let on = value == speed
                Button { pick(value) } label: {
                    Text(Self.label(value))
                        .font(.jakarta(13, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(on ? Color(hex: 0x2A1620) : Color.white)
                        .padding(.horizontal, 4)
                        .frame(width: 58, height: 34)
                        .background(on ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("Speed \(Self.label(value))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.45), in: Capsule())
        .motion(Motion.standard, value: speed)
    }

    static func label(_ value: Double) -> String { value == 0.5 ? "0.5x" : "\(Int(value))x" }
}

// Live filters: a round swatch for each, with its name.
struct FilterStrip: View {
    let selected: ReelFilter
    let pick: (ReelFilter) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReelFilter.allCases) { filter in
                        let on = filter == selected
                        Button { pick(filter) } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(LinearGradient(colors: filter.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay {
                                        if filter == .none {
                                            Image(systemName: "circle.slash")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(.black.opacity(0.45))
                                        }
                                    }
                                    .frame(width: 46, height: 46)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: on ? 2.5 : 0))
                                    .scaleEffect(on ? 1.06 : 1)
                                Text(filter.rawValue)
                                    .font(.jakarta(10, .bold))
                                    .foregroundStyle(on ? Color.white : Color.white.opacity(0.75))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .frame(minWidth: 60)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.9))
                        .id(filter)
                        .accessibilityLabel("\(filter.rawValue) filter")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, next in
                withMotion(Motion.standard) { proxy.scrollTo(next, anchor: .center) }
            }
        }
        .motion(Motion.standard, value: selected)
    }
}

// MARK: - On the picture

// Where you tapped to focus: a square, and the sun beside it showing how
// much brighter or darker you made it (slide up or down to change it).
struct FocusMark: View {
    let locked: Bool
    let exposure: Float

    private let tint = Color(hex: 0xFFD166)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint, lineWidth: locked ? 2.5 : 1.5)
                .frame(width: 76, height: 76)
            Capsule().fill(tint.opacity(0.7))
                .frame(width: 1.5, height: 96)
                .overlay {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .offset(y: -CGFloat(exposure) * 22)
                }
                .offset(x: 56)
        }
        .shadow(color: .black.opacity(0.3), radius: 3)
        .accessibilityHidden(true)
    }
}

// Rule-of-thirds lines over the camera.
struct CameraGrid: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3
                    let y = g.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
