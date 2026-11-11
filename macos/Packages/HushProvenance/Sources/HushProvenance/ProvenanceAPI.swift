import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public enum ProvenanceAPI {
    public static func client(baseURL: URL) -> Client {
        Client(
            serverURL: baseURL,
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: URLSessionTransport()
        )
    }
}
