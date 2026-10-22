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
    case bubblegum = "Bubblegum", pacifico = "Pacifico", lilita = "Lilita", balsamiq = "Balsamiq", modak = "Modak", brush = "Brush", chela = "Chela"
    var uiName: String {
        switch self {
        case .bubbly: return "BubblegumSans-Regular"
        case .cute: return "CaveatBrush-Regular"
        case .bold: return "PlusJakartaSans-ExtraBold"
        case .classic: return "PlusJakartaSans-SemiBold"
        case .bubblegum: return "BubblegumSans-Regular"
        case .pacifico: return "Pacifico-Regular"
        case .lilita: return "LilitaOne"
        case .balsamiq: return "BalsamiqSans-Regular"
        case .modak: return "Modak"
        case .brush: return "CaveatBrush-Regular"
        case .chela: return "ChelaOne-Regular"
        }
    }
}

enum StickerStyle: String, CaseIterable {
    case plain = "Plain", label = "Label", outline = "Outline", glow = "Glow"
    var title: String { self == .glow ? "Neon" : rawValue }
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
        if style == .glow { return 0xFFFFFF }
        return color
    }

    // Neon: a white core with the picked colour glowing round it (pink when
    // the colour is white, so it never disappears).
    var glowColor: UInt32 { color == 0xFFFFFF ? 0xFF4F8B : color }
    var outlineColor: UInt32 { color == 0x2A1620 ? 0xFFFFFF : 0x2A1620 }

    // How big the words are once wrapped (the same measuring the finished
    // video uses), so the label box always fits the text.
    func textSize(fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        let text = NSAttributedString(string: self.text.isEmpty ? " " : self.text, attributes: [.font: uiFont(size: fontSize), .paragraphStyle: paragraph])
        let r = text.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        return CGSize(width: ceil(r.width) + 2, height: ceil(r.height))
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
            attrs[.strokeColor] = UIColor(hex: outlineColor)
            attrs[.strokeWidth] = -8.0
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
            let spot = CGRect(x: pad, y: pad * 0.6, width: textSize.width + 1, height: textSize.height + 1)
            if style == .glow && !isEmoji {
                // A wide soft glow, then a tighter bright one, then the white core.
                ctx.cgContext.setShadow(offset: .zero, blur: size * 0.6, color: UIColor(hex: glowColor).cgColor)
                text.draw(with: spot, options: [.usesLineFragmentOrigin], context: nil)
                ctx.cgContext.setShadow(offset: .zero, blur: size * 0.22, color: UIColor(hex: glowColor).cgColor)
            } else if style == .plain && !isEmoji {
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: size * 0.04), blur: size * 0.18, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            }
            text.draw(with: spot, options: [.usesLineFragmentOrigin], context: nil)
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
    var trimStart: Double = 0   // where the reel starts in the video being rendered
    var rate: Double = 1        // speed: 2 means one second of video per half second
}

// MARK: - Reel Studio

// What the studio hands back when it's used to send something in a chat.
enum ChatMedia {
    case photos([UIImage])
    case video(URL, cover: UIImage?)
}

// Making a reel: the camera (or your library, or a draft), then the editor,
// then the caption and Post. In chats the same camera and editor send the
// photo or video instead.
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
    @State private var doc = EditorModel()
    @State private var step: Step = .pick
    @State private var library = false
    @State private var showDrafts = false
    @State private var items: [PhotosPickerItem] = []
    @State private var loadingPick = false
    // The last picture from the editor, blurred behind the camera while it
    // wakes up again (so going back never shows a black screen).
    @State private var backdrop: UIImage?

    // posting
    @State private var caption = ""
    @State private var allowComments = true
    @State private var postCover: UIImage?
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
        .photosPicker(isPresented: $library, selection: $items, maxSelectionCount: 10, matching: .any(of: [.videos, .images]))
        .sheet(isPresented: $showDrafts) { draftsSheet }
        .onChange(of: items) { _, list in Task { await loadPicked(list) } }
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
                doc.setSound(requested)
                model.soundRequest = nil
            }
        }
        .onDisappear { doc.player.teardown() }
    }

    // MARK: step 1 — the camera

    // Making a reel opens the camera straight away (like TikTok). Upload
    // picks from your library; Drafts opens the ones you saved.
    private var pickScreen: some View {
        RecorderView(sound: Binding(get: { doc.sound }, set: { doc.setSound($0) }), onVideo: { url, filter in
            Task { await openVideo(url, filter: filter) }
        }, onPhotos: { images, filter in
            Task { await openPhotos(images, filter: filter) }
        }, onClose: { dismiss() },
        onUpload: { library = true },
        draftCount: isChat ? 0 : drafts.count,
        onDrafts: { showDrafts = true },
        backdrop: backdrop)
        .overlay {
            if loadingPick {
                ProgressView().tint(.white).controlSize(.large)
                    .frame(width: 90, height: 90)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            // (In chats the problem shows in the middle instead.)
            if let error, !isChat {
                Text(error).font(.jakarta(13, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.danger, in: Capsule())
                    .padding(.top, 60)
                    .onTapGesture { self.error = nil }
                    .transition(.opacity)
            }
        }
    }

    private var draftsSheet: some View {
        DraftStrip(title: "Drafts", items: drafts, dark: true, thumb: { Drafts.reelCover($0) },
                   label: { d in d.caption.isEmpty ? d.saved.formatted(date: .abbreviated, time: .omitted) : d.caption },
                   onOpen: { d in
                       showDrafts = false
                       Task { await openDraft(d) }
                   },
                   onDelete: { d in
                       Drafts.delete("reels", d.id)
                       drafts = Drafts.reels()
                       if drafts.isEmpty { showDrafts = false }
                   })
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(220)])
            .presentationCornerRadius(30)
            .presentationBackground(Color(hex: 0x1A0F15))
            .preferredColorScheme(.dark)
    }

    // MARK: step 2 — edit

    private var editScreen: some View {
        MediaEditor(doc: doc,
                    primaryTitle: isChat ? "Send" : "Next",
                    primaryIcon: isChat ? "paperplane.fill" : "arrow.right",
                    busy: busy,
                    onBack: { if isChat { resetToPick() } else { askDraft = true } },
                    onPrimary: { if isChat { Task { await sendToChat() } } else { goToPost() } })
            .transition(.opacity)
    }

    // MARK: step 3 — post

    private var postScreen: some View {
        VStack(spacing: 14) {
            postTopBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    postCard
                    commentsSwitch
                    if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            postButtons
        }
        .background(EditorPalette.backdrop.ignoresSafeArea())
        .interactiveDismissDisabled(busy)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var postTopBar: some View {
        HStack {
            Button {
                withMotion { step = .edit }
                doc.player.play()
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Back")
            .disabled(busy)
            Spacer()
            Text("New reel").font(.display(22)).foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var postInfo: String {
        doc.isVideo ? "\(Int(doc.finalLength.rounded()))s video" : "\(doc.photos.count) photos · \(Int(doc.length.rounded()))s"
    }

    private var postCard: some View {
        HStack(alignment: .top, spacing: 14) {
            postThumb
            VStack(alignment: .leading, spacing: 10) {
                Label(postInfo, systemImage: doc.isVideo ? "video.fill" : "photo.on.rectangle.angled")
                    .font(.jakarta(12, .heavy)).foregroundStyle(Theme.pink)
                TextField("Write a caption… #tags", text: $caption, axis: .vertical)
                    .font(.jakarta(15)).foregroundStyle(.white).lineLimit(4...8)
                if let sound = doc.sound {
                    Label(sound.title, systemImage: "music.note")
                        .font(.jakarta(12, .bold)).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var postThumb: some View {
        Group {
            if let postCover {
                Image(uiImage: postCover).resizable().scaledToFill()
            } else if let first = doc.previews.first ?? doc.thumbs.first {
                Image(uiImage: first).resizable().scaledToFill()
            } else {
                Theme.gradient
            }
        }
        .frame(width: 104, height: 185)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: postCover)
    }

    private var commentsSwitch: some View {
        // The iPhone's own switch, in your colour.
        Toggle(isOn: $allowComments) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow comments").font(.jakarta(15, .bold)).foregroundStyle(.white)
                Text("You can change this later").font(.jakarta(12)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .tint(Theme.main)
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var postButtons: some View {
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
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: opening

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
        await openPhotos(images)
    }

    // (A filter picked on the camera is already on when the editor opens.)
    private func openVideo(_ url: URL, filter: ReelFilter = .none) async {
        guard await doc.openVideo(url) else {
            error = "That video couldn't be opened."
            return
        }
        doc.startWith(filter)
        error = nil
        withMotion { step = .edit }
    }

    private func openPhotos(_ images: [UIImage], filter: ReelFilter = .none) async {
        guard !images.isEmpty else { return }
        loadingPick = true
        await doc.openSlides(images)
        doc.startWith(filter)
        loadingPick = false
        error = nil
        withMotion { step = .edit }
    }

    private func resetToPick() {
        backdrop = doc.thumbs.first ?? doc.previews.first
        doc.clear()
        doc.setSound(nil)
        caption = ""
        allowComments = true
        postCover = nil
        draftId = nil
        error = nil
        drafts = Drafts.reels()
        withMotion { step = .pick }
    }

    private func goToPost() {
        doc.player.pause()
        doc.selectedOverlay = nil
        postCover = nil
        withMotion { step = .post }
        if doc.isVideo {
            Task { postCover = await doc.coverImage() }
        }
    }

    // MARK: drafts

    private func saveDraft() {
        guard doc.hasMedia else { return }
        let state = Drafts.ReelState(caption: caption, allowComments: allowComments, look: doc.look,
                                     trimStart: doc.trimStart, trimEnd: doc.trimEnd, sound: doc.sound, soundVolume: doc.soundVolume,
                                     originalVolume: doc.originalVolume, video: doc.isVideo ? doc.videoURL : nil,
                                     photos: doc.isSlides ? doc.photos : [], cover: doc.thumbs.first, stickers: doc.stickers,
                                     strokes: doc.strokes, videoCrop: doc.videoCrop,
                                     slideSeconds: doc.isSlides ? doc.slideSeconds : [], speed: doc.isVideo ? doc.speed : 1)
        draftId = Drafts.saveReel(id: draftId, state)
        drafts = Drafts.reels()
        model.showToast("Saved to drafts", icon: "tray.and.arrow.down.fill")
    }

    private func openDraft(_ d: Drafts.Reel) async {
        let restored = Drafts.restore(d)
        doc.soundVolume = d.soundVolume
        doc.originalVolume = d.originalVolume
        doc.setSound(restored.sound)
        loadingPick = true
        defer { loadingPick = false }
        if let url = Drafts.reelVideo(d) {
            guard await doc.openVideo(url) else {
                error = "That draft's video couldn't be opened."
                return
            }
        } else {
            let pics = Drafts.reelPhotos(d)
            guard !pics.isEmpty else {
                error = "That draft is empty."
                return
            }
            await doc.openSlides(pics)
        }
        var crop: CGRect?
        if let c = d.crop, c.count == 4 { crop = CGRect(x: c[0], y: c[1], width: c[2], height: c[3]) }
        doc.restoreDraft(look: restored.look, stickers: restored.stickers, strokes: restored.strokes, crop: crop,
                         trim: (start: d.trimStart, end: d.trimEnd), speed: d.speed, slideSeconds: d.slideSeconds)
        draftId = d.id
        caption = d.caption
        allowComments = d.allowComments
        error = nil
        withMotion { step = .edit }
    }

    // MARK: posting

    private func post() async {
        guard let me = model.me, doc.hasMedia else { return }
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
            let length = doc.finalLength
            if doc.isVideo {
                kind = "video"
                status = "Making your video…"
                let exported = try await doc.exportVideo()
                let data = try Data(contentsOf: exported)
                guard data.count < 58 * 1024 * 1024 else { throw APIError(message: "That video is too big — trim it a little shorter.") }
                status = "Uploading…"
                mediaURL = try await StorageClient.upload(data, contentType: "video/mp4", fileExtension: "mp4")
                var cover = postCover
                if cover == nil { cover = await doc.coverImage() }
                if let cover, let jpeg = ImageTools.jpeg(cover, maxSide: 1080) {
                    coverURL = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
                }
            } else {
                status = "Getting your pictures ready…"
                let baked = await doc.bakedSlides()
                status = "Uploading pictures…"
                for photo in baked {
                    if let jpeg = ImageTools.jpeg(photo, maxSide: 1600) {
                        mediaURLs.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                    }
                }
                mediaURL = mediaURLs.first ?? ""
                coverURL = mediaURL
            }
            status = "Posting…"
            let now = FS.nowISO()
            let sound = doc.sound
            var source = ""
            if let sound, sound.id.hasPrefix("deezer_") { source = "deezer:" + sound.id.replacingOccurrences(of: "deezer_", with: "") }
            var edits: [String: Any] = [:]
            if doc.isSlides, doc.slideSeconds.count == doc.photos.count, doc.slideSeconds.contains(where: { abs($0 - 3) > 0.01 }) {
                edits["slide_durations"] = doc.slideSeconds
            }
            let record: Doc = [
                "kind": kind, "media_url": mediaURL, "media_urls": mediaURLs.count > 1 ? mediaURLs : [String](),
                "cover_url": coverURL, "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
                "music_title": sound?.title ?? "", "music_artist": sound?.artist ?? "", "music_url": sound?.audioURL ?? "",
                "music_source": source, "duration": (length * 10).rounded() / 10, "edits": edits,
                "comments_off": !allowComments, "likes": [String](), "views": 0,
                "tags": Hashtags.tags(caption),
                "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
                "created_by": me.email, "created_date": now, "updated_date": now,
            ]
            let created = try await FS.create("Reel", record)
            // Show it at the top of your feed right away.
            NotificationCenter.default.post(name: ReelsView.posted, object: Reel(created))
            model.tabRequest = .reels
            if let draftId { Drafts.delete("reels", draftId) }
            try? await model.addToMe(["xp": 30, "coins": 5])
            doc.player.teardown()
            dismiss()
            model.showToast("Your reel is live! +30 XP", icon: "play.rectangle.fill")
        } catch {
            TextGuard.forget(.caption, model: model)
            self.error = PostProblem.message(error)
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
        guard let onChatSend, doc.hasMedia else { return }
        doc.player.pause()
        busy = true
        error = nil
        defer { busy = false }
        do {
            if doc.isVideo {
                status = "Making your video…"
                let exported = try await doc.exportVideo()
                let cover = await doc.coverImage()
                onChatSend(.video(exported, cover: cover))
            } else {
                status = "Getting your photos ready…"
                onChatSend(.photos(await doc.bakedSlides()))
            }
            doc.player.teardown()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// The video in the editor (fills its rounded frame).
struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
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
    private var minLength: Double { min(1, duration) }
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
                .coordinateSpace(name: "videoTrim")
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
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
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
        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 28)
        .background(active ? AnyShapeStyle(Theme.main.opacity(0.55)) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
        .animation(.snappy(duration: 0.2), value: active)
    }

    // Uses how far the finger moved (not where it is), so nothing jumps
    // when a drag starts.
    private func drag(_ part: Part, _ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: part == .window ? 4 : 0, coordinateSpace: .named("videoTrim"))
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
    @Environment(AppModel.self) private var model
    @State private var loading = true
    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var preview: AVPlayer?
    @State private var playing: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Add a sound").font(.display(26)).foregroundStyle(Palette.text).padding(.top, 20)
            Text("Your uploaded audio — use tracks you own or have licensed.").font(.jakarta(11)).foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search songs or artists", text: $query).font(.jakarta(15))
            }
            .padding(.horizontal, 16).frame(height: 46)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            ScrollView {
                LazyVStack(spacing: 6) {
                    if loading { SugarLoader().padding(30) }
                    else if tracks.isEmpty { Text("Upload an original track in Music, then choose it here.").font(.jakarta(14)).foregroundStyle(Palette.muted).padding(30) }
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
            loading = true
            defer { loading = false }
            guard let email = model.me?.email, !email.isEmpty else { tracks = []; return }
            let docs = (try? await FS.query("MusicReview", orderBy: "created_date", limit: 300)) ?? []
            tracks = docs.map(Track.init).filter {
                $0.authorEmail == email && ProviderMedia.allows($0) && !$0.audioURL.isEmpty &&
                (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query))
            }
        }
        .onDisappear { preview?.pause() }
    }
}
