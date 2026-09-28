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
                if let shown = own ?? (url.isEmpty ? nil : (AnimatedImages.looksAnimated(url) ? AnimatedImages.cached(url, maxPixel: pixel) : MemoryImages.get(url))) {
                    LoadedImage(image: shown)
                } else {
                    initial
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(ring || nitro ? max(2, size * 0.05) : 0)
            .background {
                if nitro { NitroRing() } else if ring { Circle().fill(Theme.gradient) }
            }
            .overlay {
                if ring || nitro { Circle().strokeBorder(Palette.surface, lineWidth: max(1.5, size * 0.035)).padding(max(2, size * 0.05) - max(1.5, size * 0.035)) }
            }

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
        .accessibilityHidden(true)
        .task(id: url) {
            if imageURL != url { image = nil; imageURL = url }
            guard !url.isEmpty else { return }
            let target = url
            if AnimatedImages.looksAnimated(target) {
                if let loaded = await AnimatedImages.load(target, maxPixel: pixel), target == url { image = loaded }
                return
            }
            guard image == nil || MemoryImages.get(target) == nil else { return }
            if let loaded = await ImagePipeline.shared.load(target), target == url { image = loaded }
        }
    }

    private var pixel: CGFloat { min(400, max(96, size * 3)) }

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
        .shadow(color: Theme.main.opacity(0.18), radius: 18, y: 8)
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

    func load(_ url: String) async -> UIImage? {
        if let hit = MemoryImages.get(url) { return hit }
        if let task = running[url] { return await task.value }
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            guard let link = URL(string: url) else { return nil }
            var request = URLRequest(url: link)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
            return ImagePipeline.downsample(data, maxPixel: 1400)
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        if let image { MemoryImages.set(image, for: url) }
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
        c.totalCostLimit = 160 * 1024 * 1024
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
    @State private var image: UIImage?
    @State private var failed = false

    private var animated: Bool { AnimatedImages.looksAnimated(url) }

    var body: some View {
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
    }

    let target: Target
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason = Social.reportReasons[0]
    @State private var details = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(Social.reportReasons, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("More details (optional)") {
                    TextField("Tell us what happened", text: $details, axis: .vertical).lineLimit(3...6)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Text("Our moderators review reports within 24 hours.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") { Task { await send() } }.disabled(sending)
                }
            }
        }
    }

    private func send() async {
        guard let me = model.me else { return }
        sending = true
        defer { sending = false }
        let report: Doc = [
            "target_type": target.type, "target_id": target.id, "target_owner_email": target.ownerEmail,
            "target_preview": String(target.preview.prefix(280)), "link": target.link, "reason": reason,
            "details": String(details.prefix(1000)), "reporter_email": me.email, "reporter_name": me.displayName,
            "status": "open", "created_by": me.email, "created_date": FS.nowISO(), "updated_date": FS.nowISO(),
        ]
        do {
            try await FS.create("Report", report)
            dismiss()
            model.showToast("Thanks — our team will take a look", icon: "flag.fill")
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

// Nitro's animated rainbow-candy ring around a profile picture.
struct NitroRing: View {
    @State private var spin = false
    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [Color(hex: 0xFF7AA2), Color(hex: 0xB19CFF), Color(hex: 0x7CBEFF), Color(hex: 0xFFD166), Color(hex: 0xFF7AA2)], center: .center))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .shadow(color: Color(hex: 0xB19CFF).opacity(0.6), radius: 6)
            .onAppear { withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true } }
    }
}
