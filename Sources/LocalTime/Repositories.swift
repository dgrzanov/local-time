import Foundation
import SwiftData

enum RepositoryError: LocalizedError, Equatable {
    case blankProjectName
    case duplicateProjectName
    case invalidEntryDuration
    case archivedProject
    case invalidWeeklyGoal
    case invalidDefaultWorkStart

    var errorDescription: String? {
        switch self {
        case .blankProjectName: "Project name cannot be empty."
        case .duplicateProjectName: "A project with that name already exists."
        case .invalidEntryDuration: "An entry must be longer than zero and no longer than 24 hours."
        case .archivedProject: "Archived projects cannot be used for new entries."
        case .invalidWeeklyGoal: "The weekly goal must be between 15 minutes and 168 hours, in 15-minute increments."
        case .invalidDefaultWorkStart: "The default work start must be a valid time of day."
        }
    }
}

@MainActor
protocol ProjectRepository {
    func fetchAll() throws -> [Project]
    func create(name: String, colorHex: String) throws -> Project
    func update(_ project: Project, name: String, colorHex: String) throws
    func setArchived(_ project: Project, archived: Bool) throws
}

@MainActor
protocol TimeEntryRepository {
    func fetch(overlapping range: DateRange) throws -> [TimeEntry]
    func create(description: String, note: String, category: TimeEntryCategory, startAt: Date, endAt: Date, project: Project) throws -> TimeEntry
    func update(_ entry: TimeEntry, description: String, note: String, category: TimeEntryCategory, startAt: Date, endAt: Date, project: Project) throws
    func delete(_ entry: TimeEntry) throws
}

@MainActor
protocol SettingsRepository {
    func current() throws -> AppSettings
    func setWeeklyGoal(minutes: Int?) throws
    func setDefaultWorkStart(minutes: Int) throws
}

@MainActor
final class SwiftDataProjectRepository: ProjectRepository {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func fetchAll() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.name)]))
    }

    func create(name: String, colorHex: String) throws -> Project {
        let normalized = try validatedName(name, excluding: nil)
        let project = Project(name: normalized, colorHex: colorHex)
        context.insert(project)
        try context.save()
        return project
    }

    func update(_ project: Project, name: String, colorHex: String) throws {
        project.name = try validatedName(name, excluding: project.id)
        project.colorHex = colorHex
        project.updatedAt = .now
        try context.save()
    }

    func setArchived(_ project: Project, archived: Bool) throws {
        project.archivedAt = archived ? .now : nil
        project.updatedAt = .now
        try context.save()
    }

    private func validatedName(_ name: String, excluding id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.blankProjectName }
        let duplicate = try fetchAll().contains {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !duplicate else { throw RepositoryError.duplicateProjectName }
        return trimmed
    }
}

@MainActor
final class SwiftDataTimeEntryRepository: TimeEntryRepository {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func fetch(overlapping range: DateRange) throws -> [TimeEntry] {
        let all = try context.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\TimeEntry.startAt, order: .reverse)]))
        return all.filter { range.intersects(start: $0.startAt, end: $0.endAt) }
    }

    func create(
        description: String,
        note: String,
        category: TimeEntryCategory = .development,
        startAt: Date,
        endAt: Date,
        project: Project
    ) throws -> TimeEntry {
        guard !project.isArchived else { throw RepositoryError.archivedProject }
        try validate(startAt: startAt, endAt: endAt)
        let entry = TimeEntry(
            entryDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            startAt: startAt,
            endAt: endAt,
            project: project
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    func update(
        _ entry: TimeEntry,
        description: String,
        note: String,
        category: TimeEntryCategory = .development,
        startAt: Date,
        endAt: Date,
        project: Project
    ) throws {
        if project.isArchived && entry.project?.id != project.id { throw RepositoryError.archivedProject }
        try validate(startAt: startAt, endAt: endAt)
        entry.entryDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = category
        entry.startAt = startAt
        entry.endAt = endAt
        entry.project = project
        entry.updatedAt = .now
        try context.save()
    }

    func delete(_ entry: TimeEntry) throws {
        context.delete(entry)
        try context.save()
    }

    private func validate(startAt: Date, endAt: Date) throws {
        let duration = endAt.timeIntervalSince(startAt)
        guard duration > 0, duration <= 24 * 3_600 else { throw RepositoryError.invalidEntryDuration }
    }
}

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func current() throws -> AppSettings {
        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first { return settings }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    func setWeeklyGoal(minutes: Int?) throws {
        if let minutes {
            guard (15...(168 * 60)).contains(minutes), minutes.isMultiple(of: 15) else {
                throw RepositoryError.invalidWeeklyGoal
            }
        }
        let settings = try current()
        settings.weeklyGoalMinutes = minutes
        try context.save()
    }

    func setDefaultWorkStart(minutes: Int) throws {
        guard (0..<(24 * 60)).contains(minutes) else {
            throw RepositoryError.invalidDefaultWorkStart
        }
        let settings = try current()
        settings.defaultWorkStartMinutes = minutes
        try context.save()
    }
}
