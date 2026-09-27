import SwiftUI
import AVFoundation
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

    static func get(_ id: String, url: URL, start: Double) -> ReelVideo {
        if let hit = pool[id] { return hit }
        let video = ReelVideo(url: url, start: start)
        pool[id] = video
        order.append(id)
        while order.count > 5 {
            let old = order.removeFirst()
            pool[old]?.pause()
            pool[old] = nil
        }
        return video
    }

    init(url: URL, start: Double) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        player.automaticallyWaitsToMinimizeStalling = false
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

    func play() { player.play() }
    func pause() { player.pause() }
}

// Set up playback audio once, not on every swipe (it can take a moment).
enum ReelAudio {
    nonisolated(unsafe) private static var ready = false
    static func prepare() {
        guard !ready else { return }
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

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { reel.likes.contains(me) }
    private var saved: Bool { model.me?.savedReels.contains(reel.id) ?? false }
    private var author: UserProfile? { model.person(reel.authorEmail) }
    private var following: Bool { model.me?.following.contains(reel.authorEmail) ?? false }

    var body: some View {
        ZStack {
            Color.black
            media
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

    private var overlay: some View {
        VStack {
            if showBack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 42, height: 42).background(.white.opacity(0.18), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { path.append(.person(reel.authorEmail)) } label: {
                        HStack(spacing: 8) {
                            Text("@\(author?.displayName ?? reel.authorName)").font(.jakarta(16, .heavy)).foregroundStyle(.white)
                            Text(Dates.ago(reel.created)).font(.jakarta(13)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                    if !reel.caption.isEmpty {
                        Text(Hashtags.styled(reel.caption)).font(.jakarta(15)).foregroundStyle(.white).lineLimit(3)
                    }
                    if !reel.musicTitle.isEmpty {
                        Label("\(reel.musicTitle)\(reel.musicArtist.isEmpty ? "" : " · \(reel.musicArtist)")", systemImage: "music.note")
                            .font(.jakarta(13, .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 4)
                Spacer()
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }

    private var actions: some View {
        VStack(spacing: 18) {
            Button { path.append(.person(reel.authorEmail)) } label: {
                Avatar(url: author?.picture ?? reel.authorPicture, name: reel.authorName, size: 50)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .overlay(alignment: .bottom) {
                        if !following && reel.authorEmail != me {
                            Image(systemName: "plus").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Theme.gradient, in: Circle()).offset(y: 10)
                                .onTapGesture { follow() }
                        }
                    }
            }
            .buttonStyle(BouncyStyle())
            action(liked ? "heart.fill" : "heart", "\(reel.likes.count)", tint: liked) { toggleLike() }
                .sensoryFeedback(.impact(weight: .light), trigger: liked)
            action("bubble.right.fill", reel.commentsOff ? "Off" : "Chat") { comments = true }
            action(saved ? "bookmark.fill" : "bookmark", saved ? "Saved" : "Save", tint: saved) { toggleSave() }
            ShareLink(item: reel.caption.isEmpty ? "A reel on Sugerly" : reel.caption) {
                VStack(spacing: 4) {
                    Image(systemName: "paperplane.fill").font(.system(size: 24, weight: .bold))
                    Text("Share").font(.jakarta(11, .bold))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4)
            }
            Menu {
                if reel.authorEmail != me {
                    Button { reporting = ReportSheet.Target(id: reel.id, type: "reel", ownerEmail: reel.authorEmail, preview: reel.caption, link: "/Reels?r=\(reel.id)") } label: { Label("Report", systemImage: "flag") }
                } else {
                    Button(role: .destructive) { Task { try? await FS.delete("Reel", reel.id) } } label: { Label("Delete reel", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 30)
            }
        }
    }

    private func action(_ icon: String, _ label: String, tint: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(tint ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white))
                    .symbolEffect(.bounce, value: tint)
                Text(label).font(.jakarta(12, .bold)).foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.4), radius: 4)
        }
        .buttonStyle(BouncyStyle(scale: 0.8))
    }

    // Get the video ready (buffered, paused) before you swipe to it.
    private func preload() {
        guard reel.isVideo, video == nil, let url = URL(string: reel.mediaURL) else { return }
        video = ReelVideo.get(reel.id, url: url, start: reel.trimStart)
    }

    private func start() {
        if music.playing { music.pause() }
        if reel.isVideo {
            if video == nil, let url = URL(string: reel.mediaURL) {
                video = ReelVideo.get(reel.id, url: url, start: reel.trimStart)
            }
            ReelAudio.prepare()
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
