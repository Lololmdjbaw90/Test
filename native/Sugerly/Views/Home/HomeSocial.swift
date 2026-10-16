import SwiftUI
import UIKit

// The social bits of Home: stories, a "what are you making" bar, today's art
// prompt, what friends are up to, trending tags and people to follow.

// MARK: - Stories (people with a new reel, then friends who are online)

struct StoriesRow: View {
    let reels: [Reel]
    @Binding var path: [Route]
    var compose: (Composer) -> Void
    @Environment(AppModel.self) private var model
    @AppStorage("sugerly.storiesSeen") private var seenRaw = ""

    struct Story: Identifiable {
        var email: String
        var reel: Reel?
        var id: String { email }
    }

    private var seen: Set<String> { Set(seenRaw.split(separator: ",").map(String.init)) }

    private var stories: [Story] {
        let me = model.me?.email ?? ""
        let blocked = Set(model.me?.blocked ?? [])
        let dayAgo = Dates.iso(Date().addingTimeInterval(-2 * 86_400))
        var out: [Story] = []
        var added = Set<String>()
        // Newest reel per person from the last two days.
        for r in reels.sorted(by: { $0.created > $1.created }) where r.created > dayAgo && r.authorEmail != me && !blocked.contains(r.authorEmail) && !added.contains(r.authorEmail) {
            out.append(Story(email: r.authorEmail, reel: r))
            added.insert(r.authorEmail)
        }
        // Unwatched first, then the rest.
        out.sort { (seen.contains($0.reel?.id ?? "") ? 1 : 0) < (seen.contains($1.reel?.id ?? "") ? 1 : 0) }
        let following = model.me?.following ?? []
        for email in following where !added.contains(email) && model.person(email)?.isOnline == true {
            out.append(Story(email: email, reel: nil))
            added.insert(email)
        }
        return Array(out.prefix(20))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                Button { compose(.reel) } label: {
                    VStack(spacing: 6) {
                        Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 62)
                            .padding(4)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.gradient, in: Circle())
                                    .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 2.5))
                            }
                        Text("Your reel").font(.jakarta(11, .bold)).foregroundStyle(Palette.text2)
                    }
                    .frame(width: 76)
                }
                .buttonStyle(BouncyStyle(scale: 0.9))
                ForEach(Array(stories.enumerated()), id: \.element.id) { i, story in
                    bubble(story).transition(.pop).swipeFade()
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private func bubble(_ story: Story) -> some View {
        let person = model.person(story.email)
        let fresh = story.reel.map { !seen.contains($0.id) } ?? false
        return Button {
            if let reel = story.reel {
                var ids = seen
                ids.insert(reel.id)
                seenRaw = ids.suffix(200).joined(separator: ",")
                path.append(.reel(reel))
            } else {
                path.append(.person(story.email))
            }
        } label: {
            VStack(spacing: 6) {
                Avatar(url: person?.picture ?? story.reel?.authorPicture ?? "", name: person?.displayName ?? story.reel?.authorName ?? "", size: 62)
                    .padding(4)
                    .background {
                        if story.reel == nil {
                            Circle().strokeBorder(Palette.success, lineWidth: 3)
                        } else if fresh {
                            Circle().strokeBorder(AngularGradient(colors: [Theme.main, Theme.light, Color(hex: 0xFFD166), Theme.main], center: .center), lineWidth: 3.2)
                        } else {
                            Circle().strokeBorder(Palette.border, lineWidth: 2)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if story.reel == nil {
                            Text("LIVE").font(.jakarta(8, .black)).foregroundStyle(.white)
                                .padding(.horizontal, 6).frame(height: 16)
                                .background(Palette.success, in: Capsule())
                                .overlay(Capsule().strokeBorder(Palette.bg, lineWidth: 2))
                                .offset(y: 6)
                        }
                    }
                Text(person?.displayName ?? story.reel?.authorName ?? "").font(.jakarta(11, fresh ? .heavy : .semibold))
                    .foregroundStyle(fresh ? Palette.text : Palette.text2).lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(BouncyStyle(scale: 0.9))
    }
}

// MARK: - "What are you making today?"

struct HomeComposerBar: View {
    var compose: (Composer) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Button { compose(.post) } label: {
                HStack(spacing: 12) {
                    Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What are you making today?")
                            .font(.jakarta(15, .bold)).foregroundStyle(Palette.text)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text("Tap to share it with everyone")
                            .font(.jakarta(12, .medium)).foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Theme.gradient, in: Circle())
                        .shadow(color: Theme.main.opacity(0.28), radius: 6, y: 3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyStyle(scale: 0.98))
            Rectangle().fill(Palette.border).frame(height: 1).padding(.horizontal, 14)
            HStack(spacing: 0) {
                action("Post", "text.bubble.fill", Palette.blushHex) { compose(.post) }
                action("Reel", "play.rectangle.fill", Palette.pinkHex) { compose(.reel) }
                action("Drawing", "paintbrush.pointed.fill", Palette.creamHex) { compose(.artwork) }
                action("Song", "music.note", Palette.ivoryHex) { compose(.track) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .sugarCard(radius: 24)
    }

    private func action(_ title: String, _ icon: String, _ tint: UInt32, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.main)
                    .frame(width: 36, height: 36)
                    .background(Palette.tile(tint), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                Text(title).font(.jakarta(11, .bold)).foregroundStyle(Palette.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyStyle(scale: 0.92))
        .accessibilityLabel("New \(title.lowercased())")
    }
}

// MARK: - Today's art prompt

struct ArtPromptCard: View {
    var compose: (Composer) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false
    @State private var editing = false

    private var hoursLeft: Int {
        let end = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return max(1, Int(ceil(end.timeIntervalSinceNow / 3600)))
    }

    var body: some View {
        if let prompt = DailyContent.prompt {
            card(prompt)
                .sheet(isPresented: $editing) { DailyContentEditor(kind: .prompts).presentationCornerRadius(30) }
        } else if model.me?.isAdmin == true {
            Button { editing = true } label: {
                Label("Add daily art prompts", systemImage: "plus.circle.fill").font(.jakarta(14, .bold)).foregroundStyle(Theme.main)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(BouncyStyle(scale: 0.97))
            .sheet(isPresented: $editing) { DailyContentEditor(kind: .prompts).presentationCornerRadius(30) }
        }
    }

    private func card(_ prompt: ArtPrompt) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Today's prompt", systemImage: "paintpalette.fill").font(.jakarta(12, .semibold))
                        .foregroundStyle(Palette.text2)
                    if model.me?.isAdmin == true { AdminEditChip { editing = true } }
                }
                Text(prompt.text).font(.display(24)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                Text(DailyContent.promptPinned ? "Picked by the Sugerly team" : "New prompt in \(hoursLeft)h").font(.jakarta(12, .medium)).foregroundStyle(Palette.text2)
                HStack(spacing: 8) {
                    Button { compose(.artwork) } label: {
                        Label("Draw it", systemImage: "paintbrush.pointed.fill").font(.jakarta(13, .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background {
                                Capsule().fill(Theme.candy).shadow(color: Theme.main.opacity(0.28), radius: 6, y: 3)
                            }
                    }
                    Button { compose(.post) } label: {
                        Label("Share", systemImage: "photo.fill").font(.jakarta(13, .bold))
                            .foregroundStyle(Theme.main)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Palette.surface.opacity(0.75), in: Capsule())
                    }
                }
                .buttonStyle(BouncyStyle(scale: 0.93))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: prompt.icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.main)
                .symbolEffect(.bounce, options: .repeat(2), value: float && !reduceMotion)
                .frame(width: 82, height: 82)
                .background(Palette.surface.opacity(0.75), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .padding(.trailing, 4)
        }
        .pastelCard(radius: 24, padding: 18)
        .onAppear { float = true }
        .onDisappear { float = false }
    }
}

// MARK: - What friends are up to

struct HappeningNow: View {
    let posts: [Post]
    let artworks: [Artwork]
    let reels: [Reel]
    let tracks: [Track]
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    struct Item: Identifiable {
        var id: String
        var email: String
        var name: String
        var verb: String
        var icon: String
        var tint: UInt32
        var thumb: String
        var created: String
        var route: Route?
    }

    private var items: [Item] {
        let me = model.me?.email ?? ""
        let following = Set(model.me?.following ?? [])
        let blocked = Set(model.me?.blocked ?? [])
        var all: [Item] = []
        for p in posts.prefix(40) {
            all.append(Item(id: "p" + p.id, email: p.authorEmail, name: p.authorName, verb: p.imageURL.isEmpty ? "shared a thought" : "posted a new picture", icon: "bubble.left.fill", tint: 0xFF7AA2, thumb: p.imageURL, created: p.created, route: .post(p)))
        }
        for a in artworks.prefix(30) {
            all.append(Item(id: "a" + a.id, email: a.authorEmail, name: a.authorName, verb: a.title.isEmpty ? "finished a drawing" : "drew “\(a.title)”", icon: "paintbrush.pointed.fill", tint: 0xB19CFF, thumb: a.imageURL, created: a.created, route: .artwork(a)))
        }
        for r in reels.prefix(20) {
            all.append(Item(id: "r" + r.id, email: r.authorEmail, name: r.authorName, verb: "posted a reel", icon: "play.rectangle.fill", tint: 0xF08A20, thumb: r.coverURL.isEmpty ? (r.pictures.first ?? "") : r.coverURL, created: r.created, route: .reel(r)))
        }
        for t in tracks.prefix(10) {
            let name = model.person(t.authorEmail)?.displayName ?? t.artist
            all.append(Item(id: "t" + t.id, email: t.authorEmail, name: name, verb: "shared “\(t.title)”", icon: "music.note", tint: 0x7CBEFF, thumb: t.coverURL, created: t.created, route: nil))
        }
        let visible = all.filter { $0.email != me && !blocked.contains($0.email) }
        let friends = visible.filter { following.contains($0.email) }
        let pool = friends.count >= 3 ? friends : visible
        return Array(pool.sorted { $0.created > $1.created }.prefix(6))
    }

    var body: some View {
        let list = items
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SectionHeader(icon: "dot.radiowaves.left.and.right", title: "Happening now")
                }
                .overlay(alignment: .topLeading) {
                    Circle().fill(Palette.success).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Palette.success.opacity(0.5), lineWidth: 2).scaleEffect(pulse ? 2.2 : 1).opacity(pulse ? 0 : 1))
                        .offset(x: 28, y: -2)
                        .animation(reduceMotion ? nil : .easeOut(duration: 1.3).repeatCount(2, autoreverses: false), value: pulse)
                }
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        Button {
                            if let route = item.route { path.append(route) } else { path.append(.music) }
                        } label: { row(item) }
                            .buttonStyle(BouncyStyle(scale: 0.98))
                        if i < list.count - 1 { Divider().overlay(Palette.border).padding(.leading, 64) }
                    }
                }
                .sugarCard(radius: 26, padding: 6)
            }
            .onAppear { pulse = !reduceMotion }
        }
    }

    private func row(_ item: Item) -> some View {
        let person = model.person(item.email)
        return HStack(spacing: 12) {
            Avatar(url: person?.picture ?? "", name: person?.displayName ?? item.name, size: 42, online: person?.isOnline ?? false)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: item.icon).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color(hex: item.tint), in: Circle())
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            VStack(alignment: .leading, spacing: 2) {
                (Text(person?.displayName ?? item.name).font(.jakarta(14, .heavy)) + Text(" " + item.verb).font(.jakarta(14, .medium)))
                    .foregroundStyle(Palette.text).lineLimit(2).multilineTextAlignment(.leading)
                Text(Dates.ago(item.created)).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            if !item.thumb.isEmpty {
                RemoteImage(url: item.thumb)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - Trending tags

struct TrendingTags: View {
    let posts: [Post]
    let reels: [Reel]
    var open: (String) -> Void

    private var tags: [(String, Int)] {
        var count: [String: Int] = [:]
        let texts = posts.prefix(150).map { $0.text + " " + $0.title } + reels.map(\.caption)
        for text in texts {
            for tag in Set(Hashtags.find(text)) { count["#" + tag, default: 0] += 1 }
        }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(12).map { ($0.key, $0.value) }
    }

    var body: some View {
        let list = tags
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "number", title: "Trending tags")
                FlowLayout(spacing: 8) {
                    ForEach(Array(list.enumerated()), id: \.element.0) { i, tag in
                        Button { open(tag.0) } label: {
                            HStack(spacing: 5) {
                                if i < 3 { Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0xF08A20)) }
                                Text(tag.0).font(.jakarta(13, .bold)).foregroundStyle(i < 3 ? Theme.main : Palette.text2)
                                Text("\(tag.1)").font(.jakarta(11, .heavy)).foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(i < 3 ? Theme.soft : Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(i < 3 ? Theme.main.opacity(0.25) : Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(BouncyStyle(scale: 0.92))
                    }
                }
            }
        }
    }
}

// MARK: - People you might like

struct SuggestedPeople: View {
    @Binding var path: [Route]
    @Environment(AppModel.self) private var model
    @State private var hidden: Set<String> = []

    private var people: [UserProfile] {
        guard let me = model.me else { return [] }
        let following = Set(me.following)
        let blocked = Set(me.blocked)
        // Friends of friends first, then whoever's online, then the most active.
        var mutual: [String: Int] = [:]
        for email in me.following {
            for other in model.person(email)?.following ?? [] { mutual[other.lowercased(), default: 0] += 1 }
        }
        return model.people.values
            .filter { $0.email != me.email && !following.contains($0.email) && !blocked.contains($0.email) && !hidden.contains($0.email) }
            .sorted {
                let a = (mutual[$0.email] ?? 0) * 10 + ($0.isOnline ? 5 : 0) + min($0.xp / 100, 20)
                let b = (mutual[$1.email] ?? 0) * 10 + ($1.isOnline ? 5 : 0) + min($1.xp / 100, 20)
                return a > b
            }
            .prefix(10).map { $0 }
    }

    var body: some View {
        let list = people
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "person.crop.circle.badge.plus", title: "People you might like") { path.append(.people) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(list, id: \.email) { person in
                            card(person)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: list.map(\.email))
                }
                .scrollClipDisabled()
            }
        }
    }

    private func card(_ person: UserProfile) -> some View {
        VStack(spacing: 8) {
            Button { path.append(.person(person.email)) } label: {
                VStack(spacing: 6) {
                    Avatar(url: person.picture, name: person.displayName, size: 64, online: person.isOnline, nitro: person.isNitro)
                    Text(person.displayName).font(.jakarta(14, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(subtitle(person)).font(.jakarta(11, .semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            .buttonStyle(BouncyStyle(scale: 0.95))
            FollowButton(email: person.email, compact: true)
        }
        .frame(width: 138)
        .padding(.vertical, 14)
        .sugarCard(radius: 24, padding: 0)
        .overlay(alignment: .topTrailing) {
            Button { withMotion(Motion.standard) { _ = hidden.insert(person.email) } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted)
                    .frame(width: 26, height: 26)
            }
            .padding(4)
            .accessibilityLabel("Hide")
        }
    }

    private func subtitle(_ person: UserProfile) -> String {
        if !person.status.isEmpty { return person.status }
        let mutual = (model.me?.following ?? []).filter { model.person($0)?.following.contains(person.email) == true }.count
        if mutual > 0 { return "\(mutual) mutual\(mutual == 1 ? "" : "s")" }
        return person.isOnline ? "Online now" : "New to you"
    }
}

// MARK: - Weekly challenge (Community)

struct WeeklyChallengeCard: View {
    let posts: [Post]
    var active: Bool
    var compose: () -> Void
    var showEntries: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var shine = false
    @State private var editing = false

    private var daysLeft: Int {
        let cal = Calendar.current
        guard let end = cal.dateInterval(of: .weekOfYear, for: Date())?.end else { return 1 }
        return max(1, Int(ceil(end.timeIntervalSinceNow / 86_400)))
    }

    var body: some View {
        Group {
            if let c = DailyContent.challenge {
                card(c)
            } else if model.me?.isAdmin == true {
                Button { editing = true } label: {
                    Label("Add weekly challenges", systemImage: "plus.circle.fill").font(.jakarta(14, .bold)).foregroundStyle(Theme.main)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(BouncyStyle(scale: 0.97))
            }
        }
        .sheet(isPresented: $editing) { DailyContentEditor(kind: .challenges).presentationCornerRadius(30) }
    }

    @ViewBuilder
    private func card(_ c: Challenge) -> some View {
        let entries = posts.filter { Hashtags.find($0.title + " " + $0.text).contains(c.tag) }
        let people = Array(uniqued(entries.map(\.authorEmail)).prefix(4))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: c.icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.main)
                    .frame(width: 46, height: 46)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .symbolEffect(.bounce, value: shine)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Weekly challenge").font(.jakarta(13, .medium)).foregroundStyle(Palette.muted)
                        if model.me?.isAdmin == true { AdminEditChip { editing = true } }
                    }
                    Text(c.title).font(.display(24)).foregroundStyle(Palette.text)
                }
                Spacer(minLength: 0)
                Text(daysLeft == 1 ? "1 day left" : "\(daysLeft) days left")
                    .font(.jakarta(12, .semibold)).foregroundStyle(Theme.main)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Theme.soft, in: Capsule())
            }
            HStack(spacing: 8) {
                if !people.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(people, id: \.self) { email in
                            let p = model.person(email)
                            Avatar(url: p?.picture ?? "", name: p?.displayName ?? "", size: 26)
                                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                        }
                    }
                }
                Text(entries.isEmpty ? "Be the first to join with #\(c.tag)" : "\(entries.count) entr\(entries.count == 1 ? "y" : "ies") · #\(c.tag)")
                    .font(.jakarta(13)).foregroundStyle(Palette.text2).lineLimit(1)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = "#\(c.tag) "
                    model.showToast("#\(c.tag) copied — paste it in your post", icon: "number")
                    compose()
                } label: {
                    Label("Join", systemImage: "plus").font(.jakarta(14, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Theme.main, in: Capsule())
                }
                Button { showEntries(c.tag) } label: {
                    Label(active ? "Showing entries" : "See entries", systemImage: active ? "checkmark" : "square.grid.2x2")
                        .font(.jakarta(14, .semibold)).foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(active ? Theme.soft : Palette.surface2, in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(BouncyStyle(scale: 0.95))
            .motion(Motion.standard, value: active)
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .onAppear { shine = true }
    }
}

// Keeps the first of each value, in order.
private func uniqued(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { seen.insert($0).inserted }
}
