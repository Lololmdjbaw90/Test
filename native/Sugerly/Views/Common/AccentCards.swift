import SwiftUI

// The colour picker: a little sketchbook card per colour with Mimi drawn in
// it, instead of plain gradient dots. The picked one gets a solid edge and a
// check sticker; the others sit on a dashed edge.

extension Accent {
    var mimi: String { "Mimi\(rawValue.capitalized)" }
}

struct AccentCard<Art: View>: View {
    let title: String
    let main: Color
    let light: Color
    let picked: Bool
    var height: CGFloat = 78
    @ViewBuilder var art: () -> Art

    private var edgeColor: Color { picked ? main : light.opacity(0.7) }
    private var edge: StrokeStyle { picked ? StrokeStyle(lineWidth: 2.5) : StrokeStyle(lineWidth: 1.4, dash: [5, 4]) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(light.opacity(picked ? 0.3 : 0.16))
                CardDots(color: main.opacity(picked ? 0.2 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                // a soft "floor" shadow under Mimi
                Ellipse().fill(main.opacity(0.18))
                    .frame(width: height * 0.42, height: 6)
                    .padding(.bottom, 5)
                art()
                    .frame(height: height - 16)
                    .padding(.bottom, 7)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(edgeColor, style: edge)
            }
            .overlay(alignment: .topTrailing) {
                if picked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(main, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2.5))
                        .offset(x: 6, y: -6)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .shadow(color: main.opacity(picked ? 0.28 : 0), radius: 10, y: 5)

            Text(title)
                .font(.jakarta(12, .heavy))
                .foregroundStyle(picked ? main : Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .animation(Motion.reduced ? nil : .spring(response: 0.32, dampingFraction: 0.7), value: picked)
        .contentShape(Rectangle())
    }
}

extension AccentCard where Art == AccentMimi {
    init(accent: Accent, picked: Bool, height: CGFloat = 78) {
        self.init(title: accent.label, main: accent.main, light: accent.light, picked: picked, height: height) {
            AccentMimi(name: accent.mimi, picked: picked)
        }
    }
}

// Mimi stays still: she only fades a touch brighter when picked.
struct AccentMimi: View {
    let name: String
    let picked: Bool
    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .opacity(picked ? 1 : 0.82)
            .accessibilityHidden(true)
    }
}

private struct CardDots: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 11
            var y: CGFloat = gap / 2
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? gap / 2 : gap
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(color))
                    x += gap
                }
                y += gap
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
