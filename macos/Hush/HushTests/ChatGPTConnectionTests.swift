import Foundation
import Security
import Testing
@testable import Hush

@Suite("Sign in with ChatGPT")
struct ChatGPTConnectionTests {

    // MARK: PKCE and the authorization request

    @Test("PKCE matches the RFC 7636 reference values and tokens are 43 URL-safe characters")
    func pkce() {
        #expect(ChatGPTOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let token = ChatGPTOAuth.randomToken()
        #expect(token.count == 43)
        #expect(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(ChatGPTOAuth.randomToken() != token)
    }

    private func parameters(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test("A first registration uses dynamic_agent_client, names hush and asks for plan usage")
    func registrationRequest() {
        let attempt = ChatGPTOAuth.Attempt.fresh(redirectURI: ChatGPTOAuth.redirectURI(port: 1455), clientID: nil)
        let url = ChatGPTOAuth.authorizationURL(for: attempt, hostID: "urn:uuid:host")
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"))
        let query = parameters(url)
        #expect(query["client_id"] == "dynamic_agent_client")
        #expect(query["agent_name_hint"] == "hush")
        #expect(query["ext_agent_host_id"] == "urn:uuid:host")
        #expect(query["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(query["response_type"] == "code")
        #expect(query["resource"] == "https://api.openai.com/v1")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == attempt.challenge)
        #expect(query["state"] == attempt.state)
        #expect(query["nonce"] == attempt.nonce)
        #expect(Set((query["scope"] ?? "").split(separator: " ").map(String.init))
                == ["openid", "profile", "email", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"])
        #expect(query["login_hint"] == nil && query["id_token_hint"] == nil)
    }

    @Test("A returning sign-in uses the issued client ID and leaves out the app name")
    func reauthorizationRequest() {
        let attempt = ChatGPTOAuth.Attempt.fresh(redirectURI: ChatGPTOAuth.redirectURI(port: 54321), clientID: "oaiapp_123")
        let query = parameters(ChatGPTOAuth.authorizationURL(for: attempt, hostID: "urn:uuid:host", loginHint: "me+hush@example.com"))
        #expect(query["client_id"] == "oaiapp_123")
        #expect(query["agent_name_hint"] == nil)
        #expect(query["login_hint"] == "me+hush@example.com")
        #expect(query["redirect_uri"] == "http://127.0.0.1:54321/auth/callback")
    }

    // MARK: Callback

    @Test("A callback is accepted only with the right state, a code and the issued client ID")
    func callbacks() throws {
        let attempt = ChatGPTOAuth.Attempt.fresh(redirectURI: ChatGPTOAuth.redirectURI(port: 1455), clientID: nil)
        let base = "http://127.0.0.1:1455/auth/callback"
        let good = try ChatGPTOAuth.authorization(from: URL(string: "\(base)?code=abc&state=\(attempt.state)&client_id=oaiapp_9&scope=openid")!, for: attempt)
        #expect(good == .init(code: "abc", clientID: "oaiapp_9"))
        #expect(throws: ChatGPTOAuth.CallbackError.stateMismatch) {
            try ChatGPTOAuth.authorization(from: URL(string: "\(base)?code=abc&state=forged&client_id=oaiapp_9")!, for: attempt)
        }
        #expect(throws: ChatGPTOAuth.CallbackError.denied("access_denied")) {
            try ChatGPTOAuth.authorization(from: URL(string: "\(base)?error=access_denied&state=\(attempt.state)")!, for: attempt)
        }
        #expect(throws: ChatGPTOAuth.CallbackError.registrationIncomplete) {
            try ChatGPTOAuth.authorization(from: URL(string: "\(base)?code=abc&state=\(attempt.state)")!, for: attempt)
        }
        #expect(throws: ChatGPTOAuth.CallbackError.registrationIncomplete) {
            try ChatGPTOAuth.authorization(from: URL(string: "\(base)?code=abc&state=\(attempt.state)&client_id=dynamic_agent_client")!, for: attempt)
        }
        let returning = ChatGPTOAuth.Attempt.fresh(redirectURI: attempt.redirectURI, clientID: "oaiapp_9")
        #expect(try ChatGPTOAuth.authorization(from: URL(string: "\(base)?code=x&state=\(returning.state)")!, for: returning).clientID == "oaiapp_9")
        #expect(throws: ChatGPTOAuth.CallbackError.clientMismatch) {
            try ChatGPTOAuth.authorization(from: URL(string: "\(base)?code=x&state=\(returning.state)&client_id=oaiapp_other")!, for: returning)
        }
    }

    // MARK: Token requests

    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map {
            let pair = $0.split(separator: "=", maxSplits: 1).map(String.init)
            return (pair[0], pair.count > 1 ? pair[1].removingPercentEncoding ?? "" : "")
        })
    }

    @Test("Code exchange, refresh and revocation send exactly the documented fields, no secret")
    func tokenRequests() {
        let attempt = ChatGPTOAuth.Attempt.fresh(redirectURI: ChatGPTOAuth.redirectURI(port: 1455), clientID: nil)
        let exchange = ChatGPTOAuth.tokenRequest(code: "c0de", attempt: attempt, clientID: "oaiapp_9")
        #expect(exchange.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/token")
        #expect(exchange.httpMethod == "POST")
        #expect(form(exchange) == [
            "grant_type": "authorization_code", "client_id": "oaiapp_9", "code": "c0de",
            "code_verifier": attempt.verifier, "redirect_uri": "http://127.0.0.1:1455/auth/callback",
            "resource": "https://api.openai.com/v1",
        ])
        #expect(form(ChatGPTOAuth.refreshRequest(refreshToken: "r/t+1", clientID: "oaiapp_9")) == [
            "grant_type": "refresh_token", "client_id": "oaiapp_9", "refresh_token": "r/t+1", "resource": "https://api.openai.com/v1",
        ])
        let revoke = ChatGPTOAuth.revocationRequest(refreshToken: "rt", clientID: "oaiapp_9")
        #expect(revoke.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/revoke")
        #expect(form(revoke) == ["token": "rt", "token_type_hint": "refresh_token", "client_id": "oaiapp_9"])
    }

    @Test("Plan usage needs its own granted scope")
    func planScope() throws {
        let granted = try JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: Data(#"{"access_token":"a","refresh_token":"r","id_token":"i","token_type":"Bearer","expires_in":3600,"scope":"openid email chatgpt.tokens.use.direct"}"#.utf8))
        #expect(granted.grantsPlanUsage)
        let identityOnly = try JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: Data(#"{"access_token":"a","expires_in":3600,"scope":"openid email"}"#.utf8))
        #expect(!identityOnly.grantsPlanUsage)
    }

    // MARK: ID token

    private struct Signer {
        let key: SecKey
        let jwk: ChatGPTIDToken.JWK

        init(kid: String) throws {
            let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
            key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
            let publicKey = try #require(SecKeyCopyPublicKey(key))
            let der = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
            let (n, e) = try Self.modulusAndExponent(der)
            jwk = .init(kid: kid, kty: "RSA", alg: "RS256", n: n.base64URLEncoded, e: e.base64URLEncoded)
        }

        func token(_ claims: [String: Any], kid: String? = nil) throws -> String {
            let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": kid ?? jwk.kid!])
            let body = try JSONSerialization.data(withJSONObject: claims)
            let signing = "\(header.base64URLEncoded).\(body.base64URLEncoded)"
            let signature = try #require(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(signing.utf8) as CFData, nil) as Data?)
            return "\(signing).\(signature.base64URLEncoded)"
        }

        /// Reads INTEGER n and INTEGER e from a PKCS#1 RSAPublicKey sequence.
        static func modulusAndExponent(_ der: Data) throws -> (Data, Data) {
            var bytes = [UInt8](der)[...]
            func length() -> Int {
                let first = Int(bytes.removeFirst())
                guard first & 0x80 != 0 else { return first }
                return (0..<(first & 0x7F)).reduce(0) { value, _ in (value << 8) | Int(bytes.removeFirst()) }
            }
            func integer() -> Data { _ = bytes.removeFirst(); let count = length(); defer { bytes.removeFirst(count) }; return Data(bytes.prefix(count)) }
            _ = bytes.removeFirst(); _ = length()
            return (integer(), integer())
        }
    }

    private func claims(audience: String = "oaiapp_9", nonce: String = "n1", expires: Date = Date().addingTimeInterval(3600)) -> [String: Any] {
        ["iss": "https://auth.openai.com", "sub": "user-1", "aud": audience, "exp": expires.timeIntervalSince1970, "nonce": nonce, "email": "me@example.com"]
    }

    @Test("A correctly signed ID token gives the account; anything forged or stale is rejected")
    func idToken() throws {
        let signer = try Signer(kid: "k1")
        let keys = ChatGPTIDToken.JWKS(keys: [signer.jwk])
        let identity = try ChatGPTIDToken.validate(try signer.token(claims()), keys: keys, clientID: "oaiapp_9", nonce: "n1")
        #expect(identity == ChatGPTIdentity(subject: "user-1", email: "me@example.com", name: nil))

        let other = try Signer(kid: "k1")
        #expect(throws: ChatGPTIDToken.Failure.badSignature) {
            try ChatGPTIDToken.validate(try other.token(self.claims()), keys: keys, clientID: "oaiapp_9", nonce: "n1")
        }
        #expect(throws: ChatGPTIDToken.Failure.wrongAudience) {
            try ChatGPTIDToken.validate(try signer.token(self.claims(audience: "someone_else")), keys: keys, clientID: "oaiapp_9", nonce: "n1")
        }
        #expect(throws: ChatGPTIDToken.Failure.wrongNonce) {
            try ChatGPTIDToken.validate(try signer.token(self.claims(nonce: "replayed")), keys: keys, clientID: "oaiapp_9", nonce: "n1")
        }
        #expect(throws: ChatGPTIDToken.Failure.expired) {
            try ChatGPTIDToken.validate(try signer.token(self.claims(expires: Date().addingTimeInterval(-3600))), keys: keys, clientID: "oaiapp_9", nonce: "n1")
        }
        #expect(throws: ChatGPTIDToken.Failure.unknownKey) {
            try ChatGPTIDToken.validate(try signer.token(self.claims(), kid: "rotated"), keys: keys, clientID: "oaiapp_9", nonce: "n1")
        }
        let token = try signer.token(claims())
        let parts = token.split(separator: ".")
        let tampered = "\(parts[0]).\(Data(#"{"iss":"https://auth.openai.com","sub":"attacker","aud":"oaiapp_9","exp":9999999999,"nonce":"n1"}"#.utf8).base64URLEncoded).\(parts[2])"
        #expect(throws: ChatGPTIDToken.Failure.badSignature) {
            try ChatGPTIDToken.validate(tampered, keys: keys, clientID: "oaiapp_9", nonce: "n1")
        }
    }

    // MARK: Responses

    @Test("The request is a streamed, unstored Responses call with no rejected parameters")
    func responsesRequest() throws {
        let request = try ChatGPTResponses.request(model: "m", instructions: "rules", input: [.init(role: "user", content: "hi")], accessToken: "tok")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        #expect(body["instructions"] as? String == "rules")
        for rejected in ["temperature", "max_output_tokens", "top_p", "previous_response_id", "metadata", "user"] {
            #expect(body[rejected] == nil)
        }
    }

    @Test("The stream gives the text only after response.completed and maps documented failures")
    func stream() throws {
        var reader = ChatGPTResponses.StreamReader()
        for line in [
            "event: response.output_text.delta", #"data: {"type":"response.output_text.delta","delta":"Hallo "}"#, "",
            #"data: {"type":"response.output_text.delta","delta":"Klaus,"}"#, "",
            #"data: {"type":"response.completed","response":{}}"#, "",
        ] { try reader.consume(line: line) }
        try reader.finish()
        #expect(reader.text == "Hallo Klaus,")

        var unfinished = ChatGPTResponses.StreamReader()
        try unfinished.consume(line: #"data: {"type":"response.output_text.delta","delta":"Hal"}"#)
        #expect(throws: ChatGPTError.incomplete("The stream ended before response.completed")) { try unfinished.finish() }

        var limited = ChatGPTResponses.StreamReader()
        #expect(throws: ChatGPTError.usageLimitReached) {
            try limited.consume(line: #"data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#)
            try limited.consume(line: "")
        }
    }

    @Test("Errors before the stream map to what hush does next")
    func admissionErrors() {
        func error(_ status: Int, _ code: String?, _ param: String? = nil) -> ChatGPTError {
            var object: [String: Any] = [:]
            if let code { object["error"] = ["code": code, "param": param as Any] }
            return ChatGPTResponses.admissionError(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
        #expect(error(429, "subscription_sharing_usage_limit_exceeded") == .usageLimitReached)
        #expect(error(403, "subscription_sharing_user_not_eligible") == .notEligible(nil))
        #expect(error(503, "subscription_sharing_usage_unavailable") == .temporarilyUnavailable)
        #expect(error(400, "subscription_sharing_unsupported_capability", "input[0]") == .unsupported("input[0]"))
        #expect(error(401, "subscription_sharing_invalid_user") == .signInRequired)
        #expect(error(401, nil) == .signInRequired)
        #expect(error(503, nil) == .temporarilyUnavailable)
    }

    @Test("Only models listed for the account are offered")
    func models() {
        let body = Data(#"{"models":[{"slug":"gpt-a","display_name":"GPT A","visibility":"list"},{"slug":"gpt-hidden","visibility":"hide"},{"slug":"gpt-b"}]}"#.utf8)
        #expect(ChatGPTResponses.models(from: body) == [.init(slug: "gpt-a", displayName: "GPT A"), .init(slug: "gpt-b", displayName: "gpt-b")])
    }

    // MARK: Storage and callback listener

    @Test("Credentials live in the Keychain; sign-out keeps the registration and host, not the tokens")
    func credentialStore() throws {
        let store = ChatGPTCredentialStore(service: "com.decentralfreedom.hush.tests.chatgpt.\(UUID().uuidString)")
        defer { try? store.deleteAll() }
        let host = try store.hostID()
        #expect(host.hasPrefix("urn:uuid:"))
        #expect(try store.hostID() == host)
        try store.saveRegistration(.init(clientID: "oaiapp_9", identity: .init(subject: "user-1", email: "me@example.com", name: nil)))
        try store.saveSession(.init(accessToken: "a", refreshToken: "r", idToken: nil, expiresAt: Date().addingTimeInterval(30), scopes: ["chatgpt.tokens.use.direct"]))
        #expect(try store.session()?.needsRefresh() == true)
        try store.deleteSession()
        #expect(try store.session() == nil)
        #expect(try store.registration()?.clientID == "oaiapp_9")
    }

    @Test("The callback listener binds 127.0.0.1, answers only the callback path and hands over the URL")
    func loopback() async throws {
        let server = try ChatGPTLoopbackServer.start(preferredPort: 0)
        defer { server.stop() }
        #expect(server.port != 0)
        let (_, other) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/favicon.ico")!)
        #expect((other as? HTTPURLResponse)?.statusCode == 404)
        async let callback = server.callback(timeout: .seconds(5))
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/auth/callback?code=c&state=s")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let url = try await callback
        #expect(url.query == "code=c&state=s")
    }
}
