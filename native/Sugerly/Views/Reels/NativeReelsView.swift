import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers

struct NativeReel: Identifiable {
    let data: Doc
    var id: String { data.str("id") }
    var photos: [String] {
        let urls = data.strs("media_urls").isEmpty ? data.strs("photo_urls") : data.strs("media_urls")
        return urls.isEmpty ? [data.str("media_url")] : urls
    }
    var isVideo: Bool { data.str("kind") == "video" }
}

struct NativeReelsView: View {
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var reels: [NativeReel] = []
    @State private var cursor: Doc?
    @State private var selected: String?
    @State private var loading = false
    @State private var more = true
    @State private var error: String?
    @State private var creating = false
    @State private var visible = false
    @State private var reporting: ReportSheet.Target?
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(reels) { reel in
                        NativeReelCard(reel: reel, active: isSelected && visible && scenePhase == .active && selected == reel.id && !creating && reporting == nil, report: {
                            reporting = ReportSheet.Target(id: reel.id, type: "reel", ownerEmail: reel.data.str("user_email"), preview: reel.data.str("caption"), link: "/Reels?r=\(reel.id)")
                        }).containerRelativeFrame([.horizontal, .vertical]).id(reel.id)
                            .onAppear { if reel.id == reels.suffix(4).first?.id { Task { await load() } } }
                    }
                    if more {
                        VStack(spacing: 16) {
                            if let error { Text(error).multilineTextAlignment(.center); Button("Try again") { Task { await load() } } }
                            else { ProgressView().tint(.white) }
                        }.id(cursor?.str("id") ?? "initial").padding().containerRelativeFrame([.horizontal, .vertical]).onAppear { Task { await load() } }
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.paging).scrollPosition(id: $selected).scrollIndicators(.hidden)
                .background(.black).foregroundStyle(.white)
                .overlay { if reels.isEmpty && !loading && !more { ContentUnavailableView("Your story starts here", systemImage: "play.rectangle", description: Text("Create the first reel.")) } }
                .navigationTitle("Reels").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { NativeWordmark() }
                    ToolbarItem(placement: .topBarTrailing) { Button { creating = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Create reel") }
                }
                .sheet(isPresented: $creating) { NativeReelComposer { reel in reels.insert(reel, at: 0); selected = reel.id } }
                .sheet(item: $reporting) { ReportSheet(target: $0) }
                .onAppear { visible = true }
                .onDisappear { visible = false }
                .task { if reels.isEmpty { await load() } }
        }
    }
    private func load() async {
        guard !loading, more else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let page = try await FS.page("Reel", after: cursor)
            let known = Set(reels.map(\.id)), blocked = Set(model.me?.blocked ?? [])
            let next = page.rows.filter { !known.contains($0.str("id")) && !blocked.contains($0.str("user_email")) }.map { NativeReel(data: $0) }
            reels.append(contentsOf: next); cursor = page.rows.last ?? cursor; more = page.more
            if selected == nil { selected = reels.first?.id }
        } catch { self.error = error.localizedDescription }
    }
}

struct NativeReelCard: View {
    let reel: NativeReel
    let active: Bool
    let report: () -> Void
    @Environment(AppModel.self) private var model
    @State private var player: AVPlayer?
    @State private var audio: AVPlayer?
    @State private var photo = 0
    @State private var liked = false
    @State private var likeCount = 0
    @State private var likeBusy = false
    @State private var error: String?
    @State private var muted = true
    @State private var comments = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if reel.isVideo {
                if let player { VideoPlayer(player: player) }
                else { RemoteImage(url: reel.data.str("cover_url"), contentMode: .fit) }
            } else {
                TabView(selection: $photo) {
                    ForEach(Array(reel.photos.enumerated()), id: \.offset) { i, url in
                        Group { if abs(i - photo) <= 1 { RemoteImage(url: url, contentMode: .fit) } else { Color.black } }.tag(i)
                    }
                }.tabViewStyle(.page(indexDisplayMode: reel.photos.count > 1 ? .always : .never))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("@\(reel.data.str("user_display_name"))").font(.headline)
                    Text(reel.data.str("caption")).font(.subheadline).lineLimit(4)
                    if !reel.data.str("music_title").isEmpty { Label(reel.data.str("music_title"), systemImage: "music.note").font(.caption).lineLimit(1) }
                    if let error { Text(error).font(.caption).foregroundStyle(.pink) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 20) {
                    Button { Task { await toggleLike() } } label: { VStack { Image(systemName: liked ? "heart.fill" : "heart").font(.title); Text("\(likeCount)").font(.caption) }.foregroundStyle(liked ? Theme.pink : .white) }.disabled(likeBusy).accessibilityLabel(liked ? "Unlike reel" : "Like reel")
                    Button { muted.toggle(); player?.isMuted = muted || (reel.data["edits"] as? Doc ?? [:]).bool("muted"); audio?.isMuted = muted } label: { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.title2) }.accessibilityLabel(muted ? "Turn sound on" : "Mute")
                    if !reel.data.bool("comments_off") { Button { comments = true } label: { Image(systemName: "bubble.right").font(.title2) }.accessibilityLabel("Comments") }
                    Button(action: report) { Image(systemName: "flag").font(.title2) }.accessibilityLabel("Report reel")
                }.frame(width: 44)
            }.padding(.horizontal, 20).padding(.bottom, 42).foregroundStyle(.white)
        }.clipped()
            .sheet(isPresented: $comments) { NativeReelComments(reel: reel) }
            .onAppear { liked = reel.data.strs("likes").contains(model.me?.email ?? ""); likeCount = reel.data.strs("likes").count }
            .task(id: active) {
                player?.pause(); audio?.pause()
                guard active else { player = nil; audio = nil; return }
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                if reel.isVideo, let url = URL(string: reel.data.str("media_url")) {
                    let p = AVPlayer(url: url); p.isMuted = muted || (reel.data["edits"] as? Doc ?? [:]).bool("muted"); player = p
                    let edits = reel.data["edits"] as? Doc ?? [:]
                    let start = edits["trim_start"] as? Double ?? 0
                    if let end = edits["trim_end"] as? Double, end > start { p.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600) }
                    await p.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                    guard !Task.isCancelled, active else { p.pause(); return }
                    p.playImmediately(atRate: Float(edits["speed"] as? Double ?? 1))
                }
                var musicURL = reel.data.str("music_url")
                let source = reel.data.str("music_source")
                if source.hasPrefix("deezer:"), let url = URL(string: "https://api.deezer.com/track/\(source.dropFirst(7))"), let data = try? await HTTP.json(url) as? Doc, !data.str("preview").isEmpty { musicURL = data.str("preview") }
                guard !Task.isCancelled, active else { return }
                if let url = URL(string: musicURL), !musicURL.isEmpty { let p = AVPlayer(url: url); p.isMuted = muted; audio = p; p.play() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { event in
                guard active, let item = event.object as? AVPlayerItem else { return }
                if item === player?.currentItem {
                    let edits = reel.data["edits"] as? Doc ?? [:]
                    player?.seek(to: CMTime(seconds: edits["trim_start"] as? Double ?? 0, preferredTimescale: 600)); player?.playImmediately(atRate: Float(edits["speed"] as? Double ?? 1))
                }
                if item === audio?.currentItem { audio?.seek(to: .zero); audio?.play() }
            }
            .onDisappear { player?.pause(); audio?.pause(); player = nil; audio = nil }
    }
    private func toggleLike() async {
        guard let me = model.me, !likeBusy else { return }
        likeBusy = true; error = nil
        defer { likeBusy = false }
        do {
            guard let latest = try await FS.get("Reel", reel.id) else { return }
            var likes = latest.strs("likes")
            if likes.contains(me.email) { likes.removeAll { $0 == me.email } } else { likes.append(me.email) }
            try await FS.update("Reel", reel.id, ["likes": likes, "updated_date": FS.nowISO()])
            liked = likes.contains(me.email); likeCount = likes.count
        } catch { self.error = error.localizedDescription }
    }
}

struct NativeReelComposer: View {
    let posted: (NativeReel) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selections: [PhotosPickerItem] = []
    @State private var caption = ""
    @State private var music: NativeTrack?
    @State private var choosingMusic = false
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SugerlyHeading(title: "Make it yours.", subtitle: "Choose one video or up to 20 photos to swipe through.")
                    PhotosPicker(selection: $selections, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                        VStack(spacing: 14) { Image(systemName: "photo.stack.fill").font(.largeTitle); Text(selections.isEmpty ? "Choose photos or a video" : "\(selections.count) selected").font(.headline) }.frame(maxWidth: .infinity, minHeight: 170).background(Theme.soft, in: RoundedRectangle(cornerRadius: 28))
                    }.disabled(busy)
                    TextField("Write a caption… no links", text: $caption, axis: .vertical).lineLimit(3...6).padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 22)).disabled(busy)
                    Button { choosingMusic = true } label: { Label(music?.title ?? "Choose a soundtrack", systemImage: "music.note").frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Theme.soft, in: Capsule()) }.disabled(busy)
                    if music != nil { Button("Remove music") { music = nil }.font(.caption).disabled(busy) }
                    if Moderation.hasLink(caption) { Text("Links aren't allowed in captions.").foregroundStyle(.red).font(.footnote) }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button { Task { await publish() } } label: { HStack { if busy { ProgressView().tint(.white) }; Text(busy ? status : "Post reel") } }.buttonStyle(PrimaryButtonStyle()).disabled(busy || selections.isEmpty || Moderation.hasLink(caption) || caption.count > 300)
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.background(Theme.background).navigationTitle("New reel").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
                .sheet(isPresented: $choosingMusic) { NativeMusicView(onPick: { music = $0 }) }
                .interactiveDismissDisabled(busy)
        }
    }
    private func publish() async {
        guard let me = model.me, !busy, !selections.isEmpty, !Moderation.hasLink(caption), caption.count <= 300 else { return }
        let videos = selections.filter { $0.supportedContentTypes.contains { $0.conforms(to: .movie) } }
        guard videos.isEmpty || selections.count == 1 else { error = "Choose one video, or photos only."; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            var urls: [String] = []
            for (i, item) in selections.enumerated() {
                status = "Uploading \(i + 1) of \(selections.count)…"
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 100 * 1024 * 1024 else { throw APIError(message: "Each file must be under 100 MB.") }
                let url: String
                if videos.isEmpty {
                    guard let photo = UIImage(data: data), let jpeg = photo.jpegData(compressionQuality: 0.85) else { throw APIError(message: "This photo couldn't be opened.") }
                    url = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
                } else {
                    let type = item.supportedContentTypes.first { $0.conforms(to: .movie) } ?? .mpeg4Movie
                    url = try await StorageClient.upload(data, contentType: type.preferredMIMEType ?? "video/mp4", fileExtension: type.preferredFilenameExtension ?? "mp4")
                }
                urls.append(url)
            }
            status = "Posting…"
            let doc: Doc = ["kind": videos.isEmpty ? "photo" : "video", "media_url": urls[0], "media_urls": videos.isEmpty ? urls : [], "cover_url": videos.isEmpty ? urls[0] : "", "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines), "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture, "created_by": me.email, "created_date": FS.nowISO(), "updated_date": FS.nowISO(), "likes": [String](), "views": 0, "edits": [String: String](), "music_url": music?.url ?? "", "music_title": music?.title ?? "", "music_artist": music?.artist ?? "", "music_source": music?.id.replacingOccurrences(of: "deezer_", with: "deezer:") ?? "", "comments_off": false]
            let created = try await FS.create("Reel", doc)
            posted(NativeReel(data: created)); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
