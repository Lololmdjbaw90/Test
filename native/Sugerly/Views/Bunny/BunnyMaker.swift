import SwiftUI
import UIKit
import Photos

// The bunny maker: your bunny on a little stage at the top, then a row of
// tabs (fur, face, outfit, accessories, bow, collar, background) and the choices for
// the one you picked. Changes show straight away; Done keeps them. You can
// shuffle, save her to Photos, or make her your profile picture.
struct BunnyMakerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = BunnyStore.shared
    @State private var look = BunnyLook()
    @State private var tab: Tab = .fur
    @State private var loaded = false
    @State private var busy = false
    @State private var cheer = 0
    @State private var shuffles = 0
    // The team adding a new item (clothes or an accessory).
    @State private var adding: BunnySlot?
    @State private var catalog = BunnyCatalog.shared

    enum Tab: String, CaseIterable, Identifiable {
        case fur, face, outfit, accessory, bow, collar, scene
        var id: String { rawValue }
        var label: String {
            switch self {
            case .scene: return "Background"
            case .accessory: return "Accessories"
            default: return rawValue.capitalized
            }
        }
        var icon: String {
            switch self {
            case .fur: return "hare.fill"
            case .bow: return "gift.fill"
            case .collar: return "seal.fill"
            case .outfit: return "tshirt.fill"
            case .face: return "face.smiling.inverse"
            case .accessory: return "headphones"
            case .scene: return "photo.fill"
            }
        }
        var candy: Candy {
            switch self {
            case .fur: return .berry
            case .bow: return .peach
            case .collar: return .grape
            case .outfit: return .sky
            case .face: return .lemon
            case .accessory: return .grape
            case .scene: return .mint
            }
        }
        var part: BunnyPart? {
            switch self {
            case .fur: return .fur
            case .bow: return .bow
            case .collar: return .collar
            default: return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                stage
                tabs
                choices
                    .id(tab)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                actions
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sugarBackground()
        .navigationTitle("Bunny maker")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            store.use(model.me?.email ?? "")
            look = store.look
            loaded = true
        }
        .onChange(of: look) { _, next in if loaded { store.save(next) } }
        .sensoryFeedback(.selection, trigger: look)
        .sensoryFeedback(.success, trigger: cheer)
        .task { await catalog.load() }
        .sheet(item: $adding) { slot in
            BunnyItemUploader(slot: slot, look: look)
                .presentationCornerRadius(30)
        }
    }

    private var isAdmin: Bool { model.me?.isAdmin == true }

    // MARK: stage

    private var stage: some View {
        BunnyPortrait(look: look)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Palette.rim(0.7), lineWidth: 1.5))
            .shadow(color: Theme.glow(0.22), radius: 18, y: 8)
            .overlay(alignment: .topTrailing) {
                Button {
                    shuffles += 1
                    withAnimation(Motion.playful) { look = BunnyLook.random() }
                } label: {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.main)
                        .symbolEffect(.bounce, value: shuffles)
                        .rotationEffect(.degrees(Double(shuffles) * 90))
                        .animation(Motion.playful, value: shuffles)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.9), in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                }
                .buttonStyle(BouncyStyle(scale: 0.88))
                .padding(14)
                .accessibilityLabel("Surprise me")
            }
            .overlay(alignment: .bottomLeading) {
                Text("Tap her!")
                    .font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.85), in: Capsule())
                    .padding(14)
                    .accessibilityHidden(true)
            }
    }

    // MARK: tabs

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { item in
                    let on = tab == item
                    Button {
                        withAnimation(Motion.playful) { tab = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 13, weight: .bold))
                                .symbolEffect(.bounce, value: on)
                            Text(item.label).font(.jakarta(14, .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(on ? .white : Palette.text2)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background {
                            if on {
                                Capsule().fill(item.candy.gradient)
                                    .shadow(color: item.candy.color.softGlow(0.35), radius: 6, y: 3)
                            } else {
                                Capsule().fill(Palette.surface)
                                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.92))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    // MARK: choices

    @ViewBuilder
    private var choices: some View {
        if tab == .bow && !look.head.isEmpty {
            VStack(spacing: 12) {
                EmptyCard(icon: "headphones", title: "Bow hidden", text: "She's wearing an accessory, which takes the bow's place.", compact: true)
                Button { withAnimation(Motion.playful) { look.head = "" } } label: {
                    Label("Take the accessory off", systemImage: "xmark.circle")
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
            }
        } else if tab == .bow {
            VStack(spacing: 12) {
                Toggle(isOn: Binding(get: { look.bowOn }, set: { on in withAnimation(Motion.playful) { look.bowOn = on } })) {
                    Text("Wear a bow").font(.jakarta(15, .semibold)).foregroundStyle(Palette.text)
                }
                .tint(Theme.main)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .sugarCard(radius: 18)
                if look.bowOn { swatches(.bow).transition(.opacity.combined(with: .scale(scale: 0.96))) }
            }
        } else if tab == .collar && (look.top != .sailor || !look.wear.isEmpty) {
            EmptyCard(icon: "tshirt.fill", title: "No collar", text: "The collar comes with the sailor top. Pick it under Outfit.", compact: true)
        } else if let part = tab.part {
            swatches(part)
        } else if tab == .face {
            faces
        } else if tab == .outfit {
            outfits
        } else if tab == .accessory {
            accessories
        } else {
            scenes
        }
    }

    // Each face shown on your bunny's own fur.
    private var faces: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(Array(BunnyFace.allCases.enumerated()), id: \.element.id) { i, face in
                let on = look.face == face
                Button {
                    withAnimation(Motion.playful) { look.face = face }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            BunnyLayer("BunnyFur", look.tint(.fur))
                            BunnyImages.image(face.image).resizable()
                            BunnyImages.image(face.eyes).resizable()
                        }
                        .aspectRatio(BunnyArt.aspect, contentMode: .fit)
                        .scaleEffect(2.6, anchor: UnitPoint(x: 0.5, y: 0.42))
                        .frame(width: 78, height: 78)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                        .scaleEffect(on ? 1.06 : 1)
                        .shadow(color: on ? Theme.glow(0.3) : .clear, radius: 8, y: 3)
                        Text(face.label).font(.jakarta(12, on ? .bold : .medium))
                            .foregroundStyle(on ? Palette.text : Palette.text2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BouncyStyle(scale: 0.9))
                .accessibilityLabel("Face: \(face.label)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(ChoicePop(index: i))
            }
        }
        .padding(14)
        .sugarCard(radius: 24)
    }

    // Her top (one at a time), each shown as the piece itself, then the
    // picture clothes; the colour works on the first ones.
    private var outfits: some View {
        let tops = catalog.items(.top)
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(BunnyTop.allCases.enumerated()), id: \.element.id) { i, top in
                    clothes(top.label, pieces: top.piece.map { [$0] } ?? [], on: look.wear.isEmpty && look.top == top, index: i) {
                        look.top = top
                        look.wear = ""
                    }
                }
                ForEach(Array(tops.enumerated()), id: \.element.id) { i, item in
                    itemTile(item, on: look.wear == item.id, index: BunnyTop.allCases.count + i) { look.wear = item.id }
                }
                if isAdmin { addTile(.top, index: BunnyTop.allCases.count + tops.count) }
            }
            if look.wear.isEmpty && look.top != .none {
                ListHeader(title: "COLOUR").padding(.leading, 6)
                swatches(.outfit)
            }
        }
    }

    // Hats, headphones and the like (one at a time, instead of the bow).
    private var accessories: some View {
        let heads = catalog.items(.head)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            clothes("None", pieces: [], on: look.head.isEmpty, index: 0) { look.head = "" }
            ForEach(Array(heads.enumerated()), id: \.element.id) { i, item in
                itemTile(item, on: look.head == item.id, index: i + 1) { look.head = item.id }
            }
            if isAdmin { addTile(.head, index: heads.count + 1) }
        }
    }

    // A picture item, zoomed to the part she wears.
    private func itemTile(_ item: BunnyItem, on: Bool, index: Int, pick: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.playful) { pick() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.soft : Palette.surface2)
                    BunnyItemLayer(item: item)
                        .aspectRatio(BunnyArt.aspect, contentMode: .fit)
                        .scaleEffect(item.tileZoom, anchor: item.tileFocus)
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                .scaleEffect(on ? 1.03 : 1)
                Text(item.name).font(.jakarta(12, on ? .bold : .medium))
                    .foregroundStyle(on ? Palette.text : Palette.text2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.93))
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .modifier(ChoicePop(index: index))
        .modifier(TeamDelete(enabled: isAdmin && item.uploaded) { Task { await remove(item) } })
    }

    // The team adds a new item here.
    private func addTile(_ slot: BunnySlot, index: Int) -> some View {
        Button { adding = slot } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.main)
                    .frame(height: 84)
                    .frame(maxWidth: .infinity)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.main.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                Text("Add item").font(.jakarta(12, .bold)).foregroundStyle(Theme.main).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.93))
        .accessibilityLabel("Add a new \(slot == .top ? "clothes" : "accessory") item for everyone")
        .modifier(ChoicePop(index: index))
    }

    private func remove(_ item: BunnyItem) async {
        do {
            try await catalog.remove(item)
            if look.wear == item.id { look.wear = "" }
            if look.head == item.id { look.head = "" }
            model.showToast("Item deleted", icon: "trash.fill")
        } catch {
            model.showToast("Couldn't delete it — \(error.localizedDescription)", error: true)
        }
    }

    private func clothes(_ title: String, pieces: [BunnyPiece], on: Bool, index: Int, pick: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.playful) { pick() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.soft : Palette.surface2)
                    if pieces.isEmpty {
                        Image(systemName: "circle.slash").font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.muted)
                    } else {
                        ZStack {
                            ForEach(pieces, id: \.self) { piece in BunnyLayer(piece, look.tint(.outfit)) }
                            if pieces.contains(.sailor) { BunnyLayer("BunnyCollar", look.tint(.collar)) }
                        }
                        .aspectRatio(BunnyArt.aspect, contentMode: .fit)
                        .scaleEffect(2.4, anchor: UnitPoint(x: 0.5, y: 0.68))
                    }
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                .scaleEffect(on ? 1.03 : 1)
                Text(title).font(.jakarta(12, on ? .bold : .medium))
                    .foregroundStyle(on ? Palette.text : Palette.text2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.93))
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .modifier(ChoicePop(index: index))
    }

    private func swatches(_ part: BunnyPart) -> some View {
        let picked = look.index(part)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(Array(part.tints.enumerated()), id: \.element.id) { i, tint in
                let on = picked == i
                Button {
                    withAnimation(Motion.playful) { look.set(part, i) }
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: Palette.mix(tint.swatch, 0xFFFFFF, 0.35)), Color(hex: tint.swatch)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center)).padding(3))
                            .overlay {
                                if on {
                                    Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: 52, height: 52)
                            .padding(4)
                            .overlay(Circle().strokeBorder(on ? Color(hex: tint.swatch) : .clear, lineWidth: 3))
                            .scaleEffect(on ? 1.06 : 1)
                            .shadow(color: Color(hex: tint.swatch).softGlow(on ? 0.45 : 0.18), radius: on ? 8 : 4, y: 3)
                        Text(tint.name).font(.jakarta(12, on ? .bold : .medium))
                            .foregroundStyle(on ? Palette.text : Palette.text2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BouncyStyle(scale: 0.9))
                .accessibilityLabel("\(part.label): \(tint.name)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(ChoicePop(index: i))
            }
        }
        .padding(16)
        .sugarCard(radius: 24)
    }

    private var scenes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(Array(BunnyScene.allCases.enumerated()), id: \.element.id) { i, scene in
                let on = look.scene == scene
                Button {
                    withAnimation(Motion.playful) { look.scene = scene }
                } label: {
                    VStack(spacing: 6) {
                        BunnySceneView(scene: scene, animated: false)
                            .frame(height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, Theme.main)
                                        .padding(6).transition(.scale.combined(with: .opacity))
                                }
                            }
                            .scaleEffect(on ? 1.03 : 1)
                        Text(scene.label).font(.jakarta(12, on ? .bold : .medium))
                            .foregroundStyle(on ? Palette.text : Palette.text2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BouncyStyle(scale: 0.93))
                .accessibilityLabel("Background: \(scene.label)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(ChoicePop(index: i))
            }
        }
        .padding(12)
        .sugarCard(radius: 24)
    }

    // MARK: actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { Task { await useAsPicture() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) } else { Image(systemName: "person.crop.circle.fill") }
                    Text("Use as my profile picture")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 52))
            .disabled(busy || model.me == nil)
            HStack(spacing: 10) {
                Button { Task { await saveToPhotos() } } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
                Button {
                    withAnimation(Motion.playful) { look = BunnyLook() }
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
            }
        }
    }

    private func useAsPicture() async {
        guard !busy, let image = BunnyPortrait.render(look, side: 720), let data = image.pngData() else { return }
        busy = true
        defer { busy = false }
        do {
            let url = try await StorageClient.upload(data, contentType: "image/png", fileExtension: "png", screen: false)
            try await model.updateMe(["profile_picture": url])
            cheer += 1
            model.showToast("Your bunny is your profile picture now", icon: "hare.fill")
        } catch {
            model.showToast("Couldn't change your picture. Try again.", error: true)
        }
    }

    private func saveToPhotos() async {
        guard let image = BunnyPortrait.render(look, side: 1080), let data = image.pngData() else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            model.showToast("Allow Sugerly to add to Photos in Settings.", error: true)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            cheer += 1
            model.showToast("Saved to Photos", icon: "checkmark.circle.fill")
        } catch {
            model.showToast("Couldn't save it. Try again.", error: true)
        }
    }
}

// Choices pop in one after another when a tab opens.
private struct ChoicePop: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.playful.delay(Double(min(index, 10)) * 0.035)) { shown = true }
            }
    }
}

// Long-press an uploaded item to delete it (the team only).
private struct TeamDelete: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                Button(role: .destructive, action: action) { Label("Delete item", systemImage: "trash") }
            }
        } else {
            content
        }
    }
}
