import Combine
import Foundation
import HushProvenance
import SwiftData

struct RecentInsert: Equatable, Identifiable {
    let id: UUID
    let text: String
    let appName: String
    let createdAt: Date
}

struct DictationActivity: Equatable, Identifiable {
    let id: UUID
    let text: String
    let appName: String
    let appBundleIdentifier: String?
    let createdAt: Date
    let duration: TimeInterval
    let wordCount: Int
    let modelName: String
    let personaName: String?
    let providerName: String?
    let copiedToClipboard: Bool
    var proofId: String? = nil
    var proofCommitment: String? = nil
    var provenanceEvents: [ProofManifest.ProvenanceEvent] = []
    var sourceText: String? = nil

    var isHushEditorOutput: Bool {
        duration == 0 && modelName == "hush Editor"
    }
}

struct ActivityMetrics: Equatable {
    var words = 0
    var speechDuration: TimeInterval = 0
    var estimatedTimeSaved: TimeInterval = 0
    var dictations = 0
}

struct AppActivity: Equatable, Identifiable {
    var id: String { bundleIdentifier ?? name }
    let name: String
    let bundleIdentifier: String?
    let count: Int
    let words: Int
    let speechDuration: TimeInterval
    let estimatedTimeSaved: TimeInterval
    let fraction: Double
}

struct DailyActivityPoint: Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let words: Int
    let dictations: Int
}

enum ActivityRange: String, CaseIterable, Hashable {
    case today
    case sevenDays
    case thirtyDays
    case allTime

    var title: String {
        switch self {
        case .today: return "Today"
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .allTime: return "All"
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .sevenDays:
            return date >= calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        case .thirtyDays:
            return date >= calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        case .allTime:
            return true
        }
    }
}

@Model
final class DictationActivityEntity {
    @Attribute(.unique) var id: UUID
    var text: String
    var appName: String
    var appBundleIdentifier: String?
    var createdAt: Date
    var duration: Double
    var wordCount: Int
    var modelID: String
    var modelName: String
    var personaName: String?
    var providerName: String?
    var copiedToClipboard: Bool
    var proofId: String?
    var proofCommitment: String?
    var provenanceEventsJSON: Data?
    var sourceText: String?

    init(
        id: UUID = UUID(),
        text: String,
        appName: String,
        appBundleIdentifier: String?,
        createdAt: Date = Date(),
        duration: Double,
        wordCount: Int,
        modelID: String,
        modelName: String,
        personaName: String?,
        providerName: String?,
        copiedToClipboard: Bool,
        proofId: String? = nil,
        proofCommitment: String? = nil,
        provenanceEventsJSON: Data? = nil,
        sourceText: String? = nil
    ) {
        self.id = id
        self.text = text
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.createdAt = createdAt
        self.duration = duration
        self.wordCount = wordCount
        self.modelID = modelID
        self.modelName = modelName
        self.personaName = personaName
        self.providerName = providerName
        self.copiedToClipboard = copiedToClipboard
        self.proofId = proofId
        self.proofCommitment = proofCommitment
        self.provenanceEventsJSON = provenanceEventsJSON
        self.sourceText = sourceText
    }
}

@Model
final class DailyActivityEntity {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var words: Int
    var speechDuration: Double
    var estimatedTimeSaved: Double
    var dictations: Int
    var destinationsJSON: Data

    init(dayKey: String, date: Date) {
        self.dayKey = dayKey
        self.date = date
        self.words = 0
        self.speechDuration = 0
        self.estimatedTimeSaved = 0
        self.dictations = 0
        self.destinationsJSON = Data()
    }
}

@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published private(set) var history: [DictationActivity] = []
    @Published private(set) var recentInserts: [RecentInsert] = []
    @Published private(set) var revision = 0

    private static let legacyStorageKey = "recentInserts.v1"
    private static let migrationKey = "activityStore.didImportRecent.v1"
    private static let destinationAggregateMigrationKey = "activityStore.didUpgradeDestinationAggregates.v2"
    private let container: ModelContainer
    private let context: ModelContext
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let schema = Schema([DictationActivityEntity.self, DailyActivityEntity.self])
        do {
            let configuration = ModelConfiguration("HushActivity", schema: schema)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let fallback = ModelConfiguration("HushActivityFallback", schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [fallback])
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
        importLegacyRecentsIfNeeded()
        upgradeLegacyDestinationAggregatesIfNeeded()
        applyRetentionPolicy()
        reloadHistory()
    }

    func record(
        text: String,
        appName: String,
        appBundleIdentifier: String?,
        duration: TimeInterval,
        modelID: String,
        modelName: String,
        personaName: String?,
        providerName: String?,
        copiedToClipboard: Bool,
        proofId: String? = nil,
        proofCommitment: String? = nil,
        provenanceEvents: [ProofManifest.ProvenanceEvent] = [],
        sourceText: String? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let words = trimmed.split { $0.isWhitespace }.count
        updateDailySummary(
            createdAt: Date(),
            words: words,
            duration: duration,
            destinationName: appName,
            destinationBundleIdentifier: appBundleIdentifier
        )

        if Settings.shared.historyRetention != .off {
            context.insert(DictationActivityEntity(
                text: trimmed,
                appName: appName,
                appBundleIdentifier: appBundleIdentifier,
                duration: duration,
                wordCount: words,
                modelID: modelID,
                modelName: modelName,
                personaName: personaName,
                providerName: providerName,
                copiedToClipboard: copiedToClipboard,
                proofId: proofId,
                proofCommitment: proofCommitment,
                provenanceEventsJSON: Self.encodeProvenanceEvents(provenanceEvents),
                sourceText: sourceText
            ))
        }

        saveAndReload()
    }

    /// Retains text created or edited inside Hush so the contextual shortcut can
    /// reopen it later. Editor output is deliberately excluded from voice activity
    /// and time-saved metrics.
    func recordEditorOutput(
        text: String,
        appName: String,
        appBundleIdentifier: String?,
        personaName: String?,
        providerName: String?,
        copiedToClipboard: Bool,
        proofId: String? = nil,
        proofCommitment: String? = nil,
        provenanceEvents: [ProofManifest.ProvenanceEvent] = [],
        sourceText: String? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Settings.shared.historyRetention != .off else { return }

        context.insert(DictationActivityEntity(
            text: trimmed,
            appName: appName,
            appBundleIdentifier: appBundleIdentifier,
            duration: 0,
            wordCount: trimmed.split { $0.isWhitespace }.count,
            modelID: "hush-editor",
            modelName: "hush Editor",
            personaName: personaName,
            providerName: providerName,
            copiedToClipboard: copiedToClipboard,
            proofId: proofId,
            proofCommitment: proofCommitment,
            provenanceEventsJSON: Self.encodeProvenanceEvents(provenanceEvents),
            sourceText: sourceText
        ))
        saveAndReload()
    }

    /// Counts a voice section recorded inside the composer without retaining a
    /// duplicate history message. The completed editor output is stored once
    /// when the composer is committed.
    func recordComposerVoiceSegment(
        text: String,
        duration: TimeInterval,
        destinationName: String,
        destinationBundleIdentifier: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateDailySummary(
            createdAt: Date(),
            words: trimmed.split { $0.isWhitespace }.count,
            duration: duration,
            destinationName: destinationName,
            destinationBundleIdentifier: destinationBundleIdentifier
        )
        do { try context.save() } catch { context.rollback() }
        revision += 1
    }

    func delete(_ id: UUID) {
        guard let entity = fetchHistoryEntities().first(where: { $0.id == id }) else { return }
        context.delete(entity)
        saveAndReload()
    }

    func clearHistory() {
        for entity in fetchHistoryEntities() { context.delete(entity) }
        saveAndReload()
    }

    func resetActivity() {
        for entity in fetchDailyEntities() { context.delete(entity) }
        try? context.save()
        revision += 1
    }

    func applyRetentionPolicy(now: Date = Date()) {
        guard let days = Settings.shared.historyRetention.days else {
            reloadHistory()
            return
        }
        if days == 0 {
            let entities = fetchHistoryEntities()
            for entity in entities { context.delete(entity) }
            if !entities.isEmpty {
                do { try context.save() } catch { context.rollback() }
            }
            reloadHistory()
            return
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        var changed = false
        for entity in fetchHistoryEntities() where entity.createdAt < cutoff {
            context.delete(entity)
            changed = true
        }
        if changed { try? context.save() }
        reloadHistory()
    }

    func metrics(for range: ActivityRange, now: Date = Date()) -> ActivityMetrics {
        let typingWordsPerMinute = Settings.shared.typingWordsPerMinute
        return fetchDailyEntities()
            .filter { range.contains($0.date, now: now) }
            .reduce(into: ActivityMetrics()) { result, entity in
                result.words += entity.words
                result.speechDuration += entity.speechDuration
                result.estimatedTimeSaved += entity.words > 0
                    ? max(0, Double(entity.words) / typingWordsPerMinute * 60 - entity.speechDuration)
                    : entity.estimatedTimeSaved
                result.dictations += entity.dictations
            }
    }

    func destinations(for range: ActivityRange, now: Date = Date()) -> [AppActivity] {
        var totals: [DestinationKey: DestinationAggregate] = [:]
        for entity in fetchDailyEntities() where range.contains(entity.date, now: now) {
            for (destination, aggregate) in decodeDestinations(entity.destinationsJSON) {
                totals[destination, default: .zero].merge(aggregate)
            }
        }
        let typingWordsPerMinute = Settings.shared.typingWordsPerMinute
        let savedByDestination = totals.mapValues { aggregate in
            aggregate.words > 0
                ? max(0, Double(aggregate.words) / typingWordsPerMinute * 60 - aggregate.speechDuration)
                : aggregate.estimatedTimeSaved
        }
        let savedTotal = savedByDestination.values.reduce(0, +)
        let countTotal = max(1, totals.values.reduce(0) { $0 + $1.count })
        return totals
            .map { key, aggregate in
                let estimatedTimeSaved = savedByDestination[key] ?? 0
                let fraction = savedTotal > 0
                    ? estimatedTimeSaved / savedTotal
                    : Double(aggregate.count) / Double(countTotal)
                return AppActivity(
                    name: key.name,
                    bundleIdentifier: key.bundleIdentifier,
                    count: aggregate.count,
                    words: aggregate.words,
                    speechDuration: aggregate.speechDuration,
                    estimatedTimeSaved: estimatedTimeSaved,
                    fraction: fraction
                )
            }
            .sorted { lhs, rhs in
                if lhs.estimatedTimeSaved != rhs.estimatedTimeSaved {
                    return lhs.estimatedTimeSaved > rhs.estimatedTimeSaved
                }
                return lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
            }
    }

    func dailyActivity(for range: ActivityRange, now: Date = Date()) -> [DailyActivityPoint] {
        let points = fetchDailyEntities()
            .filter { range.contains($0.date, now: now) }
            .map { DailyActivityPoint(date: $0.date, words: $0.words, dictations: $0.dictations) }
            .sorted { $0.date < $1.date }

        let numberOfDays: Int
        switch range {
        case .sevenDays: numberOfDays = 7
        case .thirtyDays: numberOfDays = 30
        case .today, .allTime: return points
        }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(numberOfDays - 1), to: end) ?? end
        let pointsByDay = Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0) })
        return (0..<numberOfDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return pointsByDay[date] ?? DailyActivityPoint(date: date, words: 0, dictations: 0)
        }
    }

    private func updateDailySummary(
        createdAt: Date,
        words: Int,
        duration: TimeInterval,
        destinationName: String,
        destinationBundleIdentifier: String?
    ) {
        let startOfDay = Calendar.current.startOfDay(for: createdAt)
        let dayKey = Self.dayFormatter.string(from: startOfDay)
        let entity = fetchDailyEntities().first(where: { $0.dayKey == dayKey })
            ?? DailyActivityEntity(dayKey: dayKey, date: startOfDay)
        if entity.modelContext == nil { context.insert(entity) }

        let typingDuration = Double(words) / Settings.shared.typingWordsPerMinute * 60
        entity.words += words
        entity.speechDuration += max(0, duration)
        entity.estimatedTimeSaved += max(0, typingDuration - duration)
        entity.dictations += 1

        var destinations = decodeDestinations(entity.destinationsJSON)
        let destination = DestinationKey(name: destinationName, bundleIdentifier: destinationBundleIdentifier)
        var aggregate = destinations[destination, default: .zero]
        aggregate.count += 1
        aggregate.words += words
        aggregate.speechDuration += max(0, duration)
        aggregate.estimatedTimeSaved += max(0, typingDuration - duration)
        destinations[destination] = aggregate
        entity.destinationsJSON = (try? JSONEncoder().encode(destinations)) ?? Data()
    }

    private func decodeDestinations(_ data: Data) -> [DestinationKey: DestinationAggregate] {
        if let current = try? JSONDecoder().decode([DestinationKey: DestinationAggregate].self, from: data) {
            return current
        }
        let legacy = (try? JSONDecoder().decode([DestinationKey: Int].self, from: data)) ?? [:]
        return legacy.mapValues { DestinationAggregate(count: $0, words: 0, speechDuration: 0, estimatedTimeSaved: 0) }
    }

    private func saveAndReload() {
        do { try context.save() } catch { context.rollback() }
        applyRetentionPolicy()
        revision += 1
    }

    private func reloadHistory() {
        history = fetchHistoryEntities().map {
            DictationActivity(
                id: $0.id,
                text: $0.text,
                appName: $0.appName,
                appBundleIdentifier: $0.appBundleIdentifier,
                createdAt: $0.createdAt,
                duration: $0.duration,
                wordCount: $0.wordCount,
                modelName: $0.modelName,
                personaName: $0.personaName,
                providerName: $0.providerName,
                copiedToClipboard: $0.copiedToClipboard,
                proofId: $0.proofId,
                proofCommitment: $0.proofCommitment,
                provenanceEvents: Self.decodeProvenanceEvents($0.provenanceEventsJSON),
                sourceText: $0.sourceText
            )
        }
        recentInserts = history.prefix(3).map {
            RecentInsert(id: $0.id, text: $0.text, appName: $0.appName, createdAt: $0.createdAt)
        }
    }

    private func fetchHistoryEntities() -> [DictationActivityEntity] {
        let descriptor = FetchDescriptor<DictationActivityEntity>(
            sortBy: [SortDescriptor(\DictationActivityEntity.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func encodeProvenanceEvents(
        _ events: [ProofManifest.ProvenanceEvent]
    ) -> Data? {
        events.isEmpty ? nil : try? JSONEncoder().encode(events)
    }

    private static func decodeProvenanceEvents(
        _ data: Data?
    ) -> [ProofManifest.ProvenanceEvent] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ProofManifest.ProvenanceEvent].self, from: data)) ?? []
    }

    private func fetchDailyEntities() -> [DailyActivityEntity] {
        let descriptor = FetchDescriptor<DailyActivityEntity>(
            sortBy: [SortDescriptor(\DailyActivityEntity.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func importLegacyRecentsIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        defer { defaults.set(true, forKey: Self.migrationKey) }
        guard let data = defaults.data(forKey: Self.legacyStorageKey),
              let legacy = try? JSONDecoder().decode([LegacyRecentInsert].self, from: data) else { return }

        for item in legacy where !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.insert(DictationActivityEntity(
                id: item.id,
                text: item.text,
                appName: item.appName,
                appBundleIdentifier: nil,
                createdAt: item.createdAt,
                duration: 0,
                wordCount: item.text.split { $0.isWhitespace }.count,
                modelID: "",
                modelName: "Unknown",
                personaName: nil,
                providerName: nil,
                copiedToClipboard: item.appName == "Clipboard"
            ))
        }
        try? context.save()
    }

    private func upgradeLegacyDestinationAggregatesIfNeeded() {
        guard !defaults.bool(forKey: Self.destinationAggregateMigrationKey) else { return }
        defer { defaults.set(true, forKey: Self.destinationAggregateMigrationKey) }

        let historyEntities = fetchHistoryEntities()
        var changed = false
        for day in fetchDailyEntities() {
            guard (try? JSONDecoder().decode([DestinationKey: DestinationAggregate].self, from: day.destinationsJSON)) == nil,
                  let legacy = try? JSONDecoder().decode([DestinationKey: Int].self, from: day.destinationsJSON),
                  !legacy.isEmpty else { continue }

            let records = historyEntities.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day.date) }
            var exact: [DestinationKey: DestinationAggregate] = [:]
            for record in records {
                let key = DestinationKey(name: record.appName, bundleIdentifier: record.appBundleIdentifier)
                let typingDuration = Double(record.wordCount) / Settings.shared.typingWordsPerMinute * 60
                var aggregate = exact[key, default: .zero]
                aggregate.count += 1
                aggregate.words += record.wordCount
                aggregate.speechDuration += max(0, record.duration)
                aggregate.estimatedTimeSaved += max(0, typingDuration - record.duration)
                exact[key] = aggregate
            }

            let exactMatchesLegacy = exact.count == legacy.count && legacy.allSatisfy { exact[$0.key]?.count == $0.value }
            let upgraded = exactMatchesLegacy ? exact : proportionalAggregates(for: legacy, day: day)
            day.destinationsJSON = (try? JSONEncoder().encode(upgraded)) ?? day.destinationsJSON
            changed = true
        }
        if changed { try? context.save() }
    }

    private func proportionalAggregates(
        for legacy: [DestinationKey: Int],
        day: DailyActivityEntity
    ) -> [DestinationKey: DestinationAggregate] {
        let entries = legacy.sorted {
            ($0.key.bundleIdentifier ?? $0.key.name) < ($1.key.bundleIdentifier ?? $1.key.name)
        }
        let totalCount = max(1, entries.reduce(0) { $0 + $1.value })
        var remainingWords = day.words
        var remainingSpeech = day.speechDuration
        var remainingSaved = day.estimatedTimeSaved
        var result: [DestinationKey: DestinationAggregate] = [:]

        for (index, entry) in entries.enumerated() {
            let isLast = index == entries.count - 1
            let fraction = Double(entry.value) / Double(totalCount)
            let words = isLast ? remainingWords : min(remainingWords, Int((Double(day.words) * fraction).rounded()))
            let speech = isLast ? remainingSpeech : min(remainingSpeech, day.speechDuration * fraction)
            let saved = isLast ? remainingSaved : min(remainingSaved, day.estimatedTimeSaved * fraction)
            result[entry.key] = DestinationAggregate(
                count: entry.value,
                words: words,
                speechDuration: speech,
                estimatedTimeSaved: saved
            )
            remainingWords -= words
            remainingSpeech -= speech
            remainingSaved -= saved
        }
        return result
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct LegacyRecentInsert: Codable {
    let id: UUID
    let text: String
    let appName: String
    let createdAt: Date
}

private struct DestinationKey: Codable, Hashable {
    let name: String
    let bundleIdentifier: String?
}

private struct DestinationAggregate: Codable {
    var count: Int
    var words: Int
    var speechDuration: TimeInterval
    var estimatedTimeSaved: TimeInterval

    static let zero = DestinationAggregate(count: 0, words: 0, speechDuration: 0, estimatedTimeSaved: 0)

    mutating func merge(_ other: DestinationAggregate) {
        count += other.count
        words += other.words
        speechDuration += other.speechDuration
        estimatedTimeSaved += other.estimatedTimeSaved
    }
}
