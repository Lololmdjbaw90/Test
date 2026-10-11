import SwiftUI
import PencilKit
import PhotosUI

// Make your own shirt or pants: paint on the template (every side of the
// body and the arms or legs is laid out flat), fill whole sides with one
// tap, drop your own art onto a side, and watch it on your avatar while you
// work. Then name it, price it in coins and put it in the catalog.
struct ClothingStudioView: View {
    let kind: CatalogItem.Kind
    var onPublished: ((CatalogItem) -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var board = StudioBoard()
    @State private var tool: Tool = .pen
    @State private var color = Color(hex: 0xF27BA3)
    @State private var width: CGFloat = 18
    @State private var guides = true
    @State private var preview: UIImage?
    @State private var bigPreview = false
    @State private var publishing = false
    @State private var confirmClose = false
    @State private var photoFace: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var importItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var importing = false
    @State private var base = "blank"
    @State private var note: String?

    enum Tool: String, CaseIterable, Identifiable {
        case pen, marker, crayon, eraser, fill, photo
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "highlighter"
            case .crayon: return "scribble.variable"
            case .eraser: return "eraser.fill"
            case .fill: return "drop.fill"
            case .photo: return "photo.fill"
            }
        }
        var label: String {
            switch self {
            case .pen: return "Pen"
            case .marker: return "Marker"
            case .crayon: return "Crayon"
            case .eraser: return "Eraser"
            case .fill: return "Fill"
            case .photo: return "Picture"
            }
        }
    }

    static let palette: [UInt32] = [0xF27BA3, 0xF7A1C4, 0xB19CFF, 0x7C5CF0, 0x7CBEFF, 0x5FD3B0, 0xFFD166, 0xFFAA80, 0xE0526B, 0xFFFFFF, 0x8A8A9A, 0x2A1F33]

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                starters
                    .photosPicker(isPresented: $importing, selection: $importItem, matching: .images)
                canvasArea
                toolRow
                if tool != .photo { colourRow }
                if [.pen, .marker, .crayon, .eraser].contains(tool) { sizeRow }
                if let note {
                    Text(note).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2).transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .background { Palette.bg.ignoresSafeArea() }
            .navigationTitle(kind == .shirt ? "New shirt" : "New pants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if board.isEmpty { dismiss() } else { confirmClose = true } } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItemGroup(placement: .principal) {
                    HStack(spacing: 18) {
                        Button { board.undo(); refreshSoon() } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(!board.canUndo)
                            .accessibilityLabel("Undo")
                        Button { withMotion { guides.toggle() }; board.guides = guides } label: {
                            Image(systemName: guides ? "square.dashed" : "square")
                        }
                        .accessibilityLabel(guides ? "Hide guides" : "Show guides")
                        Menu {
                            Button { importing = true } label: { Label("Use a finished template", systemImage: "square.and.arrow.down") }
                            Button { saveTemplate() } label: { Label("Save blank template to Photos", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { board.clear(); refreshSoon() } label: { Label("Start over", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    .font(.system(size: 17, weight: .semibold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { refreshNow(); publishing = true }
                        .font(.jakarta(16, .heavy))
                        .disabled(board.isEmpty)
                }
            }
        }
        .tint(Theme.main)
        .onAppear {
            board.kind = kind
            board.guides = guides
            board.onChange = { refreshSoon() }
            board.onTap = { point in tapped(point) }
            applyTool()
            refreshNow()
        }
        .onChange(of: tool) { _, _ in applyTool() }
        .onChange(of: color) { _, _ in applyTool() }
        .onChange(of: width) { _, _ in applyTool() }
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item, let face = photoFace else { return }
            pickerItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                board.setPhoto(image, on: face)
                refreshSoon()
            }
        }
        .onChange(of: importItem) { _, item in
            guard let item else { return }
            importItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                board.setBase(image)
                base = "import"
                refreshSoon()
                flash("Template added. Paint on top of it, or tap Next.")
            }
        }
        .confirmationDialog("Throw away this design?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Throw away", role: .destructive) { dismiss() }
        }
        .sheet(isPresented: $publishing) {
            PublishClothesSheet(kind: kind, image: board.composite(side: ClothTemplate.side)) { item in
                onPublished?(item)
                dismiss()
            }
            .presentationCornerRadius(30)
        }
    }

    // MARK: pieces

    private var starters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Blank", on: base == "blank") {
                    base = "blank"
                    board.setBase(nil)
                    refreshSoon()
                }
                ForEach(CatalogItem.builtIns.filter { $0.kind == kind }) { item in
                    chip(item.name, on: base == item.id) {
                        base = item.id
                        board.setBase(BuiltInClothes.image(item.id))
                        refreshSoon()
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.jakarta(13, .bold))
                .foregroundStyle(on ? .white : Palette.text2)
                .padding(.horizontal, 12).frame(height: 32)
                .background {
                    if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface) }
                }
                .overlay(Capsule().strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.92))
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            StudioCanvas(board: board, side: side)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    Button { withMotion(.spring(response: 0.4, dampingFraction: 0.8)) { bigPreview.toggle() } } label: {
                        AvatarStage(look: previewLook, framing: kind == .shirt ? .upper : .full,
                                    shirtImage: kind == .shirt ? preview : nil, pantsImage: kind == .pants ? preview : nil)
                            .frame(width: bigPreview ? side * 0.62 : 92, height: bigPreview ? side * 0.62 : 116)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("Preview on your avatar")
                }
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // Your avatar, with the other piece of clothing it already wears.
    private var previewLook: AvatarLook {
        var look = model.me?.avatar ?? .starter
        if kind == .shirt { look.shirt = "studio"; look.shirtURL = "" } else { look.pants = "studio"; look.pantsURL = "" }
        return look
    }

    private var toolRow: some View {
        HStack(spacing: 6) {
            ForEach(Tool.allCases) { t in
                let on = tool == t
                Button {
                    tool = t
                    if t == .fill { flash("Tap a side to fill it with your colour.") }
                    if t == .photo { flash("Tap a side to put a picture on it.") }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .bold))
                        Text(t.label).font(.jakarta(10.5, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? .white : Palette.text2)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background {
                        if on { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.gradient) }
                        else { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface) }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.92))
                .sensoryFeedback(.selection, trigger: on)
            }
        }
    }

    private var colourRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Self.palette, id: \.self) { hex in
                        let on = AvatarEditorView.hex(color) == hex
                        Button { color = Color(hex: hex) } label: {
                            Circle().fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                                .overlay(Circle().strokeBorder(on ? Theme.main : .clear, lineWidth: 2.5).padding(-3.5))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.86))
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.text2).frame(width: 6, height: 6)
            Slider(value: $width, in: 4...70).tint(Theme.main)
            Circle().fill(Palette.text2).frame(width: 16, height: 16)
        }
        .padding(.horizontal, 6)
    }

    // MARK: actions

    private func applyTool() {
        let ui = UIColor(color)
        switch tool {
        case .pen: board.setInk(PKInkingTool(.pen, color: ui, width: width))
        case .marker: board.setInk(PKInkingTool(.marker, color: ui, width: width * 1.6))
        case .crayon: board.setInk(PKInkingTool(.crayon, color: ui, width: width * 1.4))
        case .eraser: board.setInk(PKEraserTool(.bitmap, width: width * 1.5))
        case .fill, .photo: board.setTapping()
        }
    }

    private func tapped(_ point: CGPoint) {
        guard let face = ClothTemplate.allFaces.first(where: { $0.rect.contains(point) }) else { return }
        let key = "\(face.block).\(face.face.rawValue)"
        if tool == .fill {
            board.fill(key, with: AvatarEditorView.hex(color))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            refreshSoon()
        } else if tool == .photo {
            photoFace = key
            choosingPhoto = true
        }
    }

    @State private var refreshTask: Task<Void, Never>?

    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            refreshNow()
        }
    }

    private func refreshNow() {
        preview = board.composite(side: 512)
    }

    private func flash(_ text: String) {
        withMotion { note = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if note == text { withMotion { note = nil } }
        }
    }

    private func saveTemplate() {
        let side = ClothTemplate.side
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            ClothTemplate.guides(kind: kind).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        flash("Template saved to Photos. Draw on it in any app, then use it here.")
    }
}

// MARK: - the painting board (UIKit)

// A 1024 × 1024 board (one point = one template pixel) inside a zoomable
// view: one finger paints, two fingers move and pinch.
@MainActor
@Observable
final class StudioBoard: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
    let scroll = UIScrollView()
    private let content = UIView()
    private let back = UIImageView()
    let canvas = PKCanvasView()
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onTap: ((CGPoint) -> Void)?
    @ObservationIgnored var kind: CatalogItem.Kind = .shirt

    @ObservationIgnored var guides = true { didSet { if prepared { redrawBack() } } }
    private(set) var canUndo = false
    private(set) var isEmpty = true

    @ObservationIgnored private var baseImage: UIImage?
    @ObservationIgnored private var fills: [String: UInt32] = [:]
    @ObservationIgnored private var photos: [String: UIImage] = [:]
    // What Undo takes back: a stroke, or a fill / picture / template change.
    private enum Step { case stroke, layer([String: UInt32], [String: UIImage], UIImage?) }
    @ObservationIgnored private var history: [Step] = []
    @ObservationIgnored private var undoing = false
    @ObservationIgnored private var laidOut: CGFloat = 0
    @ObservationIgnored private var prepared = false

    private var side: CGFloat { ClothTemplate.side }

    // Set up once the board is really on screen (SwiftUI may make a few
    // throwaway copies of the screen before that).
    func prepare() {
        guard !prepared else { return }
        prepared = true
        content.frame = CGRect(x: 0, y: 0, width: side, height: side)
        back.frame = content.bounds
        back.contentMode = .scaleToFill
        canvas.frame = content.bounds
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.delegate = self
        content.addSubview(back)
        content.addSubview(canvas)
        content.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        scroll.addSubview(content)
        scroll.contentSize = content.bounds.size
        scroll.delegate = self
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        scroll.delaysContentTouches = false
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = .white
        redrawBack()
    }

    func layout(_ visible: CGFloat) {
        guard visible > 0, abs(visible - laidOut) > 0.5 else { return }
        laidOut = visible
        let fit = visible / side
        scroll.minimumZoomScale = fit
        scroll.maximumZoomScale = fit * 5
        scroll.zoomScale = fit
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { scrollView === scroll ? content : nil }

    // MARK: tools

    func setInk(_ tool: PKTool) {
        canvas.tool = tool
        canvas.isUserInteractionEnabled = true
    }

    func setTapping() {
        canvas.isUserInteractionEnabled = false
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onTap?(g.location(in: content))
    }

    func fill(_ key: String, with hex: UInt32) {
        remember()
        fills[key] = hex
        photos[key] = nil
        changed()
    }

    func setPhoto(_ image: UIImage, on key: String) {
        remember()
        photos[key] = image
        changed()
    }

    func setBase(_ image: UIImage?) {
        remember()
        baseImage = image
        changed()
    }

    func clear() {
        remember()
        fills = [:]
        photos = [:]
        baseImage = nil
        undoing = true
        canvas.drawing = PKDrawing()
        undoing = false
        changed()
    }

    func undo() {
        guard let last = history.popLast() else { return }
        switch last {
        case .stroke:
            undoing = true
            var strokes = canvas.drawing.strokes
            if !strokes.isEmpty { strokes.removeLast() }
            canvas.drawing = PKDrawing(strokes: strokes)
            undoing = false
        case .layer(let f, let p, let b):
            fills = f
            photos = p
            baseImage = b
        }
        changed(record: false)
    }

    private func remember() {
        history.append(.layer(fills, photos, baseImage))
        if history.count > 80 { history.removeFirst() }
    }

    private func changed(record: Bool = true) {
        if prepared { redrawBack() }
        canUndo = !history.isEmpty
        isEmpty = baseImage == nil && fills.isEmpty && photos.isEmpty && canvas.drawing.strokes.isEmpty
        onChange?()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !undoing else { return }
        // Only count new strokes (erasing changes the drawing too).
        history.append(.stroke)
        if history.count > 80 { history.removeFirst() }
        canUndo = true
        isEmpty = baseImage == nil && fills.isEmpty && photos.isEmpty && canvas.drawing.strokes.isEmpty
        onChange?()
    }

    // MARK: pictures

    private func redrawBack() {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let layers = composite(side: side, drawing: false)
        let guideImage = guides ? ClothTemplate.guides(kind: kind) : nil
        back.image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(hex: 0xFBF6F8).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Faint body-coloured sides so you can see where things go.
            UIColor(hex: 0xF6D2B8).withAlphaComponent(0.35).setFill()
            for (_, block) in ClothTemplate.blocks {
                for face in ClothTemplate.Face.allCases { ctx.fill(block.rect(face)) }
            }
            layers.draw(in: CGRect(origin: .zero, size: size))
            guideImage?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // Everything painted, as the clothes picture (transparent where bare).
    func composite(side out: CGFloat, drawing: Bool = true) -> UIImage {
        let size = CGSize(width: out, height: out)
        let k = out / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let strokes = drawing ? canvas.drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 1) : nil
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            baseImage?.draw(in: CGRect(origin: .zero, size: size))
            for face in ClothTemplate.allFaces {
                let key = "\(face.block).\(face.face.rawValue)"
                let r = face.rect.applying(CGAffineTransform(scaleX: k, y: k))
                if let hex = fills[key] {
                    UIColor(hex: hex).setFill()
                    ctx.fill(r)
                }
                if let photo = photos[key] {
                    ctx.cgContext.saveGState()
                    ctx.cgContext.clip(to: r)
                    let scale = max(r.width / max(photo.size.width, 1), r.height / max(photo.size.height, 1))
                    let w = photo.size.width * scale, h = photo.size.height * scale
                    photo.draw(in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
                    ctx.cgContext.restoreGState()
                }
            }
            strokes?.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

struct StudioCanvas: UIViewRepresentable {
    let board: StudioBoard
    let side: CGFloat

    func makeUIView(context: Context) -> UIScrollView {
        board.prepare()
        board.layout(side)
        return board.scroll
    }

    func updateUIView(_ view: UIScrollView, context: Context) {
        board.layout(side)
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

                    Text("Keep it kind: clothes with rude words or pictures are removed.")
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
