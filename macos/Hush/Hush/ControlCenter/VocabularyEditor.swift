import SwiftUI

/// Settings > Transcription > Vocabulary (PRD R13): the row that opens the user's words.
struct VocabularySection: View {
    let coordinator: DictationCoordinator?
    @ObservedObject private var boost = VocabularyBoostStore.shared
    @State private var count = Settings.shared.vocabulary.count
    @State private var isOpen = false

    /// Parakeet is listening for the words without its boost.
    private var boostMissing: Bool {
        count > 0 && VocabularyBoostStore.appliesToActiveEngine() && !boost.isInstalled
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary")
                    Text(count == 0 ? "Teach hush names and terms it gets wrong" : count == 1 ? "1 word" : "\(count) words")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if boostMissing {
                        Label("Recognition boost is off", systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button(count == 0 ? "Add Words\u{2026}" : "Manage\u{2026}") { isOpen = true }
                    .accessibilityIdentifier("hush.vocabulary.open")
            }
        } footer: {
            Text("Applied to every dictation on this Mac, with or without Live Write.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isOpen, onDismiss: { count = Settings.shared.vocabulary.count }) {
            VocabularySheet(coordinator: coordinator)
        }
    }
}

/// The user's words, and the flow that teaches hush a new one.
struct VocabularySheet: View {
    let coordinator: DictationCoordinator?
    @Environment(\.dismiss) private var dismiss
    @State private var terms = Settings.shared.vocabulary
    @State private var teacher: WordTeacher?

    var body: some View {
        ZStack {
            if let teacher {
                WordTeacherView(teacher: teacher, close: closeTeacher, addAnother: addAnother)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: teacher == nil)
        .frame(width: 600, height: 580)
        .onDisappear { teacher?.stop() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vocabulary").font(.title2.bold())
                    Text("Names, brands and terms hush writes your way.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !terms.isEmpty {
                    Button { open(nil) } label: { Label("Add Word", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("hush.vocabulary.add")
                }
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)

            if terms.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(terms, id: \.term) { term in
                        VocabularyRow(term: term, modelID: coordinator?.vocabularySampleModelID,
                                      teach: { open(term, step: .listen) }, edit: { open(term, step: .review) },
                                      delete: { delete(term) })
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                // The inset list draws rows 16 pt in; this lines them up with the title.
                .padding(.horizontal, 8)
                .accessibilityIdentifier("hush.vocabulary.list")
            }

            RecognitionBoostCard()
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            Divider()
            HStack {
                Text("Your words and recordings stay on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 44))
                .foregroundStyle(.indigo.gradient)
            Text("Teach hush your words").font(.title3.weight(.semibold))
            Text("Type a name or term the way you write it, then say it a few times. hush learns what it hears and writes your word from then on.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Button { open(nil) } label: { Label("Add Your First Word", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
                .accessibilityIdentifier("hush.vocabulary.add")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func open(_ term: VocabularyTerm?, step: WordTeacher.Step = .word) {
        let teacher = WordTeacher(coordinator: coordinator, term: term, step: step)
        self.teacher = teacher
        if step == .listen { teacher.startOver() }
    }

    private func closeTeacher() {
        teacher?.stop()
        terms = Settings.shared.vocabulary
        teacher = nil
    }

    private func addAnother() {
        teacher?.stop()
        terms = Settings.shared.vocabulary
        teacher = WordTeacher(coordinator: coordinator)
    }

    private func delete(_ term: VocabularyTerm) {
        Settings.shared.vocabulary.removeAll { $0.term == term.term }
        withAnimation { terms = Settings.shared.vocabulary }
    }
}

private struct VocabularyRow: View {
    let term: VocabularyTerm
    let modelID: String?
    let teach: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(term.term).font(.body.weight(.semibold))
                if term.needsPractice(with: modelID) {
                    Label("Learned with another speech model. Say it again to keep it reliable.", systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    Text(term.spellings.isEmpty ? "hush writes it as is" : "Fixes \(term.soundsLike.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: teach) { Image(systemName: "waveform") }
                .help("Say it again")
                .accessibilityLabel("Say \(term.term) again")
            Button(action: edit) { Image(systemName: "pencil") }
                .help("Edit spellings")
                .accessibilityLabel("Edit \(term.term)")
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                .help("Remove")
                .accessibilityLabel("Remove \(term.term)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Say It Again", action: teach)
            Button("Edit Spellings", action: edit)
            Divider()
            Button("Remove", role: .destructive, action: delete)
        }
    }
}

/// The Parakeet recognition boost: downloaded only after the user agrees, removable, and
/// named plainly when it is missing.
private struct RecognitionBoostCard: View {
    @ObservedObject private var boost = VocabularyBoostStore.shared
    @State private var confirmingDownload = false
    @State private var confirmingRemoval = false

    var body: some View {
        if VocabularyBoostStore.appliesToActiveEngine() {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: boost.isInstalled ? "ear.badge.checkmark" : "ear.badge.waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(boost.isInstalled ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                action
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .confirmationDialog("Download the recognition boost?", isPresented: $confirmingDownload) {
                Button("Download \(boost.sizeDescription)") { boost.install() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A \(boost.sizeDescription) speech model from Hugging Face, stored on this Mac. It helps Parakeet hear your words and runs only when a dictation sounds like one. You can remove it at any time.")
            }
            .confirmationDialog("Remove the recognition boost?", isPresented: $confirmingRemoval) {
                Button("Remove", role: .destructive) { boost.remove() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("hush keeps fixing the spellings it learned. You can download the boost again at any time.")
            }
        } else {
            Label("hush fixes the spellings it learned. The recognition boost works with Parakeet.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        switch boost.state {
        case .installed: "Recognition boost is on"
        case .downloading: "Downloading the recognition boost\u{2026}"
        case .notInstalled, .failed: "Recognition boost is off"
        }
    }

    private var detail: String {
        switch boost.state {
        case .installed: "Parakeet listens for your words, so it also catches them when it hears them in a new way. \(boost.sizeDescription) on this Mac."
        case .downloading: "You can keep using hush meanwhile."
        case .notInstalled: "hush fixes the spellings it learned, but Parakeet does not listen for your words. Download the boost (\(boost.sizeDescription)) to turn it on."
        case .failed(let message): message
        }
    }

    @ViewBuilder private var action: some View {
        switch boost.state {
        case .installed:
            Button("Remove\u{2026}") { confirmingRemoval = true }
                .accessibilityIdentifier("hush.vocabulary.boost.remove")
        case .downloading:
            ProgressView().controlSize(.small)
        case .notInstalled, .failed:
            Button("Download\u{2026}") { confirmingDownload = true }
                .accessibilityIdentifier("hush.vocabulary.boost.download")
        }
    }
}

// MARK: - Teaching a word

private struct WordTeacherView: View {
    @ObservedObject var teacher: WordTeacher
    let close: () -> Void
    let addAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch teacher.step {
                case .word: WordStep(teacher: teacher)
                case .listen: ListenStep(teacher: teacher)
                case .review: ReviewStep(teacher: teacher)
                case .saved: SavedStep(teacher: teacher, addAnother: addAnother, close: close)
                case .manual: ManualStep(teacher: teacher)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .id(teacher.step)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .animation(.smooth(duration: 0.28), value: teacher.step)
    }

    private var header: some View {
        HStack {
            Button(action: close) { Label("Vocabulary", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            if let position {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule()
                            .fill(index <= position ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: index == position ? 22 : 8, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(position) of 3")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var position: Int? {
        switch teacher.step {
        case .word: 1
        case .listen, .manual: 2
        case .review: 3
        case .saved: nil
        }
    }
}

private struct WordStep: View {
    @ObservedObject var teacher: WordTeacher
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which word should hush learn?").font(.title.bold())
            Text("Type it exactly as you want it written, with capitals and symbols.")
                .foregroundStyle(.secondary)
            TextField("Word", text: $teacher.word, prompt: Text("For example, Kubernetes"))
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.tint.opacity(focused ? 0.7 : 0), lineWidth: 2))
                .focused($focused)
                .onSubmit(next)
                .padding(.top, 8)
                .accessibilityIdentifier("hush.vocabulary.word")
            if teacher.isDuplicate {
                Label("\u{201C}\(teacher.trimmedWord)\u{201D} is already in your vocabulary. Continuing teaches it again.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button("Type What hush Writes Instead\u{2026}") { teacher.step = .manual }
                    .buttonStyle(.link)
                    .disabled(teacher.trimmedWord.isEmpty)
                Spacer()
                Button("Continue", action: next)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(teacher.trimmedWord.isEmpty)
                    .accessibilityIdentifier("hush.vocabulary.continue")
            }
            .padding(.bottom, 24)
        }
        .onAppear { focused = true }
    }

    private func next() {
        guard !teacher.trimmedWord.isEmpty else { return }
        teacher.listen()
    }
}

private struct ListenStep: View {
    @ObservedObject var teacher: WordTeacher
    @ObservedObject private var sampler: VoiceSampler

    init(teacher: WordTeacher) {
        self.teacher = teacher
        sampler = teacher.sampler
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Say").font(.title3).foregroundStyle(.secondary)
                Text("\u{201C}\(teacher.trimmedWord)\u{201D}")
                    .font(.system(size: 38, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 4)

            LevelMeter(levels: sampler.levels, active: sampler.phase == .listening)
                .frame(height: 54)
                .padding(.horizontal, 40)

            Text(status)
                .font(.callout.weight(.medium))
                .foregroundStyle(sampler.phase == .listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
                .animation(.default, value: status)
                .accessibilityIdentifier("hush.vocabulary.status")

            HStack(spacing: 10) {
                ForEach(0..<teacher.target, id: \.self) { index in
                    AttemptCard(index: index, attempt: index < teacher.attempts.count ? teacher.attempts[index] : nil,
                                current: index == teacher.attempts.count ? sampler.phase : nil)
                }
            }

            if let problem = teacher.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text("Say just the word in your normal voice, then pause. hush stops listening on its own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            HStack {
                Button("Change Word") {
                    teacher.stop()
                    teacher.step = .word
                }
                Spacer()
                if teacher.problem != nil, sampler.phase == .idle {
                    Button("Try Again") { teacher.listen() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Over") { teacher.startOver() }
                        .disabled(teacher.attempts.isEmpty)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var status: String {
        switch sampler.phase {
        case .getReady: teacher.attempts.isEmpty ? "Get ready\u{2026}" : "Once more\u{2026}"
        case .listening: "Listening"
        case .checking: "Checking what hush heard\u{2026}"
        case .idle: teacher.problem == nil ? " " : "Paused"
        }
    }
}

private struct AttemptCard: View {
    let index: Int
    let attempt: WordTeacher.Attempt?
    let current: VoiceSampler.Phase?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(fill).frame(width: 30, height: 30)
                if let attempt {
                    Image(systemName: attempt.matches ? "checkmark" : "ear")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else if current == .checking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(index + 1)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Text(caption)
                .font(.callout)
                .foregroundStyle(attempt == nil ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 36, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(current == .listening ? 0.9 : 0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.tint.opacity(current == .listening ? 0.6 : 0), lineWidth: 1.5))
        .animation(.smooth, value: attempt)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Try \(index + 1)")
        .accessibilityValue(caption)
    }

    private var fill: AnyShapeStyle {
        guard let attempt else { return AnyShapeStyle(.quaternary) }
        return attempt.matches ? AnyShapeStyle(.green) : AnyShapeStyle(.orange)
    }

    private var caption: String {
        if let attempt { return attempt.matches ? "Recognised" : "Heard \u{201C}\(attempt.heard)\u{201D}" }
        switch current {
        case .listening: return "Listening\u{2026}"
        case .checking: return "Checking\u{2026}"
        case .getReady: return "Next"
        default: return "Try \(index + 1)"
        }
    }
}

/// The microphone level as a row of bars, newest on the right.
private struct LevelMeter: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(levels.count)
            HStack(alignment: .center, spacing: 0) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: max(2, width * 0.55),
                               height: max(4, geometry.size.height * CGFloat(min(1, levels[index] * 2.2))))
                        .frame(width: width)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.linear(duration: 0.08), value: levels)
        }
        .accessibilityHidden(true)
    }
}

private struct ReviewStep: View {
    @ObservedObject var teacher: WordTeacher
    @State private var newSpelling = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\u{201C}\(teacher.trimmedWord)\u{201D}, your way").font(.title.bold())
            Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("When hush hears").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                if teacher.spellings.isEmpty {
                    Text("Nothing to fix: hush already writes \u{201C}\(teacher.trimmedWord)\u{201D}.")
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(teacher.spellings, id: \.self) { spelling in
                            SpellingChip(spelling: spelling) { teacher.removeSpelling(spelling) }
                        }
                    }
                }
                HStack {
                    TextField("Add a spelling", text: $newSpelling, prompt: Text("Another way hush writes it"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newSpelling.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                    Text("it writes \u{201C}\(teacher.trimmedWord)\u{201D}").font(.body.weight(.semibold))
                }
                .foregroundStyle(.tint)
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer()
            HStack {
                Button("Say It Again") { teacher.listenMore() }
                    .disabled(!teacher.sampler.isAvailable)
                Spacer()
                Button(teacher.original == nil ? "Add to Vocabulary" : "Save") { teacher.save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("hush.vocabulary.save")
            }
            .padding(.bottom, 24)
        }
    }

    private var summary: String {
        if teacher.recognizedEveryTime {
            return "hush recognised \u{201C}\(teacher.trimmedWord)\u{201D} every time. Adding it still helps Live Write spell it exactly."
        }
        if teacher.attempts.isEmpty {
            return "Check the spellings hush replaces with your word."
        }
        return "hush heard your word differently. From now on it turns these into \u{201C}\(teacher.trimmedWord)\u{201D}."
    }

    private func add() {
        teacher.addSpelling(newSpelling)
        newSpelling = ""
    }
}

private struct SpellingChip: View {
    let spelling: VocabularyTerm.Spelling
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: spelling.modelID == nil ? "keyboard" : "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(spelling.text)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(spelling.text)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .help(spelling.modelID == nil ? "Typed by you" : "Heard when you said it")
    }
}

private struct SavedStep: View {
    @ObservedObject var teacher: WordTeacher
    let addAnother: () -> Void
    let close: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, value: appeared)
                .padding(.top, 8)
            Text("\u{201C}\(teacher.trimmedWord)\u{201D} is in your vocabulary").font(.title2.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Text("Try it: say a sentence with \u{201C}\(teacher.trimmedWord)\u{201D}.")
                    .font(.callout.weight(.semibold))
                trialView
                    .frame(minHeight: 64)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 6)

            Spacer()
            HStack {
                Button("Add Another Word", action: addAnother)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }

    @ViewBuilder private var trialView: some View {
        switch teacher.trial {
        case .idle:
            Button { teacher.tryIt() } label: { Label("Try It", systemImage: "mic.fill") }
                .controlSize(.large)
                .disabled(!teacher.sampler.isAvailable)
                .accessibilityIdentifier("hush.vocabulary.try")
        case .listening:
            VStack(spacing: 8) {
                TrialMeter(sampler: teacher.sampler).frame(height: 36).padding(.horizontal, 60)
                Text("Listening").font(.callout).foregroundStyle(.tint)
            }
        case .checking:
            ProgressView("Checking\u{2026}").controlSize(.small)
        case .recognized(let text):
            result(text, recognized: true)
        case .missed(let text):
            VStack(spacing: 10) {
                result(text, recognized: false)
                Button("Teach It More") { teacher.listenMore() }
            }
        case .nothingHeard:
            VStack(spacing: 8) {
                Text("hush didn\u{2019}t hear anything.").foregroundStyle(.secondary)
                Button("Try Again") { teacher.tryIt() }
            }
        case .unavailable(let message):
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func result(_ text: String, recognized: Bool) -> some View {
        VStack(spacing: 8) {
            Label(recognized ? "hush wrote it your way" : "Not this time", systemImage: recognized ? "checkmark.seal.fill" : "ear.trianglebadge.exclamationmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(recognized ? .green : .orange)
            Text(highlighted(text))
                .multilineTextAlignment(.center)
            if recognized {
                Button("Try Again") { teacher.tryIt() }.buttonStyle(.link)
            }
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var string = AttributedString(text)
        var searchStart = string.startIndex
        while let range = string[searchStart...].range(of: teacher.trimmedWord, options: .caseInsensitive) {
            string[range].font = .body.bold()
            string[range].foregroundColor = .green
            searchStart = range.upperBound
        }
        return string
    }
}

/// The level meter while the user tries a sentence; observes the sampler directly.
private struct TrialMeter: View {
    @ObservedObject var sampler: VoiceSampler
    var body: some View { LevelMeter(levels: sampler.levels, active: true) }
}

private struct ManualStep: View {
    @ObservedObject var teacher: WordTeacher
    @State private var spelling = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What does hush write instead?").font(.title.bold())
            Text("Type how hush gets \u{201C}\(teacher.trimmedWord)\u{201D} wrong. Add as many as you like.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Spelling", text: $spelling, prompt: Text("For example, cuba netties"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(add)
                Button("Add", action: add).disabled(spelling.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            FlowLayout(spacing: 8) {
                ForEach(teacher.spellings, id: \.self) { item in
                    SpellingChip(spelling: item) { teacher.removeSpelling(item) }
                }
            }
            Spacer()
            HStack {
                Button("Say It Instead") { teacher.listen() }
                    .disabled(!teacher.sampler.isAvailable)
                Spacer()
                Button("Review") { teacher.step = .review }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(teacher.spellings.isEmpty)
            }
            .padding(.bottom, 24)
        }
    }

    private func add() {
        teacher.addSpelling(spelling)
        spelling = ""
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
