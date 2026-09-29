#if DEBUG
import SwiftUI
import PhotosUI

// Isolated real controls: no login, account mutations, or remote fixtures.
struct PolishUITestHost: View {
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
    private let art = Artwork(["id": "ui-art", "title": "Pink sketch", "user_display_name": "Luna", "user_email": "fixture@example.invalid"])

    var body: some View {
        VStack(spacing: 12) {
            Picker("Screen", selection: $tab) {
                Text("Editor").tag(0)
                Text("Fanart").tag(1)
            }.pickerStyle(.segmented).padding()
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
            } else {
                Text(action).accessibilityIdentifier("art-action")
                GalleryCard(artwork: art, liked: likes, onOpen: { action = "Opened artwork" }, onLike: { likes.toggle(); action = "Liked artwork" }, onProfile: { action = "Opened artist" })
                    .frame(width: 190)
                Spacer()
            }
        }
        .sugarBackground()
        .sheet(item: $editor) { sticker in
            TextStickerEditor(sticker: sticker) { updated in
                if let i = stickers.firstIndex(where: { $0.id == updated.id }) { stickers[i] = updated } else { stickers.append(updated) }
            } onDelete: { id in stickers.removeAll { $0.id == id } }
        }
    }
}
#endif
