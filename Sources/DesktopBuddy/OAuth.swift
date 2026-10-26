import Foundation
import AppKit
import Network
import CryptoKit

enum AuthError: LocalizedError {
    case missingClient(Provider), notSignedIn, expired, cancelled, portInUse(Int), badResponse(String)
    var errorDescription: String? {
        switch self {
        case .missingClient(let p):
            return "No \(p.name) sign-in client is set up. Ask your admin for the team setup file, or add a client ID under Advanced."
        case .notSignedIn: return "Not signed in."
        case .expired: return "Sign-in expired. Sign in again to keep checking this account."
        case .cancelled: return "Sign-in was cancelled."
        case .portInUse(let port): return "Port \(port) is busy. Change the sign-in port under Advanced and try again."
        case .badResponse(let s): return s
        }
    }
}

/// OAuth 2.0 for installed apps (RFC 8252): system browser + PKCE + loopback redirect.
/// Works for Google and Microsoft identity platform. Read-only scopes only.
actor OAuth {
    static let shared = OAuth()

    static func scopes(_ p: Provider) -> [String] {
        switch p {
        case .google:
            return ["openid", "email",
                    "https://www.googleapis.com/auth/gmail.readonly",
                    "https://www.googleapis.com/auth/calendar.readonly",
                    "https://www.googleapis.com/auth/chat.spaces.readonly",
                    "https://www.googleapis.com/auth/chat.messages.readonly",
                    "https://www.googleapis.com/auth/tasks.readonly",
                    "https://www.googleapis.com/auth/directory.readonly"]
        case .microsoft:
            return ["openid", "email", "offline_access", "User.Read",
                    "Mail.Read", "Calendars.Read", "Chat.Read", "Tasks.Read"]
        }
    }

    /// Human-readable list shown before sign-in so people know exactly what is shared.
    static func permissionSummary(_ p: Provider) -> [String] {
        switch p {
        case .google:
            return ["Read Gmail (never sends or deletes)", "Read Google Chat messages",
                    "Read your calendar", "Read Google Tasks", "Look up names in your directory"]
        case .microsoft:
            return ["Read Outlook mail (never sends or deletes)", "Read your Teams chats",
                    "Read your calendar", "Read Microsoft To Do", "Sign you in and read your profile"]
        }
    }

    private var accessTokens: [String: (token: String, expires: Date)] = [:]
    /// In-flight browser sign-ins, so a new attempt (or Cancel) can end a stuck one and free its port.
    private var pending: [String: any CallbackReceiver] = [:]

    /// Which address actually signed in (to catch "approved in the wrong browser profile").
    nonisolated static func signedInEmails(_ account: AccountConfig) async throws -> [String] {
        let api = APIClient(account: account)
        switch account.provider {
        case .google:
            let info = try await api.get("https://openidconnect.googleapis.com/v1/userinfo")
            return [info["email"] as? String].compactMap { $0?.lowercased() }
        case .microsoft:
            let me = try await api.get("https://graph.microsoft.com/v1.0/me", ["$select": "mail,userPrincipalName,otherMails"])
            return ([me["mail"] as? String, me["userPrincipalName"] as? String] + (me["otherMails"] as? [String] ?? []))
                .compactMap { $0?.lowercased() }
        }
    }

    func cancelSignIn(_ accountID: String) {
        pending[accountID]?.cancel()
        pending[accountID] = nil
    }

    static func secretKey(_ id: String) -> String { "secret.\(id)" }
    static func refreshKey(_ id: String) -> String { "refresh.\(id)" }

    nonisolated static func isSignedIn(_ account: AccountConfig) -> Bool {
        Keychain.get(refreshKey(account.id)) != nil
    }

    func signOut(_ account: AccountConfig) {
        Keychain.set(nil, for: Self.refreshKey(account.id))
        accessTokens[account.id] = nil
    }

    func forget(_ account: AccountConfig) {
        signOut(account)
        Keychain.set(nil, for: Self.secretKey(account.id))
    }

    // MARK: - Client resolution (account override → team default)

    private struct Client { var id: String; var secret: String?; var authURL: String; var tokenURL: String }

    private func client(for a: AccountConfig) throws -> Client {
        let team = TeamConfig.current
        switch a.provider {
        case .google:
            let id = a.clientID.isEmpty ? (team.googleClientID ?? "") : a.clientID
            guard !id.isEmpty else { throw AuthError.missingClient(.google) }
            // iOS-type clients have no secret (PKCE only); Desktop-type clients send theirs.
            let secret = Keychain.get(Self.secretKey(a.id)) ?? team.googleClientSecret
            return Client(id: id, secret: (secret?.isEmpty ?? true) ? nil : secret,
                          authURL: "https://accounts.google.com/o/oauth2/v2/auth",
                          tokenURL: "https://oauth2.googleapis.com/token")
        case .microsoft:
            let id = a.clientID.isEmpty ? (team.microsoftClientID ?? "") : a.clientID
            guard !id.isEmpty else { throw AuthError.missingClient(.microsoft) }
            let tenant = a.tenant ?? team.microsoftTenant ?? "organizations"
            return Client(id: id, secret: nil,
                          authURL: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/authorize",
                          tokenURL: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token")
        }
    }

    nonisolated static func redirectURI(_ a: AccountConfig) -> String {
        // No-secret Google clients return to the app's own URL scheme. Google Desktop clients accept any
        // loopback port; Entra "Mobile and desktop" accepts http://localhost on any port.
        if let scheme = appScheme(a) { return "\(scheme):/oauth2redirect" }
        return a.provider == .google ? "http://localhost:\(a.redirectPort)/oauth2callback" : "http://localhost:\(a.redirectPort)"
    }

    /// The reversed client ID ("com.googleusercontent.apps.123-abc") when Google sign-in uses an
    /// iOS-type client with no secret, or nil when it uses a Desktop client and the loopback redirect.
    nonisolated static func appScheme(_ a: AccountConfig) -> String? {
        guard a.provider == .google else { return nil }
        let team = TeamConfig.current
        let id = a.clientID.isEmpty ? (team.googleClientID ?? "") : a.clientID
        let secret = Keychain.get(secretKey(a.id)) ?? team.googleClientSecret ?? ""
        guard !id.isEmpty, secret.isEmpty else { return nil }
        return reversedClientID(id)
    }

    nonisolated static func reversedClientID(_ id: String) -> String {
        "com.googleusercontent.apps." + id.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    // MARK: - Interactive sign-in

    /// `onURL` receives the browser link (for "Copy Link" / "Open Again" while waiting).
    func signIn(_ account: AccountConfig, onURL: @escaping @MainActor (URL) -> Void = { _ in }) async throws {
        // A previous attempt that was abandoned (tab closed, wrong browser profile) still holds the port.
        if let old = pending[account.id] {
            old.cancel()
            pending[account.id] = nil
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        let c = try client(for: account)
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomURLSafe(24)
        let redirect = Self.redirectURI(account)

        var comps = URLComponents(string: c.authURL)!
        var q: [URLQueryItem] = [
            .init(name: "client_id", value: c.id),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes(account.provider).joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        // New accounts sign in first (no email yet): let the person pick which account to add.
        if !account.email.isEmpty { q.append(.init(name: "login_hint", value: account.email)) }
        if account.provider == .google {
            q += [.init(name: "access_type", value: "offline"),
                  .init(name: "prompt", value: account.email.isEmpty ? "select_account consent" : "consent")]
        } else {
            q += [.init(name: "prompt", value: "select_account")]
        }
        comps.queryItems = q

        let receiver: any CallbackReceiver = Self.appScheme(account) != nil
            ? SchemeReceiver() : LoopbackReceiver(port: UInt16(account.redirectPort))
        pending[account.id] = receiver
        defer { if pending[account.id] === receiver { pending[account.id] = nil } }
        let codeTask = Task { try await receiver.waitForCallback(timeout: 300) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let authURL = comps.url!
        await MainActor.run {
            onURL(authURL)
            _ = NSWorkspace.shared.open(authURL)
        }

        let params = try await codeTask.value
        guard params["state"] == state else { throw AuthError.badResponse("Sign-in response didn't match. Please try again.") }
        guard let code = params["code"] else {
            throw AuthError.badResponse(params["error_description"] ?? params["error"] ?? "No code returned")
        }

        var form = [
            "code": code, "client_id": c.id, "redirect_uri": redirect,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ]
        if let s = c.secret { form["client_secret"] = s }
        if account.provider == .microsoft { form["scope"] = Self.scopes(.microsoft).joined(separator: " ") }
        let json = try await Self.tokenRequest(c.tokenURL, form)
        guard let refresh = json["refresh_token"] as? String else {
            throw AuthError.badResponse("The provider did not return a long-lived sign-in. Try again.")
        }
        Keychain.set(refresh, for: Self.refreshKey(account.id))
        try cache(json, for: account.id)
    }

    // MARK: - Access tokens

    func accessToken(for account: AccountConfig) async throws -> String {
        if let cached = accessTokens[account.id], cached.expires > Date().addingTimeInterval(60) {
            return cached.token
        }
        guard let refresh = Keychain.get(Self.refreshKey(account.id)) else { throw AuthError.notSignedIn }
        let c = try client(for: account)
        var form = ["refresh_token": refresh, "client_id": c.id, "grant_type": "refresh_token"]
        if let s = c.secret { form["client_secret"] = s }
        if account.provider == .microsoft { form["scope"] = Self.scopes(.microsoft).joined(separator: " ") }
        let json = try await Self.tokenRequest(c.tokenURL, form)
        // Microsoft rotates refresh tokens; keep the newest.
        if let newRefresh = json["refresh_token"] as? String { Keychain.set(newRefresh, for: Self.refreshKey(account.id)) }
        return try cache(json, for: account.id)
    }

    @discardableResult
    private func cache(_ json: [String: Any], for id: String) throws -> String {
        guard let token = json["access_token"] as? String else { throw AuthError.badResponse("No access token") }
        let ttl = (json["expires_in"] as? Double) ?? Double(json["expires_in"] as? String ?? "") ?? 3600
        accessTokens[id] = (token, Date().addingTimeInterval(ttl))
        return token
    }

    private static func tokenRequest(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = json["error"] as? String {
            if err == "invalid_grant" { throw AuthError.expired }
            throw AuthError.badResponse("\(err): \(json["error_description"] as? String ?? "")")
        }
        return json
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URL
    }
}

/// Waits for the OAuth redirect and returns its query parameters.
protocol CallbackReceiver: AnyObject, Sendable {
    func waitForCallback(timeout: TimeInterval) async throws -> [String: String]
    func cancel()
}

/// Captures the redirect sent to the app's own URL scheme (Google iOS-type clients, no secret).
/// macOS hands the URL to the app delegate, which passes it to `deliver`.
final class SchemeReceiver: CallbackReceiver, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var active: SchemeReceiver?
    private var cont: CheckedContinuation<[String: String], Error>?
    private var finished = false

    /// Returns true when the URL was a sign-in redirect that a waiting sign-in took.
    @discardableResult
    static func deliver(_ url: URL) -> Bool {
        var out: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach { out[$0.name] = $0.value }
        guard out["code"] != nil || out["error"] != nil else { return false }
        lock.lock(); let r = active; lock.unlock()
        r?.finish(.success(out))
        return r != nil
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { c in
            Self.lock.lock()
            if finished { Self.lock.unlock(); c.resume(throwing: AuthError.cancelled); return }
            cont = c
            Self.active = self
            Self.lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(.failure(AuthError.cancelled)) }
        }
    }

    func cancel() { finish(.failure(AuthError.cancelled)) }

    private func finish(_ result: Result<[String: String], Error>) {
        Self.lock.lock()
        guard !finished else { Self.lock.unlock(); return }
        finished = true
        let c = cont
        cont = nil
        if Self.active === self { Self.active = nil }
        Self.lock.unlock()
        c?.resume(with: result)
    }
}

/// One-shot HTTP listener on the loopback interface that captures the OAuth redirect.
final class LoopbackReceiver: CallbackReceiver, @unchecked Sendable {
    private let port: UInt16
    private let lock = NSLock()
    private var cancelHandler: (() -> Void)?
    private var cancelledEarly = false
    init(port: UInt16) { self.port = port }

    /// Ends the wait right away (user pressed Cancel, or started a new attempt).
    func cancel() {
        lock.lock()
        let h = cancelHandler
        if h == nil { cancelledEarly = true }
        lock.unlock()
        h?()
    }

    func waitForCallback(timeout: TimeInterval = 300) async throws -> [String: String] {
        // Loopback only (IPv4 and IPv6), so "localhost" works whichever the browser picks.
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        do { listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) }
        catch { throw AuthError.portInUse(Int(port)) }
        let queue = DispatchQueue(label: "oauth.loopback")

        return try await withCheckedThrowingContinuation { cont in
            var finished = false
            func finish(_ result: Result<[String: String], Error>) {
                queue.async {
                    guard !finished else { return }
                    finished = true
                    listener.cancel()
                    cont.resume(with: result)
                }
            }

            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    var out: [String: String] = [:]
                    URLComponents(string: "http://x\(path)")?.queryItems?.forEach { out[$0.name] = $0.value }
                    guard out["code"] != nil || out["error"] != nil else {
                        conn.send(content: Self.response("Not found", status: "404 Not Found"),
                                  completion: .contentProcessed { _ in conn.cancel() })
                        return
                    }
                    let ok = out["code"] != nil
                    conn.send(content: Self.response(ok ? "You're signed in" : "Sign-in didn't finish",
                                                     sub: ok ? "You can close this tab and go back to Desktop Buddy."
                                                             : (out["error_description"] ?? out["error"] ?? "")),
                              completion: .contentProcessed { _ in
                        conn.cancel()
                        finish(.success(out))
                    })
                }
            }
            lock.lock()
            cancelHandler = { finish(.failure(AuthError.cancelled)) }
            let early = cancelledEarly
            lock.unlock()
            if early { finish(.failure(AuthError.cancelled)) }

            listener.stateUpdateHandler = { state in
                if case .failed = state { finish(.failure(AuthError.portInUse(Int(self.port)))) }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(AuthError.cancelled)) }
        }
    }

    private static func response(_ title: String, sub: String = "", status: String = "200 OK") -> Data {
        let html = """
        <html><head><meta name="viewport" content="width=device-width"><title>Desktop Buddy</title></head>
        <body style="font-family:-apple-system,system-ui;background:#f5f5f7;color:#1d1d1f;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
        <div style="text-align:center"><div style="font-size:44px">✓</div>
        <h1 style="font-weight:600;letter-spacing:-0.02em;margin:12px 0 6px">\(title)</h1>
        <p style="color:#6e6e73;margin:0">\(sub)</p></div></body></html>
        """
        return Data("HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)".utf8)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
