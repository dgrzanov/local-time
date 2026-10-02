import Foundation
import SwiftData

enum TimeEntryCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case meeting = "Meeting"
    case development = "Development"
    case education = "Education"
    case planning = "Planning"
    case administration = "Administration"
    case research = "Research"
    case other = "Other"

    var id: String { rawValue }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .deny, inverse: \TimeEntry.project)
    var entries: [TimeEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    var isArchived: Bool { archivedAt != nil }
}

@Model
final class TimeEntry {
    @Attribute(.unique) var id: UUID
    var entryDescription: String
    var note: String
    var startAt: Date
    var endAt: Date
    var createdAt: Date
    var updatedAt: Date
    var categoryRawValue: String = TimeEntryCategory.other.rawValue
    var project: Project?

    init(
        id: UUID = UUID(),
        entryDescription: String = "",
        note: String = "",
        category: TimeEntryCategory = .development,
        startAt: Date,
        endAt: Date,
        project: Project,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.entryDescription = entryDescription
        self.note = note
        self.categoryRawValue = category.rawValue
        self.startAt = startAt
        self.endAt = endAt
        self.project = project
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: TimeInterval { max(0, endAt.timeIntervalSince(startAt)) }

    var category: TimeEntryCategory {
        get { TimeEntryCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var weeklyGoalMinutes: Int?
    var defaultWorkStartMinutes: Int = 9 * 60

    init(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        weeklyGoalMinutes: Int? = 2_400,
        defaultWorkStartMinutes: Int = 9 * 60
    ) {
        self.id = id
        self.weeklyGoalMinutes = weeklyGoalMinutes
        self.defaultWorkStartMinutes = defaultWorkStartMinutes
    }
}

struct DateRange: Hashable, Sendable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        precondition(start < end, "A date range must have a positive duration")
        self.start = start
        self.end = end
    }

    func intersects(start itemStart: Date, end itemEnd: Date) -> Bool {
        itemStart < end && itemEnd > start
    }

    func clippedDuration(start itemStart: Date, end itemEnd: Date) -> TimeInterval {
        guard intersects(start: itemStart, end: itemEnd) else { return 0 }
        return max(0, min(end, itemEnd).timeIntervalSince(max(start, itemStart)))
    }

    static func week(containing date: Date, calendar: Calendar = .mondayFirst) -> DateRange {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return DateRange(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }

    func isExactWeek(calendar: Calendar = .mondayFirst) -> Bool {
        self == DateRange.week(containing: start, calendar: calendar)
    }
}

extension Calendar {
    static var mondayFirst: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .current
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

struct ProjectBreakdown: Identifiable, Equatable {
    let projectID: UUID
    let projectName: String
    let colorHex: String
    let seconds: TimeInterval
    let percentage: Double

    var id: UUID { projectID }
}
