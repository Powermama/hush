import Foundation
import ImageIO

actor WebsiteIconLoader {
    static let shared = WebsiteIconLoader()

    private static let maximumImageBytes = 1_500_000
    private static let maximumHTMLBytes = 750_000

    private let session: URLSession
    private var memoryCache: [String: Data] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func iconData(for host: String) async -> Data? {
        guard let normalizedHost = VerifiedMessageWebsiteException.normalized(host) else {
            return nil
        }
        if let cached = memoryCache[normalizedHost] {
            return cached
        }
        if let cached = Self.readDiskCache(for: normalizedHost) {
            memoryCache[normalizedHost] = cached
            return cached
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--website-icon-test-fixture"),
           let fixture = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
           ) {
            memoryCache[normalizedHost] = fixture
            return fixture
        }
        #endif

        guard let rootURL = URL(string: "https://\(normalizedHost)/") else { return nil }
        if let data = await fetchImage(from: rootURL.appending(path: "favicon.ico")) {
            memoryCache[normalizedHost] = data
            Self.writeDiskCache(data, for: normalizedHost)
            return data
        }

        guard let html = await fetchHTML(from: rootURL) else { return nil }
        let candidates = Self.iconURLs(in: html, baseURL: rootURL)
        var visited = Set<URL>()
        for candidate in candidates where visited.insert(candidate).inserted {
            guard let data = await fetchImage(from: candidate) else { continue }
            memoryCache[normalizedHost] = data
            Self.writeDiskCache(data, for: normalizedHost)
            return data
        }
        return nil
    }

    nonisolated static func iconURLs(in html: String, baseURL: URL) -> [URL] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let tagExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        return tagExpression.matches(in: html, range: range).compactMap { match in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let tag = String(html[tagRange])
            guard let relation = attribute("rel", in: tag)?.lowercased(),
                  relation.split(whereSeparator: \.isWhitespace).contains(where: {
                    $0 == "icon" || $0 == "apple-touch-icon"
                  }),
                  let href = attribute("href", in: tag),
                  !href.lowercased().hasPrefix("data:"),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  url.scheme?.lowercased() == "https" else { return nil }
            return url
        }
    }

    private nonisolated static func attribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\b\(escapedName)\\s*=\\s*([\\\"'])(.*?)\\1"
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, range: range),
              let valueRange = Range(match.range(at: 2), in: tag) else { return nil }
        return String(tag[valueRange])
    }

    private func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              Self.isSuccessful(response),
              data.count <= Self.maximumHTMLBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func fetchImage(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/avif,image/webp,image/png,image/*,*/*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              Self.isSuccessful(response),
              data.count <= Self.maximumImageBytes,
              Self.isImage(data) else { return nil }
        return data
    }

    private nonisolated static func isSuccessful(_ response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(response.statusCode)
    }

    private nonisolated static func isImage(_ data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil) != nil
    }

    private nonisolated static func cacheURL(for host: String) -> URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let safeHost = host.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "_"
        }.joined()
        return caches
            .appending(path: "com.decentralfreedom.hush/WebsiteIcons", directoryHint: .isDirectory)
            .appending(path: safeHost)
    }

    private nonisolated static func readDiskCache(for host: String) -> Data? {
        guard let url = cacheURL(for: host),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate,
              modifiedAt > Date().addingTimeInterval(-30 * 24 * 60 * 60),
              let data = try? Data(contentsOf: url),
              data.count <= maximumImageBytes,
              isImage(data) else { return nil }
        return data
    }

    private nonisolated static func writeDiskCache(_ data: Data, for host: String) {
        guard let url = cacheURL(for: host) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
