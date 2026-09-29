import SwiftUI
import UIKit
import Photos

// MARK: - Sharing a reel (like TikTok's share sheet)

enum ReelLinks {
    static func url(_ reel: Reel) -> URL { URL(string: "\(Servers.site)/Reels?r=\(reel.id)")! }
    static func post(_ id: String) -> URL { URL(string: "\(Servers.site)/Community?post=\(id)")! }
    static func artwork(_ id: String) -> URL { URL(string: "\(Servers.site)/Gallery?art=\(id)")! }

    // Sends the reel into chats — same message shape as the website, so it
    // shows as a reel card there too.
    @MainActor
    static func send(_ reel: Reel, to targets: [ShareTarget], note: String, me: UserProfile) async throws {
        let link = url(reel).absoluteString
        let shared: [String: Any] = [
            "id": reel.id, "cover_url": reel.coverURL.isEmpty ? (reel.isVideo ? "" : reel.pictures.first ?? "") : reel.coverURL,
            "caption": String(reel.caption.prefix(120)), "by": reel.authorName,
        ]
        let content = [note.trimmingCharacters(in: .whitespacesAndNewlines), "\u{1F3AC} \(reel.authorName)'s reel: \(link)"].filter { !$0.isEmpty }.joined(separator: "\n")
        try await deliver(content, extra: ["shared_reel": shared], to: targets, me: me)
    }

    // Sends a community post into chats as a link message.
    @MainActor
    static func sendPost(_ post: Post, to targets: [ShareTarget], note: String, me: UserProfile) async throws {
        let link = self.post(post.id).absoluteString
        let content = [note.trimmingCharacters(in: .whitespacesAndNewlines), "\(post.authorName)'s post: \(link)"].filter { !$0.isEmpty }.joined(separator: "\n")
        try await deliver(content, extra: [:], to: targets, me: me)
    }

    @MainActor
    private static func deliver(_ content: String, extra: Doc, to targets: [ShareTarget], me: UserProfile) async throws {
        let now = FS.nowISO()
        for target in targets {
            var doc: Doc = [
                "content": content, "image_url": "",
                "user_email": me.email, "user_display_name": me.displayName, "user_profile_picture": me.picture,
                "read_by": [me.email], "reactions": [String: Any](), "is_edited": false,
                "created_by": me.email, "created_date": now, "updated_date": now,
            ]
            for (k, v) in extra { doc[k] = v }
            if target.isGroup {
                doc["conversation_id"] = target.id
                doc["conversation_type"] = "group"
                doc["group_name"] = target.name
                doc["member_emails"] = target.members
            } else {
                let other = target.members.first { $0 != me.email } ?? me.email
                doc["conversation_id"] = Social.dmId(me.email, other)
                doc["conversation_type"] = "dm"
                doc["group_name"] = ""
                doc["member_emails"] = [me.email, other].sorted()
            }
            _ = try await FS.create("DirectMessage", doc)
        }
    }

    // Downloads the video (or pictures) into your photo library.
    static func saveToPhotos(_ reel: Reel) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw APIError(message: "Allow Sugerly to add to Photos in Settings.") }
        if reel.isVideo {
            guard let link = URL(string: reel.mediaURL) else { return }
            let (temp, _) = try await URLSession.shared.download(from: link)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(reel.id).mp4")
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temp, to: file)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
            }
        } else {
            var images: [Data] = []
            for pic in reel.pictures {
                if let u = URL(string: pic), let (data, _) = try? await URLSession.shared.data(from: u) { images.append(data) }
            }
            try await PHPhotoLibrary.shared().performChanges {
                for data in images { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
            }
        }
    }
}

struct ShareTarget: Identifiable, Hashable {
    var id: String
    var name: String
    var picture: String
    var isGroup: Bool
    var members: [String]

    // Your recent chats, then people you follow.
    @MainActor
    static func all(_ model: AppModel, _ chats: ChatStore) -> [ShareTarget] {
        let me = model.me?.email ?? ""
        var out: [ShareTarget] = []
        var seen = Set<String>()
        // Only chats you can actually write in (no pending requests), and friends.
        for c in chats.conversations.prefix(30) where DMRules.state(c, model: model, chats: chats) == .open {
            let t = c.isGroup
                ? ShareTarget(id: c.id, name: c.title(model), picture: "", isGroup: true, members: c.members)
                : ShareTarget(id: "dm:" + (c.others(me).first ?? me), name: c.title(model), picture: c.picture(model), isGroup: false, members: c.members.isEmpty ? [me] : c.members)
            if seen.insert(t.id).inserted { out.append(t) }
        }
        for email in model.me?.following ?? [] where !seen.contains("dm:" + email) && DMRules.friends(model, email) {
            guard let p = model.person(email) else { continue }
            seen.insert("dm:" + email)
            out.append(ShareTarget(id: "dm:" + email, name: p.displayName, picture: p.picture, isGroup: false, members: [me, email]))
        }
        return out
    }
}

// A small "Send to" sheet for posts and art.
struct SendToChatsSheet: View {
    var title = "Send to"
    var send: ([ShareTarget], String) async throws -> Void
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var chats
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var note = ""
    @State private var sending = false
    @State private var query = ""

    private var targets: [ShareTarget] {
        let all = ShareTarget.all(model, chats)
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Palette.borderStrong).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            HStack {
                Text(title).font(.jakarta(17, .heavy)).foregroundStyle(Palette.text)
                Spacer()
                Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.main)
            }
            .padding(.horizontal, 18)
            SearchField(text: $query, placeholder: "Search chats and friends").padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if targets.isEmpty {
                        Text("Follow people or start a chat to send things to them.").font(.jakarta(13)).foregroundStyle(Palette.muted)
                    }
                    ForEach(targets) { t in
                        let on = picked.contains(t.id)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if on { picked.remove(t.id) } else { picked.insert(t.id) }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    Avatar(url: t.picture, name: t.name, size: 58)
                                        .overlay(Circle().strokeBorder(on ? Theme.main : .clear, lineWidth: 3))
                                        .scaleEffect(on ? 0.94 : 1)
                                    if on {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                                            .frame(width: 22, height: 22).background(Theme.gradient, in: Circle())
                                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                Text(t.name).font(.jakarta(11, .semibold)).foregroundStyle(Palette.text).lineLimit(1).frame(width: 66)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .sensoryFeedback(.selection, trigger: picked)
            HStack(spacing: 10) {
                TextField("Write a message…", text: $note).font(.jakarta(15))
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Palette.surface2, in: Capsule())
                Button { Task { await go() } } label: {
                    if sending { ProgressView().tint(.white) } else { Text(picked.count > 1 ? "Send (\(picked.count))" : "Send") }
                }
                .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
                .disabled(sending || picked.isEmpty)
                .opacity(picked.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 18)
            Spacer(minLength: 0)
        }
        .background(Palette.bg)
    }

    private func go() async {
        let chosen = ShareTarget.all(model, chats).filter { picked.contains($0.id) }
        guard !chosen.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await send(chosen, note)
            model.showToast(chosen.count == 1 ? "Sent to \(chosen[0].name)" : "Sent to \(chosen.count) chats", icon: "paperplane.fill")
            dismiss()
        } catch {
            model.showToast("Couldn't send — \(error.localizedDescription)", icon: "exclamationmark.triangle", error: true)
        }
    }
}

struct ReelShareSheet: View {
    let reel: Reel
    var mine: Bool
    var onNotInterested: () -> Void
    var onReport: () -> Void
    var onDelete: () -> Void
    var onUseSound: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(ChatStore.self) private var chats
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sugerly.reels.speed") private var speed = 1.0
    @AppStorage("sugerly.reels.autoscroll") private var autoScroll = false
    @AppStorage("sugerly.reels.clear") private var clearMode = false
    @AppStorage("sugerly.reels.muted") private var muted = false
    @State private var picked: Set<String> = []
    @State private var note = ""
    @State private var sending = false
    @State private var saving = false

    private var targets: [ShareTarget] { ShareTarget.all(model, chats) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Palette.borderStrong).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            Text("Send to").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if targets.isEmpty {
                        Text("Follow people or start a chat to send reels to them.").font(.jakarta(13)).foregroundStyle(Palette.muted)
                    }
                    ForEach(targets) { t in
                        let on = picked.contains(t.id)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if on { picked.remove(t.id) } else { picked.insert(t.id) }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    Avatar(url: t.picture, name: t.name, size: 58)
                                        .overlay(Circle().strokeBorder(on ? Theme.main : .clear, lineWidth: 3))
                                        .scaleEffect(on ? 0.94 : 1)
                                    if on {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                                            .frame(width: 22, height: 22).background(Theme.gradient, in: Circle())
                                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                Text(t.name).font(.jakarta(11, .semibold)).foregroundStyle(Palette.text).lineLimit(1).frame(width: 66)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .sensoryFeedback(.selection, trigger: picked)

            if !picked.isEmpty {
                HStack(spacing: 10) {
                    TextField("Write a message…", text: $note).font(.jakarta(15))
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Palette.surface2, in: Capsule())
                    Button { Task { await send() } } label: {
                        if sending { ProgressView().tint(.white) } else { Text("Send") }
                    }
                    .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
                    .disabled(sending)
                }
                .padding(.horizontal, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    action("link", "Copy link") {
                        UIPasteboard.general.url = ReelLinks.url(reel)
                        model.showToast("Link copied", icon: "link")
                        dismiss()
                    }
                    ShareLink(item: ReelLinks.url(reel), subject: Text("\(reel.authorName) on Sugerly"), message: Text(reel.caption)) {
                        tile("square.and.arrow.up", "Share")
                    }
                    .buttonStyle(BouncyStyle(scale: 0.9))
                    action(saving ? "hourglass" : "arrow.down.to.line", "Save") { Task { await save() } }
                    action("music.note", "Use sound") { dismiss(); onUseSound() }
                    action(muted ? "speaker.wave.2.fill" : "speaker.slash.fill", muted ? "Sound on" : "Mute") { muted.toggle() }
                }
                .padding(.horizontal, 18)
            }

            // Speed: plain buttons (a pop-up menu inside this sideways row
            // didn't open reliably and its label didn't update).
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.muted)
                    .frame(width: 26)
                    .accessibilityLabel("Playback speed")
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { v in
                    Button { withAnimation(.snappy) { speed = v } } label: {
                        Text(Self.speedText(v)).font(.jakarta(14, .heavy))
                            .foregroundStyle(speed == v ? Color.white : Palette.text)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(speed == v ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.surface), in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: speed == v ? 0 : 1))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                    .accessibilityAddTraits(speed == v ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: speed)
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    action(autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle", autoScroll ? "Auto-scroll on" : "Auto-scroll") { autoScroll.toggle() }
                    action("eye.slash", "Clear mode") { clearMode = true; dismiss() }
                    if mine {
                        action("trash", "Delete", danger: true) { dismiss(); onDelete() }
                    } else {
                        action("heart.slash", "Not interested") { dismiss(); onNotInterested() }
                        action("flag", "Report", danger: true) { dismiss(); onReport() }
                    }
                }
                .padding(.horizontal, 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .background(Palette.bg)
        .animation(.snappy, value: picked.isEmpty)
    }

    static func speedText(_ v: Double) -> String { v == 1 ? "1x" : v == 0.5 ? "0.5x" : v == 1.5 ? "1.5x" : "2x" }

    private func tile(_ icon: String, _ title: String, danger: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(danger ? Palette.danger : Palette.text)
                .frame(width: 54, height: 54)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
            Text(title).font(.jakarta(11, .semibold)).foregroundStyle(danger ? Palette.danger : Palette.text2).lineLimit(1).frame(width: 72)
        }
    }

    private func action(_ icon: String, _ title: String, danger: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) { tile(icon, title, danger: danger) }
            .buttonStyle(BouncyStyle(scale: 0.9))
    }

    private func send() async {
        guard let me = model.me else { return }
        guard await TextGuard.clear([note], kind: .message, model: model) else { return }
        sending = true
        defer { sending = false }
        let chosen = targets.filter { picked.contains($0.id) }
        do {
            try await ReelLinks.send(reel, to: chosen, note: note, me: me)
            model.showToast(chosen.count == 1 ? "Sent to \(chosen[0].name)" : "Sent to \(chosen.count) chats", icon: "paperplane.fill")
            dismiss()
        } catch {
            model.showToast("Couldn't send — \(error.localizedDescription)", icon: "exclamationmark.triangle", error: true)
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await ReelLinks.saveToPhotos(reel)
            model.showToast("Saved to Photos", icon: "arrow.down.circle.fill")
        } catch {
            model.showToast(error.localizedDescription, icon: "exclamationmark.triangle", error: true)
        }
    }
}

// MARK: - Seek bar

// Thin progress line you can drag to jump through the video (shows the time).
struct ReelSeekBar: View {
    let video: ReelVideo
    var onScrub: (Bool) -> Void = { _ in }
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = dragging ?? video.progress
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: max(0, geo.size.width * shown))
                if dragging != nil {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .shadow(radius: 3)
                        .offset(x: geo.size.width * shown - 7)
                }
            }
            .frame(height: dragging == nil ? 3 : 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .top) {
                if let dragging {
                    Text("\(Self.clock(dragging * video.duration)) / \(Self.clock(video.duration))")
                        .font(.jakarta(20, .heavy)).monospacedDigit().foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .offset(y: -44)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragging == nil { onScrub(true) }
                        dragging = min(1, max(0, v.location.x / max(1, geo.size.width)))
                    }
                    .onEnded { _ in
                        if let dragging { video.seek(to: dragging) }
                        withAnimation(.easeOut(duration: 0.2)) { self.dragging = nil }
                        onScrub(false)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: dragging == nil)
        }
        .frame(height: 22)
    }

    static func clock(_ s: Double) -> String {
        let v = Int(max(0, s.isFinite ? s : 0))
        return String(format: "%d:%02d", v / 60, v % 60)
    }
}

// MARK: - Heart bursts

struct HeartBurst: Identifiable {
    let id = UUID()
    let point: CGPoint
    let angle: Double
}

struct HeartBurstView: View {
    let burst: HeartBurst
    @State private var phase = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 96))
            .foregroundStyle(Theme.gradient)
            .shadow(color: Theme.pink.opacity(0.6), radius: 18)
            .rotationEffect(.degrees(burst.angle))
            .scaleEffect(phase == 0 ? 0.3 : phase == 1 ? 1.1 : 1.4)
            .opacity(phase == 2 ? 0 : 1)
            .offset(y: phase == 2 ? -70 : 0)
            .position(burst.point)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { phase = 1 }
                withAnimation(.easeIn(duration: 0.45).delay(0.45)) { phase = 2 }
            }
    }
}
