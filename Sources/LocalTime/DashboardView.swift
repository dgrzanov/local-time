import AppKit
import Charts
import SwiftData
import SwiftUI

private enum EntrySort: String, CaseIterable, Identifiable {
    case start = "Start"
    case description = "Description"
    case project = "Project"
    case category = "Category"
    case duration = "Duration"

    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \TimeEntry.startAt, order: .reverse) private var allEntries: [TimeEntry]
    @Query private var settings: [AppSettings]

    @State private var range = DateRange.week(containing: .now)
    @State private var isCustomRange = false
    @State private var showChart = true
    @State private var sort: EntrySort = .start
    @State private var sortAscending = false
    @State private var selectedEntryID: UUID?
    @State private var editingEntry: TimeEntry?
    @State private var showEntryEditor = false
    @State private var deletingEntry: TimeEntry?
    @State private var showProjects = false
    @State private var showGoalEditor = false
    @State private var showCustomRangeEditor = false
    @State private var importBundle: ImportBundle?
    @State private var alertInfo: AlertInfo?

    private var visibleEntries: [TimeEntry] {
        allEntries.filter { range.intersects(start: $0.startAt, end: $0.endAt) }
    }

    private var weeklyGoalMinutes: Int? { settings.first?.weeklyGoalMinutes }
    private var defaultWorkStartMinutes: Int { settings.first?.defaultWorkStartMinutes ?? 9 * 60 }
    private var canAddEntry: Bool { projects.contains { !$0.isArchived } }

    var body: some View {
        VStack(spacing: 0) {
            dateBar
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    if !isCustomRange, range.isExactWeek(), let goal = weeklyGoalMinutes, goal > 0 {
                        WeeklyGoalCard(
                            goalMinutes: goal,
                            trackedSeconds: TimeCalculations.totalDuration(entries: visibleEntries, in: range),
                            onEdit: { showGoalEditor = true }
                        )
                    }

                    HSplitView {
                        TimesheetView(
                            entries: visibleEntries,
                            sort: $sort,
                            sortAscending: $sortAscending,
                            selectedEntryID: $selectedEntryID,
                            onEdit: edit,
                            onDelete: { deletingEntry = $0 }
                        )
                        .frame(minWidth: 680)

                        if showChart {
                            DistributionChartView(entries: visibleEntries, range: range)
                                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                        }
                    }
                    .frame(minHeight: 440)
                }
                .padding(16)
            }
        }
        .navigationTitle("Local Time")
        .toolbar { toolbar }
        .onAppear {
            WindowCoordinator.shared.openWindow = { openWindow(id: "main") }
            ensureSettings()
        }
        .sheet(isPresented: $showEntryEditor) {
            EntryEditorView(
                entry: editingEntry,
                defaultDate: defaultEntryDate,
                projects: projects,
                existingEntries: allEntries
            )
        }
        .sheet(isPresented: $showProjects) {
            ProjectManagerView()
        }
        .sheet(isPresented: $showGoalEditor) {
            GoalEditorView()
        }
        .sheet(isPresented: $showCustomRangeEditor) {
            CustomRangeEditor(initialRange: range) { newRange in
                range = newRange
                isCustomRange = true
            }
        }
        .sheet(item: $importBundle) { bundle in
            ImportPreviewView(bundle: bundle) {
                applyImport(bundle)
            }
        }
        .alert(item: $alertInfo) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: Binding(
                get: { deletingEntry != nil },
                set: { if !$0 { deletingEntry = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deletingEntry { delete(entry) }
                deletingEntry = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var dateBar: some View {
        HStack(spacing: 12) {
            if !isCustomRange {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isCustomRange ? "Custom range" : "Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(rangeLabel)
                    .font(.headline)
            }

            if !isCustomRange {
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next week")
                Button("This Week") {
                    range = .week(containing: .now)
                    isCustomRange = false
                }
            }

            Spacer()
            Button("Custom Range…", systemImage: "calendar") { showCustomRangeEditor = true }
            if isCustomRange {
                Button("Weekly View") {
                    range = .week(containing: range.start)
                    isCustomRange = false
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("New Entry", systemImage: "plus") {
                editingEntry = nil
                showEntryEditor = true
            }
            .keyboardShortcut("n")
            .disabled(!canAddEntry)
            .help(canAddEntry ? "Add a time entry" : "Create a project before adding entries")

            Button("Projects", systemImage: "folder") { showProjects = true }

            Menu("Data", systemImage: "arrow.up.arrow.down") {
                Button("Export CSV Folder…") { exportCSV() }
                Button("Import CSV Folder…") { previewImport() }
            }

            Button(showChart ? "Hide Chart" : "Show Chart", systemImage: "chart.pie") {
                withAnimation { showChart.toggle() }
            }
        }
    }

    private var rangeLabel: String {
        let inclusiveEnd = Calendar.mondayFirst.date(byAdding: .day, value: -1, to: range.end)!
        return "\(range.start.formatted(date: .abbreviated, time: .omitted)) – \(inclusiveEnd.formatted(date: .abbreviated, time: .omitted))"
    }

    private var defaultEntryDate: Date {
        let entryDay = range.intersects(start: .now, end: .now.addingTimeInterval(1)) ? Date.now : range.start
        return TimeCalculations.suggestedStart(
            for: entryDay,
            entries: allEntries,
            defaultWorkStartMinutes: defaultWorkStartMinutes
        )
    }

    private func moveWeek(_ amount: Int) {
        let start = Calendar.mondayFirst.date(byAdding: .day, value: amount * 7, to: range.start)!
        range = DateRange(start: start, end: Calendar.mondayFirst.date(byAdding: .day, value: 7, to: start)!)
    }

    private func edit(_ entry: TimeEntry) {
        editingEntry = entry
        showEntryEditor = true
    }

    private func delete(_ entry: TimeEntry) {
        do {
            try SwiftDataTimeEntryRepository(context: modelContext).delete(entry)
            selectedEntryID = nil
        } catch {
            alertInfo = AlertInfo(title: "Couldn’t Delete Entry", message: error.localizedDescription)
        }
    }

    private func ensureSettings() {
        do { _ = try SwiftDataSettingsRepository(context: modelContext).current() }
        catch { alertInfo = AlertInfo(title: "Couldn’t Load Settings", message: error.localizedDescription) }
    }

    private func exportCSV() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Export Folder"
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let exportNames = [LocalCSVTransferService.projectsFilename, LocalCSVTransferService.entriesFilename]
        let willReplace = exportNames.contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        if willReplace {
            let confirmation = NSAlert()
            confirmation.messageText = "Replace Existing CSV Files?"
            confirmation.informativeText = "The selected folder already contains a Local Time export. Its projects.csv and time_entries.csv files will be replaced."
            confirmation.addButton(withTitle: "Replace")
            confirmation.addButton(withTitle: "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try LocalCSVTransferService().export(projects: projects, entries: allEntries, to: folder)
            alertInfo = AlertInfo(title: "Export Complete", message: "Created projects.csv and time_entries.csv in \(folder.lastPathComponent).")
        } catch {
            alertInfo = AlertInfo(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func previewImport() {
        let panel = NSOpenPanel()
        panel.title = "Choose a CSV Import Folder"
        panel.prompt = "Review Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            importBundle = try LocalCSVTransferService().previewImport(from: folder)
        } catch {
            alertInfo = AlertInfo(title: "Import Validation Failed", message: error.localizedDescription)
        }
    }

    private func applyImport(_ bundle: ImportBundle) {
        do {
            let result = try LocalCSVTransferService().apply(bundle, to: modelContext)
            importBundle = nil
            alertInfo = AlertInfo(
                title: "Import Complete",
                message: "Projects: \(result.projectsInserted) added, \(result.projectsUpdated) updated. Entries: \(result.entriesInserted) added, \(result.entriesUpdated) updated."
            )
        } catch {
            importBundle = nil
            alertInfo = AlertInfo(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

private struct WeeklyGoalCard: View {
    let goalMinutes: Int
    let trackedSeconds: TimeInterval
    let onEdit: () -> Void

    private var goalSeconds: TimeInterval { TimeInterval(goalMinutes * 60) }
    private var progress: Double { trackedSeconds / goalSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly goal")
                        .font(.headline)
                    Text("\(DurationFormatter.hoursAndMinutes(trackedSeconds)) of \(DurationFormatter.hoursAndMinutes(goalSeconds))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.bold())
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(progress >= 1 ? Color.green : Color(nsColor: .secondaryLabelColor))
                }
                Button("Edit Goal", systemImage: "pencil", action: onEdit)
                    .labelStyle(.iconOnly)
            }
            ProgressView(value: min(progress, 1))
                .tint(progress >= 1 ? Color.green : Color.accentColor)
                .controlSize(.large)
                .accessibilityLabel("Weekly goal progress")
                .accessibilityValue("\(Int((progress * 100).rounded())) percent")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        if progress > 1 { return "\(DurationFormatter.hoursAndMinutes(trackedSeconds - goalSeconds)) over goal" }
        if progress == 1 { return "Goal reached" }
        return "\(DurationFormatter.hoursAndMinutes(goalSeconds - trackedSeconds)) remaining"
    }
}

private struct DistributionChartView: View {
    let entries: [TimeEntry]
    let range: DateRange

    private var items: [ProjectBreakdown] { TimeCalculations.breakdown(entries: entries, in: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Time distribution")
                .font(.headline)
            if items.isEmpty {
                ContentUnavailableView("No Tracked Time", systemImage: "chart.pie", description: Text("Add entries in this date range to see a project breakdown."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(items) { item in
                    SectorMark(
                        angle: .value("Time", item.seconds),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: item.colorHex))
                }
                .chartLegend(.hidden)
                .frame(height: 240)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items, id: \.id) { item in
                            HStack {
                                Circle().fill(Color(hex: item.colorHex)).frame(width: 9, height: 9)
                                Text(item.projectName).lineLimit(1)
                                Spacer()
                                Text(item.percentage, format: .percent.precision(.fractionLength(1)))
                                    .monospacedDigit()
                                Text(DurationFormatter.hoursAndMinutes(item.seconds))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TimesheetView: View {
    let entries: [TimeEntry]
    @Binding var sort: EntrySort
    @Binding var sortAscending: Bool
    @Binding var selectedEntryID: UUID?
    let onEdit: (TimeEntry) -> Void
    let onDelete: (TimeEntry) -> Void

    private var groupedEntries: [(date: Date, entries: [TimeEntry])] {
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.startAt) }
        return groups.keys.sorted(by: >).map { date in
            (date, groups[date, default: []].sorted(by: comparison))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            if entries.isEmpty {
                ContentUnavailableView("No Time Entries", systemImage: "clock", description: Text("Add a manual entry for this date range."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedEntries, id: \.date) { group in
                        Section {
                            ForEach(group.entries, id: \.id) { entry in
                                entryRow(entry)
                                    .listRowBackground(selectedEntryID == entry.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntryID = entry.id }
                                    .onTapGesture(count: 2) { onEdit(entry) }
                                    .contextMenu {
                                        Button("Edit") { onEdit(entry) }
                                        Button("Delete", role: .destructive) { onDelete(entry) }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(group.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                Spacer()
                                Text(DurationFormatter.hoursAndMinutes(group.entries.reduce(0) { $0 + $1.duration }))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onDeleteCommand {
            guard let id = selectedEntryID, let entry = entries.first(where: { $0.id == id }) else { return }
            onDelete(entry)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            sortButton("Description", key: .description).frame(maxWidth: .infinity, alignment: .leading)
            sortButton("Project", key: .project).frame(width: 125, alignment: .leading)
            sortButton("Category", key: .category).frame(width: 105, alignment: .leading)
            sortButton("Start", key: .start).frame(width: 74, alignment: .leading)
            Text("End").foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            sortButton("Duration", key: .duration).frame(width: 86, alignment: .trailing)
        }
        .font(.caption.bold())
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.entryDescription.isEmpty ? "Untitled entry" : entry.entryDescription)
                    .foregroundStyle(entry.entryDescription.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(Color(hex: entry.project?.colorHex ?? "6B7280")).frame(width: 8, height: 8)
                Text(entry.project?.name ?? "Missing project").lineLimit(1)
            }
            .frame(width: 125, alignment: .leading)
            Text(entry.category.rawValue)
                .lineLimit(1)
                .frame(width: 105, alignment: .leading)
            Text(entry.startAt.shortTime).monospacedDigit().frame(width: 74, alignment: .leading)
            Text(endLabel(entry)).monospacedDigit().frame(width: 74, alignment: .leading)
            Text(DurationFormatter.hoursAndMinutes(entry.duration)).monospacedDigit().frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func endLabel(_ entry: TimeEntry) -> String {
        let nextDay = !Calendar.current.isDate(entry.startAt, inSameDayAs: entry.endAt)
        return entry.endAt.shortTime + (nextDay ? " +1" : "")
    }

    private func sortButton(_ title: String, key: EntrySort) -> some View {
        Button {
            if sort == key { sortAscending.toggle() }
            else { sort = key; sortAscending = true }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sort == key { Image(systemName: sortAscending ? "chevron.up" : "chevron.down") }
            }
        }
        .buttonStyle(.plain)
    }

    private func comparison(_ lhs: TimeEntry, _ rhs: TimeEntry) -> Bool {
        let first = sortAscending ? lhs : rhs
        let second = sortAscending ? rhs : lhs
        switch sort {
        case .start: return first.startAt < second.startAt
        case .description: return first.entryDescription.localizedCaseInsensitiveCompare(second.entryDescription) == .orderedAscending
        case .project: return (first.project?.name ?? "").localizedCaseInsensitiveCompare(second.project?.name ?? "") == .orderedAscending
        case .category: return first.category.rawValue.localizedCaseInsensitiveCompare(second.category.rawValue) == .orderedAscending
        case .duration: return first.duration < second.duration
        }
    }
}

private struct CustomRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var inclusiveEnd: Date
    let onSave: (DateRange) -> Void

    init(initialRange: DateRange, onSave: @escaping (DateRange) -> Void) {
        _start = State(initialValue: initialRange.start)
        _inclusiveEnd = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: initialRange.end)!)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Date Range").font(.title2.bold())
            DatePicker("Start", selection: $start, displayedComponents: .date)
            DatePicker("End", selection: $inclusiveEnd, in: start..., displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Apply") {
                    let calendar = Calendar.mondayFirst
                    let startDay = calendar.startOfDay(for: start)
                    let endDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: inclusiveEnd))!
                    onSave(DateRange(start: startDay, end: endDay))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct ImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let bundle: ImportBundle
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review CSV Import").font(.title2.bold())
            Text("The import is valid. Existing records with matching UUIDs will be updated; new records will be added.")
                .foregroundStyle(.secondary)
            LabeledContent("Projects", value: "\(bundle.projects.count)")
            LabeledContent("Time entries", value: "\(bundle.entries.count)")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Import", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
