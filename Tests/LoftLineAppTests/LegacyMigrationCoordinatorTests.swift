import CADCore
import Foundation
import Testing
@testable import LoftLineApp

/// A copier that fails until told not to.
private final class FlakyCopy {
    var fails = true
    func copy(_ src: URL, _ dst: URL) throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.copyItem(at: src, to: dst)
    }
}

@Suite struct LegacyMigrationCoordinatorTests {
    @Test @MainActor func failureIsRecordedThenRetryClearsItAndReloadsTools() throws {
        let f = try LegacyKerfMigrationTests.Fixture(); defer { f.cleanUp() }
        try f.write("a", "a.json")
        let flaky = FlakyCopy()
        var reloads = 0
        let c = LegacyMigrationCoordinator(migration: f.migration(copy: flaky.copy), reloadTools: { reloads += 1 },
                                           environment: [:])
        c.runAtLaunch()
        #expect(c.failure != nil)
        #expect(reloads == 0)
        flaky.fails = false
        #expect(c.resolve(.retry) == .completed)
        #expect(c.failure == nil)
        #expect(reloads == 1)
        #expect(f.read("a.json") == "a")
    }

    @Test @MainActor func continueWithoutWritesSkippedAndClearsTheFailure() throws {
        let f = try LegacyKerfMigrationTests.Fixture(); defer { f.cleanUp() }
        try f.write("a", "a.json")
        var reloads = 0
        let c = LegacyMigrationCoordinator(migration: f.migration(copy: FlakyCopy().copy), reloadTools: { reloads += 1 },
                                           environment: [:])
        c.runAtLaunch()
        #expect(c.failure != nil)
        #expect(c.resolve(.continueWithout) == nil)
        #expect(c.failure == nil)
        #expect(f.defaults.string(forKey: LegacyKerfMigration.flagKey) == "skipped")
        #expect(reloads == 0)
    }

    @Test @MainActor func noMigrationEnvVarSkipsTheRun() throws {
        let f = try LegacyKerfMigrationTests.Fixture(); defer { f.cleanUp() }
        try f.write("a", "a.json")
        let c = LegacyMigrationCoordinator(migration: f.migration(), reloadTools: {},
                                           environment: ["LOFTLINE_NO_MIGRATION": "1"])
        c.runAtLaunch()
        #expect(c.failure == nil)
        #expect(!FileManager.default.fileExists(atPath: f.newSupport.path))
        #expect(f.defaults.object(forKey: LegacyKerfMigration.flagKey) == nil)
    }

    @Test @MainActor func toolLibraryReloadPicksUpAFileWrittenAfterInit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("loftline-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ToolLibraryStore(fileURL: dir.appendingPathComponent("tools.json"))
        let model = ToolLibraryModel(store: store)
        let seededCount = model.tools.count
        var library = ToolLibrary.seeded
        library.upsert(ToolLibraryModel.template(kind: .endMill, units: .inch, number: 901))
        try store.save(library)
        #expect(model.tools.count == seededCount)
        model.reload()
        #expect(model.tools.count == seededCount + 1)
        #expect(model.tools.contains { $0.number == 901 })
    }

    /// The tool library loads while the SwiftUI `App` is built, so the migration has to run first, and after the command-line
    /// check so that headless commands never copy user data or raise an alert.
    @Test func mainSwiftOrdersTheStartup() throws {
        let main = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LoftLineApp/main.swift")
        let text = try String(contentsOf: main, encoding: .utf8)
        let cli = try #require(text.range(of: "runIfRequested")).lowerBound
        let migration = try #require(text.range(of: "LegacyMigrationCoordinator.shared.runAtLaunch()")).lowerBound
        let app = try #require(text.range(of: "LoftLineApp.main()")).lowerBound
        #expect(cli < migration && migration < app)
    }
}
