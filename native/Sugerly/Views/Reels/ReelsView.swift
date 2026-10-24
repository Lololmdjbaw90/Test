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
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
    static func dismantleUIView(_ view: PlayerUIView, coordinator: ()) {
        view.playerLayer.player = nil
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
    // About phone-shaped (9:16): fills the whole screen, edge to edge.
    var tall = true
    private var statusObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?
    private var preparation: Task<Void, Never>?
    private var wantsPlayback = false
    private var loopStart = CMTime.zero
    private var loopObservation: NSKeyValueObservation?

    // Videos are kept around for the few reels near the one on screen, so
    // swiping to the next one starts right away.
    private static var pool: [String: ReelVideo] = [:]
    private static var order: [String] = []

    static func get(_ id: String, url: URL, start: Double, filter: String = "none", speed: Double = 1) -> ReelVideo {
        if let hit = pool[id] {
            order.removeAll { $0 == id }; order.append(id)
            return hit
        }
        let video = ReelVideo(url: url, start: start, filter: filter, speed: speed)
        pool[id] = video
        order.append(id)
        while order.count > 5 {
            guard let index = order.firstIndex(where: { pool[$0]?.wantsPlayback != true }) else { break }
            let old = order.remove(at: index)
            pool[old]?.pause()
            pool[old] = nil
        }
        return video
    }

    var progress: Double = 0
    private(set) var completedLoops = 0
    private(set) var restarts = 0
    private var timeObserver: Any?

    // Forget a video so the next try loads it fresh.
    static func drop(_ id: String) {
        pool[id]?.pause()
        pool[id] = nil
        order.removeAll { $0 == id }
    }

    init(url: URL, start: Double, filter: String = "none", speed: Double = 1) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        player.automaticallyWaitsToMinimizeStalling = true
        player.defaultRate = Float(max(0.25, min(3, speed)))
        preparation = Task { [weak self] in
            do {
                let duration = try await asset.load(.duration)
                guard let self, !Task.isCancelled else { return }
                guard duration.seconds.isFinite, duration.seconds > 0 else { self.failed = true; return }
                if filter != "none" {
                    item.videoComposition = try await AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
                        request.finish(with: WebFilter.apply(filter, to: request.sourceImage), context: nil)
                    })
                }
                guard !Task.isCancelled else { return }
                let offset = start.isFinite ? max(0, min(start, max(0, duration.seconds - 0.05))) : 0
                self.loopStart = CMTime(seconds: offset, preferredTimescale: 600)
                let range = offset > 0 ? CMTimeRange(start: CMTime(seconds: offset, preferredTimescale: 600), end: duration) : .invalid
                self.looper = AVPlayerLooper(player: self.player, templateItem: item, timeRange: range)
                self.loopObservation = self.looper?.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
                    let failed = looper.status == .failed
                    Task { @MainActor in if failed { self?.failed = true } }
                }
                if self.wantsPlayback { self.player.play() }
            } catch {
                guard !Task.isCancelled else { return }
                self?.failed = true
            }
        }
        player.isMuted = false
        statusObservation = player.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] p, _ in
            let status = p.currentItem?.status
            Task { @MainActor in
                if status == .failed { self?.failed = true }
                if status == .readyToPlay { self?.ready = true }
            }
        }
        sizeObservation = player.observe(\.currentItem?.presentationSize, options: [.initial, .new]) { [weak self] p, _ in
            let size = p.currentItem?.presentationSize ?? .zero
            Task { @MainActor in
                guard size.width > 0, size.height > 0 else { return }
                self?.portrait = size.height >= size.width * 1.1
                self?.tall = size.height >= size.width * 1.55
            }
        }
    }

    func play(fromStart: Bool = false) {
        wantsPlayback = true
        if looper != nil {
            if fromStart {
                player.pause()
                progress = 0
                restarts += 1
                player.seek(to: loopStart, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in if let self, self.wantsPlayback { self.player.play() } }
                }
            } else { player.play() }
        }
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, let item = self.player.currentItem else { return }
                    let total = item.duration.seconds
                    if total.isFinite, total > 0 {
                        self.duration = total
                        if self.progress > 0.8 && time.seconds / total < 0.2 { self.completedLoops += 1 }
                        self.progress = min(1, max(0, time.seconds / total))
                    }
                }
            }
        }
    }
    func pause() { wantsPlayback = false; player.pause() }

    var duration: Double = 0

    func seek(to fraction: Double) {
        guard let item = player.currentItem else { return }
        let total = item.duration.seconds
        guard total.isFinite, total > 0 else { return }
        progress = fraction
        player.seek(to: CMTime(seconds: fraction * total, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

// Set up playback audio once, not on every swipe (it can take a moment).
enum ReelAudio {
    nonisolated(unsafe) private static var ready = false
    static func prepare() {
        // Never during a call: that would turn the call's microphone off.
        if VoiceEngine.live { return }
        // (A voice channel switches the session to calls; switch back.)
        if ready && AVAudioSession.sharedInstance().category == .playback { return }
        ready = true
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }
}

// The Reels screen's colours, made from your theme colour so it sits with
// the rest of the app: a deep night version of it behind and around the
// videos (never plain black), and the same night as soft see-through glass
// for the buttons. Gradients run top to bottom.
enum ReelTone {
    static var night: Color { Color(hex: Palette.mix(Theme.partnerHex, 0x000000, 0.8)) }
    static var dusk: Color { Color(hex: Palette.mix(Theme.mainHex, 0x000000, 0.62)) }
    static var glass: Color { night.opacity(0.42) }
    // Your colour, deep enough to read on a white pill.
    static var ink: Color { Color(hex: Palette.mix(Theme.mainHex, 0x000000, 0.22)) }
    static var backdrop: LinearGradient {
        LinearGradient(colors: [dusk, night], startPoint: .top, endPoint: .bottom)
    }
    // Over the video, so the header and the white writing always read.
    static var shade: LinearGradient {
        LinearGradient(stops: [.init(color: night.opacity(0.5), location: 0), .init(color: .clear, location: 0.2),
                               .init(color: .clear, location: 0.55), .init(color: night.opacity(0.78), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// Before iOS 26 the tab bar over the reels is the same night glass. (iOS 26
// draws its own floating glass bar, which matches every other page.)
private struct ReelTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(ReelTone.night.opacity(0.7), for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
        }
    }
}

struct ReelsView: View {
    let visible: Bool
    @Binding var path: [Route]
    var create: () -> Void
    var initialReels: [Reel]? = nil
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var music
    @State private var reels: [Reel] = []
    @State private var activeId: String?
    @State private var feed = "foryou"
    @Namespace private var feedLine
    @State private var loading = true
    @State private var lastLoad: Date?
    @State private var cursor: String?
    @State private var exhausted = false
    @State private var loadingMore = false
    @State private var pageCount = 0
    // Paging through the server's ranking (scripts/rank.mjs), best first.
    @State private var hotCursor: Double?
    @State private var hotExhausted = false
    // Pull down on the first reel to refresh (like TikTok).
    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var refreshing = false
    private let pullToRefresh: CGFloat = 90

    private var shown: [Reel] {
        let blocked = Set(model.me?.blocked ?? [])
        let list = reels.filter { !blocked.contains($0.authorEmail) && !Removed.shared.ids.contains($0.id) }
        if feed == "following" {
            let following = Set(model.me?.following ?? [])
            return list.filter { following.contains($0.authorEmail) }
        }
        return list
    }

    var body: some View {
        ZStack(alignment: .top) {
            ReelTone.backdrop.ignoresSafeArea()
            if loading && reels.isEmpty {
                ReelSkeleton().transition(.opacity)
            } else if shown.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 40)).foregroundStyle(Theme.gradient)
                    Text(feed == "following" ? "No reels from people you follow" : "No reels yet").font(.display(26)).foregroundStyle(.white)
                    Button("Create a reel", action: create).buttonStyle(GradientButtonStyle(fullWidth: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The reels fill the whole screen, under the clock and the
                // tab bar (the writing and buttons keep clear of both). The
                // reader keeps to the safe area so it can say how big the
                // clock and tab bar are; only the scrolling goes edge to edge.
                GeometryReader { geo in
                    let list = shown
                    let activeIndex = list.firstIndex { $0.id == activeId } ?? 0
                    let safe: EdgeInsets = geo.safeAreaInsets
                    let width: CGFloat = geo.size.width + safe.leading + safe.trailing
                    let height: CGFloat = geo.size.height + safe.top + safe.bottom
                    // On iPad (or any wide screen) the reel is a phone-shaped
                    // card in the middle, on a blurred copy of its cover.
                    let column: CGFloat = Swift.min(width, height * 0.6)
                    let wide: Bool = column < width - 1
                    let room: CGFloat = wide ? geo.size.height : height
                    let card: CGFloat = Swift.min(column, room * 9 / 16)
                    let lift: CGFloat = wide ? (safe.top - safe.bottom) / 2 : 0
                    let pageInsets: EdgeInsets = wide ? EdgeInsets() : safe
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, reel in
                                ZStack {
                                    if wide {
                                        RemoteImage(url: reel.coverURL.isEmpty ? (reel.pictures.first ?? "") : reel.coverURL)
                                            .blur(radius: 40)
                                            .overlay(ReelTone.night.opacity(0.5))
                                    }
                                    ReelPage(reel: reel, active: visible && activeId == reel.id, near: abs(i - activeIndex) <= 1, path: $path,
                                             insets: pageInsets, loadContent: initialReels == nil,
                                             onNext: { advance(from: reel.id) }, onHide: { hide($0) })
                                        .frame(width: card, height: room)
                                        .clipShape(RoundedRectangle(cornerRadius: wide ? 28 : 0, style: .continuous))
                                        .offset(y: lift)
                                }
                                .frame(width: width)
                                .containerRelativeFrame(.vertical)
                                .clipped()
                                .id(reel.id)
                            }
                        }
                        .scrollTargetLayout()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named("reels")).minY
                        } action: { y in
                            pullChanged(max(0, y))
                        }
                    }
                    .coordinateSpace(.named("reels"))
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $activeId, anchor: .top)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .clipped()
                    .accessibilityIdentifier("reel-feed")
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .ignoresSafeArea()
                }
            }

            refreshBadge
            feedSwitch
                .frame(maxWidth: .infinity)
                .opacity(pull > 8 || refreshing ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: pull > 8 || refreshing)
                .overlay(alignment: .trailing) {
                    // Like the + on the other pages: your colour, round.
                    Button(action: create) {
                        Image(systemName: "camera.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Theme.gradient, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle())
                    .accessibilityLabel("Make a reel")
                    .padding(.trailing, 16)
                }
                .padding(.top, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        // The reel's buttons sit just above the tab bar.
        .modifier(ReelTabBar())
        .task {
            if let initialReels {
                if reels.isEmpty { reels = initialReels; activeId = initialReels.first?.id }
                loading = false
                return
            }
            if let lastLoad, Date().timeIntervalSince(lastLoad) < 90 { return }
            lastLoad = Date()
            await load()
        }
        .onChange(of: visible, initial: true) { _, now in
            music.setSuppressed("reel-feed", active: now)
            if now { AppleMusic.shared.stop() }
            if now, activeId == nil { activeId = shown.first?.id }
            if now && initialReels == nil { Task { await checkNew() } }
        }
        .onAppear { music.setSuppressed("reel-feed", active: visible) }
        .onDisappear { music.setSuppressed("reel-feed", active: false) }
        .onReceive(NotificationCenter.default.publisher(for: Self.posted)) { note in
            if let reel = note.object as? Reel { showPosted(reel) }
        }
        .onChange(of: activeId) { _, id in
            // Fetch the next page before you reach the end.
            guard let id, let i = shown.firstIndex(where: { $0.id == id }), i >= shown.count - 6 else { return }
            Task { await loadMore() }
        }
    }

    private static let pageSize = 30
    static let posted = Notification.Name("sugerly.reelPosted")

    // Your new reel goes straight to the top of the feed.
    private func showPosted(_ reel: Reel) {
        reels.removeAll { $0.id == reel.id }
        reels.insert(reel, at: 0)
        Self.cache = reels
        feed = "foryou"
        activeId = reel.id
    }

    // Coming back to Reels: slot any brand-new reels in right after the one
    // you're on, so the next swipe shows them (nothing jumps under you).
    private func checkNew() async {
        guard let lastLoad, Date().timeIntervalSince(lastLoad) > 45, !refreshing else { return }
        self.lastLoad = Date()
        guard let docs = try? await FS.query("Reel", orderBy: "created_date", limit: 12) else { return }
        let known = Set(reels.map(\.id))
        let fresh = docs.map(Reel.init).filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let ranked = await ReelBrain.shared.rank(fresh, me: model.me?.email ?? "", following: Set(model.me?.following ?? []))
        let at = (reels.firstIndex { $0.id == activeId } ?? -1) + 1
        reels.insert(contentsOf: ranked, at: min(at, reels.count))
        Self.cache = reels
    }

    // Following / For you: a little glass pill with a white bubble on the
    // one you're on (like the tab bar's), sliding across when you switch.
    private var feedSwitch: some View {
        HStack(spacing: 2) {
            ForEach([("following", "Following"), ("foryou", "For you")], id: \.0) { id, title in
                Button { withMotion(Motion.standard) { feed = id; activeId = shown.first?.id } } label: {
                    Text(title)
                        .font(.jakarta(15, .heavy))
                        .foregroundStyle(feed == id ? ReelTone.ink : Color.white.opacity(0.88))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background { feedBubble(feed == id) }
                        .contentShape(Capsule())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityAddTraits(feed == id ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ReelTone.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func feedBubble(_ on: Bool) -> some View {
        if on {
            Capsule().fill(.white).matchedGeometryEffect(id: "line", in: feedLine)
        }
    }

    // The "pull to refresh" pill that replaces the tabs while you pull.
    @ViewBuilder
    private var refreshBadge: some View {
        if pull > 8 || refreshing {
            let progress = min(1, pull / pullToRefresh)
            HStack(spacing: 8) {
                if refreshing {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(armed ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: armed)
                }
                Text(refreshing ? "Refreshing…" : armed ? "Release to refresh" : "Pull to refresh")
                    .font(.jakarta(14, .bold))
            }
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 14).frame(height: 34)
            .background(ReelTone.glass, in: Capsule())
            .opacity(refreshing ? 1 : Double(progress))
            .scaleEffect(refreshing ? 1 : 0.85 + 0.15 * progress)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }

    private func pullChanged(_ y: CGFloat) {
        guard !refreshing else { pull = 0; return }
        pull = y
        if y >= pullToRefresh, !armed {
            armed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if y < 6, armed {
            // Let go past the line: refresh.
            armed = false
            Task { await refresh() }
        }
    }

    // A brand-new For You page: fresh reels, unseen ones first.
    private func refresh() async {
        guard !refreshing else { return }
        withMotion(Motion.standard) { refreshing = true }
        defer { withMotion(Motion.standard) { refreshing = false } }
        async let top = Self.hot(below: nil, limit: 15)
        guard let docs = try? await FS.query("Reel", orderBy: "created_date", limit: Self.pageSize + 10) else { return }
        let newest = docs.map(Reel.init)
        let best = await top
        let have = Set(newest.map(\.id))
        let batch = newest + best.filter { !have.contains($0.id) }
        let ranked = await ReelBrain.shared.rank(batch, me: model.me?.email ?? "", following: Set(model.me?.following ?? []))
        guard !ranked.isEmpty else { return }
        await LikeBook.shared.prime(ranked)
        cursor = newest.map(\.created).filter { !$0.isEmpty }.min()
        exhausted = docs.count < Self.pageSize
        hotCursor = best.compactMap(\.rankScore).min()
        hotExhausted = best.count < 15
        Self.cache = ranked
        lastLoad = Date()
        withAnimation(.easeInOut(duration: 0.25)) {
            reels = ranked
            activeId = ranked.first?.id
        }
    }

    // First page: the newest reels, the server's best right now, a few from
    // people you follow and a few about the #tags you like most, ranked by
    // the on-device brain. Each source is one small indexed look-up and more
    // pages load as you scroll (cursor paging), so the feed stays light
    // however many reels exist.
    private func load() async {
        defer { withAnimation(Motion.fade) { loading = false } }
        if let cached = Self.cache, reels.isEmpty {
            reels = cached
            if activeId == nil { activeId = reels.first?.id }
        }
        async let top = Self.hot(below: nil, limit: 15)
        guard let docs = try? await FS.query("Reel", orderBy: "created_date", limit: Self.pageSize + 10) else { return }
        var batch = docs.map(Reel.init)
        cursor = batch.map(\.created).filter { !$0.isEmpty }.min()
        exhausted = docs.count < Self.pageSize
        let best = await top
        hotCursor = best.compactMap(\.rankScore).min()
        hotExhausted = best.count < 15
        let newest = Set(batch.map(\.id))
        batch += best.filter { !newest.contains($0.id) }
        let picks = Array((model.me?.following ?? []).shuffled().prefix(4))
        async let r0 = Self.reels(by: picks.count > 0 ? picks[0] : nil)
        async let r1 = Self.reels(by: picks.count > 1 ? picks[1] : nil)
        async let r2 = Self.reels(by: picks.count > 2 ? picks[2] : nil)
        async let r3 = Self.reels(by: picks.count > 3 ? picks[3] : nil)
        let favourites = await ReelBrain.shared.favouriteTags(2)
        let tagged = await Self.reels(tagged: favourites, before: nil)
        let extra = await r0 + r1 + r2 + r3
        var have = Set(batch.map(\.id))
        batch += (extra + tagged).filter { have.insert($0.id).inserted }
        let ranked = await ReelBrain.shared.rank(batch, me: model.me?.email ?? "", following: Set(model.me?.following ?? []))
        await LikeBook.shared.prime(ranked)
        Self.cache = ranked
        if reels.isEmpty { reels = ranked } else {
            // Keep what's on screen in place; add new ones behind it.
            let known = Set(reels.map(\.id))
            reels += ranked.filter { !known.contains($0.id) }
        }
        if activeId == nil { activeId = reels.first?.id }
    }

    // Auto-scroll and "Not interested" move on to the next reel.
    private func advance(from id: String) {
        let list = shown
        guard let i = list.firstIndex(where: { $0.id == id }), i + 1 < list.count else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { activeId = list[i + 1].id }
    }

    private func hide(_ id: String) {
        advance(from: id)
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withMotion(Motion.standard) { reels.removeAll { $0.id == id } }
        }
    }

    // The best reels right now, as scored on the server (scripts/rank.mjs).
    private static func hot(below score: Double?, limit: Int) async -> [Reel] {
        let filters: [FS.Filter] = score.map { [.below("rank_score", $0)] } ?? []
        return ((try? await FS.query("Reel", filters, orderBy: "rank_score", limit: limit)) ?? []).map(Reel.init)
    }

    private static func reels(by email: String?) async -> [Reel] {
        guard let email else { return [] }
        return ((try? await FS.query("Reel", [.equals("user_email", email)], limit: 4)) ?? []).map(Reel.init)
    }

    // A few reels for each #tag (newest first, or from before a moment in
    // the past for variety).
    private static func reels(tagged tags: [String], before: String?) async -> [Reel] {
        var out: [Reel] = []
        for tag in tags {
            var filters: [FS.Filter] = [.contains("tags", tag)]
            if let before { filters.append(.before("created_date", before)) }
            out += ((try? await FS.query("Reel", filters, orderBy: "created_date", limit: 6)) ?? []).map(Reel.init)
        }
        return out
    }

    // Next page. Most pages continue down the timeline; every third one also
    // dives to a random point in the past, so with millions of reels the feed
    // still surfaces older gems instead of only the newest.
    private func loadMore() async {
        guard !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        pageCount += 1
        var page: [Reel] = []
        if pageCount % 3 == 0 {
            let dive = Self.randomPoint(before: cursor)
            page = ((try? await FS.query("Reel", [.before("created_date", dive)], orderBy: "created_date", limit: 12)) ?? []).map(Reel.init)
        }
        if !exhausted, let cursor, let docs = try? await FS.query("Reel", [.before("created_date", cursor)], orderBy: "created_date", limit: Self.pageSize) {
            let timeline = docs.map(Reel.init)
            self.cursor = timeline.map(\.created).filter { !$0.isEmpty }.min() ?? cursor
            exhausted = docs.count < Self.pageSize
            page += timeline
        }
        // Every other page: a few about one of the #tags you like most, from
        // a random point in the past, so your interests keep showing up.
        if pageCount % 2 == 0, let tag = await ReelBrain.shared.favouriteTags(4).randomElement() {
            page += await Self.reels(tagged: [tag], before: Self.randomPoint(before: nil))
        }
        // Plus the next few from the server's ranking (liked, watched and
        // commented most for their age), so good reels reach everyone.
        if !hotExhausted, let hotCursor {
            let best = await Self.hot(below: hotCursor, limit: 8)
            self.hotCursor = best.compactMap(\.rankScore).min() ?? hotCursor
            hotExhausted = best.count < 8
            page += best
        }
        let known = Set(reels.map(\.id))
        var seenIds = Set<String>()
        let fresh = page.filter { !known.contains($0.id) && seenIds.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        let ranked = await ReelBrain.shared.rank(fresh, me: model.me?.email ?? "", following: Set(model.me?.following ?? []), recent: reels.suffix(2).map(\.authorEmail))
        await LikeBook.shared.prime(ranked)
        reels += ranked
    }

    nonisolated(unsafe) private static var cache: [Reel]?

    // A random moment within the year before the given time.
    private static func randomPoint(before cursor: String?) -> String {
        let end = Dates.parse(cursor ?? "") ?? Date()
        let start = end.addingTimeInterval(-365 * 86_400)
        return Dates.iso(Date(timeIntervalSince1970: Double.random(in: start.timeIntervalSince1970...end.timeIntervalSince1970)))
    }
}

// One reel filling the screen.
struct ReelPage: View {
    @State var reel: Reel
    let active: Bool
    var near = true
    @Binding var path: [Route]
    var showBack = false
    // The screen's notch / home bar and the floating tab bar, so the
    // buttons sit just clear of them on every iPhone and iPad.
    var insets = EdgeInsets()
    var loadContent = true
    var bottomRoom: CGFloat = 0
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var watchStart: Date?
    @State private var useSound = false
    @State private var sharing = false
    @State private var hearts: [HeartBurst] = []
    @State private var captionOpen = false
    @State private var justFollowed = false
    @State private var scrubbing = false
    @State private var lastProgress: Double = 0
    @AppStorage("sugerly.reels.muted") private var muted = false
    @AppStorage("sugerly.reels.speed") private var playSpeed = 1.0
    @AppStorage("sugerly.reels.autoscroll") private var autoScroll = false
    @AppStorage("sugerly.reels.clear") private var clearMode = false
    var onNext: () -> Void = {}
    var onHide: (String) -> Void = { _ in }

    private var me: String { model.me?.email ?? "" }
    private var liked: Bool { LikeBook.shared.isLiked(reel, me: me) }
    private var saved: Bool { model.me?.savedReels.contains(reel.id) ?? false }
    private var author: UserProfile? { model.person(reel.authorEmail) }
    private var following: Bool { model.me?.following.contains(reel.authorEmail) ?? false }

    var body: some View {
        ZStack {
            ReelTone.backdrop
            GeometryReader { frame in
                // The reel's 9:16 stage, with its text stickers on it.
                let stage = Self.stage(frame.size, fill: fillsScreen)
                ZStack {
                    media
                    if !reel.texts.isEmpty {
                        ReelTextLayer(texts: reel.texts, active: active).allowsHitTesting(false)
                    }
                }
                .frame(width: stage.width, height: stage.height)
                .frame(width: frame.size.width, height: frame.size.height)
                .clipped()
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture(count: 1))
                    .onEnded { tap in
                        switch tap {
                        case .first(let value): doubleTap(at: value.location)
                        case .second: togglePause()
                        }
                    }
            )
            .onLongPressGesture(minimumDuration: 0.45) { sharing = true }
            .accessibilityIdentifier("reel-media")
            ReelTone.shade
                .allowsHitTesting(false)
            if paused {
                Image(systemName: "play.fill").font(.system(size: 60)).foregroundStyle(.white.opacity(0.85)).shadow(radius: 10)
                    .transition(.pop)
                    .allowsHitTesting(false)
            }
            ForEach(hearts) { HeartBurstView(burst: $0).allowsHitTesting(false) }
            if clearMode {
                VStack {
                    HStack {
                        Spacer()
                        Button { withMotion(Motion.standard) { clearMode = false } } label: {
                            Label("Show", systemImage: "eye.fill").font(.jakarta(13, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 36).background(ReelTone.glass, in: Capsule())
                        }
                        .padding(.trailing, 16).padding(.top, insets.top + (showBack ? 8 : 50))
                    }
                    Spacer()
                }
                .transition(.opacity)
            } else {
                overlay.transition(.opacity)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sharing) { _, now in now }
        .animation(.easeInOut(duration: 0.25), value: clearMode)
        .onChange(of: video?.progress ?? 0) { _, now in
            // Finished a loop: auto-scroll to the next reel.
            if autoScroll && active && !scrubbing && lastProgress > 0.9 && now < 0.1 { onNext() }
            lastProgress = now
        }
        .onChange(of: playSpeed) { _, _ in applySpeed() }
        .sheet(isPresented: $sharing) {
            ReelShareSheet(reel: reel, mine: reel.authorEmail == me,
                           onNotInterested: { notInterested() },
                           onReport: { reporting = ReportSheet.Target(id: reel.id, type: "reel", ownerEmail: reel.authorEmail, preview: reel.caption, link: "/Reels?r=\(reel.id)") },
                           onDelete: { deleteReel() },
                           onUseSound: { useSound = true })
                .presentationDetents([.height(500), .large])
                .presentationCornerRadius(30)
        }
        .onAppear {
            if active { start(restart: true) } else if near { preload() }
        }
        .onChange(of: near) { _, now in if now && !active { preload() } }
        .onDisappear { video?.pause(); sound?.pause(); learnWatch() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && active { start() }
            else { video?.pause(); sound?.pause() }
        }
        .onChange(of: active) { _, now in
            if now { start(restart: true); watchStart = Date() } else { video?.pause(); sound?.pause(); learnWatch() }
        }
        .confirmationDialog(soundName, isPresented: $useSound, titleVisibility: .visible) {
            Button("Use this sound") { Task { await takeSound() } }
        } message: {
            Text("Make your own reel with this sound")
        }
        .onChange(of: muted) { _, now in
            video?.player.isMuted = now || reel.muted
            sound?.isMuted = now
        }
        .task(id: reel.id) { if loadContent { await refreshComments() } }
        .sheet(isPresented: $comments, onDismiss: { Task { await refreshComments() } }) {
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

    // Phone-shaped videos fill the whole screen edge to edge (a little comes
    // off the sides, like TikTok). Photos and wider videos are shown whole on
    // the backdrop.
    private var fillsScreen: Bool {
        reel.isVideo && video?.failed != true && (video?.tall ?? true)
    }

    static func stage(_ size: CGSize, fill: Bool) -> CGSize {
        let w = size.width, h = size.height
        let cover = CGSize(width: max(w, h * 9 / 16), height: max(h, w * 16 / 9))
        // (Never more than a little off the sides.)
        if fill && cover.width <= w * 1.3 && cover.height <= h * 1.3 { return cover }
        return CGSize(width: min(w, h * 9 / 16), height: min(h, w * 16 / 9))
    }

    @ViewBuilder
    private var media: some View {
        if reel.isVideo {
            if let video, !video.failed {
                ZStack {
                    // The cover shows at once; the video fades in over it.
                    if !video.ready { RemoteImage(url: reel.coverURL, contentMode: .fit) }
                    LoopingVideo(player: video.player, fill: video.tall)
                        .scaleEffect(x: reel.mirror ? -1 : 1, y: 1)
                        .opacity(video.ready ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: video.ready)
                }
            } else {
                ZStack {
                    RemoteImage(url: reel.coverURL)
                    if video?.failed == true {
                        VStack(spacing: 10) {
                            Label("This video didn't load", systemImage: "exclamationmark.triangle.fill")
                                .font(.jakarta(13, .semibold)).foregroundStyle(.white)
                            Button {
                                ReelVideo.drop(reel.id)
                                video = nil
                                start()
                            } label: { Label("Try again", systemImage: "arrow.clockwise") }
                                .buttonStyle(GradientButtonStyle(height: 40, fullWidth: false))
                        }
                        .padding(14).background(ReelTone.night.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            // Photos stay put until you swipe to the next one (they used to
            // move on by themselves).
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()
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
                    Button { if path.isEmpty { dismiss() } else { path.removeLast() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(ReelTone.glass, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, insets.top + 6)
            }
            if muted && active {
                Button { withMotion(Motion.standard) { muted = false } } label: {
                    Label("Tap for sound", systemImage: "speaker.slash.fill")
                        .font(.jakarta(14, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(ReelTone.glass, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(BouncyStyle())
                .padding(.top, showBack ? 10 : insets.top + 50)
                .transition(.pop)
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
                ReelSeekBar(video: video) { on in
                    scrubbing = on
                    if on { video.pause() } else if !paused { video.play() }
                }
            }
        }
        .padding(.bottom, insets.bottom + (showBack ? 14 : bottomRoom + 2))
    }

    private var relation: String? {
        guard let meProfile = model.me, reel.authorEmail != me else { return nil }
        let theyFollow = author?.following.contains(me) ?? false
        if following && theyFollow { return "From your friend" }
        if following { return "From someone you follow" }
        if theyFollow { return "Follows you" }
        if reel.likeTotal >= 10 { return "Trending" }
        _ = meProfile
        return nil
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { path.append(.person(reel.authorEmail)) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("@\(author?.displayName ?? reel.authorName)").font(.jakarta(17, .heavy)).foregroundStyle(.white)
                    Text("· \(Dates.ago(reel.created))").font(.jakarta(13)).foregroundStyle(.white.opacity(0.7))
                    if reel.views > 0 {
                        Label(Self.compact(reel.views), systemImage: "play.fill").font(.jakarta(12, .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .buttonStyle(SoftPressStyle())
            if let relation {
                Label(relation, systemImage: "sparkles")
                    .font(.jakarta(12, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(ReelTone.glass, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }
            if !reel.caption.isEmpty {
                Button { withMotion(Motion.standard) { captionOpen.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReelCaption.styled(reel.caption)).font(.jakarta(15)).foregroundStyle(.white)
                            .lineLimit(captionOpen ? 12 : 2).multilineTextAlignment(.leading)
                        if reel.caption.count > 70 {
                            Text(captionOpen ? "less" : "more").font(.jakarta(13, .heavy)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(SoftPressStyle())
            }
            if !reel.musicTitle.isEmpty || reel.isVideo {
                Button { useSound = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note").font(.system(size: 14, weight: .semibold))
                        Text(soundName).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).opacity(0.7)
                    }
                    .font(.jakarta(14, .medium)).foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(ReelTone.glass, in: Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.95))
            }
        }
        .shadow(color: ReelTone.night.opacity(0.5), radius: 3, y: 1)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { path.append(.person(reel.authorEmail)) } label: {
                Avatar(url: author?.picture ?? reel.authorPicture, name: author?.displayName ?? reel.authorName, size: 48, nitro: author?.isNitro ?? false)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .overlay(alignment: .bottom) {
                        if (!following || justFollowed) && reel.authorEmail != me {
                            Image(systemName: justFollowed ? "checkmark" : "plus").font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(justFollowed ? ReelTone.ink : .white)
                                .frame(width: 22, height: 22)
                                .background(justFollowed ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.gradient), in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .contentTransition(.symbolEffect(.replace))
                                .offset(y: 10)
                                .onTapGesture { follow() }
                                .transition(.pop)
                        }
                    }
            }
            .buttonStyle(BouncyStyle())
            .padding(.bottom, 6)
            bubble(liked ? "heart.fill" : "heart", count: reel.likeTotal, tint: liked) { toggleLike() }
                .accessibilityLabel(liked ? "Unlike" : "Like")
                .sensoryFeedback(.impact(weight: .light), trigger: liked)
            bubble("bubble.left", count: reel.commentsOff ? nil : commentCount) {
                comments = true
                let r = reel
                Task { await ReelBrain.shared.commented(r) }
            }
            .accessibilityLabel("Comments")
            bubble(saved ? "bookmark.fill" : "bookmark", tint: saved) { toggleSave() }
                .accessibilityLabel(saved ? "Unsave" : "Save")
            bubble("arrowshape.turn.up.right.fill") { sharing = true }
                .accessibilityLabel("Share")
            Button { useSound = true } label: {
                MusicDisc(picture: author?.picture ?? reel.authorPicture, name: author?.displayName ?? reel.authorName, spinning: active && !paused)
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Use this sound")
            .padding(.top, 4)
        }
    }

    // A round button of night glass with an optional count under it; when
    // it's on (liked, saved) it fills with your colour, like the + elsewhere.
    private func bubble(_ icon: String, count: Int? = nil, tint: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                bubbleLabel(icon, tint: tint)
                if let count {
                    Text("\(count)").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                        .shadow(color: ReelTone.night.opacity(0.6), radius: 2, y: 1)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(BouncyStyle(scale: 0.85))
    }

    private func bubbleLabel(_ icon: String, tint: Bool) -> some View {
        // (No frosted blur or soft shadow: plain fills stay smooth while
        // you swipe.)
        Image(systemName: icon)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce, value: tint)
            .frame(width: 48, height: 48)
            .background(tint ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(ReelTone.glass), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(tint ? 0.4 : 0.16), lineWidth: 1))
    }

    // Get the video ready (buffered, paused) before you swipe to it.
    private func preload() {
        guard reel.isVideo, video == nil, let url = URL(string: reel.mediaURL) else { return }
        video = ReelVideo.get(reel.id, url: url, start: reel.trimStart, filter: reel.filterId, speed: reel.speed)
    }

    private func start(restart: Bool = false) {
        if restart { paused = false; sound?.seek(to: .zero) }
        AppleMusic.shared.stop()
        if reel.isVideo {
            if video == nil, let url = URL(string: reel.mediaURL) {
                video = ReelVideo.get(reel.id, url: url, start: reel.trimStart, filter: reel.filterId, speed: reel.speed)
            }
            ReelAudio.prepare()
            applySpeed()
            video?.player.isMuted = muted || reel.muted
            if !paused { video?.play(fromStart: restart) }
        }
        if !paused { startSound() }
        if loadContent { countView() }
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
            guard active, !paused, scenePhase == .active, wanted == reel.id, sound == nil, let url = URL(string: link), !link.isEmpty else { return }
            let p = AVPlayer(url: url)
            p.isMuted = muted
            p.defaultRate = currentRate   // the song keeps pace with the video
            p.play()
            sound = p
        }
    }

    private func togglePause() {
        withMotion(Motion.standard) { paused.toggle() }
        if paused {
            video?.pause()
            sound?.pause()
        } else {
            if reel.isVideo { video?.play() }
            sound?.play()
        }
    }

    // Double-tap: a heart pops where you tapped (tap again for more).
    private func doubleTap(at point: CGPoint) {
        if !liked { toggleLike() }
        let burst = HeartBurst(point: point, angle: Double.random(in: -22...22))
        hearts.append(burst)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(1000))
            hearts.removeAll { $0.id == burst.id }
        }
    }

    private var currentRate: Float { Float(max(0.25, min(3, reel.speed * playSpeed))) }

    // Video and its song change speed together, so they stay in sync.
    private func applySpeed() {
        let rate = currentRate
        video?.player.defaultRate = rate
        if video?.player.timeControlStatus == .playing { video?.player.rate = rate }
        sound?.defaultRate = rate
        if sound?.timeControlStatus == .playing { sound?.rate = rate }
    }

    private func refreshComments() async {
        let docs = (try? await FS.query("CommunityComment", [.equals("post_id", "reel_\(reel.id)")], orderBy: "created_date", limit: 200)) ?? []
        commentCount = docs.count
    }

    private func notInterested() {
        let r = reel
        Task { await ReelBrain.shared.notInterested(r) }
        model.showToast("Got it — you'll see fewer reels like this", icon: "heart.slash.fill")
        onHide(reel.id)
    }

    private func deleteReel() {
        let id = reel.id
        Task {
            try? await FS.delete("Reel", id)
            Removed.shared.add(id)
            model.showToast("Reel deleted", icon: "trash.fill")
        }
        onHide(id)
    }

    static func compact(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private func toggleLike() {
        guard let meProfile = model.me else { return }
        let before = reel
        let liking = !LikeBook.shared.isLiked(before, me: me)
        TapSound.play(liking ? .like : .tap)
        reel.setLiked(liking, me: me)
        let r = reel
        Task { await ReelBrain.shared.liked(r, liking) }
        Task {
            do {
                try await LikeBook.shared.write(before, liking: liking, me: me, owner: before.authorEmail)
                if liking { Notify.send(to: reel.authorEmail, from: meProfile, type: "like", message: "\(meProfile.displayName) liked your reel", link: "/Reels?r=\(reel.id)") }
            } catch { reel.restoreLikes(from: before) }
        }
    }

    private func toggleSave() {
        guard let meProfile = model.me else { return }
        var next = meProfile.savedReels
        let saving = !next.contains(reel.id)
        if saving { next.append(reel.id) } else { next.removeAll { $0 == reel.id } }
        let r = reel
        Task { await ReelBrain.shared.saved(r, saving) }
        Task { try? await model.updateMe(["saved_reels": next]) }
    }

    private func follow() {
        guard let meProfile = model.me else { return }
        let email = reel.authorEmail
        Task { await ReelBrain.shared.followed(email) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { justFollowed = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.25)) { justFollowed = false }
        }
        Task {
            try? await model.updateMe(["following": meProfile.following + [reel.authorEmail]])
            Notify.send(to: reel.authorEmail, from: meProfile, type: "follow", message: "\(meProfile.displayName) started following you", link: "/Profile?email=\(meProfile.email)")
        }
    }

    private var soundName: String {
        if !reel.musicTitle.isEmpty { return "\(reel.musicTitle)\(reel.musicArtist.isEmpty ? "" : " · \(reel.musicArtist)")" }
        return "Original sound · \(author?.displayName ?? reel.authorName)"
    }

    // How long you watched teaches the For You brain.
    private func learnWatch() {
        guard let started = watchStart else { return }
        watchStart = nil
        let seconds = Date().timeIntervalSince(started)
        let r = reel
        Task { await ReelBrain.shared.watched(r, seconds: seconds) }
    }

    // "Use this sound": the song (with a fresh preview link) or the video's own sound.
    private func takeSound() async {
        var link = reel.musicURL
        var id = "reel_\(reel.id)"
        if reel.musicSource.hasPrefix("deezer:"), let dz = reel.musicSource.split(separator: ":").last {
            id = "deezer_\(dz)"
            if let url = URL(string: "https://api.deezer.com/track/\(dz)"),
               let json = try? await HTTP.json(url) as? [String: Any], let fresh = json["preview"] as? String, !fresh.isEmpty {
                link = fresh
            }
        }
        if reel.musicTitle.isEmpty { link = reel.mediaURL }
        guard !link.isEmpty else { return }
        video?.pause()
        sound?.pause()
        let track = Track([
            "id": id,
            "title": reel.musicTitle.isEmpty ? "Original sound" : reel.musicTitle,
            "user_display_name": reel.musicTitle.isEmpty ? reel.authorName : reel.musicArtist,
            "music_url": link,
            "cover_url": reel.coverURL.isEmpty ? (author?.picture ?? reel.authorPicture) : reel.coverURL,
        ])
        model.soundRequest = track
    }

    // A view counts once per person (not rewatches, not your own).
    private func countView() {
        guard !me.isEmpty, reel.authorEmail != me else { return }
        let key = "sugerly.viewed.\(me)"
        var seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard !seen.contains(reel.id) else { return }
        seen.insert(reel.id)
        UserDefaults.standard.set(Array(seen.suffix(4000)), forKey: key)
        reel.views += 1
        Task { try? await FS.change("Reel", reel.id, [.increment("views", 1)], set: ["updated_date": FS.nowISO()]) }
    }
}

// A single reel opened from a profile.
struct SingleReelView: View {
    let reel: Reel
    @Binding var path: [Route]
    var loadContent = true
    @Environment(\.dismiss) private var dismiss
    @Environment(Player.self) private var music
    var body: some View {
        GeometryReader { geo in
            // The reel fills the whole screen (the reader keeps to the safe
            // area so it knows the clock's and home bar's size). On iPad
            // it's a phone-shaped card on a blurred copy of its cover, like
            // in the feed.
            let safe: EdgeInsets = geo.safeAreaInsets
            let width: CGFloat = geo.size.width + safe.leading + safe.trailing
            let height: CGFloat = geo.size.height + safe.top + safe.bottom
            let column: CGFloat = Swift.min(width, height * 0.6)
            let wide: Bool = column < width - 1
            let room: CGFloat = wide ? geo.size.height : height
            let card: CGFloat = Swift.min(column, room * 9 / 16)
            let lift: CGFloat = wide ? (safe.top - safe.bottom) / 2 : 0
            ZStack {
                ReelTone.backdrop
                if wide {
                    RemoteImage(url: reel.coverURL.isEmpty ? (reel.pictures.first ?? "") : reel.coverURL)
                        .blur(radius: 40)
                        .overlay(ReelTone.night.opacity(0.5))
                }
                ReelPage(reel: reel, active: true, path: $path, showBack: false, insets: wide ? EdgeInsets() : safe, loadContent: loadContent)
                    .frame(width: card, height: room)
                    .clipShape(RoundedRectangle(cornerRadius: wide ? 28 : 0, style: .continuous))
                    .offset(y: lift)
            }
            .frame(width: width, height: height)
            .clipped()
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button {
                if path.isEmpty { dismiss() } else { path.removeLast() }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(ReelTone.glass, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .padding(.leading, 12).padding(.top, 6)
        }
        .background(ReelTone.backdrop.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { music.setSuppressed("single-reel", active: true) }
        .onDisappear { music.setSuppressed("single-reel", active: false) }
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
            .background(Circle().fill(LinearGradient(colors: [ReelTone.dusk, ReelTone.night], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
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
            if i > 0 { out += AttributedString(" ") }
            var piece = AttributedString(String(word))
            if word.hasPrefix("#") || word.hasPrefix("@") { piece.font = Font.jakarta(15, .heavy) }
            // A #tag opens its page (everything with it).
            if word.hasPrefix("#"), let tag = Hashtags.tags(String(word)).first { piece.link = Hashtags.link(tag) }
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
            case "bubbly": return .custom("BubblegumSans-Regular", size: size)
            case "cute": return .custom("CaveatBrush-Regular", size: size)
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
