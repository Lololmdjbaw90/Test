import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// A looping video filling its frame (no controls), for reels.
final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct LoopingVideo: UIViewRepresentable {
    let player: AVQueuePlayer
    var fill = true
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

@MainActor
@Observable
final class ReelVideo {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    var failed = false
    var ready = false
    var portrait = true
    private var statusObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?

    // Videos are kept around for the few reels near the one on screen, so
    // swiping to the next one starts right away.
    private static var pool: [String: ReelVideo] = [:]
    private static var order: [String] = []

    static func get(_ id: String, url: URL, start: Double, filter: String = "none", speed: Double = 1) -> ReelVideo {
        if let hit = pool[id] { return hit }
        let video = ReelVideo(url: url, start: start, filter: filter, speed: speed)
        pool[id] = video
        order.append(id)
        while order.count > 5 {
            let old = order.removeFirst()
            pool[old]?.pause()
            pool[old] = nil
        }
        return video
    }

    var progress: Double = 0
    private var timeObserver: Any?

    init(url: URL, start: Double, filter: String = "none", speed: Double = 1) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        player.automaticallyWaitsToMinimizeStalling = false
        player.defaultRate = Float(max(0.25, min(3, speed)))
        if filter != "none" {
            // The website's filter, drawn live on the video.
            Task { [weak self] in
                guard let composition = try? await AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
                    request.finish(with: WebFilter.apply(filter, to: request.sourceImage), context: nil)
                }) else { return }
                guard let self else { return }
                for item in self.player.items() { item.videoComposition = composition }
            }
        }
        looper = AVPlayerLooper(player: player, templateItem: item, timeRange: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: .positiveInfinity))
        player.isMuted = false
        statusObservation = player.observe(\.currentItem?.status, options: [.new]) { [weak self] p, _ in
            let status = p.currentItem?.status
            Task { @MainActor in
                if status == .failed { self?.failed = true }
                if status == .readyToPlay { self?.ready = true }
            }
        }
        sizeObservation = player.observe(\.currentItem?.presentationSize, options: [.new]) { [weak self] p, _ in
            let size = p.currentItem?.presentationSize ?? .zero
            Task { @MainActor in
                if size.width > 0, size.height > 0 { self?.portrait = size.height >= size.width * 1.1 }
            }
        }
    }

    func play() {
        player.play()
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, let item = self.player.currentItem else { return }
                    let total = item.duration.seconds
                    if total.isFinite, total > 0 { self.progress = min(1, max(0, time.seconds / total)) }
                }
            }
        }
    }
    func pause() { player.pause() }
}

// Set up playback audio once, not on every swipe (it can take a moment).
enum ReelAudio {
    nonisolated(unsafe) private static var ready = false
    static func prepare() {
        // (A voice channel switches the session to calls; switch back.)
        if ready && AVAudioSession.sharedInstance().category == .playback { return }
        ready = true
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }
}

struct ReelsView: View {
    let visible: Bool
    @Binding var path: [Route]
    var create: () -> Void
    @Environment(AppModel.self) private var model
    @State private var reels: [Reel] = []
    @State private var activeId: String?
    @State private var feed = "foryou"
    @State private var loading = true
    @State private var lastLoad: Date?

    private var shown: [Reel] {
        let blocked = Set(model.me?.blocked ?? [])
        let list = reels.filter { !blocked.contains($0.authorEmail) }
        if feed == "following" {
            let following = Set(model.me?.following ?? [])
            return list.filter { following.contains($0.authorEmail) }
        }
        return list
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if loading && reels.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 40)).foregroundStyle(Theme.gradient)
                    Text(feed == "following" ? "No reels from people you follow" : "No reels yet").font(.display(26)).foregroundStyle(.white)
                    Button("Create a reel", action: create).buttonStyle(GradientButtonStyle(fullWidth: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let list = shown
                    let activeIndex = list.firstIndex { $0.id == activeId } ?? 0
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, reel in
                                // On iPad (or any wide screen) the reel is a phone-shaped
                                // column in the middle, on a blurred copy of its cover.
                                let column = Swift.min(geo.size.width, geo.size.height * 0.6)
                                ZStack {
                                    if column < geo.size.width - 1 {
                                        RemoteImage(url: reel.coverURL.isEmpty ? (reel.pictures.first ?? "") : reel.coverURL)
                                            .blur(radius: 40)
                                            .overlay(Color.black.opacity(0.45))
                                    }
                                    ReelPage(reel: reel, active: visible && activeId == reel.id, near: abs(i - activeIndex) <= 1, path: $path)
                                        .frame(width: column, height: geo.size.height)
                                        .clipShape(RoundedRectangle(cornerRadius: column < geo.size.width - 1 ? 28 : 0, style: .continuous))
                                        .padding(.vertical, column < geo.size.width - 1 ? 0 : 0)
                                }
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .id(reel.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $activeId)
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .ignoresSafeArea()
            }

            HStack(spacing: 22) {
                ForEach([("following", "Following"), ("foryou", "For you")], id: \.0) { id, title in
                    Button { withAnimation(.snappy) { feed = id; activeId = shown.first?.id } } label: {
                        VStack(spacing: 4) {
                            Text(title).font(.jakarta(17, .bold)).foregroundStyle(.white.opacity(feed == id ? 1 : 0.6))
                            Capsule().fill(.white).frame(width: feed == id ? 24 : 6, height: 3).opacity(feed == id ? 1 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 6)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button(action: create) {
                    Image(systemName: "camera.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(BouncyStyle())
                .padding(.trailing, 16)
            }
            .padding(.top, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let lastLoad, Date().timeIntervalSince(lastLoad) < 90 { return }
            lastLoad = Date()
            await load()
        }
        .onChange(of: visible) { _, now in if now, activeId == nil { activeId = shown.first?.id } }
    }

    private func load() async {
        defer { loading = false }
        if let cached = Self.cache, reels.isEmpty {
            reels = cached
            if activeId == nil { activeId = reels.first?.id }
        }
        guard let docs = try? await FS.query("Reel", orderBy: "created_date", limit: 60) else { return }
        let all = docs.map(Reel.init)
        // Freshest and most liked first, a little shuffled so it feels alive.
        let now = Date()
        func score(_ r: Reel) -> Double {
            let age: Double = now.timeIntervalSince(Dates.parse(r.created) ?? now) / 3600.0
            let hours: Double = Swift.max(1.0, age) + 2.0
            let points = Double(r.likes.count * 3 + r.views)
            return points / pow(hours, 0.8)
        }
        let scores = Dictionary(all.map { ($0.id, score($0)) }, uniquingKeysWith: { a, _ in a })
        let sorted = all.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        Self.cache = sorted
        if reels.isEmpty { reels = sorted } else {
            // Keep what's on screen in place; add new ones behind it.
            let have = Set(reels.map(\.id))
            reels += sorted.filter { !have.contains($0.id) }
        }
        if activeId == nil { activeId = reels.first?.id }
    }

    nonisolated(unsafe) private static var cache: [Reel]?
}

// One reel filling the screen.
struct ReelPage: View {
    @State var reel: Reel
    let active: Bool
    var near = true
    @Binding var path: [Route]
    var showBack = false
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var music
    @Environment(\.dismiss) private var dismiss
    @State private var video: ReelVideo?
    @State private var sound: AVPlayer?
    @State private var paused = false
    @State private var heart = false
    @State private var comments = false
    @State private var slide = 0
    @State private var reporting: ReportSheet.Target?
    @State private var commentCount = 0
    @AppStorage("sugerly.reels.muted") private var muted = false

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { reel.likes.contains(me) }
    private var saved: Bool { model.me?.savedReels.contains(reel.id) ?? false }
    private var author: UserProfile? { model.person(reel.authorEmail) }
    private var following: Bool { model.me?.following.contains(reel.authorEmail) ?? false }

    var body: some View {
        ZStack {
            Color.black
            media
            if !reel.texts.isEmpty {
                ReelTextLayer(texts: reel.texts, active: active).allowsHitTesting(false)
            }
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            if paused {
                Image(systemName: "play.fill").font(.system(size: 60)).foregroundStyle(.white.opacity(0.85)).shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            Image(systemName: "heart.fill")
                .font(.system(size: 110))
                .foregroundStyle(Theme.gradient)
                .shadow(color: Theme.pink.opacity(0.7), radius: 24)
                .scaleEffect(heart ? 1 : 0.3)
                .opacity(heart ? 1 : 0)
                .allowsHitTesting(false)
            overlay
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { doubleTap() }
        .onTapGesture { togglePause() }
        .onAppear {
            if active { start() } else if near { preload() }
        }
        .onChange(of: near) { _, now in if now && !active { preload() } }
        .onDisappear { video?.pause(); sound?.pause() }
        .onChange(of: active) { _, now in
            if now { start() } else { video?.pause(); sound?.pause() }
        }
        .onChange(of: muted) { _, now in
            video?.player.isMuted = now || reel.muted
            sound?.isMuted = now
        }
        .task(id: reel.id) {
            let docs = (try? await FS.query("CommunityComment", [.equals("post_id", "reel_\(reel.id)")], limit: 200)) ?? []
            commentCount = docs.count
        }
        .sheet(isPresented: $comments) {
            NavigationStack {
                CommentsScreen(collection: "CommunityComment", field: "post_id", targetId: "reel_\(reel.id)", ownerEmail: reel.authorEmail, link: "/Reels?r=\(reel.id)", disabled: reel.commentsOff) {
                    if reel.commentsOff {
                        Label("Comments are turned off for this reel", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                            .font(.jakarta(14, .semibold)).foregroundStyle(Palette.muted)
                    }
                }
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(30)
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
    }

    @ViewBuilder
    private var media: some View {
        if reel.isVideo {
            if let video, !video.failed {
                ZStack {
                    // The cover shows at once; the video fades in over it.
                    if !video.ready { RemoteImage(url: reel.coverURL, contentMode: video.portrait ? .fill : .fit) }
                    LoopingVideo(player: video.player, fill: video.portrait)
                        .scaleEffect(x: reel.mirror ? -1 : 1, y: 1)
                        .opacity(video.ready ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: video.ready)
                    if !video.ready { ProgressView().tint(.white).controlSize(.large) }
                }
            } else {
                ZStack {
                    RemoteImage(url: reel.coverURL)
                    if video?.failed == true {
                        Label("This video can't play on iPhone yet", systemImage: "exclamationmark.triangle.fill")
                            .font(.jakarta(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.5), in: Capsule())
                    }
                }
                .ignoresSafeArea()
            }
        } else if reel.pictures.count > 1 {
            TabView(selection: $slide) {
                ForEach(Array(reel.pictures.enumerated()), id: \.offset) { i, url in
                    RemoteImage(url: url, contentMode: .fit).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()
            .task(id: active) {
                // Slideshows move on by themselves, like on the website.
                while active && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    if active && !paused { withAnimation(.easeInOut) { slide = (slide + 1) % reel.pictures.count } }
                }
            }
        } else {
            RemoteImage(url: reel.pictures.first ?? "", contentMode: .fit).ignoresSafeArea()
        }
    }

    // Everything drawn over the reel, laid out like the website: info at the
    // bottom left, round buttons down the right, the song disc at the bottom.
    private var overlay: some View {
        VStack(spacing: 0) {
            if showBack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.white.opacity(0.2), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
            }
            if muted && active {
                Button { withAnimation(.snappy) { muted = false } } label: {
                    Label("Tap for sound", systemImage: "speaker.slash.fill")
                        .font(.jakarta(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(Color(hex: 0x2A1620).opacity(0.55), in: Capsule())
                }
                .buttonStyle(BouncyStyle())
                .padding(.top, showBack ? 10 : 108)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                info
                Spacer(minLength: 8)
                actions
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.bottom, 14)
            if reel.isVideo, let video {
                ReelProgress(video: video)
            }
        }
        .padding(.bottom, showBack ? 20 : 110)
    }

    private var relation: String? {
        guard let meProfile = model.me, reel.authorEmail != me else { return nil }
        let theyFollow = author?.following.contains(me) ?? false
        if following && theyFollow { return "From your friend" }
        if following { return "From someone you follow" }
        if theyFollow { return "Follows you" }
        if reel.likes.count >= 10 { return "Trending" }
        _ = meProfile
        return nil
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { path.append(.person(reel.authorEmail)) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("@\(author?.displayName ?? reel.authorName)").font(.jakarta(17, .heavy)).foregroundStyle(.white)
                    Text("· \(Dates.ago(reel.created))").font(.jakarta(13)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            if let relation {
                Label(relation, systemImage: "sparkles")
                    .font(.jakarta(12, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(.white.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            if !reel.caption.isEmpty {
                Text(ReelCaption.styled(reel.caption)).font(.jakarta(15)).foregroundStyle(.white).lineLimit(3)
            }
            if !reel.musicTitle.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 14, weight: .semibold))
                    Text("\(reel.musicTitle)\(reel.musicArtist.isEmpty ? "" : " · \(reel.musicArtist)")").lineLimit(1)
                }
                .font(.jakarta(14, .medium)).foregroundStyle(.white.opacity(0.95))
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 4)
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button { path.append(.person(reel.authorEmail)) } label: {
                Avatar(url: author?.picture ?? reel.authorPicture, name: reel.authorName, size: 54, nitro: author?.isNitro ?? false)
                    .overlay(Circle().strokeBorder(.white, lineWidth: (author?.isNitro ?? false) ? 0 : 2.5))
                    .overlay(alignment: .bottom) {
                        if !following && reel.authorEmail != me {
                            Image(systemName: "plus").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(Theme.gradient, in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .offset(y: 11)
                                .onTapGesture { follow() }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .buttonStyle(BouncyStyle())
            .padding(.bottom, 6)
            bubble(liked ? "heart.fill" : "heart", count: reel.likes.count, tint: liked) { toggleLike() }
                .sensoryFeedback(.impact(weight: .light), trigger: liked)
            bubble("bubble.left", count: reel.commentsOff ? nil : commentCount) { comments = true }
            bubble(saved ? "bookmark.fill" : "bookmark", tint: saved) { toggleSave() }
            ShareLink(item: reel.caption.isEmpty ? "A reel on Sugerly" : reel.caption) {
                bubbleLabel("paperplane", tint: false)
            }
            .buttonStyle(BouncyStyle(scale: 0.85))
            Menu {
                if reel.authorEmail != me {
                    Button { reporting = ReportSheet.Target(id: reel.id, type: "reel", ownerEmail: reel.authorEmail, preview: reel.caption, link: "/Reels?r=\(reel.id)") } label: { Label("Report", systemImage: "flag") }
                } else {
                    Button(role: .destructive) { Task { try? await FS.delete("Reel", reel.id); model.showToast("Reel deleted", icon: "trash.fill") } } label: { Label("Delete reel", systemImage: "trash") }
                }
                Button { muted.toggle() } label: { Label(muted ? "Sound on" : "Mute", systemImage: muted ? "speaker.wave.2" : "speaker.slash") }
            } label: {
                bubbleLabel("ellipsis", tint: false)
            }
            MusicDisc(picture: author?.picture ?? reel.authorPicture, name: reel.authorName, spinning: active && !paused)
                .padding(.top, 4)
        }
    }

    // Round frosted button with an optional count under it (like the website).
    private func bubble(_ icon: String, count: Int? = nil, tint: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                bubbleLabel(icon, tint: tint)
                if let count {
                    Text("\(count)").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
    }

    private func bubbleLabel(_ icon: String, tint: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(tint ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white))
            .symbolEffect(.bounce, value: tint)
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.2), in: Circle())
            .background(.ultraThinMaterial.opacity(0.5), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    // Get the video ready (buffered, paused) before you swipe to it.
    private func preload() {
        guard reel.isVideo, video == nil, let url = URL(string: reel.mediaURL) else { return }
        video = ReelVideo.get(reel.id, url: url, start: reel.trimStart, filter: reel.filterId, speed: reel.speed)
    }

    private func start() {
        if music.playing { music.pause() }
        if reel.isVideo {
            if video == nil, let url = URL(string: reel.mediaURL) {
                video = ReelVideo.get(reel.id, url: url, start: reel.trimStart, filter: reel.filterId, speed: reel.speed)
            }
            ReelAudio.prepare()
            video?.player.isMuted = muted || reel.muted
            if !paused { video?.play() }
        }
        if !paused { startSound() }
        countView()
    }

    // The reel's song (Deezer preview links expire, so get a fresh one).
    private func startSound() {
        guard !reel.musicTitle.isEmpty else { return }
        if let sound { sound.play(); return }
        let wanted = reel.id
        Task {
            var link = reel.musicURL
            if reel.musicSource.hasPrefix("deezer:"), let id = reel.musicSource.split(separator: ":").last,
               let url = URL(string: "https://api.deezer.com/track/\(id)"),
               let json = try? await HTTP.json(url) as? [String: Any],
               let fresh = json["preview"] as? String, !fresh.isEmpty {
                link = fresh
            }
            guard active, wanted == reel.id, sound == nil, let url = URL(string: link), !link.isEmpty else { return }
            let p = AVPlayer(url: url)
            p.isMuted = muted
            p.play()
            sound = p
        }
    }

    private func togglePause() {
        withAnimation(.snappy) { paused.toggle() }
        if paused {
            video?.pause()
            sound?.pause()
        } else {
            if reel.isVideo { video?.play() }
            sound?.play()
        }
    }

    private func doubleTap() {
        if !liked { toggleLike() }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heart = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.25)) { heart = false }
        }
    }

    private func toggleLike() {
        guard let meProfile = model.me else { return }
        let before = reel.likes
        let liking = !before.contains(me)
        reel.likes = liking ? before + [me] : before.filter { $0 != me }
        Task {
            do {
                try await FS.update("Reel", reel.id, ["likes": reel.likes, "updated_date": FS.nowISO()])
                if liking { Notify.send(to: reel.authorEmail, from: meProfile, type: "like", message: "\(meProfile.displayName) liked your reel", link: "/Reels?r=\(reel.id)") }
            } catch { reel.likes = before }
        }
    }

    private func toggleSave() {
        guard let meProfile = model.me else { return }
        var next = meProfile.savedReels
        if next.contains(reel.id) { next.removeAll { $0 == reel.id } } else { next.append(reel.id) }
        Task { try? await model.updateMe(["saved_reels": next]) }
    }

    private func follow() {
        guard let meProfile = model.me else { return }
        Task {
            try? await model.updateMe(["following": meProfile.following + [reel.authorEmail]])
            Notify.send(to: reel.authorEmail, from: meProfile, type: "follow", message: "\(meProfile.displayName) started following you", link: "/Profile?email=\(meProfile.email)")
        }
    }

    // A view counts once per person (not rewatches, not your own).
    private func countView() {
        guard !me.isEmpty, reel.authorEmail != me else { return }
        let key = "sugerly.viewed.\(me)"
        var seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard !seen.contains(reel.id) else { return }
        seen.insert(reel.id)
        UserDefaults.standard.set(Array(seen.suffix(4000)), forKey: key)
        let next = reel.views + 1
        reel.views = next
        Task { try? await FS.update("Reel", reel.id, ["views": next, "updated_date": FS.nowISO()]) }
    }
}

// A single reel opened from a profile.
struct SingleReelView: View {
    let reel: Reel
    @Binding var path: [Route]
    var body: some View {
        ReelPage(reel: reel, active: true, path: $path, showBack: true)
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
    }
}

// The thin progress line under a playing reel (its own view, so only it
// redraws as the video plays).
struct ReelProgress: View {
    let video: ReelVideo
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.25))
                Rectangle().fill(.white).frame(width: geo.size.width * video.progress)
            }
        }
        .frame(height: 3)
    }
}

// The spinning record at the bottom of the buttons.
struct MusicDisc: View {
    let picture: String
    let name: String
    let spinning: Bool
    @State private var angle: Double = 0

    var body: some View {
        Avatar(url: picture, name: name, size: 30)
            .padding(10)
            .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x333333), Color(hex: 0x0A0A0A)], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .rotationEffect(.degrees(angle))
            .task(id: spinning) {
                while spinning && !Task.isCancelled {
                    withAnimation(.linear(duration: 4)) { angle += 90 }
                    try? await Task.sleep(for: .seconds(4))
                }
            }
    }
}

// Caption with bold hashtags.
enum ReelCaption {
    static func styled(_ text: String) -> AttributedString {
        var out = AttributedString()
        for (i, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString((i > 0 ? " " : "") + word)
            if word.hasPrefix("#") || word.hasPrefix("@") { piece.font = Font.jakarta(15, .heavy) }
            out += piece
        }
        return out
    }
}

// Text stickers from reels made on the website, drawn over the video.
struct ReelTextLayer: View {
    let texts: [ReelText]
    let active: Bool
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ForEach(texts) { t in
                label(t, width: geo.size.width)
                    .rotationEffect(.degrees(t.rot))
                    .scaleEffect(shown || t.anim == "none" ? 1 : 0.4)
                    .opacity(shown || t.anim == "none" ? 1 : 0)
                    .position(x: t.x * geo.size.width, y: t.y * geo.size.height)
            }
        }
        .onChange(of: active, initial: true) { _, now in
            if now {
                shown = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.15)) { shown = true }
            }
        }
    }

    @ViewBuilder
    private func label(_ t: ReelText, width: CGFloat) -> some View {
        let size = max(10, width * t.size)
        let color = ReelText.hex(t.color)
        let contrast: UInt32 = ReelText.isLight(color) ? 0x2A1620 : 0xFFFFFF
        let font: Font = {
            switch t.font {
            case "bubbly": return .custom("Bubbly-Regular", size: size)
            case "cute": return .custom("CuteHereRegular", size: size)
            case "serif": return .custom("Georgia-BoldItalic", size: size)
            case "mono": return .system(size: size, weight: .bold, design: .monospaced)
            default: return .custom("PlusJakartaSans-ExtraBold", size: size)
            }
        }()
        let base = Text(t.text).font(font).multilineTextAlignment(.center).lineSpacing(0)
        Group {
            switch t.style {
            case "pill":
                let bg: UInt32 = t.bg.isEmpty ? (ReelText.isLight(color) ? 0xD9577F : 0xFFFFFF) : ReelText.hex(t.bg)
                base.foregroundStyle(Color(hex: color))
                    .padding(.horizontal, size * 0.55).padding(.vertical, size * 0.18)
                    .background(Color(hex: bg).opacity(0.94), in: RoundedRectangle(cornerRadius: size * 0.45, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: size * 0.3, y: size * 0.08)
            case "outline":
                base.foregroundStyle(Color(hex: color)).modifier(OutlineText(on: true, color: Color(hex: contrast)))
            case "neon":
                base.foregroundStyle(.white)
                    .shadow(color: Color(hex: color), radius: size * 0.22)
                    .shadow(color: Color(hex: color), radius: size * 0.5)
            case "shadow":
                base.foregroundStyle(Color(hex: color)).shadow(color: Color(hex: contrast), radius: 0, x: size * 0.07, y: size * 0.07)
            default:
                base.foregroundStyle(Color(hex: color)).shadow(color: .black.opacity(0.55), radius: size * 0.3, y: size * 0.05)
            }
        }
        .frame(maxWidth: width * 0.92)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// The website's photo/video filters (CSS steps + tint + vignette) in Core Image.
enum WebFilter {
    static func apply(_ id: String, to input: CIImage) -> CIImage {
        let extent = input.extent
        var img = input.clampedToExtent()
        func controls(brightness: Double = 1, contrast: Double = 1, saturation: Double = 1) {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.brightness = Float((brightness - 1) * 0.5)
            f.contrast = Float(contrast)
            f.saturation = Float(saturation)
            img = f.outputImage ?? img
        }
        func sepia(_ amount: Double) {
            let f = CIFilter.sepiaTone()
            f.inputImage = img
            f.intensity = Float(amount)
            img = f.outputImage ?? img
        }
        func hue(_ degrees: Double) {
            let f = CIFilter.hueAdjust()
            f.inputImage = img
            f.angle = Float(degrees * .pi / 180)
            img = f.outputImage ?? img
        }
        func tint(_ r: Double, _ g: Double, _ b: Double, _ a: Double) {
            let color = CIImage(color: CIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)).cropped(to: extent)
            let f = CIFilter.softLightBlendMode()
            f.inputImage = color
            f.backgroundImage = img
            img = f.outputImage ?? img
        }
        func vignette(_ amount: Double) {
            let f = CIFilter.vignette()
            f.inputImage = img
            f.intensity = Float(amount * 2.2)
            f.radius = 1.5
            img = f.outputImage ?? img
        }
        switch id {
        case "sugar": controls(brightness: 1.06, contrast: 1.04, saturation: 1.15); hue(-8); tint(255, 150, 190, 0.18)
        case "peach": controls(brightness: 1.05, saturation: 1.2); sepia(0.18); tint(255, 170, 120, 0.16)
        case "dreamy": controls(brightness: 1.1, contrast: 0.86, saturation: 1.1); tint(210, 190, 255, 0.2)
        case "vivid": controls(contrast: 1.15, saturation: 1.55)
        case "pop": controls(brightness: 1.05, contrast: 1.25, saturation: 1.35); vignette(0.25)
        case "golden": controls(brightness: 1.04, saturation: 1.35); sepia(0.3); hue(-6); vignette(0.2)
        case "cool": controls(contrast: 1.05, saturation: 1.1); hue(12); tint(120, 170, 255, 0.14)
        case "fade": controls(brightness: 1.08, contrast: 0.8, saturation: 0.8)
        case "vintage": sepia(0.45); controls(brightness: 1.05, contrast: 0.92, saturation: 1.1); vignette(0.35)
        case "mono": controls(contrast: 1.05, saturation: 0)
        case "noir": controls(brightness: 0.95, contrast: 1.45, saturation: 0); vignette(0.45)
        default: break
        }
        return img.cropped(to: extent)
    }
}
