import SwiftUI
import AVKit

struct NativeTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let url: String
    let cover: String
    var preview = false
}

@MainActor @Observable
final class NativeMusicPlayer {
    var track: NativeTrack?
    var playing = false
    var error: String?
    let player = AVPlayer()
    private var status: NSKeyValueObservation?
    private var itemStatus: NSKeyValueObservation?
    init() {
        status = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in self?.playing = player.timeControlStatus == .playing }
        }
    }
    func toggle(_ next: NativeTrack) {
        guard let url = URL(string: next.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { error = "This track is unavailable."; return }
        if track?.id != next.id {
            error = nil
            track = next
            let item = AVPlayerItem(url: url)
            itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in if item.status == .failed { self?.error = "This track couldn't play. Try another song." } }
            }
            player.replaceCurrentItem(with: item)
        } else if playing { pause(); return }
        if player.currentItem?.status == .failed { error = "This track couldn't play. Try another song."; return }
        if let item = player.currentItem, item.duration.seconds.isFinite, player.currentTime().seconds >= item.duration.seconds - 0.1 { player.seek(to: .zero) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }
    func pause() { player.pause(); playing = false }
    func close() { pause(); player.replaceCurrentItem(with: nil); track = nil }
}

struct NativeMiniPlayer: View {
    @Environment(NativeMusicPlayer.self) private var music
    var body: some View {
        if let track = music.track {
            HStack(spacing: 10) {
                RemoteImage(url: track.cover).frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.subheadline.bold()).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { music.toggle(track) } label: { Image(systemName: music.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(music.playing ? "Pause" : "Play")
                Button { music.close() } label: { Image(systemName: "xmark").frame(width: 36, height: 44) }.accessibilityLabel("Close player")
            }.padding(.horizontal, 10).padding(.vertical, 5).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border, lineWidth: 1))
        }
    }
}

struct NativeMusicView: View {
    var onPick: ((NativeTrack) -> Void)? = nil
    @Environment(NativeMusicPlayer.self) private var music
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var community = false
    @State private var tracks: [NativeTrack] = []
    @State private var cursor: Doc?
    @State private var offset = 0
    @State private var more = true
    @State private var loading = false
    @State private var error: String?
    @State private var request = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SugerlyHeading(title: onPick == nil ? "Find your soundtrack." : "Set the mood.", subtitle: "Chart previews & sounds from your community.")
                    HStack {
                        sourceButton("Top charts", selected: !community) { community = false }
                        sourceButton("Community", selected: community) { community = true }
                    }
                    if !community {
                        HStack { Image(systemName: "magnifyingglass"); TextField("Songs or artists", text: $query).autocorrectionDisabled() }
                            .padding(14).background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                        Text("30-second previews from Deezer").font(.caption).foregroundStyle(.secondary)
                    }
                    if let playbackError = music.error { Text(playbackError).font(.footnote).foregroundStyle(.red) }
                    ForEach(tracks) { track in
                        Button {
                            if let onPick { onPick(track); dismiss() } else { music.toggle(track) }
                        } label: { trackRow(track) }.buttonStyle(.plain)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
                    } else if more {
                        ProgressView().id("\(offset)-\(cursor?.str("id") ?? "start")").frame(maxWidth: .infinity).padding().onAppear { if !loading { Task { await load() } } }
                    } else if tracks.isEmpty { Text("No songs found.").foregroundStyle(.secondary).padding() }
                }.padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(Theme.background)
                .navigationTitle("Music").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { NativeWordmark() }
                    if onPick != nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
                .task(id: "\(community)-\(query)") {
                    request = UUID(); tracks = []; cursor = nil; offset = 0; more = true; error = nil; loading = true
                    let current = request
                    try? await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 300))
                    guard !Task.isCancelled, current == request else { return }
                    loading = false
                    await load()
                }
        }
    }
    private func sourceButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.subheadline.bold()).padding(.horizontal, 18).padding(.vertical, 11).foregroundStyle(selected ? .white : Theme.pink).background(selected ? Theme.pink : Theme.soft, in: Capsule()) }.buttonStyle(.plain)
    }
    private func trackRow(_ track: NativeTrack) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: track.cover).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(.subheadline, design: .rounded).bold()).foregroundStyle(.primary).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: onPick != nil ? "plus.circle.fill" : music.track?.id == track.id && music.playing ? "pause.circle.fill" : "play.circle.fill").font(.title2).foregroundStyle(Theme.pink)
        }.padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 23)).overlay(RoundedRectangle(cornerRadius: 23).stroke(Theme.border, lineWidth: 1))
    }
    private func load() async {
        guard !loading, more else { return }
        loading = true; error = nil
        let current = request
        defer { if current == request { loading = false } }
        do {
            let next: [NativeTrack]
            if community {
                let page = try await FS.page("MusicReview", after: cursor)
                guard current == request, !Task.isCancelled else { return }
                cursor = page.rows.last ?? cursor; more = page.more
                next = page.rows.compactMap { d in
                    guard d.str("music_url").hasPrefix("https://") else { return nil }
                    return NativeTrack(id: d.str("id"), title: d.str("title"), artist: d.str("user_display_name"), url: d.str("music_url"), cover: d.str("cover_url"))
                }
            } else {
                var url = URLComponents(string: query.trimmingCharacters(in: .whitespaces).isEmpty ? "https://api.deezer.com/chart/0/tracks" : "https://api.deezer.com/search")!
                url.queryItems = [URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "index", value: "\(offset)")]
                if !query.isEmpty { url.queryItems?.append(URLQueryItem(name: "q", value: query)) }
                let json = try await HTTP.json(url.url!) as? [String: Any] ?? [:]
                guard current == request, !Task.isCancelled else { return }
                if json["error"] != nil { throw APIError(message: "The charts are unavailable. Try again.") }
                let rows = json["data"] as? [Doc] ?? []
                offset += rows.count; more = json["next"] is String
                next = rows.compactMap { d in
                    guard !d.str("preview").isEmpty else { return nil }
                    let artist = d["artist"] as? Doc ?? [:], album = d["album"] as? Doc ?? [:]
                    return NativeTrack(id: "deezer_\(d.int("id"))", title: d.str("title"), artist: artist.str("name"), url: d.str("preview"), cover: album.str("cover_medium"), preview: true)
                }
            }
            var known = Set(tracks.map(\.id))
            tracks.append(contentsOf: next.filter { known.insert($0.id).inserted })
        } catch { if current == request, !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
