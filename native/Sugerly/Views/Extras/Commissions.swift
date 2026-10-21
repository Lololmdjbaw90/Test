import SwiftUI
import UIKit
import PhotosUI
import SafariServices

// MARK: - Commissions
//
// Artists open a shop (listings with price tiers and samples). A buyer sends
// a request, the artist accepts it (and can set the final price), the buyer
// pays by card through Stripe, the artist delivers the finished art and the
// buyer approves it with a review. Money only moves through the payment
// server (netlify/functions), which is also the only one that can mark an
// order paid. Sugerly keeps a small fee and pays artists out.

@MainActor
enum ArtistReview {
    static let required = "Artist verification is required before opening commissions. Add your portfolio and process links in Edit profile, then request a review through Help & support."
    static func require(_ uid: String) async throws {
        guard (try await FS.get("SiteConfig", "artist-" + uid))?["verified"] as? Bool == true else {
            throw APIError(message: required)
        }
    }
}

struct CommissionTier: Hashable {
    var name: String
    var price: Double
    var description: String
    var days: Int?
}

struct Commission: Identifiable, Hashable {
    var id: String
    var title: String
    var description: String
    var isOpen: Bool
    var currency: String
    var tags: [String]
    var tiers: [CommissionTier]
    var samples: [String]
    var artistEmail: String
    var artistName: String
    var artistPicture: String
    var created: String
    var ratingSum: Double
    var ratingCount: Int
    var ordersCompleted: Int

    var fromPrice: Double? { tiers.map(\.price).min() }
    var rating: Double? { ratingCount > 0 ? ratingSum / Double(ratingCount) : nil }

    init(_ d: Doc) {
        id = d.str("id")
        title = d.str("title")
        description = d.str("description")
        isOpen = (d["is_open"] as? Bool) ?? (d.str("status") == "open")
        let c = d.str("currency").lowercased()
        currency = Money.currencies.contains(c) ? c : "usd"
        tags = d.strs("tags")
        tiers = (d["tiers"] as? [Any] ?? []).compactMap { raw in
            guard let t = raw as? [String: Any] else { return nil }
            return CommissionTier(name: t["name"] as? String ?? "", price: ReelText.num(t["price"]) ?? 0, description: t["description"] as? String ?? "", days: ReelText.num(t["delivery_days"]).map { Int($0) })
        }
        samples = d.strs("samples")
        artistEmail = d.str("artist_email").lowercased()
        artistName = d.str("artist_display_name")
        artistPicture = d.str("artist_profile_picture")
        created = d.str("created_date")
        ratingSum = ReelText.num(d["rating_sum"]) ?? 0
        ratingCount = d.int("rating_count")
        ordersCompleted = d.int("orders_completed")
    }
}

enum Money {
    static let currencies = ["usd", "eur", "gbp", "cad", "aud"]

    static func format(_ amount: Double, _ currency: String) -> String {
        let whole = amount.rounded() == amount
        return amount.formatted(.currency(code: currency.uppercased()).precision(.fractionLength(whole ? 0 : 2)))
    }
}

struct CommissionOrder: Identifiable, Hashable {
    enum Status: String, CaseIterable {
        case requested, accepted, declined, cancelled, paid, inProgress = "in_progress", delivered, completed
        case refundRequested = "refund_requested", refunded

        var label: String {
            switch self {
            case .requested: return "Requested"
            case .accepted: return "Waiting for payment"
            case .declined: return "Declined"
            case .cancelled: return "Cancelled"
            case .paid: return "Paid"
            case .inProgress: return "In progress"
            case .delivered: return "Delivered"
            case .completed: return "Completed"
            case .refundRequested: return "Refund asked"
            case .refunded: return "Refunded"
            }
        }
        var icon: String {
            switch self {
            case .requested: return "paperplane.fill"
            case .accepted: return "creditcard.fill"
            case .declined, .cancelled: return "xmark.circle.fill"
            case .paid: return "checkmark.seal.fill"
            case .inProgress: return "paintbrush.pointed.fill"
            case .delivered: return "shippingbox.fill"
            case .completed: return "star.fill"
            case .refundRequested: return "arrow.uturn.backward.circle.fill"
            case .refunded: return "arrow.uturn.backward"
            }
        }
        var tint: UInt32 {
            switch self {
            case .requested: return 0x7C5CF0
            case .accepted: return 0xF0A020
            case .declined, .cancelled, .refunded: return 0x94A3B8
            case .paid, .inProgress: return 0x2F80E0
            case .delivered: return 0xE8457C
            case .completed: return 0x17A673
            case .refundRequested: return 0xE0526B
            }
        }
        // Where it is on the way from request to done (for the tracker).
        var step: Int {
            switch self {
            case .requested: return 0
            case .accepted: return 1
            case .paid: return 2
            case .inProgress: return 3
            case .delivered, .refundRequested: return 4
            case .completed: return 5
            case .declined, .cancelled, .refunded: return -1
            }
        }
        var isActive: Bool { ![.declined, .cancelled, .completed, .refunded].contains(self) }
        var isPaid: Bool { [.paid, .inProgress, .delivered, .completed, .refundRequested].contains(self) }
    }

    var id: String
    var commissionId: String
    var title: String
    var tier: String
    var cover: String
    var price: Double
    var currency: String
    var brief: String
    var references: [String]
    var buyerEmail: String
    var buyerName: String
    var artistEmail: String
    var artistName: String
    var artistUid: String
    var status: Status
    var quoteNote: String
    var deliveryURLs: [String]
    var deliveryNote: String
    var rating: Int
    var review: String
    var feePercent: Double?
    var artistEarnings: Double?
    var amountPaid: Double?
    var payoutStatus: String
    var created: String
    var updated: String

    init(_ d: Doc) {
        id = d.str("id")
        commissionId = d.str("commission_id")
        title = d.str("commission_title")
        tier = d.str("tier_name")
        cover = d.str("cover_url")
        price = ReelText.num(d["price"]) ?? 0
        let c = d.str("currency").lowercased()
        currency = Money.currencies.contains(c) ? c : "usd"
        brief = d.str("brief")
        references = d.strs("references")
        buyerEmail = d.str("buyer_email").lowercased()
        buyerName = d.str("buyer_name")
        artistEmail = d.str("artist_email").lowercased()
        artistName = d.str("artist_name")
        artistUid = d.str("artist_uid")
        status = Status(rawValue: d.str("status")) ?? .requested
        quoteNote = d.str("quote_note")
        deliveryURLs = d.strs("delivery_urls")
        deliveryNote = d.str("delivery_note")
        rating = d.int("rating")
        review = d.str("review")
        feePercent = ReelText.num(d["fee_percent"])
        artistEarnings = ReelText.num(d["artist_earnings"])
        amountPaid = ReelText.num(d["amount_paid"])
        payoutStatus = d.str("payout_status")
        created = d.str("created_date")
        updated = d.str("updated_date")
    }

    var link: String { "/Commissions?order=\(id)" }
    // What the artist gets (after Sugerly's fee), known once it's paid.
    var earnings: Double { artistEarnings ?? price * 0.9 }
}

// Talks to Sugerly's server (payments, call ringing, the call relay).
enum Payments {
    @discardableResult
    static func call(_ name: String, _ body: [String: Any]) async throws -> [String: Any] {
        try await Backend.call(name, body, signedIn: true, missing: "Sugerly's server isn't answering right now. Please try again in a moment.")
    }
}

// MARK: - The Commissions page

struct CommissionsView: View {
    enum Tab: String, CaseIterable {
        case explore = "Explore", orders = "My orders", shop = "My shop"
        var icon: String {
            switch self {
            case .explore: return "sparkles"
            case .orders: return "bag.fill"
            case .shop: return "storefront.fill"
            }
        }
    }
    enum Filter: String, CaseIterable { case all = "All", open = "Open now", budget = "Under 50", top = "Top rated" }

    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .explore
    @State private var filter: Filter = .all
    @State private var list: [Commission] = []
    @State private var buying: [CommissionOrder] = []
    @State private var selling: [CommissionOrder] = []
    @State private var adminOrders: [CommissionOrder] = []
    @State private var loading = true
    @State private var query = ""
    @State private var creating = false
    @State private var editing: Commission?
    @State private var selected: Commission?
    @State private var appeared = false
    @State private var payoutsReady: Bool?
    @Namespace private var tabPill

    private var me: String { model.me?.email ?? "" }
    private var myListings: [Commission] { list.filter { $0.artistEmail == me } }

    private var shown: [Commission] {
        var out = list.filter { c in
            query.isEmpty || c.title.localizedCaseInsensitiveContains(query) || model.name(c.artistEmail, c.artistName).localizedCaseInsensitiveContains(query)
                || c.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        switch filter {
        case .all: break
        case .open: out = out.filter(\.isOpen)
        case .budget: out = out.filter { ($0.fromPrice ?? 0) < 50 }
        case .top: out = out.filter { $0.rating != nil }.sorted { ($0.rating ?? 0, $0.ratingCount) > ($1.rating ?? 0, $1.ratingCount) }
        }
        // Open shops first.
        if filter != .top { out.sort { $0.isOpen && !$1.isOpen } }
        return out
    }

    private var needsMe: Int {
        buying.filter { $0.status == .accepted || $0.status == .delivered }.count
            + selling.filter { [.requested, .paid, .inProgress].contains($0.status) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero.stagger(appeared, 0)
                tabBar.stagger(appeared, 1)
                // Each tab slides in softly in place of the last.
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .explore: explore
                    case .orders: ordersTab
                    case .shop: shopTab
                    }
                }
                .id(tab)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity.animation(Motion.exit)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .motion(Motion.standard, value: tab)
        }
        .sugarBackground()
        .navigationTitle("Commissions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onAppear { appeared = true }
        .fullScreenCover(isPresented: $creating) { NewCommissionView(existing: nil) { await load() } }
        .fullScreenCover(item: $editing) { c in NewCommissionView(existing: c) { await load() } }
        .sheet(item: $selected) { c in
            CommissionDetail(commission: c, open: { route in
                selected = nil
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); path.append(route) }
            }, edit: { c in
                selected = nil
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); editing = c }
            }, changed: { Task { await load() } })
            .presentationDetents([.large])
            .presentationCornerRadius(32)
        }
    }

    // MARK: top

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commissions").font(.display(34)).foregroundStyle(Palette.text)
                    Text("Hire artists you love · pay safely by card").font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2)
                }
                Spacer(minLength: 0)
                Image(systemName: "creditcard.and.123").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.main)
                    .frame(width: 46, height: 46).background(Palette.surface.opacity(0.75), in: Circle())
            }
            HStack(spacing: 8) {
                heroStat("\(list.filter(\.isOpen).count)", "open shops")
                heroStat("\(buying.filter { $0.status.isActive }.count)", "your orders")
                heroStat("\(selling.filter { $0.status.isActive }.count)", "to make")
            }
            Button {
                if myListings.isEmpty { creating = true } else { withMotion(Motion.standard) { tab = .shop } }
            } label: {
                Label(myListings.isEmpty ? "Open your shop" : "Go to your shop", systemImage: "storefront.fill")
            }
            .buttonStyle(GradientButtonStyle(height: 46))
        }
        .pastelCard(radius: 26, padding: 18)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.jakarta(18, .heavy)).foregroundStyle(Palette.text)
                .contentTransition(.numericText())
            Text(label).font(.jakarta(10, .bold)).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rim(0.6), lineWidth: 1))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = tab == t
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = t } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.icon).font(.system(size: 14, weight: .bold))
                        Text(t.rawValue).font(.jakarta(13, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        if t != .explore && badge(t) > 0 {
                            Text("\(badge(t))").font(.jakarta(11, .heavy)).foregroundStyle(active ? Theme.main : .white)
                                .padding(.horizontal, 6).frame(height: 18)
                                .background(active ? Color.white : Theme.main, in: Capsule())
                        }
                    }
                    .foregroundStyle(active ? .white : Palette.text2)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background {
                        if active {
                            Capsule().fill(Theme.gradient).matchedGeometryEffect(id: "tab", in: tabPill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(BouncyStyle(scale: 0.95))
            }
        }
        .padding(5)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 8, y: 3)
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func badge(_ t: Tab) -> Int {
        switch t {
        case .explore: return 0
        case .orders: return buying.filter { $0.status == .accepted || $0.status == .delivered }.count
        case .shop: return selling.filter { [.requested, .paid, .inProgress].contains($0.status) }.count
        }
    }

    // MARK: explore

    @ViewBuilder
    private var explore: some View {
        SearchField(text: $query, placeholder: "Search styles, artists, tags…")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Chip(title: f.rawValue, icon: f == .all ? "square.grid.2x2.fill" : f == .open ? "circle.fill" : f == .budget ? "tag.fill" : "star.fill", active: filter == f) {
                        withMotion(Motion.standard) { filter = f }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        if loading && list.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 240, radius: 24) }
            }
        } else if shown.isEmpty {
            EmptyCard(icon: "storefront.fill", title: "No shops here yet", text: "Be the first artist to open a shop.", actionTitle: "Open your shop") { creating = true }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, c in
                    Button { selected = c } label: { ListingCard(commission: c) }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                        .stagger(appeared, min(i, 8) + 2)
                }
            }
        }
    }

    // MARK: my orders (buying)

    @ViewBuilder
    private var ordersTab: some View {
        let active = buying.filter { $0.status.isActive }
        let past = buying.filter { !$0.status.isActive }
        if buying.isEmpty && !loading {
            EmptyCard(icon: "bag.fill", title: "No orders yet", text: "Find an artist you love in Explore and send them a request.", actionTitle: "Explore shops") {
                withMotion(Motion.standard) { tab = .explore }
            }
        }
        if !active.isEmpty {
            sectionTitle("Going on", "sparkles")
            ForEach(active) { o in orderButton(o, buyer: true) }
        }
        if !past.isEmpty {
            sectionTitle("Past orders", "clock.fill")
            ForEach(past) { o in orderButton(o, buyer: true) }
        }
    }

    private func orderButton(_ o: CommissionOrder, buyer: Bool) -> some View {
        Button { path.append(.commissionOrder(o.id)) } label: { OrderRow(order: o, asBuyer: buyer) }
            .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private func sectionTitle(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
            .labelStyle(TintedIconLabel(tint: Theme.main))
            .padding(.top, 4)
    }

    // MARK: my shop (selling)

    @ViewBuilder
    private var shopTab: some View {
        if payoutsReady == false {
            SetUpPayoutsNotice()
            PayoutInfoCard { withMotion(Motion.standard) { payoutsReady = true } }
        }
        EarningsCard(orders: selling)
        let requests = selling.filter { $0.status == .requested }
        let working = selling.filter { [.accepted, .paid, .inProgress, .delivered, .refundRequested].contains($0.status) }
        if !requests.isEmpty {
            sectionTitle("New requests", "tray.full.fill")
            ForEach(requests) { o in orderButton(o, buyer: false) }
        }
        if !working.isEmpty {
            sectionTitle("Your work", "paintbrush.pointed.fill")
            ForEach(working) { o in orderButton(o, buyer: false) }
        }
        HStack {
            sectionTitle("Your listings", "storefront.fill")
            Spacer()
            Button { creating = true } label: { Label("New", systemImage: "plus") }
                .buttonStyle(GradientButtonStyle(height: 36, fullWidth: false))
        }
        if myListings.isEmpty {
            EmptyCard(icon: "storefront.fill", title: "Open your shop", text: "List what you draw, your prices and a few samples. Buyers pay by card and you get paid out.", compact: true)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(myListings) { c in
                    Button { selected = c } label: { ListingCard(commission: c) }
                        .buttonStyle(BouncyStyle(scale: 0.96))
                }
            }
        }
        if payoutsReady != false { PayoutInfoCard() }
        let done = selling.filter { $0.status == .completed }
        if !done.isEmpty {
            sectionTitle("Finished", "checkmark.seal.fill")
            ForEach(done.prefix(20)) { o in orderButton(o, buyer: false) }
        }
        if model.me?.isAdmin == true { AdminPayouts(orders: adminOrders, open: { path.append(.commissionOrder($0)) }, reload: { Task { await load() } }) }
    }

    // MARK: data

    private func load() async {
        defer { loading = false }
        async let listings = try? FS.query("Commission", orderBy: "created_date", limit: 200)
        async let bought = try? FS.query("CommissionOrder", [.equals("buyer_email", me)], limit: 200)
        async let sold = try? FS.query("CommissionOrder", [.equals("artist_email", me)], limit: 300)
        let newest: (CommissionOrder, CommissionOrder) -> Bool = { $0.updated > $1.updated }
        let listingDocs = await listings
        let boughtDocs = await bought
        let soldDocs = await sold
        withAnimation(Motion.pick(.smooth(duration: 0.4))) {
            if let listingDocs { list = listingDocs.map(Commission.init) }
            if let boughtDocs { buying = boughtDocs.map(CommissionOrder.init).sorted(by: newest) }
            if let soldDocs { selling = soldDocs.map(CommissionOrder.init).sorted(by: newest) }
        }
        payoutsReady = await Payouts.isSetUp(model.me?.id ?? "")
        if model.me?.isAdmin == true {
            async let completed = try? FS.query("CommissionOrder", [.equals("status", "completed")], limit: 300)
            async let refunds = try? FS.query("CommissionOrder", [.equals("status", "refund_requested")], limit: 100)
            adminOrders = ((await completed ?? []) + (await refunds ?? [])).map(CommissionOrder.init).sorted(by: newest)
        }
    }
}

// A shop listing in the grid.
struct ListingCard: View {
    let commission: Commission
    @Environment(AppModel.self) private var model

    var body: some View {
        let c = commission
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let first = c.samples.first {
                        RemoteImage(url: first)
                    } else {
                        Theme.pastel
                            .overlay(Image(systemName: "paintbrush.pointed.fill").font(.system(size: 34)).foregroundStyle(Theme.main.opacity(0.7)))
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                StatusPill(open: c.isOpen).padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if let price = c.fromPrice {
                    Text("from \(Money.format(price, c.currency))")
                        .font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 26)
                        .background(Palette.surface, in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(c.title).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Avatar(url: model.person(c.artistEmail)?.picture ?? c.artistPicture, name: model.name(c.artistEmail, c.artistName), size: 20)
                    Text(model.name(c.artistEmail, c.artistName)).font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let r = c.rating {
                        Label(String(format: "%.1f", r), systemImage: "star.fill").font(.jakarta(11, .heavy)).foregroundStyle(Palette.gold)
                    }
                    if c.ordersCompleted > 0 {
                        Text("\(c.ordersCompleted) sold").font(.jakarta(11, .bold)).foregroundStyle(Palette.muted)
                    } else if c.rating == nil {
                        Text("New shop").font(.jakarta(11, .bold)).foregroundStyle(Theme.main)
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sugarCard(radius: 24)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct StatusPill: View {
    let open: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(open ? Palette.success : Palette.muted).frame(width: 7, height: 7)
            Text(open ? "Open" : "Closed").font(.jakarta(11, .heavy)).foregroundStyle(open ? Palette.success : Palette.muted)
        }
        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 26)
        .background(Palette.surface, in: Capsule())
    }
}

struct OrderStatusBadge: View {
    let status: CommissionOrder.Status
    var body: some View {
        Label(status.label, systemImage: status.icon)
            .font(.jakarta(11, .heavy)).foregroundStyle(Color(hex: status.tint))
            .padding(.horizontal, 9).frame(height: 24)
            .background(Color(hex: status.tint).opacity(0.12), in: Capsule())
    }
}

// One order in a list: picture, title, the other person, price and what's next.
struct OrderRow: View {
    let order: CommissionOrder
    let asBuyer: Bool
    @Environment(AppModel.self) private var model

    private var next: String? {
        switch (order.status, asBuyer) {
        case (.requested, true): return "Waiting for the artist to accept"
        case (.requested, false): return "Accept or decline this request"
        case (.accepted, true): return "Pay to get started"
        case (.accepted, false): return "Waiting for payment"
        case (.paid, false), (.inProgress, false): return "Deliver when it's ready"
        case (.paid, true), (.inProgress, true): return "The artist is working on it"
        case (.delivered, true): return "Your art is here! Approve it"
        case (.delivered, false): return "Waiting for approval"
        default: return nil
        }
    }
    private var needsMe: Bool {
        asBuyer ? [.accepted, .delivered].contains(order.status) : [.requested, .paid, .inProgress].contains(order.status)
    }

    var body: some View {
        let other = asBuyer ? order.artistEmail : order.buyerEmail
        let otherName = model.name(other, asBuyer ? order.artistName : order.buyerName)
        HStack(spacing: 12) {
            Group {
                if !order.cover.isEmpty { RemoteImage(url: order.cover) } else { Theme.gradient }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.title.isEmpty ? "Commission" : order.title).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Money.format(order.price, order.currency)).font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
                }
                Text((asBuyer ? "by " : "for ") + otherName + (order.tier.isEmpty ? "" : " · \(order.tier)"))
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                HStack(spacing: 6) {
                    OrderStatusBadge(status: order.status)
                    if let next {
                        Text(next).font(.jakarta(11, .semibold)).foregroundStyle(needsMe ? Theme.main : Palette.muted).lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(needsMe ? Theme.main.opacity(0.45) : Palette.border, lineWidth: needsMe ? 1.5 : 1))
        .shadow(color: Palette.shadow, radius: 6, y: 2)
    }
}

// What you've earned as an artist.
struct EarningsCard: View {
    let orders: [CommissionOrder]

    var body: some View {
        let currency = orders.first(where: { $0.status.isPaid })?.currency ?? "usd"
        let pending = orders.filter { [.paid, .inProgress, .delivered].contains($0.status) }.reduce(0) { $0 + $1.earnings }
        let ready = orders.filter { $0.status == .completed && $0.payoutStatus != "paid_out" }.reduce(0) { $0 + $1.earnings }
        let paidOut = orders.filter { $0.status == .completed && $0.payoutStatus == "paid_out" }.reduce(0) { $0 + $1.earnings }
        VStack(alignment: .leading, spacing: 12) {
            Label("Your earnings", systemImage: "banknote.fill").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                .labelStyle(TintedIconLabel(tint: Palette.success))
            HStack(spacing: 8) {
                cell(Money.format(pending, currency), "In progress", 0x2F80E0)
                cell(Money.format(ready, currency), "To be paid", 0x17A673)
                cell(Money.format(paidOut, currency), "Paid out", 0x86707C)
            }
            Text("Buyers pay by card. When they approve your art, Sugerly pays you out (minus Sugerly's \(Int(SiteTheme.shared.commissionFee))% fee) to your payout details below.")
                .font(.jakarta(12)).foregroundStyle(Palette.muted)
        }
        .padding(16)
        .sugarCard(radius: 24)
    }

    private func cell(_ value: String, _ label: String, _ tint: UInt32) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.jakarta(16, .heavy)).foregroundStyle(Color(hex: tint)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.jakarta(11, .bold)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity).frame(height: 58)
        .background(Color(hex: tint).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// Where the artist wants their money (private: only them and admins).
// Artists need payout details before they can take paid orders, so
// Sugerly knows where to send their money.
enum Payouts {
    static func isSetUp(_ uid: String) async -> Bool {
        guard !uid.isEmpty, let doc = try? await FS.get("PayoutInfo", uid) else { return false }
        return doc.str("paypal_email").contains("@")
    }
}

struct PayoutInfoCard: View {
    var onSaved: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var name = ""
    @State private var saved = false
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Payout details", systemImage: "lock.fill").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                .labelStyle(TintedIconLabel(tint: Theme.main))
            Text("Where Sugerly sends your money. Only you and the Sugerly team can see this.").font(.jakarta(12)).foregroundStyle(Palette.muted)
            SugarField(placeholder: "PayPal email", text: $email)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            SugarField(placeholder: "Your full name", text: $name)
            Button { Task { await save() } } label: {
                if saving { ProgressView().tint(.white) } else { Label(saved ? "Saved" : "Save payout details", systemImage: saved ? "checkmark" : "tray.and.arrow.down.fill") }
            }
            .buttonStyle(GradientButtonStyle(height: 44))
            .disabled(saving || !email.contains("@"))
        }
        .padding(16)
        .sugarCard(radius: 24)
        .task { await load() }
        .onChange(of: email) { _, _ in saved = false }
        .onChange(of: name) { _, _ in saved = false }
    }

    private func load() async {
        guard let uid = model.me?.id, let doc = try? await FS.get("PayoutInfo", uid) else { return }
        email = doc.str("paypal_email")
        name = doc.str("full_name")
        saved = !email.isEmpty
    }

    private func save() async {
        guard let me = model.me else { return }
        saving = true
        defer { saving = false }
        let data: Doc = ["paypal_email": email.trimmingCharacters(in: .whitespaces).lowercased(), "full_name": name.trimmingCharacters(in: .whitespaces),
                         "email": me.email, "updated_date": FS.nowISO()]
        do {
            do { try await FS.update("PayoutInfo", me.id, data) } catch { try await FS.create("PayoutInfo", data, id: me.id) }
            saved = true
            model.showToast("Payout details saved", icon: "lock.fill")
            onSaved?()
        } catch {
            model.showToast(error.localizedDescription, error: true)
        }
    }
}

// "Set up payouts first": shown in My shop and on requests until the artist
// has saved where Sugerly should send their money.
struct SetUpPayoutsNotice: View {
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "banknote.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: [Palette.gold.opacity(0.75), Palette.gold], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up payouts first").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                Text("Add the PayPal email where Sugerly should send your money. You can accept paid requests once it's saved.")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button("Set up payouts", action: action)
                        .buttonStyle(OutlineButtonStyle())
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.warning.opacity(0.35), lineWidth: 1))
    }
}

// Admins: pay artists for approved work, and handle refund requests.
struct AdminPayouts: View {
    let orders: [CommissionOrder]
    var open: (String) -> Void
    var reload: () -> Void
    @Environment(AppModel.self) private var model
    @State private var payouts: [String: String] = [:]   // artist email → PayPal email
    @State private var working = false

    var body: some View {
        let owed = orders.filter { $0.status == .completed && $0.payoutStatus != "paid_out" }
        let refunds = orders.filter { $0.status == .refundRequested }
        let byArtist = Dictionary(grouping: owed, by: \.artistEmail)
        VStack(alignment: .leading, spacing: 12) {
            Label("Admin · payouts", systemImage: "shield.lefthalf.filled").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                .labelStyle(TintedIconLabel(tint: Theme.main))
            if byArtist.isEmpty && refunds.isEmpty {
                Text("Nothing to pay out or refund right now.").font(.jakarta(13)).foregroundStyle(Palette.muted)
            }
            ForEach(byArtist.keys.sorted(), id: \.self) { artist in
                let list = byArtist[artist] ?? []
                let total = list.reduce(0) { $0 + $1.earnings }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Avatar(url: model.person(artist)?.picture ?? "", name: model.name(artist, artist), size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name(artist, list.first?.artistName ?? artist)).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                            Text(payouts[artist].map { "PayPal: \($0)" } ?? "No payout details yet").font(.jakarta(12)).foregroundStyle(Palette.muted)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(Money.format(total, list.first?.currency ?? "usd")).font(.jakarta(15, .heavy)).foregroundStyle(Palette.success)
                    }
                    Button { Task { await markPaid(list) } } label: { Label("Mark \(list.count) as paid out", systemImage: "checkmark.circle.fill") }
                        .buttonStyle(OutlineButtonStyle(height: 38, fullWidth: true))
                        .disabled(working)
                }
                .padding(12)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            ForEach(refunds) { o in
                Button { open(o.id) } label: { OrderRow(order: o, asBuyer: false) }.buttonStyle(SoftPressStyle())
            }
        }
        .padding(16)
        .sugarCard(radius: 24)
        .task(id: orders.map(\.artistUid).joined()) { await loadPayouts(owed) }
    }

    private func loadPayouts(_ owed: [CommissionOrder]) async {
        var out: [String: String] = [:]
        for o in owed where out[o.artistEmail] == nil {
            let uid = o.artistUid.isEmpty ? (model.person(o.artistEmail)?.id ?? "") : o.artistUid
            guard !uid.isEmpty, let doc = try? await FS.get("PayoutInfo", uid) else { continue }
            let mail = doc.str("paypal_email")
            if !mail.isEmpty { out[o.artistEmail] = mail }
        }
        payouts = out
    }

    private func markPaid(_ list: [CommissionOrder]) async {
        working = true
        defer { working = false }
        let now = FS.nowISO()
        for o in list { try? await FS.update("CommissionOrder", o.id, ["payout_status": "paid_out", "payout_at": now, "updated_date": now]) }
        if let me = model.me, let first = list.first {
            // Tell the artist where the money went, so they know to check.
            let total = Money.format(list.reduce(0) { $0 + $1.earnings }, first.currency)
            let whereTo = payouts[first.artistEmail].map { " to your PayPal (\($0))" } ?? " by PayPal"
            Notify.send(to: first.artistEmail, from: me, type: "commission",
                        message: "Sugerly sent you \(total) for \(list.count) commission\(list.count == 1 ? "" : "s")\(whereTo). Check your PayPal account!",
                        link: "/Commissions")
        }
        model.showToast("Marked as paid out", icon: "banknote.fill")
        reload()
    }
}

// MARK: - A listing

struct CommissionDetail: View {
    @State var commission: Commission
    var open: (Route) -> Void
    var edit: (Commission) -> Void
    var changed: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var tierIndex = 0
    @State private var confirmDelete = false
    @State private var requesting = false

    private var owner: Bool { model.me?.email == commission.artistEmail || model.me?.isAdmin == true }
    private var tier: CommissionTier? { commission.tiers.indices.contains(tierIndex) ? commission.tiers[tierIndex] : commission.tiers.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery
                VStack(alignment: .leading, spacing: 8) {
                    Text(commission.title).font(.display(30)).foregroundStyle(Palette.text)
                    Button { dismiss(); open(.person(commission.artistEmail)) } label: {
                        HStack(spacing: 8) {
                            Avatar(url: model.person(commission.artistEmail)?.picture ?? commission.artistPicture, name: model.name(commission.artistEmail, commission.artistName), size: 32)
                            Text(model.name(commission.artistEmail, commission.artistName)).font(.jakarta(14, .bold)).foregroundStyle(Palette.text2)
                            if let r = commission.rating {
                                Label(String(format: "%.1f (%d)", r, commission.ratingCount), systemImage: "star.fill")
                                    .font(.jakarta(12, .heavy)).foregroundStyle(Palette.gold)
                            }
                            if commission.ordersCompleted > 0 {
                                Text("· \(commission.ordersCompleted) sold").font(.jakarta(12, .bold)).foregroundStyle(Palette.muted)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                        }
                    }
                    .buttonStyle(SoftPressStyle())
                }
                if !commission.description.isEmpty {
                    Text(commission.description).font(.jakarta(15)).foregroundStyle(Palette.text2)
                }
                if !commission.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(commission.tags, id: \.self) { t in
                            Text("#\(t)").font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
                                .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 10).frame(height: 28).background(Theme.soft, in: Capsule())
                        }
                    }
                }
                if !commission.tiers.isEmpty {
                    Text("PICK A SIZE").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                    VStack(spacing: 10) {
                        ForEach(Array(commission.tiers.enumerated()), id: \.offset) { i, t in
                            Button { withMotion(Motion.standard) { tierIndex = i } } label: { tierCard(t, picked: i == tierIndex) }
                                .buttonStyle(BouncyStyle(scale: 0.98))
                        }
                    }
                }
                actions
                Label("Pay safely by card through Stripe. The artist only gets paid once you approve your art.", systemImage: "lock.shield.fill")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted)
            }
            .padding(18)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .sheet(isPresented: $requesting) {
            if let tier {
                CommissionRequestSheet(commission: commission, tier: tier) { orderId in
                    requesting = false
                    dismiss()
                    open(.commissionOrder(orderId))
                }
                .presentationCornerRadius(30)
            }
        }
        .confirmationDialog("Delete this listing?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await FS.delete("Commission", commission.id)
                    model.showToast("Listing deleted", icon: "trash.fill")
                    changed()
                    dismiss()
                }
            }
        } message: { Text("Orders already placed stay as they are.") }
    }

    @ViewBuilder
    private var gallery: some View {
        if !commission.samples.isEmpty {
            TabView(selection: $index) {
                ForEach(commission.samples.indices, id: \.self) { i in
                    RemoteImage(url: commission.samples[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topLeading) { StatusPill(open: commission.isOpen).padding(12) }
        }
    }

    private func tierCard(_ t: CommissionTier, picked: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(picked ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.borderStrong))
            VStack(alignment: .leading, spacing: 4) {
                Text(t.name).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                if !t.description.isEmpty { Text(t.description).font(.jakarta(12)).foregroundStyle(Palette.muted).multilineTextAlignment(.leading) }
                if let days = t.days { Label("Ready in about \(days) day\(days == 1 ? "" : "s")", systemImage: "clock").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 8)
            Text(Money.format(t.price, commission.currency)).font(.display(22)).foregroundStyle(Theme.main)
        }
        .padding(14)
        .background(picked ? Theme.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(picked ? Theme.main.opacity(0.6) : Palette.border, lineWidth: picked ? 2 : 1))
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if model.me?.email != commission.artistEmail {
                if commission.isOpen, let tier {
                    Button { requesting = true } label: { Label("Request · \(Money.format(tier.price, commission.currency))", systemImage: "paperplane.fill") }
                        .buttonStyle(GradientButtonStyle(height: 52))
                } else {
                    Label("This shop is closed right now", systemImage: "lock.fill").font(.jakarta(14, .bold)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Palette.surface2, in: Capsule())
                }
                Button {
                    let me = model.me?.email ?? ""
                    let convo = Conversation(id: Social.dmId(me, commission.artistEmail), members: [me, commission.artistEmail], isGroup: false, groupName: "", last: nil, unread: 0)
                    dismiss()
                    open(.chat(convo))
                } label: { Label("Ask the artist a question", systemImage: "bubble.left.and.bubble.right.fill") }
                    .buttonStyle(OutlineButtonStyle(height: 48, fullWidth: true))
            }
            if owner {
                HStack(spacing: 10) {
                    Button {
                        let next = !commission.isOpen
                        Task {
                            do {
                                if next { try await ArtistReview.require(model.me?.id ?? "") }
                                try await FS.update("Commission", commission.id, ["is_open": next, "updated_date": FS.nowISO()])
                                commission.isOpen = next
                                model.showToast(next ? "Your shop is open" : "Your shop is closed", icon: "storefront.fill")
                                changed()
                            } catch { model.showToast(error.localizedDescription, error: true) }
                        }
                    } label: { Label(commission.isOpen ? "Close shop" : "Open shop", systemImage: commission.isOpen ? "lock.fill" : "lock.open.fill") }
                        .buttonStyle(GradientButtonStyle(height: 46))
                    Button { edit(commission) } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete listing", systemImage: "trash").foregroundStyle(Palette.danger) }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            }
        }
    }
}

// MARK: - Sending a request

struct CommissionRequestSheet: View {
    let commission: Commission
    let tier: CommissionTier
    var done: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var brief = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var refs: [UIImage] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "Your request", actionTitle: "Send", busy: busy, canPost: brief.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10, onClose: { dismiss() }, onPost: { Task { await send() } }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Group {
                        if let s = commission.samples.first { RemoteImage(url: s) } else { Theme.gradient }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commission.title).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("\(tier.name) · \(Money.format(tier.price, commission.currency))").font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("WHAT WOULD YOU LIKE?").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                SugarField(placeholder: "Describe it: who or what, pose, colours, mood, where you'll use it…", text: $brief, lines: 4...10)
                Text("REFERENCES (OPTIONAL)").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(refs.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { withMotion { refs.removeAll { $0 === image } } } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                        }
                        if refs.count < 4 {
                            PhotosPicker(selection: $items, maxSelectionCount: 4 - refs.count, matching: .images) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.main)
                                    .frame(width: 76, height: 76)
                                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.main.opacity(0.18), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                VStack(alignment: .leading, spacing: 6) {
                    step("1", "The artist accepts (they can adjust the price)")
                    step("2", "You pay by card, safely through Stripe")
                    step("3", "They make your art and deliver it here")
                    step("4", "You approve it, and then the artist gets paid")
                }
                .padding(14)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
        .onChange(of: items) { _, list in
            Task {
                for item in list {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), refs.count < 4 {
                        withMotion(Motion.standard) { refs.append(image) }
                    }
                }
                items = []
            }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.jakarta(12, .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Theme.gradient, in: Circle())
            Text(text).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2)
        }
    }

    private func send() async {
        guard let me = model.me else { return }
        guard await TextGuard.clear([brief], kind: .post, model: model) else { return }
        busy = true
        defer { busy = false }
        do {
            let artist: UserProfile?
            if let cached = model.person(commission.artistEmail) { artist = cached }
            else { artist = try await FS.query("User", [.equals("email", commission.artistEmail)], limit: 1).first.map(UserProfile.init) }
            guard let artist else { throw APIError(message: "This artist’s profile is unavailable.") }
            try await ArtistReview.require(artist.id)
            var urls: [String] = []
            for image in refs {
                if let jpeg = ImageTools.jpeg(image, maxSide: 1600) {
                    urls.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                }
            }
            let created = try await FS.create("CommissionOrder", [
                "commission_id": commission.id, "commission_title": commission.title, "tier_name": tier.name,
                "cover_url": commission.samples.first ?? "", "price": tier.price, "currency": commission.currency,
                "brief": brief.trimmingCharacters(in: .whitespacesAndNewlines), "references": urls,
                "buyer_email": me.email, "buyer_name": me.displayName,
                "artist_email": commission.artistEmail, "artist_name": artist.displayName, "artist_uid": artist.id,
                "status": "requested",
            ])
            let id = created.str("id")
            Notify.send(to: commission.artistEmail, from: me, type: "commission", message: "\(me.displayName) sent you a commission request for \"\(commission.title)\"", link: "/Commissions?order=\(id)")
            model.showToast("Request sent!", icon: "paperplane.fill")
            done(id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - One order

struct CommissionOrderView: View {
    let orderId: String
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var order: CommissionOrder?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var checkout: CheckoutPage?
    @State private var canPayByCard: Bool?
    @State private var quote = ""
    @State private var currency = "usd"
    @State private var quoteNote = ""
    @State private var delivering = false
    @State private var approving = false
    @State private var confirm: Confirm?
    @State private var reason = ""
    @State private var viewing: String?
    @State private var payoutsReady: Bool?
    @State private var settingUpPayouts = false

    enum Confirm: String, Identifiable { case decline, cancel, refund; var id: String { rawValue } }

    private var me: String { model.me?.email ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let order {
                    header(order)
                    tracker(order)
                    people(order)
                    briefCard(order)
                    if !order.deliveryURLs.isEmpty || !order.deliveryNote.isEmpty { deliveryCard(order) }
                    if order.status == .completed && (order.rating > 0 || !order.review.isEmpty) { reviewCard(order) }
                    actionPanel(order)
                    if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
                    Label(footnote(order), systemImage: "lock.shield.fill").font(.jakarta(12)).foregroundStyle(Palette.muted)
                } else if loading {
                    SkeletonBlock(height: 180, radius: 26)
                    SkeletonBlock(height: 90, radius: 22)
                    SkeletonBlock(height: 160, radius: 22)
                } else {
                    EmptyCard(icon: "bag.fill", title: "Order not found", text: "It may have been removed.")
                }
            }
            .padding(16)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .task { canPayByCard = await Payments.cardCheckoutAllowed() }
        .task { payoutsReady = await Payouts.isSetUp(model.me?.id ?? "") }
        .sheet(isPresented: $settingUpPayouts) {
            NavigationStack {
                ScrollView {
                    PayoutInfoCard {
                        payoutsReady = true
                        settingUpPayouts = false
                    }
                    .padding(16)
                }
                .sugarBackground()
                .navigationTitle("Payouts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { settingUpPayouts = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        // Keeps up with the other side while you're looking at it.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                await load()
            }
        }
        .sheet(item: $checkout, onDismiss: { Task { await confirmPayment() } }) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .sheet(isPresented: $delivering) {
            if let order { DeliverSheet(order: order) { await load() } }
        }
        .sheet(isPresented: $approving) {
            if let order { ApproveSheet(order: order) { await load() } }
        }
        .sheet(item: Binding(get: { viewing.map { ViewedImage(url: $0) } }, set: { viewing = $0?.url })) { item in
            ZoomableRemoteImage(url: item.url).presentationBackground(.black)
        }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            TextField(confirm == .refund ? "What went wrong?" : "Reason (optional)", text: $reason)
            Button("Back", role: .cancel) { reason = "" }
            Button(confirm == .refund ? "Ask for refund" : confirm == .decline ? "Decline" : "Cancel order", role: .destructive) {
                let kind = confirm
                Task { await finish(kind) }
            }
        } message: {
            Text(confirm == .refund ? "The Sugerly team will look at it and refund you if it's fair." : "This can't be undone.")
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .decline: return "Decline this request?"
        case .cancel: return "Cancel this order?"
        case .refund: return "Ask for a refund?"
        case nil: return ""
        }
    }

    // MARK: parts

    private func header(_ o: CommissionOrder) -> some View {
        HStack(spacing: 14) {
            Group {
                if !o.cover.isEmpty { RemoteImage(url: o.cover) } else { Theme.gradient }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(o.title.isEmpty ? "Commission" : o.title).font(.display(22)).foregroundStyle(Palette.text).lineLimit(2)
                if !o.tier.isEmpty { Text(o.tier).font(.jakarta(13, .bold)).foregroundStyle(Palette.muted) }
                HStack(spacing: 8) {
                    Text(Money.format(o.price, o.currency)).font(.display(22)).foregroundStyle(Theme.main)
                    OrderStatusBadge(status: o.status)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .sugarCard(radius: 26)
    }

    // Requested → Accepted → Paid → Working → Delivered → Done.
    @ViewBuilder
    private func tracker(_ o: CommissionOrder) -> some View {
        let steps: [(String, String)] = [("Sent", "paperplane.fill"), ("Accepted", "hand.thumbsup.fill"), ("Paid", "creditcard.fill"),
                                         ("Working", "paintbrush.pointed.fill"), ("Delivered", "shippingbox.fill"), ("Done", "star.fill")]
        if o.status.step < 0 {
            Label(o.status == .refunded ? "This order was refunded." : o.status == .declined ? "The artist declined this request." : "This order was cancelled.", systemImage: o.status.icon)
                .font(.jakarta(14, .bold)).foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    let reached = i <= o.status.step
                    VStack(spacing: 5) {
                        Image(systemName: s.1).font(.system(size: 12, weight: .bold))
                            .foregroundStyle(reached ? .white : Palette.muted)
                            .frame(width: 32, height: 32)
                            .background {
                                if reached { Circle().fill(Theme.gradient) } else { Circle().fill(Palette.surface2) }
                            }
                            .overlay(Circle().strokeBorder(i == o.status.step ? Theme.main.opacity(0.4) : .clear, lineWidth: 3).padding(-4))
                        Text(s.0).font(.jakarta(10, .bold)).foregroundStyle(reached ? Palette.text : Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .sugarCard(radius: 22)
        }
    }

    private func people(_ o: CommissionOrder) -> some View {
        let other = o.buyerEmail == me ? o.artistEmail : o.buyerEmail
        return HStack(spacing: 12) {
            personChip(o.buyerEmail, o.buyerName, "Buyer")
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
            personChip(o.artistEmail, o.artistName, "Artist")
            Spacer(minLength: 0)
            Button {
                let convo = Conversation(id: Social.dmId(me, other), members: [me, other], isGroup: false, groupName: "", last: nil, unread: 0)
                path.append(.chat(convo))
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Theme.gradient, in: Circle())
            }
            .buttonStyle(BouncyStyle())
            .accessibilityLabel("Message")
        }
        .padding(12)
        .sugarCard(radius: 22)
    }

    private func personChip(_ email: String, _ fallback: String, _ role: String) -> some View {
        Button { path.append(.person(email)) } label: {
            HStack(spacing: 8) {
                Avatar(url: model.person(email)?.picture ?? "", name: model.name(email, fallback), size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(email == me ? "You" : model.name(email, fallback)).font(.jakarta(13, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(role).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                }
            }
        }
        .buttonStyle(SoftPressStyle())
    }

    private func briefCard(_ o: CommissionOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The request", systemImage: "text.quote").font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                .labelStyle(TintedIconLabel(tint: Theme.main))
            Text(o.brief).font(.jakarta(15)).foregroundStyle(Palette.text2).textSelection(.enabled)
            if !o.references.isEmpty { imageStrip(o.references) }
            if !o.quoteNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From the artist").font(.jakarta(12, .heavy)).foregroundStyle(Theme.main)
                    Text(o.quoteNote).font(.jakarta(14)).foregroundStyle(Palette.text2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 24)
    }

    private func deliveryCard(_ o: CommissionOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your art", systemImage: "shippingbox.fill").font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                .labelStyle(TintedIconLabel(tint: Theme.main))
            if !o.deliveryURLs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(o.deliveryURLs, id: \.self) { url in
                        Button { viewing = url } label: {
                            RemoteImage(url: url).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.97))
                    }
                }
            }
            if !o.deliveryNote.isEmpty { Text(o.deliveryNote).font(.jakarta(14)).foregroundStyle(Palette.text2) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 24)
    }

    private func reviewCard(_ o: CommissionOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= o.rating ? "star.fill" : "star").foregroundStyle(Palette.gold)
                }
            }
            .font(.system(size: 16, weight: .bold))
            if !o.review.isEmpty { Text("“\(o.review)”").font(.jakarta(14)).foregroundStyle(Palette.text2) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sugarCard(radius: 24)
    }

    private func imageStrip(_ urls: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(urls, id: \.self) { url in
                    Button { viewing = url } label: {
                        RemoteImage(url: url).frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyStyle(scale: 0.95))
                }
            }
        }
    }

    // What you can do next, depending on who you are and where the order is.
    @ViewBuilder
    private func actionPanel(_ o: CommissionOrder) -> some View {
        let isBuyer = o.buyerEmail == me
        let isArtist = o.artistEmail == me
        VStack(alignment: .leading, spacing: 10) {
            switch o.status {
            case .requested where isArtist:
                Text("Set your price").font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    Menu {
                        ForEach(Money.currencies, id: \.self) { c in Button(c.uppercased()) { currency = c } }
                    } label: {
                        HStack(spacing: 4) { Text(currency.uppercased()); Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
                            .font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
                            .padding(.horizontal, 12).frame(height: 48)
                            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    SugarField(placeholder: "Price", text: $quote).keyboardType(.decimalPad)
                }
                SugarField(placeholder: "A note for the buyer (optional): what's included, when it'll be ready…", text: $quoteNote, lines: 2...5)
                if payoutsReady == false {
                    SetUpPayoutsNotice(action: { settingUpPayouts = true })
                }
                Button { Task { await accept(o) } } label: { Label("Accept request", systemImage: "hand.thumbsup.fill") }
                    .buttonStyle(GradientButtonStyle(height: 50))
                    .disabled(busy || payoutsReady != true || (Double(quote.replacingOccurrences(of: ",", with: ".")) ?? 0) < 1)
                Button { confirm = .decline } label: { Label("Decline", systemImage: "xmark") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .requested where isBuyer:
                infoLine("The artist will look at your request soon.", "hourglass")
                Button { confirm = .cancel } label: { Label("Cancel request", systemImage: "xmark") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .accepted where isBuyer:
                if canPayByCard == true {
                    Button { Task { await pay(o) } } label: {
                        if busy { ProgressView().tint(.white) } else { Label("Pay \(Money.format(o.price, o.currency)) by card", systemImage: "creditcard.fill") }
                    }
                    .buttonStyle(GradientButtonStyle(height: 54))
                    .disabled(busy)
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Card, Apple Pay and more · secured by Stripe")
                    }
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                } else if canPayByCard == false {
                    infoLine("Paying for commissions isn't available in the iOS app in your region yet.", "creditcard")
                }
                Button { confirm = .cancel } label: { Label("Cancel order", systemImage: "xmark") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .accepted where isArtist:
                infoLine("Waiting for the buyer to pay. You'll get a notification.", "creditcard")
                Button { confirm = .cancel } label: { Label("Cancel order", systemImage: "xmark") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .paid where isArtist:
                Button { Task { await setStatus(o, "in_progress", note: "started working on \"\(o.title)\"") } } label: { Label("Start working", systemImage: "paintbrush.pointed.fill") }
                    .buttonStyle(GradientButtonStyle(height: 50))
                    .disabled(busy)
                Button { delivering = true } label: { Label("Deliver the art", systemImage: "shippingbox.fill") }
                    .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
            case .inProgress where isArtist:
                Button { delivering = true } label: { Label("Deliver the art", systemImage: "shippingbox.fill") }
                    .buttonStyle(GradientButtonStyle(height: 50))
            case .paid where isBuyer, .inProgress where isBuyer:
                infoLine("Paid! The artist is making your art.", "paintbrush.pointed")
                Button { confirm = .refund } label: { Label("Something wrong? Ask for a refund", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .delivered where isBuyer:
                Button { approving = true } label: { Label("Approve and review", systemImage: "star.fill") }
                    .buttonStyle(GradientButtonStyle(height: 52))
                Button { confirm = .refund } label: { Label("Not right? Ask for a refund", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .delivered where isArtist:
                infoLine("Delivered! Waiting for the buyer to approve.", "checkmark.circle")
                Button { delivering = true } label: { Label("Send a new version", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
            case .completed where isArtist:
                infoLine(o.payoutStatus == "paid_out" ? "Sugerly sent you \(Money.format(o.earnings, o.currency)) by PayPal. Check your PayPal account." : "Approved! Sugerly will send you \(Money.format(o.earnings, o.currency)) by PayPal, to the email in My shop → Payout details.", "banknote")
            case .refundRequested:
                infoLine("A refund was asked for. The Sugerly team will sort it out.", "arrow.uturn.backward")
            default:
                EmptyView()
            }
            if model.me?.isAdmin == true && [.refundRequested, .paid, .inProgress, .delivered].contains(o.status) {
                Button { Task { await refund(o) } } label: { Label("Admin: refund the buyer", systemImage: "arrow.uturn.backward.circle.fill") }
                    .buttonStyle(OutlineButtonStyle(height: 44, fullWidth: true))
                    .disabled(busy)
            }
        }
        .onAppear {
            quote = o.price.rounded() == o.price ? String(Int(o.price)) : String(o.price)
            currency = o.currency
        }
    }

    private func infoLine(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func footnote(_ o: CommissionOrder) -> String {
        if let fee = o.feePercent, o.status.isPaid {
            return "Paid by card through Stripe. Sugerly keeps \(Int(fee))% to run the app; the artist gets the rest once you approve."
        }
        return "Payments go through Stripe. The artist only gets paid once the buyer approves the art."
    }

    // MARK: actions

    private func load() async {
        defer { loading = false }
        guard let doc = try? await FS.get("CommissionOrder", orderId) else { return }
        let fresh = CommissionOrder(doc)
        if fresh != order { withMotion(Motion.standard) { order = fresh } }
    }

    private func notifyOther(_ o: CommissionOrder, _ message: String) {
        guard let meProfile = model.me else { return }
        let other = o.buyerEmail == me ? o.artistEmail : o.buyerEmail
        Notify.send(to: other, from: meProfile, type: "commission", message: message, link: o.link)
    }

    private func update(_ o: CommissionOrder, _ fields: Doc) async -> Bool {
        busy = true
        error = nil
        defer { busy = false }
        var data = fields
        data["updated_date"] = FS.nowISO()
        do {
            try await FS.update("CommissionOrder", o.id, data)
            await load()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func accept(_ o: CommissionOrder) async {
        guard let price = Double(quote.replacingOccurrences(of: ",", with: ".")), price >= 1 else { error = "Enter a price of at least 1."; return }
        if !quoteNote.isEmpty { guard await TextGuard.clear([quoteNote], kind: .message, model: model) else { return } }
        if await update(o, ["status": "accepted", "price": (price * 100).rounded() / 100, "currency": currency, "quote_note": quoteNote.trimmingCharacters(in: .whitespacesAndNewlines)]) {
            notifyOther(o, "\(model.me?.displayName ?? "The artist") accepted your commission \"\(o.title)\" for \(Money.format(price, currency)). Pay to get started!")
            model.showToast("Accepted!", icon: "hand.thumbsup.fill")
        }
    }

    private func setStatus(_ o: CommissionOrder, _ status: String, note: String) async {
        if await update(o, ["status": status]) {
            notifyOther(o, "\(model.me?.displayName ?? "Someone") \(note)")
        }
    }

    private func finish(_ kind: Confirm?) async {
        guard let o = order, let kind else { return }
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        reason = ""
        confirm = nil
        switch kind {
        case .decline:
            if await update(o, ["status": "declined"]) { notifyOther(o, "\(model.me?.displayName ?? "The artist") declined your commission request \"\(o.title)\"") }
        case .cancel:
            if await update(o, ["status": "cancelled", "cancel_reason": text]) { notifyOther(o, "\(model.me?.displayName ?? "Someone") cancelled the commission \"\(o.title)\"") }
        case .refund:
            if await update(o, ["status": "refund_requested", "refund_reason": text]) {
                notifyOther(o, "\(model.me?.displayName ?? "The buyer") asked for a refund on \"\(o.title)\"")
                model.showToast("Refund asked. The team will look at it.", icon: "arrow.uturn.backward")
            }
        }
    }

    private func pay(_ o: CommissionOrder) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await Payments.call("commission-checkout", ["orderId": o.id])
            guard let link = result["url"] as? String, let url = URL(string: link) else { throw APIError(message: "Couldn't open the payment page.") }
            checkout = CheckoutPage(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Back from the payment page: ask the server whether it went through.
    private func confirmPayment() async {
        guard let o = order else { return }
        for attempt in 0..<3 {
            if let result = try? await Payments.call("commission-confirm", ["orderId": o.id]), (result["status"] as? String) == "paid" {
                await load()
                model.showToast("Payment done! The artist has been told.", icon: "checkmark.seal.fill")
                return
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1) * 1.5))
        }
        await load()
    }

    private func refund(_ o: CommissionOrder) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await Payments.call("commission-refund", ["orderId": o.id])
            await load()
            model.showToast("Refunded", icon: "arrow.uturn.backward.circle.fill")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// The Stripe page to show.
struct CheckoutPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ViewedImage: Identifiable {
    let url: String
    var id: String { url }
}

// A picture you can pinch to zoom.
struct ZoomableRemoteImage: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteImage(url: url, contentMode: .fit)
                .scaleEffect(scale)
                .gesture(MagnifyGesture()
                    .onChanged { v in scale = min(5, max(1, base * v.magnification)) }
                    .onEnded { _ in base = scale; if scale < 1.05 { withMotion(Motion.standard) { scale = 1; base = 1 } } })
                .onTapGesture(count: 2) { withMotion(Motion.standard) { scale = scale > 1 ? 1 : 2.5; base = scale } }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.white.opacity(0.2), in: Circle())
            }
            .padding(16)
        }
    }
}

// Stripe's payment page inside the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.main)
        controller.dismissButtonStyle = .close
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// The artist sends the finished pictures.
struct DeliverSheet: View {
    let order: CommissionOrder
    var done: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "Deliver", actionTitle: "Deliver", busy: busy, canPost: !images.isEmpty, onClose: { dismiss() }, onPost: { Task { await deliver() } }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("THE FINISHED ART").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 110).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { withMotion { images.removeAll { $0 === image } } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .padding(4)
                            }
                    }
                    if images.count < 8 {
                        PhotosPicker(selection: $items, maxSelectionCount: 8 - images.count, matching: .images) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.main)
                                .frame(height: 110).frame(maxWidth: .infinity)
                                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.main.opacity(0.18), lineWidth: 1))
                        }
                    }
                }
                SugarField(placeholder: "A note for the buyer (optional)", text: $note, lines: 2...6)
                Label("Pictures are sent in high quality. The buyer approves them, then you get paid.", systemImage: "info.circle")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted)
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
        .onChange(of: items) { _, list in
            Task {
                for item in list {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), images.count < 8 {
                        withMotion(Motion.standard) { images.append(image) }
                    }
                }
                items = []
            }
        }
    }

    private func deliver() async {
        if !note.isEmpty { guard await TextGuard.clear([note], kind: .message, model: model) else { return } }
        busy = true
        defer { busy = false }
        do {
            var urls: [String] = []
            for image in images {
                if let jpeg = ImageTools.jpeg(image, maxSide: 3000, quality: 0.92) {
                    urls.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                }
            }
            let now = FS.nowISO()
            try await FS.update("CommissionOrder", order.id, ["status": "delivered", "delivery_urls": urls, "delivery_note": note.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              "delivered_at": now, "updated_date": now])
            if let me = model.me {
                Notify.send(to: order.buyerEmail, from: me, type: "commission", message: "\(me.displayName) delivered your commission \"\(order.title)\"! Take a look.", link: order.link)
            }
            model.showToast("Delivered!", icon: "shippingbox.fill")
            await done()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// The buyer approves the art and leaves a review.
struct ApproveSheet: View {
    let order: CommissionOrder
    var done: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 5
    @State private var review = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "Approve", actionTitle: "Approve", busy: busy, canPost: rating > 0, onClose: { dismiss() }, onPost: { Task { await approve() } }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("How did \(model.name(order.artistEmail, order.artistName)) do?").font(.display(24)).foregroundStyle(Palette.text)
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { i in
                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { rating = i } } label: {
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Palette.gold)
                                .scaleEffect(i == rating ? 1.12 : 1)
                        }
                        .buttonStyle(SoftPressStyle())
                        .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    }
                }
                .sensoryFeedback(.selection, trigger: rating)
                SugarField(placeholder: "Say something nice about your art (optional)", text: $review, lines: 3...6)
                Label("Approving tells Sugerly to pay the artist. Only approve when you're happy.", systemImage: "info.circle")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted)
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
    }

    private func approve() async {
        if !review.isEmpty { guard await TextGuard.clear([review], kind: .comment, model: model) else { return } }
        busy = true
        defer { busy = false }
        do {
            let now = FS.nowISO()
            try await FS.update("CommissionOrder", order.id, ["status": "completed", "rating": rating, "review": review.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              "completed_at": now, "updated_date": now])
            // Counts the review and the sale on the artist's shop (best effort).
            _ = try? await Payments.call("commission-review", ["orderId": order.id])
            model.showToast("Approved! Thank you", icon: "star.fill")
            await done()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Opening or editing a shop listing

struct TierDraft: Identifiable {
    var id = UUID()
    var name = ""
    var price = ""
    var days = ""
    var info = ""
}

struct NewCommissionView: View {
    let existing: Commission?
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var tags = ""
    @State private var currency = "usd"
    @State private var isOpen = true
    @State private var items: [PhotosPickerItem] = []
    @State private var oldSamples: [String] = []
    @State private var samples: [UIImage] = []
    @State private var tiers: [TierDraft] = [TierDraft(name: "Sketch"), TierDraft(name: "Full colour")]
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var focusedTierField: String?

    init(existing: Commission?, initialSamples: [UIImage] = [], onDone: @escaping () async -> Void) {
        self.existing = existing
        self.onDone = onDone
        _samples = State(initialValue: initialSamples)
    }

    private var sampleCount: Int { oldSamples.count + samples.count }
    private var validTiers: [TierDraft] {
        tiers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && (Double($0.price.replacingOccurrences(of: ",", with: ".")) ?? 0) >= 1 }
    }

    var body: some View {
        ComposerScaffold(title: existing == nil ? "Open your shop" : "Edit listing", actionTitle: existing == nil ? "Publish" : "Save", busy: busy,
                         canPost: !title.trimmingCharacters(in: .whitespaces).isEmpty && !validTiers.isEmpty,
                         onClose: { dismiss() }, onPost: { Task { await publish() } }) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Artist verification is required to publish or open a shop.", systemImage: "checkmark.seal.fill")
                    .font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2)
                SugarField(placeholder: "Title — e.g. Cute pet portraits", text: $title)
                SugarField(placeholder: "Your style, what's included, how you work…", text: $about, lines: 3...8)
                Text("SAMPLES").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(oldSamples, id: \.self) { url in
                            RemoteImage(url: url).frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(alignment: .topTrailing) { removeButton { oldSamples.removeAll { $0 == url } } }
                        }
                        ForEach(Array(samples.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(alignment: .topTrailing) { removeButton { samples.removeAll { $0 === image } } }
                        }
                        if sampleCount < 6 {
                            PhotosPicker(selection: $items, maxSelectionCount: 6 - sampleCount, matching: .images) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.main)
                                    .frame(width: 84, height: 84)
                                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.main.opacity(0.18), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                HStack {
                    Text("PRICES").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                    Spacer()
                    Menu {
                        ForEach(Money.currencies, id: \.self) { c in Button(c.uppercased()) { currency = c } }
                    } label: {
                        HStack(spacing: 4) { Text(currency.uppercased()); Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
                            .font(.jakarta(13, .heavy)).foregroundStyle(Theme.main)
                            .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 12).frame(height: 32)
                            .background(Theme.soft, in: Capsule())
                    }
                }
                ForEach(tiers) { tier in
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Size name (e.g. Headshot)", text: tierField(tier, \.name)).focused($focusedTierField, equals: "\(tier.id)-name").font(.jakarta(14, .semibold))
                            TextField("Price", text: tierField(tier, \.price)).focused($focusedTierField, equals: "\(tier.id)-price").keyboardType(.decimalPad).font(.jakarta(14, .bold)).multilineTextAlignment(.trailing).frame(width: 76)
                            if tiers.count > 1 {
                                Button {
                                    if focusedTierField?.hasPrefix(tier.id.uuidString) == true { focusedTierField = nil }
                                    tiers.removeAll { $0.id == tier.id }
                                } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Palette.muted) }
                                    .buttonStyle(SoftPressStyle())
                                    .accessibilityLabel("Remove size")
                                    .accessibilityIdentifier("commission-remove-tier-\(tier.id)")
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("What's included (optional)", text: tierField(tier, \.info)).focused($focusedTierField, equals: "\(tier.id)-info").font(.jakarta(13))
                            TextField("Days", text: tierField(tier, \.days)).focused($focusedTierField, equals: "\(tier.id)-days").keyboardType(.numberPad).font(.jakarta(13)).multilineTextAlignment(.trailing).frame(width: 56)
                        }
                    }
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                }
                if tiers.count < 5 {
                    Button { withMotion(Motion.standard) { tiers.append(TierDraft()) } } label: { Label("Add a size", systemImage: "plus") }
                        .font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                }
                SugarField(placeholder: "Tags: portrait, anime, pets", text: $tags)
                Toggle(isOn: $isOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open for orders").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                        Text("Close it any time you're busy.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                    }
                }
                .tint(Theme.main)
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Label("Buyers pay by card through Stripe. You get paid out after they approve your art, minus Sugerly's \(Int(SiteTheme.shared.commissionFee))% fee. Add your payout details in My shop.", systemImage: "banknote")
                    .font(.jakarta(12)).foregroundStyle(Palette.muted)
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
        .onAppear(perform: fill)
        .onChange(of: items) { _, list in
            Task {
                for item in list {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), sampleCount < 6 {
                        withMotion(Motion.standard) { samples.append(image) }
                    }
                }
                items = []
            }
        }
    }

    // SwiftUI may finish a text-field read/write after its row was deleted.
    // Resolve the stable ID every time; never retain an array subscript.
    private func tierField(_ snapshot: TierDraft, _ keyPath: WritableKeyPath<TierDraft, String>) -> Binding<String> {
        Binding(get: {
            tiers.first(where: { $0.id == snapshot.id })?[keyPath: keyPath] ?? snapshot[keyPath: keyPath]
        }, set: { value in
            guard let index = tiers.firstIndex(where: { $0.id == snapshot.id }) else { return }
            tiers[index][keyPath: keyPath] = value
        })
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button { withMotion { action() } } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.5))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .offset(x: 6, y: -6)
        .accessibilityLabel("Remove sample")
    }

    private func fill() {
        guard !loaded else { return }
        loaded = true
        guard let c = existing else { return }
        title = c.title
        about = c.description
        tags = c.tags.joined(separator: ", ")
        currency = c.currency
        isOpen = c.isOpen
        oldSamples = c.samples
        if !c.tiers.isEmpty {
            tiers = c.tiers.map { t in
                TierDraft(name: t.name, price: t.price.rounded() == t.price ? String(Int(t.price)) : String(t.price), days: t.days.map(String.init) ?? "", info: t.description)
            }
        }
    }

    private func publish() async {
        guard let me = model.me else { return }
        if Moderation.hasLink(title + " " + about) && !me.isAdmin { error = "Links aren't allowed here."; return }
        guard await TextGuard.clear([title, about] + tiers.map { "\($0.name) \($0.info)" }, kind: .caption, model: model) else { return }
        busy = true
        defer { busy = false }
        do {
            if existing == nil || isOpen { try await ArtistReview.require(me.id) }
            var urls = oldSamples
            for image in samples {
                if let jpeg = ImageTools.jpeg(image, maxSide: 1600) {
                    urls.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                }
            }
            let tierDocs: [[String: Any]] = validTiers.map { t in
                var doc: [String: Any] = ["name": t.name.trimmingCharacters(in: .whitespaces), "price": Double(t.price.replacingOccurrences(of: ",", with: ".")) ?? 0,
                                          "description": t.info.trimmingCharacters(in: .whitespaces)]
                doc["delivery_days"] = Int(t.days).map { $0 as Any } ?? NSNull()
                return doc
            }
            var data: Doc = [
                "title": title.trimmingCharacters(in: .whitespaces), "description": about.trimmingCharacters(in: .whitespacesAndNewlines),
                "is_open": isOpen, "currency": currency,
                "tags": tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }.prefix(6).map { $0 },
                "tiers": tierDocs, "samples": urls,
                "artist_display_name": me.displayName, "artist_profile_picture": me.picture,
            ]
            if let existing {
                data["updated_date"] = FS.nowISO()
                try await FS.update("Commission", existing.id, data)
                model.showToast("Listing saved", icon: "storefront.fill")
            } else {
                data["artist_email"] = me.email
                _ = try await FS.create("Commission", data)
                model.showToast("Your shop is open!", icon: "storefront.fill")
            }
            await onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
