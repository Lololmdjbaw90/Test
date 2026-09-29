import Foundation
import Security

// Sugerly talks to the same Firebase project as the website, over Firebase's
// REST APIs (Auth, Firestore, Storage). No SDK to install and no extra
// console setup: accounts, posts and chats are shared with the web app, and
// the same security rules apply.
enum FirebaseConfig {
    static let apiKey = "AIzaSyA__4874dkVIZMdV5GWQVzWX0rSPET_W4E"
    static let projectId = "umikoworks-86333"
    static let storageBucket = "umikoworks-86333.firebasestorage.app"
    static let siteOwners: Set<String> = ["paologionfriddo90@gmail.com"]
}

struct APIError: LocalizedError {
    var message: String
    var status: Int = 0
    var code: String = ""
    var errorDescription: String? { message }
}

enum HTTP {
    static func json(_ url: URL, method: String = "GET", body: Any? = nil, auth: String? = nil) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        // Always the newest data from the server, never an old saved copy.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(message: "No connection — check your internet and try again.", status: -1, code: "OFFLINE")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object: Any = data.isEmpty ? [String: Any]() : ((try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]())
        guard (200..<300).contains(status) else {
            // runQuery wraps its error in a list: [{"error": {...}}]
            let wrapper = (object as? [String: Any]) ?? ((object as? [[String: Any]])?.first ?? [:])
            let error = wrapper["error"]
            let message = (error as? [String: Any])?["message"] as? String ?? (error as? String) ?? "Something went wrong (\(status))."
            let code = (error as? [String: Any])?["status"] as? String ?? ""
            throw APIError(message: message, status: status, code: code)
        }
        return object
    }
}

enum Keychain {
    private static let service = "com.mimilocks.sugerly.session"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Auth (email + password)

@MainActor
final class AuthClient {
    static let shared = AuthClient()

    private(set) var uid: String?
    private(set) var email: String?
    private var idToken: String?
    private var expiry = Date.distantPast
    private var refreshToken: String?
    private var refreshing: Task<String, Error>?

    var hasSession: Bool { refreshToken != nil }

    private init() {
        refreshToken = Keychain.get("refresh")
        uid = UserDefaults.standard.string(forKey: "sugerly.uid")
        email = UserDefaults.standard.string(forKey: "sugerly.email")
    }

    private static func endpoint(_ method: String) -> URL {
        URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(method)?key=\(FirebaseConfig.apiKey)")!
    }

    private func store(idToken: String, refreshToken: String, expiresIn: String?, uid: String, email: String?) {
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.uid = uid
        if let email { self.email = email.lowercased() }
        expiry = Date().addingTimeInterval((Double(expiresIn ?? "3600") ?? 3600) - 120)
        Keychain.set(refreshToken, for: "refresh")
        UserDefaults.standard.set(uid, forKey: "sugerly.uid")
        UserDefaults.standard.set(self.email, forKey: "sugerly.email")
    }

    func signIn(email: String, password: String) async throws {
        let body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password, "returnSecureToken": true]
        do {
            let json = try await HTTP.json(Self.endpoint("signInWithPassword"), method: "POST", body: body) as? [String: Any] ?? [:]
            try storeAuthResponse(json)
        } catch let error as APIError { throw Self.friendly(error) }
    }

    func signUp(email: String, password: String, name: String) async throws {
        let body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password, "returnSecureToken": true]
        do {
            let json = try await HTTP.json(Self.endpoint("signUp"), method: "POST", body: body) as? [String: Any] ?? [:]
            try storeAuthResponse(json)
            let update: [String: Any] = ["idToken": idToken ?? "", "displayName": name, "returnSecureToken": false]
            _ = try? await HTTP.json(Self.endpoint("update"), method: "POST", body: update)
        } catch let error as APIError { throw Self.friendly(error) }
    }

    func sendPasswordReset(email: String) async throws {
        let body: [String: Any] = ["requestType": "PASSWORD_RESET", "email": email.trimmingCharacters(in: .whitespaces).lowercased()]
        do { _ = try await HTTP.json(Self.endpoint("sendOobCode"), method: "POST", body: body) } catch let error as APIError { throw Self.friendly(error) }
    }

    private func storeAuthResponse(_ json: [String: Any]) throws {
        guard let token = json["idToken"] as? String, let refresh = json["refreshToken"] as? String, let uid = json["localId"] as? String else {
            throw APIError(message: "Couldn't sign in. Try again.")
        }
        store(idToken: token, refreshToken: refresh, expiresIn: json["expiresIn"] as? String, uid: uid, email: json["email"] as? String)
    }

    // A fresh ID token for Firestore / Storage (refreshed a bit before it expires).
    func token() async throws -> String {
        if let idToken, Date() < expiry { return idToken }
        if let refreshing { return try await refreshing.value }
        guard let refreshToken else { throw APIError(message: "Please log in again.", status: 401, code: "UNAUTHENTICATED") }
        let task = Task<String, Error> {
            let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(FirebaseConfig.apiKey)")!
            let body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken]
            let json = try await HTTP.json(url, method: "POST", body: body) as? [String: Any] ?? [:]
            guard let token = json["id_token"] as? String, let refresh = json["refresh_token"] as? String, let uid = json["user_id"] as? String else {
                throw APIError(message: "Please log in again.", status: 401, code: "UNAUTHENTICATED")
            }
            self.store(idToken: token, refreshToken: refresh, expiresIn: json["expires_in"] as? String, uid: uid, email: nil)
            return token
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    func signOut() {
        idToken = nil
        refreshToken = nil
        uid = nil
        email = nil
        expiry = .distantPast
        Keychain.set(nil, for: "refresh")
        UserDefaults.standard.removeObject(forKey: "sugerly.uid")
        UserDefaults.standard.removeObject(forKey: "sugerly.email")
    }

    func deleteAccount() async throws {
        let fresh = try await self.token()
        let body: [String: Any] = ["idToken": fresh]
        _ = try await HTTP.json(Self.endpoint("delete"), method: "POST", body: body)
        signOut()
    }

    static func friendly(_ error: APIError) -> APIError {
        let m = error.message
        var text = m
        if m.contains("INVALID_LOGIN_CREDENTIALS") || m.contains("INVALID_PASSWORD") || m.contains("EMAIL_NOT_FOUND") { text = "Wrong email or password." }
        else if m.contains("EMAIL_EXISTS") { text = "There's already an account with this email — log in instead." }
        else if m.contains("WEAK_PASSWORD") { text = "Use at least 6 characters for your password." }
        else if m.contains("INVALID_EMAIL") || m.contains("MISSING_EMAIL") { text = "That email doesn't look right." }
        else if m.contains("TOO_MANY_ATTEMPTS") { text = "Too many tries. Wait a moment and try again." }
        else if m.contains("USER_DISABLED") { text = "This account has been disabled." }
        else if m.contains("MISSING_PASSWORD") { text = "Enter your password." }
        return APIError(message: text, status: error.status, code: error.code)
    }
}

// MARK: - Firestore (REST)

typealias Doc = [String: Any]

enum FS {
    static let base = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents"

    struct Filter {
        let field: String
        let op: String
        let value: Any
        static func equals(_ field: String, _ value: Any) -> Filter { Filter(field: field, op: "EQUAL", value: value) }
        static func contains(_ field: String, _ value: Any) -> Filter { Filter(field: field, op: "ARRAY_CONTAINS", value: value) }
        static func after(_ field: String, _ value: String) -> Filter { Filter(field: field, op: "GREATER_THAN", value: value) }
        static func before(_ field: String, _ value: String) -> Filter { Filter(field: field, op: "LESS_THAN", value: value) }
        static func atLeast(_ field: String, _ value: String) -> Filter { Filter(field: field, op: "GREATER_THAN_OR_EQUAL", value: value) }
        static func isIn(_ field: String, _ values: [String]) -> Filter { Filter(field: field, op: "IN", value: values) }
        static func below(_ field: String, _ value: Double) -> Filter { Filter(field: field, op: "LESS_THAN", value: value) }
    }

    // Atomic changes done by the database itself, so millions of people can
    // like or view the same thing at once without overwriting each other.
    enum Change {
        case add(String, Any)        // add to an array (once)
        case remove(String, Any)     // take out of an array
        case increment(String, Int)  // bump a number
    }

    static func nowISO() -> String { Dates.iso(Date()) }

    // Collections whose sorted queries lack an index in this project (they
    // still work, just more slowly) — screens check in less often for them.
    nonisolated(unsafe) static var missingIndex: Set<String> = []

    @MainActor private static func bearer() async throws -> String {
        let token = try await AuthClient.shared.token()
        return "Bearer \(token)"
    }

    private static func path(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? segment
    }

    // Swift value -> Firestore JSON value
    static func encode(_ value: Any?) -> [String: Any] {
        guard let value else { return ["nullValue": NSNull()] }
        switch value {
        case is NSNull: return ["nullValue": NSNull()]
        case let v as Bool: return ["booleanValue": v]
        case let v as Int: return ["integerValue": String(v)]
        case let v as Double: return ["doubleValue": v]
        case let v as Date: return ["timestampValue": Dates.iso(v)]
        case let v as String: return ["stringValue": v]
        case let v as [Any]:
            let values: [[String: Any]] = v.map { encode($0) }
            return ["arrayValue": ["values": values] as [String: Any]]
        case let v as [String: Any]:
            let fields: [String: Any] = v.mapValues { encode($0) }
            return ["mapValue": ["fields": fields] as [String: Any]]
        default: return ["stringValue": String(describing: value)]
        }
    }

    // Firestore JSON value -> Swift value
    static func decode(_ v: [String: Any]) -> Any {
        if let s = v["stringValue"] as? String { return s }
        if let s = v["integerValue"] as? String { return Int(s) ?? 0 }
        if let n = v["integerValue"] as? NSNumber { return n.intValue }
        if let d = v["doubleValue"] as? Double { return d }
        if let b = v["booleanValue"] as? Bool { return b }
        if let t = v["timestampValue"] as? String { return t }
        if let a = v["arrayValue"] as? [String: Any] {
            let values = a["values"] as? [[String: Any]] ?? []
            return values.map { decode($0) }
        }
        if let m = v["mapValue"] as? [String: Any] { return fields(m["fields"] as? [String: Any] ?? [:]) }
        if let r = v["referenceValue"] as? String { return r }
        return NSNull()
    }

    static func fields(_ raw: [String: Any]) -> Doc {
        var out: Doc = [:]
        for (key, value) in raw {
            if let v = value as? [String: Any] { out[key] = decode(v) }
        }
        return out
    }

    static func document(_ json: [String: Any]) -> Doc? {
        guard let name = json["name"] as? String else { return nil }
        var doc = fields(json["fields"] as? [String: Any] ?? [:])
        doc["id"] = name.components(separatedBy: "/").last ?? ""
        return doc
    }

    static func get(_ collection: String, _ id: String) async throws -> Doc? {
        do {
            let json = try await HTTP.json(URL(string: "\(base)/\(collection)/\(path(id))")!, auth: try await bearer())
            return document(json as? [String: Any] ?? [:])
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    @discardableResult
    static func create(_ collection: String, _ data: Doc, id: String? = nil) async throws -> Doc {
        var comps = URLComponents(string: "\(base)/\(collection)")!
        if let id { comps.queryItems = [URLQueryItem(name: "documentId", value: id)] }
        // Same bookkeeping fields the website adds to every new record.
        var data = data
        let now = nowISO()
        if data["created_date"] == nil { data["created_date"] = now }
        if data["updated_date"] == nil { data["updated_date"] = now }
        if data["created_by"] == nil, let email = await MainActor.run(body: { AuthClient.shared.email }) { data["created_by"] = email }
        let fields: [String: Any] = data.mapValues { encode($0) }
        let body: [String: Any] = ["fields": fields]
        let json = try await HTTP.json(comps.url!, method: "POST", body: body, auth: try await bearer())
        return document(json as? [String: Any] ?? [:]) ?? data
    }

    // Changes only the given fields (the rest of the document stays as it is).
    static func update(_ collection: String, _ id: String, _ data: Doc) async throws {
        var comps = URLComponents(string: "\(base)/\(collection)/\(path(id))")!
        comps.queryItems = data.keys.sorted().map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) } + [URLQueryItem(name: "currentDocument.exists", value: "true")]
        let fields: [String: Any] = data.mapValues { encode($0) }
        let body: [String: Any] = ["fields": fields]
        _ = try await HTTP.json(comps.url!, method: "PATCH", body: body, auth: try await bearer())
    }

    static func delete(_ collection: String, _ id: String) async throws {
        _ = try await HTTP.json(URL(string: "\(base)/\(collection)/\(path(id))")!, method: "DELETE", auth: try await bearer())
    }

    static func change(_ collection: String, _ id: String, _ changes: [Change], set: Doc = [:]) async throws {
        try await commit([.change(collection, id, changes, set: set)])
    }

    // Several writes that all happen, or none do (e.g. a Like record plus the
    // post's like_count).
    enum Write {
        case create(String, String, Doc)                    // must not exist yet
        case delete(String, String)                         // must exist
        case change(String, String, [Change], set: Doc)     // must exist
    }

    static func name(_ collection: String, _ id: String) -> String {
        "projects/\(FirebaseConfig.projectId)/databases/(default)/documents/\(collection)/\(id)"
    }

    static func commit(_ writes: [Write]) async throws {
        let body: [[String: Any]] = writes.map { write in
            switch write {
            case .create(let collection, let id, let data):
                let doc: [String: Any] = ["name": name(collection, id), "fields": data.mapValues { encode($0) }]
                return ["update": doc, "currentDocument": ["exists": false]]
            case .delete(let collection, let id):
                return ["delete": name(collection, id), "currentDocument": ["exists": true]]
            case .change(let collection, let id, let changes, let set):
                let transforms: [[String: Any]] = changes.map { change in
                    switch change {
                    case .add(let field, let value):
                        return ["fieldPath": field, "appendMissingElements": ["values": [encode(value)]] as [String: Any]]
                    case .remove(let field, let value):
                        return ["fieldPath": field, "removeAllFromArray": ["values": [encode(value)]] as [String: Any]]
                    case .increment(let field, let by):
                        return ["fieldPath": field, "increment": encode(by)]
                    }
                }
                let doc: [String: Any] = ["name": name(collection, id), "fields": set.mapValues { encode($0) }]
                return [
                    "update": doc,
                    "updateMask": ["fieldPaths": Array(set.keys)],
                    "updateTransforms": transforms,
                    "currentDocument": ["exists": true],
                ]
            }
        }
        _ = try await HTTP.json(URL(string: "\(base):commit")!, method: "POST", body: ["writes": body], auth: try await bearer())
    }

    // Many documents by id in one request; ids that don't exist are left out.
    static func getMany(_ collection: String, _ ids: [String]) async throws -> [String: Doc] {
        guard !ids.isEmpty else { return [:] }
        let body: [String: Any] = ["documents": ids.map { name(collection, $0) }]
        let json = try await HTTP.json(URL(string: "\(base):batchGet")!, method: "POST", body: body, auth: try await bearer())
        var out: [String: Doc] = [:]
        for row in json as? [[String: Any]] ?? [] {
            if let found = row["found"] as? [String: Any], let doc = document(found) { out[doc.str("id")] = doc }
        }
        return out
    }

    // How many documents match, counted by the database (nothing is
    // downloaded, so it works the same for ten rows or ten billion).
    static func count(_ collection: String, _ filters: [Filter] = []) async throws -> Int {
        var structured: [String: Any] = ["from": [["collectionId": collection]]]
        if let clause = whereClause(filters) { structured["where"] = clause }
        let aggregation: [String: Any] = ["alias": "n", "count": [String: Any]()]
        let body: [String: Any] = ["structuredAggregationQuery": ["structuredQuery": structured, "aggregations": [aggregation]] as [String: Any]]
        let json = try await HTTP.json(URL(string: "\(base):runAggregationQuery")!, method: "POST", body: body, auth: try await bearer())
        let rows = json as? [[String: Any]] ?? []
        for row in rows {
            if let result = row["result"] as? [String: Any], let fields = result["aggregateFields"] as? [String: Any],
               let n = fields["n"] as? [String: Any] {
                if let text = n["integerValue"] as? String, let value = Int(text) { return value }
                if let value = n["integerValue"] as? Int { return value }
            }
        }
        return 0
    }

    private static func whereClause(_ filters: [Filter]) -> [String: Any]? {
        let clauses: [[String: Any]] = filters.map { filter in
            let fieldFilter: [String: Any] = ["field": ["fieldPath": filter.field], "op": filter.op, "value": encode(filter.value)]
            return ["fieldFilter": fieldFilter]
        }
        if clauses.count == 1 { return clauses[0] }
        if clauses.count > 1 { return ["compositeFilter": ["op": "AND", "filters": clauses] as [String: Any]] }
        return nil
    }

    // Names starting with what you typed (a prefix range on one field).
    static func prefix(_ collection: String, field: String, _ text: String, limit: Int = 20) async throws -> [Doc] {
        guard !text.isEmpty else { return [] }
        return try await query(collection, [.atLeast(field, text), .before(field, text + "\u{f8ff}")], orderBy: field, descending: false, limit: limit)
    }

    static func query(_ collection: String, _ filters: [Filter] = [], orderBy: String? = nil, descending: Bool = true, limit: Int? = nil) async throws -> [Doc] {
        do {
            return try await runQuery(collection, filters, orderBy: orderBy, descending: descending, limit: limit)
        } catch let error as APIError where error.code == "FAILED_PRECONDITION" {
            // The query needs an index that isn't there: ask with the simple
            // filters only, then filter and sort here instead.
            missingIndex.insert(collection)
            let simple = filters.filter { $0.op == "EQUAL" || $0.op == "ARRAY_CONTAINS" }
            let ranges = filters.filter { $0.op == "GREATER_THAN" || $0.op == "LESS_THAN" }
            // Never download a whole collection (it could hold millions of
            // rows): cap the fallback at a generous multiple of what was asked.
            let cap = min(5000, max((limit ?? 100) * 20, 1000))
            var docs = try await runQuery(collection, simple, orderBy: nil, descending: descending, limit: cap)
            for range in ranges {
                if let edge = range.value as? Double {
                    docs = docs.filter { doc in
                        guard let v = ReelText.num(doc[range.field]) else { return false }
                        return range.op == "LESS_THAN" ? v < edge : v > edge
                    }
                    continue
                }
                let edge = range.value as? String ?? ""
                docs = docs.filter { range.op == "LESS_THAN" ? $0.str(range.field) < edge : $0.str(range.field) > edge }
            }
            if let key = orderBy {
                docs.sort { a, b in
                    let x = a.str(key), y = b.str(key)
                    return descending ? x > y : x < y
                }
            }
            if let limit, docs.count > limit { docs = Array(docs.prefix(limit)) }
            return docs
        }
    }

    private static func runQuery(_ collection: String, _ filters: [Filter], orderBy: String?, descending: Bool, limit: Int?) async throws -> [Doc] {
        var structured: [String: Any] = ["from": [["collectionId": collection]]]
        let clauses: [[String: Any]] = filters.map { filter in
            let fieldFilter: [String: Any] = ["field": ["fieldPath": filter.field], "op": filter.op, "value": encode(filter.value)]
            return ["fieldFilter": fieldFilter]
        }
        if clauses.count == 1 {
            structured["where"] = clauses[0]
        } else if clauses.count > 1 {
            let composite: [String: Any] = ["op": "AND", "filters": clauses]
            structured["where"] = ["compositeFilter": composite]
        }
        if let orderBy {
            let order: [String: Any] = ["field": ["fieldPath": orderBy], "direction": descending ? "DESCENDING" : "ASCENDING"]
            structured["orderBy"] = [order]
        }
        if let limit { structured["limit"] = limit }
        let body: [String: Any] = ["structuredQuery": structured]
        let json = try await HTTP.json(URL(string: "\(base):runQuery")!, method: "POST", body: body, auth: try await bearer())
        let rows = json as? [[String: Any]] ?? []
        return rows.compactMap { row in (row["document"] as? [String: Any]).flatMap { document($0) } }
    }
}

// MARK: - Storage (uploads go to uploads/<uid>/…, like the website)

enum StorageClient {
    @MainActor
    static func upload(_ data: Data, contentType: String, fileExtension: String) async throws -> String {
        guard let uid = AuthClient.shared.uid else { throw APIError(message: "Please log in again.") }
        let token = try await AuthClient.shared.token()
        let name = "uploads/\(uid)/\(Int(Date().timeIntervalSince1970 * 1000))-ios.\(fileExtension)"
        var comps = URLComponents(string: "https://firebasestorage.googleapis.com/v0/b/\(FirebaseConfig.storageBucket)/o")!
        comps.queryItems = [URLQueryItem(name: "uploadType", value: "media"), URLQueryItem(name: "name", value: name)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Firebase \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Upload failed (\(status))."
            throw APIError(message: message, status: status)
        }
        let downloadToken = (json["downloadTokens"] as? String ?? "").components(separatedBy: ",").first ?? ""
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return "https://firebasestorage.googleapis.com/v0/b/\(FirebaseConfig.storageBucket)/o/\(encoded)?alt=media&token=\(downloadToken)"
    }
}
