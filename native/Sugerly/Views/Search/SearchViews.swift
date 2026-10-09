import SwiftUI

// MARK: - Follow button (used by People, Search and profiles)

struct FollowButton: View {
    let email: String
    var compact = false
    @Environment(AppModel.self) private var model

    private var following: Bool { model.me?.following.contains(email) ?? false }

    var body: some View {
        if email != model.me?.email {
            Button { toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: following ? "checkmark" : "plus").font(.system(size: 11, weight: .heavy))
                    Text(following ? "Following" : "Follow")
                }
                .font(.jakarta(compact ? 12 : 13, .heavy))
                .foregroundStyle(following ? Theme.main : .white)
                .padding(.horizontal, compact ? 12 : 16)
                .frame(height: compact ? 30 : 34)
                .background {
                    if following {
                        Capsule().fill(Theme.soft)
                    } else {
                        Capsule().fill(Theme.gradient).shadow(color: Theme.main.opacity(0.35), radius: 6, y: 3)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(BouncyStyle(scale: 0.9))
            .sensoryFeedback(.impact(weight: .light), trigger: following)
            .motion(Motion.standard, value: following)
        }
    }

    private func toggle() {
        guard let me = model.me else { return }
        let now = !following
        let next = now ? me.following + [email] : me.following.filter { $0 != email }
        Task {
            do {
                try await model.updateMe(["following": next])
                if now {
                    Notify.send(to: email, from: me, type: "follow", message: "\(me.displayName) started following you", link: "/Profile?email=\(me.email)")
                    model.showToast("Following \(model.person(email)?.displayName ?? "them")", icon: "heart.fill")
                }
            } catch {
                model.showToast("Couldn't update — try again", error: true)
            }
        }
    }
}

// MARK: - People: find artists to follow

struct PeopleView: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter = 0
    @State private var appeared = false

    // Friends = you follow each other (same as chats and calls).
    private let filters = ["Friends", "Suggested", "Online", "Following", "Followers"]

    private var list: [UserProfile] {
        guard let me = model.me else { return [] }
        let blocked = Set(me.blocked)
        let mine = Set(me.following)
        var all = model.people.values.filter { $0.email != me.email && !blocked.contains($0.email) }
        switch filter {
        case 0: all = all.filter { mine.contains($0.email) && $0.following.contains(me.email) }
        case 2: all = all.filter(\.isOnline)
        case 3: all = all.filter { mine.contains($0.email) }
        case 4: all = all.filter { $0.following.contains(me.email) }
        default: all = all.filter { !mine.contains($0.email) }
        }
        if !query.isEmpty {
            all = all.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.bio.localizedCaseInsensitiveContains(query) }
        }
        // Always the same order for the same people: the people list refreshes
        // every few seconds, and an unsettled order made rows jump around.
        let byName: (UserProfile, UserProfile) -> Bool = { a, b in
            let x = a.displayName.lowercased(), y = b.displayName.lowercased()
            return x != y ? x < y : a.email < b.email
        }
        if filter == 1 {
            // People who follow you or your friends, then the most active.
            let scores = Dictionary(all.map { ($0.email, PeopleView.score($0, me: me)) }, uniquingKeysWith: { a, _ in a })
            all.sort { a, b in
                let sa = scores[a.email] ?? 0, sb = scores[b.email] ?? 0
                return sa != sb ? sa > sb : byName(a, b)
            }
        } else {
            all.sort(by: byName)
        }
        return all
    }

    // The list above only shows people this phone knows about; these fetch
    // the right ones from the server for each tab and search.
    private func fetchForTab() async {
        guard let me = model.me else { return }
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            _ = await model.searchPeople(query)
            return
        }
        switch filter {
        case 0, 3:
            for email in me.following.prefix(300) { _ = model.person(email) }
        case 4:
            let docs = (try? await FS.query("User", [.contains("following", me.email)], limit: 300)) ?? []
            var map = model.people
            for doc in docs {
                let u = UserProfile(doc)
                if !u.email.isEmpty { map[u.email] = u }
            }
            model.people = map
        default:
            break
        }
    }

    // Leaves out online status on purpose: it flips all the time and would
    // keep reshuffling the list.
    static func score(_ p: UserProfile, me: UserProfile) -> Int {
        var s = p.xp / 50
        if p.following.contains(me.email) { s += 1000 }
        let mutual = p.following.filter { me.following.contains($0) }.count
        s += mutual * 100
        return s
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friends").font(.display(40)).foregroundStyle(Palette.text)
                    Text("Your friends, and new people to meet.").font(.jakarta(14)).foregroundStyle(Palette.muted)
                }
                SearchField(text: $query, placeholder: "Search people…")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters.indices, id: \.self) { i in
                            Chip(title: filters[i], active: filter == i) { withMotion(Motion.standard) { filter = i } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if model.people.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in SkeletonRow() }
                }
                let shown = list
                if !model.people.isEmpty && shown.isEmpty {
                    if filter == 0 && query.isEmpty {
                        EmptyCard(icon: "person.2.fill", title: "No friends yet", text: "When someone you follow follows you back, they show up here. Find people in Suggested.")
                    } else {
                        EmptyCard(icon: "person.2.fill", title: "No one here yet", text: query.isEmpty ? "Try another tab." : "Try another name.")
                    }
                }
                // Round tiles in a grid instead of long rows.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(shown.prefix(150).enumerated()), id: \.element.id) { i, person in
                        PersonBubble(person: person) { path.append(.person(person.email)) }
                            .stagger(appeared, i)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .sideRails(680)
        }
        .scrollDismissesKeyboard(.interactively)
        .sugarBackground()
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.loadPeople() }
        .task { if model.people.isEmpty { await model.loadPeople() } }
        .task(id: "\(filter)|\(query)") { await fetchForTab() }
        .onAppear { appeared = true }
    }
}

// A round, friendly card for one person: big picture, name, level and a
// follow button.
struct PersonBubble: View {
    let person: UserProfile
    var open: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let info = LevelInfo(xp: person.xp)
        let followsYou = person.following.contains(model.me?.email ?? "")
        VStack(spacing: 10) {
            Button(action: open) {
                VStack(spacing: 8) {
                    Avatar(url: person.picture, name: person.displayName, size: 82, online: person.isOnline,
                           presence: person.isOnline ? person.presenceNow : nil)
                    HStack(spacing: 4) {
                        Text(person.displayName).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                        if person.isAdmin {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(Theme.gradient)
                        }
                    }
                    Text("Lv. \(info.level) · \(info.title)").font(.jakarta(11, .bold)).foregroundStyle(info.color).lineLimit(1)
                    Text(followsYou ? "Follows you" : (person.bio.isEmpty ? " " : person.bio))
                        .font(.jakarta(11, followsYou ? .semibold : .regular)).foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.96))
            FollowButton(email: person.email, compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }
}

struct PersonRow: View {
    let person: UserProfile
    var open: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let info = LevelInfo(xp: person.xp)
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Avatar(url: person.picture, name: person.displayName, size: 52, online: person.isOnline, ring: person.isOnline)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(person.displayName).font(.jakarta(15, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                            if person.isAdmin {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Theme.gradient)
                            }
                        }
                        Text("Lv. \(info.level) · \(info.title)").font(.jakarta(12, .bold)).foregroundStyle(info.color)
                        if !person.bio.isEmpty {
                            Text(person.bio).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                        } else if person.following.contains(model.me?.email ?? "") {
                            Text("Follows you").font(.jakarta(12, .semibold)).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.98))
            FollowButton(email: person.email, compact: true)
        }
        .sugarCard(radius: 22, padding: 12)
    }
}

// Rounded search box used across the app.
struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search…"
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold)).foregroundStyle(focused ? Theme.main : Palette.muted)
            TextField(placeholder, text: $text).font(.jakarta(15)).focused($focused).submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .buttonStyle(BouncyStyle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Theme.main.opacity(0.5) : Palette.border, lineWidth: focused ? 1.5 : 1))
        .shadow(color: focused ? Theme.main.opacity(0.15) : .clear, radius: 10, y: 4)
        .motion(Motion.standard, value: focused)
        .onAppear { if autofocus { focused = true } }
    }
}

// MARK: - Search everything (people, posts, art, servers)

struct SearchView: View {
    var go: (Route) -> Void
    var initial = ""
    @Environment(AppModel.self) private var model
    @Environment(PostsStore.self) private var posts
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var artworks: [Artwork] = []
    @State private var servers: [Server] = []
    @AppStorage("sugerly.recentSearches") private var recentRaw = ""

    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private var q: String { query.trimmingCharacters(in: .whitespaces) }

    private var people: [UserProfile] {
        guard !q.isEmpty else { return [] }
        return model.people.values.filter { $0.displayName.localizedCaseInsensitiveContains(q) }.sorted { $0.xp > $1.xp }.prefix(6).map { $0 }
    }
    private var postHits: [Post] {
        guard !q.isEmpty else { return [] }
        return posts.posts.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.title.localizedCaseInsensitiveContains(q) }.prefix(6).map { $0 }
    }
    private var artHits: [Artwork] {
        guard !q.isEmpty else { return [] }
        return artworks.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.authorName.localizedCaseInsensitiveContains(q) || $0.medium.localizedCaseInsensitiveContains(q) }.prefix(8).map { $0 }
    }
    private var serverHits: [Server] {
        guard !q.isEmpty else { return [] }
        return servers.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SearchField(text: $query, placeholder: "Search Sugerly…", autofocus: true)
                Button("Cancel") { dismiss() }.font(.jakarta(15, .bold)).foregroundStyle(Theme.main)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if q.isEmpty {
                        idle
                    } else if people.isEmpty && postHits.isEmpty && artHits.isEmpty && serverHits.isEmpty {
                        EmptyCard(icon: "magnifyingglass", title: "Nothing found", text: "Try another word.")
                    }
                    if !people.isEmpty {
                        group("People", "person.2.fill") {
                            ForEach(people) { person in
                                PersonRow(person: person) { open(.person(person.email)) }
                            }
                        }
                    }
                    if !artHits.isEmpty {
                        group("Artworks", "paintpalette.fill") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(artHits) { art in
                                        Button { open(.artwork(art)) } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                RemoteImage(url: art.imageURL).frame(width: 130, height: 150).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                                Text(art.title).font(.jakarta(12, .bold)).foregroundStyle(Palette.text).lineLimit(1).frame(width: 130, alignment: .leading)
                                            }
                                        }
                                        .buttonStyle(BouncyStyle(scale: 0.95))
                                    }
                                }
                            }
                        }
                    }
                    if !postHits.isEmpty {
                        group("Posts", "text.bubble.fill") {
                            ForEach(postHits) { post in
                                Button { open(.post(post)) } label: {
                                    HStack(spacing: 12) {
                                        if !post.imageURL.isEmpty {
                                            RemoteImage(url: post.imageURL).frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(model.name(post.authorEmail, post.authorName)).font(.jakarta(13, .heavy)).foregroundStyle(Palette.text)
                                            Text(post.text.isEmpty ? post.title : post.text).font(.jakarta(13)).foregroundStyle(Palette.text2).lineLimit(2).multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .sugarCard(radius: 20, padding: 10)
                                }
                                .buttonStyle(BouncyStyle(scale: 0.97))
                            }
                        }
                    }
                    if !serverHits.isEmpty {
                        group("Servers", "person.3.fill") {
                            ForEach(serverHits) { server in
                                Button { open(.server(server)) } label: {
                                    HStack(spacing: 12) {
                                        ServerIcon(server: server, size: 44)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(server.name).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text)
                                            Text("\(server.members.count) members").font(.jakarta(12)).foregroundStyle(Palette.muted)
                                        }
                                        Spacer()
                                    }
                                    .sugarCard(radius: 20, padding: 10)
                                }
                                .buttonStyle(BouncyStyle(scale: 0.97))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sugarBackground()
        .onAppear { if !initial.isEmpty && query.isEmpty { query = initial } }
        .dropRemoved($artworks)
        .task(id: q) {
            // Ask the server too (names starting with what you typed), so
            // results aren't limited to what this phone has loaded.
            guard !q.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let capital = q.prefix(1).uppercased() + q.dropFirst()
            async let people = model.searchPeople(q)
            async let art1 = try? FS.prefix("Artwork", field: "title", q, limit: 12)
            async let art2 = try? FS.prefix("Artwork", field: "title", capital, limit: 12)
            async let srv1 = try? FS.prefix("Community", field: "name", q, limit: 8)
            async let srv2 = try? FS.prefix("Community", field: "name", capital, limit: 8)
            _ = await people
            var knownArt = Set(artworks.map(\.id))
            artworks += ((await art1 ?? []) + (await art2 ?? [])).map(Artwork.init).filter { knownArt.insert($0.id).inserted }
            var knownServers = Set(servers.map(\.id))
            servers += ((await srv1 ?? []) + (await srv2 ?? [])).map(Server.init).filter { knownServers.insert($0.id).inserted }
        }
        .task {
            async let art = try? FS.query("Artwork", orderBy: "created_date", limit: 200)
            async let srv = try? FS.query("Community", orderBy: "created_date", limit: 150)
            artworks = (await art ?? []).map(Artwork.init)
            servers = (await srv ?? []).map(Server.init)
            if model.people.isEmpty { await model.loadPeople() }
        }
    }

    @ViewBuilder
    private var idle: some View {
        if !recents.isEmpty {
            HStack {
                Text("RECENT").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
                Spacer()
                Button("Clear") { recentRaw = "" }.font(.jakarta(12, .bold)).foregroundStyle(Theme.main)
            }
            FlowChips(items: recents) { query = $0 }
        }
        Text("TRY").font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
        FlowChips(items: ["#art", "#wip", "digital", "watercolor", "anime", "music"]) { query = $0 }
        Button { open(.people) } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill").foregroundStyle(.white).frame(width: 44, height: 44).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find people").font(.jakarta(15, .heavy)).foregroundStyle(Palette.text)
                    Text("Suggested artists and friends").font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
            }
            .sugarCard(radius: 22, padding: 12)
        }
        .buttonStyle(BouncyStyle(scale: 0.97))
    }

    private func group<Content: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: icon).font(.jakarta(11, .heavy)).tracking(1.2).foregroundStyle(Palette.muted)
            content()
        }
    }

    private func open(_ route: Route) {
        if !q.isEmpty {
            var list = recents.filter { $0.lowercased() != q.lowercased() }
            list.insert(q, at: 0)
            recentRaw = list.prefix(8).joined(separator: "\n")
        }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            go(route)
        }
    }
}

// Chips that wrap onto new lines.
struct FlowChips: View {
    let items: [String]
    var tap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { tap(item) } label: {
                    Text(item).font(.jakarta(13, .semibold)).foregroundStyle(Palette.text2)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                }
                .buttonStyle(BouncyStyle())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
