import ImageIO
import SwiftUI
import UIKit


// Round profile picture with the person's initial as a fallback. Pictures
// come from the shared image cache, so avatars never flash while scrolling.
struct Avatar: View {
    var url: String
    var name: String
    var size: CGFloat = 40
    var online = false
    // No longer drawn: profile pictures have no ring around them. Kept so
    // existing callers still compile.
    var ring = false
    var nitro = false
    // Idle / do-not-disturb badge instead of the plain green dot.
    var presence: Presence? = nil
    @State private var image: UIImage?
    // Which picture `image` belongs to, so a changed (or removed) picture never
    // keeps showing the old one.
    @State private var imageURL = ""

    var body: some View {
        let own = imageURL == url ? image : nil
        ZStack(alignment: .bottomTrailing) {
            Group {
                if live {
                    FullGIF(url: url)
                } else if let shown = own ?? (url.isEmpty ? nil : (AnimatedImages.looksAnimated(url) ? AnimatedImages.cached(url, maxPixel: pixel, maxFrames: 1) : MemoryImages.get(ImagePipeline.cacheKey(url, maxPixel: pixel)))) {
                    LoadedImage(image: shown)
                } else {
                    initial
                }
            }
            .frame(width: size, height: size)
            .modifier(SensitiveCover(url: url, compact: true))
            .clipShape(Circle())

            PresenceBadge(presence: presence, online: online, size: size)
        }
        .accessibilityHidden(true)
        .task(id: "\(url)#\(Int(pixel))#\(live)") {
            if imageURL != url { image = nil; imageURL = url }
            guard !url.isEmpty, !live else { return }
            let target = url
            if AnimatedImages.looksAnimated(target) {
                if let loaded = await AnimatedImages.load(target, maxPixel: pixel, maxFrames: 1), target == url { image = loaded }
                return
            }
            guard image == nil || MemoryImages.get(ImagePipeline.cacheKey(target, maxPixel: pixel)) == nil else { return }
            if let loaded = await ImagePipeline.shared.load(target, maxPixel: pixel), target == url { image = loaded }
        }
    }

    private var pixel: CGFloat { min(400, max(96, size * 3)) }
    // Big GIF pictures (profile headers) play at full quality.
    private var live: Bool { size >= 72 && AnimatedImages.looksAnimated(url) }

    private var initial: some View {
        ZStack {
            LinearGradient(colors: [Theme.light, Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(name.first ?? "?").uppercased())
                .font(.display(size * 0.45))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        }
    }
}

// The little status dot on a picture (online, idle, do not disturb). Also
// used on its own on top of a picture that has a ring or frame around it,
// so the dot always sits in front of the ring, never behind it.
struct PresenceBadge: View {
    var presence: Presence? = nil
    var online = false
    // The size of the picture it belongs to.
    let size: CGFloat

    var body: some View {
        if let presence, presence != .offline {
            PresenceDot(presence: presence, size: max(11, size * 0.3))
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: max(1.5, size * 0.04)))
        } else if online {
            Circle().fill(Palette.success)
                .frame(width: max(9, size * 0.27), height: max(9, size * 0.27))
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: max(2, size * 0.05)))
                .shadow(color: Palette.success.opacity(0.5), radius: 3)
        }
    }
}

// The pop-up shown at the top of the screen for a couple of seconds.
struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(toast.error ? AnyShapeStyle(Palette.danger) : AnyShapeStyle(Theme.gradient), in: Circle())
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.text).font(.jakarta(14, .bold)).foregroundStyle(Palette.text).lineLimit(2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .padding(.vertical, 8)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 12, y: 8)
        .padding(.horizontal, 20)
        .sensoryFeedback(toast.error ? .error : .success, trigger: toast.id)
    }
}

// Picture from the web, with a soft placeholder while it loads.
// Pictures load once, get shrunk to screen size off the main thread and stay
// in memory, so feeds scroll without flashing or reloading.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private var running: [String: Task<UIImage?, Never>] = [:]

    nonisolated static func cacheKey(_ url: String, maxPixel: CGFloat = 1400) -> String {
        maxPixel == 1400 ? url : "\(url)#thumb-\(Int(maxPixel))"
    }

    func load(_ url: String, maxPixel: CGFloat = 1400) async -> UIImage? {
        let key = Self.cacheKey(url, maxPixel: maxPixel)
        if let hit = MemoryImages.get(key) { return hit }
        if let task = running[key] { return await task.value }
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            guard let link = URL(string: url) else { return nil }
            var request = URLRequest(url: link)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
            await DecodeGate.shared.enter()
            let image = ImagePipeline.downsample(data, maxPixel: maxPixel)
            await DecodeGate.shared.leave()
            return image
        }
        running[key] = task
        let image = await task.value
        running[key] = nil
        if let image { MemoryImages.set(image, for: key) }
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return UIImage(data: data) }
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

enum MemoryImages {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 100 * 1024 * 1024
        // Low on memory: let go of saved pictures so iOS doesn't close the app.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            c.removeAllObjects()
        }
        return c
    }()
    static func get(_ url: String) -> UIImage? { cache.object(forKey: url as NSString) }
    static func set(_ image: UIImage, for url: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSString, cost: cost)
    }
}

// A remote picture. In .fill mode it fills the space it's given and is
// clipped to it (never pushes the layout wider); in .fit mode it shows the
// whole picture.
struct RemoteImage: View {
    var url: String
    var contentMode: ContentMode = .fill
    // Banners: GIFs play at full quality instead of a shrunk copy.
    var live = false
    @State private var image: UIImage?
    @State private var failed = false

    private var animated: Bool { AnimatedImages.looksAnimated(url) }

    var body: some View {
        if live && animated {
            FullGIF(url: url, fill: contentMode == .fill)
        } else {
            still
        }
    }

    @ViewBuilder private var still: some View {
        let shown = image ?? (animated ? AnimatedImages.cached(url, maxPixel: 720) : MemoryImages.get(url))
        Group {
            if let shown {
                if contentMode == .fill {
                    Color.clear
                        .overlay { LoadedImage(image: shown, fill: true) }
                        .clipped()
                } else {
                    LoadedImage(image: shown, fill: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                placeholder.overlay {
                    if failed { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
        }
        .modifier(SensitiveCover(url: url))
        .task(id: url) {
            guard !url.isEmpty else { return }
            if animated {
                if let loaded = await AnimatedImages.load(url, maxPixel: 720) { withAnimation(.easeOut(duration: 0.2)) { image = loaded } } else { failed = true }
                return
            }
            if MemoryImages.get(url) != nil { image = MemoryImages.get(url); return }
            let loaded = await ImagePipeline.shared.load(url)
            if let loaded {
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            } else {
                failed = true
            }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Palette.surface2)
            .overlay { LinearGradient(colors: [Theme.main.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
}

// A drawing shown whole, at its own shape (never cropped). Very tall or very
// wide pictures are letterboxed on a soft blurred copy of themselves.
struct ArtImage: View {
    var url: String
    var tallest: CGFloat = 0.62 // width / height
    var widest: CGFloat = 1.8
    @State private var image: UIImage?

    var body: some View {
        let shown = image ?? (AnimatedImages.looksAnimated(url) ? AnimatedImages.cached(url, maxPixel: 720) : MemoryImages.get(url))
        let natural: CGFloat = shown.map { $0.size.width / Swift.max(1, $0.size.height) } ?? 0.8
        let ratio: CGFloat = Swift.min(widest, Swift.max(tallest, natural))
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let shown {
                    ZStack {
                        if abs(ratio - natural) > 0.01 && shown.images == nil {
                            Image(uiImage: shown).resizable().scaledToFill().blur(radius: 22).opacity(0.55)
                        }
                        LoadedImage(image: shown, fill: false)
                    }
                    .transition(.opacity)
                } else {
                    Rectangle().fill(Palette.surface2).shimmer()
                }
            }
            .clipped()
            .modifier(SensitiveCover(url: url))
            .task(id: url) {
                guard !url.isEmpty, image == nil else { return }
                if AnimatedImages.looksAnimated(url) {
                    if let loaded = await AnimatedImages.load(url, maxPixel: 720) { withAnimation(.easeOut(duration: 0.2)) { image = loaded } }
                    return
                }
                if let loaded = await ImagePipeline.shared.load(url) {
                    withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                }
            }
    }
}

typealias PrimaryButtonStyle = GradientButtonStyle

// Report a post, comment, message or person (App Store requirement for
// apps with user content). Lands in Admin → Reports on the website.
struct ReportSheet: View {
    struct Target: Identifiable {
        var id: String
        var type: String
        var ownerEmail: String
        var preview: String
        var link: String
        // Where it's stored (so moderators remove the right thing) and any
        // GIF, sticker, picture, voice note or video it holds.
        var collection = ""
        var media = ""

        private var mediaKind: String {
            let lower = media.lowercased()
            if media.isEmpty { return "" }
            if lower.contains(".m4a") || lower.contains("audio") { return "Voice note" }
            if lower.contains(".mp4") || lower.contains(".mov") || lower.contains("video") { return "Video" }
            return AnimatedImages.looksAnimated(media) ? "GIF / sticker" : "Picture"
        }

        var showsPicture: Bool { mediaKind == "GIF / sticker" || mediaKind == "Picture" }

        var shownPreview: String {
            let text = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            if mediaKind.isEmpty { return text }
            return text.isEmpty ? mediaKind : "\(text) (+ \(mediaKind.lowercased()))"
        }
    }

    struct Reason: Identifiable {
        let title: String
        let detail: String
        let icon: String
        var urgent = false
        var id: String { title }
    }

    static let reasons: [Reason] = [
        Reason(title: "Spam or scam", detail: "Fake offers, links, begging for coins", icon: "envelope.badge.fill"),
        Reason(title: "Harassment or bullying", detail: "Mean, targeted or threatening someone", icon: "person.fill.xmark"),
        Reason(title: "Hate speech", detail: "Attacks on who someone is", icon: "exclamationmark.bubble.fill"),
        Reason(title: "Nudity or sexual content", detail: "Anything not OK for everyone", icon: "eye.slash.fill"),
        Reason(title: "Violence or threats", detail: "Gore, threats or dangerous acts", icon: "bolt.trianglebadge.exclamationmark.fill"),
        Reason(title: "Someone may be in danger", detail: "Self-harm or someone at risk", icon: "heart.text.square.fill", urgent: true),
        Reason(title: "Stolen art / copyright", detail: "Posting someone else's work as theirs", icon: "paintbrush.pointed.fill"),
        Reason(title: "Pretending to be someone else", detail: "Fake account or impersonation", icon: "theatermasks.fill"),
        Reason(title: "Something else", detail: "Tell us below", icon: "ellipsis.bubble.fill"),
    ]

    let target: Target
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason?
    @State private var details = ""
    @State private var block = false
    @State private var sending = false
    @State private var sent = false
    @State private var already = false
    @State private var error: String?

    private var me: String { model.me?.email ?? "" }
    private var canBlock: Bool { !target.ownerEmail.isEmpty && target.ownerEmail.lowercased() != me.lowercased() && !(model.me?.blocked.contains(target.ownerEmail.lowercased()) ?? false) }
    private var ownerName: String { model.person(target.ownerEmail)?.displayName ?? "them" }

    var body: some View {
        NavigationStack {
            ZStack {
                if sent {
                    done.transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    form.transition(.opacity)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: sent)
            .sugarBackground()
            .navigationTitle(sent ? "" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !sent { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
        .task { await checkAlready() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !target.shownPreview.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        if target.showsPicture {
                            AnimatedThumb(url: target.media, fill: true, maxPixel: 200, maxFrames: 30, budget: AnimatedImages.thumbBudget)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reporting a \(target.type)").font(.jakarta(11, .heavy)).tracking(0.6).foregroundStyle(Palette.muted)
                            Text(target.shownPreview).font(.jakarta(14)).foregroundStyle(Palette.text).lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                }
                if already {
                    Label("You already reported this. You can add more, or follow it in Help & support → My reports.", systemImage: "info.circle.fill")
                        .font(.jakarta(13, .semibold)).foregroundStyle(Theme.main)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text("What's wrong?").font(.display(24)).foregroundStyle(Palette.text)
                VStack(spacing: 8) {
                    ForEach(Self.reasons) { r in reasonRow(r) }
                }
                if reason?.urgent == true {
                    Label("If someone is in danger right now, call your local emergency number (112 in Europe, 911 in the US). In the US you can call or text 988 any time.", systemImage: "phone.fill")
                        .font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if reason != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anything else we should know?").font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                        TextField("Optional", text: $details, axis: .vertical)
                            .font(.jakarta(15)).lineLimit(3...6)
                            .padding(12)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                        if canBlock {
                            Toggle(isOn: $block) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Also block \(ownerName)").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                                    Text("They won't be able to message you or see your posts.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                                }
                            }
                            .tint(Theme.main)
                            .padding(12)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
                Button { Task { await send() } } label: {
                    Label(sending ? "Sending…" : "Send report", systemImage: "paperplane.fill")
                }
                .buttonStyle(GradientButtonStyle(height: 52))
                .disabled(reason == nil || sending)
                .opacity(reason == nil ? 0.5 : 1)
                Label("Reports are private. The person isn't told who reported them. Our team checks every report, usually within 24 hours.", systemImage: "lock.fill")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            .padding(18)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: reason?.id)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func reasonRow(_ r: Reason) -> some View {
        let active = reason?.id == r.id
        return Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { reason = r } } label: {
            HStack(spacing: 12) {
                Image(systemName: r.icon).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(active ? .white : (r.urgent ? Palette.danger : Theme.main))
                    .frame(width: 36, height: 36)
                    .background(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(r.urgent ? Palette.danger.opacity(0.1) : Theme.soft), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title).font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                    Text(r.detail).font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(active ? Theme.main : Palette.border)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(10)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(active ? Theme.main : Palette.border, lineWidth: active ? 2 : 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
        .sensoryFeedback(.selection, trigger: active)
    }

    // Sent: a thank-you and what happens next.
    private var done: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Theme.soft).frame(width: 120, height: 120)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54, weight: .bold)).foregroundStyle(Theme.gradient)
                    .symbolEffect(.bounce, value: sent)
            }
            Text("Thanks for telling us").font(.display(28)).foregroundStyle(Palette.text)
            Text("Our team will look at it soon. You can see what happened any time in Help & support → My reports.")
                .font(.jakarta(15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
            if block {
                Label("\(ownerName.capitalized) is blocked", systemImage: "hand.raised.fill")
                    .font(.jakarta(13, .bold)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(GradientButtonStyle(height: 52))
        }
        .padding(24)
        .sensoryFeedback(.success, trigger: sent)
    }

    private func checkAlready() async {
        guard !me.isEmpty else { return }
        let docs = (try? await FS.query("Report", [.equals("reporter_email", me), .equals("target_id", target.id)], limit: 1)) ?? []
        if !docs.isEmpty { withMotion(Motion.standard) { already = true } }
    }

    private func send() async {
        guard let me = model.me, let reason else { return }
        sending = true
        defer { sending = false }
        let report: Doc = [
            "target_type": target.type, "target_id": target.id, "target_owner_email": target.ownerEmail,
            "target_preview": String(target.shownPreview.prefix(280)), "link": target.link, "reason": reason.title,
            "target_collection": target.collection, "target_media": target.media, "urgent": reason.urgent,
            "details": String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)), "reporter_email": me.email, "reporter_name": me.displayName,
            "status": "open", "created_by": me.email, "created_date": FS.nowISO(), "updated_date": FS.nowISO(),
        ]
        do {
            try await FS.create("Report", report)
            if block && canBlock { await Privacy.setBlocked(target.ownerEmail, true, model: model) }
            withMotion { sent = true }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Links aren't allowed in bios and captions (spam and scams).
enum Moderation {
    static func hasLink(_ text: String) -> Bool {
        let pattern = #"(https?://|www\.)\S+|\b[a-z0-9-]+\.(com|net|org|io|co|gg|ly|me|app|xyz|link|shop|site)\b"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// Pictures the upload check marked sensitive (saved as "sensitive-…", see
// MediaGuard) are blurred with a note until tapped, unless you chose to see
// them in Settings → Safety. Small ones (profile pictures) just stay blurred.
struct SensitiveCover: ViewModifier {
    let url: String
    var compact = false
    @AppStorage(SensitiveCover.showKey) private var showAll = false
    @State private var revealed = false

    static let showKey = "sugerly.safety.showSensitive"

    static func isSensitive(_ url: String) -> Bool {
        url.contains("sensitive") && (url.removingPercentEncoding ?? url).contains("/sensitive-")
    }

    func body(content: Content) -> some View {
        if Self.isSensitive(url) && !showAll && !revealed {
            if compact {
                content.blur(radius: 6, opaque: true)
            } else {
                content
                    .blur(radius: 28, opaque: true)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "eye.slash.fill").font(.system(size: 20, weight: .bold))
                            Text("Sensitive content").font(.jakarta(13, .bold))
                            Text("Tap to show").font(.jakarta(11, .semibold)).opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .padding(8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.fade) { revealed = true } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sensitive content")
                    .accessibilityHint("Shows the picture")
                    .accessibilityAddTraits(.isButton)
            }
        } else {
            content
        }
    }
}
