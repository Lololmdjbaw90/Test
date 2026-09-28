import SwiftUI
import UIKit
import PhotosUI

// MARK: - Commissions (the website's Commissions page)

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
    var paypal: String
    var tags: [String]
    var tiers: [CommissionTier]
    var samples: [String]
    var artistEmail: String
    var artistName: String
    var artistPicture: String
    var created: String

    var fromPrice: Double? { tiers.map(\.price).min() }

    init(_ d: Doc) {
        id = d.str("id")
        title = d.str("title")
        description = d.str("description")
        isOpen = (d["is_open"] as? Bool) ?? (d.str("status") == "open")
        paypal = d.str("paypal_link")
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
    }
}

struct CommissionsView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var list: [Commission] = []
    @State private var loading = true
    @State private var query = ""
    @State private var openOnly = false
    @State private var creating = false
    @State private var selected: Commission?
    @State private var appeared = false

    private var shown: [Commission] {
        list.filter { c in
            (!openOnly || c.isOpen) &&
            (query.isEmpty || c.title.localizedCaseInsensitiveContains(query) || c.artistName.localizedCaseInsensitiveContains(query) || c.tags.contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Commissions").font(.display(38)).foregroundStyle(Palette.text)
                        Text("Hire an artist you love").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { creating = true } label: { Label("List", systemImage: "plus") }
                        .buttonStyle(GradientButtonStyle(height: 42, fullWidth: false))
                }
                SearchField(text: $query, placeholder: "Search styles, artists, tags…")
                HStack(spacing: 8) {
                    Chip(title: "All", icon: "square.grid.2x2.fill", active: !openOnly) { withAnimation(.snappy) { openOnly = false } }
                    Chip(title: "Open now", icon: "circle.fill", active: openOnly) { withAnimation(.snappy) { openOnly = true } }
                }
                if loading && list.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 220, radius: 22) }
                    }
                } else if shown.isEmpty {
                    EmptyCard(icon: "storefront.fill", title: "No commissions yet", text: "Be the first to open commissions — tap List.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, c in
                        Button { selected = c } label: { card(c) }
                            .buttonStyle(BouncyStyle(scale: 0.96))
                            .stagger(appeared, i)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle("Commissions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onAppear { appeared = true }
        .fullScreenCover(isPresented: $creating) { NewCommissionView { await load() } }
        .sheet(item: $selected) { c in
            CommissionDetail(commission: c, open: { route in
                selected = nil
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); path.append(route) }
            }, changed: { Task { await load() } })
            .presentationDetents([.large])
            .presentationCornerRadius(32)
        }
    }

    private func card(_ c: Commission) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let first = c.samples.first {
                    RemoteImage(url: first)
                } else {
                    LinearGradient(colors: [Theme.light, Theme.main], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "paintbrush.pointed.fill").font(.system(size: 34)).foregroundStyle(.white.opacity(0.8)))
                }
                StatusPill(open: c.isOpen).padding(8)
            }
            .frame(height: 140)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let price = c.fromPrice {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("FROM").font(.jakarta(8, .heavy)).foregroundStyle(Palette.muted)
                        Text("$\(Int(price))").font(.display(20)).foregroundStyle(Palette.text)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(c.title).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Avatar(url: model.person(c.artistEmail)?.picture ?? c.artistPicture, name: c.artistName, size: 20)
                    Text(c.artistName).font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            .padding(10)
        }
        .sugarCard(radius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func load() async {
        defer { loading = false }
        guard let docs = try? await FS.query("Commission", orderBy: "created_date", limit: 150) else { return }
        list = docs.map(Commission.init)
    }
}

struct StatusPill: View {
    let open: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(open ? Palette.success : Palette.muted).frame(width: 7, height: 7)
                .shadow(color: open ? Palette.success.opacity(0.6) : .clear, radius: 3)
            Text(open ? "Open" : "Closed").font(.jakarta(11, .heavy)).foregroundStyle(open ? Palette.success : Palette.muted)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct CommissionDetail: View {
    @State var commission: Commission
    var open: (Route) -> Void
    var changed: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var confirmDelete = false

    private var owner: Bool { model.me?.email == commission.artistEmail || model.me?.isAdmin == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !commission.samples.isEmpty {
                    TabView(selection: $index) {
                        ForEach(commission.samples.indices, id: \.self) { i in
                            RemoteImage(url: commission.samples[i]).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(alignment: .topLeading) { StatusPill(open: commission.isOpen).padding(12) }
                }
                Text(commission.title).font(.display(32)).foregroundStyle(Palette.text)
                Button { dismiss(); open(.person(commission.artistEmail)) } label: {
                    HStack(spacing: 8) {
                        Avatar(url: model.person(commission.artistEmail)?.picture ?? commission.artistPicture, name: commission.artistName, size: 30)
                        Text(commission.artistName).font(.jakarta(14, .bold)).foregroundStyle(Palette.text2)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                }
                .buttonStyle(.plain)
                if !commission.description.isEmpty {
                    Text(commission.description).font(.jakarta(15)).foregroundStyle(Palette.text2)
                }
                if !commission.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(commission.tags, id: \.self) { t in
                            Text("#\(t)").font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
                                .padding(.horizontal, 10).frame(height: 28).background(Theme.soft, in: Capsule())
                        }
                    }
                }
                if !commission.tiers.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(commission.tiers, id: \.self) { t in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(t.name).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                                    Spacer()
                                    Text("$\(t.price.formatted(.number.precision(.fractionLength(0...2))))").font(.display(22)).foregroundStyle(Theme.gradient)
                                }
                                if !t.description.isEmpty { Text(t.description).font(.jakarta(12)).foregroundStyle(Palette.muted) }
                                if let days = t.days { Label("\(days)-day delivery", systemImage: "clock").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted) }
                            }
                            .sugarCard(radius: 18, padding: 12)
                        }
                    }
                }
                VStack(spacing: 10) {
                    if !owner {
                        if commission.isOpen, let url = URL(string: commission.paypal), !commission.paypal.isEmpty {
                            Link(destination: url) { Label("Commission now", systemImage: "arrow.up.right.square.fill") }
                                .buttonStyle(GradientButtonStyle(height: 50))
                        }
                        Button {
                            let me = model.me?.email ?? ""
                            let convo = Conversation(id: Social.dmId(me, commission.artistEmail), members: [me, commission.artistEmail], isGroup: false, groupName: "", last: nil, unread: 0)
                            dismiss()
                            open(.chat(convo))
                        } label: { Label("Message artist", systemImage: "paperplane.fill") }
                            .buttonStyle(OutlineButtonStyle(height: 48, fullWidth: true))
                    } else {
                        Button {
                            let next = !commission.isOpen
                            commission.isOpen = next
                            Task {
                                try? await FS.update("Commission", commission.id, ["is_open": next, "updated_date": FS.nowISO()])
                                model.showToast(next ? "Open for commissions" : "Marked as closed", icon: "storefront.fill")
                                changed()
                            }
                        } label: { Label(commission.isOpen ? "Close commissions" : "Reopen commissions", systemImage: commission.isOpen ? "lock.fill" : "lock.open.fill") }
                            .buttonStyle(GradientButtonStyle(height: 48))
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete listing", systemImage: "trash").foregroundStyle(Palette.danger) }
                            .buttonStyle(OutlineButtonStyle(height: 46, fullWidth: true))
                    }
                }
            }
            .padding(18)
        }
        .sugarBackground()
        .confirmationDialog("Delete this listing?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await FS.delete("Commission", commission.id)
                    model.showToast("Listing deleted", icon: "trash.fill")
                    changed()
                    dismiss()
                }
            }
        }
    }
}

struct TierDraft: Identifiable {
    var id = UUID()
    var name = ""
    var price = ""
    var days = ""
    var info = ""
}

struct NewCommissionView: View {
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var link = ""
    @State private var tags = ""
    @State private var isOpen = true
    @State private var items: [PhotosPickerItem] = []
    @State private var samples: [UIImage] = []
    @State private var tiers: [TierDraft] = [TierDraft()]
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ComposerScaffold(title: "List a commission", actionTitle: "Publish", busy: busy, canPost: !title.trimmingCharacters(in: .whitespaces).isEmpty, onClose: { dismiss() }, onPost: { Task { await publish() } }) {
            VStack(alignment: .leading, spacing: 14) {
                SugarField(placeholder: "Title — e.g. Watercolor pet portraits", text: $title)
                SugarField(placeholder: "Style, what's included, turnaround…", text: $about, lines: 3...8)
                Text("SAMPLES").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(samples.indices, id: \.self) { i in
                            Image(uiImage: samples[i]).resizable().scaledToFill().frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { withAnimation { _ = samples.remove(at: i) } } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                                .transition(.scale.combined(with: .opacity))
                        }
                        if samples.count < 6 {
                            PhotosPicker(selection: $items, maxSelectionCount: 6 - samples.count, matching: .images) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 22)).foregroundStyle(Theme.main)
                                    .frame(width: 84, height: 84)
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.main.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Text("PRICING TIERS").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                ForEach(tiers.indices, id: \.self) { i in
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Tier name", text: $tiers[i].name).font(.jakarta(14, .semibold))
                            TextField("$ price", text: $tiers[i].price).keyboardType(.decimalPad).font(.jakarta(14)).frame(width: 70)
                            TextField("days", text: $tiers[i].days).keyboardType(.numberPad).font(.jakarta(14)).frame(width: 50)
                            if tiers.count > 1 {
                                Button { withAnimation { _ = tiers.remove(at: i) } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Palette.muted) }
                            }
                        }
                        TextField("What's included (optional)", text: $tiers[i].info).font(.jakarta(13))
                    }
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                }
                Button { withAnimation(.snappy) { tiers.append(TierDraft()) } } label: { Label("Add tier", systemImage: "plus") }
                    .font(.jakarta(13, .bold)).foregroundStyle(Theme.main)
                SugarField(placeholder: "Payment link (paypal.me/you)", text: $link)
                SugarField(placeholder: "Tags: portrait, anime, pets", text: $tags)
                Toggle(isOn: $isOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open for commissions").font(.jakarta(14, .bold)).foregroundStyle(Palette.text)
                        Text("You can close it any time.").font(.jakarta(12)).foregroundStyle(Palette.muted)
                    }
                }
                .tint(Theme.main)
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let error { Text(error).font(.jakarta(13, .semibold)).foregroundStyle(Palette.danger) }
            }
        }
        .onChange(of: items) { _, list in
            Task {
                for item in list {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), samples.count < 6 {
                        withAnimation(.snappy) { samples.append(image) }
                    }
                }
                items = []
            }
        }
    }

    private func publish() async {
        guard let me = model.me else { return }
        if Moderation.hasLink(title + " " + about) && !me.isAdmin { error = "Links go in the payment link box."; return }
        busy = true
        defer { busy = false }
        do {
            var urls: [String] = []
            for image in samples {
                if let jpeg = ImageTools.jpeg(image, maxSide: 1600) {
                    urls.append(try await StorageClient.upload(jpeg, contentType: "image/jpeg", fileExtension: "jpg"))
                }
            }
            var cleanLink = link.trimmingCharacters(in: .whitespaces)
            if !cleanLink.isEmpty && !cleanLink.lowercased().hasPrefix("http") { cleanLink = "https://" + cleanLink }
            let tierDocs: [[String: Any]] = tiers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && Double($0.price) != nil }.map { t in
                var doc: [String: Any] = ["name": t.name, "price": Double(t.price) ?? 0, "description": t.info]
                doc["delivery_days"] = Int(t.days).map { $0 as Any } ?? NSNull()
                return doc
            }
            _ = try await FS.create("Commission", [
                "title": title.trimmingCharacters(in: .whitespaces), "description": about.trimmingCharacters(in: .whitespacesAndNewlines),
                "is_open": isOpen, "paypal_link": cleanLink,
                "tags": tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(6).map { $0 },
                "tiers": tierDocs, "samples": urls,
                "artist_email": me.email, "artist_display_name": me.displayName, "artist_profile_picture": me.picture,
            ])
            model.showToast("Commission listed!", icon: "storefront.fill")
            await onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Top artists (the website's TopArtists page)

struct TopArtistsView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var posts
    @State private var artworks: [Artwork] = []
    @State private var appeared = false
    @State private var risen = false
    @State private var spin = false
    @State private var burst = 0
    @State private var range = 0
    @Namespace private var chip

    struct RankEntry: Hashable { var email: String; var likes: Int; var works: Int }

    private static let gold = Color(hex: 0xF0A020)
    private static let goldLight = Color(hex: 0xFFD166)
    private static let silver = Color(hex: 0x94A3B8)
    private static let bronze = Color(hex: 0xC2773A)

    private var ranking: [RankEntry] {
        let since = range == 0 ? "" : Dates.iso(Date().addingTimeInterval(range == 1 ? -7 * 86_400 : -30 * 86_400))
        var likes: [String: Int] = [:]
        var works: [String: Int] = [:]
        for a in artworks where a.created > since { likes[a.authorEmail, default: 0] += a.likes.count; works[a.authorEmail, default: 0] += 1 }
        for p in posts.posts where p.created > since { likes[p.authorEmail, default: 0] += p.likes.count; works[p.authorEmail, default: 0] += 1 }
        return likes.keys.filter { model.person($0) != nil }
            .map { RankEntry(email: $0, likes: likes[$0] ?? 0, works: works[$0] ?? 0) }
            .sorted { $0.likes != $1.likes ? $0.likes > $1.likes : $0.works > $1.works }
    }

    var body: some View {
        let list = ranking
        let top = max(1, list.first?.likes ?? 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero.stagger(appeared, 0)
                HStack(spacing: 6) {
                    ForEach(Array(["All time", "This week", "This month"].enumerated()), id: \.offset) { i, title in
                        let on = range == i
                        Button { pick(i) } label: {
                            Text(title).font(.jakarta(13, .bold))
                                .foregroundStyle(on ? .white : Palette.text2)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background {
                                    if on { Capsule().fill(LinearGradient(colors: [Self.goldLight, Self.gold], startPoint: .topLeading, endPoint: .bottomTrailing)).matchedGeometryEffect(id: "range", in: chip) }
                                    else { Capsule().fill(Palette.surface) }
                                }
                                .overlay(Capsule().strokeBorder(on ? Color.clear : Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.94))
                    }
                }
                .sensoryFeedback(.selection, trigger: range)
                .stagger(appeared, 1)
                if list.count >= 3 { podium(Array(list.prefix(3))).stagger(appeared, 2) }
                if let me = model.me?.email, let mine = list.firstIndex(where: { $0.email == me }) {
                    yourSpot(list, mine).stagger(appeared, 3)
                }
                VStack(spacing: 8) {
                    ForEach(Array(list.enumerated()).dropFirst(list.count >= 3 ? 3 : 0), id: \.element.email) { i, entry in
                        row(entry, rank: i + 1, top: top)
                            .opacity(risen ? 1 : 0)
                            .offset(x: risen ? 0 : 70)
                            .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.5 + Double(min(i, 14)) * 0.05), value: risen)
                    }
                }
                if list.isEmpty { EmptyCard(icon: "crown.fill", title: "No artists yet", text: "Post art to get on the board!") }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) { ConfettiBurst(trigger: burst).frame(height: 520).allowsHitTesting(false) }
        .sugarBackground()
        .navigationTitle("Top artists")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if posts.posts.isEmpty { await posts.load() }
            artworks = ((try? await FS.query("Artwork", orderBy: "created_date", limit: 200)) ?? []).map(Artwork.init)
            try? await Task.sleep(for: .milliseconds(150))
            risen = true
            burst += 1
        }
        .onAppear {
            appeared = true
            spin = true
            if !artworks.isEmpty || !posts.posts.isEmpty { risen = true }
        }
    }

    private func pick(_ i: Int) {
        guard range != i else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { range = i }
        // Replay the podium rise for the new board.
        risen = false
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            risen = true
            burst += 1
        }
    }

    // A big bouncing crown with a glint and sparkles circling it.
    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Self.goldLight.opacity(0.55), .clear], center: .center, startRadius: 4, endRadius: 52))
                    .frame(width: 104, height: 104)
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "sparkle").font(.system(size: CGFloat(10 + i * 3), weight: .bold)).foregroundStyle(Self.goldLight)
                        .offset(x: 40)
                        .rotationEffect(.degrees(Double(i) * 120 + (spin ? 360 : 0)))
                }
                .animation(.linear(duration: 7).repeatForever(autoreverses: false), value: spin)
                Image(systemName: "crown.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Self.goldLight, Self.gold], startPoint: .top, endPoint: .bottom))
                    .overlay { Glint().mask(Image(systemName: "crown.fill").font(.system(size: 42, weight: .bold))) }
                    .shadow(color: Self.gold.opacity(0.5), radius: 10, y: 4)
                    .phaseAnimator([false, true]) { v, up in
                        v.offset(y: up ? -7 : 2).rotationEffect(.degrees(up ? -6 : 6)).scaleEffect(up ? 1.06 : 0.97)
                    } animation: { _ in .easeInOut(duration: 0.9) }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text("Top artists").font(.display(36))
                    .foregroundStyle(LinearGradient(colors: [Self.gold, Theme.main], startPoint: .leading, endPoint: .trailing))
                Text("The most loved artists on Sugerly. Post, get likes, climb the board!").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 6)
    }

    private func podium(_ top: [RankEntry]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            place(top[1], rank: 2, height: 112, color: Self.silver, delay: 0.15)
            place(top[0], rank: 1, height: 156, color: Self.gold, delay: 0.3)
            place(top[2], rank: 3, height: 90, color: Self.bronze, delay: 0)
        }
        .padding(.top, 30)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func place(_ entry: RankEntry, rank: Int, height: CGFloat, color: Color, delay: Double) -> some View {
        let person = model.person(entry.email)
        let size: CGFloat = rank == 1 ? 78 : 62
        return Button { path.append(.person(entry.email)) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: size)
                        .padding(4)
                        .overlay {
                            if rank == 1 {
                                Circle().strokeBorder(AngularGradient(colors: [Self.goldLight, Self.gold, .white, Self.gold, Self.goldLight], center: .center), lineWidth: 4)
                                    .rotationEffect(.degrees(spin ? 360 : 0))
                                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: spin)
                            } else {
                                Circle().strokeBorder(color, lineWidth: 3)
                            }
                        }
                        .shadow(color: color.opacity(0.55), radius: rank == 1 ? 16 : 8)
                    if rank == 1 {
                        Image(systemName: "crown.fill").font(.system(size: 26, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [Self.goldLight, Self.gold], startPoint: .top, endPoint: .bottom))
                            .overlay { Glint().mask(Image(systemName: "crown.fill").font(.system(size: 26, weight: .bold))) }
                            .shadow(color: Self.gold.opacity(0.6), radius: 6)
                            .phaseAnimator([false, true]) { v, up in
                                v.offset(y: up ? -34 : -26).rotationEffect(.degrees(up ? -10 : 8))
                            } animation: { _ in .easeInOut(duration: 0.8) }
                        Twinkle(size: 13).offset(x: size * 0.55, y: size * 0.1)
                    } else {
                        Text("\(rank)").font(.jakarta(12, .black)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(color, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                            .offset(x: size * 0.36, y: size * 0.72)
                    }
                }
                .scaleEffect(risen ? 1 : 0.3)
                .opacity(risen ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(delay + 0.35), value: risen)
                Text(person?.displayName ?? "").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                VStack(spacing: 2) {
                    Text("\(rank)").font(.display(rank == 1 ? 36 : 28)).foregroundStyle(.white)
                    Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(11, .heavy)).foregroundStyle(.white.opacity(0.92))
                }
                .opacity(risen ? 1 : 0)
                .frame(maxWidth: .infinity)
                .frame(height: risen ? height : 14, alignment: .top)
                .padding(.top, 4)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
                        .overlay { if rank == 1 { Glint().clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)) } }
                }
                .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(delay), value: risen)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
    }

    // Where you are on the board and how far to the next spot.
    private func yourSpot(_ list: [RankEntry], _ index: Int) -> some View {
        let entry = list[index]
        let gap = index > 0 ? list[index - 1].likes - entry.likes + 1 : 0
        return HStack(spacing: 12) {
            Text("#\(index + 1)").font(.display(26)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Your spot").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                Text(index == 0 ? "You're the top artist. Keep that crown!" : "\(gap) more like\(gap == 1 ? "" : "s") to reach #\(index)")
                    .font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
        }
        .sugarCard(radius: 22, padding: 12)
    }

    private func row(_ entry: RankEntry, rank: Int, top: Int) -> some View {
        let person = model.person(entry.email)
        let share = CGFloat(entry.likes) / CGFloat(top)
        return Button { path.append(.person(entry.email)) } label: {
            HStack(spacing: 12) {
                Text("\(rank)").font(.display(20)).foregroundStyle(rank <= 10 ? Theme.main : Palette.muted).frame(width: 30)
                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 44, online: person?.isOnline ?? false)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(person?.displayName ?? "").font(.jakarta(15, .bold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text("\(entry.works) works").font(.jakarta(11)).foregroundStyle(Palette.muted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surface2)
                            Capsule().fill(Theme.gradient).frame(width: max(6, geo.size.width * (risen ? share : 0)))
                                .animation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.6 + Double(min(rank, 14)) * 0.05), value: risen)
                        }
                    }
                    .frame(height: 6)
                }
                Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(13, .heavy)).foregroundStyle(Theme.main)
                FollowButton(email: entry.email, compact: true)
            }
            .sugarCard(radius: 20, padding: 10)
        }
        .buttonStyle(BouncyStyle(scale: 0.98))
    }
}

// A soft white glint that sweeps across now and then, like the logo shine.
// The band is much taller than the view and starts/ends well outside it, so
// no sliver is ever left showing at the edge while it waits.
struct Glint: View {
    var pause: Double = 2.2
    var strength: Double = 0.75

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let band = max(20, min(w, h) * 0.55)
            let reach = band + h * 0.5
            LinearGradient(colors: [.white.opacity(0), .white.opacity(strength), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: band, height: h * 3 + band)
                .rotationEffect(.degrees(20))
                .phaseAnimator([false, true]) { v, go in
                    v.position(x: go ? w + reach : -reach, y: h / 2)
                } animation: { go in go ? .easeInOut(duration: 0.9).delay(pause) : nil }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - What's new (release notes + updates admins post)

struct AppRelease: Identifiable {
    var id: String
    var icon: String
    var title: String
    var date: String
    var items: [String]
    var author: String = ""
    var docId: String? = nil
}

enum AppReleases {
    static let native: [AppRelease] = [
        AppRelease(id: "ios-1.8", icon: "lock.shield.fill", title: "Status, requests & privacy", date: "2026-09-28T13:00:00Z", items: [
            "Set your status like Discord: Online, Idle, Do not disturb or Invisible, plus a custom status that can clear itself.",
            "Messages from people you aren't friends with arrive as requests you can accept, decline or block.",
            "Calls and voice messages are for friends (people who follow each other).",
            "Ignore people to stop hearing from them, or block them. Manage both in Settings → Privacy & status.",
            "Logging out closes everything, and a new account starts completely fresh.",
            "Voice messages play instantly, and photos and videos in chats go through the in-app camera and editor.",
            "Pull down on the first reel to refresh the feed, like TikTok. GIFs show up in comments again.",
            "Built for huge amounts: chats keep every old conversation, scroll up to load older messages (DMs and servers), comments load in pages, and For You also digs up older reels.",
        ]),
        AppRelease(id: "ios-1.7", icon: "person.2.wave.2.fill", title: "More social & smoother", date: "2026-09-28T11:00:00Z", items: [
            "Home has stories, today's art prompt, Happening now, people you might like and trending tags.",
            "Community has a weekly challenge, top creators this week and you can send posts to chats.",
            "Top artists has a bouncing crown, a rising podium and confetti.",
            "Changing colours is smooth and keeps your music playing.",
            "A big, crisp white shine sweeps over the whole screen when you switch pages, and pages pop in again each time.",
            "Soft click sounds when you tap (Settings → Sounds & haptics).",
            "Empty pages have Mimi, the Sugerly bunny, in your accent colour.",
            "The animated background keeps moving after you change it.",
            "Your picture opens a quick menu that pops open instantly.",
            "Admins can add, remove and pin weekly challenges and daily art prompts.",
            "A new notifications card, and long-press on server messages to reply, edit or delete.",
        ]),
        AppRelease(id: "ios-1.6", icon: "bell.badge.fill", title: "Widgets, notifications & calls", date: "2026-09-28T06:00:00Z", items: [
            "Home-screen and lock-screen widgets: streak & coins, inbox and featured art.",
            "Notifications for DMs, servers, likes, comments, follows and new reels.",
            "Drafts for posts and reels, and you can close DMs.",
            "Animated backgrounds — polka dots, clouds, stripes, hearts or stars — in Settings.",
            "Voice channels ring like real calls, with a green circle that grows while you talk.",
        ]),
        AppRelease(id: "ios-1.5", icon: "sparkles", title: "Nitro, GIFs & stickers", date: "2026-09-28T05:00:00Z", items: [
            "A better camera: speed 0.5x–3x, 15s or 60s, a grid and your sound while you film.",
            "GIFs and stickers in chats, servers, comments and posts. Make your own stickers and GIFs.",
            "MimiNitro: GIF profile picture and banner, premium name styles and profile effects.",
            "Crop your picture and banner, add pronouns, a status, interests and colours.",
            "Use any reel's sound, draw on reels and photos, and smoother two-finger text.",
            "A smarter For You feed that learns what you like, right on your phone.",
        ]),
        AppRelease(id: "ios-1.4", icon: "waveform.circle.fill", title: "Servers, voice & admin", date: "2026-09-27T20:00:00Z", items: [
            "Discord-style servers: a rail of your servers, channels, roles with colours and permissions, pins and reactions.",
            "Voice channels right in the app — talk with people on the app and the website.",
            "The full admin panel, commissions, top artists and a photo editor for posts.",
        ]),
        AppRelease(id: "ios-1.3", icon: "camera.aperture", title: "Camera & editor", date: "2026-09-27T19:30:00Z", items: [
            "Film in clips: pause, delete the last clip or start over, with flash, timer and flip.",
            "Text you can drag, pinch and twist, stickers, filters and adjustments.",
            "Reels and Community look just like the website.",
        ]),
        AppRelease(id: "ios-1.2", icon: "heart.circle.fill", title: "Cuter everywhere", date: "2026-09-27T19:00:00Z", items: [
            "Gallery is a main tab, notifications pop up, a pinker look and snappier tabs.",
            "Search, People, toasts and shimmer loading.",
        ]),
    ]
}

struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @State private var posted: [AppRelease] = []
    @State private var title = ""
    @State private var text = ""
    @State private var busy = false
    @State private var appeared = false
    @AppStorage("sugerly.updatesSeen") private var seen = ""

    private var all: [AppRelease] { (posted + AppReleases.native).sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new").font(.display(38)).foregroundStyle(Palette.text)
                    Text("Everything new in Sugerly, newest first.").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                }
                if model.me?.isAdmin == true { composer }
                ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: r.icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.gradient).frame(width: 46, height: 46)
                            .background(Theme.soft, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.main.opacity(0.25), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(r.title).font(.jakarta(16, .heavy)).foregroundStyle(Palette.text)
                                Spacer()
                                if let docId = r.docId, model.me?.isAdmin == true {
                                    Button { Task { try? await FS.delete("AppUpdate", docId); posted.removeAll { $0.docId == docId } } } label: {
                                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Palette.danger)
                                    }
                                }
                            }
                            Text(Dates.parse(r.date)?.formatted(date: .long, time: .omitted) ?? "").font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
                            ForEach(r.items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Theme.gradient).frame(width: 6, height: 6).padding(.top, 7)
                                    Text(item).font(.jakarta(14)).foregroundStyle(Palette.text2)
                                }
                            }
                        }
                        .sugarCard(radius: 22, padding: 14)
                    }
                    .stagger(appeared, i)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear { appeared = true; seen = FS.nowISO() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("POST AN UPDATE (ADMINS)").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
            SugarField(placeholder: "Title — e.g. New stickers in Reels", text: $title)
            SugarField(placeholder: "What changed? One line per point.", text: $text, lines: 3...8)
            Button { Task { await post() } } label: {
                if busy { ProgressView().tint(.white) } else { Label("Post update", systemImage: "paperplane.fill") }
            }
            .buttonStyle(GradientButtonStyle(height: 44))
            .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .sugarCard(radius: 22, padding: 14)
    }

    private func load() async {
        let docs = (try? await FS.query("AppUpdate", orderBy: "created_date", limit: 50)) ?? []
        posted = docs.map { d in
            AppRelease(id: "post-\(d.str("id"))", icon: "megaphone.fill", title: d.str("title"), date: d.str("created_date"),
                       items: d.str("body").split(separator: "\n").map(String.init).filter { !$0.isEmpty }, author: d.str("author_name"), docId: d.str("id"))
        }
    }

    private func post() async {
        guard let me = model.me else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await FS.create("AppUpdate", ["title": title.trimmingCharacters(in: .whitespaces), "body": text.trimmingCharacters(in: .whitespacesAndNewlines), "emoji": "", "author_name": me.displayName])
            title = ""
            text = ""
            model.showToast("Update posted", icon: "megaphone.fill")
            await load()
        } catch {
            model.showToast("Couldn't post — \(error.localizedDescription)", error: true)
        }
    }
}
