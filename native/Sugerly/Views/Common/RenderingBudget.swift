import SwiftUI
import UIKit

// Recording/mirroring and thermal pressure share the compositor with the app.
// Shed decoration, not user video, calls, or touch handling. No polling timer.
@MainActor
@Observable
final class RenderingBudget {
    static let shared = RenderingBudget()
    private(set) var recording = false
    private(set) var limited = false
    @ObservationIgnored private var capturedScenes: Set<UUID> = []
    func sceneCapture(_ captured: Bool, id: UUID) {
        if captured { capturedScenes.insert(id) } else { capturedScenes.remove(id) }
        refresh()
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    #if DEBUG
    @ObservationIgnored private var recordingOverride: Bool?
    func simulateRecording(_ value: Bool?) { recordingOverride = value; refresh() }
    #endif

    private init() {
        refresh()
        for name in [UIScreen.capturedDidChangeNotification, UIApplication.didBecomeActiveNotification,
                     ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    private func refresh() {
        var captured = !capturedScenes.isEmpty || UIScreen.screens.contains { $0.isCaptured }
        #if DEBUG
        captured = recordingOverride ?? captured
        #endif
        recording = captured
        let heat = ProcessInfo.processInfo.thermalState
        limited = captured || ProcessInfo.processInfo.isLowPowerModeEnabled || heat == .serious || heat == .critical
    }
}

// Observe the scene, including a recording already running before app launch.
struct CaptureBudgetObserver: ViewModifier {
    @Environment(\.isSceneCaptured) private var captured
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .onChange(of: captured, initial: true) { _, value in
                RenderingBudget.shared.sceneCapture(value, id: id)
            }
            .onDisappear { RenderingBudget.shared.sceneCapture(false, id: id) }
    }
}

extension View {
    // Keep colors and a small offset shadow; omit the blur kernel during capture.
    func budgetShadow(color: Color = .black.opacity(0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        shadow(color: RenderingBudget.shared.limited ? color.opacity(0.45) : color,
               radius: RenderingBudget.shared.limited ? 0 : radius, x: x, y: y)
    }
}
