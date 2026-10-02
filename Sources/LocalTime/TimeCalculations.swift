import Foundation

struct DescriptionSuggestion: Identifiable, Equatable {
    let text: String
    let usageCount: Int

    var id: String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum TimeCalculations {
    static func continuedInterval(after interval: DateInterval) -> DateInterval {
        DateInterval(start: interval.end, duration: interval.duration)
    }

    static func descriptionSuggestions(
        entries: [TimeEntry],
        excluding entryID: UUID? = nil,
        matching query: String,
        limit: Int = 6
    ) -> [DescriptionSuggestion] {
        var usage: [String: (text: String, count: Int)] = [:]

        for entry in entries where entry.id != entryID {
            let text = entry.entryDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = normalizedDescription(text)
            if let existing = usage[key] {
                usage[key] = (existing.text, existing.count + 1)
            } else {
                usage[key] = (text, 1)
            }
        }

        let normalizedQuery = normalizedDescription(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return usage
            .filter { normalizedQuery.isEmpty || $0.key.localizedStandardContains(normalizedQuery) }
            .map { DescriptionSuggestion(text: $0.value.text, usageCount: $0.value.count) }
            .sorted {
                if $0.usageCount == $1.usageCount {
                    return $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending
                }
                return $0.usageCount > $1.usageCount
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func normalizedDescription(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func suggestedStart(
        for day: Date,
        entries: [TimeEntry],
        defaultWorkStartMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let latestEnd = entries
            .filter { calendar.isDate($0.startAt, inSameDayAs: day) && $0.endAt < dayEnd }
            .map(\.endAt)
            .max()
        if calendar.isDate(day, inSameDayAs: now), let latestEnd {
            return latestEnd
        }

        let safeMinutes = min(max(defaultWorkStartMinutes, 0), 24 * 60 - 1)
        return calendar.date(byAdding: .minute, value: safeMinutes, to: dayStart)!
    }

    static func totalDuration(entries: [TimeEntry], in range: DateRange) -> TimeInterval {
        entries.reduce(0) { total, entry in
            total + range.clippedDuration(start: entry.startAt, end: entry.endAt)
        }
    }

    static func breakdown(entries: [TimeEntry], in range: DateRange) -> [ProjectBreakdown] {
        var totals: [UUID: (project: Project, seconds: TimeInterval)] = [:]

        for entry in entries {
            guard let project = entry.project else { continue }
            let seconds = range.clippedDuration(start: entry.startAt, end: entry.endAt)
            guard seconds > 0 else { continue }
            let existing = totals[project.id]?.seconds ?? 0
            totals[project.id] = (project, existing + seconds)
        }

        let grandTotal = totals.values.reduce(0) { $0 + $1.seconds }
        guard grandTotal > 0 else { return [] }

        return totals.values
            .map { item in
                ProjectBreakdown(
                    projectID: item.project.id,
                    projectName: item.project.name,
                    colorHex: item.project.colorHex,
                    seconds: item.seconds,
                    percentage: item.seconds / grandTotal
                )
            }
            .sorted { lhs, rhs in
                if lhs.seconds == rhs.seconds { return lhs.projectName < rhs.projectName }
                return lhs.seconds > rhs.seconds
            }
    }
}

enum DurationFormatter {
    static func hoursAndMinutes(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((interval / 60).rounded())
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    static func decimalHours(_ interval: TimeInterval) -> String {
        String(format: "%.1f h", interval / 3_600)
    }
}
