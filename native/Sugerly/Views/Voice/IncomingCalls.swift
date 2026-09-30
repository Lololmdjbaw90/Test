import Foundation
import UIKit
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
        } catch {
            if (try? await FS.create("PushToken", fields, id: email)) != nil { uploaded = key }
        }
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
        MainActor.assumeIsolated { self.ring(info) }
        completion()
    }

    // MARK: ringing

    private func ring(_ info: [AnyHashable: Any]) {
        let callId = info["call_id"] as? String ?? ""
        let group = (info["is_group"] as? Bool) ?? false
        let groupName = info["group_name"] as? String ?? ""
        let caller = info["caller_name"] as? String ?? ""
        let title = group ? (groupName.isEmpty ? "Group call" : groupName) : (caller.isEmpty ? "Sugerly call" : caller)
        let bridge = VoiceEngine.shared.bridge
        let calls = CallCenter.shared
        // iOS requires every call push to show the call screen, even a
        // repeated one or one you're already in; those end straight away.
        let repeated = callId.isEmpty || bridge.isRinging(callId) || calls.current?.id == callId
        let reported = bridge.reportIncoming(callId: repeated ? "" : callId, title: title)
        if repeated {
            bridge.endReported(reported, reason: .remoteEnded)
            return
        }
        // iPhone's call screen rings now; the in-app banner steps aside.
        calls.systemRinging(callId)
        watch(callId)
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
