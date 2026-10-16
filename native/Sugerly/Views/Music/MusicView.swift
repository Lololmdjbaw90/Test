import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// Today's hits from Deezer (30-second previews — the full song opens in
// Spotify, Apple Music, YouTube Music or Deezer).
enum Deezer {
    static let genres: [(Int, String)] = [(0, "Top"), (132, "Pop"), (116, "Hip-Hop"), (113, "Dance"), (165, "R&B"), (152, "Rock"), (197, "Latin"), (106, "Electro"), (16, "K-Pop")]

    static func page(genre: Int, query: String, index: Int, limit: Int = 25) async throws -> (tracks: [Track], more: Bool) {
        let q = query.trimmingCharacters(in: .whitespaces)
        var comps = URLComponents(string: q.isEmpty ? "https://api.deezer.com/chart/\(genre)/tracks" : "https://api.deezer.com/search")!
        comps.queryItems = [URLQueryItem(name: "index", value: "\(index)"), URLQueryItem(name: "limit", value: "\(limit)")] + (q.isEmpty ? [] : [URLQueryItem(name: "q", value: q)])
        let json = try await HTTP.json(comps.url!) as? [String: Any] ?? [:]
        let raw = json["data"] as? [[String: Any]] ?? []
        let tracks: [Track] = raw.compactMap { t in
            guard let id = t["id"], let preview = t["preview"] as? String, !preview.isEmpty else { return nil }
            let artist = (t["artist"] as? [String: Any])?["name"] as? String ?? ""
            let album = t["album"] as? [String: Any] ?? [:]
            let cover = album["cover_medium"] as? String ?? album["cover_big"] as? String ?? ""
            let title = t["title_short"] as? String ?? t["title"] as? String ?? ""
            return Track(id: "deezer_\(id)", title: title, artist: artist, audioURL: preview, coverURL: cover, external: URL(string: t["link"] as? String ?? ""))
        }
        let total = json["total"] as? Int ?? 0
        let more = !raw.isEmpty && (json["next"] != nil || (total > 0 && index + raw.count < total))
        return (tracks, more)
    }
}

struct MusicView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track] = []
    @State private var charts: [Track] = []
    @State private var genre = 0
    @State private var query = ""
    @State private var chartsLoading = true
    @State private var chartsError = false
    @State private var showAllUploads = false
    @State private var apple = AppleMusic.shared
    @State private var fullFor: Track?
    @State private var uploading = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        if path.isEmpty { dismiss() } else { withAnimation(.smooth(duration: 0.3)) { _ = path.popLast() } }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                            .frame(width: 44, height: 44)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle())
                    .accessibilityLabel("Back")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Music").font(.display(40)).foregroundStyle(Palette.text)
                        Text("\(tracks.count) tracks from \(Set(tracks.map(\.authorEmail)).count) artists").font(.jakarta(14)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { uploading = true } label: { Image(systemName: "arrow.up").font(.system(size: 17, weight: .heavy)) }
                        .buttonStyle(GradientButtonStyle(height: 46, fullWidth: false))
                        .accessibilityLabel("Share a track")
                }
                if let pick = tracks.first { hero(pick) }
                appleMusicCard
                chartsSection
                if !tracks.isEmpty {
                    SectionHeader(icon: "music.note.list", title: "All tracks")
                    // Rows are built as they scroll into view (hundreds of songs
                    // at once made the page stutter).
                    LazyVStack(spacing: 6) {
                        ForEach(showAllUploads ? tracks : Array(tracks.prefix(30))) { t in TrackRow(track: t, list: tracks).songCard() }
                        if !showAllUploads && tracks.count > 30 {
                            Button { showAllUploads = true } label: {
                                Text("Show all \(tracks.count) tracks").font(.jakarta(14, .bold)).foregroundStyle(Theme.main)
                                    .frame(maxWidth: .infinity).frame(height: 44)
                            }
                            .buttonStyle(BouncyStyle(scale: 0.97))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .sideRails(760)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadUploads() }
        .task(id: "\(genre)|\(query)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            await loadCharts()
        }
        .sheet(item: $fullFor) { t in FullSongSheet(track: t).presentationDetents([.height(AppleMusic.shared.canPlayFull ? 440 : 360)]).presentationCornerRadius(32) }
        .fullScreenCover(isPresented: $uploading) { NewTrackView() }
    }

    // The newest upload, on its own cover art (blurred behind, tilted in
    // front), with little bars dancing while it plays.
    private func hero(_ t: Track) -> some View {
        let playing = player.isPlaying(t)
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: t.coverURL)
                    .overlay { if t.coverURL.isEmpty { Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.white.opacity(0.8)) } }
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                    .rotationEffect(.degrees(playing ? 0 : -3))
                if playing {
                    EqualizerBars(height: 16)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(.black.opacity(0.45), in: Capsule())
                        .offset(x: 8, y: 8)
                        .transition(.pop)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Picked for you", systemImage: "sparkles")
                    .font(.jakarta(12, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())
                Text(t.title).font(.display(25)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(t.artist).font(.jakarta(14, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                Button { player.play(t, in: tracks) } label: {
                    Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                        .font(.jakarta(15, .bold)).foregroundStyle(Theme.main)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 20).frame(height: 42)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                }
                .buttonStyle(BouncyStyle())
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            ZStack {
                Theme.gradient
                Color.clear.overlay { RemoteImage(url: t.coverURL) }
                    .blur(radius: 34)
                    .opacity(0.5)
                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.22)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Palette.shadow, radius: 12, y: 8)
        }
        .motion(Motion.playful, value: playing)
    }

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "chart.line.uptrend.xyaxis", title: "Top charts")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Songs or artists", text: $query).font(.jakarta(15)).submitLabel(.search)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            if query.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Deezer.genres, id: \.0) { id, name in
                            Chip(title: name, active: genre == id) { genre = id }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            LazyVStack(spacing: 4) {
                if chartsLoading && charts.isEmpty { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
                if chartsError && charts.isEmpty {
                    Text("Couldn't load the charts right now — try again in a moment.").font(.jakarta(14)).foregroundStyle(Palette.muted).padding(20)
                }
                ForEach(Array(charts.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, list: charts, rank: i + 1) { fullFor = t }.songCard()
                }
            }
            Text("Previews by Deezer · tap Full for the whole song").font(.jakarta(11)).foregroundStyle(Palette.muted)
        }
    }

    private func loadUploads() async {
        guard let docs = try? await FS.query("MusicReview", orderBy: "created_date", limit: 300) else { return }
        let list = docs.map(Track.init).filter { !$0.audioURL.isEmpty }
        await Self.prefetch(list.prefix(30).map(\.coverURL))
        tracks = list
    }

    // The whole chart in one go (covers fetched before it shows), so nothing
    // loads in while you scroll.
    private func loadCharts() async {
        chartsLoading = true
        chartsError = false
        defer { chartsLoading = false }
        do {
            let result = try await Deezer.page(genre: genre, query: query, index: 0, limit: 50)
            await Self.prefetch(result.tracks.map(\.coverURL))
            charts = result.tracks
        } catch {
            if !Task.isCancelled { chartsError = true; charts = [] }
        }
    }

    private static func prefetch(_ urls: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls where !url.isEmpty && MemoryImages.get(url) == nil {
                group.addTask { _ = await ImagePipeline.shared.load(url) }
            }
        }
    }

    private var appleMusicCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(hex: 0xFA2D48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                Text(apple.nowPlaying.map { "Playing \($0)" } ?? apple.summary)
                    .font(.jakarta(12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if apple.nowPlaying != nil {
                Button { apple.stop() } label: { Image(systemName: "stop.fill").frame(width: 38, height: 38) }
                    .buttonStyle(BouncyStyle()).foregroundStyle(Theme.main)
                    .accessibilityLabel("Stop Apple Music")
            } else if !apple.isConnected {
                Button { Task { await apple.connect() } } label: {
                    Text(apple.state == .connecting ? "…" : "Connect").font(.jakarta(13, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Color(hex: 0xFA2D48), in: Capsule())
                }
                .buttonStyle(BouncyStyle())
                .disabled(apple.state == .connecting)
            }
        }
        .sugarCard(radius: 22, padding: 12)
    }
}

struct FullSongSheet: View {
    let track: Track
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(Player.self) private var player
    @State private var apple = AppleMusic.shared
    @State private var appleError: String?
    @State private var starting = false

    private var query: String { "\(track.artist) \(track.title)" }
    private var apps: [(String, UInt32, URL?)] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return [
            ("Spotify", 0x1DB954, URL(string: "https://open.spotify.com/search/\(q)")),
            ("Apple Music", 0xFA2D48, URL(string: "https://music.apple.com/search?term=\(q)")),
            ("YouTube Music", 0xFF0000, URL(string: "https://music.youtube.com/search?q=\(q)")),
            ("Deezer", 0xA238FF, track.external ?? URL(string: "https://www.deezer.com/search/\(q)")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                RemoteImage(url: track.coverURL).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Listen to the full song").font(.jakarta(12, .bold)).foregroundStyle(Theme.pink)
                    Text(track.title).font(.display(22)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(track.artist).font(.jakarta(14)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.top, 24)
            if apple.canPlayFull {
                Button {
                    Task {
                        starting = true
                        player.pause()
                        appleError = await apple.playFull(title: track.title, artist: track.artist)
                        starting = false
                        if appleError == nil { dismiss() }
                    }
                } label: {
                    Label(starting ? "Starting…" : "Play the whole song here", systemImage: "play.fill")
                        .font(.jakarta(15, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Color(hex: 0xFA2D48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(BouncyStyle())
                .disabled(starting)
                if let appleError { Text(appleError).font(.jakarta(12, .semibold)).foregroundStyle(Palette.danger) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(apps, id: \.0) { name, color, url in
                    Button { if let url { openURL(url) }; dismiss() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(Color(hex: color), in: Circle())
                            Text(name).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 54)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle())
                }
            }
            Text("Opens the song in your music app. Labels only allow 30-second previews inside other apps.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .sugarBackground()
    }
}

// Upload your own song (audio file + optional cover).
struct NewTrackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var genre = ""
    @State private var mood = ""
    @State private var description = ""
    @State private var audio: URL?
    @State private var picking = false
    @State private var coverItem: PhotosPickerItem?
    @State private var cover: UIImage?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "Share a track", actionTitle: "Share", busy: busy, canPost: audio != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty,
                         hint: audio == nil ? "Choose your audio file first" : "Give your track a title",
                         status: busy ? "Uploading your track…" : nil, error: error,
                         onClose: { dismiss() }, onPost: { Task { await share() } }) {
            Button { picking = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: audio == nil ? "waveform.badge.plus" : "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(audio == nil ? "Choose an audio file" : audio!.lastPathComponent).font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("MP3, M4A or WAV · up to 20 MB").font(.jakarta(12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
                .sugarCard(radius: 22, padding: 14)
            }
            .buttonStyle(BouncyStyle(scale: 0.97))
            SugarField(placeholder: "Title", text: $title)
            HStack(spacing: 10) {
                SugarField(placeholder: "Genre (Lo-fi, Pop…)", text: $genre)
                SugarField(placeholder: "Mood (Chill…)", text: $mood)
            }
            SugarField(placeholder: "About this track (optional)", text: $description, lines: 3...6)
            PhotoPickerCard(item: $coverItem, image: $cover)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav]) { result in
            if case .success(let url) = result { audio = url; if title.isEmpty { title = url.deletingPathExtension().lastPathComponent } }
        }
    }

    private func share() async {
        guard let me = model.me, let audio else { return }
        error = nil
        guard await TextGuard.clear([title, genre, mood, description], kind: .caption, model: model) else { return }
        busy = true
        defer { busy = false }
        do {
            let access = audio.startAccessingSecurityScopedResource()
            defer { if access { audio.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: audio)
            guard data.count < 20 * 1024 * 1024 else { TextGuard.forget(.caption, model: model); error = "That file is over 20 MB."; return }
            let ext = audio.pathExtension.lowercased()
            let type = ext == "m4a" ? "audio/mp4" : ext == "wav" ? "audio/wav" : "audio/mpeg"
            let musicURL = try await StorageClient.upload(data, contentType: type, fileExtension: ext.isEmpty ? "mp3" : ext)
            var coverURL = ""
            if let cover, let jpeg = ImageTools.jpeg(cover, maxSide: 1000) {
                coverURL = try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg")
            }
            let now = FS.nowISO()
            let doc: Doc = [
                "title": title.trimmingCharacters(in: .whitespaces), "genre": genre, "mood": mood, "description": description,
                "music_url": musicURL, "cover_url": coverURL, "identified_song": "", "ai_review": "",
                "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
                "likes": [String](), "created_by": me.email, "created_date": now, "updated_date": now,
            ]
            try await FS.create("MusicReview", doc)
            try? await model.updateMe(["xp": me.xp + 15])
            dismiss()
            model.showToast("Track shared · +15 XP", icon: "music.note")
        } catch {
            TextGuard.forget(.caption, model: model)
            self.error = PostProblem.message(error)
        }
    }
}

private extension View {
    // Each song gets its own light card. (One tall card with a soft shadow
    // round a whole list had to redraw that shadow while you scrolled.)
    func songCard() -> some View {
        self.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
