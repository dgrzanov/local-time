import SwiftData
import XCTest
@testable import LocalTime

final class RepositoryTests: XCTestCase {
    @MainActor
    func testProjectNamesAreCaseInsensitiveUnique() throws {
        let context = try makeContext()
        let repository = SwiftDataProjectRepository(context: context)
        _ = try repository.create(name: "Product", colorHex: "3B82F6")

        XCTAssertThrowsError(try repository.create(name: " product ", colorHex: "EF4444")) { error in
            XCTAssertEqual(error as? RepositoryError, .duplicateProjectName)
        }
    }

    @MainActor
    func testArchivedProjectCannotReceiveNewEntry() throws {
        let context = try makeContext()
        let projects = SwiftDataProjectRepository(context: context)
        let project = try projects.create(name: "Archived", colorHex: "64748B")
        try projects.setArchived(project, archived: true)

        XCTAssertThrowsError(
            try SwiftDataTimeEntryRepository(context: context).create(
                description: "Work",
                note: "",
                startAt: makeDate("2026-08-25T08:00:00Z"),
                endAt: makeDate("2026-08-25T09:00:00Z"),
                project: project
            )
        ) { error in
            XCTAssertEqual(error as? RepositoryError, .archivedProject)
        }
    }

    @MainActor
    func testEntryDurationMustNotExceedTwentyFourHours() throws {
        let context = try makeContext()
        let project = try SwiftDataProjectRepository(context: context).create(name: "Product", colorHex: "3B82F6")
        let start = makeDate("2026-08-25T08:00:00Z")

        XCTAssertThrowsError(
            try SwiftDataTimeEntryRepository(context: context).create(
                description: "Long entry",
                note: "",
                startAt: start,
                endAt: start.addingTimeInterval(24 * 3_600 + 1),
                project: project
            )
        ) { error in
            XCTAssertEqual(error as? RepositoryError, .invalidEntryDuration)
        }
    }

    @MainActor
    func testEntryCategoryIsPersisted() throws {
        let context = try makeContext()
        let project = try SwiftDataProjectRepository(context: context).create(name: "Learning", colorHex: "22C55E")

        let entry = try SwiftDataTimeEntryRepository(context: context).create(
            description: "Course",
            note: "",
            category: .education,
            startAt: makeDate("2026-08-25T08:00:00Z"),
            endAt: makeDate("2026-08-25T09:00:00Z"),
            project: project
        )

        XCTAssertEqual(entry.category, .education)
    }

    @MainActor
    func testWeeklyGoalValidationAndDisable() throws {
        let context = try makeContext()
        let repository = SwiftDataSettingsRepository(context: context)
        XCTAssertEqual(try repository.current().weeklyGoalMinutes, 2_400)

        try repository.setWeeklyGoal(minutes: 1_875)
        XCTAssertEqual(try repository.current().weeklyGoalMinutes, 1_875)

        XCTAssertThrowsError(try repository.setWeeklyGoal(minutes: 1_876))
        try repository.setWeeklyGoal(minutes: nil)
        XCTAssertNil(try repository.current().weeklyGoalMinutes)

        try repository.setDefaultWorkStart(minutes: 8 * 60 + 30)
        XCTAssertEqual(try repository.current().defaultWorkStartMinutes, 8 * 60 + 30)
        XCTAssertThrowsError(try repository.setDefaultWorkStart(minutes: 24 * 60))
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Project.self, TimeEntry.self, AppSettings.self, configurations: configuration)
        return ModelContext(container)
    }
}
