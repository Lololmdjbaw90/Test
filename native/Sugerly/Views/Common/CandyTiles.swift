import SwiftUI

// Shortcuts as candy tiles with a white icon and the place's name, three
// to a row (Home and the menu).
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
            // Every few seconds one icon hops, so Home never sits still.
            guard Motion.ambient, !Motion.reduced, !items.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                hops[Int.random(in: 0..<items.count)] += 1
            }
        }
    }

    private func tile(_ item: Item, hop: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: hop)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 12)
            Text(item.title)
                .font(.jakarta(13, .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background {
            shape.fill(item.candy.gradient)
                .overlay {
                    // A soft bubble in the corner and a shine along the top.
                    GeometryReader { geo in
                        Circle().fill(.white.opacity(0.16))
                            .frame(width: geo.size.width * 0.7)
                            .offset(x: geo.size.width * 0.5, y: geo.size.height * 0.35)
                    }
                    .clipShape(shape)
                }
                .overlay(shape.fill(LinearGradient(colors: [Palette.rim(0.35), .clear], startPoint: .top, endPoint: .center)).padding(1))
                .shadow(color: item.candy.color.softGlow(0.35), radius: 8, y: 4)
        }
        .contentShape(shape)
    }
}

// A bright banner at the top of a page: its name, a line about it, an
// optional button, and a big tilted icon, on a candy gradient with neat
// twinkles and a passing shine.
struct PageHero: View {
    let title: String
    let subtitle: String
    let icon: String
    var candy: Candy = .berry
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
            shape.fill(candy.gradient)
                .overlay {
                    GeometryReader { geo in
                        Circle().fill(.white.opacity(0.14)).frame(width: geo.size.height * 1.6)
                            .offset(x: geo.size.width * 0.6, y: -geo.size.height * 0.4)
                        Circle().fill(.white.opacity(0.1)).frame(width: geo.size.height * 0.7)
                            .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.62)
                    }
                    .clipShape(shape)
                }
                .overlay { TwinkleField(colors: [.white, UIColor(hex: 0xFFF1A8)]).clipShape(shape) }
                .overlay { ShineSweep(every: 5.5, strength: 0.28).clipShape(shape) }
                .shadow(color: candy.color.softGlow(0.35), radius: 14, y: 6)
        }
        .onAppear { shown = true }
    }
}
