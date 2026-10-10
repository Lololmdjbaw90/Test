import SwiftUI

// A precise alternative to dragging a short overlay on a small iPhone.
struct OverlayTimingEditor: View {
    @Binding var sticker: TextSticker
    let length: Double
    var onSeek: (Double) -> Void
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var minimum: Double { min(0.3, length) }
    private var finish: Double { min(length, sticker.end ?? length) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text timing").font(.display(28))
                    Text(sticker.text.isEmpty ? "Overlay" : sticker.text)
                        .font(.jakarta(14)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GradientButtonStyle(height: 44, fullWidth: false))
            }
            timingRow("Appears", value: Binding(get: { sticker.start }, set: {
                sticker.start = min(max(0, $0), max(0, finish - minimum))
                onSeek(sticker.start)
            }), range: 0...max(0.001, finish - minimum))
            timingRow("Disappears", value: Binding(get: { finish }, set: {
                let end = min(length, max(sticker.start + minimum, $0))
                sticker.end = end >= length ? nil : end
                onSeek(max(sticker.start, end - 0.05))
            }), range: min(length, sticker.start + minimum)...max(length, 0.001))
            Label(String(format: "Visible for %.1f seconds", finish - sticker.start), systemImage: "text.bubble")
                .font(.jakarta(14, .bold)).foregroundStyle(Theme.main)
            Spacer(minLength: 0)
        }
        .padding(24).foregroundStyle(Palette.text).sugarBackground()
        .onDisappear { onDone() }
    }

    private func timingRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.jakarta(15, .bold))
                Spacer()
                Text(ReelTimeline.clock(value.wrappedValue)).font(.jakarta(15, .bold)).monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.1).tint(Theme.main).accessibilityLabel(title)
        }
    }
}
