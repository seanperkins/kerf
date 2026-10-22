import Foundation
import Testing
@testable import KerfApp

/// A failed save inside a sheet is shown by the sheet, above its buttons: an alert set on the document
/// sits under the sheet and never shows.
@Suite struct SheetErrorTests {
    @Test func aSuccessfulWriteLeavesNoError() throws {
        let file = AppTestSupport.tempDir().appendingPathComponent("out.tap")
        #expect(SheetError.attempt("Could not save G-code") { try "G0 X0".write(to: file, atomically: true, encoding: .utf8) } == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "G0 X0")
    }

    @Test func aWriteIntoAnUnwritableFolderGivesTheTextTheSheetShows() throws {
        // A folder that cannot be created because its parent is a file: the same write failure as a
        // read-only or missing export folder.
        let dir = AppTestSupport.tempDir()
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let target = blocker.appendingPathComponent("out.tap")
        let message = try #require(SheetError.attempt("Could not save G-code") {
            try "G0 X0".write(to: target, atomically: true, encoding: .utf8)
        })
        #expect(message.hasPrefix("Could not save G-code: "))
        #expect(message.count > "Could not save G-code: ".count)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func theMessageNamesTheFileThatCouldNotBeRead() {
        let error = CocoaError(.fileReadNoSuchFile)
        #expect(SheetError.message("Could not read plates.csv", error) == "Could not read plates.csv: \(error.localizedDescription)")
        #expect(SheetError.message("Plates not made", "No rows") == "Plates not made: No rows")
    }
}
