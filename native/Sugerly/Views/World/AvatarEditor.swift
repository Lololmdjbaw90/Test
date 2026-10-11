import SwiftUI

// Dress up your avatar: skin colours per body part, then the shirts, pants,
// faces, hats and back things you own. Drag the avatar to turn it around.
struct AvatarEditorView: View {
    var onSave: ((AvatarLook) -> Void)? = nil
    // In a sheet of its own, or a page pushed in the app (no extra top bar).
    var standalone = true
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var look = AvatarLook.starter
    @State private var tab: Tab = .body
    @State private var group: PartGroup = .all
    @State private var made: [CatalogItem] = []
    @State private var saving = false
    @State private var shopping = false
    @State private var custom = Color(hex: 0xF6D2B8)
    @State private var error: String?

    init(standalone: Bool = true, onSave: ((AvatarLook) -> Void)? = nil) {
        self.standalone = standalone
        self.onSave = onSave
    }

    enum Tab: String, CaseIterable, Identifiable {
        case body = "Body", shirt = "Shirts", pants = "Pants", face = "Faces", hat = "Hats", back = "Back"
        var id: String { rawValue }
        var kind: CatalogItem.Kind? {
            switch self {
            case .body: return nil
            case .shirt: return .shirt
            case .pants: return .pants
            case .face: return .face
            case .hat: return .hat
            case .back: return .back
            }
        }
        var icon: String {
            switch self {
            case .body: return "figure.stand"
            case .shirt: return "tshirt.fill"
            case .pants: return "figure.walk"
            case .face: return "face.smiling.inverse"
            case .hat: return "crown.fill"
            case .back: return "bag.fill"
            }
        }
        var framing: AvatarStage.Framing {
            switch self {
            case .body, .pants: return .full
            case .shirt: return .upper
            case .face, .hat: return .head
            case .back: return .back
            }
        }
    }

    enum PartGroup: String, CaseIterable, Identifiable {
        case all = "Everything", head = "Head", torso = "Body", arms = "Arms", legs = "Legs"
        var id: String { rawValue }
        var parts: [BodyPart] {
            switch self {
            case .all: return BodyPart.allCases
            case .head: return [.head]
            case .torso: return [.torso]
            case .arms: return [.leftArm, .rightArm]
            case .legs: return [.leftLeg, .rightLeg]
            }
        }
    }

    var body: some View {
        if standalone {
            NavigationStack { editor }
                .tint(Theme.main)
        } else {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            stage
            tabBar
            ScrollView {
                Group {
                    if let kind = tab.kind { itemsGrid(kind) } else { bodyColours }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background { Palette.bg.ignoresSafeArea() }
        .roundTitle("Avatar")
        .toolbar {
            if standalone {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.jakarta(16, .semibold))
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await save() } } label: {
                    if saving { SugarLoader(size: 9) } else { Text("Save").font(.jakarta(16, .heavy)) }
                }
                .disabled(saving)
            }
        }
        .task { await load() }
        .onChange(of: model.me?.avatarItems ?? []) { _, _ in Task { await loadMade() } }
        .sheet(isPresented: $shopping) {
            NavigationStack { CatalogView() }
                .presentationCornerRadius(30)
        }
    }

    // MARK: pieces

    private var stage: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Theme.light.opacity(0.35), Palette.surface], startPoint: .top, endPoint: .bottom)
            AvatarStage(look: look, framing: tab.framing)
            Button { look = model.me?.avatar ?? .starter } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(BouncyStyle(scale: 0.88))
            .accessibilityLabel("Undo changes")
            .padding(12)
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { t in
                    let on = tab == t
                    Button { withMotion(.spring(response: 0.3, dampingFraction: 0.8)) { tab = t } } label: {
                        Label(t.rawValue, systemImage: t.icon)
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(on ? .white : Palette.text2)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background {
                                if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface) }
                            }
                            .overlay(Capsule().strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.92))
                    .sensoryFeedback(.selection, trigger: on)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 12)
    }

    private var bodyColours: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(PartGroup.allCases) { g in
                        let on = group == g
                        Button { group = g } label: {
                            Text(g.rawValue).font(.jakarta(13, .bold))
                                .foregroundStyle(on ? Theme.main : Palette.text2)
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(on ? Theme.soft : Palette.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? Theme.main.opacity(0.5) : Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.92))
                    }
                }
            }
            .scrollIndicators(.hidden)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(AvatarLook.skinTones, id: \.self) { hex in
                    let on = group.parts.allSatisfy { look.color($0) == hex }
                    Button { paint(hex) } label: {
                        Circle().fill(Color(hex: hex))
                            .frame(height: 50)
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                            .overlay {
                                if on {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .black))
                                        .foregroundStyle(hex == 0xFFFFFF || hex > 0xE0E0E0 ? Palette.text : .white)
                                }
                            }
                            .overlay(Circle().strokeBorder(on ? Theme.main : .clear, lineWidth: 2.5).padding(-4))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.88))
                    .accessibilityLabel("Colour")
                }
            }
            HStack {
                Text("Any colour").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                Spacer()
                ColorPicker("", selection: $custom, supportsOpacity: false).labelsHidden()
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onChange(of: custom) { _, c in paint(Self.hex(c)) }
        }
    }

    private func itemsGrid(_ kind: CatalogItem.Kind) -> some View {
        let list = items(kind)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                if kind != .face {
                    let none = isNone(kind)
                    Button { takeOff(kind) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "circle.slash").font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(none ? Theme.main : Palette.border, lineWidth: none ? 2.5 : 1))
                            Text("None").font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                        }
                    }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                }
                ForEach(list) { item in
                    let on = CatalogShop.wearing(item, look)
                    Button { withMotion(.spring(response: 0.3, dampingFraction: 0.75)) { look = AvatarSnapshot.look(trying: item, on: look) } } label: {
                        ItemTile(item: item, selected: on)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                }
                Button { shopping = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "bag.fill.badge.plus").font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.gradient)
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.main.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        Text("Get more").font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
                    }
                }
                .buttonStyle(BouncyStyle(scale: 0.93))
            }
            if let error {
                Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
            }
        }
    }

    // MARK: actions

    private func items(_ kind: CatalogItem.Kind) -> [CatalogItem] {
        guard let me = model.me else { return [] }
        let own = CatalogItem.builtIns.filter { $0.kind == kind && CatalogShop.owns($0, me) }
        return own + made.filter { $0.kind == kind }
    }

    private func isNone(_ kind: CatalogItem.Kind) -> Bool {
        switch kind {
        case .shirt: return look.shirt.isEmpty
        case .pants: return look.pants.isEmpty
        case .hat: return look.hat.isEmpty
        case .back: return look.extra.isEmpty
        case .face: return false
        }
    }

    private func takeOff(_ kind: CatalogItem.Kind) {
        withMotion(.spring(response: 0.3, dampingFraction: 0.75)) {
            switch kind {
            case .shirt: look.shirt = ""; look.shirtURL = ""
            case .pants: look.pants = ""; look.pantsURL = ""
            case .hat: look.hat = ""
            case .back: look.extra = ""
            case .face: break
            }
        }
    }

    private func paint(_ hex: UInt32) {
        for part in group.parts { look.skin[part] = hex }
    }

    static func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(255, (r * 255).rounded())))
        let gi = UInt32(max(0, min(255, (g * 255).rounded())))
        let bi = UInt32(max(0, min(255, (b * 255).rounded())))
        return (ri << 16) | (gi << 8) | bi
    }

    private func load() async {
        look = model.me?.avatar ?? .starter
        await loadMade()
    }

    private func loadMade() async {
        guard let me = model.me else { return }
        made = await CatalogShop.ownedMade(me)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await model.updateMe(["avatar_look": look.json])
            onSave?(look)
            dismiss()
        } catch {
            withMotion { self.error = "Couldn't save your avatar. Check your connection and try again." }
        }
    }
}

// One thing in a grid: its picture on a plain body, its name and a tick
// when you're wearing it.
struct ItemTile: View {
    let item: CatalogItem
    var selected = false
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.light.opacity(0.22), Palette.surface], startPoint: .top, endPoint: .bottom))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(4)
                        .transition(.opacity)
                } else {
                    SugarLoader(size: 8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Theme.main : Palette.border, lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Theme.main, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2.5))
                        .offset(x: 5, y: -5)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            Text(item.name).font(.jakarta(12, .bold)).foregroundStyle(selected ? Theme.main : Palette.text2)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.top, 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        .task(id: item.id) {
            if let hit = AvatarSnapshot.cached(item) { image = hit; return }
            let made = await AvatarSnapshot.image(for: item)
            withAnimation(.easeOut(duration: 0.25)) { image = made }
        }
    }
}
