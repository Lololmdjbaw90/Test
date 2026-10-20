#if DEBUG
import SwiftUI
import PhotosUI
import ImageIO

// Isolated real controls: no login, account mutations, or remote fixtures.
struct PolishUITestHost: View {
    @Environment(AppModel.self) private var model
    static let overlayID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @State private var stickers = [TextSticker(id: overlayID, text: "Hello Sugerly", start: 1, end: 7)]
    @State private var selected: UUID?
    @State private var selectedSlide: Int?
    @State private var photoItem: PhotosPickerItem?
    @State private var slideSeconds: [Double] = []
    @State private var playhead = 0.0
    @State private var editor: TextSticker?
    @State private var tab = 0
    @State private var likes = false
    @State private var action = "Ready"
    @State private var path: [Route] = []
    @State private var posts: PostsStore = {
        let store = PostsStore()
        store.hasMore = false
        store.posts = [Post(["id": "sample-post", "user_email": "fixture@example.invalid", "user_display_name": "Luna", "title": "A tiny work in progress", "content": "Trying a new colour palette today. Pink skies or peach skies?", "created_date": FS.nowISO()])]
        return store
    }()
    @State private var notes = NotificationsStore()
    @State private var player = Player()
    @State private var chats = ChatStore()
    private let art = Artwork(["id": "ui-art", "title": "Pink sketch", "user_display_name": "Luna", "user_email": "fixture@example.invalid"])

    var body: some View {
        VStack(spacing: 12) {
            Picker("Screen", selection: $tab) {
                Text("Editor").tag(0)
                Text("Fanart").tag(1)
                Text("Community").tag(2)
                Text("Wall").tag(3)
                Text("Home").tag(4)
            }.pickerStyle(.segmented).padding()
            if ProcessInfo.processInfo.arguments.contains("--check-performance-policy") {
                Text(PerformanceFixture.result).font(.caption2).accessibilityIdentifier("performance-policy")
            }
            if tab == 0 {
                Text(stickers.first.map { String(format: "%.2f,%.2f", $0.start, $0.end ?? 10) } ?? "Deleted")
                    .accessibilityIdentifier("timing-value")
                Text(StickerFont.allCases.allSatisfy { UIFont(name: $0.uiName, size: 16) != nil } ? "Fonts loaded" : "Missing font")
                Spacer()
                ReelTimeline(length: 10, playhead: playhead, playing: false, thumbs: [], slides: [],
                             slideSeconds: $slideSeconds, stickers: $stickers, selected: $selected, selectedSlide: $selectedSlide,
                             photoItem: $photoItem, onSeek: { playhead = $0 }, onScrub: { _ in }, onTogglePlay: {},
                             onAddText: { editor = TextSticker(text: "") }, onAddSticker: {}, onEditText: { editor = $0 },
                             onCheckpoint: {}, onMoveSlide: { _, _ in }, onDeleteSlide: { _ in })
                    .frame(height: 270).background(Color(hex: 0x24101B))
                Spacer()
            } else if tab == 1 {
                Text(action).accessibilityIdentifier("art-action")
                GalleryCard(artwork: art, liked: likes, onOpen: { action = "Opened artwork" }, onLike: { likes.toggle(); action = "Liked artwork" }, onProfile: { action = "Opened artist" })
                    .frame(width: 190)
                Spacer()
            } else if tab == 2 {
                NavigationStack(path: $path) {
                    CommunityView(path: $path, compose: {})
                }
            } else if tab == 3 {
                NavigationStack(path: $path) {
                    GalleryView(path: $path, initialArtworks: [art])
                }
            } else {
                NavigationStack(path: $path) {
                    HomeView(path: $path, compose: { _ in }, loadContent: false)
                }
            }
        }
        .sugarBackground()
        // Everything the real pages read (the top bar's bell, the music and
        // call bar), without logging in.
        .environment(posts).environment(notes).environment(player).environment(chats)
        .environment(VoiceEngine.shared).environment(CallCenter.shared)
        .onAppear {
            model.me = UserProfile(["id": "fixture-user", "email": "test@example.invalid", "display_name": "Mimi"])
        }
        .sheet(item: $editor) { sticker in
            TextStickerEditor(sticker: sticker) { updated in
                if let i = stickers.firstIndex(where: { $0.id == updated.id }) { stickers[i] = updated } else { stickers.append(updated) }
            } onDelete: { id in stickers.removeAll { $0.id == id } }
        }
    }
}
// Exercise the real image decoders without network access or private accounts.
@MainActor
private enum PerformanceFixture {
    static let result: String = {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, 2, nil) else { return "GIF fixture failed" }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        for color in [UIColor.red, UIColor.blue] {
            let image = renderer.image { context in color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16)) }
            guard let cg = image.cgImage else { return "GIF frame failed" }
            CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination),
              let poster = AnimatedImages.decode(data as Data, maxPixel: 16, maxFrames: 1), poster.images == nil,
              let animated = AnimatedImages.decode(data as Data, maxPixel: 16, maxFrames: 2), (animated.images?.count ?? 0) >= 2 else { return "GIF playback policy failed" }
        guard !Motion.ambient else { return "Decorative animations still running" }
        guard ImagePipeline.cacheKey("fixture", maxPixel: 96) != ImagePipeline.cacheKey("fixture") else { return "Thumbnail cache collision" }
        return "Performance fixtures passed"
    }()
}
#endif
