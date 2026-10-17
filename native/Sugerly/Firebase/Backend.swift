import Foundation

// Sugerly's own server: login codes, card payments, call ringing and the call
// relay (the code in netlify/functions). It runs on Firebase now; the Netlify
// copies still answer when Firebase can't, so the app works before, during
// and after the move.
enum Backend {
    static let bases = [
        "https://us-central1-\(FirebaseConfig.projectId).cloudfunctions.net/api",
        "https://sugerly.netlify.app/.netlify/functions",
        // Netlify keeps building this preview copy even when the live site
        // is out of credits.
        "https://deploy-preview-2--sugerly.netlify.app/.netlify/functions",
    ]

    /// Sends `body` to the server's `name` part. Only an answer with Sugerly's
    /// own JSON counts: an address without the server (not deployed yet, out
    /// of credits, not reachable) hands over to the next one. `missing` is
    /// the message when none of them has it.
    @discardableResult
    static func call(_ name: String, _ body: [String: Any], signedIn: Bool, missing: String) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        let token = signedIn ? try await AuthClient.shared.token() : nil
        var answered = false
        for base in bases {
            guard let url = URL(string: "\(base)/\(name)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Not the Authorization header: Netlify can answer that one itself.
            if let token { request.setValue(token, forHTTPHeaderField: "X-Sugerly-Token") }
            request.httpBody = data
            let reply: Data
            let response: URLResponse
            do {
                (reply, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where unreachable(error) {
                continue
            } catch {
                throw APIError(message: "No connection — check your internet and try again.", status: -1)
            }
            answered = true
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
            if (200..<300).contains(status) { return json }
            if let message = json["error"] as? String { throw APIError(message: message, status: status) }
        }
        if !answered { throw APIError(message: "No connection — check your internet and try again.", status: -1) }
        throw APIError(message: missing, status: 404, code: "NOT_DEPLOYED")
    }

    // The request never got to a server at this address, so the next one can
    // safely try. Not after a timeout or a dropped connection: the server may
    // already have done the work.
    private static func unreachable(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
            return true
        default:
            return false
        }
    }
}
