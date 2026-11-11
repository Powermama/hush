import AppKit
import Charts
import Combine
import SwiftUI

@MainActor
final class DashboardViewController: NSViewController {
    private weak var coordinator: DictationCoordinator?
    private let previewMode: Bool
    private let onNavigate: (HushDestination) -> Void
    private let onRangeChanged: (ActivityRange) -> Void
    private let model = DashboardViewModel()
    private var subscriptions = Set<AnyCancellable>()

    init(
        coordinator: DictationCoordinator?,
        previewMode: Bool,
        initialRange: ActivityRange = .sevenDays,
        onNavigate: @escaping (HushDestination) -> Void,
        onRangeChanged: @escaping (ActivityRange) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.previewMode = previewMode
        self.onNavigate = onNavigate
        self.onRangeChanged = onRangeChanged
        model.selectedRange = initialRange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = DashboardRootView(
            model: model,
            onNavigate: onNavigate,
            onCopy: Self.copy
        )
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        view = host
        bind()
        refresh()
    }

    private func bind() {
        model.$selectedRange
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] range in
                self?.onRangeChanged(range)
                self?.refresh()
            }
            .store(in: &subscriptions)

        guard !previewMode else { return }
        ActivityStore.shared.$revision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        LLMRuntime.shared.stateChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshLocalSetup() }
            .store(in: &subscriptions)
        coordinator?.phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLocalSetup() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        let preview = previewMode ? Self.previewData : nil
        model.metrics = preview?.metrics ?? ActivityStore.shared.metrics(for: model.selectedRange)
        model.daily = preview?.daily ?? ActivityStore.shared.dailyActivity(for: model.selectedRange)
        model.destinations = preview?.destinations ?? ActivityStore.shared.destinations(for: model.selectedRange)
        model.history = preview?.history ?? ActivityStore.shared.history
        model.typingResults = previewMode
            ? [
                TypingTestResult(wordsPerMinute: 56, accuracy: 0.98),
                TypingTestResult(completedAt: Date().addingTimeInterval(-86_400), wordsPerMinute: 52, accuracy: 0.96),
            ]
            : Settings.shared.typingTestResults
        model.everydayTypingMeasurementEnabled = previewMode || Settings.shared.everydayTypingMeasurementEnabled
        model.everydayTypingSamples = previewMode ? Self.previewEverydayTypingSamples : Settings.shared.everydayTypingSamples
        refreshLocalSetup()
    }

    private func refreshLocalSetup() {
        let modelID = Settings.shared.modelID
        let rawModelName = ModelInfo.info(for: modelID)?.displayName ?? ModelInfo.deriveDisplayName(from: modelID)
        let modelName = rawModelName.replacingOccurrences(
            of: #"\s*\(\d+\s*MB\)$"#,
            with: "",
            options: .regularExpression
        )
        let modelStatus: String
        if previewMode || coordinator?.isModelReady == true {
            modelStatus = "Ready on this Mac"
        } else if case .modelLoading(let progress) = coordinator?.phase.value {
            modelStatus = "Loading \(Int(progress * 100))%"
        } else {
            modelStatus = "On this Mac"
        }

        let provider = Settings.shared.llmProvider
        model.localSetup = DashboardLocalSetup(
            modelName: modelName,
            modelStatus: modelStatus,
            personaName: provider == .off ? "Persona AI off" : Settings.shared.activeProfile.name,
            personaStatus: provider == .off ? "Optional" : "\(provider.displayName) on this Mac",
            personaIsOff: provider == .off,
            profileCount: Settings.shared.profiles.count
        )
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    fileprivate static var previewData: DashboardPreviewData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let words = [182, 346, 228, 512, 405, 267, 546]
        let points = words.enumerated().map { index, value in
            DailyActivityPoint(
                date: calendar.date(byAdding: .day, value: index - 6, to: today)!,
                words: value,
                dictations: max(1, value / 75)
            )
        }
        let destinations = [
            AppActivity(name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", count: 18, words: 1_043, speechDuration: 430, estimatedTimeSaved: 1_134, fraction: 0.42),
            AppActivity(name: "Mail", bundleIdentifier: "com.apple.mail", count: 13, words: 771, speechDuration: 316, estimatedTimeSaved: 841, fraction: 0.31),
            AppActivity(name: "Notes", bundleIdentifier: "com.apple.Notes", count: 8, words: 448, speechDuration: 193, estimatedTimeSaved: 479, fraction: 0.18),
            AppActivity(name: "Clipboard", bundleIdentifier: nil, count: 4, words: 224, speechDuration: 95, estimatedTimeSaved: 246, fraction: 0.09),
        ]
        let history = [
            DictationActivity(id: UUID(), text: "I wanted to follow up on our shipping timeline and confirm the final launch date.", appName: "Mail", appBundleIdentifier: "com.apple.mail", createdAt: Date().addingTimeInterval(-120), duration: 11, wordCount: 15, modelName: "Large v3", personaName: "Business", providerName: "Qwen 3 1.7B", copiedToClipboard: false),
            DictationActivity(id: UUID(), text: "Shipping the landing page today. I will send the preview when it is ready.", appName: "Slack", appBundleIdentifier: "com.tinyspeck.slackmacgap", createdAt: Date().addingTimeInterval(-1080), duration: 8, wordCount: 13, modelName: "Large v3", personaName: "Slack DM", providerName: "Qwen 3 1.7B", copiedToClipboard: false),
            DictationActivity(id: UUID(), text: "Review the onboarding flow before the next release candidate.", appName: "Notes", appBundleIdentifier: "com.apple.Notes", createdAt: Date().addingTimeInterval(-3500), duration: 6, wordCount: 9, modelName: "Large v3", personaName: nil, providerName: nil, copiedToClipboard: false),
        ]
        return DashboardPreviewData(
            metrics: ActivityMetrics(words: 2_486, speechDuration: 18 * 60, estimatedTimeSaved: 56 * 60, dictations: 43),
            daily: points,
            destinations: destinations,
            history: history
        )
    }

    fileprivate static var previewEverydayTypingSamples: [EverydayTypingSample] {
        [
            EverydayTypingSample(day: Date().addingTimeInterval(-86_400 * 3), characterCount: 920, activeDuration: 276),
            EverydayTypingSample(day: Date().addingTimeInterval(-86_400 * 2), characterCount: 1_140, activeDuration: 326),
            EverydayTypingSample(day: Date().addingTimeInterval(-86_400), characterCount: 780, activeDuration: 245),
            EverydayTypingSample(day: Date(), characterCount: 1_260, activeDuration: 350),
        ]
    }
}

@MainActor
final class TimeSavedInsightsViewController: NSViewController {
    private let previewMode: Bool
    private let onRangeChanged: (ActivityRange) -> Void
    private let model = DashboardViewModel()
    private var subscriptions = Set<AnyCancellable>()

    init(
        initialRange: ActivityRange,
        previewMode: Bool,
        onRangeChanged: @escaping (ActivityRange) -> Void = { _ in }
    ) {
        self.previewMode = previewMode
        self.onRangeChanged = onRangeChanged
        model.selectedRange = initialRange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSHostingView(rootView: TimeSavedInsightsRootView(model: model))
        host.sizingOptions = []
        view = host

        model.$selectedRange
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] range in
                self?.onRangeChanged(range)
                self?.refresh()
            }
            .store(in: &subscriptions)

        if !previewMode {
            ActivityStore.shared.$revision
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &subscriptions)
            Settings.shared.didChange
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.refresh() }
                .store(in: &subscriptions)
        }
        refresh()
    }

    private func refresh() {
        if previewMode {
            model.metrics = DashboardViewController.previewData.metrics
            model.typingResults = [
                TypingTestResult(wordsPerMinute: 56, accuracy: 0.98),
                TypingTestResult(completedAt: Date().addingTimeInterval(-86_400 * 3), wordsPerMinute: 52, accuracy: 0.96),
                TypingTestResult(completedAt: Date().addingTimeInterval(-86_400 * 8), wordsPerMinute: 49, accuracy: 0.97),
                TypingTestResult(completedAt: Date().addingTimeInterval(-86_400 * 14), wordsPerMinute: 54, accuracy: 0.95),
            ]
            model.everydayTypingMeasurementEnabled = true
            model.everydayTypingSamples = DashboardViewController.previewEverydayTypingSamples
        } else {
            model.metrics = ActivityStore.shared.metrics(for: model.selectedRange)
            model.typingResults = Settings.shared.typingTestResults
            model.everydayTypingMeasurementEnabled = Settings.shared.everydayTypingMeasurementEnabled
            model.everydayTypingSamples = Settings.shared.everydayTypingSamples
        }
    }
}

@MainActor
final class ActivityBreakdownViewController: NSViewController {
    private let previewMode: Bool
    private let model = DashboardViewModel()
    private var subscriptions = Set<AnyCancellable>()

    init(initialRange: ActivityRange, previewMode: Bool) {
        self.previewMode = previewMode
        model.selectedRange = initialRange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSHostingView(rootView: ActivityBreakdownRootView(model: model))
        host.sizingOptions = []
        view = host

        model.$selectedRange
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)

        if !previewMode {
            ActivityStore.shared.$revision
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &subscriptions)
            Settings.shared.didChange
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.refresh() }
                .store(in: &subscriptions)
        }
        refresh()
    }

    private func refresh() {
        if previewMode {
            model.metrics = DashboardViewController.previewData.metrics
            model.destinations = DashboardViewController.previewData.destinations
        } else {
            model.metrics = ActivityStore.shared.metrics(for: model.selectedRange)
            model.destinations = ActivityStore.shared.destinations(for: model.selectedRange)
        }
    }
}

@MainActor
private final class DashboardViewModel: ObservableObject {
    @Published var selectedRange: ActivityRange = .sevenDays
    @Published var metrics = ActivityMetrics()
    @Published var daily: [DailyActivityPoint] = []
    @Published var destinations: [AppActivity] = []
    @Published var history: [DictationActivity] = []
    @Published var typingResults: [TypingTestResult] = []
    @Published var everydayTypingSamples: [EverydayTypingSample] = []
    @Published var everydayTypingMeasurementEnabled = false
    @Published var localSetup = DashboardLocalSetup(
        modelName: "Transcription model",
        modelStatus: "On this Mac",
        personaName: "Persona AI off",
        personaStatus: "Optional",
        personaIsOff: true,
        profileCount: 1
    )

    var latestTypingResult: TypingTestResult? { typingResults.first }

    var averageTypingWordsPerMinute: Double? {
        guard !typingResults.isEmpty else { return nil }
        return typingResults.map(\.wordsPerMinute).reduce(0, +) / Double(typingResults.count)
    }

    var typingWordsPerMinute: Double {
        if everydayTypingMeasurementEnabled, let everydayTypingWordsPerMinute {
            return everydayTypingWordsPerMinute
        }
        return averageTypingWordsPerMinute ?? 40
    }

    var everydayTypingWordsPerMinute: Double? {
        let valid = everydayTypingSamples.filter { $0.characterCount > 0 && $0.activeDuration > 0 }
        let characters = valid.reduce(0) { $0 + $1.characterCount }
        let duration = valid.reduce(0) { $0 + $1.activeDuration }
        guard characters >= 100, duration >= 30 else { return nil }
        return (Double(characters) / 5) / (duration / 60)
    }

    var speechWordsPerMinute: Double? {
        guard metrics.words > 0, metrics.speechDuration > 0 else { return nil }
        return Double(metrics.words) / metrics.speechDuration * 60
    }

    var voiceSpeedMultiplier: Double? {
        guard let speechWordsPerMinute, typingWordsPerMinute > 0 else { return nil }
        return speechWordsPerMinute / typingWordsPerMinute
    }

}

private struct DashboardPreviewData {
    let metrics: ActivityMetrics
    let daily: [DailyActivityPoint]
    let destinations: [AppActivity]
    let history: [DictationActivity]
}

private struct DashboardLocalSetup: Equatable {
    let modelName: String
    let modelStatus: String
    let personaName: String
    let personaStatus: String
    let personaIsOff: Bool
    let profileCount: Int
}

private struct DashboardRootView: View {
    @ObservedObject var model: DashboardViewModel
    let onNavigate: (HushDestination) -> Void
    let onCopy: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                DashboardHero(
                    model: model,
                    onOpenDetails: { onNavigate(.timeSaved(range: model.selectedRange)) }
                )
                HStack(alignment: .top, spacing: 14) {
                    DashboardDestinations(
                        activities: Array(model.destinations.prefix(3)),
                        onViewAll: { onNavigate(.activity(range: model.selectedRange)) }
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    DashboardLocalStack(setup: model.localSetup, onNavigate: onNavigate)
                        .frame(width: 276)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                DashboardRecent(
                    items: Array(model.history.prefix(4)),
                    onViewAll: { onNavigate(.history()) },
                    onOpen: { onNavigate(.history(recordID: $0)) },
                    onCopy: onCopy
                )
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 34)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your voice at a glance")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.35)
                Text("Private activity insights from this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Activity range", selection: $model.selectedRange) {
                ForEach(ActivityRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 232)
        }
    }
}

private struct TimeSavedInsightsRootView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var showsTypingTest = false

    private let peach = Color(nsColor: DesignTokens.peach)

    init(model: DashboardViewModel) {
        self.model = model
        #if DEBUG
        _showsTypingTest = State(initialValue: ProcessInfo.processInfo.arguments.contains("--preview-typing-test"))
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                impactSummary
                activitySummary
                typingHistory
                paceComparison
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 34)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showsTypingTest) {
            TypingSpeedTestView(
                speechWordsPerMinute: model.speechWordsPerMinute,
                priorResults: model.typingResults
            )
            .frame(width: 820, height: 600)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your time advantage")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.35)
                Text("See how your voice compares with your measured typing pace.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Activity range", selection: $model.selectedRange) {
                ForEach(ActivityRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 232)
        }
    }

    private var impactSummary: some View {
        DashboardPanel(accented: true) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("VOICE ADVANTAGE")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(peach)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(model.voiceSpeedMultiplier.map { $0.formatted(.number.precision(.fractionLength(1))) + "×" } ?? "-")
                                .font(.system(size: 50, weight: .bold, design: .rounded))
                                .tracking(-1.6)
                                .contentTransition(.numericText())
                                .fixedSize(horizontal: true, vertical: false)
                            Text(advantageLabel)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text(paceDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(width: 1, height: 78)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TIME SAVED")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(model.metrics.estimatedTimeSaved.hushCompactDuration)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .fixedSize(horizontal: true, vertical: false)
                        Text(impactDetail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 170, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 22)
            }
        }
    }

    private var activitySummary: some View {
        DashboardPanel {
            HStack(spacing: 0) {
                DashboardInlineMetric(
                    value: model.metrics.words.formatted(.number.grouping(.automatic)),
                    label: "words spoken"
                )
                DashboardMetricDivider()
                DashboardInlineMetric(value: model.metrics.speechDuration.hushCompactDuration, label: "recorded")
                DashboardMetricDivider()
                DashboardInlineMetric(
                    value: "\(model.metrics.dictations)",
                    label: model.metrics.dictations == 1 ? "dictation" : "dictations"
                )
            }
            .padding(.vertical, 16)
        }
    }

    private var typingHistory: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Typing speed over time")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Compare your optional everyday estimate with focused typing tests.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.typingResults.isEmpty ? "Take typing test" : "Take another test") {
                        showsTypingTest = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(peach)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Everyday typing estimate")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(everydayPrivacyDetail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(everydayMeasurementStatus)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(model.everydayTypingMeasurementEnabled ? peach : .secondary)
                    Toggle("", isOn: everydayMeasurementBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if model.typingResults.isEmpty && model.everydayTypingSamples.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 22))
                            .foregroundStyle(peach)
                        Text("Measure your typing speed")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Until then, time saved uses a 40 WPM baseline.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    HStack(spacing: 16) {
                        chartLegend(color: Color.accentColor, title: "Everyday estimate")
                        chartLegend(color: peach, title: "Typing tests")
                    }

                    Chart {
                        ForEach(chronologicalEverydaySamples) { sample in
                            LineMark(
                                x: .value("Day", sample.day),
                                y: .value("Everyday WPM", sample.wordsPerMinute)
                            )
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Day", sample.day),
                                y: .value("Everyday WPM", sample.wordsPerMinute)
                            )
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(26)
                        }
                        ForEach(chronologicalResults) { result in
                            LineMark(
                                x: .value("Test date", result.completedAt),
                                y: .value("Test WPM", result.wordsPerMinute)
                            )
                            .foregroundStyle(peach)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Test date", result.completedAt),
                                y: .value("Test WPM", result.wordsPerMinute)
                            )
                            .foregroundStyle(peach)
                            .symbolSize(34)
                        }
                        if let average = model.averageTypingWordsPerMinute {
                            RuleMark(y: .value("Test average", average))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(.primary.opacity(0.05))
                            AxisValueLabel()
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYScale(domain: chartYDomain)
                    .frame(height: 168)

                    Divider().opacity(0.55)
                    HStack(spacing: 0) {
                        DashboardInlineMetric(value: formattedEverydayAverage, label: "everyday WPM")
                        DashboardMetricDivider()
                        DashboardInlineMetric(value: formattedAverage, label: "test average")
                        DashboardMetricDivider()
                        DashboardInlineMetric(value: formattedLatest, label: "latest test")
                        DashboardMetricDivider()
                        DashboardInlineMetric(value: "\(model.typingResults.count)", label: model.typingResults.count == 1 ? "test" : "tests")
                    }
                }
            }
            .padding(18)
        }
    }

    private var paceComparison: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice versus keyboard")
                        .font(.system(size: 15, weight: .semibold))
                    Text(comparisonDetail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                PaceComparisonRow(
                    title: "Spoken pace",
                    value: model.speechWordsPerMinute ?? 0,
                    maximum: comparisonMaximum,
                    color: peach
                )
                if let everyday = model.everydayTypingWordsPerMinute {
                    PaceComparisonRow(
                        title: "Everyday typing average",
                        value: everyday,
                        maximum: comparisonMaximum,
                        color: Color.accentColor
                    )
                }
                if let testAverage = model.averageTypingWordsPerMinute {
                    PaceComparisonRow(
                        title: "Typing test average",
                        value: testAverage,
                        maximum: comparisonMaximum,
                        color: Color.accentColor.opacity(0.68)
                    )
                } else if model.everydayTypingWordsPerMinute == nil {
                    PaceComparisonRow(
                        title: "Typing baseline",
                        value: 40,
                        maximum: comparisonMaximum,
                        color: Color.accentColor
                    )
                }
                if let latest = model.latestTypingResult {
                    PaceComparisonRow(
                        title: "Latest typing test",
                        value: latest.wordsPerMinute,
                        maximum: comparisonMaximum,
                        color: Color.accentColor.opacity(0.55)
                    )
                }
            }
            .padding(18)
        }
    }

    private var chronologicalResults: [TypingTestResult] {
        model.typingResults.sorted { $0.completedAt < $1.completedAt }
    }

    private var chronologicalEverydaySamples: [EverydayTypingSample] {
        model.everydayTypingSamples
            .filter { $0.activeDuration > 0 && $0.wordsPerMinute > 0 }
            .sorted { $0.day < $1.day }
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = model.typingResults.map(\.wordsPerMinute)
            + chronologicalEverydaySamples.map(\.wordsPerMinute)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...80 }
        let lower = max(0, floor((minimum - 8) / 5) * 5)
        let upper = max(lower + 10, ceil((maximum + 8) / 5) * 5)
        return lower...upper
    }

    private var formattedAverage: String {
        model.averageTypingWordsPerMinute?.formatted(.number.precision(.fractionLength(0))) ?? "-"
    }

    private var formattedEverydayAverage: String {
        model.everydayTypingWordsPerMinute?.formatted(.number.precision(.fractionLength(0)))
            ?? (model.everydayTypingMeasurementEnabled ? "Learning" : "Off")
    }

    private var formattedLatest: String {
        model.latestTypingResult?.wordsPerMinute.formatted(.number.precision(.fractionLength(0))) ?? "-"
    }

    private var impactDetail: String {
        if let everyday = model.everydayTypingWordsPerMinute,
           model.everydayTypingMeasurementEnabled {
            return "Using your private \(everyday.formatted(.number.precision(.fractionLength(0)))) WPM everyday average."
        }
        if let average = model.averageTypingWordsPerMinute {
            return "Using your \(average.formatted(.number.precision(.fractionLength(0)))) WPM test average."
        }
        return "Using the 40 WPM baseline."
    }

    private var advantageLabel: String {
        guard let multiplier = model.voiceSpeedMultiplier else { return "typing comparison" }
        return multiplier >= 1 ? "faster than typing" : "of typing speed"
    }

    private var paceDetail: String {
        guard let speechWordsPerMinute = model.speechWordsPerMinute else {
            return "Record a dictation to measure your spoken pace."
        }
        let spoken = speechWordsPerMinute.formatted(.number.precision(.fractionLength(0)))
        let typed = model.typingWordsPerMinute.formatted(.number.precision(.fractionLength(0)))
        if model.everydayTypingMeasurementEnabled, model.everydayTypingWordsPerMinute != nil {
            return "\(spoken) spoken WPM · \(typed) WPM everyday average"
        }
        return model.averageTypingWordsPerMinute == nil
            ? "\(spoken) spoken WPM · \(typed) WPM baseline"
            : "\(spoken) spoken WPM · \(typed) WPM test average"
    }

    private var comparisonMaximum: Double {
        max(
            model.speechWordsPerMinute ?? 0,
            model.everydayTypingWordsPerMinute ?? 0,
            model.averageTypingWordsPerMinute ?? 0,
            model.latestTypingResult?.wordsPerMinute ?? 0,
            40
        )
    }

    private var comparisonDetail: String {
        guard let multiplier = model.voiceSpeedMultiplier else {
            return "Record a dictation to compare your spoken and typing pace."
        }
        let basis = model.everydayTypingMeasurementEnabled && model.everydayTypingWordsPerMinute != nil
            ? "your private everyday average"
            : model.averageTypingWordsPerMinute == nil ? "the 40 WPM baseline" : "your typing-test average"
        return "Your time-saved estimate uses \(basis). Voice is currently \(multiplier.formatted(.number.precision(.fractionLength(1))))× typing speed."
    }

    private var everydayPrivacyDetail: String {
        "Off by default. Counts key presses and active seconds only. No characters, key identities, or app names are stored."
    }

    private var everydayMeasurementStatus: String {
        guard model.everydayTypingMeasurementEnabled else { return "Off" }
        guard PermissionsChecker.isAccessibilityGranted else { return "Needs Accessibility" }
        return model.everydayTypingWordsPerMinute == nil ? "Learning" : "Private & local"
    }

    private var everydayMeasurementBinding: Binding<Bool> {
        Binding(
            get: { model.everydayTypingMeasurementEnabled },
            set: { enabled in
                model.everydayTypingMeasurementEnabled = enabled
                Settings.shared.everydayTypingMeasurementEnabled = enabled
                if enabled && !PermissionsChecker.isAccessibilityGranted {
                    PermissionsChecker.promptAccessibilityIfNeeded()
                }
            }
        )
    }

    private func chartLegend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PaceComparisonRow: View {
    let title: String
    let value: Double
    let maximum: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(0))) + " WPM")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.055))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(value / maximum, 0), 1))
                }
            }
            .frame(height: 7)
        }
    }
}

private struct ActivityBreakdownRootView: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summary
                destinationList
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 34)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where you saved time")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.35)
                Text("Every app ranked by estimated time saved.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Activity range", selection: $model.selectedRange) {
                ForEach(ActivityRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 232)
        }
    }

    private var summary: some View {
        DashboardPanel(accented: true) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TOTAL TIME SAVED")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color(nsColor: DesignTokens.peach))
                    Text(model.metrics.estimatedTimeSaved.hushCompactDuration)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DashboardMetricDivider()
                DashboardInlineMetric(
                    value: model.metrics.speechDuration.hushCompactDuration,
                    label: "recorded"
                )
                DashboardMetricDivider()
                DashboardInlineMetric(
                    value: model.metrics.words.formatted(.number.grouping(.automatic)),
                    label: "words spoken"
                )
                DashboardMetricDivider()
                DashboardInlineMetric(
                    value: "\(model.destinations.count)",
                    label: model.destinations.count == 1 ? "destination" : "destinations"
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    private var destinationList: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("All destinations")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Share of time saved")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                if model.destinations.isEmpty {
                    DashboardCompactEmpty(
                        symbol: "arrow.up.right.square",
                        title: "No destinations yet",
                        detail: "Apps appear here after hush inserts your text."
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                } else {
                    Divider().opacity(0.55)
                    ForEach(Array(model.destinations.enumerated()), id: \.element.id) { index, activity in
                        DashboardDestinationRow(activity: activity, rank: index)
                        if index < model.destinations.count - 1 {
                            Divider().padding(.leading, 60).opacity(0.55)
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardHero: View {
    @ObservedObject var model: DashboardViewModel
    let onOpenDetails: () -> Void

    var body: some View {
        DashboardPanel(accented: true) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TIME YOU GOT BACK")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color(nsColor: DesignTokens.peach))
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(model.metrics.estimatedTimeSaved.hushCompactDuration)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .tracking(-1.7)
                                .contentTransition(.numericText())
                            Text("saved")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text(summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("View details", action: onOpenDetails)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let multiplier = model.voiceSpeedMultiplier,
                       let speechWordsPerMinute = model.speechWordsPerMinute {
                        DashboardSpeedComparison(
                            multiplier: multiplier,
                            speechWordsPerMinute: speechWordsPerMinute,
                            typingWordsPerMinute: model.typingWordsPerMinute,
                            isMeasured: model.averageTypingWordsPerMinute != nil
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Divider().opacity(0.55)

                DashboardDailyChart(points: model.daily, range: model.selectedRange)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 19)
            }
        }
    }

    private var summary: String {
        guard model.metrics.dictations > 0 else {
            return "Hold your shortcut and speak to start building this view."
        }
        if let everyday = model.everydayTypingWordsPerMinute,
           model.everydayTypingMeasurementEnabled {
            return "Estimated against your private \(everyday.formatted(.number.precision(.fractionLength(0)))) WPM everyday average."
        }
        if let average = model.averageTypingWordsPerMinute {
            return "Estimated against your measured \(average.formatted(.number.precision(.fractionLength(0)))) WPM typing average."
        }
        return "Estimated against a 40 WPM typing baseline."
    }
}

private struct DashboardSpeedComparison: View {
    let multiplier: Double
    let speechWordsPerMinute: Double
    let typingWordsPerMinute: Double
    let isMeasured: Bool

    private let peach = Color(nsColor: DesignTokens.peach)

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.07), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(max(multiplier / 5, 0.08), 1))
                    .stroke(
                        AngularGradient(colors: [peach.opacity(0.72), peach], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(multiplier.formatted(.number.precision(.fractionLength(1))))×")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                    Text(multiplier >= 1 ? "faster" : "of typing")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)

            Text(multiplier >= 1 ? "than typing" : "typing speed")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .frame(width: 176)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speech was \(multiplier.formatted(.number.precision(.fractionLength(1)))) times typing speed. \(comparisonDetail).")
    }

    private var comparisonDetail: String {
        let spoken = speechWordsPerMinute.formatted(.number.precision(.fractionLength(0)))
        let typed = typingWordsPerMinute.formatted(.number.precision(.fractionLength(0)))
        return isMeasured ? "\(spoken) spoken · \(typed) typed WPM" : "\(spoken) spoken · \(typed) WPM baseline"
    }
}

private struct TypingSpeedTestView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTypingFocused: Bool

    let speechWordsPerMinute: Double?
    let priorResults: [TypingTestResult]

    @State private var typedText = ""
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var result: TypingTestResult?
    @State private var averageAfterResult: Double?
    @State private var passage: String

    private let duration: TimeInterval = 30
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private static let commonWords = """
    about after again air all also always and answer any around as ask back be because become before begin between both bring but by call can change child city clear close come could country create day decide different do down each early end enough even every example eye face fact feel few find first follow for form from get give go good great group grow hand happen have he head help her here high hold home house how idea if important in into is it just keep know large last late lead learn leave life light like line little long look make many may mean might more most move much must name near need never new next night no not now number of off often old on once one only open or other out over own part people place plan play point possible problem public put question quick real right run same say see seem set she should show side simple since small so some something start state still stop story study such system take talk team tell than that the their them then there these they thing think this those time to together too try turn two under up use very want way we well what when where which while who will with word work world would write year you young your
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init)

    init(speechWordsPerMinute: Double?, priorResults: [TypingTestResult]) {
        self.speechWordsPerMinute = speechWordsPerMinute
        self.priorResults = priorResults
        _passage = State(initialValue: Self.makePassage())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Typing benchmark")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Type naturally for 30 seconds. hush uses your pace to estimate the time you save.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(startedAt == nil ? "READY" : "TIME LEFT")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(timeRemaining)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("seconds")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 24)

                compactLiveMetric(
                    liveWordsPerMinute.formatted(.number.precision(.fractionLength(0))),
                    label: "WPM"
                )
                metricDivider
                compactLiveMetric(
                    liveAccuracy.formatted(.percent.precision(.fractionLength(0))),
                    label: "ACCURACY"
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("TYPE NEXT")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.tertiary)
                    Text(activeWord)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("hush.typing.current-word")
                        .accessibilityLabel(activeWord)
                    Spacer()
                    Text(typingGuidance)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)

                Divider()
                    .opacity(0.6)

                ZStack(alignment: .topLeading) {
                    Text(renderedPassage)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .lineSpacing(10)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture { isTypingFocused = result == nil }
                        .accessibilityIdentifier("hush.typing.passage")

                    TextField("", text: $typedText)
                        .textFieldStyle(.plain)
                        .focused($isTypingFocused)
                        .disabled(result != nil)
                        .opacity(0.01)
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("hush.typing.input")
                        .onChange(of: typedText) { _, newValue in
                            handleTyping(newValue)
                        }
                    }
                    .frame(maxHeight: .infinity)
            }
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isTypingFocused && result == nil
                            ? Color.accentColor.opacity(0.72)
                            : .primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .frame(height: result == nil ? 275 : 220)

            VStack(spacing: 8) {
                ProgressView(value: min(elapsed / duration, 1))
                    .tint(Color(nsColor: DesignTokens.peach))
                HStack {
                    Text(statusText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(characterFeedback)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("hush.typing.character-feedback")
                        .accessibilityLabel(characterFeedback)
                }
            }

            if let result {
                HStack(spacing: 22) {
                    resultMetric(
                        result.wordsPerMinute.formatted(.number.precision(.fractionLength(0))),
                        label: "latest WPM"
                    )
                    if let averageAfterResult {
                        resultMetric(
                            averageAfterResult.formatted(.number.precision(.fractionLength(0))),
                            label: "average WPM"
                        )
                    }
                    resultMetric(result.accuracy.formatted(.percent.precision(.fractionLength(0))), label: "accuracy")
                    if let comparison = resultComparison {
                        resultMetric(
                            comparison.formatted(.number.precision(.fractionLength(1))) + "×",
                            label: "vs typing average"
                        )
                    }
                    Spacer()
                    Button("Try another") { reset() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 2)
            }
        }
        .padding(24)
        .onAppear { isTypingFocused = true }
        .onReceive(timer) { now in
            guard let startedAt, result == nil else { return }
            elapsed = min(duration, now.timeIntervalSince(startedAt))
            if elapsed >= duration {
                finishTest()
            }
        }
    }

    private var timeRemaining: String {
        let remaining = max(0, duration - elapsed)
        return String(format: "%.0f", ceil(remaining))
    }

    private var correctCharacterCount: Int {
        zip(typedText, passage).reduce(into: 0) { count, pair in
            if pair.0 == pair.1 { count += 1 }
        }
    }

    private var liveAccuracy: Double {
        typedText.isEmpty ? 1 : Double(correctCharacterCount) / Double(typedText.count)
    }

    private var liveWordsPerMinute: Double {
        guard elapsed > 0 else { return 0 }
        return (Double(correctCharacterCount) / 5) / (elapsed / 60)
    }

    private var incorrectCharacterCount: Int {
        max(0, typedText.count - correctCharacterCount)
    }

    private var characterFeedback: String {
        let mistakeLabel = incorrectCharacterCount == 1 ? "mistake" : "mistakes"
        return "\(correctCharacterCount) correct · \(incorrectCharacterCount) \(mistakeLabel)"
    }

    private var renderedPassage: AttributedString {
        let typedCharacters = Array(typedText)
        let highlightedWordRange = activeWordRange
        var output = AttributedString()
        for (index, character) in passage.enumerated() {
            let isCurrentCharacter = index == typedCharacters.count && result == nil
            let displayedCharacter = isCurrentCharacter && character.isWhitespace ? "·" : String(character)
            var item = AttributedString(displayedCharacter)
            let isInActiveWord = highlightedWordRange?.contains(index) == true
            if index < typedCharacters.count {
                item.foregroundColor = typedCharacters[index] == character
                    ? Color.primary.opacity(0.78)
                    : Color.red.opacity(0.94)
                if typedCharacters[index] != character {
                    item.backgroundColor = Color.red.opacity(0.12)
                } else if isInActiveWord {
                    item.backgroundColor = Color(nsColor: DesignTokens.peach).opacity(0.22)
                }
            } else if isCurrentCharacter {
                item.foregroundColor = Color.primary
                item.backgroundColor = Color(nsColor: DesignTokens.peach).opacity(0.42)
            } else if isInActiveWord {
                item.foregroundColor = Color.primary
                item.backgroundColor = Color(nsColor: DesignTokens.peach).opacity(0.22)
            } else {
                item.foregroundColor = Color.secondary.opacity(0.58)
            }
            output.append(item)
        }
        return output
    }

    private var activeWord: String {
        guard let range = activeWordRange else { return result == nil ? "Keep going" : "Complete" }
        return String(Array(passage)[range])
    }

    private var activeWordRange: Range<Int>? {
        guard result == nil else { return nil }
        let cursor = min(typedText.count, passage.count)
        return wordRanges.first { cursor < $0.upperBound }
    }

    private var wordRanges: [Range<Int>] {
        let characters = Array(passage)
        var ranges: [Range<Int>] = []
        var wordStart: Int?

        for (index, character) in characters.enumerated() {
            if character.isWhitespace {
                if let start = wordStart {
                    ranges.append(start..<index)
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = index
            }
        }

        if let wordStart {
            ranges.append(wordStart..<characters.count)
        }
        return ranges
    }

    private var statusText: String {
        if result != nil { return "Saved locally. Your dashboard estimate is now personalized." }
        if startedAt == nil { return "The timer starts with your first keystroke." }
        return "Correct mistakes as you go for a more realistic result."
    }

    private var typingGuidance: String {
        if result != nil { return "Saved locally" }
        return startedAt == nil ? "Timer starts with your first keystroke" : "Keep typing naturally"
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 1, height: 34)
    }

    private func compactLiveMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 88, alignment: .leading)
    }

    private func resultMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func finishTest() {
        guard result == nil, let startedAt else { return }
        let measuredDuration = min(duration, max(1, Date().timeIntervalSince(startedAt)))
        elapsed = measuredDuration
        let accuracy = liveAccuracy
        let wordsPerMinute = (Double(correctCharacterCount) / 5) / (measuredDuration / 60)
        let completed = TypingTestResult(wordsPerMinute: wordsPerMinute, accuracy: accuracy)
        result = completed
        let rollingResults = ([completed] + priorResults).prefix(20)
        averageAfterResult = rollingResults.map(\.wordsPerMinute).reduce(0, +) / Double(rollingResults.count)
        Settings.shared.recordTypingTest(wordsPerMinute: wordsPerMinute, accuracy: accuracy)
        isTypingFocused = false
    }

    private func handleTyping(_ newValue: String) {
        guard result == nil else { return }
        if newValue.count > passage.count {
            typedText = String(newValue.prefix(passage.count))
            return
        }
        if startedAt == nil, !newValue.isEmpty {
            startedAt = Date()
        }
        if newValue.count >= passage.count {
            finishTest()
        }
    }

    private var resultComparison: Double? {
        guard let speechWordsPerMinute, let averageAfterResult, averageAfterResult > 0 else { return nil }
        return speechWordsPerMinute / averageAfterResult
    }

    private func reset() {
        typedText = ""
        startedAt = nil
        elapsed = 0
        result = nil
        averageAfterResult = nil
        passage = Self.makePassage()
        isTypingFocused = true
    }

    private static func makePassage() -> String {
        commonWords.shuffled().prefix(90).joined(separator: " ")
    }
}

private struct DashboardInlineMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }
}

private struct DashboardMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 1, height: 32)
    }
}

private struct DashboardDailyChart: View {
    let points: [DailyActivityPoint]
    let range: ActivityRange

    private let peach = Color(nsColor: DesignTokens.peach)
    private var hasActivity: Bool { points.contains { $0.words > 0 || $0.dictations > 0 } }

    private var axisDates: [Date] {
        guard !points.isEmpty else { return [] }
        switch range {
        case .today:
            return [points[0].date]
        case .sevenDays:
            return points.map(\.date)
        case .thirtyDays:
            return points.enumerated().compactMap { index, point in
                index % 5 == 0 || index == points.count - 1 ? point.date : nil
            }
        case .allTime:
            let step = max(1, Int(ceil(Double(points.count) / 6)))
            return points.enumerated().compactMap { index, point in
                index % step == 0 || index == points.count - 1 ? point.date : nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Voice activity")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(hasActivity ? "Words by day" : "Waiting for your first dictation")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            if !hasActivity {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array([0.30, 0.54, 0.38, 0.76, 0.48, 0.63, 0.42].enumerated()), id: \.offset) { _, height in
                        Capsule()
                            .fill(peach.opacity(0.11))
                            .frame(maxWidth: .infinity)
                            .frame(height: 64 * height)
                    }
                }
                .frame(height: 112, alignment: .bottom)
                .accessibilityHidden(true)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Words", point.words),
                        width: points.count == 1 ? .fixed(44) : .ratio(0.58)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(nsColor: DesignTokens.brand300), peach],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(5)
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(point.words) words in \(point.dictations) dictations")
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel().font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(height: 138)
                .accessibilityLabel("Daily voice activity")
            }
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch range {
        case .today:
            return "Today"
        case .sevenDays:
            return date.formatted(.dateTime.weekday(.narrow))
        case .thirtyDays:
            return date.formatted(.dateTime.day())
        case .allTime:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct DashboardDestinations: View {
    let activities: [AppActivity]
    let onViewAll: () -> Void

    var body: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Where you saved time")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Apps ranked by estimated time saved")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View All", action: onViewAll)
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.top, 17)
                .padding(.bottom, activities.isEmpty ? 8 : 12)

                if activities.isEmpty {
                    DashboardCompactEmpty(
                        symbol: "arrow.up.right.square",
                        title: "No destinations yet",
                        detail: "Apps appear here after hush inserts your text."
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                } else {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        DashboardDestinationRow(activity: activity, rank: index)
                        if index < activities.count - 1 {
                            Divider().padding(.leading, 60).opacity(0.55)
                        }
                    }
                }
            }
            .frame(height: 270, alignment: .top)
        }
    }
}

private struct DashboardDestinationRow: View {
    let activity: AppActivity
    let rank: Int

    private let colors = [
        Color(nsColor: DesignTokens.peach),
        Color(nsColor: DesignTokens.info),
        Color(nsColor: DesignTokens.good),
        Color(nsColor: DesignTokens.lilac)
    ]

    var body: some View {
        HStack(spacing: 12) {
            DashboardAppIcon(activity: activity, tint: colors[rank % colors.count])
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(activity.estimatedTimeSaved.hushCompactDuration + " saved")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors[rank % colors.count])
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.07))
                        Capsule()
                            .fill(colors[rank % colors.count].gradient)
                            .frame(width: max(3, proxy.size.width * activity.fraction))
                    }
                }
                .frame(height: 5)
                Text("\(activity.count) \(activity.count == 1 ? "dictation" : "dictations") · \(activity.words) words · \(Int((activity.fraction * 100).rounded()))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardAppIcon: View {
    let activity: AppActivity
    let tint: Color

    var body: some View {
        Group {
            if let image = appImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(3)
            } else {
                Text(String(activity.name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint.opacity(0.12))
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appImage: NSImage? {
        guard let identifier = activity.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct DashboardLocalStack: View {
    let setup: DashboardLocalSetup
    let onNavigate: (HushDestination) -> Void

    var body: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("On this Mac")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Label("Local", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(nsColor: DesignTokens.good))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 17)

                DashboardLocalRow(symbol: "waveform", title: setup.modelName, detail: setup.modelStatus) {
                    onNavigate(.transcription)
                }
                Divider().padding(.leading, 58).opacity(0.55)
                DashboardLocalRow(symbol: "sparkles", title: setup.personaName, detail: setup.personaStatus) {
                    onNavigate(.personas(focusEnableAI: setup.personaIsOff))
                }
                Divider().padding(.leading, 58).opacity(0.55)
                DashboardLocalRow(
                    symbol: "person.2",
                    title: "\(setup.profileCount) \(setup.profileCount == 1 ? "profile" : "profiles")",
                    detail: ""
                ) {
                    onNavigate(.personas())
                }

                Divider().opacity(0.55)
                Label("Audio and text processing stay on this Mac.", systemImage: "lock.shield.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .frame(height: 270, alignment: .top)
        }
    }
}

private struct DashboardLocalRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(nsColor: DesignTokens.peach))
                    .frame(width: 28, height: 28)
                    .background(Color(nsColor: DesignTokens.peach).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardRecent: View {
    let items: [DictationActivity]
    let onViewAll: () -> Void
    let onOpen: (UUID) -> Void
    let onCopy: (String) -> Void

    var body: some View {
        DashboardPanel {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recent dictations")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Open or copy text without leaving hush")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View All", action: onViewAll)
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                if items.isEmpty {
                    DashboardCompactEmpty(
                        symbol: "text.bubble",
                        title: "No recent dictations",
                        detail: "Completed text appears here when history is enabled."
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                } else {
                    Divider().opacity(0.55)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Button {
                                onOpen(item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.text.replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(item.appName) · \(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                onCopy(item.text)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy dictation")
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 18).opacity(0.55)
                        }
                    }
                }
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private struct DashboardCompactEmpty: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardPanel<Content: View>: View {
    let accented: Bool
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(accented: Bool = false, @ViewBuilder content: () -> Content) {
        self.accented = accented
        self.content = content()
    }

    var body: some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.78))
                    if accented {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [Color(nsColor: DesignTokens.peach).opacity(colorScheme == .dark ? 0.13 : 0.09), .clear],
                                    center: .topTrailing,
                                    startRadius: 8,
                                    endRadius: 340
                                )
                            )
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.primary.opacity(colorScheme == .dark ? 0.085 : 0.055), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.055), radius: 16, x: 0, y: 7)
    }
}
