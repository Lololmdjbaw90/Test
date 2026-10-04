import SwiftUI
import PhotosUI
import AVFoundation

// The photo and video editor, made for phones: the picture as big as the
// screen allows, the tools down the right side (like TikTok), each tool's
// controls sliding up from the bottom, and undo / redo at the top. Used for
// reels (video or slideshow), for chat media and for photos in posts.

enum EditorPalette {
    static let backdrop = Color(hex: 0x0E090C)
    static let panel = Color(hex: 0x1C1218)
    static let chip = Color.white.opacity(0.1)
}

enum EditorTool: String, CaseIterable, Identifiable {
    case text, stickers, draw, filters, adjust, trim, speed, timeline, crop, rotate, sound
    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .stickers: return "Stickers"
        case .draw: return "Draw"
        case .filters: return "Filters"
        case .adjust: return "Adjust"
        case .trim: return "Trim"
        case .speed: return "Speed"
        case .timeline: return "Timeline"
        case .crop: return "Crop"
        case .rotate: return "Rotate"
        case .sound: return "Sound"
        }
    }

    var icon: String {
        switch self {
        case .text: return "textformat"
        case .stickers: return "star.square.on.square.fill"
        case .draw: return "scribble.variable"
        case .filters: return "camera.filters"
        case .adjust: return "slider.horizontal.3"
        case .trim: return "scissors"
        case .speed: return "speedometer"
        case .timeline: return "film.stack"
        case .crop: return "crop"
        case .rotate: return "rotate.right"
        case .sound: return "music.note"
        }
    }

    // Text and Rotate act straight away; the rest open their controls.
    var hasPanel: Bool { self != .text && self != .rotate }
}

struct MediaEditor: View {
    @Bindable var doc: EditorModel
    var primaryTitle: String
    var primaryIcon: String? = nil
    var busy = false
    var backIcon = "chevron.left"
    var onBack: () -> Void
    var onPrimary: () -> Void

    @State private var tool: EditorTool?
    @State private var editingText: TextSticker?
    @State private var cropJob: EditorCrop?
    @State private var choosingSound = false
    @State private var overlayItem: PhotosPickerItem?

    private var tools: [EditorTool] {
        if doc.isPhoto { return [.text, .stickers, .draw, .filters, .adjust, .crop, .rotate] }
        if doc.isVideo { return [.text, .stickers, .draw, .filters, .adjust, .trim, .speed, .timeline, .crop, .sound] }
        return [.text, .stickers, .draw, .filters, .adjust, .timeline, .crop, .sound]
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(doc: doc, primaryTitle: primaryTitle, primaryIcon: primaryIcon, busy: busy, backIcon: backIcon, onBack: onBack) {
                tool = nil
                onPrimary()
            }
            stage
            bottom
        }
        .background(EditorPalette.backdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: tool)
        .sensoryFeedback(.selection, trigger: tool)
        .sheet(item: $editingText) { sticker in
            TextStickerEditor(sticker: sticker) { updated in
                doc.saveText(updated)
            } onDelete: { id in
                doc.deleteSticker(id)
            }
            .presentationDetents([.large])
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $choosingSound) {
            SoundPicker { track in doc.setSound(track) }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(30)
        }
        .fullScreenCover(item: $cropJob) { job in
            ImageCropper(image: job.image, circle: false, aspect: cropAspect(job), choices: CropAspect.editor, title: "Move and pinch to crop", onDone: { rect in
                cropJob = nil
                doc.applyCrop(job, rect)
            }, onCancel: { cropJob = nil })
            .preferredColorScheme(.dark)
        }
        .onChange(of: overlayItem) { _, item in
            guard let item else { return }
            Task {
                defer { overlayItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                doc.addPhotoOverlay(EditorModel.overlayPicture(image))
            }
        }
        .onChange(of: editingText?.id) { _, id in
            if id != nil { doc.player.pause() }
        }
    }

    // MARK: the picture

    private var stage: some View {
        GeometryReader { geo in
            let area = CGSize(width: max(0, geo.size.width - 24), height: max(0, geo.size.height - 8))
            let size = Self.fit(doc.aspect, in: area)
            EditorCanvas(doc: doc, size: size, drawing: tool == .draw, onEditText: { editingText = $0 }, onTapEmpty: {
                if !doc.isPhoto { doc.player.toggle() }
            })
            // The shadow sits on a plain shape behind the picture, so the
            // video itself never has to be shadowed frame by frame.
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            }
            .overlay(alignment: .topTrailing) {
                if tool == nil {
                    ToolRail(tools: tools) { pick($0) }
                        .padding(.top, 8)
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static func fit(_ aspect: CGFloat, in area: CGSize) -> CGSize {
        guard area.width > 0, area.height > 0, aspect > 0 else { return CGSize(width: 1, height: 1) }
        let w = min(area.width, area.height * aspect)
        return CGSize(width: max(1, w), height: max(1, w / aspect))
    }

    private func cropAspect(_ job: EditorCrop) -> CGFloat {
        guard doc.isPhoto else { return 9 / 16 }
        return max(0.2, job.image.size.width / max(1, job.image.size.height))
    }

    // MARK: tools

    private func pick(_ t: EditorTool) {
        switch t {
        case .text:
            doc.checkpoint()
            editingText = TextSticker(text: "")
        case .rotate:
            doc.rotatePhoto()
        case .sound:
            if doc.sound == nil { choosingSound = true }
            tool = .sound
        case .timeline:
            tool = .timeline
            Task { await doc.refreshStrip() }
        default:
            tool = t
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if let tool {
            ToolPanel(title: tool.title, icon: tool.icon, onDone: { self.tool = nil }) {
                panel(tool)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if doc.isPhoto {
            Color.clear.frame(height: 10)
        } else {
            PlaybackBar(doc: doc)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func panel(_ t: EditorTool) -> some View {
        switch t {
        case .filters:
            FiltersPanel(doc: doc)
        case .adjust:
            AdjustPanel(doc: doc)
        case .trim:
            TrimPanel(doc: doc)
        case .speed:
            SpeedPanel(doc: doc)
        case .timeline:
            TimelinePanel(doc: doc, photoItem: $overlayItem, onAddText: {
                doc.checkpoint()
                let timing = doc.newOverlayTiming()
                editingText = TextSticker(text: "", start: timing.start, end: timing.end)
            }, onAddSticker: {
                tool = .stickers
            }, onEditText: { sticker in
                doc.checkpoint()
                editingText = sticker
            })
        case .crop:
            CropPanel(doc: doc) {
                Task { if let job = await doc.makeCropJob() { cropJob = job } }
            }
        case .draw:
            DrawToolPanel(doc: doc)
        case .stickers:
            StickersPanel(doc: doc, photoItem: $overlayItem)
        case .sound:
            SoundPanel(doc: doc) { choosingSound = true }
        case .text, .rotate:
            EmptyView()
        }
    }
}

// MARK: - Top bar

struct EditorTopBar: View {
    let doc: EditorModel
    var primaryTitle: String
    var primaryIcon: String?
    var busy: Bool
    var backIcon: String
    var onBack: () -> Void
    var onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            barButton(backIcon, "Back", enabled: true, action: onBack)
            barButton("arrow.uturn.backward", "Undo", enabled: doc.canUndo) { doc.undo() }
            barButton("arrow.uturn.forward", "Redo", enabled: doc.canRedo) { doc.redo() }
            Spacer(minLength: 8)
            Button(action: onPrimary) {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView().tint(.white).controlSize(.small)
                    } else if let primaryIcon {
                        Image(systemName: primaryIcon)
                    }
                    Text(primaryTitle)
                }
            }
            .buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
            .disabled(busy)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func barButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(BouncyStyle(scale: 0.88))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Tool rail

// The tools down the right side of the picture, icons with their names.
struct ToolRail: View {
    let tools: [EditorTool]
    var onPick: (EditorTool) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(tools) { t in
                    Button { onPick(t) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon)
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.34), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            Text(t.title).font(.jakarta(10, .heavy))
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                        .frame(width: 58)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.86))
                    .accessibilityLabel(t.title)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 60)
    }
}

// MARK: - The canvas

// The picture with everything on it. Each layer watches only what it shows:
// the video, the slide on screen, the drawing, the text and stickers, and
// the pen (the stroke being drawn lives in the pen layer alone).
struct EditorCanvas: View {
    let doc: EditorModel
    let size: CGSize
    let drawing: Bool
    var onEditText: (TextSticker) -> Void
    var onTapEmpty: () -> Void

    var body: some View {
        ZStack {
            MediaLayer(doc: doc)
            StrokesLayer(doc: doc)
            OverlayLayer(doc: doc, size: size, onEditText: onEditText, onTapEmpty: onTapEmpty)
            if drawing {
                PenLayer(doc: doc).transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct MediaLayer: View {
    let doc: EditorModel

    var body: some View {
        if doc.isVideo {
            VideoPlayerLayer(player: doc.player.av)
        } else {
            SlideImage(doc: doc)
        }
    }
}

// The photo on screen (a soft cross-fade from one slide to the next).
private struct SlideImage: View {
    let doc: EditorModel

    var body: some View {
        let i = doc.isSlides ? doc.player.slide : 0
        Color.black
            .overlay {
                if doc.previews.indices.contains(i) {
                    Image(uiImage: doc.previews[i])
                        .resizable()
                        .scaledToFill()
                        .id(i)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.28), value: i)
    }
}

private struct StrokesLayer: View {
    let doc: EditorModel
    var body: some View {
        DrawingLayer(strokes: doc.strokes)
    }
}

private struct OverlayLayer: View {
    @Bindable var doc: EditorModel
    let size: CGSize
    var onEditText: (TextSticker) -> Void
    var onTapEmpty: () -> Void

    var body: some View {
        // Only overlays with a time follow the playhead.
        let timed = !doc.isPhoto && doc.stickers.contains { $0.isTimed }
        StickerCanvas(stickers: $doc.stickers, size: size, onEdit: { sticker in
            doc.selectedOverlay = sticker.id
            guard sticker.image == nil else { return }
            doc.checkpoint()
            onEditText(sticker)
        }, onTapEmpty: onTapEmpty, onSwipe: { step in
            if doc.isSlides { doc.player.stepSlide(step) }
        }, onBegin: {
            doc.checkpoint()
        }, isShown: { sticker in
            timed ? doc.isShown(sticker) : true
        }, corner: 22)
    }
}

// Draw with a finger. The stroke being drawn stays here until the finger
// lifts, so drawing never redraws the rest of the editor.
private struct PenLayer: View {
    let doc: EditorModel
    @State private var current: DrawStroke?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DrawingLayer(strokes: [], current: current)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let w = max(1, geo.size.width), h = max(1, geo.size.height)
                                let p = CGPoint(x: min(1, max(0, v.location.x / w)), y: min(1, max(0, v.location.y / h)))
                                if current == nil {
                                    current = DrawStroke(points: [p], color: doc.penColor, width: doc.penWidth, neon: doc.penNeon)
                                } else if let last = current?.points.last, hypot((last.x - p.x) * w, (last.y - p.y) * h) > 1.5 {
                                    current?.points.append(p)
                                }
                            }
                            .onEnded { _ in
                                if let current { doc.addStroke(current) }
                                current = nil
                            }
                    )
            }
        }
    }
}

// MARK: - Panels

// The card that slides up with a tool's controls; the tick closes it.
struct ToolPanel<Content: View>: View {
    let title: String
    let icon: String
    var onDone: () -> Void
    let content: () -> Content

    init(title: String, icon: String, onDone: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.onDone = onDone
        self.content = content
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.jakarta(15, .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.gradient, in: Circle())
                }
                .buttonStyle(BouncyStyle(scale: 0.86))
                .accessibilityLabel("Done")
            }
            .padding(.horizontal, 18)
            content()
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(EditorPalette.panel)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct FiltersPanel: View {
    let doc: EditorModel

    var body: some View {
        let base = doc.filterBase
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ReelFilter.allCases) { f in
                    let on = doc.look.filter == f
                    Button { doc.setFilter(f) } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let base {
                                    Image(uiImage: FilterThumbs.make(base, f)).resizable().scaledToFill()
                                } else {
                                    LinearGradient(colors: f.swatch, startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white, lineWidth: on ? 3 : 0))
                            .shadow(color: on ? Theme.pink.opacity(0.6) : .clear, radius: 8)
                            Text(f.rawValue)
                                .font(.jakarta(11, on ? .heavy : .bold))
                                .foregroundStyle(.white.opacity(on ? 1 : 0.65))
                        }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.9))
                    .accessibilityLabel(f.rawValue)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .sensoryFeedback(.selection, trigger: doc.look.filter)
    }
}

private struct AdjustPanel: View {
    let doc: EditorModel

    var body: some View {
        VStack(spacing: 2) {
            row("Brightness", "sun.max.fill", \.brightness, -1...1)
            row("Contrast", "circle.lefthalf.filled", \.contrast, -1...1)
            row("Saturation", "drop.fill", \.saturation, -1...1)
            row("Warmth", "thermometer.sun.fill", \.warmth, -1...1)
            row("Vignette", "camera.aperture", \.vignette, 0...1)
            Button("Reset") { doc.resetAdjust() }
                .font(.jakarta(12, .heavy))
                .foregroundStyle(Theme.pink)
                .padding(.top, 4)
                .opacity(doc.look.adjust.isNeutral ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
    }

    private func row(_ title: String, _ icon: String, _ kp: WritableKeyPath<ReelAdjust, Double>, _ range: ClosedRange<Double>) -> some View {
        let value = Binding(get: { doc.look.adjust[keyPath: kp] }, set: { v in
            doc.look.adjust[keyPath: kp] = v
            doc.refreshLook()
        })
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.pink).frame(width: 20)
            Text(title).font(.jakarta(12, .bold)).foregroundStyle(.white).frame(width: 76, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { doc.checkpoint() } })
                .tint(Theme.pink)
            Text("\(Int((value.wrappedValue * 100).rounded()))")
                .font(.jakarta(11, .bold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 34, alignment: .trailing)
        }
        .frame(height: 34)
    }
}

private struct TrimPanel: View {
    let doc: EditorModel

    var body: some View {
        TrimBar(thumbs: doc.thumbs, duration: doc.duration,
                start: Binding(get: { doc.trimStart }, set: { doc.trimStart = $0; doc.trimChanged() }),
                end: Binding(get: { doc.trimEnd }, set: { doc.trimEnd = $0; doc.trimChanged() }),
                onSeek: { doc.player.show(sourceSeconds: $0) },
                onScrub: { began in
                    if began {
                        doc.checkpoint()
                        doc.player.beginScrub()
                    } else {
                        doc.player.seek(0, precise: true)
                        doc.player.endScrub()
                    }
                })
            .padding(.horizontal, 16)
    }
}

private struct SpeedPanel: View {
    let doc: EditorModel
    private let speeds: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(speeds, id: \.self) { v in
                    let on = abs(doc.speed - v) < 0.01
                    Button { doc.setSpeed(v) } label: {
                        Text(String(format: "%gx", v)).font(.jakarta(14, .heavy))
                            .foregroundStyle(on ? Color(hex: 0x2A1620) : .white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(on ? Color.white : EditorPalette.chip, in: Capsule())
                    }
                    .buttonStyle(BouncyStyle(scale: 0.9))
                    .accessibilityLabel("Speed \(String(format: "%gx", v))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(abs(doc.speed - 1) < 0.01 ? "Normal speed" : "\(doc.speed < 1 ? "Slow motion" : "Faster") · \(Int(doc.finalLength.rounded()))s video")
                .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: doc.speed)
    }
}

private struct TimelinePanel: View {
    @Bindable var doc: EditorModel
    @Binding var photoItem: PhotosPickerItem?
    var onAddText: () -> Void
    var onAddSticker: () -> Void
    var onEditText: (TextSticker) -> Void

    var body: some View {
        ReelTimeline(length: doc.length, playhead: doc.player.time, playing: doc.player.playing,
                     thumbs: doc.stripThumbs.isEmpty ? doc.thumbs : doc.stripThumbs,
                     slides: doc.isSlides ? doc.previews : [],
                     slideSeconds: Binding(get: { doc.slideSeconds }, set: { doc.slideSeconds = $0; doc.slidesChanged() }),
                     stickers: $doc.stickers, selected: $doc.selectedOverlay, selectedSlide: $doc.selectedSlide, photoItem: $photoItem,
                     onSeek: { doc.player.seek($0) },
                     onScrub: { began in began ? doc.player.beginScrub() : doc.player.endScrub() },
                     onTogglePlay: { doc.player.toggle() },
                     onAddText: onAddText,
                     onAddSticker: onAddSticker,
                     onEditText: onEditText,
                     onCheckpoint: { doc.checkpoint() },
                     onMoveSlide: { doc.moveSlide($0, $1) },
                     onDeleteSlide: { doc.deleteSlide($0) })
            .frame(height: 250)
    }
}

private struct CropPanel: View {
    let doc: EditorModel
    var onCrop: () -> Void

    private var hint: String {
        if doc.isVideo { return doc.videoCrop == nil ? "Zoom in and keep just the part you want" : "Video cropped" }
        if doc.isSlides { return "Photo \(doc.player.slide + 1) of \(doc.photos.count) · swipe the picture to pick another" }
        return "Crop to any shape, or turn the photo"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(hint)
                .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(action: onCrop) { Label(doc.isVideo ? "Crop video" : "Crop photo", systemImage: "crop") }
                    .buttonStyle(GradientButtonStyle(height: 42, fullWidth: false))
                if doc.isVideo && doc.videoCrop != nil {
                    Button { doc.resetCrop() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(OutlineButtonStyle(height: 42))
                }
                if doc.isPhoto {
                    Button { doc.rotatePhoto() } label: { Label("Turn", systemImage: "rotate.right") }
                        .buttonStyle(OutlineButtonStyle(height: 42))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }
}

private struct DrawToolPanel: View {
    @Bindable var doc: EditorModel

    var body: some View {
        DrawPanel(color: $doc.penColor, width: $doc.penWidth, neon: $doc.penNeon, canUndo: !doc.strokes.isEmpty,
                  onUndo: { doc.undoStroke() }, onClear: { doc.clearStrokes() })
    }
}

private struct StickersPanel: View {
    let doc: EditorModel
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            StickerTray { doc.addSticker($0) }
                .frame(height: 110)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Add a photo on top", systemImage: "photo.badge.plus")
                    .font(.jakarta(13, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(EditorPalette.chip, in: Capsule())
            }
            .buttonStyle(SoftPressStyle())
        }
    }
}

private struct SoundPanel: View {
    let doc: EditorModel
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if let cover = doc.sound?.coverURL, !cover.isEmpty {
                        RemoteImage(url: cover)
                    } else {
                        Theme.gradient.overlay(Image(systemName: "music.note").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.sound?.title ?? "No sound yet").font(.jakarta(14, .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(doc.sound?.artist ?? "Pick a song for your reel").font(.jakarta(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(doc.sound == nil ? "Add" : "Change", action: onPick)
                    .buttonStyle(GradientButtonStyle(height: 34, fullWidth: false))
                if doc.sound != nil {
                    Button { doc.setSound(nil) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.6))
                    }
                    .accessibilityLabel("Remove sound")
                }
            }
            if doc.sound != nil {
                volume("Song", "music.note", Binding(get: { doc.soundVolume }, set: { doc.soundVolume = $0; doc.soundVolumeChanged() }))
            }
            if doc.isVideo {
                volume("Original", "waveform", Binding(get: { doc.originalVolume }, set: { doc.originalVolume = $0; doc.originalVolumeChanged() }))
            }
        }
        .padding(.horizontal, 16)
    }

    private func volume(_ title: String, _ icon: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.pink).frame(width: 20)
            Text(title).font(.jakarta(12, .bold)).foregroundStyle(.white).frame(width: 64, alignment: .leading)
            Slider(value: value, in: 0...1).tint(Theme.pink)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.jakarta(11, .bold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Play bar

// Play / pause, a bar you can drag to any moment, and the time.
private struct PlaybackBar: View {
    let doc: EditorModel
    @State private var dragging = false

    var body: some View {
        let player = doc.player
        let length = doc.length
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .accessibilityLabel(player.playing ? "Pause" : "Play")
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let p = CGFloat(min(1, max(0, player.time / max(0.1, length))))
                let knob: CGFloat = dragging ? 18 : 12
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16)).frame(height: 6)
                    Capsule().fill(Theme.gradient).frame(width: max(6, w * p), height: 6)
                    Circle().fill(.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: min(max(0, w * p - knob / 2), w - knob))
                }
                .frame(width: w, height: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !dragging {
                                dragging = true
                                player.beginScrub()
                            }
                            player.seek(Double(min(max(0, v.location.x / w), 1)) * length)
                        }
                        .onEnded { _ in
                            dragging = false
                            player.endScrub()
                        }
                )
                .animation(.snappy(duration: 0.18), value: dragging)
            }
            .frame(height: 32)
            Text("\(ReelTimeline.clock(player.time)) / \(ReelTimeline.clock(length))")
                .font(.jakarta(11, .bold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
