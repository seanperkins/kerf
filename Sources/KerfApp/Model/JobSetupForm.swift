import CADCore
import CAMCore
import Foundation
import PostCore

/// Editable copy of the Job Setup sheet. Switching units converts the values in the form;
/// applying converts the whole project when the units differ.
struct JobSetupForm: Equatable {
    var units: LengthUnit
    var job: JobSetup
    var gridSpacing: Double
    var name: String
    /// Name of the current material sheet (multi-sheet jobs).
    var sheetName: String
    var isMultiSheet: Bool
    /// The machine and post processor the job is cut with. nil means "leave the project's as they are"
    /// (a form made from a document alone, or a project whose post matches no known machine).
    var machineID: String?
    var postID: String?

    init(document: Document) {
        units = document.units; job = document.job; gridSpacing = document.gridSpacing; name = document.name
        sheetName = document.currentSheetName; isMultiSheet = document.isMultiSheet
    }

    init(project: KerfProject, machines: [MachineDefinition]) {
        self.init(document: project.document)
        machineID = MachineResolver.machine(for: project, machines: machines)?.id
        postID = project.postProfileID ?? PostProfileStore.defaultID(for: project.document.units)
    }

    /// Chooses `machine`, switching to one of its posts if the current post does not drive it.
    mutating func selectMachine(_ machine: MachineDefinition, profiles: [PostProfile]) {
        machineID = machine.id
        let current = postID ?? PostProfileStore.defaultID(for: units)
        postID = MachineResolver.post(afterSelecting: machine, current: current, units: units, profiles: profiles)
    }

    mutating func setUnits(_ new: LengthUnit) {
        guard new != units else { return }
        let f = units.factor(to: new)
        job = job.scaled(by: f)
        gridSpacing *= f
        units = new
    }

    /// Problems that block applying (empty = valid).
    var problems: [String] {
        var p: [String] = []
        if job.width <= 0 || job.height <= 0 { p.append("Material width and height must be positive.") }
        if job.thickness <= 0 { p.append("Material thickness must be positive.") }
        if job.safeZ <= 0 { p.append("Safe Z must be above the material.") }
        if job.homeZ < job.safeZ { p.append("Home Z should be at or above Safe Z.") }
        if let g = job.plungeGap, g < 0 || g > job.safeZ { p.append("Plunge Z must be between the material top and Safe Z.") }
        if gridSpacing <= 0 { p.append("Grid spacing must be positive.") }
        return p
    }

    func apply(to project: KerfProject) -> KerfProject {
        var p = project.converted(to: units)
        // Job Setup edits the current sheet's stock; the other sheets keep theirs, and so do
        // the operations that cut them.
        let oldThickness = p.document.job.thickness
        let sheet = p.document.currentSheetID
        let onThisSheet = Set(p.operations.filter { p.sheetID(of: $0) == sheet }.map(\.id))
        p.document.job = job
        p.operations = DepthFollow.adjusted(p.operations, thicknessFrom: oldThickness, to: job.thickness) { onThisSheet.contains($0.id) }
        p.document.gridSpacing = gridSpacing
        p.document.name = name
        if isMultiSheet, !sheetName.isEmpty { p.document.activeSheetName = sheetName }
        if let machineID { p.machineID = machineID }
        if let postID { p.postProfileID = postID }
        p.ensureBottomLayer()
        return p
    }
}
