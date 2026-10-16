import SwiftUI
import UIKit

// The social bits of Home: stories, a "what are you making" bar, today's art
// prompt, trending tags and people to follow.

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
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.main, in: Circle())
                                    .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 2))
                            }
                        Text("Your reel").font(.jakarta(11, .medium)).foregroundStyle(Palette.text2)
                    }
                    .frame(width: 76)
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("New reel")
                ForEach(stories) { story in
                    bubble(story).transition(.opacity).swipeFade()
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
        let name = person?.displayName ?? story.reel?.authorName ?? ""
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
                Avatar(url: person?.picture ?? story.reel?.authorPicture ?? "", name: name, size: 62)
                    .padding(4)
                    .background {
                        // A ring in your colour for a reel you haven't watched,
                        // green for a friend who's online, grey otherwise.
                        if story.reel == nil {
                            Circle().strokeBorder(Palette.success, lineWidth: 2)
                        } else if fresh {
                            Circle().strokeBorder(Theme.main, lineWidth: 2.5)
                        } else {
                            Circle().strokeBorder(Palette.border, lineWidth: 1.5)
                        }
                    }
                Text(name).font(.jakarta(11, fresh ? .semibold : .regular))
                    .foregroundStyle(fresh ? Palette.text : Palette.text2).lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(story.reel == nil ? "\(name), online" : fresh ? "\(name), new reel" : "\(name), reel")
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
                    Avatar(url: model.me?.picture ?? "", name: model.me?.displayName ?? "", size: 40)
                    Text("What are you making today?")
                        .font(.jakarta(15)).foregroundStyle(Palette.muted)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Palette.surface2, in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle(scale: 0.99))
            .accessibilityLabel("Write a post")
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 0) {
                action("Post", "text.bubble") { compose(.post) }
                action("Reel", "video") { compose(.reel) }
                action("Drawing", "paintbrush.pointed") { compose(.artwork) }
                action("Song", "music.note") { compose(.track) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .sugarCard(radius: 16)
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.text2)
                Text(title).font(.jakarta(13, .medium)).foregroundStyle(Palette.text2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel("New \(title.lowercased())")
    }
}

// MARK: - Today's art prompt

struct ArtPromptCard: View {
    var compose: (Composer) -> Void
    @Environment(AppModel.self) private var model
    @State private var editing = false

    private var hoursLeft: Int {
        let end = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return max(1, Int(ceil(end.timeIntervalSinceNow / 3600)))
    }

    var body: some View {
        if let prompt = DailyContent.prompt {
            card(prompt)
                .sheet(isPresented: $editing) { DailyContentEditor(kind: .prompts).presentationCornerRadius(24) }
        } else if model.me?.isAdmin == true {
            Button { editing = true } label: {
                Label("Add daily art prompts", systemImage: "plus").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text2)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(SoftPressStyle())
            .sheet(isPresented: $editing) { DailyContentEditor(kind: .prompts).presentationCornerRadius(24) }
        }
    }

    private func card(_ prompt: ArtPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: prompt.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.main)
                    .frame(width: 44, height: 44)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Today's prompt").font(.jakarta(13, .medium)).foregroundStyle(Palette.muted)
                        if model.me?.isAdmin == true { AdminEditChip { editing = true } }
                    }
                    Text(prompt.text).font(.jakarta(19, .semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DailyContent.promptPinned ? "Picked by the Sugerly team" : "New prompt in \(hoursLeft)h")
                        .font(.jakarta(12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { compose(.artwork) } label: {
                    Label("Draw it", systemImage: "paintbrush.pointed")
                }
                .buttonStyle(GradientButtonStyle(height: 40))
                Button { compose(.post) } label: {
                    Label("Share", systemImage: "photo")
                }
                .buttonStyle(OutlineButtonStyle(height: 40, fullWidth: true))
            }
        }
        .padding(16)
        .sugarCard(radius: 16)
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
                            HStack(spacing: 6) {
                                Text(tag.0).font(.jakarta(13, .medium)).foregroundStyle(i < 3 ? Palette.text : Palette.text2)
                                Text("\(tag.1)").font(.jakarta(12)).foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(i < 3 ? Palette.borderStrong : Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(SoftPressStyle())
                        .accessibilityLabel("\(tag.0), \(tag.1) posts")
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
                let a = (mutual[$0.email.lowercased()] ?? 0) * 10 + ($0.isOnline ? 5 : 0) + min($0.xp / 100, 20)
                let b = (mutual[$1.email.lowercased()] ?? 0) * 10 + ($1.isOnline ? 5 : 0) + min($1.xp / 100, 20)
                // Same score: by name, so the row doesn't reshuffle on every refresh.
                return a != b ? a > b : $0.displayName.lowercased() < $1.displayName.lowercased()
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
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 6)
                    .animation(Motion.standard, value: list.map(\.email))
                }
                .scrollClipDisabled()
            }
        }
    }

    private func card(_ person: UserProfile) -> some View {
        VStack(spacing: 8) {
            Button { path.append(.person(person.email)) } label: {
                VStack(spacing: 4) {
                    Avatar(url: person.picture, name: person.displayName, size: 60, online: person.isOnline, nitro: person.isNitro)
                        .padding(.bottom, 2)
                    Text(person.displayName).font(.jakarta(14, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(subtitle(person)).font(.jakarta(12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(SoftPressStyle())
            FollowButton(email: person.email, compact: true)
        }
        .frame(width: 138)
        .padding(.vertical, 14)
        .sugarCard(radius: 16, padding: 0)
        .overlay(alignment: .topTrailing) {
            Button { withMotion(Motion.standard) { _ = hidden.insert(person.email) } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .padding(2)
            .accessibilityLabel("Hide \(person.displayName)")
        }
    }

    private func subtitle(_ person: UserProfile) -> String {
        if !person.status.isEmpty { return person.status }
        let mutual = (model.me?.following ?? []).filter { model.person($0)?.following.contains(person.email) == true }.count
        if mutual > 0 { return "\(mutual) mutual\(mutual == 1 ? "" : "s")" }
        return person.isOnline ? "Online now" : "New to you"
    }
}
