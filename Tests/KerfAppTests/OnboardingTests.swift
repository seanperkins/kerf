import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct OnboardingTests {
    @Test func samplesAreFoundInTheCheckout() throws {
        for s in SampleProjects.all {
            let url = try #require(SampleProjects.url(for: s), "\(s.fileName) not found")
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        // The sign opens as a project with toolpaths ready to calculate.
        let url = try #require(SampleProjects.url(for: SampleProjects.sign))
        let project = try KerfProject.decode(from: Data(contentsOf: url))
        #expect(project.operations.count >= 4)
    }

    @Test func bundleFolderWinsOverCheckout() throws {
        let dir = AppTestSupport.tempDir()
        try Data("{}".utf8).write(to: dir.appendingPathComponent(SampleProjects.sign.fileName))
        let found = SampleProjects.url(for: SampleProjects.sign, in: [dir] + SampleProjects.searchDirectories())
        #expect(found?.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        #expect(SampleProjects.url(for: SampleProjects.sign, in: [AppTestSupport.tempDir()]) == nil)
    }

    @Test func quickStartCoversTheWorkflow() {
        #expect(SampleProjects.quickStart.count == 6)
        #expect(SampleProjects.quickStart.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        #expect(SampleProjects.all.filter(\.isProject) == [SampleProjects.sign])
    }

    @Test func bundleScriptCopiesSamples() throws {
        // scripts/bundle.sh must ship the samples the Welcome window opens.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: repo.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
        #expect(script.contains("Contents/Resources/samples"))
    }
}
