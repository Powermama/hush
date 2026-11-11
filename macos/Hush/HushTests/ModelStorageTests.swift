import Foundation
import Testing
@testable import Hush
#if canImport(HuggingFace)
import HuggingFace
#endif
#if canImport(WhisperKit)
import WhisperKit
#endif

@MainActor
@Suite("Model storage")
struct ModelStorageTests {
    @Test("An allowed bundled ID is only installed when its complete files exist")
    func bundledAvailabilityUsesPhysicalFiles() {
        let actual = Set(ModelInfo.bundledEntries.map(\.id))
        for id in ModelInfo.bundledIDs {
            let available = actual.contains(id) || ModelManager.isInCache(id)
            #expect(ModelManager.isAvailable(id) == available)
            #expect(ModelManager.availableIDs().contains(id) == available)
        }
    }

    @Test("Every downloadable AI model lives in Hush application data")
    func usesApplicationSupport() {
        let root = AIModelStorage.root.standardizedFileURL.path
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .standardizedFileURL.path
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .standardizedFileURL.path

        #expect(root.hasPrefix(applicationSupport + "/"))
        #expect(!root.hasPrefix(documents + "/"))
        #expect(ModelManager.huggingFaceRoot.path.hasPrefix(root + "/"))
        #expect(ModelManager.cacheRoot.path.hasPrefix(root + "/"))
        #expect(AIModelStorage.qwenHuggingFaceHubRoot.path.hasPrefix(root + "/"))

        for model in LLMRuntime.QwenModel.allCases {
            #expect(LLMRuntime.qwenCacheURL(for: model).path.hasPrefix(root + "/"))
            #expect(!LLMRuntime.qwenCacheURL(for: model).path.contains("/.cache/huggingface/"))
        }
    }

    #if canImport(HuggingFace)
    @Test("Qwen downloader uses the private Hush Hub cache")
    func qwenDownloaderUsesExplicitCache() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let client = LLMRuntime.makeQwenHubClient(session: session)
        #expect(
            client.cache?.cacheDirectory.standardizedFileURL
                == AIModelStorage.qwenHuggingFaceHubRoot.standardizedFileURL
        )
    }
    #endif

    #if canImport(WhisperKit)
    @Test("The bundled default model is complete and never needs a tokenizer download")
    func bundledModelIsOfflineComplete() throws {
        let folder = try #require(WhisperKitTranscriber.bundledModelFolder(for: "base"))
        let root = URL(fileURLWithPath: folder, isDirectory: true)

        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("tokenizer.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("tokenizer_config.json").path
        ))
    }

    @Test("Whisper model and tokenizer clients use Hush application data")
    func whisperConfigurationHasNoImplicitDocumentsFallback() {
        let configuration = WhisperKitTranscriber.makeConfiguration(
            modelID: "base",
            modelFolder: "/tmp/example-model"
        )

        #expect(
            configuration.downloadBase?.standardizedFileURL
                == AIModelStorage.whisperHuggingFaceRoot.standardizedFileURL
        )
        #expect(
            configuration.tokenizerFolder?.standardizedFileURL
                == AIModelStorage.whisperHuggingFaceRoot.standardizedFileURL
        )
        #expect(configuration.prewarm == false)
    }
    #endif

    @Test("Legacy migration moves only Hush Qwen repositories")
    func migratesOnlySupportedRepositories() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("HushModelStorageTests-\(UUID().uuidString)", isDirectory: true)
        let legacy = temporary.appendingPathComponent("legacy", isDirectory: true)
        let destination = temporary.appendingPathComponent("destination", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let supported = AIModelStorage.qwenRepositoryFolders[0]
        let unrelated = "models--someone-else--unrelated-model"
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent(supported, isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent(unrelated, isDirectory: true),
            withIntermediateDirectories: true
        )
        let legacyLock = legacy
            .appendingPathComponent(".locks", isDirectory: true)
            .appendingPathComponent(supported, isDirectory: true)
        try FileManager.default.createDirectory(at: legacyLock, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(
            atPath: legacyLock.appendingPathComponent("blob.lock").path,
            contents: Data()
        )

        let migrated = try AIModelStorage.migrateLegacyQwenRepositories(
            from: legacy,
            to: destination
        )

        #expect(migrated == [supported])
        #expect(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(supported).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: legacy.appendingPathComponent(supported).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: legacy.appendingPathComponent(unrelated).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: destination
                .appendingPathComponent(".locks")
                .appendingPathComponent(supported)
                .appendingPathComponent("blob.lock").path
        ))
        #expect(!FileManager.default.fileExists(atPath: legacyLock.path))
    }
}
