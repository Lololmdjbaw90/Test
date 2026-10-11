import SwiftUI

// The avatar shop: Sugerly's own clothes and accessories, plus shirts and
// pants people paint themselves. Everything costs in-app coins; makers get
// 70% of each sale.
struct CatalogView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var sort: Sort = .new
    @State private var made: [CatalogItem] = []
    @State private var loading = false
    @State private var selected: CatalogItem?
    @State private var creating: CatalogItem.Kind?
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", shirt = "Shirts", pants = "Pants", hat = "Hats", back = "Back", face = "Faces", mine = "Made by me"
        var id: String { rawValue }
        var kind: CatalogItem.Kind? {
            switch self {
            case .shirt: return .shirt
            case .pants: return .pants
            case .hat: return .hat
            case .back: return .back
            case .face: return .face
            default: return nil
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case new = "New", popular = "Popular"
        var id: String { rawValue }
    }

    private var showsMade: Bool { filter == .all || filter == .shirt || filter == .pants || filter == .mine }
    private var showsOwn: Bool { filter != .mine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                chips
                if showsMade { madeSection }
                if showsOwn { ownSection }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background { Palette.bg.ignoresSafeArea() }
        .roundTitle("Catalog")
        .searchable(text: $search, prompt: "Search clothes")
        .task(id: "\(filter.rawValue)-\(sort.rawValue)") { await load() }
        .task { await CatalogShop.collect(model: model) }
        .refreshable { await load() }
        .sheet(item: $selected) { item in
            CatalogItemSheet(item: item) { removed in
                if removed { made.removeAll { $0.id == item.id } }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(30)
        }
        .fullScreenCover(item: $creating) { kind in
            ClothingStudioView(kind: kind) { item in
                made.insert(item, at: 0)
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                CoinIcon(size: 22)
                Text("\(model.me?.coins ?? 0)").font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            Spacer(minLength: 0)
            Menu {
                Button { creating = .shirt } label: { Label("Make a shirt", systemImage: "tshirt.fill") }
                Button { creating = .pants } label: { Label("Make pants", systemImage: "figure.walk") }
            } label: {
                Label("Create", systemImage: "paintbrush.pointed.fill")
                    .font(.jakarta(15, .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 42)
                    .background(Theme.gradient, in: Capsule())
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { f in
                    let on = filter == f
                    Button { withMotion(.spring(response: 0.3, dampingFraction: 0.8)) { filter = f } } label: {
                        Text(f.rawValue).font(.jakarta(14, .bold))
                            .foregroundStyle(on ? .white : Palette.text2)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background {
                                if on { Capsule().fill(Theme.gradient) } else { Capsule().fill(Palette.surface) }
                            }
                            .overlay(Capsule().strokeBorder(on ? .clear : Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.92))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var madeSection: some View {
        let list = madeShown
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(filter == .mine ? "Your creations" : "Made by artists").font(.display(24)).foregroundStyle(Palette.text)
                Spacer()
                if filter != .mine {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
            if loading && made.isEmpty {
                HStack { Spacer(); SugarLoader(size: 12); Spacer() }.padding(.vertical, 30)
            } else if list.isEmpty {
                EmptyCard(icon: "tshirt.fill",
                          title: filter == .mine ? "Nothing made yet" : "No clothes yet",
                          text: "Paint a shirt or pants on the template and sell it for coins.",
                          actionTitle: "Make a shirt", action: { creating = .shirt }, compact: true)
            } else {
                grid(list)
            }
        }
    }

    private var ownSection: some View {
        let list = CatalogItem.builtIns.filter { item in
            (filter.kind == nil || item.kind == filter.kind) && matches(item)
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("From Sugerly").font(.display(24)).foregroundStyle(Palette.text)
            grid(list)
        }
    }

    private func grid(_ list: [CatalogItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(list) { item in
                Button { selected = item } label: { CatalogCard(item: item) }
                    .buttonStyle(BouncyStyle(scale: 0.95))
            }
        }
    }

    private var madeShown: [CatalogItem] {
        var list = made.filter(matches)
        if filter != .mine { list = list.filter(\.onSale) }
        if let kind = filter.kind { list = list.filter { $0.kind == kind } }
        if sort == .popular && filter != .mine { list.sort { $0.sales > $1.sales } }
        return list
    }

    private func matches(_ item: CatalogItem) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || item.name.lowercased().contains(q) || item.creatorName.lowercased().contains(q)
    }

    private func load() async {
        guard showsMade, let me = model.me else { return }
        loading = true
        defer { loading = false }
        var filters: [FS.Filter] = []
        if filter == .mine { filters.append(.equals("creator_email", me.email)) }
        if let kind = filter.kind, kind.paintable { filters.append(.equals("kind", kind.rawValue)) }
        let order = sort == .popular && filter != .mine ? "sales" : "created_date"
        let docs = (try? await FS.query("CatalogItem", filters, orderBy: order, limit: 80)) ?? []
        var list = docs.compactMap { CatalogItem($0) }
        list.removeAll { me.blocked.contains($0.creatorEmail) }
        made = list
    }
}

// A card in the shop grid.
struct CatalogCard: View {
    let item: CatalogItem
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        let owned = model.me.map { CatalogShop.owns(item, $0) } ?? false
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(colors: [Theme.light.opacity(0.25), Palette.surface], startPoint: .top, endPoint: .bottom)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(6).transition(.opacity)
                } else {
                    SugarLoader(size: 10)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                if owned {
                    Label("Owned", systemImage: "checkmark")
                        .font(.jakarta(11, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Palette.success, in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                Text(item.creatorName.isEmpty ? "Sugerly" : "by \(item.creatorName)")
                    .font(.jakarta(12, .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                HStack(spacing: 5) {
                    if item.price == 0 {
                        Text("Free").font(.jakarta(13, .heavy)).foregroundStyle(Palette.success)
                    } else {
                        CoinIcon(size: 16)
                        Text("\(item.price)").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text)
                    }
                    Spacer(minLength: 0)
                    if item.sales > 0 {
                        Text("\(item.sales) sold").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .task(id: item.id) {
            if let hit = AvatarSnapshot.cached(item) { image = hit; return }
            let made = await AvatarSnapshot.image(for: item)
            withAnimation(.easeOut(duration: 0.25)) { image = made }
        }
    }
}

// One item: try it on (on your own avatar), buy it, wear it.
struct CatalogItemSheet: View {
    let item: CatalogItem
    var onChange: ((Bool) -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    @State private var confirm = false
    @State private var burst = 0
    @State private var reporting: ReportSheet.Target?
    @State private var removing = false

    var body: some View {
        let me = model.me
        let owned = me.map { CatalogShop.owns(item, $0) } ?? false
        let wearing = me.map { CatalogShop.wearing(item, $0.avatar) } ?? false
        let mine = !item.creatorEmail.isEmpty && item.creatorEmail == me?.email
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    LinearGradient(colors: [Theme.light.opacity(0.4), Palette.surface], startPoint: .top, endPoint: .bottom)
                    AvatarStage(look: AvatarSnapshot.look(trying: item, on: me?.avatar ?? .starter),
                                framing: AvatarSnapshot.framing(for: item.kind) == .back ? .back : .full)
                    ConfettiBurst(trigger: burst).allowsHitTesting(false)
                }
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .bottom) {
                    Text("Trying it on · drag to turn").font(.jakarta(12, .bold)).foregroundStyle(Palette.text2)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }

                VStack(spacing: 6) {
                    Text(item.name).font(.display(30)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
                    Text(item.creatorName.isEmpty ? "by Sugerly" : "by \(item.creatorName)")
                        .font(.jakarta(14, .semibold)).foregroundStyle(Palette.muted)
                    if item.sales > 0 {
                        Text("\(item.sales) sold").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    }
                }

                if let error {
                    Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger).multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                if owned {
                    Button { Task { await wear() } } label: {
                        HStack(spacing: 8) {
                            if busy { SugarLoader(size: 9) }
                            Image(systemName: wearing ? "checkmark" : "tshirt.fill")
                            Text(wearing ? "You're wearing it" : "Wear it")
                        }
                    }
                    .buttonStyle(GradientButtonStyle(height: 54))
                    .disabled(busy || wearing)
                } else {
                    Button { confirm = true } label: {
                        HStack(spacing: 8) {
                            if busy { SugarLoader(size: 9) }
                            if item.price == 0 {
                                Text("Get it free")
                            } else {
                                Text("Buy for")
                                CoinIcon(size: 20)
                                Text("\(item.price)")
                            }
                        }
                    }
                    .buttonStyle(GradientButtonStyle(height: 54))
                    .disabled(busy)
                    if let coins = me?.coins, coins < item.price {
                        Text("You have \(coins) coins. Earn more with the daily reward, posting, or the star at the top of the Sugar World tower.")
                            .font(.jakarta(12.5)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }
                }

                if !item.builtIn {
                    HStack(spacing: 10) {
                        if !mine {
                            Button {
                                reporting = ReportSheet.Target(id: item.id, type: "catalog item", ownerEmail: item.creatorEmail,
                                                               preview: item.name, link: "/Catalog?item=\(item.id)",
                                                               collection: "CatalogItem", media: item.imageURL)
                            } label: { Label("Report", systemImage: "flag.fill") }
                                .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
                        }
                        if mine || me?.isAdmin == true {
                            Button(role: .destructive) { removing = true } label: { Label(mine ? "Stop selling" : "Remove", systemImage: "trash") }
                                .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { Palette.bg.ignoresSafeArea() }
        .confirmationDialog(item.price == 0 ? "Get \(item.name)?" : "Buy \(item.name) for \(item.price) coins?", isPresented: $confirm, titleVisibility: .visible) {
            Button(item.price == 0 ? "Get it" : "Buy") { Task { await buy() } }
        }
        .confirmationDialog(mine ? "Stop selling this? People who bought it keep it." : "Remove this from the catalog?", isPresented: $removing, titleVisibility: .visible) {
            Button(mine ? "Stop selling" : "Remove", role: .destructive) { Task { await remove(mine: mine) } }
        }
        .sheet(item: $reporting) { target in ReportSheet(target: target) }
    }

    private func buy() async {
        busy = true
        defer { busy = false }
        do {
            try await CatalogShop.buy(item, model: model)
            burst += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withMotion { error = nil }
            await CatalogShop.wear(item, model: model)
        } catch {
            withMotion { self.error = error.localizedDescription }
        }
    }

    private func wear() async {
        busy = true
        await CatalogShop.wear(item, model: model)
        busy = false
    }

    private func remove(mine: Bool) async {
        do {
            if mine && model.me?.isAdmin != true {
                try await FS.update("CatalogItem", item.id, ["on_sale": false, "updated_date": FS.nowISO()])
            } else {
                try await FS.delete("CatalogItem", item.id)
            }
            onChange?(true)
            dismiss()
        } catch {
            withMotion { self.error = "Couldn't do that. Check your connection and try again." }
        }
    }
}
