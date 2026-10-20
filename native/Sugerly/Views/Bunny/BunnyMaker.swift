import SwiftUI
import UIKit
import Photos

// The bunny maker: your bunny on a little stage at the top, then a row of
// tabs (fur, face, outfit, accessories, collar, background) and the choices for
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
    @State private var editing: BunnyItem?
    @State private var deleting: BunnyItem?
    @State private var arranging: BunnySlot?
    @State private var buying: BunnyItem?
    @State private var owned = Set<String>()
    @State private var purchasing = false
    @State private var catalog = BunnyCatalog.shared

    enum Tab: String, CaseIterable, Identifiable {
        case body, fur, face, outfit, accessory, collar, scene
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
            case .body: return "pawprint.fill"
            case .fur: return "hare.fill"
            case .collar: return "seal.fill"
            case .outfit: return "tshirt.fill"
            case .face: return "face.smiling.inverse"
            case .accessory: return "headphones"
            case .scene: return "photo.fill"
            }
        }
        var candy: Candy {
            switch self {
            case .body: return .berry
            case .fur: return .berry
            case .collar: return .peach
            case .outfit: return .sky
            case .face: return .lemon
            case .accessory: return .grape
            case .scene: return .mint
            }
        }
        var part: BunnyPart? {
            switch self {
            case .fur: return .fur
            case .collar: return .collar
            default: return nil
            }
        }
    }

    var body: some View {
        ZStack {
            if loaded { editor.transition(.identity) }
            else {
                VStack(spacing: 14) {
                    Image(systemName: "hare.fill").font(.system(size: 54)).foregroundStyle(Theme.main)
                    Text("Getting your bunny ready…").font(.display(22)).foregroundStyle(Palette.text)
                    ProgressView().tint(Theme.main)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.surface)
            }
        }
        .task {
            guard !loaded else { return }
            store.use(model.me?.email ?? "")
            look = store.look
            let ids = [look.bodyItem, look.faceItem, look.collarItem] + look.layers(.top).map(\.id) + look.layers(.head).map(\.id)
            if ids.contains(where: { !$0.isEmpty && !$0.hasPrefix("classic:") && catalog.item($0) == nil }) { await catalog.load() }
            await BunnyImages.prepare(look)
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { loaded = true }
        }
        .navigationTitle("Customize bunny")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var editor: some View {
        ScrollView {
            VStack(spacing: 18) {
                stage
                tabs
                choices
                    .id(tab)
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
        .navigationTitle("Customize bunny")
        .navigationBarTitleDisplayMode(.inline)

        .task(id: look) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { store.save(look) }
        }
        .onDisappear { if loaded { store.save(look) } }
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.success, trigger: cheer)
        .task {
            await catalog.load()
            if let email = model.me?.email,
               let docs = try? await FS.query("BunnyPurchase", [.equals("user_email", email)], limit: 1000) {
                owned = Set(docs.map { $0.str("item_id") })
            }
        }
        .sheet(item: $arranging) { slot in BunnyLayerEditor(look: $look, slot: slot) }
        .sheet(item: $editing) { item in BunnyItemEditView(item: item) }
        .alert("Delete uploaded item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let item = deleting { Task { await remove(item) } }; deleting = nil }
        } message: { Text("This removes the item from everyone's catalog and bunny. Purchases already made are not refunded.") }
        .confirmationDialog("Buy this bunny item?", isPresented: Binding(get: { buying != nil }, set: { if !$0 { buying = nil } }), titleVisibility: .visible) {
            if let item = buying {
                Button("Buy \(item.name) for \(item.price) coins") { Task { await purchase(item) } }
            }
            Button("Cancel", role: .cancel) { buying = nil }
        }
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
            .background(RoundedRectangle(cornerRadius: 32).fill(Theme.main.opacity(0.12)).offset(y: 3))
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
                        // Instant, so you can hop between tabs as fast as you like.
                        tab = item
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
        if tab == .body {
            catalogChoices(.body)
        } else if tab == .collar {
            catalogChoices(.collar)
            swatches(.collar)
        } else if let part = tab.part {
            swatches(part)
        } else if tab == .face {
            faces
            catalogChoices(.face)
        } else if tab == .outfit {
            outfits
        } else if tab == .accessory {
            accessories
        } else {
            scenes
        }
    }

    private func selected(_ slot: BunnySlot) -> String {
        switch slot { case .body: return look.bodyItem; case .face: return look.faceItem; case .collar: return look.collarItem; default: return "" }
    }

    private func catalogChoices(_ slot: BunnySlot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            Button(slot == .body ? "Classic bunny" : "Default") {
                switch slot { case .body: look.bodyItem = ""; case .face: look.faceItem = ""; case .collar: look.collarItem = ""; default: break }
            }.buttonStyle(OutlineButtonStyle(fullWidth: true))
            ForEach(Array(catalog.items(slot).enumerated()), id: \.element.id) { i, item in
                itemTile(item, on: selected(slot) == item.id, index: i) {
                    switch slot { case .body: look.bodyItem = item.id; case .face: look.faceItem = item.id; case .collar: look.collarItem = item.id; default: break }
                }
            }
            if isAdmin { addTile(slot, index: catalog.items(slot).count) }
        }
    }

    // Each face shown on your bunny's own fur.
    private var faces: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(Array(BunnyFace.allCases.enumerated()), id: \.element.id) { i, face in
                let on = look.face == face
                Button {
                    withAnimation(Motion.playful) { look.face = face; look.faceItem = "" }
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
                    clothes(top.label, pieces: top.piece.map { [$0] } ?? [], on: top == .none ? look.layers(.top).isEmpty : look.layers(.top).contains { $0.id == "classic:" + top.rawValue }, index: i) {
                        if top == .none { look.setLayers([], .top) }
                        else { toggle("classic:" + top.rawValue, slot: .top) }
                    }
                }
                ForEach(Array(tops.enumerated()), id: \.element.id) { i, item in
                    itemTile(item, on: look.layers(.top).contains { $0.id == item.id }, index: BunnyTop.allCases.count + i) { toggle(item.id, slot: .top) }
                }
                if isAdmin { addTile(.top, index: BunnyTop.allCases.count + tops.count) }
            }
            arrangeButton(.top)
            if !look.layers(.top).isEmpty {
                ListHeader(title: "COLOUR").padding(.leading, 6)
                swatches(.outfit)
            }
        }
    }

    // One thing on her head at a time: the bow, or a hat, headphones and
    // the like. Then the colour of whichever she wears.
    private var accessories: some View {
        let heads = catalog.items(.head)
        let bow = look.layers(.head).contains { $0.id == "classic:bow" }
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                clothes("None", pieces: [], on: look.layers(.head).isEmpty, index: 0) {
                    look.setLayers([], .head)
                }
                bowTile(on: bow)
                ForEach(Array(heads.enumerated()), id: \.element.id) { i, item in
                    itemTile(item, on: look.layers(.head).contains { $0.id == item.id }, index: i + 2) { toggle(item.id, slot: .head) }
                }
                if isAdmin { addTile(.head, index: heads.count + 2) }
            }
            arrangeButton(.head)
            if !look.layers(.head).isEmpty {
                ListHeader(title: "COLOUR").padding(.leading, 6)
                swatches(.accessory)
                if bow { ListHeader(title: "BOW COLOUR"); swatches(.bow) }
            }
        }
    }

    // The bow, zoomed to where she wears it.
    private func bowTile(on: Bool) -> some View {
        Button {
            withAnimation(Motion.playful) {
                toggle("classic:bow", slot: .head)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.soft : Palette.surface2)
                    BunnyLayer("BunnyBow", look.tint(.bow))
                        .aspectRatio(BunnyArt.aspect, contentMode: .fit)
                        .scaleEffect(2.3, anchor: UnitPoint(x: 0.72, y: 0.19))
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                .scaleEffect(on ? 1.03 : 1)
                Text("Bow").font(.jakarta(12, on ? .bold : .medium))
                    .foregroundStyle(on ? Palette.text : Palette.text2).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.93))
        .accessibilityLabel("Bow")
        .accessibilityAddTraits(on ? .isSelected : [])
        .modifier(ChoicePop(index: 1))
    }

    // A picture item, zoomed to the part she wears.
    private func itemTile(_ item: BunnyItem, on: Bool, index: Int, pick: @escaping () -> Void) -> some View {
        Button {
            if item.price > 0 && !owned.contains(item.id) { buying = item }
            else { pick() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.soft : Palette.surface2)
                    BunnyItemLayer(item: item, tint: look.tint(item.slot == .top ? .outfit : .accessory))
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
                if item.price > 0 { Text(owned.contains(item.id) ? "Owned" : "\(item.price) coins").font(.jakarta(11, .bold)).foregroundStyle(Theme.main) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.93))
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .modifier(ChoicePop(index: index))
        .disabled(purchasing)
        .overlay(alignment: .topTrailing) {
            if isAdmin && item.uploaded {
                Menu {
                    Button { editing = item } label: { Label("Rename / price", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = item } label: { Label("Delete item", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.system(size: 24))
                        .foregroundStyle(Theme.main, Palette.surface).frame(width: 44, height: 44)
                }.accessibilityLabel("Manage \(item.name)")
            }
        }
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
            look.setLayers(look.layers(.top).filter { $0.id != item.id }, .top)
            look.setLayers(look.layers(.head).filter { $0.id != item.id }, .head)
            if look.wear == item.id { look.wear = "" }
            if look.head == item.id { look.head = "" }
            if look.bodyItem == item.id { look.bodyItem = "" }
            if look.faceItem == item.id { look.faceItem = "" }
            if look.collarItem == item.id { look.collarItem = "" }
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
        return VStack(spacing: 14) {
            ColorPicker("Custom colour · Free", selection: customColor(part), supportsOpacity: false)
                .font(.jakarta(14, .bold)).frame(minHeight: 44)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(Array(part.tints.enumerated()), id: \.element.id) { i, tint in
                let on = picked == i && look.customColors[part.rawValue] == nil
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
        }
        .padding(16)
        .sugarCard(radius: 24)
    }

    private func customColor(_ part: BunnyPart) -> Binding<Color> {
        Binding(get: { Color(hex: look.tint(part).swatch) }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ value: CGFloat) -> UInt32 { UInt32(max(0, min(255, value * 255))) }
            look.customColors[part.rawValue] = (byte(r) << 16) | (byte(g) << 8) | byte(b)
        })
    }

    private func toggle(_ id: String, slot: BunnySlot) {
        switch slot {
        case .body: look.bodyItem = id; return
        case .face: look.faceItem = id; return
        case .collar: look.collarItem = id; return
        default: break
        }
        var layers = look.layers(slot)
        if layers.contains(where: { $0.id == id }) { layers.removeAll { $0.id == id } }
        else {
            guard layers.count < 3 else { model.showToast("Up to 3 items per tab. Remove one first."); return }
            layers.append(.init(id: id))
        }
        look.setLayers(layers, slot)
    }

    private func arrangeButton(_ slot: BunnySlot) -> some View {
        Button { arranging = slot } label: {
            Label("Arrange layers (\(look.layers(slot).count)/3)", systemImage: "square.3.layers.3d")
        }.buttonStyle(OutlineButtonStyle(fullWidth: true)).disabled(look.layers(slot).isEmpty)
    }

    private func purchase(_ item: BunnyItem) async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false; buying = nil }
        do {
            _ = try await Backend.call("bunny-purchase", ["item_id": item.id, "expected_price": item.price], signedIn: true, missing: "The shop is temporarily unavailable.")
            owned.insert(item.id)
            try? await model.loadProfile()
            toggle(item.id, slot: item.slot)
            model.showToast("Item unlocked", icon: "checkmark.circle.fill")
        } catch { model.showToast(error.localizedDescription, error: true) }
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
        // No fade-in: the choices are simply there when a tab opens.
        content
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
