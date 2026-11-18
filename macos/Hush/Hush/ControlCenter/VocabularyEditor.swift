import SwiftUI

/// Settings > Transcription > Vocabulary: the user's names and terms (PRD R13), edited like
/// macOS' Text Replacements: a two-column table with add and remove buttons.
struct VocabularySection: View {
    @State private var count = Settings.shared.vocabulary.count
    @State private var isEditing = false

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary")
                    Text(count == 0 ? "Names and terms hush writes your way" : count == 1 ? "1 word" : "\(count) words")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit\u{2026}") { isEditing = true }
                    .accessibilityIdentifier("hush.vocabulary.edit")
            }
        } footer: {
            Text("Applied to every dictation on this Mac, with or without Live Write.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isEditing, onDismiss: { count = Settings.shared.vocabulary.count }) {
            VocabularyEditor()
        }
    }
}

struct VocabularyEditor: View {
    private struct Row: Identifiable, Hashable {
        let id = UUID()
        var term: String
        var soundsLike: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = Settings.shared.vocabulary.map {
        Row(term: $0.term, soundsLike: $0.soundsLike.joined(separator: ", "))
    }
    @State private var selection = Set<Row.ID>()
    @FocusState private var focused: Row.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vocabulary")
                .font(.title2.bold())
            Text("Names, brands and terms hush writes exactly as you type them here. Under Sounds Like, add what hush hears instead, separated by commas.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Table($rows, selection: $selection) {
                TableColumn("Word") { $row in
                    TextField("Word", text: $row.term, prompt: Text("Name or term"))
                        .focused($focused, equals: row.id)
                }
                TableColumn("Sounds Like") { $row in
                    TextField("Sounds Like", text: $row.soundsLike, prompt: Text("Optional"))
                }
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 260)
            .accessibilityIdentifier("hush.vocabulary.table")
            HStack(spacing: 0) {
                Button { add() } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                    .accessibilityLabel("Add Word")
                    .accessibilityIdentifier("hush.vocabulary.add")
                Divider().frame(height: 16)
                Button { remove() } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                    .disabled(selection.isEmpty)
                    .accessibilityLabel("Remove Word")
                    .accessibilityIdentifier("hush.vocabulary.remove")
            }
            .buttonStyle(.borderless)
            .padding(.top, -6)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
        .onChange(of: rows) { save() }
    }

    private func add() {
        let row = Row(term: "", soundsLike: "")
        rows.append(row)
        selection = [row.id]
        focused = row.id
    }

    private func remove() {
        rows.removeAll { selection.contains($0.id) }
        selection = []
    }

    /// Saves each change as it happens, like System Settings; opening and closing saves nothing.
    private func save() {
        Settings.shared.vocabulary = rows.map {
            VocabularyTerm(term: $0.term, soundsLike: $0.soundsLike.split(separator: ",").map(String.init))
        }
    }
}
