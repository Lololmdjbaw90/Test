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
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    #if DEBUG
    @ObservationIgnored private var recordingOverride: Bool?
    func simulateRecording(_ value: Bool) { recordingOverride = value; refresh() }
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
        var captured = UIScreen.screens.contains { $0.isCaptured }
        #if DEBUG
        captured = recordingOverride ?? captured
        #endif
        recording = captured
        let heat = ProcessInfo.processInfo.thermalState
        limited = captured || ProcessInfo.processInfo.isLowPowerModeEnabled || heat == .serious || heat == .critical
    }
}
