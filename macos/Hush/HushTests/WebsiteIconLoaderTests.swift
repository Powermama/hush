import Foundation
import ImageIO
import Testing
@testable import Hush

nonisolated private let liveWebsiteIconHost =
    ProcessInfo.processInfo.environment["HUSH_FAVICON_E2E_HOST"]

@Suite("Website exception icons")
struct WebsiteIconLoaderTests {
    @Test("Extracts standard and Apple touch icons from website HTML")
    func extractsIconLinks() throws {
        let html = """
        <html><head>
          <link rel="stylesheet" href="/styles.css">
          <link rel="icon" href="/favicon-32.png">
          <link href="https://cdn.example.com/touch.png" rel="apple-touch-icon">
        </head></html>
        """
        let baseURL = try #require(URL(string: "https://example.com/account"))
        let standardIcon = try #require(URL(string: "https://example.com/favicon-32.png"))
        let touchIcon = try #require(URL(string: "https://cdn.example.com/touch.png"))

        #expect(WebsiteIconLoader.iconURLs(in: html, baseURL: baseURL) == [
            standardIcon,
            touchIcon,
        ])
    }

    @Test("Rejects embedded data and insecure cross-origin icons")
    func rejectsUnsafeIconLinks() throws {
        let html = """
        <link rel="icon" href="data:image/png;base64,private">
        <link rel="icon" href="http://tracker.example/icon.png">
        """
        let baseURL = try #require(URL(string: "https://example.com"))

        #expect(WebsiteIconLoader.iconURLs(in: html, baseURL: baseURL).isEmpty)
    }

    @Test(
        "Fetches and decodes a real website icon",
        .enabled(if: liveWebsiteIconHost != nil)
    )
    func fetchesLiveWebsiteIcon() async throws {
        let host = try #require(liveWebsiteIconHost)
        let data = try #require(await WebsiteIconLoader().iconData(for: host))

        #expect(!data.isEmpty)
        #expect(CGImageSourceCreateWithData(data as CFData, nil) != nil)
    }
}
