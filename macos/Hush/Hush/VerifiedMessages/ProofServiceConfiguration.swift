import Foundation

struct ProofServiceConfiguration: Equatable {
    static let productionServiceURL = URL(string: "https://behu.sh")!

    let serviceURL: URL
    let proofURLBaseURL: URL

    static var current: ProofServiceConfiguration {
        resolve()
    }

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> ProofServiceConfiguration {
        let environmentServiceURL = validURL(environment["HUSH_PROOF_SERVICE_URL"])
        let bundledServiceURL = validURL(infoDictionary["HushProofServiceURL"] as? String)
        let serviceURL = environmentServiceURL
            ?? bundledServiceURL
            ?? productionServiceURL

        let bundledShortURL = validURL(infoDictionary["HushProofShortURL"] as? String)
        let proofURLBaseURL = validURL(environment["HUSH_PROOF_SHORT_URL"])
            ?? environmentServiceURL?.appending(path: "s")
            ?? bundledShortURL
            ?? serviceURL.appending(path: "s")

        return ProofServiceConfiguration(
            serviceURL: serviceURL,
            proofURLBaseURL: proofURLBaseURL
        )
    }

    private static func validURL(_ value: String?) -> URL? {
        guard let value,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              (scheme == "https" || (scheme == "http" && isLoopback(host)))
        else {
            return nil
        }
        return components.url
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
