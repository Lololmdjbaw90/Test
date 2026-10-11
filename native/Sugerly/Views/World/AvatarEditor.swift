import SwiftUI

// Dress up your avatar: a skin colour for each body part, then the shirts
// and pants you own. Drag the avatar to turn it around.
struct AvatarEditorView: View {
    var onSave: ((AvatarLook) -> Void)? = nil
    // In a sheet of its own, or a page pushed in the app (no extra top bar).
    var standalone = true
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var look = AvatarLook.starter
    @State private var tab: Tab = .body
    @State private var group: PartGroup = .all
    @State private var owned: [CatalogItem] = []
    @State private var saving = false
    @State private var shopping = false
    @State private var making: CatalogItem.Kind?
    @State private var custom = Color(hex: 0xF6D2B8)
    @State private var error: String?

    init(standalone: Bool = true, onSave: ((AvatarLook) -> Void)? = nil) {
        self.standalone = standalone
        self.onSave = onSave
    }

    enum Tab: String, CaseIterable, Identifiable {
        case body = "Body", shirt = "Shirts", pants = "Pants"
        var id: String { rawValue }
        var kind: CatalogItem.Kind? {
            switch self {
            case .body: return nil
            case .shirt: return .shirt
            case .pants: return .pants
            }
        }
        var icon: String {
            switch self {
            case .body: return "figure.stand"
            case .shirt: return "tshirt.fill"
            case .pants: return "figure.walk"
            }
        }
        var framing: AvatarStage.Framing { self == .shirt ? .upper : .full }
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
        Group {
            // Sideways (in the game): the avatar on the left, choices on the right.
            if verticalSize == .compact {
                HStack(spacing: 0) {
                    stage
                        .frame(maxHeight: .infinity)
                        .frame(width: 280)
                        .padding(.vertical, 8)
                    VStack(spacing: 0) {
                        tabBar
                        choices
                    }
                }
            } else {
                VStack(spacing: 0) {
                    stage
                        .frame(height: 290)
                        .padding(.top, 6)
                    tabBar
                    choices
                }
            }
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
        .onChange(of: model.me?.avatarItems ?? []) { _, _ in Task { await loadOwned() } }
        .sheet(isPresented: $shopping) {
            NavigationStack { CatalogView() }
                .presentationCornerRadius(30)
        }
        .fullScreenCover(item: $making) { kind in ClothingStudioView(kind: kind) }
    }

    // MARK: pieces

    private var choices: some View {
        ScrollView {
            Group {
                if let kind = tab.kind { itemsGrid(kind) } else { bodyColours }
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

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
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { t in
                let on = tab == t
                Button { withMotion(.spring(response: 0.3, dampingFraction: 0.8)) { tab = t } } label: {
                    Label(t.rawValue, systemImage: t.icon)
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(on ? .white : Palette.text2)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background {
                            if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface) }
                        }
                        .overlay(Capsule().strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.94))
                .sensoryFeedback(.selection, trigger: on)
            }
        }
        .padding(.horizontal, 16)
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
                                        .foregroundStyle(hex > 0xE0E0E0 ? Palette.text : .white)
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
        let list = owned.filter { $0.kind == kind }
        let none = kind == .shirt ? look.shirt.isEmpty : look.pants.isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                actionPill("Shop", icon: "bag.fill") { shopping = true }
                actionPill("Upload", icon: "square.and.arrow.up") { making = kind }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                Button { takeOff(kind) } label: { NoneTile(kind: kind, selected: none) }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                ForEach(list) { item in
                    let on = CatalogShop.wearing(item, look)
                    Button { withMotion(.spring(response: 0.3, dampingFraction: 0.75)) { look = AvatarSnapshot.look(trying: item, on: look) } } label: {
                        ItemTile(item: item, selected: on)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                }
            }
            if list.isEmpty {
                Text("No \(kind == .shirt ? "shirts" : "pants") yet. Get some in the shop or upload your own.")
                    .font(.jakarta(13)).foregroundStyle(Palette.muted)
            }
            if let error {
                Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger)
            }
        }
    }

    private func actionPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.jakarta(14, .bold))
                .foregroundStyle(Theme.main)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(Theme.soft, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.main.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(BouncyStyle(scale: 0.95))
    }

    // MARK: actions

    private func takeOff(_ kind: CatalogItem.Kind) {
        withMotion(.spring(response: 0.3, dampingFraction: 0.75)) {
            if kind == .shirt { look.shirt = ""; look.shirtURL = "" } else { look.pants = ""; look.pantsURL = "" }
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
        await loadOwned()
    }

    private func loadOwned() async {
        guard let me = model.me else { return }
        owned = await CatalogShop.owned(me)
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

// "None": the plain body, in the same style as the clothes next to it.
struct NoneTile: View {
    let kind: CatalogItem.Kind
    var selected = false
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.surface2.opacity(0.8), Palette.surface], startPoint: .top, endPoint: .bottom))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(4).opacity(0.85)
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
            Text("None").font(.jakarta(12, .bold)).foregroundStyle(selected ? Theme.main : Palette.text2)
        }
        .padding(.top, 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        .task(id: kind) { image = AvatarSnapshot.bare(kind) }
    }
}
