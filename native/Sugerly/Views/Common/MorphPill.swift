import SwiftUI

// A pill button that morphs between two states (Follow ⇄ Following,
// Join ⇄ Joined…). In one smooth change: the solid accent fades to a plain outline,
// the pill settles to the width of the new words, the icon morphs (plus into
// a tick) and the words blur from one into the other. Tapping again half-way
// simply turns it back from where it is.
struct MorphPill: View {
    enum Size { case small, regular, large }

    let on: Bool
    let offTitle: String
    let onTitle: String
    var offIcon: String? = "plus"
    var onIcon: String? = "checkmark"
    var size: Size = .regular
    var fullWidth = false
    var action: () -> Void

    private var height: CGFloat {
        switch size {
        case .small: return 28
        case .regular: return 34
        case .large: return 44
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 12
        case .regular: return 13
        case .large: return 15
        }
    }

    private var icon: String? { on ? onIcon : offIcon }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                // Both words share one spot while they swap, so the pill
                // grows or shrinks smoothly instead of jumping.
                ZStack {
                    Text(on ? onTitle : offTitle)
                        .lineLimit(1)
                        .fixedSize()
                        .id(on)
                        .transition(.blurSwap)
                }
            }
            .font(.jakarta(fontSize, .semibold))
            .foregroundStyle(on ? Palette.text : Color.white)
            .padding(.horizontal, size == .small ? 12 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background {
                ZStack {
                    Capsule().fill(Palette.surface)
                        .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    Capsule().fill(Theme.main)
                        .opacity(on ? 0 : 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SoftPressStyle(scale: 0.96))
        .sensoryFeedback(.impact(weight: .light), trigger: on)
        .motion(.spring(response: 0.3, dampingFraction: 1), value: on)
        .accessibilityLabel(on ? onTitle : offTitle)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
