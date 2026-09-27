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

// Text on the video: where it sits (0…1 of the frame), size, colour, font.
struct TextSticker: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var color: UInt32 = 0xFFFFFF
    var bubbly = true
    var background = true
    var x: CGFloat = 0.5
    var y: CGFloat = 0.4
    var scale: CGFloat = 1

    func uiFont(size: CGFloat) -> UIFont {
        UIFont(name: bubbly ? "Bubbly-Regular" : "PlusJakartaSans-ExtraBold", size: size) ?? .boldSystemFont(ofSize: size)
    }

    // The sticker drawn as a picture (for baking into the video).
    func render(width: CGFloat) -> UIImage {
        let size = width * 0.075 * scale
        let font = uiFont(size: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: background ? UIColor(hex: 0x2A1620) : UIColor(hex: color)]
        let text = NSAttributedString(string: self.text, attributes: attrs)
        let textSize = text.boundingRect(with: CGSize(width: width * 0.9, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).size
        let pad = size * 0.45
        let box = CGSize(width: ceil(textSize.width + pad * 2), height: ceil(textSize.height + pad * 1.2))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: box, format: format).image { _ in
            if background {
                UIColor(hex: color).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: box), cornerRadius: size * 0.5).fill()
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
    var filter: ReelFilter = .none
    var scale: CGFloat = 1
    var overlays: [CIImage] = []
}

// MARK: - Reel Studio

struct ReelStudioView: View {
    enum Step { case pick, edit, post }

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
    @State private var filter: ReelFilter = .none
    @State private var stickers: [TextSticker] = []
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
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .fullScreenCover(isPresented: $camera) {
            CameraCapture { url in camera = false; Task { await openVideo(url) } } onCancel: { camera = false }
                .ignoresSafeArea()
        }
        .sheet(item: $editingText) { sticker in
            TextStickerEditor(sticker: sticker) { updated in
                if let i = stickers.firstIndex(where: { $0.id == updated.id }) { stickers[i] = updated } else { stickers.append(updated) }
            } onDelete: { id in stickers.removeAll { $0.id == id } }
            .presentationDetents([.height(360)])
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
        .onChange(of: filter) { _, _ in applyPreviewFilter() }
        .onDisappear { teardown() }
    }

    // MARK: step 1 — pick

    private var pickScreen: some View {
        VStack(spacing: 22) {
            topBar(title: "New reel", back: { dismiss() }, next: nil)
            Spacer()
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 190, height: 190).blur(radius: 50).opacity(0.7)
                Image(systemName: "video.fill")
                    .font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 130, height: 130)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .shadow(color: Theme.pink.opacity(0.6), radius: 24, y: 10)
            }
            Text("Make something cute").font(.display(34)).foregroundStyle(.white)
            Text("Film a video or pick one — or choose several pictures for a slideshow.")
                .font(.jakarta(15)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            if loadingPick {
                ProgressView().tint(.white).padding()
            }
            VStack(spacing: 12) {
                Button { camera = true } label: { Label("Record a video", systemImage: "record.circle") }
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
        VStack(spacing: 12) {
            topBar(title: "Edit", back: { resetToPick() }, next: { goToPost() })
            GeometryReader { geo in
                ZStack {
                    if asset != nil {
                        VideoPlayerLayer(player: player).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    } else if !photos.isEmpty {
                        TabView(selection: $slide) {
                            ForEach(photos.indices, id: \.self) { i in
                                Image(uiImage: photos[i]).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped().tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    ForEach($stickers) { $sticker in
                        StickerView(sticker: $sticker, frame: geo.size) { editingText = sticker }
                    }
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)

            if asset != nil {
                TrimBar(thumbs: thumbs, duration: duration, start: $trimStart, end: $trimEnd) { player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600)) }
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ReelFilter.allCases) { f in
                            Button { filter = f } label: {
                                VStack(spacing: 5) {
                                    Circle().fill(LinearGradient(colors: f.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 48, height: 48)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: filter == f ? 3 : 0))
                                        .shadow(color: filter == f ? Theme.pink.opacity(0.7) : .clear, radius: 8)
                                    Text(f.rawValue).font(.jakarta(11, .bold)).foregroundStyle(.white.opacity(filter == f ? 1 : 0.7))
                                }
                            }
                            .buttonStyle(BouncyStyle(scale: 0.88))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .sensoryFeedback(.selection, trigger: filter)
            }

            HStack(spacing: 10) {
                tool("textformat", "Text") { editingText = TextSticker(text: "") }
                tool("music.note", sound == nil ? "Sound" : "Change") { choosingSound = true }
                if asset != nil {
                    tool(muteOriginal ? "speaker.slash.fill" : "speaker.wave.2.fill", muteOriginal ? "Muted" : "Audio") {
                        muteOriginal.toggle()
                        player.isMuted = muteOriginal
                    }
                }
            }
            .padding(.horizontal, 16)
            if let sound {
                Label("\(sound.title) · \(sound.artist)", systemImage: "music.note")
                    .font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.bottom, 12)
    }

    private func tool(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(title).font(.jakarta(11, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(BouncyStyle())
    }

    // MARK: step 3 — post

    private var postScreen: some View {
        VStack(spacing: 16) {
            topBar(title: "Post", back: { withAnimation { step = .edit }; player.play() }, next: nil)
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
            Button { Task { await post() } } label: {
                if busy {
                    HStack(spacing: 10) { ProgressView().tint(.white); Text(status) }
                } else {
                    Label("Post reel", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 56))
            .disabled(busy)
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
        photos = images
        asset = nil
        withAnimation { step = .edit }
    }

    private func openVideo(_ url: URL) async {
        let a = AVURLAsset(url: url)
        let seconds = (try? await a.load(.duration).seconds) ?? 0
        guard seconds > 0.3 else { error = "That video couldn't be opened."; return }
        videoURL = url
        asset = a
        duration = seconds
        trimStart = 0
        trimEnd = min(seconds, 60)
        photos = []
        let item = AVPlayerItem(asset: a)
        player.replaceCurrentItem(with: item)
        applyPreviewFilter()
        loopPreview()
        player.play()
        withAnimation { step = .edit }
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
        guard let asset, let item = player.currentItem else { return }
        let chosen = filter
        item.videoComposition = chosen == .none ? nil : AVMutableVideoComposition(asset: asset) { request in
            let output = chosen.apply(request.sourceImage.clampedToExtent()).cropped(to: request.sourceImage.extent)
            request.finish(with: output, context: nil)
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
            }
        }
    }

    private func startSound() {
        soundPlayer?.pause()
        guard let sound, let url = URL(string: sound.audioURL) else { return }
        let p = AVPlayer(url: url)
        p.play()
        soundPlayer = p
        player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
    }

    private func resetToPick() {
        player.pause()
        soundPlayer?.pause()
        asset = nil
        photos = []
        stickers = []
        sound = nil
        withAnimation { step = .pick }
    }

    private func goToPost() {
        player.pause()
        withAnimation { step = .post }
    }

    private func teardown() {
        player.pause()
        soundPlayer?.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    // MARK: export + post

    private func post() async {
        guard let me = model.me else { return }
        guard !Moderation.hasLink(caption) else { error = "Links aren't allowed in captions."; return }
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
                for photo in photos {
                    let baked = bake(photo)
                    if let jpeg = ImageTools.jpeg(baked, maxSide: 1600) {
                        mediaURLs.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                    }
                }
                mediaURL = mediaURLs.first ?? ""
                coverURL = mediaURL
                length = Double(photos.count * 3)
            }
            status = "Posting…"
            let now = FS.nowISO()
            var source = ""
            if let sound, sound.id.hasPrefix("deezer_") { source = "deezer:" + sound.id.replacingOccurrences(of: "deezer_", with: "") }
            let doc: Doc = [
                "kind": kind, "media_url": mediaURL, "media_urls": mediaURLs.count > 1 ? mediaURLs : [String](),
                "cover_url": coverURL, "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
                "music_title": sound?.title ?? "", "music_artist": sound?.artist ?? "", "music_url": sound?.audioURL ?? "",
                "music_source": source, "duration": (length * 10).rounded() / 10, "edits": [String: Any](),
                "comments_off": !allowComments, "likes": [String](), "views": 0,
                "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
                "created_by": me.email, "created_date": now, "updated_date": now,
            ]
            try await FS.create("Reel", doc)
            try? await model.updateMe(["xp": me.xp + 30, "coins": me.coins + 5])
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
        return bake(UIImage(cgImage: result.image))
    }

    // Filter + text stickers drawn onto a picture.
    private func bake(_ image: UIImage) -> UIImage {
        guard filter != .none || !stickers.isEmpty, let cg = image.cgImage else { return image }
        var ci = CIImage(cgImage: cg)
        ci = filter.apply(ci.clampedToExtent()).cropped(to: ci.extent)
        for overlay in overlayImages(width: ci.extent.width, height: ci.extent.height) { ci = overlay.composited(over: ci) }
        let context = CIContext()
        guard let out = context.createCGImage(ci, from: ci.extent) else { return image }
        return UIImage(cgImage: out)
    }

    private func overlayImages(width: CGFloat, height: CGFloat) -> [CIImage] {
        stickers.filter { !$0.text.isEmpty }.compactMap { sticker in
            guard let cg = sticker.render(width: width).cgImage else { return nil }
            let img = CIImage(cgImage: cg)
            let x = sticker.x * width - img.extent.width / 2
            let y = (1 - sticker.y) * height - img.extent.height / 2
            return img.transformed(by: CGAffineTransform(translationX: x, y: y))
        }
    }

    private func exportVideo(_ asset: AVURLAsset) async throws -> URL {
        let box = RenderBox()
        box.filter = filter
        let composition = AVMutableVideoComposition(asset: asset) { request in
            var img = request.sourceImage
            if box.scale < 1 { img = img.transformed(by: CGAffineTransform(scaleX: box.scale, y: box.scale)) }
            let extent = img.extent
            img = box.filter.apply(img.clampedToExtent()).cropped(to: extent)
            for overlay in box.overlays { img = overlay.composited(over: img) }
            request.finish(with: img, context: nil)
        }
        let natural = composition.renderSize
        let scale = min(1, 1280 / max(natural.width, natural.height))
        box.scale = scale
        let size = CGSize(width: (natural.width * scale / 2).rounded() * 2, height: (natural.height * scale / 2).rounded() * 2)
        composition.renderSize = size
        box.overlays = overlayImages(width: size.width, height: size.height)

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw APIError(message: "Couldn't make the video on this device.")
        }
        session.videoComposition = composition
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 600), end: CMTime(seconds: trimEnd, preferredTimescale: 600))
        if muteOriginal {
            let mix = AVMutableAudioMix()
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            mix.inputParameters = tracks.map { track in
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(0, at: .zero)
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

// A draggable, pinchable text sticker on the preview.
struct StickerView: View {
    @Binding var sticker: TextSticker
    let frame: CGSize
    var onEdit: () -> Void
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1

    var body: some View {
        if !sticker.text.isEmpty {
            Text(sticker.text)
                .font(sticker.bubbly ? .display(frame.width * 0.075 * sticker.scale * pinch) : .jakarta(frame.width * 0.07 * sticker.scale * pinch, .heavy))
                .foregroundStyle(sticker.background ? Color(hex: 0x2A1620) : Color(hex: sticker.color))
                .multilineTextAlignment(.center)
                .padding(.horizontal, frame.width * 0.03)
                .padding(.vertical, frame.width * 0.015)
                .background {
                    if sticker.background {
                        RoundedRectangle(cornerRadius: frame.width * 0.035, style: .continuous).fill(Color(hex: sticker.color))
                    }
                }
                .shadow(color: .black.opacity(sticker.background ? 0.15 : 0.5), radius: 4)
                .position(x: sticker.x * frame.width + drag.width, y: sticker.y * frame.height + drag.height)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            sticker.x = min(0.95, max(0.05, sticker.x + v.translation.width / frame.width))
                            sticker.y = min(0.95, max(0.05, sticker.y + v.translation.height / frame.height))
                            drag = .zero
                        }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { pinch = $0.magnification }
                            .onEnded { v in sticker.scale = min(3, max(0.5, sticker.scale * v.magnification)); pinch = 1 })
                )
                .onTapGesture(perform: onEdit)
        }
    }
}

struct TextStickerEditor: View {
    @State var sticker: TextSticker
    var onSave: (TextSticker) -> Void
    var onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    private let colors: [UInt32] = [0xFFFFFF, 0xFFB3D1, 0xD9577F, 0xB19CFF, 0x7CBEFF, 0x5FD3B0, 0xFFD166, 0x2A1620]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Delete") { onDelete(sticker.id); dismiss() }.foregroundStyle(Palette.danger).font(.jakarta(15, .bold))
                Spacer()
                Button("Done") { onSave(sticker); dismiss() }.buttonStyle(GradientButtonStyle(height: 38, fullWidth: false))
            }
            TextField("Type something cute…", text: $sticker.text, axis: .vertical)
                .font(sticker.bubbly ? .display(28) : .jakarta(24, .heavy))
                .multilineTextAlignment(.center)
                .focused($focused)
                .padding(14)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            HStack(spacing: 10) {
                Chip(title: "Bubbly", active: sticker.bubbly) { sticker.bubbly = true }
                Chip(title: "Bold", active: !sticker.bubbly) { sticker.bubbly = false }
                Chip(title: "Label", icon: "rectangle.fill", active: sticker.background) { sticker.background.toggle() }
            }
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { c in
                    Button { sticker.color = c } label: {
                        Circle().fill(Color(hex: c)).frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(sticker.color == c ? Theme.pink : Palette.border, lineWidth: sticker.color == c ? 3 : 1))
                    }
                    .buttonStyle(BouncyStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .sugarBackground()
        .onAppear { focused = true }
    }
}

// Trim: drag the two handles over the film strip.
struct TrimBar: View {
    let thumbs: [UIImage]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    var onChange: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x0 = duration > 0 ? CGFloat(start / duration) * w : 0
                let x1 = duration > 0 ? CGFloat(end / duration) * w : w
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(thumbs.indices, id: \.self) { i in
                            Image(uiImage: thumbs[i]).resizable().scaledToFill().frame(width: w / CGFloat(max(1, thumbs.count)), height: 54).clipped()
                        }
                    }
                    .frame(width: w, height: 54, alignment: .leading)
                    .background(.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, x0), height: 54)
                    Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, w - x1), height: 54).offset(x: x1)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.gradient, lineWidth: 3)
                        .frame(width: max(20, x1 - x0), height: 54)
                        .offset(x: x0)
                        .allowsHitTesting(false)
                    handle.offset(x: x0 - 9)
                        .gesture(DragGesture().onChanged { v in
                            let t = Double(max(0, min(v.location.x, x1 - 20)) / w) * duration
                            start = max(0, min(t, end - 1))
                            onChange()
                        })
                    handle.offset(x: x1 - 9)
                        .gesture(DragGesture().onChanged { v in
                            let t = Double(max(x0 + 20, min(v.location.x, w)) / w) * duration
                            end = min(duration, max(t, start + 1), start + 60)
                            onChange()
                        })
                }
            }
            .frame(height: 54)
            Text(String(format: "%.1fs selected", end - start)).font(.jakarta(12, .bold)).foregroundStyle(.white.opacity(0.8))
        }
    }

    private var handle: some View {
        Capsule().fill(.white).frame(width: 18, height: 62).shadow(radius: 4)
            .overlay(Capsule().fill(Theme.pink).frame(width: 4, height: 24))
            .contentShape(Rectangle().inset(by: -12))
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
