import Network
import SwiftUI

// Watches the internet connection so the app can show Mimi with her
// broken wifi box when it drops, and hide her again when it's back.
@MainActor @Observable
final class Connection {
    static let shared = Connection()

    private(set) var offline = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var pending: Task<Void, Never>?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let down = path.status != .satisfied
            Task { @MainActor in self?.update(down) }
        }
        monitor.start(queue: DispatchQueue(label: "sugerly.connection"))
    }

    private func update(_ down: Bool) {
        pending?.cancel()
        guard down else {
            if offline { withAnimation(.easeOut(duration: 0.3)) { offline = false } }
            return
        }
        // Wait a moment: switching between wifi and mobile data drops the
        // connection for a split second, and that shouldn't flash a notice.
        pending = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { offline = true }
        }
    }
}

// The card that shows while there's no internet inside the app.
struct OfflineNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("MimiOffline")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 58, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No internet").font(.display(20)).foregroundStyle(Palette.text)
                Text("Check your wifi. Sugerly will load again by itself once you're back online.")
                    .font(.jakarta(13, .semibold))
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .frostedFill(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 12, y: 8)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}
