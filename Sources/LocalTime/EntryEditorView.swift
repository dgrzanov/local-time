import SwiftData
import SwiftUI

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: TimeEntry?
    let projects: [Project]
    let existingEntries: [TimeEntry]

    @State private var descriptionText: String
    @State private var note: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var projectID: UUID?
    @State private var category: TimeEntryCategory
    @State private var errorMessage: String?
    @State private var selectedSuggestionIndex: Int?
    @State private var descriptionFieldWidth: CGFloat
    @State private var descriptionSuggestionsDismissed: Bool
    @FocusState private var descriptionIsFocused: Bool

    init(entry: TimeEntry?, defaultDate: Date, projects: [Project], existingEntries: [TimeEntry]) {
        self.entry = entry
        self.projects = projects
        self.existingEntries = existingEntries
        let start = entry?.startAt ?? defaultDate
        let end = entry?.endAt ?? start.addingTimeInterval(3_600)
        _descriptionText = State(initialValue: entry?.entryDescription ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _date = State(initialValue: start)
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: end)
        _projectID = State(initialValue: entry?.project?.id ?? projects.first(where: { !$0.isArchived })?.id)
        _category = State(initialValue: entry?.category ?? .development)
        _selectedSuggestionIndex = State(initialValue: nil)
        _descriptionFieldWidth = State(initialValue: 320)
        _descriptionSuggestionsDismissed = State(initialValue: false)
    }

    private var availableProjects: [Project] {
        projects.filter { !$0.isArchived || $0.id == entry?.project?.id }
    }

    private var descriptionSuggestions: [DescriptionSuggestion] {
        guard descriptionIsFocused else { return [] }
        return TimeCalculations.descriptionSuggestions(
            entries: existingEntries,
            excluding: entry?.id,
            matching: descriptionText
        )
    }

    private var resolvedInterval: (start: Date, end: Date)? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        guard
            let start = calendar.date(bySettingHour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0, second: 0, of: day),
            var end = calendar.date(bySettingHour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0, second: 0, of: day)
        else { return nil }
        if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end)! }
        return (start, end)
    }

    private var endsNextDay: Bool {
        guard let interval = resolvedInterval else { return false }
        return !Calendar.current.isDate(interval.start, inSameDayAs: interval.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(entry == nil ? "New Time Entry" : "Edit Time Entry")
                .font(.title2.bold())

            Form {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Description", text: $descriptionText, prompt: Text("What did you work on?"))
                        .focused($descriptionIsFocused)
                        .onKeyPress(.downArrow) { moveSuggestionSelection(by: 1) }
                        .onKeyPress(.upArrow) { moveSuggestionSelection(by: -1) }
                        .onKeyPress(.tab) { acceptSelectedSuggestion() }
                        .onKeyPress(.escape) { dismissDescriptionSuggestions() }
                        .onChange(of: descriptionText) {
                            selectedSuggestionIndex = nil
                            descriptionSuggestionsDismissed = false
                        }
                        .onChange(of: descriptionIsFocused) { _, isFocused in
                            if isFocused {
                                descriptionSuggestionsDismissed = false
                            }
                        }
                        .background {
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        descriptionFieldWidth = geometry.size.width
                                    }
                                    .onChange(of: geometry.size.width) { _, width in
                                        descriptionFieldWidth = width
                                    }
                            }
                        }
                        .popover(
                            isPresented: suggestionMenuIsPresented,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .bottom
                        ) {
                            suggestionMenu
                                .frame(width: max(descriptionFieldWidth, 240))
                                .padding(4)
                        }
                        .zIndex(10)
                }
                .zIndex(10)

                Picker("Project", selection: $projectID) {
                    Text("Select a project").tag(UUID?.none)
                    ForEach(availableProjects, id: \.id) { project in
                        HStack {
                            Circle().fill(Color(hex: project.colorHex)).frame(width: 8, height: 8)
                            Text(project.name + (project.isArchived ? " (Archived)" : ""))
                        }
                        .tag(Optional(project.id))
                    }
                }

                Picker("Category", selection: $category) {
                    ForEach(TimeEntryCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)

                if endsNextDay {
                    LabeledContent("Overnight entry") {
                        Label("Ends the next day", systemImage: "moon.stars")
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3...6)

                if let interval = resolvedInterval {
                    LabeledContent("Duration", value: DurationFormatter.hoursAndMinutes(interval.end.timeIntervalSince(interval.start)))
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                if entry == nil {
                    Button("Add Entry & Continue") { save(continueAdding: true) }
                        .disabled(projectID == nil)
                    Button("Add Entry") { save(continueAdding: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(projectID == nil)
                } else {
                    Button("Save Changes") { save(continueAdding: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(projectID == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var suggestionMenuIsPresented: Binding<Bool> {
        Binding(
            get: {
                descriptionIsFocused
                    && !descriptionSuggestionsDismissed
                    && !descriptionSuggestions.isEmpty
            },
            set: { isPresented in
                if !isPresented {
                    selectedSuggestionIndex = nil
                    descriptionSuggestionsDismissed = true
                    descriptionIsFocused = false
                }
            }
        )
    }

    private var suggestionMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(descriptionSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    chooseSuggestion(suggestion)
                } label: {
                    Text(suggestion.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            selectedSuggestionIndex == index
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { isHovering in
                    if isHovering {
                        selectedSuggestionIndex = index
                    }
                }

                if index < descriptionSuggestions.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func moveSuggestionSelection(by offset: Int) -> KeyPress.Result {
        let suggestions = descriptionSuggestions
        guard !suggestions.isEmpty else { return .ignored }

        if let selectedSuggestionIndex {
            self.selectedSuggestionIndex =
                (selectedSuggestionIndex + offset + suggestions.count) % suggestions.count
        } else {
            selectedSuggestionIndex = offset > 0 ? 0 : suggestions.count - 1
        }
        return .handled
    }

    private func acceptSelectedSuggestion() -> KeyPress.Result {
        let suggestions = descriptionSuggestions
        guard !suggestions.isEmpty else { return .ignored }
        let index = selectedSuggestionIndex ?? 0
        chooseSuggestion(suggestions[index])
        return .handled
    }

    private func dismissDescriptionSuggestions() -> KeyPress.Result {
        guard descriptionIsFocused else { return .ignored }
        descriptionSuggestionsDismissed = true
        selectedSuggestionIndex = nil
        descriptionIsFocused = false
        return .handled
    }

    private func chooseSuggestion(_ suggestion: DescriptionSuggestion) {
        descriptionText = suggestion.text
        selectedSuggestionIndex = nil
        descriptionIsFocused = false
    }

    private func save(continueAdding: Bool) {
        guard
            let projectID,
            let project = projects.first(where: { $0.id == projectID }),
            let interval = resolvedInterval
        else {
            errorMessage = "Select a project and valid times."
            return
        }

        do {
            let repository = SwiftDataTimeEntryRepository(context: modelContext)
            if let entry {
                try repository.update(
                    entry,
                    description: descriptionText,
                    note: note,
                    category: category,
                    startAt: interval.start,
                    endAt: interval.end,
                    project: project
                )
                dismiss()
            } else {
                _ = try repository.create(
                    description: descriptionText,
                    note: note,
                    category: category,
                    startAt: interval.start,
                    endAt: interval.end,
                    project: project
                )
                if continueAdding {
                    prepareContinuation(after: interval)
                } else {
                    dismiss()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareContinuation(after interval: (start: Date, end: Date)) {
        let next = TimeCalculations.continuedInterval(
            after: DateInterval(start: interval.start, end: interval.end)
        )
        descriptionText = ""
        note = ""
        date = next.start
        startTime = next.start
        endTime = next.end
        errorMessage = nil
        descriptionIsFocused = true
    }
}
