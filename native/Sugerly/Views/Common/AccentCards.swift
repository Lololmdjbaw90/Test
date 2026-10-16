import SwiftUI

// The colour picker: a small card per colour with Mimi drawn in it. The
// picked one gets a solid edge in its colour and a tick.

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

    private var edgeColor: Color { picked ? main : Palette.border }
    private var edge: StrokeStyle { StrokeStyle(lineWidth: picked ? 2 : 1) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(light.opacity(0.18))
                art()
                    .frame(height: height - 16)
                    .padding(.bottom, 7)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                        .transition(.opacity)
                }
            }

            Text(title)
                .font(.jakarta(12, picked ? .semibold : .medium))
                .foregroundStyle(picked ? Palette.text : Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .animation(Motion.fade, value: picked)
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
