import Foundation
import UIKit
import SwiftUI
import PushKit
import CallKit

// Calls that reach you while Sugerly is closed or in the background.
//
// The phone gets a call-only push address from Apple (PushKit "VoIP") and
// saves it in PushToken/<your email>, which only our server can read. When
// someone calls you, their app asks our server (netlify/functions/call-ring)
// to send that push; iOS then wakes Sugerly, which shows iPhone's own
// incoming-call screen. Answering there joins the call, even from the lock
// screen without opening the app.
@MainActor
final class IncomingCalls: NSObject, PKPushRegistryDelegate {
    static let shared = IncomingCalls()

    private let registry = PKPushRegistry(queue: .main)
    private(set) var token: String?
    private var watchers: [String: Task<Void, Never>] = [:]
    private var uploaded = ""
    // Why saving this phone's call address last failed (shown in Settings).
    private(set) var lastProblem: String?

    // For Settings: can this phone be rung while Sugerly is closed?
    enum Readiness: Equatable { case ready, saving, noAddress, problem(String) }
    var readiness: Readiness {
        guard let token else { return .noAddress }
        let email = AuthClient.shared.email ?? ""
        if !email.isEmpty, uploaded == "\(email)|\(token)" { return .ready }
        if let lastProblem { return .problem(lastProblem) }
        return .saving
    }

    #if DEBUG
    private static let environment = "sandbox"
    #else
    private static let environment = "production"
    #endif

    // At launch, so a call push that wakes the app is handled.
    func start() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    // Saves this phone's push address for the signed-in account.
    func upload() async {
        let auth = AuthClient.shared
        guard auth.hasSession, let email = auth.email, !email.isEmpty, let token else { return }
        let key = "\(email)|\(token)"
        guard key != uploaded else { return }
        let fields: Doc = ["email": email, "uid": auth.uid ?? "", "voip_token": token, "env": Self.environment,
                           "platform": "ios", "updated_date": FS.nowISO()]
        do {
            try await FS.update("PushToken", email, fields)
            uploaded = key
            lastProblem = nil
        } catch {
            do {
                try await FS.create("PushToken", fields, id: email)
                uploaded = key
                lastProblem = nil
            } catch {
                lastProblem = (error as? APIError)?.message ?? error.localizedDescription
            }
        }
    }

    // Settings → "Check": asks Apple again and saves the address again.
    func recheck() async {
        if token == nil {
            registry.desiredPushTypes = []
            registry.desiredPushTypes = [.voIP]
            try? await Task.sleep(for: .seconds(2))
        }
        uploaded = ""
        await upload()
    }

    // Logging out: calls for that account stop coming to this phone.
    func forget() async {
        guard let email = AuthClient.shared.email, !email.isEmpty else { return }
        try? await FS.delete("PushToken", email)
        uploaded = ""
    }

    // MARK: PKPushRegistryDelegate

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        let hex = credentials.token.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated {
            self.token = hex
            Task { await self.upload() }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        MainActor.assumeIsolated {
            self.token = nil
            Task { await self.forget() }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                                  for type: PKPushType, completion: @escaping () -> Void) {
        let info = payload.dictionaryPayload
        guard type == .voIP else { completion(); return }
        // Finish the PushKit delivery only after CallKit finishes reporting.
        MainActor.assumeIsolated { self.ring(info, completion: completion) }
    }

    // MARK: ringing

    private func ring(_ info: [AnyHashable: Any], completion: @escaping () -> Void) {
        let callId = info["call_id"] as? String ?? ""
        let group = (info["is_group"] as? Bool) ?? false
        let groupName = info["group_name"] as? String ?? ""
        let caller = info["caller_name"] as? String ?? ""
        let title = group ? (groupName.isEmpty ? "Group call" : groupName) : (caller.isEmpty ? "Sugerly call" : caller)
        let bridge = VoiceEngine.shared.bridge
        let calls = CallCenter.shared
        // iOS requires every call push to show the call screen, even a
        // repeated one or one you're already in; those end straight away.
        let startedAt = (info["started_at"] as? NSNumber)?.doubleValue ?? 0
        let now = Date().timeIntervalSince1970 * 1000
        let expired = startedAt <= 0 || now - startedAt >= CallCenter.ringMs || startedAt - now > 5_000
        let repeated = callId.isEmpty || expired || !AuthClient.shared.hasSession || bridge.isRinging(callId) || calls.current?.id == callId
        bridge.reportIncoming(callId: repeated ? "" : callId, title: title) { [weak self] reported, error in
            defer { completion() }
            guard error == nil else { return }
            if repeated {
                bridge.endReported(reported, reason: .remoteEnded)
                return
            }
            calls.systemRinging(callId)
            self?.watch(callId)
        }
    }

    // While it rings: stop when the caller hangs up, someone else picks up
    // (a group call on another phone of yours), or nobody answers.
    private func watch(_ callId: String) {
        watchers[callId]?.cancel()
        watchers[callId] = Task { [weak self] in
            let bridge = VoiceEngine.shared.bridge
            let started = Date()
            while !Task.isCancelled, bridge.isRinging(callId) {
                try? await Task.sleep(for: .seconds(2))
                guard bridge.isRinging(callId) else { break }
                if Date().timeIntervalSince(started) > CallCenter.ringMs / 1000 + 5 {
                    bridge.stopRinging(callId, reason: .unanswered)
                    break
                }
                guard let doc = try? await FS.get("Call", callId) else { continue }
                let call = CallInfo(doc)
                let me = AuthClient.shared.email ?? ""
                if call.status == "ended" || (!call.ringing && call.status == "ringing") {
                    bridge.stopRinging(callId, reason: .remoteEnded)
                } else if call.declinedBy.contains(me) {
                    bridge.stopRinging(callId, reason: .declinedElsewhere)
                } else if call.joined.contains(me) {
                    bridge.stopRinging(callId, reason: .answeredElsewhere)
                }
            }
            self?.watchers[callId] = nil
        }
    }
}

// Settings: can this phone ring while Sugerly is closed? With a Check button
// that asks Apple for the call address again and saves it again.
struct CallReadinessRow: View {
    @State private var state: IncomingCalls.Readiness = .saving
    @State private var checking = false

    var body: some View {
        HStack(spacing: 8) {
            IconRow(title: "Calls with Sugerly closed", detail: detail, icon: state == .ready ? "checkmark.circle.fill" : "phone.fill",
                    colors: state == .ready ? [0x5FD3B0, 0x16A37F] : [0xFFAA80, 0xEE6E40])
            Button {
                Task {
                    checking = true
                    await IncomingCalls.shared.recheck()
                    withMotion(Motion.standard) { state = IncomingCalls.shared.readiness }
                    checking = false
                }
            } label: {
                if checking { ProgressView().controlSize(.small) } else { Text("Check") }
            }
            .buttonStyle(OutlineButtonStyle(height: 34))
            .disabled(checking)
        }
        .task { state = IncomingCalls.shared.readiness }
    }

    private var detail: String {
        switch state {
        case .ready: return "Ready: this phone rings even when Sugerly is closed."
        case .saving: return "Saving this phone's call address… tap Check."
        case .noAddress: return "Apple hasn't given this phone a call address yet. Check your internet, then tap Check."
        case .problem(let why): return "Couldn't save this phone's call address: \(why)"
        }
    }
}
