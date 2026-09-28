import Foundation
import UIKit
import AVFoundation
import CallKit
import WebRTC

// Makes a voice channel a real iOS call (CallKit): the green call pill in the
// status bar, lock-screen controls, it keeps going in the background and
// other calls put it on hold properly. If CallKit isn't available the voice
// channel still works — the app then runs the audio itself.
@MainActor
final class CallBridge: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private let controller = CXCallController()
    private(set) var callId: UUID?
    var onMute: ((Bool) -> Void)?
    var onEnd: (() -> Void)?

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        if let icon = UIImage(systemName: "heart.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 40)).pngData() {
            config.iconTemplateImageData = icon
        }
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // Starts the system call. Returns false if iOS said no.
    func start(title: String) async -> Bool {
        let id = UUID()
        let handle = CXHandle(type: .generic, value: title)
        let action = CXStartCallAction(call: id, handle: handle)
        action.isVideo = false
        callId = id
        do {
            try await controller.request(CXTransaction(action: action))
        } catch {
            callId = nil
            return false
        }
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.localizedCallerName = title
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportCall(with: id, updated: update)
        provider.reportOutgoingCall(with: id, startedConnectingAt: Date())
        return true
    }

    func connected() {
        guard let callId else { return }
        provider.reportOutgoingCall(with: callId, connectedAt: Date())
    }

    func setMuted(_ muted: Bool) {
        guard let callId else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: callId, muted: muted))) { _ in }
    }

    func end() {
        guard let id = callId else { return }
        callId = nil
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { _ in }
    }

    // MARK: CXProviderDelegate

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            guard self.callId != nil else { return }
            self.callId = nil
            self.onEnd?()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        action.fulfill()
        // Only when it was ended from the system (lock screen / call UI).
        Task { @MainActor in
            guard self.callId == id else { return }
            self.callId = nil
            self.onEnd?()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let muted = action.isMuted
        action.fulfill()
        Task { @MainActor in self.onMute?(muted) }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
}
