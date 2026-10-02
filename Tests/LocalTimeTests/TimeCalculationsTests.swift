import XCTest
@testable import LocalTime

final class TimeCalculationsTests: XCTestCase {
    func testWeekRunsMondayThroughSunday() {
        let date = makeDate("2026-08-27T12:00:00Z")
        let range = DateRange.week(containing: date, calendar: utcCalendar)

        XCTAssertEqual(range.start, makeDate("2026-08-24T00:00:00Z"))
        XCTAssertEqual(range.end, makeDate("2026-08-31T00:00:00Z"))
        XCTAssertTrue(range.isExactWeek(calendar: utcCalendar))
    }

    func testDurationIsClippedAtBothRangeBoundaries() {
        let range = DateRange(start: makeDate("2026-08-24T00:00:00Z"), end: makeDate("2026-08-31T00:00:00Z"))

        XCTAssertEqual(
            range.clippedDuration(start: makeDate("2026-08-23T23:00:00Z"), end: makeDate("2026-08-24T02:00:00Z")),
            2 * 3_600
        )
        XCTAssertEqual(
            range.clippedDuration(start: makeDate("2026-08-30T22:00:00Z"), end: makeDate("2026-08-31T02:00:00Z")),
            2 * 3_600
        )
    }

    @MainActor
    func testBreakdownCalculatesProjectPercentages() {
        let projectA = Project(name: "Product", colorHex: "3B82F6")
        let projectB = Project(name: "Admin", colorHex: "EF4444")
        let day = makeDate("2026-08-25T08:00:00Z")
        let entries = [
            TimeEntry(startAt: day, endAt: day.addingTimeInterval(6 * 3_600), project: projectA),
            TimeEntry(startAt: day, endAt: day.addingTimeInterval(2 * 3_600), project: projectB)
        ]
        let range = DateRange(start: makeDate("2026-08-24T00:00:00Z"), end: makeDate("2026-08-31T00:00:00Z"))

        let result = TimeCalculations.breakdown(entries: entries, in: range)

        XCTAssertEqual(result.map(\.projectName), ["Product", "Admin"])
        XCTAssertEqual(result[0].percentage, 0.75, accuracy: 0.0001)
        XCTAssertEqual(result[1].percentage, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testSuggestedStartUsesLatestEntryEndForToday() {
        let project = Project(name: "Product", colorHex: "3B82F6")
        let now = makeDate("2026-08-27T12:00:00Z")
        let entries = [
            TimeEntry(startAt: makeDate("2026-08-27T08:00:00Z"), endAt: makeDate("2026-08-27T09:30:00Z"), project: project),
            TimeEntry(startAt: makeDate("2026-08-27T10:00:00Z"), endAt: makeDate("2026-08-27T11:15:00Z"), project: project),
            TimeEntry(startAt: makeDate("2026-08-26T11:00:00Z"), endAt: makeDate("2026-08-26T13:00:00Z"), project: project)
        ]

        let result = TimeCalculations.suggestedStart(
            for: now,
            entries: entries,
            defaultWorkStartMinutes: 8 * 60 + 30,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(result, makeDate("2026-08-27T11:15:00Z"))
    }

    func testSuggestedStartFallsBackToConfiguredWorkStart() {
        let now = makeDate("2026-08-27T12:00:00Z")

        let result = TimeCalculations.suggestedStart(
            for: now,
            entries: [],
            defaultWorkStartMinutes: 8 * 60 + 30,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(result, makeDate("2026-08-27T08:30:00Z"))
    }

    func testContinuedIntervalStartsAtPreviousEndAndPreservesDuration() {
        let original = DateInterval(
            start: makeDate("2026-08-27T10:00:00Z"),
            end: makeDate("2026-08-27T11:30:00Z")
        )

        let next = TimeCalculations.continuedInterval(after: original)

        XCTAssertEqual(next.start, makeDate("2026-08-27T11:30:00Z"))
        XCTAssertEqual(next.end, makeDate("2026-08-27T13:00:00Z"))
        XCTAssertEqual(next.duration, original.duration)
    }

    @MainActor
    func testDescriptionSuggestionsFilterAndRankByUsage() {
        let project = Project(name: "Product", colorHex: "3B82F6")
        let start = makeDate("2026-08-27T08:00:00Z")
        let descriptions = ["Daily standup", "Design review", "Daily standup", "Development", "Daily standup", "Design review"]
        let entries = descriptions.enumerated().map { offset, description in
            TimeEntry(
                entryDescription: description,
                startAt: start.addingTimeInterval(Double(offset) * 3_600),
                endAt: start.addingTimeInterval(Double(offset + 1) * 3_600),
                project: project
            )
        }

        let result = TimeCalculations.descriptionSuggestions(entries: entries, matching: "d")

        XCTAssertEqual(
            result,
            [
                DescriptionSuggestion(text: "Daily standup", usageCount: 3),
                DescriptionSuggestion(text: "Design review", usageCount: 2),
                DescriptionSuggestion(text: "Development", usageCount: 1)
            ]
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}

func makeDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
