import Foundation
import SwiftData

struct ProjectCSVRecord: Equatable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
}

struct TimeEntryCSVRecord: Equatable, Sendable {
    let id: UUID
    let description: String
    let note: String
    let category: TimeEntryCategory
    let projectID: UUID
    let startAt: Date
    let endAt: Date
    let createdAt: Date
    let updatedAt: Date
}

struct ImportBundle: Identifiable, Sendable {
    let id = UUID()
    let projects: [ProjectCSVRecord]
    let entries: [TimeEntryCSVRecord]
}

struct ImportResult: Equatable, Sendable {
    let projectsInserted: Int
    let projectsUpdated: Int
    let entriesInserted: Int
    let entriesUpdated: Int
}

enum CSVTransferError: LocalizedError, Equatable {
    case missingFile(String)
    case malformedCSV(file: String, row: Int, reason: String)
    case duplicateIdentifier(file: String, id: UUID)
    case duplicateProjectName(String)
    case missingProject(entryID: UUID, projectID: UUID)
    case invalidEntryDuration(entryID: UUID)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name): "Missing required file: \(name)."
        case .malformedCSV(let file, let row, let reason): "\(file), row \(row): \(reason)"
        case .duplicateIdentifier(let file, let id): "\(file) contains duplicate identifier \(id.uuidString)."
        case .duplicateProjectName(let name): "The project name “\(name)” is duplicated."
        case .missingProject(let entryID, let projectID): "Entry \(entryID) references missing project \(projectID)."
        case .invalidEntryDuration(let entryID): "Entry \(entryID) must be longer than zero and no longer than 24 hours."
        }
    }
}

@MainActor
protocol CSVTransferService {
    func export(projects: [Project], entries: [TimeEntry], to folder: URL) throws
    func previewImport(from folder: URL) throws -> ImportBundle
    func apply(_ bundle: ImportBundle, to context: ModelContext) throws -> ImportResult
}

@MainActor
final class LocalCSVTransferService: CSVTransferService {
    static let projectsFilename = "projects.csv"
    static let entriesFilename = "time_entries.csv"

    private let fileManager: FileManager
    private let isoFormatter: ISO8601DateFormatter

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func export(projects: [Project], entries: [TimeEntry], to folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let projectsRows = [["id", "name", "color_hex", "created_at", "updated_at", "archived_at"]] + projects.map {
            [$0.id.uuidString, $0.name, $0.colorHex, dateString($0.createdAt), dateString($0.updatedAt), optionalDateString($0.archivedAt)]
        }
        let entryRows = [["id", "description", "note", "category", "project_id", "start_at", "end_at", "created_at", "updated_at"]] + entries.compactMap { entry -> [String]? in
            guard let project = entry.project else { return nil }
            return [
                entry.id.uuidString,
                entry.entryDescription,
                entry.note,
                entry.category.rawValue,
                project.id.uuidString,
                dateString(entry.startAt),
                dateString(entry.endAt),
                dateString(entry.createdAt),
                dateString(entry.updatedAt)
            ]
        }

        try CSVCodec.encode(projectsRows).write(
            to: folder.appendingPathComponent(Self.projectsFilename),
            atomically: true,
            encoding: .utf8
        )
        try CSVCodec.encode(entryRows).write(
            to: folder.appendingPathComponent(Self.entriesFilename),
            atomically: true,
            encoding: .utf8
        )
    }

    func previewImport(from folder: URL) throws -> ImportBundle {
        let projectRows = try loadRows(filename: Self.projectsFilename, folder: folder)
        let entryRows = try loadRows(filename: Self.entriesFilename, folder: folder)
        let projects = try parseProjects(projectRows)
        let entries = try parseEntries(entryRows)
        try validate(projects: projects, entries: entries)
        return ImportBundle(projects: projects, entries: entries)
    }

    func apply(_ bundle: ImportBundle, to context: ModelContext) throws -> ImportResult {
        try validate(projects: bundle.projects, entries: bundle.entries)
        let existingProjects = try context.fetch(FetchDescriptor<Project>())
        let existingEntries = try context.fetch(FetchDescriptor<TimeEntry>())
        var projectsByID: [UUID: Project] = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.id, $0) })

        let importedIDs = Set(bundle.projects.map(\.id))
        var combinedNames: [String: UUID] = [:]
        for project in existingProjects where !importedIDs.contains(project.id) {
            combinedNames[project.name.folding(options: String.CompareOptions([.caseInsensitive, .diacriticInsensitive]), locale: Locale.current)] = project.id
        }
        for record in bundle.projects {
            let key = record.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let otherID = combinedNames[key], otherID != record.id {
                throw CSVTransferError.duplicateProjectName(record.name)
            }
            combinedNames[key] = record.id
        }

        var projectsInserted = 0
        var projectsUpdated = 0
        var entriesInserted = 0
        var entriesUpdated = 0

        do {
            for record in bundle.projects {
                if let project = projectsByID[record.id] {
                    project.name = record.name
                    project.colorHex = record.colorHex
                    project.createdAt = record.createdAt
                    project.updatedAt = record.updatedAt
                    project.archivedAt = record.archivedAt
                    projectsUpdated += 1
                } else {
                    let project = Project(
                        id: record.id,
                        name: record.name,
                        colorHex: record.colorHex,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt,
                        archivedAt: record.archivedAt
                    )
                    context.insert(project)
                    projectsByID[record.id] = project
                    projectsInserted += 1
                }
            }

            var entriesByID: [UUID: TimeEntry] = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.id, $0) })
            for record in bundle.entries {
                guard let project = projectsByID[record.projectID] else {
                    throw CSVTransferError.missingProject(entryID: record.id, projectID: record.projectID)
                }
                if let entry = entriesByID[record.id] {
                    entry.entryDescription = record.description
                    entry.note = record.note
                    entry.category = record.category
                    entry.project = project
                    entry.startAt = record.startAt
                    entry.endAt = record.endAt
                    entry.createdAt = record.createdAt
                    entry.updatedAt = record.updatedAt
                    entriesUpdated += 1
                } else {
                    let entry = TimeEntry(
                        id: record.id,
                        entryDescription: record.description,
                        note: record.note,
                        category: record.category,
                        startAt: record.startAt,
                        endAt: record.endAt,
                        project: project,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt
                    )
                    context.insert(entry)
                    entriesByID[record.id] = entry
                    entriesInserted += 1
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return ImportResult(
            projectsInserted: projectsInserted,
            projectsUpdated: projectsUpdated,
            entriesInserted: entriesInserted,
            entriesUpdated: entriesUpdated
        )
    }

    private func loadRows(filename: String, folder: URL) throws -> [[String]] {
        let url = folder.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { throw CSVTransferError.missingFile(filename) }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try CSVCodec.decode(text)
    }

    private func parseProjects(_ rows: [[String]]) throws -> [ProjectCSVRecord] {
        let expected = ["id", "name", "color_hex", "created_at", "updated_at", "archived_at"]
        try validateHeader(rows, expected: expected, file: Self.projectsFilename)
        return try rows.dropFirst().enumerated().map { offset, row in
            let number = offset + 2
            guard row.count == expected.count else { throw malformed(Self.projectsFilename, number, "Expected \(expected.count) columns.") }
            guard let id = UUID(uuidString: row[0]) else { throw malformed(Self.projectsFilename, number, "Invalid project UUID.") }
            let name = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw malformed(Self.projectsFilename, number, "Project name cannot be empty.") }
            guard isValidColorHex(row[2]) else { throw malformed(Self.projectsFilename, number, "color_hex must contain exactly six hexadecimal characters.") }
            guard let createdAt = date(row[3]), let updatedAt = date(row[4]) else {
                throw malformed(Self.projectsFilename, number, "Invalid created_at or updated_at timestamp.")
            }
            let archivedAt: Date?
            if row[5].isEmpty { archivedAt = nil }
            else if let parsed = date(row[5]) { archivedAt = parsed }
            else { throw malformed(Self.projectsFilename, number, "Invalid archived_at timestamp.") }
            return ProjectCSVRecord(id: id, name: name, colorHex: row[2], createdAt: createdAt, updatedAt: updatedAt, archivedAt: archivedAt)
        }
    }

    private func parseEntries(_ rows: [[String]]) throws -> [TimeEntryCSVRecord] {
        let expected = ["id", "description", "note", "category", "project_id", "start_at", "end_at", "created_at", "updated_at"]
        let legacy = ["id", "description", "note", "project_id", "start_at", "end_at", "created_at", "updated_at"]
        guard let header = rows.first else { throw malformed(Self.entriesFilename, 1, "File is empty.") }
        guard header == expected || header == legacy else { throw malformed(Self.entriesFilename, 1, "Unexpected header.") }
        let isLegacy = header == legacy
        return try rows.dropFirst().enumerated().map { offset, row in
            let number = offset + 2
            let columnCount = isLegacy ? legacy.count : expected.count
            guard row.count == columnCount else { throw malformed(Self.entriesFilename, number, "Expected \(columnCount) columns.") }
            let category: TimeEntryCategory
            if isLegacy {
                category = .other
            } else if let parsedCategory = TimeEntryCategory(rawValue: row[3]) {
                category = parsedCategory
            } else {
                throw malformed(Self.entriesFilename, number, "Unknown time-entry category.")
            }
            let projectIndex = isLegacy ? 3 : 4
            let startIndex = isLegacy ? 4 : 5
            guard let id = UUID(uuidString: row[0]), let projectID = UUID(uuidString: row[projectIndex]) else {
                throw malformed(Self.entriesFilename, number, "Invalid entry or project UUID.")
            }
            guard
                let startAt = date(row[startIndex]),
                let endAt = date(row[startIndex + 1]),
                let createdAt = date(row[startIndex + 2]),
                let updatedAt = date(row[startIndex + 3])
            else { throw malformed(Self.entriesFilename, number, "Invalid timestamp.") }
            return TimeEntryCSVRecord(
                id: id,
                description: row[1],
                note: row[2],
                category: category,
                projectID: projectID,
                startAt: startAt,
                endAt: endAt,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func validate(projects: [ProjectCSVRecord], entries: [TimeEntryCSVRecord]) throws {
        try ensureUnique(projects.map(\.id), file: Self.projectsFilename)
        try ensureUnique(entries.map(\.id), file: Self.entriesFilename)

        var names = Set<String>()
        for project in projects {
            let key = project.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard names.insert(key).inserted else { throw CSVTransferError.duplicateProjectName(project.name) }
        }

        let projectIDs = Set(projects.map(\.id))
        for entry in entries {
            guard projectIDs.contains(entry.projectID) else {
                throw CSVTransferError.missingProject(entryID: entry.id, projectID: entry.projectID)
            }
            let duration = entry.endAt.timeIntervalSince(entry.startAt)
            guard duration > 0, duration <= 24 * 3_600 else {
                throw CSVTransferError.invalidEntryDuration(entryID: entry.id)
            }
        }
    }

    private func ensureUnique(_ ids: [UUID], file: String) throws {
        var seen = Set<UUID>()
        for id in ids where !seen.insert(id).inserted {
            throw CSVTransferError.duplicateIdentifier(file: file, id: id)
        }
    }

    private func validateHeader(_ rows: [[String]], expected: [String], file: String) throws {
        guard let header = rows.first else { throw malformed(file, 1, "File is empty.") }
        guard header == expected else { throw malformed(file, 1, "Unexpected header.") }
    }

    private func malformed(_ file: String, _ row: Int, _ reason: String) -> CSVTransferError {
        .malformedCSV(file: file, row: row, reason: reason)
    }

    private func dateString(_ date: Date) -> String { isoFormatter.string(from: date) }
    private func optionalDateString(_ date: Date?) -> String { date.map(dateString) ?? "" }
    private func date(_ string: String) -> Date? { isoFormatter.date(from: string) }

    private func isValidColorHex(_ value: String) -> Bool {
        let hexadecimalScalars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return value.count == 6 && value.unicodeScalars.allSatisfy(hexadecimalScalars.contains)
    }
}

enum CSVCodec {
    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var index = text.startIndex
        var quoted = false

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    quoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }
            index = next
        }

        guard !quoted else {
            throw CSVTransferError.malformedCSV(file: "CSV", row: rows.count + 1, reason: "Unterminated quoted field.")
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
