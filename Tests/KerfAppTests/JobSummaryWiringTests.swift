import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

/// The sidebar total through the app's own wiring (issue #27): the document's motion estimate over
/// the program the summary orders, against the 3D preview's estimate of the same toolpaths.
@Suite struct JobSummaryWiringTests {
    /// A document with a profile and a pocket on the same vectors, on two different tools so the
    /// program has a tool change, both calculated.
    @MainActor
    private func makeDoc(units: LengthUnit) -> KerfDocument {
        var p = AppTestSupport.project()
        if units == .millimeter {
            p.document.units = .millimeter
            p.document.job = JobSetup(width: 600, height: 450, thickness: 18, safeZ: 5, homeZ: 20)
            p.document.shapes = p.document.shapes.map { $0.transformed(.scale(25.4, 25.4)) }
        }
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        doc.selectAll()
        doc.addOperation(.profile); doc.addOperation(.pocket)
        var pocket = doc.project.operations[1]
        var setup = pocket.editableSetup
        setup.toolID = ToolLibrary.seeded.tools[1].id   // 1/8 in end mill; the profile keeps the 1/4 in
        pocket.editableSetup = setup
        let changed = pocket
        doc.perform("Tool") { $0.upsertOperation(changed) }
        doc.calculateNow(doc.project.operations.map(\.id))
        return doc
    }

    @MainActor
    @Test(arguments: [LengthUnit.inch, .millimeter], [true, false])
    func sidebarTotalMatchesThePreviewsEstimate(units: LengthUnit, groupByTool: Bool) {
        let doc = makeDoc(units: units)
        let settings = TimeEstimateSettings.load()
        #expect(doc.results.count == 2 && doc.results.values.allSatisfy(\.isOK))
        let s = doc.jobSummary(groupByTool: groupByTool, settings: settings)
        #expect(s.stops == 1 && s.toolChangeAllowance == settings.toolChangeSeconds)
        // What the preview shows for "All Toolpaths": the same list, timed with the post's rapid rate
        // in document units and the tool-change allowance.
        let shown = PreviewScope.all.toolpaths(operations: doc.outputProject.operations, results: doc.results,
                                               hidden: [], selected: nil, groupByTool: groupByTool)
        let preview = settings.estimate(shown, rapidRate: SimulationPreviewView.rapidRate(for: doc.postProfile, units: doc.units),
                                        units: doc.units)
        #expect(s.machiningSeconds > 0)
        #expect(abs(s.totalSeconds - preview) < 1e-6, "\(units) grouped \(groupByTool): \(s.totalSeconds) vs \(preview)")
        // The program's motion is more than the operations' own by the rapids between them.
        let separate = doc.results.values.map { doc.motionSeconds($0.toolpaths) }.reduce(0, +)
        #expect(s.machiningSeconds > separate)
        // The job sheet prints the same total.
        let sheet = doc.makeJobSheet()
        #expect(sheet.totalTime == ToolpathCalculator.formatDuration(s.totalSeconds))
    }

    @MainActor
    @Test func summaryIsRebuiltOnlyWhenItsInputsChange() {
        let doc = makeDoc(units: .inch)
        let memo = JobSummary.Memo()
        var timed = 0
        func summary(groupByTool: Bool = false, settings: TimeEstimateSettings = TimeEstimateSettings(), rapid: Double = 200) -> JobSummary {
            let key = JobSummary.Key(operations: doc.outputProject.operations, results: doc.results, groupByTool: groupByTool,
                                     settings: settings, rapidRate: rapid, units: .inch)
            return memo.summary(operations: doc.outputProject.operations, results: doc.results, key: key) { timed += 1; return doc.motionSeconds($0) }
        }
        let first = summary()
        #expect(summary() == first && timed == 1)
        _ = summary(groupByTool: true)
        #expect(timed == 2)
        var slower = TimeEstimateSettings(); slower.toolChangeSeconds += 1
        _ = summary(settings: slower)
        #expect(timed == 3)
        _ = summary(rapid: 300)
        #expect(timed == 4)
        // A recalculation replaces the toolpaths, so the summary is rebuilt.
        doc.calculateNow(doc.project.operations.map(\.id))
        _ = summary()
        #expect(timed == 5)
    }
}
