import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

final class ReelPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct ReelPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> ReelPlayerUIView { let v = ReelPlayerUIView(); v.playerLayer.videoGravity = .resizeAspect; return v }
    func updateUIView(_ view: ReelPlayerUIView, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: ReelPlayerUIView, coordinator: ()) { view.playerLayer.player = nil }
}

struct ReelLook: ViewModifier {
    let filter: String
    let mirror: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(x: mirror ? -1 : 1, y: 1)
            .saturation(filter == "mono" ? 0 : filter == "vivid" ? 1.55 : filter == "sugar" ? 1.15 : 1)
            .contrast(filter == "vivid" ? 1.15 : filter == "dreamy" ? 0.86 : 1)
            .brightness(filter == "dreamy" ? 0.06 : filter == "sugar" ? 0.03 : 0)
            .overlay { if filter == "sugar" { Color.pink.opacity(0.12).allowsHitTesting(false) }; if filter == "dreamy" { Color.purple.opacity(0.1).allowsHitTesting(false) } }
    }
}

struct ReelTextOverlay: View {
    let items: [Doc]
    var body: some View {
        GeometryReader { g in
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item.str("text"))
                    .font(.custom(item.str("font") == "bubbly" ? "Bubbly-Regular" : "CuteHereRegular", size: g.size.width * (item["size"] as? Double ?? 0.07)))
                    .foregroundStyle(Color(hex: item.str("color").isEmpty ? "ffffff" : item.str("color")))
                    .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    .position(x: g.size.width * (item["x"] as? Double ?? 0.5), y: g.size.height * (item["y"] as? Double ?? 0.35))
            }
        }.allowsHitTesting(false)
    }
}

struct EditorAsset: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage?
    let type: UTType
    var video: Bool { type.conforms(to: .movie) }
}

@MainActor @Observable final class ReelDraft {
    var assets: [EditorAsset] = []
    var player: AVPlayer?
    var loading = false
    var error: String?
    var duration = 0.0
    var start = 0.0
    var end = 0.0
    var speed = 1.0
    var filter = "none"
    var mirror = false
    var muted = false
    var text = ""
    var textX = 0.5
    var textY = 0.35
    var textColor = "FFFFFF"
    var textFont = "cute"
    var photo = 0
    var playing = false
    private var temporary: URL?
    var isVideo: Bool { assets.first?.video == true }
    var edits: Doc {
        let sticker: Doc = ["id": "native-text", "text": text, "x": textX, "y": textY, "size": 0.075, "color": "#" + textColor, "font": textFont, "style": "pill", "anim": "none"]
        return ["trim_start": start, "trim_end": end, "speed": speed, "filter": filter, "mirror": mirror, "muted": muted, "text": text.isEmpty ? [] : [sticker]]
    }
    func load(_ selections: [PhotosPickerItem]) async {
        cleanup(); loading = true; error = nil; assets = []; photo = 0; duration = 0; start = 0; end = 0
        defer { if !Task.isCancelled { loading = false } }
        do {
            var next: [EditorAsset] = []; var total = 0
            for item in selections {
                guard !Task.isCancelled else { return }
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 100 * 1024 * 1024 else { throw APIError(message: "Each file must be under 100 MB.") }
                total += data.count
                guard total <= 200 * 1024 * 1024 else { throw APIError(message: "Choose fewer files: keep this reel under 200 MB.") }
                let videoType = item.supportedContentTypes.first { $0.conforms(to: .movie) }
                let image = videoType == nil ? UIImage(data: data) : nil
                guard videoType != nil || image != nil else { throw APIError(message: "This photo couldn't be opened.") }
                next.append(EditorAsset(data: data, image: image, type: videoType ?? .jpeg))
            }
            guard !Task.isCancelled else { return }
            guard !next.contains(where: \.video) || next.count == 1 else { throw APIError(message: "Choose a single video, or photos only.") }
            if let first = next.first, first.video {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(first.type.preferredFilenameExtension ?? "mp4")
                try first.data.write(to: file)
                let asset = AVURLAsset(url: file)
                do {
                    let seconds = try await asset.load(.duration).seconds
                    guard !Task.isCancelled else { try? FileManager.default.removeItem(at: file); return }
                    guard seconds.isFinite, seconds >= 0.3 else { throw APIError(message: "This video is too short or couldn't be read.") }
                    temporary = file; duration = seconds; end = seconds; player = AVPlayer(url: file)
                } catch { try? FileManager.default.removeItem(at: file); throw error }
            }
            assets = next
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func preview() {
        guard let player else { return }
        player.pause(); playing = false; player.isMuted = muted
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func toggle() {
        guard let player else { return }
        if playing { player.pause(); playing = false }
        else { player.isMuted = muted; player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600); player.playImmediately(atRate: Float(speed)); playing = true }
    }
    func movePhoto(_ offset: Int) {
        let to = photo + offset
        guard assets.indices.contains(to), !isVideo else { return }
        assets.swapAt(photo, to); photo = to
    }
    func cleanup() {
        player?.pause(); player = nil; playing = false
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
        temporary = nil
    }
}

struct CandyScrubber: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let changed: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(String(format: "%.1fs", value)).monospacedDigit() }.font(.caption.bold())
            GeometryReader { g in
                let fraction = (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.soft).frame(height: 10)
                    Capsule().fill(Theme.gradient).frame(width: max(12, g.size.width * fraction), height: 10)
                    Circle().fill(Theme.pink).frame(width: 24, height: 24).overlay(Circle().stroke(.white, lineWidth: 3)).offset(x: max(0, (g.size.width - 24) * fraction))
                }.frame(height: 36).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in value = range.lowerBound + min(1, max(0, event.location.x / g.size.width)) * (range.upperBound - range.lowerBound); changed() })
            }.frame(height: 36)
        }.accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(String(format: "%.1f seconds", value))
            .accessibilityAdjustableAction { direction in value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 0.1 : -0.1))); changed() }
    }
}

struct NativeEditorPanel: View {
    let selections: [PhotosPickerItem]
    @Bindable var draft: ReelDraft
    @State private var tool = "Look"
    var body: some View {
        VStack(spacing: 16) {
            if draft.loading { ProgressView("Preparing your canvas…").padding(40) }
            if let error = draft.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if !draft.assets.isEmpty {
                preview
                HStack(spacing: 6) {
                    ForEach(["Look", "Trim", "Text", "Sound"], id: \.self) { item in
                        Button { tool = item } label: { Text(item).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(tool == item ? .white : Theme.pink).background(tool == item ? Theme.pink : Theme.soft, in: Capsule()) }
                    }
                }
                CandyCard(title: tool == "Look" ? "Find your vibe" : tool == "Trim" ? "Keep the good bits" : tool == "Text" ? "Say a little something" : "Sound & speed", icon: tool == "Text" ? "textformat" : "sparkles") {
                    controls
                }
            }
        }.task(id: selections) { await draft.load(selections) }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { event in
                if let item = event.object as? AVPlayerItem, item === draft.player?.currentItem { draft.preview() }
            }
    }
    private var preview: some View {
        ZStack {
            Color.black
            Group {
                if let player = draft.player { ReelPlayerSurface(player: player) }
                else { TabView(selection: $draft.photo) { ForEach(Array(draft.assets.enumerated()), id: \.element.id) { i, asset in if let image = asset.image { Image(uiImage: image).resizable().scaledToFit().tag(i) } } }.tabViewStyle(.page(indexDisplayMode: draft.assets.count > 1 ? .always : .never)) }
            }.modifier(ReelLook(filter: draft.filter, mirror: draft.mirror))
            if !draft.text.isEmpty {
                GeometryReader { g in
                    Text(draft.text).font(.custom(draft.textFont == "bubbly" ? "Bubbly-Regular" : "CuteHereRegular", size: g.size.width * 0.075)).foregroundStyle(Color(hex: draft.textColor))
                        .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                        .position(x: g.size.width * draft.textX, y: g.size.height * draft.textY)
                        .gesture(DragGesture(coordinateSpace: .named("reelCanvas")).onChanged { event in draft.textX = min(0.85, max(0.15, event.location.x / g.size.width)); draft.textY = min(0.85, max(0.15, event.location.y / g.size.height)) })
                }.coordinateSpace(name: "reelCanvas")
            }
            if draft.isVideo { VStack { Spacer(); Button { draft.toggle() } label: { Label(draft.playing ? "Pause" : "Preview", systemImage: draft.playing ? "pause.fill" : "play.fill").font(.caption.bold()).padding(12).background(Theme.pink, in: Capsule()).foregroundStyle(.white) }.padding(14) } }
        }.frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.pink.opacity(0.35), lineWidth: 2))
    }
    @ViewBuilder private var controls: some View {
        switch tool {
        case "Look":
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(["none", "sugar", "dreamy", "vivid", "mono"], id: \.self) { filter in
                    Button { draft.filter = filter } label: { VStack { RoundedRectangle(cornerRadius: 13).fill(Theme.gradient).frame(width: 62, height: 62).modifier(ReelLook(filter: filter, mirror: false)).overlay { Image(systemName: "heart.fill").foregroundStyle(.white) }; Text(filter == "none" ? "Original" : filter.capitalized).font(.caption).foregroundStyle(draft.filter == filter ? Theme.pink : .secondary) } }
                } }
            }
            Button { draft.mirror.toggle() } label: { Label(draft.mirror ? "Mirrored ✓" : "Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
        case "Trim":
            if draft.isVideo {
                CandyScrubber(title: "Start", value: $draft.start, range: 0...max(0.001, draft.end - 0.3), changed: draft.preview)
                CandyScrubber(title: "End", value: $draft.end, range: min(draft.duration, draft.start + 0.3)...max(0.3, draft.duration), changed: draft.preview)
                Text(String(format: "Final length: %.1f seconds", (draft.end - draft.start) / draft.speed)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Photo \(draft.photo + 1) of \(draft.assets.count) · swipe the preview").font(.subheadline)
                HStack { Button("Move left") { draft.movePhoto(-1) }.disabled(draft.photo == 0); Spacer(); Button("Move right") { draft.movePhoto(1) }.disabled(draft.photo >= draft.assets.count - 1) }
                Button("Remove this photo") { draft.assets.remove(at: draft.photo); draft.photo = min(draft.photo, draft.assets.count - 1) }.foregroundStyle(.red).disabled(draft.assets.count <= 1)
            }
        case "Text":
            TextField("Add your words…", text: $draft.text, axis: .vertical).lineLimit(1...3).padding(12).background(Theme.soft, in: RoundedRectangle(cornerRadius: 14)).onChange(of: draft.text) { _, value in if value.count > 100 { draft.text = String(value.prefix(100)) } }
            Text("Drag the text on your preview to place it.").font(.caption).foregroundStyle(.secondary)
            HStack { ForEach(["FFFFFF", "FFB8D6", "FFE08A", "C9B7FF"], id: \.self) { color in Button { draft.textColor = color } label: { Circle().fill(Color(hex: color)).frame(width: 38, height: 38).overlay(Circle().stroke(Theme.pink, lineWidth: draft.textColor == color ? 3 : 1)) }.accessibilityLabel("Text color \(color)") }; Spacer() }
            HStack { Button("Cute Here") { draft.textFont = "cute" }.font(.custom("CuteHereRegular", size: 20)); Button("Bubbly") { draft.textFont = "bubbly" }.font(.custom("Bubbly-Regular", size: 20)) }
        default:
            if draft.isVideo {
                Button { draft.muted.toggle(); draft.player?.isMuted = draft.muted } label: { Label(draft.muted ? "Original sound off" : "Original sound on", systemImage: draft.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                HStack { ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { speed in Button { draft.speed = speed; if draft.playing { draft.player?.rate = Float(speed) } } label: { Text("\(speed, specifier: "%g")×").font(.caption.bold()).padding(10).background(draft.speed == speed ? Theme.pink : Theme.soft, in: Capsule()).foregroundStyle(draft.speed == speed ? .white : Theme.pink) } } }
            } else { Text("Choose a soundtrack below. Photos stay still until you swipe.").font(.subheadline) }
        }
    }
}
