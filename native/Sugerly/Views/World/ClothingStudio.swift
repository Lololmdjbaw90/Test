import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

// Make clothes the classic way: download the template, draw on it in any
// drawing app, then upload the finished picture here. You see it on your
// avatar straight away, then name it, price it and put it in the catalog.
struct ClothingStudioView: View {
    @State private var kind: CatalogItem.Kind
    var onPublished: ((CatalogItem) -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var design: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var publishing = false
    @State private var note: String?
    @State private var templateFile: URL?

    init(kind: CatalogItem.Kind, onPublished: ((CatalogItem) -> Void)? = nil) {
        _kind = State(initialValue: kind)
        self.onPublished = onPublished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    kindPicker
                    templateCard
                    uploadCard
                    if let note {
                        Text(note).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background { Palette.bg.ignoresSafeArea() }
            .roundTitle(kind == .shirt ? "Upload a shirt" : "Upload pants")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { publishing = true }
                        .font(.jakarta(16, .heavy))
                        .disabled(design == nil)
                }
            }
        }
        .tint(Theme.main)
        .task(id: kind) { templateFile = writeTemplate() }
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    flash("Couldn't open that picture.")
                    return
                }
                use(image)
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.png, .jpeg, .image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                flash("Couldn't open that file.")
                return
            }
            use(image)
        }
        .sheet(isPresented: $publishing) {
            if let design {
                PublishClothesSheet(kind: kind, image: ClothTemplate.normalized(design)) { item in
                    onPublished?(item)
                    dismiss()
                }
                .presentationCornerRadius(30)
            }
        }
    }

    // MARK: pieces

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(CatalogItem.Kind.allCases) { k in
                let on = kind == k
                Button { withMotion(.spring(response: 0.3, dampingFraction: 0.8)) { kind = k } } label: {
                    Label(k == .shirt ? "Shirt" : "Pants", systemImage: k.icon)
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(on ? .white : Palette.text2)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background {
                            if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface) }
                        }
                        .overlay(Capsule().strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.95))
            }
        }
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "Get the template", "Draw on it in any drawing app, keeping the size (585 × 559). The parts are named on it.")
            Image(uiImage: ClothTemplate.blank(kind: kind))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(10)
                .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            HStack(spacing: 10) {
                Button { Task { await saveTemplate() } } label: {
                    Label("Save to Photos", systemImage: "photo.badge.arrow.down.fill")
                }
                .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
                if let templateFile {
                    ShareLink(item: templateFile) {
                        Label("Share / Files", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
                }
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(2, "Upload your design", "Pick your finished template. You'll see it on your avatar right away.")
            if let design {
                HStack(spacing: 12) {
                    Image(uiImage: design)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(6)
                        .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                        .frame(maxWidth: .infinity)
                    AvatarStage(look: previewLook, spin: false, framing: .full,
                                shirtImage: kind == .shirt ? design : nil, pantsImage: kind == .pants ? design : nil)
                        .frame(width: 140, height: 190)
                        .background(LinearGradient(colors: [Theme.light.opacity(0.3), Palette.surface], startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if !ClothTemplate.fits(design) {
                    Label("This picture isn't template-shaped (585 × 559), so it may look stretched.", systemImage: "exclamationmark.triangle.fill")
                        .font(.jakarta(12.5, .semibold)).foregroundStyle(Palette.warning)
                }
            }
            HStack(spacing: 10) {
                Button { choosingPhoto = true } label: {
                    Label(design == nil ? "From Photos" : "Change", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(GradientButtonStyle(height: 46))
                Button { choosingFile = true } label: {
                    Label("From Files", systemImage: "folder.fill")
                }
                .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.jakarta(15, .heavy)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.jakarta(17, .heavy)).foregroundStyle(Palette.text)
                Text(detail).font(.jakarta(13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var previewLook: AvatarLook {
        var look = model.me?.avatar ?? .starter
        if kind == .shirt { look.shirt = "upload"; look.shirtURL = "" } else { look.pants = "upload"; look.pantsURL = "" }
        return look
    }

    // MARK: actions

    private func use(_ image: UIImage) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { design = image }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func flash(_ text: String) {
        withMotion { note = text }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if note == text { withMotion { note = nil } }
        }
    }

    private func writeTemplate() -> URL? {
        guard let png = ClothTemplate.blank(kind: kind).pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sugerly \(kind == .shirt ? "shirt" : "pants") template.png")
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // As a PNG, so the see-through parts stay see-through.
    private func saveTemplate() async {
        guard let png = ClothTemplate.blank(kind: kind).pngData() else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            flash("Allow Sugerly to add photos in iPhone Settings, or use Share / Files.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash("Template saved to Photos.")
        } catch {
            flash("Couldn't save it. Try Share / Files instead.")
        }
    }
}

// MARK: - naming, pricing and publishing

struct PublishClothesSheet: View {
    let kind: CatalogItem.Kind
    let image: UIImage
    var onDone: (CatalogItem) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = 25
    @State private var wearNow = true
    @State private var busy = false
    @State private var error: String?

    private var share: Int { Int((Double(price) * CatalogShop.creatorShare).rounded(.down)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        LinearGradient(colors: [Theme.light.opacity(0.4), Palette.surface], startPoint: .top, endPoint: .bottom)
                        AvatarStage(look: look, spin: true, framing: .full,
                                    shirtImage: kind == .shirt ? image : nil, pantsImage: kind == .pants ? image : nil)
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                        SugarField(placeholder: kind == .shirt ? "e.g. Strawberry tee" : "e.g. Galaxy jeans", text: $name)
                            .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Price").font(.jakarta(13, .bold)).foregroundStyle(Palette.text2)
                            Spacer()
                            HStack(spacing: 5) {
                                if price == 0 {
                                    Text("Free").font(.jakarta(17, .heavy)).foregroundStyle(Palette.success)
                                } else {
                                    CoinIcon(size: 20)
                                    Text("\(price)").font(.jakarta(17, .heavy)).foregroundStyle(Palette.text)
                                        .contentTransition(.numericText(value: Double(price)))
                                }
                            }
                        }
                        Slider(value: Binding(get: { Double(price) }, set: { price = Int(($0 / 5).rounded()) * 5 }), in: 0...500)
                            .tint(Theme.main)
                        Text(price == 0 ? "Anyone can get it for free." : "You get \(share) coins (70%) each time someone buys it.")
                            .font(.jakarta(12.5)).foregroundStyle(Palette.muted)
                    }
                    .padding(16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Toggle(isOn: $wearNow) {
                        Text("Wear it now").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                    }
                    .tint(Theme.main)
                    .padding(.horizontal, 16).frame(height: 54)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let error {
                        Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
                    }

                    Button { Task { await publish() } } label: {
                        HStack(spacing: 8) {
                            if busy { SugarLoader(size: 9) }
                            Text(busy ? "Putting it in the catalog…" : "Put it in the catalog")
                        }
                    }
                    .buttonStyle(GradientButtonStyle(height: 54))
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)

                    Text("Only upload designs you made. Clothes with rude words or pictures, or copied from someone else, are removed.")
                        .font(.jakarta(12)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background { Palette.bg.ignoresSafeArea() }
            .roundTitle(kind == .shirt ? "Your shirt" : "Your pants")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            }
        }
        .tint(Theme.main)
    }

    private var look: AvatarLook {
        var look = model.me?.avatar ?? .starter
        if kind == .shirt { look.shirt = "new"; look.shirtURL = "" } else { look.pants = "new"; look.pantsURL = "" }
        return look
    }

    private func publish() async {
        guard let me = model.me else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        busy = true
        defer { busy = false }
        guard await TextGuard.clear([title], kind: .caption, model: model, cooldown: false) else {
            let reason = model.toast.flatMap { $0.error ? $0.text : nil } ?? "That name can't be used. Try another one."
            model.toast = nil
            withMotion { error = reason }
            return
        }
        guard let png = image.pngData() else { error = "Couldn't save the picture."; return }
        do {
            let url = try await StorageClient.upload(png, contentType: "image/png", fileExtension: "png")
            ClothStore.remember(image, url: url)
            let doc = try await FS.create("CatalogItem", [
                "name": title, "kind": kind.rawValue, "price": price, "image_url": url,
                "creator_email": me.email, "creator_name": me.displayName, "sales": 0, "on_sale": true,
            ])
            guard let item = CatalogItem(doc) else { throw APIError(message: "Something went wrong.") }
            var fields: Doc = ["avatar_items": me.avatarItems + [item.id]]
            if wearNow { fields["avatar_look"] = AvatarSnapshot.look(trying: item, on: me.avatar).json }
            try await model.updateMe(fields)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            model.showToast("\(title) is in the catalog!", icon: "sparkles")
            onDone(item)
            dismiss()
        } catch {
            withMotion { self.error = "Couldn't publish it: \(error.localizedDescription)" }
        }
    }
}
