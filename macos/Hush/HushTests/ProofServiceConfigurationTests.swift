import Foundation
import Testing
@testable import Hush

struct ProofServiceConfigurationTests {
    @Test func releaseConfigurationUsesBundledProductionURLs() throws {
        let configuration = ProofServiceConfiguration.resolve(
            environment: [:],
            infoDictionary: [
                "HushProofServiceURL": "https://behu.sh",
                "HushProofShortURL": "https://behu.sh/s/",
            ]
        )

        #expect(configuration.serviceURL == URL(string: "https://behu.sh"))
        #expect(configuration.proofURLBaseURL == URL(string: "https://behu.sh/s/"))
    }

    @Test func environmentCanSelectLocalDevelopmentServer() throws {
        let configuration = ProofServiceConfiguration.resolve(
            environment: [
                "HUSH_PROOF_SERVICE_URL": "http://127.0.0.1:3000",
                "HUSH_PROOF_SHORT_URL": "http://127.0.0.1:3000/s/",
            ],
            infoDictionary: [
                "HushProofServiceURL": "https://behu.sh",
                "HushProofShortURL": "https://behu.sh/s/",
            ]
        )

        #expect(configuration.serviceURL == URL(string: "http://127.0.0.1:3000"))
        #expect(configuration.proofURLBaseURL == URL(string: "http://127.0.0.1:3000/s/"))
    }

    @Test func serviceOverrideDerivesMatchingShortURL() throws {
        let configuration = ProofServiceConfiguration.resolve(
            environment: ["HUSH_PROOF_SERVICE_URL": "http://localhost:4000"],
            infoDictionary: [
                "HushProofServiceURL": "https://behu.sh",
                "HushProofShortURL": "https://behu.sh/s/",
            ]
        )

        #expect(configuration.serviceURL == URL(string: "http://localhost:4000"))
        #expect(configuration.proofURLBaseURL == URL(string: "http://localhost:4000/s"))
    }

    @Test func unsafeRemoteHTTPOverrideFailsClosed() throws {
        let configuration = ProofServiceConfiguration.resolve(
            environment: [
                "HUSH_PROOF_SERVICE_URL": "http://example.com",
                "HUSH_PROOF_SHORT_URL": "https://behu.sh/s/?redirect=other",
            ],
            infoDictionary: [:]
        )

        #expect(configuration.serviceURL == ProofServiceConfiguration.productionServiceURL)
        #expect(configuration.proofURLBaseURL == URL(string: "https://behu.sh/s"))
    }
}
