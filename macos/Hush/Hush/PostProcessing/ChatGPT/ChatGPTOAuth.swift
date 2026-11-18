import CryptoKit
import Foundation

/// OpenAI's Sign in with ChatGPT for open-source and locally hosted apps, exactly as
/// documented (developers.openai.com/siwc/token-sharing-open-source): authorization code
/// with PKCE, no client secret, a loopback callback, first-time registration through
/// `dynamic_agent_client`, and the scopes that let requests use the user's ChatGPT plan.
/// Everything here is pure, so the protocol is tested without a network.
nonisolated enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let authorizationEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let revocationEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!
    static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    /// The audience of plan-usage tokens and the base of the Responses API.
    static let resource = "https://api.openai.com/v1"
    static let registrationClientID = "dynamic_agent_client"
    /// The app's actual name, the same on every installation; display metadata only.
    static let agentName = "hush"
    static let planScope = "chatgpt.tokens.use.direct"
    static let scopes = ["openid", "profile", "email", "offline_access", "resource.invoke", planScope]
    /// The documented callback; only the port may vary between sign-ins.
    static let preferredPort: UInt16 = 1455
    static let callbackPath = "/auth/callback"

    static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)\(callbackPath)" }

    // MARK: PKCE, state and nonce

    struct Attempt: Equatable, Sendable {
        let verifier: String
        let state: String
        let nonce: String
        let redirectURI: String
        /// The issued client ID on reauthorization; nil for a first registration.
        let clientID: String?

        var challenge: String { ChatGPTOAuth.challenge(for: verifier) }

        static func fresh(redirectURI: String, clientID: String?) -> Attempt {
            Attempt(verifier: randomToken(), state: randomToken(), nonce: randomToken(), redirectURI: redirectURI, clientID: clientID)
        }
    }

    /// 32 random bytes, base64url without padding: a 43-character PKCE verifier (RFC 7636).
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "No system randomness")
        return Data(bytes).base64URLEncoded
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    // MARK: Authorization request

    /// A first registration names the app and uses `dynamic_agent_client`; a returning
    /// sign-in uses the issued client ID, omits the name, and may hint the account.
    static func authorizationURL(for attempt: Attempt, hostID: String, idTokenHint: String? = nil, loginHint: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: attempt.clientID ?? registrationClientID),
            URLQueryItem(name: "redirect_uri", value: attempt.redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "nonce", value: attempt.nonce),
            URLQueryItem(name: "code_challenge", value: attempt.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
        ]
        if attempt.clientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: agentName))
        } else {
            if let idTokenHint { items.append(URLQueryItem(name: "id_token_hint", value: idTokenHint)) }
            if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        }
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        // `+` and other reserved characters must be percent-encoded in every value.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    // MARK: Callback

    struct Authorization: Equatable, Sendable {
        let code: String
        /// The issued client ID to save and use from now on.
        let clientID: String
    }

    enum CallbackError: Error, Equatable {
        case stateMismatch
        case denied(String)
        case missingCode
        case registrationIncomplete
        case clientMismatch
    }

    /// Validates the callback against the pending attempt, as the documentation requires:
    /// state first, then an OAuth error, then the issued client ID.
    static func authorization(from callback: URL, for attempt: Attempt) throws -> Authorization {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == attempt.state else { throw CallbackError.stateMismatch }
        if let error = value("error") { throw CallbackError.denied(error) }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        let returned = value("client_id")
        if let pending = attempt.clientID {
            if let returned, returned != pending { throw CallbackError.clientMismatch }
            return Authorization(code: code, clientID: pending)
        }
        guard let returned, !returned.isEmpty, returned != registrationClientID else { throw CallbackError.registrationIncomplete }
        return Authorization(code: code, clientID: returned)
    }

    // MARK: Token, refresh and revocation requests

    struct TokenResponse: Decodable, Equatable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let tokenType: String?
        let expiresIn: Int
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token"
            case tokenType = "token_type", expiresIn = "expires_in", scope
        }

        /// Plan usage needs its own scope; a valid ID token alone does not grant it.
        var grantsPlanUsage: Bool {
            scope?.split(separator: " ").contains(Substring(ChatGPTOAuth.planScope)) ?? false
        }
    }

    static func tokenRequest(code: String, attempt: Attempt, clientID: String) -> URLRequest {
        formRequest(tokenEndpoint, [
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", attempt.verifier),
            ("redirect_uri", attempt.redirectURI),
            ("resource", resource),
        ])
    }

    /// Scope is omitted on refresh, as documented.
    static func refreshRequest(refreshToken: String, clientID: String) -> URLRequest {
        formRequest(tokenEndpoint, [
            ("grant_type", "refresh_token"),
            ("client_id", clientID),
            ("refresh_token", refreshToken),
            ("resource", resource),
        ])
    }

    static func revocationRequest(refreshToken: String, clientID: String) -> URLRequest {
        formRequest(revocationEndpoint, [
            ("token", refreshToken),
            ("token_type_hint", "refresh_token"),
            ("client_id", clientID),
        ])
    }

    /// Refresh errors after which the refresh token is unusable and the user signs in again.
    static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired",
        "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused",
    ]

    static func formRequest(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(fields.map { "\($0.0)=\(formEncoded($0.1))" }.joined(separator: "&").utf8)
        return request
    }

    static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

nonisolated extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
