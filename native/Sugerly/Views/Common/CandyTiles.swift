import SwiftUI

// Shortcuts as clean white tiles: a small candy square with the place's
// icon and its name in dark ink underneath, three to a row (Home and the
// menu). The colour sits in the icon only, so a page of them reads calm
// instead of a wall of pink.
struct CandyShortcutGrid: View {
    struct Item {
        let title: String
        let icon: String
        let candy: Candy
        let route: Route
    }
    let items: [Item]
    // They pop in one after another once this turns on.
    var shown = true
    var open: (Route) -> Void
    @State private var hops: [Int] = Array(repeating: 0, count: 8)
    @Environment(\.flat) private var flat

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.title) { i, item in
                Button { open(item.route) } label: { tile(item, hop: hops[i % hops.count]) }
                    .buttonStyle(BouncyStyle(scale: 0.92))
                    .accessibilityLabel(item.title)
                    .scaleEffect(shown || Motion.reduced ? 1 : 0.7)
                    .opacity(shown || Motion.reduced ? 1 : 0)
                    .animation(Motion.reduced ? nil : Motion.playful.delay(0.12 + Double(min(i, 8)) * 0.05), value: shown)
            }
        }
        .task {
            // Every few seconds one icon hops, so Home never sits still (not
            // in the menu, which keeps still).
            guard Motion.ambient, !Motion.reduced, !flat, !items.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                if !Motion.paused { hops[Int.random(in: 0..<items.count)] += 1 }
            }
        }
    }

    private func tile(_ item: Item, hop: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            CandyTile(icon: item.icon, candy: item.candy, size: 38)
                .symbolEffect(.bounce, value: hop)
            Spacer(minLength: 10)
            // Room for two lines on every tile (so "Customize bunny" fits and
            // the tiles stay the same height).
            Text(item.title)
                .font(.jakarta(13, .semibold)).foregroundStyle(Palette.text)
                .lineLimit(2).minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .bottomLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background {
            shape.fill(Palette.surface)
                .softShadow(Palette.shadow, radius: 4, y: 2)
        }
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(shape)
    }
}

// A bright banner at the top of a page: its name, a line about it, an
// optional button, and a big tilted icon, on a candy gradient with soft
// bubbles and a passing shine.
struct PageHero: View {
    let title: String
    let subtitle: String
    let icon: String
    var candy: Candy = .berry
    var themed = false
    var actionTitle: String? = nil
    var actionIcon: String = "plus"
    var action: (() -> Void)? = nil
    @State private var shown = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(25)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(subtitle).font(.jakarta(13, .medium)).foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionIcon)
                            .font(.jakarta(13, .bold)).foregroundStyle(candy.color)
                            .lineLimit(1)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .buttonStyle(BouncyStyle(scale: 0.93))
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: shown)
                .frame(width: 70, height: 70)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .rotationEffect(.degrees(shown ? -8 : 0))
                .animation(Motion.reduced ? nil : Motion.playful.delay(0.2), value: shown)
                .accessibilityHidden(true)
        }
        .padding(18)
        .background {
            shape.fill(themed ? Theme.gradient : candy.gradient)
                .overlay {
                    GeometryReader { geo in
                        Circle().fill(.white.opacity(0.14)).frame(width: geo.size.height * 1.6)
                            .offset(x: geo.size.width * 0.6, y: -geo.size.height * 0.4)
                        Circle().fill(.white.opacity(0.1)).frame(width: geo.size.height * 0.7)
                            .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.62)
                    }
                    .clipShape(shape)
                }
                // (No corner sparkles here: they'd sit on the big icon.)
                .overlay { ShineSweep(every: 5.5, strength: 0.28).clipShape(shape) }
                .background(shape.fill(themed ? Theme.main.opacity(0.15) : candy.color.opacity(0.15)).offset(y: 3))
        }
        .onAppear { shown = true }
    }
}

// The big title at the top of a main page: its name in Lilita One (a round,
// chunky font that comes with the app) filled with your colour's candy
// gradient, a little tilted sticker of its icon that hops in, and a line
// about the page underneath. With a search, a round button on the right
// grows into the search bar (and shrinks back on Cancel), the same on every
// page, so there's only ever one search.
struct PageTitle: View {
    let title: String
    var subtitle = ""
    let icon: String
    var candy: Candy = .berry
    var search: Binding<String>? = nil
    var prompt = "Search"
    // Return pressed (pages that search everything open the results).
    var onSubmit: (() -> Void)? = nil
    @State private var shown = false
    @State private var searching = false
    @FocusState private var focused: Bool
    @Namespace private var morph

    var body: some View {
        ZStack {
            if searching, let search {
                field(search)
                    .transition(.opacity)
            } else {
                heading
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 56)
        .animation(Motion.pick(.spring(response: 0.36, dampingFraction: 0.86)), value: searching)
        .onAppear {
            guard !shown else { return }
            withAnimation(Motion.reduced ? nil : Motion.playful.delay(0.1)) { shown = true }
        }
    }

    private var heading: some View {
        let sticker = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: shown)
                .frame(width: 44, height: 44)
                .background(Theme.gradient, in: sticker)
                .overlay(sticker.strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                .shadow(color: Theme.glow(0.35), radius: 6, y: 3)
                .rotationEffect(.degrees(shown ? -7 : 0))
            VStack(alignment: .leading, spacing: 5) {
                StickerTitle(text: title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.jakarta(13, .semibold)).foregroundStyle(Palette.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if search != nil {
                Button(action: open) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.main)
                        .frame(width: 44, height: 44)
                        .background {
                            Capsule().fill(Palette.surface)
                                .matchedGeometryEffect(id: "search", in: morph)
                                .shadow(color: Palette.shadow, radius: 6, y: 2)
                        }
                        .overlay(Capsule().strokeBorder(Theme.main.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(BouncyStyle(scale: 0.88))
                .accessibilityLabel("Search")
            }
        }
        .padding(.horizontal, 2)
    }

    private func field(_ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.main)
                TextField(prompt, text: text)
                    .font(.jakarta(16))
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { onSubmit?() }
                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background {
                Capsule().fill(Palette.surface)
                    .matchedGeometryEffect(id: "search", in: morph)
                    .shadow(color: Palette.shadow, radius: 6, y: 2)
            }
            .overlay(Capsule().strokeBorder(Theme.main.opacity(0.25), lineWidth: 1))
            Button("Cancel", action: close)
                .font(.jakarta(15, .semibold))
                .foregroundStyle(Theme.main)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    private func open() {
        searching = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            focused = true
        }
    }

    private func close() {
        search?.wrappedValue = ""
        focused = false
        searching = false
    }
}

extension View {
    /// A page that shows a big PageTitle: the top bar keeps the name (for the
    /// back button and VoiceOver) and shows the Sugerly logo in the middle
    /// instead of the name a second time.
    func quietTitle(_ title: String) -> some View {
        modifier(QuietTitle(title: title))
    }
}

private struct QuietTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        // The page itself has its accessible PageTitle. The shared toolbar
        // owns the brand, preventing two competing principal items.
        content.navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
}
