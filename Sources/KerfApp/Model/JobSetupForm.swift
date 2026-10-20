import CADCore
import CAMCore
import Foundation

/// Editable copy of the Job Setup sheet. Switching units converts the values in the form;
/// applying converts the whole project when the units differ.
struct JobSetupForm: Equatable {
    var units: LengthUnit
    var job: JobSetup
    var gridSpacing: Double
    var name: String

    init(document: Document) {
        units = document.units; job = document.job; gridSpacing = document.gridSpacing; name = document.name
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
        p.document.job = job
        p.document.gridSpacing = gridSpacing
        p.document.name = name
        p.ensureBottomLayer()
        return p
    }
}
