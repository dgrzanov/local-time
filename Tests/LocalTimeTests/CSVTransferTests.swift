import Foundation
import SwiftData
import XCTest
@testable import LocalTime

final class CSVTransferTests: XCTestCase {
    @MainActor
    func testCodecRoundTripsQuotesCommasAndNewlines() throws {
        let rows = [["id", "description"], ["1", "Review, \"fix\"\nand ship"]]
        XCTAssertEqual(try CSVCodec.decode(CSVCodec.encode(rows)), rows)
    }

    @MainActor
    func testExportPreviewAndImportRoundTrip() throws {
        let source = try makeContainer()
        let sourceContext = ModelContext(source)
        let project = Project(name: "Product", colorHex: "3B82F6")
        let entry = TimeEntry(
            entryDescription: "Build dashboard",
            note: "First pass",
            category: .development,
            startAt: makeDate("2026-08-25T08:00:00Z"),
            endAt: makeDate("2026-08-25T10:00:00Z"),
            project: project
        )
        sourceContext.insert(project)
        sourceContext.insert(entry)
        try sourceContext.save()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let service = LocalCSVTransferService()
        try service.export(projects: [project], entries: [entry], to: folder)
        let bundle = try service.previewImport(from: folder)
        XCTAssertEqual(bundle.projects.count, 1)
        XCTAssertEqual(bundle.entries.count, 1)

        let destination = try makeContainer()
        let destinationContext = ModelContext(destination)
        let first = try service.apply(bundle, to: destinationContext)
        XCTAssertEqual(first, ImportResult(projectsInserted: 1, projectsUpdated: 0, entriesInserted: 1, entriesUpdated: 0))

        let second = try service.apply(bundle, to: destinationContext)
        XCTAssertEqual(second, ImportResult(projectsInserted: 0, projectsUpdated: 1, entriesInserted: 0, entriesUpdated: 1))
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<Project>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<TimeEntry>()), 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<TimeEntry>()).first?.category, .development)
    }

    @MainActor
    func testPreviewRejectsMissingProjectReference() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let timestamp = "2026-08-25T08:00:00.000Z"
        let projects = "id,name,color_hex,created_at,updated_at,archived_at\n"
        let entries = "id,description,note,project_id,start_at,end_at,created_at,updated_at\n\(UUID()),Work,,\(UUID()),\(timestamp),2026-08-25T09:00:00.000Z,\(timestamp),\(timestamp)\n"
        try projects.write(to: folder.appendingPathComponent("projects.csv"), atomically: true, encoding: .utf8)
        try entries.write(to: folder.appendingPathComponent("time_entries.csv"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try LocalCSVTransferService().previewImport(from: folder)) { error in
            guard case CSVTransferError.missingProject = error else {
                return XCTFail("Expected missingProject, got \(error)")
            }
        }
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            TimeEntry.self,
            AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
