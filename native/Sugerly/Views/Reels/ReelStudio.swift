import SwiftUI
import UIKit
import AVFoundation
import AVKit
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - Filters (live in the preview, baked into the video when posting)

enum ReelFilter: String, CaseIterable, Identifiable {
    case none = "Normal", pink = "Pink dream", warm = "Warm", cool = "Cool", vivid = "Vivid", fade = "Fade", mono = "Mono", noir = "Noir"
    var id: String { rawValue }

    var swatch: [Color] {
        switch self {
        case .none: return [Color(hex: 0xEEEEEE), Color(hex: 0xBBBBBB)]
        case .pink: return [Color(hex: 0xFFB3D1), Color(hex: 0xD9577F)]
        case .warm: return [Color(hex: 0xFFD6A5), Color(hex: 0xEE6E40)]
        case .cool: return [Color(hex: 0xBDE0FE), Color(hex: 0x2F80E0)]
        case .vivid: return [Color(hex: 0xFFD166), Color(hex: 0xEF476F)]
        case .fade: return [Color(hex: 0xF1E3E4), Color(hex: 0xB9A7AE)]
        case .mono: return [Color(hex: 0xDDDDDD), Color(hex: 0x555555)]
        case .noir: return [Color(hex: 0x888888), Color(hex: 0x111111)]
        }
    }

    func apply(_ input: CIImage) -> CIImage {
        switch self {
        case .none:
            return input
        case .pink:
            let f = CIFilter.colorMatrix()
            f.inputImage = input
            f.rVector = CIVector(x: 1.05, y: 0.05, z: 0.05, w: 0)
            f.gVector = CIVector(x: 0, y: 0.92, z: 0.02, w: 0)
            f.bVector = CIVector(x: 0.05, y: 0.02, z: 1.0, w: 0)
            f.biasVector = CIVector(x: 0.04, y: 0, z: 0.03, w: 0)
            return f.outputImage ?? input
        case .warm:
            let f = CIFilter.temperatureAndTint()
            f.inputImage = input
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 4800, y: 0)
            return f.outputImage ?? input
        case .cool:
            let f = CIFilter.temperatureAndTint()
            f.inputImage = input
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 8500, y: 0)
            return f.outputImage ?? input
        case .vivid:
            let f = CIFilter.colorControls()
            f.inputImage = input
            f.saturation = 1.45
            f.contrast = 1.08
            return f.outputImage ?? input
        case .fade:
            let f = CIFilter.photoEffectFade()
            f.inputImage = input
            return f.outputImage ?? input
        case .mono:
            let f = CIFilter.photoEffectMono()
            f.inputImage = input
            return f.outputImage ?? input
        case .noir:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = input
            return f.outputImage ?? input
        }
    }
}

// Colour tweaks on top of the filter (0 = unchanged).
struct ReelAdjust: Equatable {
    var brightness: Double = 0   // -1…1
    var contrast: Double = 0     // -1…1
    var saturation: Double = 0   // -1…1
    var warmth: Double = 0       // -1…1
    var vignette: Double = 0     // 0…1

    var isNeutral: Bool { self == ReelAdjust() }

    func apply(_ input: CIImage) -> CIImage {
        guard !isNeutral else { return input }
        var img = input
        if brightness != 0 || contrast != 0 || saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.brightness = Float(brightness * 0.25)
            f.contrast = Float(1 + contrast * 0.35)
            f.saturation = Float(1 + saturation)
            img = f.outputImage ?? img
        }
        if warmth != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: CGFloat(6500 - warmth * 2200), y: 0)
            img = f.outputImage ?? img
        }
        if vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = img
            f.intensity = Float(vignette * 1.6)
            f.radius = 1.6
            img = f.outputImage ?? img
        }
        return img
    }
}

// The whole look: filter then adjustments.
struct ReelLook: Equatable {
    var filter: ReelFilter = .none
    var adjust = ReelAdjust()
    var isNeutral: Bool { filter == .none && adjust.isNeutral }
    func apply(_ input: CIImage) -> CIImage {
        let extent = input.extent
        return adjust.apply(filter.apply(input.clampedToExtent())).cropped(to: extent)
    }
}

enum StickerFont: String, CaseIterable {
    case bubbly = "Bubbly", cute = "Cute", bold = "Bold", classic = "Classic"
    var uiName: String {
        switch self {
        case .bubbly: return "Bubbly-Regular"
        case .cute: return "CuteHereRegular"
        case .bold: return "PlusJakartaSans-ExtraBold"
        case .classic: return "PlusJakartaSans-SemiBold"
        }
    }
}

enum StickerStyle: String, CaseIterable {
    case plain = "Plain", label = "Label", outline = "Outline", glow = "Glow"
}

// Text (or an emoji, a sticker or a photo) on the video: where it sits (0…1
// of the frame), size, turn, colour, font and style, and when it shows on the
// timeline (seconds from the start of the reel; no end = to the end).
struct TextSticker: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var color: UInt32 = 0xFFFFFF
    var font: StickerFont = .bubbly
    var style: StickerStyle = .label
    var align: NSTextAlignment = .center
    var x: CGFloat = 0.5
    var y: CGFloat = 0.4
    var scale: CGFloat = 1
    var rotation: Double = 0 // radians
    var isEmoji = false
    var image: UIImage? = nil    // picture stickers (vector, your own, GIPHY)
    var start: Double = 0
    var end: Double? = nil
    var framed = false           // photo overlays: rounded with a white edge

    func uiFont(size: CGFloat) -> UIFont {
        if isEmoji { return .systemFont(ofSize: size) }
        return UIFont(name: font.uiName, size: size) ?? .boldSystemFont(ofSize: size)
    }

    var baseSize: CGFloat { image != nil ? (framed ? 0.45 : 0.3) : isEmoji ? 0.16 : 0.075 }

    // Timing on the timeline.
    var isTimed: Bool { start > 0.01 || end != nil }
    func shows(at t: Double) -> Bool { t >= start - 0.01 && (end.map { t < $0 } ?? true) }
    func overlaps(_ from: Double, _ to: Double) -> Bool { start < to - 0.01 && (end.map { $0 > from + 0.01 } ?? true) }

    // Photo overlay edge, as parts of the overlay's width.
    static let frameEdge: CGFloat = 0.03
    static let frameCorner: CGFloat = 0.07

    // Text colour and label colour for the chosen style.
    var inkColor: UInt32 {
        if style == .label { return color == 0xFFFFFF || color == 0xFFD166 || color == 0xFFB3D1 ? 0x2A1620 : 0xFFFFFF }
        return color
    }

    // The sticker drawn as a picture (for baking into the video).
    func render(width: CGFloat) -> UIImage {
        let size = width * baseSize * scale
        if let image {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            if framed {
                let edge = size * Self.frameEdge
                let inner = size - edge * 2
                let innerH = inner * image.size.height / max(1, image.size.width)
                let box = CGSize(width: ceil(size), height: ceil(innerH + edge * 2))
                return UIGraphicsImageRenderer(size: box, format: format).image { _ in
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: CGRect(origin: .zero, size: box), cornerRadius: size * Self.frameCorner).fill()
                    let photo = CGRect(x: edge, y: edge, width: inner, height: innerH)
                    UIBezierPath(roundedRect: photo, cornerRadius: max(0, size * Self.frameCorner - edge)).addClip()
                    image.draw(in: photo)
                }
            }
            let h = size * image.size.height / max(1, image.size.width)
            return UIGraphicsImageRenderer(size: CGSize(width: ceil(size), height: ceil(h)), format: format).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: size, height: h))
            }
        }
        let font = uiFont(size: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(hex: isEmoji ? 0xFFFFFF : inkColor), .paragraphStyle: paragraph]
        if style == .outline && !isEmoji {
            attrs[.strokeColor] = UIColor(hex: color == 0x2A1620 ? 0xFFFFFF : 0x2A1620)
            attrs[.strokeWidth] = -6.0
        }
        let text = NSAttributedString(string: self.text, attributes: attrs)
        let textSize = text.boundingRect(with: CGSize(width: width * 0.9, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).size
        let pad = isEmoji ? size * 0.1 : size * 0.45
        let box = CGSize(width: ceil(textSize.width + pad * 2), height: ceil(textSize.height + pad * 1.2))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: box, format: format).image { ctx in
            if style == .label && !isEmoji {
                UIColor(hex: color).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: box), cornerRadius: size * 0.5).fill()
            }
            if style == .glow && !isEmoji {
                ctx.cgContext.setShadow(offset: .zero, blur: size * 0.5, color: UIColor(hex: color).cgColor)
            } else if style == .plain && !isEmoji {
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: size * 0.04), blur: size * 0.18, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            }
            text.draw(with: CGRect(x: pad, y: pad * 0.6, width: textSize.width + 1, height: textSize.height + 1), options: [.usesLineFragmentOrigin], context: nil)
        }
    }
}

// Film with the phone's camera.
struct CameraCapture: UIViewControllerRepresentable {
    var onVideo: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try? FileManager.default.copyItem(at: url, to: copy)
                parent.onVideo(copy)
            } else {
                parent.onCancel()
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

// A video picked from the library, copied somewhere we can read it.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// Holds what the export needs while the video is rendered frame by frame.
final class RenderBox: @unchecked Sendable {
    struct Timed {
        let image: CIImage
        let start: Double
        let end: Double?
    }
    var look = ReelLook()
    var crop: CGRect?
    var scale: CGFloat = 1
    var overlays: [CIImage] = []
    var timed: [Timed] = []     // overlays that show only part of the time
    var trimStart: Double = 0
}

// MARK: - Reel Studio

// What the studio hands back when it's used to send something in a chat.
enum ChatMedia {
    case photos([UIImage])
    case video(URL, cover: UIImage?)
}

struct ReelStudioView: View {
    enum Step { case pick, edit, post }

    // Chat mode: the same camera and editor, but "Send" instead of posting.
    var chatName: String? = nil
    var onChatSend: ((ChatMedia) -> Void)? = nil
    private var isChat: Bool { onChatSend != nil }

    init() {}

    init(chatName: String, onSend: @escaping (ChatMedia) -> Void) {
        self.chatName = chatName
        self.onChatSend = onSend
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .pick
    @State private var camera = false
    @State private var items: [PhotosPickerItem] = []
    @State private var loadingPick = false

    // what we're editing
    @State private var videoURL: URL?
    @State private var photos: [UIImage] = []
    @State private var asset: AVURLAsset?
    @State private var player = AVPlayer()
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var thumbs: [UIImage] = []
    @State private var look = ReelLook()
    @State private var stickers: [TextSticker] = []
    @State private var tool: EditTool = .filters
    @State private var history: [Snapshot] = []
    @State private var draggingSticker = false
    @State private var overTrash = false
    @State private var previewPhotos: [UIImage] = []
    @State private var soundVolume: Double = 1
    @State private var originalVolume: Double = 1
    @State private var strokes: [DrawStroke] = []
    @State private var drawing: DrawStroke?
    @State private var penColor: UInt32 = 0xFFFFFF
    @State private var penWidth: CGFloat = 0.012
    @State private var penNeon = false
    // timeline
    @State private var playhead: Double = 0         // seconds from the start of the reel
    @State private var isPlaying = false
    @State private var slideSeconds: [Double] = []  // how long each photo shows
    @State private var slideTask: Task<Void, Never>?
    @State private var timelineThumbs: [UIImage] = []
    @State private var timelineThumbKey = ""
    @State private var selectedOverlay: UUID?
    @State private var selectedSlide: Int?
    @State private var overlayItem: PhotosPickerItem?
    @State private var resumeAfterScrub = false

    enum EditTool: String, CaseIterable {
        case trim = "Trim", timeline = "Timeline", crop = "Crop", filters = "Filters", adjust = "Adjust", text = "Text", stickers = "Stickers", draw = "Draw", sound = "Sound"
        var icon: String {
            switch self {
            case .trim: return "scissors"
            case .timeline: return "film.stack"
            case .crop: return "crop"
            case .filters: return "camera.filters"
            case .adjust: return "slider.horizontal.3"
            case .text: return "textformat"
            case .stickers: return "star.square.on.square.fill"
            case .draw: return "scribble.variable"
            case .sound: return "music.note"
            }
        }
    }

    struct Snapshot { var look: ReelLook; var stickers: [TextSticker]; var strokes: [DrawStroke] = []; var photos: [UIImage] = []; var videoCrop: CGRect? = nil; var slideSeconds: [Double] = [] }
    @State private var videoCrop: CGRect?
    @State private var cropJob: EditorCrop?
    @State private var editingText: TextSticker?
    @State private var sound: Track?
    @State private var soundPlayer: AVPlayer?
    @State private var choosingSound = false
    @State private var muteOriginal = false
    @State private var slide = 0
    @State private var timeObserver: Any?

    // posting
    @State private var caption = ""
    @State private var allowComments = true
    @State private var drafts: [Drafts.Reel] = []
    @State private var draftId: String?
    @State private var askDraft = false
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .pick: pickScreen
            case .edit: editScreen
            case .post: postScreen
            }
        }
        .overlay { chatBusyOverlay }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .fullScreenCover(isPresented: $camera) {
            RecorderView(sound: $sound, onVideo: { url in
                camera = false
                Task { await openVideo(url) }
            }, onPhotos: { images in
                camera = false
                openPhotos(images)
            }, onClose: { camera = false })
        }
        .sheet(item: $editingText) { sticker in
            TextStickerEditor(sticker: sticker) { updated in
                if let i = stickers.firstIndex(where: { $0.id == updated.id }) { stickers[i] = updated } else { stickers.append(updated) }
            } onDelete: { id in stickers.removeAll { $0.id == id } }
            .presentationDetents([.height(470), .large])
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $choosingSound) {
            SoundPicker { track in
                sound = track
                startSound()
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(30)
        }
        .onChange(of: items) { _, list in Task { await loadPicked(list) } }
        .onChange(of: overlayItem) { _, item in
            guard let item else { return }
            Task {
                defer { overlayItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                addPhotoOverlay(Self.overlayPicture(image))
            }
        }
        .onChange(of: look) { _, _ in applyPreviewFilter() }
        .fullScreenCover(item: $cropJob) { job in
            ImageCropper(image: job.image, circle: false, aspect: 9 / 16, choices: CropAspect.editor, title: "Move and pinch to crop", onDone: { rect in
                cropJob = nil
                applyCrop(job, rect)
            }, onCancel: { cropJob = nil })
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("Save this reel as a draft?", isPresented: $askDraft, titleVisibility: .visible) {
            Button("Save draft") {
                saveDraft()
                resetToPick()
            }
            Button("Discard", role: .destructive) { resetToPick() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear {
            drafts = Drafts.reels()
            if let requested = model.soundRequest {
                sound = requested
                model.soundRequest = nil
            }
        }
        .onDisappear { teardown() }
    }

    // MARK: step 1 — pick

    private var pickScreen: some View {
        VStack(spacing: 22) {
            topBar(title: chatName.map { "Send to \($0)" } ?? "New reel", back: { dismiss() }, next: nil)
            Spacer()
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 190, height: 190).blur(radius: 50).opacity(0.7)
                Image(systemName: "video.fill")
                    .font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 130, height: 130)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .shadow(color: Theme.pink.opacity(0.6), radius: 24, y: 10)
            }
            Text(isChat ? "Snap or film something" : "Make something cute").font(.display(34)).foregroundStyle(.white)
            if let sound {
                Label("Using \(sound.title) · \(sound.artist)", systemImage: "music.note")
                    .font(.jakarta(13, .bold)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Theme.gradient, in: Capsule())
                    .padding(.horizontal, 30)
            }
            Text("Film in clips (pause, delete, start over), snap photos, or pick from your library.")
                .font(.jakarta(15)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            if loadingPick {
                ProgressView().tint(.white).padding()
            }
            if !drafts.isEmpty && !isChat {
                DraftStrip(title: "Drafts", items: drafts, dark: true, thumb: { Drafts.reelCover($0) },
                           label: { d in d.caption.isEmpty ? d.saved.formatted(date: .abbreviated, time: .omitted) : d.caption },
                           onOpen: { d in Task { await openDraft(d) } },
                           onDelete: { d in Drafts.delete("reels", d.id); drafts = Drafts.reels() })
                    .padding(.horizontal, 24)
            }
            VStack(spacing: 12) {
                Button { camera = true } label: { Label("Open camera", systemImage: "camera.fill") }
                    .buttonStyle(GradientButtonStyle(height: 56))
                PhotosPicker(selection: $items, maxSelectionCount: 10, matching: .any(of: [.videos, .images])) {
                    Label("Choose from library", systemImage: "photo.on.rectangle.angled")
                        .font(.jakarta(15, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(.white.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.96))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    // MARK: step 2 — edit

    private var editScreen: some View {
        VStack(spacing: 10) {
            editTopBar
            GeometryReader { geo in
                ZStack {
                    if asset != nil {
                        VideoPlayerLayer(player: player).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    } else if !photos.isEmpty {
                        let shown = previewPhotos.count == photos.count ? previewPhotos : photos
                        TabView(selection: $slide) {
                            ForEach(shown.indices, id: \.self) { i in
                                Image(uiImage: shown[i]).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped().tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .allowsHitTesting(false)
                    }
                    DrawingLayer(strokes: strokes, current: drawing)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    StickerCanvas(stickers: $stickers, size: geo.size, onEdit: { sticker in
                        selectedOverlay = sticker.id
                        guard sticker.image == nil else { return }
                        checkpoint()
                        editingText = sticker
                    }, onTapEmpty: {
                        togglePlay()
                    }, onSwipe: { step in
                        guard !photos.isEmpty else { return }
                        withAnimation(.snappy) { slide = min(photos.count - 1, max(0, slide + step)) }
                        let b = ReelTimeline.bounds(slideSeconds)
                        if b.indices.contains(slide) { playhead = b[slide] }
                    }, onBegin: { checkpoint() }, isShown: { overlayShown($0) })
                    if tool == .draw {
                        DrawCapture(strokes: $strokes, current: $drawing, color: penColor, width: penWidth, neon: penNeon) { checkpoint() }
                    }
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)

            toolPanel
                .frame(height: tool == .timeline ? 256 : tool == .trim ? 132 : 118)
                .animation(.snappy, value: tool)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditTool.allCases.filter { $0 != .trim || asset != nil }, id: \.self) { t in
                        Button {
                            withAnimation(.snappy) { tool = t }
                            if t == .text { checkpoint(); editingText = TextSticker(text: "") }
                            if t == .timeline { Task { await refreshTimelineThumbs() } }
                            if t == .sound && sound == nil { choosingSound = true }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: t.icon).font(.system(size: 18, weight: .bold))
                                Text(t.rawValue).font(.jakarta(11, .bold))
                            }
                            .foregroundStyle(tool == t ? .white : .white.opacity(0.65))
                            .frame(width: 66, height: 56)
                            .background {
                                if tool == t {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.gradient)
                                        .shadow(color: Theme.pink.opacity(0.45), radius: 8, y: 3)
                                } else {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.1))
                                }
                            }
                        }
                        .buttonStyle(BouncyStyle(scale: 0.9))
                    }
                }
                .padding(.horizontal, 16)
            }
            .sensoryFeedback(.selection, trigger: tool)
        }
        .padding(.bottom, 10)
        .onAppear { if asset == nil && tool == .trim { tool = .filters } }
    }

    private var editTopBar: some View {
        HStack(spacing: 10) {
            Button { if isChat { resetToPick() } else { askDraft = true } } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(BouncyStyle())
            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(history.isEmpty ? 0.35 : 1))
                    .frame(width: 42, height: 42).background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(BouncyStyle())
            .disabled(history.isEmpty)
            Spacer()
            Text("Edit").font(.display(24)).foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 42, height: 42)
            if isChat {
                Button { Task { await sendToChat() } } label: { Label("Send", systemImage: "paperplane.fill") }
                    .buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
                    .disabled(busy)
            } else {
                Button("Next") { goToPost() }.buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch tool {
        case .trim:
            if asset != nil {
                TrimBar(thumbs: thumbs, duration: duration, start: $trimStart, end: $trimEnd,
                        onSeek: { t in player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) },
                        onScrub: { began in
                            if !began { seek(to: 0) }
                            scrubbing(began)
                        })
                    .padding(.horizontal, 16)
            }
        case .timeline:
            ReelTimeline(length: timelineLength, playhead: playhead, playing: isPlaying,
                         thumbs: timelineThumbs.isEmpty ? thumbs : timelineThumbs,
                         slides: asset == nil ? (previewPhotos.count == photos.count ? previewPhotos : photos) : [],
                         slideSeconds: $slideSeconds, stickers: $stickers,
                         selected: $selectedOverlay, selectedSlide: $selectedSlide, photoItem: $overlayItem,
                         onSeek: { seek(to: $0) },
                         onScrub: { began in scrubbing(began) },
                         onTogglePlay: { togglePlay() },
                         onAddText: {
                             checkpoint()
                             let timing = newOverlayTiming()
                             editingText = TextSticker(text: "", start: timing.start, end: timing.end)
                         },
                         onAddSticker: { withAnimation(.snappy) { tool = .stickers } },
                         onEditText: { sticker in checkpoint(); editingText = sticker },
                         onCheckpoint: { checkpoint() },
                         onMoveSlide: { moveSlide($0, $1) },
                         onDeleteSlide: { deleteSlide($0) })
        case .filters:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ReelFilter.allCases) { f in
                        Button { checkpoint(); look.filter = f } label: {
                            VStack(spacing: 6) {
                                filterThumb(f)
                                    .frame(width: 58, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: look.filter == f ? 3 : 0))
                                    .shadow(color: look.filter == f ? Theme.pink.opacity(0.7) : .clear, radius: 8)
                                Text(f.rawValue).font(.jakarta(11, .bold)).foregroundStyle(.white.opacity(look.filter == f ? 1 : 0.7))
                            }
                        }
                        .buttonStyle(BouncyStyle(scale: 0.88))
                    }
                }
                .padding(.horizontal, 16)
            }
            .sensoryFeedback(.selection, trigger: look.filter)
        case .crop:
            VStack(spacing: 10) {
                Text(asset != nil ? (videoCrop == nil ? "Crop the video to a new shape" : "Video cropped") : "Crop photo \(slide + 1) of \(photos.count) — swipe to pick another")
                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 10) {
                    Button { Task { await startCrop() } } label: { Label(asset != nil ? "Crop video" : "Crop photo", systemImage: "crop") }
                        .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
                    if asset != nil && videoCrop != nil {
                        Button {
                            checkpoint()
                            videoCrop = nil
                            applyPreviewFilter()
                        } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(OutlineButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        case .draw:
            DrawPanel(color: $penColor, width: $penWidth, neon: $penNeon, canUndo: !strokes.isEmpty, onUndo: {
                checkpoint()
                _ = strokes.popLast()
            }, onClear: {
                checkpoint()
                withAnimation { strokes.removeAll() }
            })
        case .adjust:
            ScrollView {
                VStack(spacing: 6) {
                    adjustRow("Brightness", "sun.max.fill", $look.adjust.brightness, -1...1)
                    adjustRow("Contrast", "circle.lefthalf.filled", $look.adjust.contrast, -1...1)
                    adjustRow("Saturation", "drop.fill", $look.adjust.saturation, -1...1)
                    adjustRow("Warmth", "thermometer.sun.fill", $look.adjust.warmth, -1...1)
                    adjustRow("Vignette", "camera.aperture", $look.adjust.vignette, 0...1)
                    Button("Reset adjustments") { checkpoint(); look.adjust = ReelAdjust() }
                        .font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                }
                .padding(.horizontal, 16)
            }
        case .text:
            VStack(spacing: 10) {
                Text(stickers.contains { !$0.isEmoji && $0.image == nil } ? "Drag with one or two fingers · pinch to resize · twist to turn · tap to edit · drop on the bin to delete" : "Add some words to your reel")
                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                Button { checkpoint(); editingText = TextSticker(text: "") } label: { Label("Add text", systemImage: "plus") }
                    .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        case .stickers:
            StickerTray { image in
                checkpoint()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    stickers.append(TextSticker(text: "", x: CGFloat.random(in: 0.3...0.7), y: CGFloat.random(in: 0.3...0.6), image: image))
                }
            }
        case .sound:
            VStack(spacing: 8) {
                HStack {
                    if let sound {
                        Label("\(sound.title) · \(sound.artist)", systemImage: "music.note")
                            .font(.jakarta(12, .semibold)).foregroundStyle(.white).lineLimit(1)
                    } else {
                        Text("No sound yet").font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button(sound == nil ? "Add sound" : "Change") { choosingSound = true }
                        .font(.jakarta(12, .heavy)).foregroundStyle(Theme.pink)
                    if sound != nil {
                        Button { sound = nil; soundPlayer?.pause(); soundPlayer = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6)) }
                    }
                }
                if sound != nil {
                    adjustRow("Song", "music.note", $soundVolume, 0...1)
                }
                if asset != nil {
                    adjustRow("Original", "waveform", $originalVolume, 0...1)
                }
            }
            .padding(.horizontal, 16)
            .onChange(of: soundVolume) { _, v in soundPlayer?.volume = Float(v) }
            .onChange(of: originalVolume) { _, v in
                player.volume = Float(v)
                muteOriginal = v < 0.02
            }
        }
    }

    private func filterThumb(_ f: ReelFilter) -> some View {
        Group {
            if let base = thumbs.first ?? photos.first {
                Image(uiImage: FilterThumbs.make(base, f)).resizable().scaledToFill()
            } else {
                LinearGradient(colors: f.swatch, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private func adjustRow(_ title: String, _ icon: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.pink).frame(width: 20)
            Text(title).font(.jakarta(12, .bold)).foregroundStyle(.white).frame(width: 78, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { checkpoint() } })
                .tint(Theme.pink)
            Text("\(Int((value.wrappedValue * 100).rounded()))").font(.jakarta(11, .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 34, alignment: .trailing)
        }
    }

    private func checkpoint() {
        history.append(Snapshot(look: look, stickers: stickers, strokes: strokes, photos: photos, videoCrop: videoCrop, slideSeconds: slideSeconds))
        if history.count > 40 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        withAnimation(.snappy) {
            look = last.look
            stickers = last.stickers
            strokes = last.strokes
        }
        let photosChanged = asset == nil && !last.photos.isEmpty && (last.photos.count != photos.count || !zip(last.photos, photos).allSatisfy { $0 === $1 })
        let cropChanged = last.videoCrop != videoCrop || photosChanged
        videoCrop = last.videoCrop
        if asset == nil && !last.photos.isEmpty {
            photos = last.photos
            if last.slideSeconds.count == last.photos.count { slideSeconds = last.slideSeconds }
            slide = min(slide, max(0, photos.count - 1))
            selectedSlide = nil
        }
        if cropChanged { applyPreviewFilter() }
    }

    // MARK: step 3 — post

    private var postScreen: some View {
        VStack(spacing: 16) {
            topBar(title: "Post", back: { withAnimation { step = .edit }; if asset != nil { startPlayback() } }, next: nil)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Group {
                            if let first = photos.first {
                                Image(uiImage: first).resizable().scaledToFill()
                            } else if let thumb = thumbs.first {
                                Image(uiImage: thumb).resizable().scaledToFill()
                            } else {
                                Theme.gradient
                            }
                        }
                        .frame(width: 96, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(asset != nil ? "\(Int(trimEnd - trimStart))s video" : "Slideshow of \(photos.count) pictures").font(.jakarta(13, .bold)).foregroundStyle(Theme.pink)
                            TextField("Write a caption… #tags", text: $caption, axis: .vertical)
                                .font(.jakarta(15)).foregroundStyle(.white).lineLimit(4...8)
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Button { withAnimation(.snappy) { allowComments.toggle() } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow comments").font(.jakarta(15, .bold)).foregroundStyle(.white)
                                Text("You can change this later").font(.jakarta(12)).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Capsule().fill(allowComments ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.2)))
                                .frame(width: 52, height: 32)
                                .overlay(alignment: allowComments ? .trailing : .leading) { Circle().fill(.white).frame(width: 26, height: 26).padding(3) }
                        }
                        .padding(14)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            HStack(spacing: 10) {
                Button { saveDraft(); dismiss() } label: { Label("Draft", systemImage: "tray.and.arrow.down.fill") }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(busy)
                Button { Task { await post() } } label: {
                    if busy {
                        HStack(spacing: 10) { ProgressView().tint(.white); Text(status) }
                    } else {
                        Label("Post reel", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(GradientButtonStyle(height: 56))
                .disabled(busy)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .interactiveDismissDisabled(busy)
    }

    private func topBar(title: String, back: @escaping () -> Void, next: (() -> Void)?) -> some View {
        HStack {
            Button(action: back) {
                Image(systemName: step == .pick ? "xmark" : "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(BouncyStyle())
            Spacer()
            Text(title).font(.display(24)).foregroundStyle(.white)
            Spacer()
            if let next {
                Button("Next", action: next).buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: loading

    private func loadPicked(_ list: [PhotosPickerItem]) async {
        guard !list.isEmpty else { return }
        loadingPick = true
        defer { loadingPick = false; items = [] }
        if let first = list.first, first.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let movie = try? await first.loadTransferable(type: PickedMovie.self) { await openVideo(movie.url) }
            return
        }
        var images: [UIImage] = []
        for item in list {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
        }
        guard !images.isEmpty else { return }
        openPhotos(images)
    }

    private func openPhotos(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        photos = images.map(Self.prepare)
        slideSeconds = Array(repeating: 3, count: photos.count)
        previewPhotos = []
        asset = nil
        slide = 0
        playhead = 0
        selectedOverlay = nil
        selectedSlide = nil
        tool = .filters
        applyPreviewFilter()
        withAnimation { step = .edit }
        if sound != nil { startSound() }
    }

    // MARK: crop

    private func startCrop() async {
        if let asset {
            pausePlayback()
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1400, height: 1400)
            let at = CMTime(seconds: max(trimStart, player.currentTime().seconds.isFinite ? player.currentTime().seconds : trimStart), preferredTimescale: 600)
            guard let frame = try? await generator.image(at: at) else { return }
            cropJob = EditorCrop(image: UIImage(cgImage: frame.image), slide: nil)
        } else if photos.indices.contains(slide) {
            cropJob = EditorCrop(image: photos[slide], slide: slide)
        }
    }

    private func applyCrop(_ job: EditorCrop, _ rect: CGRect) {
        checkpoint()
        if let i = job.slide, photos.indices.contains(i) {
            photos[i] = Cropping.crop(photos[i], rect, maxSide: 2048)
        } else {
            videoCrop = rect
            player.play()
        }
        applyPreviewFilter()
    }

    // MARK: drafts

    private func saveDraft() {
        let state = Drafts.ReelState(caption: caption, allowComments: allowComments, look: look,
                                     trimStart: trimStart, trimEnd: trimEnd, sound: sound, soundVolume: soundVolume,
                                     originalVolume: originalVolume, video: asset != nil ? videoURL : nil,
                                     photos: asset == nil ? photos : [], cover: thumbs.first, stickers: stickers, strokes: strokes, videoCrop: videoCrop,
                                     slideSeconds: asset == nil ? slideSeconds : [])
        draftId = Drafts.saveReel(id: draftId, state)
        drafts = Drafts.reels()
        model.showToast("Saved to drafts", icon: "tray.and.arrow.down.fill")
    }

    private func openDraft(_ d: Drafts.Reel) async {
        let restored = Drafts.restore(d)
        draftId = d.id
        sound = restored.sound
        soundVolume = d.soundVolume
        originalVolume = d.originalVolume
        if let url = Drafts.reelVideo(d) {
            await openVideo(url)
            trimStart = min(d.trimStart, max(0, duration - 1))
            trimEnd = min(duration, max(trimStart + 1, d.trimEnd))
            player.volume = Float(originalVolume)
            muteOriginal = originalVolume < 0.02
        } else {
            let pics = Drafts.reelPhotos(d)
            guard !pics.isEmpty else { error = "That draft is empty."; return }
            openPhotos(pics)
            if let secs = d.slideSeconds, secs.count == photos.count { slideSeconds = secs }
        }
        look = restored.look
        stickers = restored.stickers
        strokes = restored.strokes
        caption = d.caption
        allowComments = d.allowComments
        if let c = d.crop, c.count == 4 { videoCrop = CGRect(x: c[0], y: c[1], width: c[2], height: c[3]) }
        history = []
        applyPreviewFilter()
    }

    private func openVideo(_ url: URL) async {
        let a = AVURLAsset(url: url)
        let seconds = (try? await a.load(.duration).seconds) ?? 0
        guard seconds > 0.3 else { error = "That video couldn't be opened."; return }
        videoCrop = nil
        videoURL = url
        asset = a
        duration = seconds
        trimStart = 0
        trimEnd = min(seconds, 60)
        photos = []
        slideSeconds = []
        playhead = 0
        selectedOverlay = nil
        selectedSlide = nil
        timelineThumbs = []
        timelineThumbKey = ""
        tool = .trim
        let item = AVPlayerItem(asset: a)
        player.replaceCurrentItem(with: item)
        applyPreviewFilter()
        loopPreview()
        player.play()
        isPlaying = true
        withAnimation { step = .edit }
        if sound != nil { startSound() }
        await makeThumbs(a, seconds: seconds)
    }

    private func makeThumbs(_ a: AVURLAsset, seconds: Double) async {
        let generator = AVAssetImageGenerator(asset: a)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        var out: [UIImage] = []
        for i in 0..<8 {
            let t = CMTime(seconds: seconds * Double(i) / 8, preferredTimescale: 600)
            if let result = try? await generator.image(at: t) { out.append(UIImage(cgImage: result.image)) }
        }
        thumbs = out
    }

    private func applyPreviewFilter() {
        let chosen = look
        if asset == nil {
            // Slideshow: redraw the pictures with the look.
            let originals = photos
            Task {
                let out = await FilterThumbs.applyAll(chosen, to: originals)
                if chosen == look { previewPhotos = out }
            }
            return
        }
        guard let asset, let item = player.currentItem else { return }
        let crop = videoCrop
        item.videoComposition = chosen.isNeutral && crop == nil ? nil : AVMutableVideoComposition(asset: asset) { request in
            var img = request.sourceImage
            if let crop { img = VideoCrop.fill(VideoCrop.cut(img, crop), request.renderSize) }
            if !chosen.isNeutral { img = chosen.apply(img) }
            request.finish(with: img, context: nil)
        }
    }

    private func loopPreview() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            MainActor.assumeIsolated {
                if time.seconds >= trimEnd || time.seconds < trimStart - 0.2 {
                    player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
                    soundPlayer?.seek(to: .zero)
                }
                let playingNow = player.rate != 0
                if playingNow != isPlaying { isPlaying = playingNow }
                // The playhead only needs to move for the timeline and for
                // overlays that come and go.
                if tool == .timeline || stickers.contains(where: { $0.isTimed }) {
                    let at = min(max(0, time.seconds - trimStart), timelineLength)
                    if abs(at - playhead) > 0.02 { playhead = at }
                }
            }
        }
    }

    private func startSound() {
        soundPlayer?.pause()
        guard let sound, let url = URL(string: sound.audioURL) else { return }
        let p = AVPlayer(url: url)
        p.volume = Float(soundVolume)
        p.play()
        soundPlayer = p
        player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
    }

    private func resetToPick() {
        pausePlayback()
        asset = nil
        photos = []
        slideSeconds = []
        playhead = 0
        selectedOverlay = nil
        selectedSlide = nil
        stickers = []
        strokes = []
        sound = nil
        look = ReelLook()
        caption = ""
        history = []
        videoCrop = nil
        draftId = nil
        drafts = Drafts.reels()
        withAnimation { step = .pick }
    }

    private func goToPost() {
        pausePlayback()
        selectedOverlay = nil
        withAnimation { step = .post }
    }

    // Runs when posting and again when the screen closes, so it must be safe
    // twice: AVPlayer crashes the app if the same time observer is removed
    // two times (that was the crash right after posting a video).
    private func teardown() {
        slideTask?.cancel()
        player.pause()
        soundPlayer?.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    // MARK: timeline

    private var timelineLength: Double {
        asset != nil ? max(0.1, trimEnd - trimStart) : max(0.1, slideSeconds.reduce(0, +))
    }

    // Overlays show only in their time: on a video at the playhead, on a
    // slideshow on the slides they cover.
    private func overlayShown(_ s: TextSticker) -> Bool {
        if asset != nil { return s.shows(at: playhead) }
        let b = ReelTimeline.bounds(slideSeconds)
        guard slideSeconds.count == photos.count, b.count > slide + 1 else { return true }
        return s.overlaps(b[slide], b[slide + 1])
    }

    private func slideIndex(at t: Double) -> Int {
        let b = ReelTimeline.bounds(slideSeconds)
        let i = b.lastIndex(where: { $0 <= t + 0.001 }) ?? 0
        return max(0, min(photos.count - 1, i))
    }

    private func seek(to t: Double) {
        let t = min(max(0, t), timelineLength)
        playhead = t
        if asset != nil {
            player.seek(to: CMTime(seconds: trimStart + t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            let i = slideIndex(at: t)
            if i != slide { slide = i }
        }
        soundPlayer?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    }

    private func scrubbing(_ began: Bool) {
        if began {
            resumeAfterScrub = isPlaying
            if isPlaying { pausePlayback() }
        } else if resumeAfterScrub {
            resumeAfterScrub = false
            startPlayback()
        }
    }

    private func togglePlay() {
        if isPlaying { pausePlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        if asset != nil {
            player.play()
            soundPlayer?.play()
            isPlaying = true
        } else if !photos.isEmpty {
            playSlides()
        }
    }

    private func pausePlayback() {
        isPlaying = false
        slideTask?.cancel()
        slideTask = nil
        player.pause()
        soundPlayer?.pause()
    }

    // Slideshows play by themselves: each photo for its own length.
    private func playSlides() {
        slideTask?.cancel()
        isPlaying = true
        if playhead >= timelineLength - 0.05 { seek(to: 0) }
        soundPlayer?.play()
        slideTask = Task {
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { break }
                let now = Date()
                var next = playhead + now.timeIntervalSince(last)
                last = now
                if next >= timelineLength {
                    next = 0
                    soundPlayer?.seek(to: .zero, completionHandler: { _ in })
                }
                playhead = next
                let i = slideIndex(at: next)
                if i != slide { withAnimation(.easeInOut(duration: 0.3)) { slide = i } }
            }
        }
    }

    // New overlays from the timeline: 3 seconds from the playhead, or the
    // slide you're on.
    private func newOverlayTiming() -> (start: Double, end: Double?) {
        if asset == nil {
            let b = ReelTimeline.bounds(slideSeconds)
            guard slideSeconds.count == photos.count, b.count > slide + 1 else { return (0, nil) }
            let end = b[slide + 1]
            return (b[slide], end >= (b.last ?? 0) - 0.01 ? nil : end)
        }
        let length = timelineLength
        let start = max(0, min(playhead, length - 3))
        let end = start + 3
        return (start, end >= length - 0.05 ? nil : end)
    }

    private func addPhotoOverlay(_ image: UIImage) {
        checkpoint()
        let timing = newOverlayTiming()
        let overlay = TextSticker(text: "", x: 0.5, y: 0.42, image: image, start: timing.start, end: timing.end, framed: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { stickers.append(overlay) }
        selectedOverlay = overlay.id
        selectedSlide = nil
    }

    // Photos on top of the reel: upright and no bigger than they need to be
    // (see-through parts stay see-through).
    nonisolated static func overlayPicture(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height, 1)
        let scale = min(1, 1200 / longest)
        let target = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func moveSlide(_ i: Int, _ j: Int) {
        guard photos.indices.contains(i), photos.indices.contains(j), slideSeconds.count == photos.count else { return }
        checkpoint()
        let old = ReelTimeline.bounds(slideSeconds)
        withAnimation(.snappy) {
            photos.swapAt(i, j)
            if previewPhotos.count == photos.count { previewPhotos.swapAt(i, j) }
            slideSeconds.swapAt(i, j)
            ReelTimeline.remap(&stickers, from: old, to: ReelTimeline.bounds(slideSeconds))
        }
        selectedSlide = j
        slide = j
        playhead = ReelTimeline.bounds(slideSeconds)[j]
    }

    private func deleteSlide(_ i: Int) {
        guard photos.count > 1, photos.indices.contains(i), slideSeconds.count == photos.count else { return }
        checkpoint()
        let b = ReelTimeline.bounds(slideSeconds)
        let newLength = (b.last ?? 0) - slideSeconds[i]
        withAnimation(.snappy) {
            photos.remove(at: i)
            if previewPhotos.count == photos.count + 1 { previewPhotos.remove(at: i) }
            slideSeconds.remove(at: i)
            ReelTimeline.removeSlide(&stickers, from: b[i], to: b[i + 1], newLength: newLength)
        }
        selectedSlide = nil
        slide = min(slide, photos.count - 1)
        playhead = ReelTimeline.bounds(slideSeconds)[slide]
    }

    // Film strip of just the trimmed part, for the timeline.
    private func refreshTimelineThumbs() async {
        guard let asset else { return }
        let key = "\(Int(trimStart * 10))-\(Int(trimEnd * 10))"
        guard key != timelineThumbKey else { return }
        timelineThumbKey = key
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let count = 10
        var out: [UIImage] = []
        for i in 0..<count {
            let t = trimStart + (trimEnd - trimStart) * (Double(i) + 0.5) / Double(count)
            if let result = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) { out.append(UIImage(cgImage: result.image)) }
        }
        if key == timelineThumbKey { timelineThumbs = out }
    }

    // MARK: export + post

    private func post() async {
        guard let me = model.me else { return }
        guard !Moderation.hasLink(caption) else { error = "Links aren't allowed in captions."; return }
        guard await TextGuard.clear([caption], kind: .caption, model: model) else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            var mediaURL = ""
            var mediaURLs: [String] = []
            var coverURL = ""
            var kind = "image"
            var length = 0.0
            if let asset {
                kind = "video"
                status = "Making your video…"
                let exported = try await exportVideo(asset)
                let data = try Data(contentsOf: exported)
                guard data.count < 58 * 1024 * 1024 else { throw APIError(message: "That video is too big — trim it a little shorter.") }
                status = "Uploading…"
                mediaURL = try await StorageClient.upload(data, contentType: "video/mp4", fileExtension: "mp4")
                if let cover = await coverImage(asset), let jpeg = ImageTools.jpeg(cover, maxSide: 1080) {
                    coverURL = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
                }
                length = trimEnd - trimStart
            } else {
                status = "Uploading pictures…"
                for (i, photo) in photos.enumerated() {
                    let baked = bake(photo, slide: i)
                    if let jpeg = ImageTools.jpeg(baked, maxSide: 1600) {
                        mediaURLs.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                    }
                }
                mediaURL = mediaURLs.first ?? ""
                coverURL = mediaURL
                length = slideSeconds.count == photos.count ? slideSeconds.reduce(0, +) : Double(photos.count * 3)
            }
            status = "Posting…"
            let now = FS.nowISO()
            var source = ""
            if let sound, sound.id.hasPrefix("deezer_") { source = "deezer:" + sound.id.replacingOccurrences(of: "deezer_", with: "") }
            var edits: [String: Any] = [:]
            if asset == nil, slideSeconds.count == photos.count, slideSeconds.contains(where: { abs($0 - 3) > 0.01 }) {
                edits["slide_durations"] = slideSeconds
            }
            let doc: Doc = [
                "kind": kind, "media_url": mediaURL, "media_urls": mediaURLs.count > 1 ? mediaURLs : [String](),
                "cover_url": coverURL, "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
                "music_title": sound?.title ?? "", "music_artist": sound?.artist ?? "", "music_url": sound?.audioURL ?? "",
                "music_source": source, "duration": (length * 10).rounded() / 10, "edits": edits,
                "comments_off": !allowComments, "likes": [String](), "views": 0,
                "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
                "created_by": me.email, "created_date": now, "updated_date": now,
            ]
            let created = try await FS.create("Reel", doc)
            // Show it at the top of your feed right away.
            NotificationCenter.default.post(name: ReelsView.posted, object: Reel(created))
            model.tabRequest = .reels
            if let draftId { Drafts.delete("reels", draftId) }
            try? await model.updateMe(["xp": me.xp + 30, "coins": me.coins + 5])
            teardown()
            dismiss()
            model.showToast("Your reel is live! +30 XP", icon: "play.rectangle.fill")
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private var chatBusyOverlay: some View {
        if isChat && (busy || error != nil) {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 12) {
                    if busy { ProgressView().tint(.white).controlSize(.large) }
                    Text(busy ? (status.isEmpty ? "Getting it ready…" : status) : (error ?? "")).font(.jakarta(15, .bold)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if !busy { Button("OK") { error = nil }.buttonStyle(GradientButtonStyle(height: 40, fullWidth: false)) }
                }
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    // Chat mode: finish the edits and hand the result to the chat.
    private func sendToChat() async {
        guard let onChatSend else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if let asset {
                status = "Making your video…"
                let exported = try await exportVideo(asset)
                let cover = await coverImage(asset)
                onChatSend(.video(exported, cover: cover))
            } else {
                guard !photos.isEmpty else { return }
                status = "Getting your photos ready…"
                onChatSend(.photos(photos.enumerated().map { bake($1, slide: $0) }))
            }
            teardown()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func coverImage(_ asset: AVURLAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        guard let result = try? await generator.image(at: CMTime(seconds: trimStart + 0.1, preferredTimescale: 600)) else { return nil }
        var frame = UIImage(cgImage: result.image)
        if let videoCrop { frame = Cropping.crop(frame, videoCrop, maxSide: 1920) }
        return bake(frame, at: 0.1)
    }

    // Filter + text stickers drawn onto a picture.
    // Every photo made upright, solid (see-through parts turn white, like
    // other apps, instead of black once saved as JPEG) and no bigger than
    // 2048 px, so it previews, filters, crops and posts the same way.
    nonisolated static func prepare(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height, 1)
        let scale = min(1, 2048 / longest)
        let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // With a slide, only the overlays timed onto that slide; with a time,
    // only the ones showing then.
    private func bake(_ image: UIImage, slide: Int? = nil, at time: Double? = nil) -> UIImage {
        guard !look.isNeutral || !stickers.isEmpty || !strokes.isEmpty, let cg = image.cgImage else { return image }
        let showing = overlayFilter(slide: slide, at: time)
        var ci = CIImage(cgImage: cg)
        ci = look.apply(ci)
        for overlay in overlayImages(width: ci.extent.width, height: ci.extent.height, showing: showing) { ci = overlay.composited(over: ci) }
        let context = CIContext()
        guard let out = context.createCGImage(ci, from: ci.extent) else { return image }
        return UIImage(cgImage: out)
    }

    private func overlayFilter(slide: Int?, at time: Double?) -> (TextSticker) -> Bool {
        if let slide {
            let b = ReelTimeline.bounds(slideSeconds)
            guard slideSeconds.count == photos.count, b.count > slide + 1 else { return { _ in true } }
            let from = b[slide], to = b[slide + 1]
            return { $0.overlaps(from, to) }
        }
        if let time { return { $0.shows(at: time) } }
        return { _ in true }
    }

    private func overlayImages(width: CGFloat, height: CGFloat, showing: (TextSticker) -> Bool = { _ in true }) -> [CIImage] {
        var out: [CIImage] = []
        if let doodle = doodleImage(width: width, height: height) { out.append(doodle) }
        return out + stickers.filter(showing).compactMap { stickerImage($0, width: width, height: height) }
    }

    private func doodleImage(width: CGFloat, height: CGFloat) -> CIImage? {
        Doodle.render(strokes, size: CGSize(width: width, height: height))?.cgImage.map { CIImage(cgImage: $0) }
    }

    private func stickerImage(_ sticker: TextSticker, width: CGFloat, height: CGFloat) -> CIImage? {
        guard !sticker.text.isEmpty || sticker.image != nil, let cg = sticker.render(width: width).cgImage else { return nil }
        let img = CIImage(cgImage: cg)
        let w = img.extent.width, h = img.extent.height
        // Centre on the origin, turn (Core Image's y axis points up, so
        // the angle flips), then move into place.
        let centred = CGAffineTransform(translationX: -w / 2, y: -h / 2)
        let turned = centred.concatenating(CGAffineTransform(rotationAngle: -CGFloat(sticker.rotation)))
        let placed = turned.concatenating(CGAffineTransform(translationX: sticker.x * width, y: (1 - sticker.y) * height))
        return img.transformed(by: placed)
    }

    private func exportVideo(_ asset: AVURLAsset) async throws -> URL {
        let box = RenderBox()
        box.look = look
        box.crop = videoCrop
        box.trimStart = trimStart
        let composition = AVMutableVideoComposition(asset: asset) { request in
            var img = request.sourceImage
            if let crop = box.crop { img = VideoCrop.cut(img, crop) }
            if box.scale < 1 { img = img.transformed(by: CGAffineTransform(scaleX: box.scale, y: box.scale)) }
            img = box.look.apply(img)
            for overlay in box.overlays { img = overlay.composited(over: img) }
            // Timeline overlays: only while they're meant to show.
            let t = request.compositionTime.seconds - box.trimStart
            for item in box.timed where t >= item.start - 0.01 && (item.end.map { t < $0 } ?? true) {
                img = item.image.composited(over: img)
            }
            request.finish(with: img, context: nil)
        }
        let full = composition.renderSize
        let natural = videoCrop.map { CGSize(width: full.width * $0.width, height: full.height * $0.height) } ?? full
        let scale = min(1, 1280 / max(natural.width, natural.height))
        box.scale = scale
        let size = CGSize(width: max(2, (natural.width * scale / 2).rounded() * 2), height: max(2, (natural.height * scale / 2).rounded() * 2))
        composition.renderSize = size
        box.overlays = doodleImage(width: size.width, height: size.height).map { [$0] } ?? []
        box.timed = stickers.compactMap { s in
            stickerImage(s, width: size.width, height: size.height).map { RenderBox.Timed(image: $0, start: s.start, end: s.end) }
        }

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw APIError(message: "Couldn't make the video on this device.")
        }
        session.videoComposition = composition
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        // A start after the end is an invalid range, which AVFoundation throws on.
        if trimEnd > trimStart + 0.05 {
            session.timeRange = CMTimeRange(start: CMTime(seconds: max(0, trimStart), preferredTimescale: 600), end: CMTime(seconds: trimEnd, preferredTimescale: 600))
        }
        if muteOriginal || originalVolume < 0.99 {
            let mix = AVMutableAudioMix()
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            let volume = Float(muteOriginal ? 0 : originalVolume)
            mix.inputParameters = tracks.map { track in
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(volume, at: .zero)
                return p
            }
            session.audioMix = mix
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { done.resume() }
        }
        guard session.status == .completed else {
            throw APIError(message: session.error?.localizedDescription ?? "Couldn't make the video.")
        }
        return out
    }
}

// The video in the editor (fills its rounded frame).
struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ view: PlayerUIView, context: Context) { view.playerLayer.player = player }
}

// Trim: drag the two handles over the film strip.
// Trim a video: drag the gradient ends to cut the start or end, or drag the
// middle to slide the whole selection. The live times show above.
struct TrimBar: View {
    let thumbs: [UIImage]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    var onSeek: (Double) -> Void
    var onScrub: (Bool) -> Void = { _ in }

    private enum Part { case start, end, window }
    @State private var dragging: Part?
    @State private var base: (start: Double, end: Double) = (0, 0)
    @State private var atLimit = false

    private let height: CGFloat = 58
    private let tab: CGFloat = 20
    private let minLength = 1.0
    private let maxLength = 60.0

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                timeTag("Start", start, active: dragging == .start || dragging == .window)
                Spacer(minLength: 0)
                Label(ReelTimeline.seconds(((end - start) * 10).rounded() / 10), systemImage: "scissors")
                    .font(.jakarta(13, .heavy)).foregroundStyle(.white).monospacedDigit()
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Theme.gradient, in: Capsule())
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                timeTag("End", end, active: dragging == .end || dragging == .window)
            }
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let x0 = x(start, w)
                let boxWidth = max(tab * 2 + 6, x(end, w) - x0)
                ZStack(alignment: .leading) {
                    strip(w)
                    Rectangle().fill(.black.opacity(0.62)).frame(width: max(0, x0), height: height)
                    Rectangle().fill(.black.opacity(0.62)).frame(width: max(0, w - x0 - boxWidth), height: height).offset(x: x0 + boxWidth)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.gradient, lineWidth: 3.5)
                        .frame(width: boxWidth, height: height)
                        .contentShape(Rectangle())
                        .offset(x: x0)
                        .gesture(drag(.window, w))
                    handle(left: true).offset(x: x0).gesture(drag(.start, w))
                    handle(left: false).offset(x: x0 + boxWidth - tab).gesture(drag(.end, w))
                }
                .frame(width: w, height: height, alignment: .leading)
            }
            .frame(height: height)
            Text(hint).font(.jakarta(11, .semibold)).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .sensoryFeedback(.selection, trigger: dragging) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .light), trigger: atLimit) { old, new in !old && new }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trim, \(ReelTimeline.seconds(end - start)) selected")
    }

    private var hint: String {
        if end - start >= maxLength - 0.05 { return "Reels can be up to 60 seconds" }
        return dragging == nil ? "Drag the ends to trim · drag the middle to move" : "Release to preview"
    }

    private func x(_ t: Double, _ w: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(min(max(0, t), duration) / duration) * w : 0
    }

    private func strip(_ w: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(thumbs.indices, id: \.self) { i in
                Image(uiImage: thumbs[i]).resizable().scaledToFill()
                    .frame(width: w / CGFloat(max(1, thumbs.count)), height: height).clipped()
            }
        }
        .frame(width: w, height: height, alignment: .leading)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handle(left: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: left ? 12 : 0, bottomLeadingRadius: left ? 12 : 0,
                               bottomTrailingRadius: left ? 0 : 12, topTrailingRadius: left ? 0 : 12, style: .continuous)
            .fill(Theme.gradient)
            .frame(width: tab, height: height)
            .overlay {
                Image(systemName: left ? "chevron.compact.left" : "chevron.compact.right")
                    .font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
            }
            .scaleEffect(y: dragging == (left ? Part.start : Part.end) ? 1.06 : 1)
            .animation(.snappy(duration: 0.2), value: dragging)
            .contentShape(Rectangle().inset(by: -12))
            .accessibilityHidden(true)
    }

    private func timeTag(_ title: String, _ t: Double, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.jakarta(10, .heavy)).opacity(0.75)
            Text(ReelTimeline.clock(t)).font(.jakarta(12, .heavy)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).frame(height: 28)
        .background(active ? AnyShapeStyle(Theme.main.opacity(0.55)) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
        .animation(.snappy(duration: 0.2), value: active)
    }

    // Uses how far the finger moved (not where it is), so nothing jumps
    // when a drag starts.
    private func drag(_ part: Part, _ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: part == .window ? 4 : 0)
            .onChanged { v in
                if dragging == nil {
                    dragging = part
                    base = (start, end)
                    onScrub(true)
                }
                let dt = Double(v.translation.width / w) * duration
                switch part {
                case .start:
                    let lo = max(0, base.end - maxLength), hi = base.end - minLength
                    let raw = base.start + dt
                    start = min(max(raw, lo), hi)
                    atLimit = raw < lo || raw > hi
                    onSeek(start)
                case .end:
                    let lo = base.start + minLength, hi = min(duration, base.start + maxLength)
                    let raw = base.end + dt
                    end = min(max(raw, lo), hi)
                    atLimit = raw < lo || raw > hi
                    onSeek(end)
                case .window:
                    let span = base.end - base.start
                    let raw = base.start + dt
                    let s = min(max(0, raw), max(0, duration - span))
                    start = s
                    end = s + span
                    atLimit = raw < 0 || raw > duration - span
                    onSeek(s)
                }
            }
            .onEnded { _ in
                dragging = nil
                atLimit = false
                onScrub(false)
            }
    }
}

// Pick a song from today's charts for the reel.
struct SoundPicker: View {
    var onPick: (Track) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var preview: AVPlayer?
    @State private var playing: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Add a sound").font(.display(26)).foregroundStyle(Palette.text).padding(.top, 20)
            Text("30-second previews by Deezer").font(.jakarta(11)).foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search songs or artists", text: $query).font(.jakarta(15))
            }
            .padding(.horizontal, 16).frame(height: 46)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            ScrollView {
                LazyVStack(spacing: 6) {
                    if tracks.isEmpty { ProgressView().padding(30) }
                    ForEach(tracks) { t in
                        HStack(spacing: 12) {
                            Button {
                                if playing == t.id { preview?.pause(); playing = nil } else if let url = URL(string: t.audioURL) {
                                    preview = AVPlayer(url: url); preview?.play(); playing = t.id
                                }
                            } label: {
                                ZStack {
                                    RemoteImage(url: t.coverURL)
                                    Color.black.opacity(0.25)
                                    Image(systemName: playing == t.id ? "pause.fill" : "play.fill").foregroundStyle(.white)
                                }
                                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(BouncyStyle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                                Text(t.artist).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer()
                            Button("Use") { preview?.pause(); onPick(t); dismiss() }
                                .buttonStyle(GradientButtonStyle(height: 34, fullWidth: false))
                        }
                        .padding(8)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .sugarBackground()
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            tracks = (try? await Deezer.page(genre: 0, query: query, index: 0, limit: 30).tracks) ?? []
        }
        .onDisappear { preview?.pause() }
    }
}
