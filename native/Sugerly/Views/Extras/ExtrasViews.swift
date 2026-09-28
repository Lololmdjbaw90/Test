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
    @State private var range = 0

    struct RankEntry: Hashable { var email: String; var likes: Int; var works: Int }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top artists").font(.display(38)).foregroundStyle(Palette.text)
                    Text("Most loved on Sugerly").font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 8) {
                    Chip(title: "All time", active: range == 0) { withAnimation(.snappy) { range = 0 } }
                    Chip(title: "This week", active: range == 1) { withAnimation(.snappy) { range = 1 } }
                    Chip(title: "This month", active: range == 2) { withAnimation(.snappy) { range = 2 } }
                }
                if list.count >= 3 { podium(Array(list.prefix(3))).stagger(appeared, 0) }
                VStack(spacing: 8) {
                    ForEach(Array(list.enumerated()).dropFirst(list.count >= 3 ? 3 : 0), id: \.element.email) { i, entry in
                        let person = model.person(entry.email)
                        Button { path.append(.person(entry.email)) } label: {
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.display(20)).foregroundStyle(Palette.muted).frame(width: 30)
                                Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: 44, online: person?.isOnline ?? false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person?.displayName ?? "").font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                                    Text("\(entry.works) works").font(.jakarta(11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(13, .heavy)).foregroundStyle(Theme.main)
                                FollowButton(email: entry.email, compact: true)
                            }
                            .sugarCard(radius: 20, padding: 10)
                        }
                        .buttonStyle(BouncyStyle(scale: 0.98))
                        .stagger(appeared, i)
                    }
                }
                if list.isEmpty { EmptyCard(icon: "crown.fill", title: "No artists yet", text: "Post art to get on the board!") }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sugarBackground()
        .navigationTitle("Top artists")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if posts.posts.isEmpty { await posts.load() }
            artworks = ((try? await FS.query("Artwork", orderBy: "created_date", limit: 200)) ?? []).map(Artwork.init)
        }
        .onAppear { appeared = true }
    }

    private func podium(_ top: [RankEntry]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            place(top[1], rank: 2, height: 110, color: Color(hex: 0x94A3B8))
            place(top[0], rank: 1, height: 150, color: Color(hex: 0xF0A020))
            place(top[2], rank: 3, height: 90, color: Color(hex: 0xC2773A))
        }
        .padding(.top, 20)
    }

    private func place(_ entry: RankEntry, rank: Int, height: CGFloat, color: Color) -> some View {
        let person = model.person(entry.email)
        return Button { path.append(.person(entry.email)) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    Avatar(url: person?.picture ?? "", name: person?.displayName ?? "", size: rank == 1 ? 76 : 62)
                        .padding(3)
                        .overlay(Circle().strokeBorder(color, lineWidth: 3))
                        .shadow(color: color.opacity(0.5), radius: 10)
                    if rank == 1 {
                        Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(color)
                            .offset(y: -24)
                            .rotationEffect(.degrees(appeared ? -8 : 8))
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: appeared)
                    }
                }
                Text(person?.displayName ?? "").font(.jakarta(13, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                VStack(spacing: 2) {
                    Text("\(rank)").font(.display(30)).foregroundStyle(.white)
                    Label("\(entry.likes)", systemImage: "heart.fill").font(.jakarta(11, .heavy)).foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(LinearGradient(colors: [color.opacity(0.9), color], startPoint: .top, endPoint: .bottom), in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BouncyStyle(scale: 0.96))
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
        AppRelease(id: "ios-1.5", icon: "sparkles", title: "Nitro, GIFs & face filters", date: "2026-09-28T05:00:00Z", items: [
            "Face filters in the camera — puppy, kitty, bunny, bear, crown and more — plus speed, 15s/60s and a grid.",
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
