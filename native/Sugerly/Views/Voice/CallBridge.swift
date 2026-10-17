import Foundation
import UIKit
import AVFoundation
import CallKit
import WebRTC

// Makes a voice channel a real iOS call (CallKit): the green call pill in the
// status bar, lock-screen controls, it keeps going in the background and
// other calls put it on hold properly. If CallKit isn't available the voice
// channel still works — the app then runs the audio itself.
//
// It also shows calls that ring you while Sugerly is closed (see
// IncomingCalls): iOS's own incoming-call screen, and answering there joins
// the call.
@MainActor
final class CallBridge: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private let controller = CXCallController()
    private(set) var callId: UUID?
    private var outgoing = false
    // iPhone's call timer starts once, when the other person first connects.
    private var reportedConnected = false
    var onMute: ((Bool) -> Void)?
    var onEnd: (() -> Void)?
    // A ringing call was answered / declined on iOS's call screen (Sugerly call id).
    var onAnswer: ((String) -> Void)?
    var onDecline: ((String) -> Void)?

    // Calls ringing on iOS's call screen: CallKit id → Sugerly call id.
    private var ringing: [UUID: String] = [:]
    // Answered there, waiting for the voice engine to take it over.
    private var answered: UUID?

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
        outgoing = true
        reportedConnected = false
        do {
            try await controller.request(CXTransaction(action: action))
        } catch {
            callId = nil
            outgoing = false
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

    // Takes over a call answered on iOS's call screen. False if there isn't one.
    func adoptAnswered() -> Bool {
        guard let id = answered else { return false }
        answered = nil
        callId = id
        outgoing = false
        reportedConnected = false
        return true
    }

    func connected() {
        guard let callId, outgoing, !reportedConnected else { return }
        reportedConnected = true
        provider.reportOutgoingCall(with: callId, connectedAt: Date())
    }

    func setMuted(_ muted: Bool) {
        guard let callId else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: callId, muted: muted))) { _ in }
    }

    func end() {
        guard let id = callId else { return }
        callId = nil
        outgoing = false
        reportedConnected = false
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { _ in }
    }

    // MARK: ringing on iOS's call screen

    // iOS insists every call push shows the call screen straight away.
    @discardableResult
    func reportIncoming(callId: String, title: String, completion: @escaping (UUID, Error?) -> Void = { _, _ in }) -> UUID {
        let id = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: title)
        update.localizedCallerName = title
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        ringing[id] = callId
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            Task { @MainActor in
                if error != nil { self?.ringing[id] = nil }
                completion(id, error)
            }
        }
        return id
    }

    // Ends one reported call at once (a repeated or stale call push).
    func endReported(_ id: UUID, reason: CXCallEndedReason) {
        ringing[id] = nil
        provider.reportCall(with: id, endedAt: Date(), reason: reason)
    }

    func isRinging(_ callId: String) -> Bool { ringing.values.contains(callId) }

    // Stops a ringing call that ended elsewhere (hung up, picked up on
    // another phone, or nobody answered).
    func stopRinging(_ callId: String, reason: CXCallEndedReason) {
        for (id, call) in ringing where call == callId {
            ringing[id] = nil
            provider.reportCall(with: id, endedAt: Date(), reason: reason)
        }
    }

    // MARK: CXProviderDelegate

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.ringing = [:]
            self.answered = nil
            guard self.callId != nil else { return }
            self.callId = nil
            self.onEnd?()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Self.prepareAudio()
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Self.prepareAudio()
        let id = action.callUUID
        action.fulfill()
        Task { @MainActor in
            guard let call = self.ringing.removeValue(forKey: id) else { return }
            self.answered = id
            self.onAnswer?(call)
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        action.fulfill()
        Task { @MainActor in
            // Declined while it rang.
            if let call = self.ringing.removeValue(forKey: id) {
                self.onDecline?(call)
                return
            }
            if self.answered == id { self.answered = nil }
            // Only when it was ended from the system (lock screen / call UI).
            guard self.callId == id else { return }
            self.callId = nil
            self.outgoing = false
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

    private nonisolated static func prepareAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
    }
}
