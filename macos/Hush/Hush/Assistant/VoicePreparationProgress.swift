import Foundation

/// A file percentage is deliberately not presented as overall setup progress.
/// Core ML loading has no measurable denominator and stays a named stage.
nonisolated enum VoicePreparationProgress: Equatable, Sendable {
    case checking, pronunciation(Int?), file(Int, Int?), loading, warming

    var label: String {
        switch self {
        case .checking: "Checking voice files…"
        case .pronunciation(let percent): "Downloading pronunciation" + (percent.map { " · \($0)%" } ?? "")
        case .file(let index, let percent): "Downloading voice file \(index)" + (percent.map { " · \($0)%" } ?? "")
        case .loading: "Preparing voice on this Mac…"
        case .warming: "Warming up the voice…"
        }
    }
    var fraction: Double? {
        switch self {
        case .pronunciation(let percent), .file(_, let percent): percent.map { Double($0) / 100 }
        default: nil
        }
    }
    static func percentage(received: Int64, expected: Int64) -> Int? {
        guard expected > 0 else { return nil }
        return Int((min(1, max(0, Double(received) / Double(expected))) * 100).rounded(.down))
    }
    static func isVoiceAsset(_ url: URL?) -> Bool {
        guard let url, url.host == "huggingface.co" else { return false }
        return url.path.hasPrefix("/FluidInference/kokoro-82m-coreml/resolve/")
    }
}

/// Observe the SDK's public session without intercepting or replacing downloads.
/// Retries of a URL keep the same file index. No URL or user data is retained.
nonisolated enum VoiceTransferObserver {
    static func observe(session: URLSession, matching: @escaping @Sendable (URL?) -> Bool = VoicePreparationProgress.isVoiceAsset, report: @escaping @MainActor @Sendable (VoicePreparationProgress) -> Void) async {
        var files: [URL: Int] = [:]
        while !Task.isCancelled {
            let tasks = await session.allTasks
            guard !Task.isCancelled else { return }
            if let task = tasks.first(where: { matching($0.originalRequest?.url) }),
               let url = task.originalRequest?.url {
                if files[url] == nil { files[url] = files.count + 1 }
                let percent = VoicePreparationProgress.percentage(received: task.countOfBytesReceived, expected: task.countOfBytesExpectedToReceive)
                await report(.file(files[url]!, percent))
            } else {
                await report(.loading)
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }
}
