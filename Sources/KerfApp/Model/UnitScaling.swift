import CADCore
import CAMCore
import Foundation

// Length scaling for parameter structs. Used to (a) rescale inch-based defaults for mm documents
// and (b) convert a whole project when the user switches document units in Job Setup.
// Angles, ratios, counts and seeds are never scaled.

extension DepthSettings {
    func scaled(by f: Double) -> DepthSettings {
        var d = self
        d.startDepth *= f; d.cutDepth *= f; d.passDepth = passDepth.map { $0 * f }; d.finalPassDepth *= f
        return d
    }
}

extension RampSettings {
    func scaled(by f: Double) -> RampSettings { var r = self; r.length *= f; return r }
}

extension TabSettings {
    func scaled(by f: Double) -> TabSettings { var t = self; t.length *= f; t.thickness *= f; return t }
}

extension LeadSettings {
    func scaled(by f: Double) -> LeadSettings { var l = self; l.distance *= f; l.overcut *= f; return l }
}

extension ProfileParameters {
    func scaled(by f: Double) -> ProfileParameters {
        var p = self
        p.depth = depth.scaled(by: f); p.allowance *= f; p.tabs = tabs.scaled(by: f)
        p.ramp = ramp.scaled(by: f); p.lead = lead.scaled(by: f)
        return p
    }
}

extension PocketParameters {
    func scaled(by f: Double) -> PocketParameters {
        var p = self
        p.depth = depth.scaled(by: f); p.allowance *= f; p.ramp = ramp.scaled(by: f)
        return p
    }
}

extension DrillParameters {
    func scaled(by f: Double) -> DrillParameters {
        var p = self
        p.startDepth *= f; p.cutDepth *= f; p.peckDepth *= f; p.retractHeight *= f
        return p
    }
}

extension FlutingParameters {
    func scaled(by f: Double) -> FlutingParameters { var p = self; p.depth = depth.scaled(by: f); return p }
}

extension TextureParameters {
    func scaled(by f: Double) -> TextureParameters {
        var p = self
        p.maxDepth *= f; p.spacing *= f; p.minStrokeLength *= f; p.maxStrokeLength *= f
        return p
    }
}

extension VCarveParameters {
    func scaled(by f: Double) -> VCarveParameters {
        var p = self
        p.startDepth *= f; p.flatDepth = flatDepth.map { $0 * f }; p.passDepth = passDepth.map { $0 * f }
        return p
    }
}

extension InlayParameters {
    func scaled(by f: Double) -> InlayParameters {
        var p = self
        p.pocketDepth *= f; p.maleStartDepth *= f; p.glueGap *= f; p.maleBoundaryMargin *= f
        return p
    }
}

extension Relief3DParameters {
    func scaled(by f: Double) -> Relief3DParameters {
        var p = self
        p.resolution *= f
        p.roughing.allowance *= f
        p.roughing.passDepth = roughing.passDepth.map { $0 * f }
        p.finishing.stepover = finishing.stepover.map { $0 * f }
        return p
    }
}

extension AnyOperation {
    func scaled(by f: Double) -> AnyOperation {
        switch self {
        case .profile(var o): o.params = o.params.scaled(by: f); return .profile(o)
        case .pocket(var o): o.params = o.params.scaled(by: f); return .pocket(o)
        case .drill(var o): o.params = o.params.scaled(by: f); return .drill(o)
        case .vcarve(var o): o.params = o.params.scaled(by: f); return .vcarve(o)
        case .inlay(var o): o.params = o.params.scaled(by: f); return .inlay(o)
        case .fluting(var o): o.params = o.params.scaled(by: f); return .fluting(o)
        case .texture(var o): o.params = o.params.scaled(by: f); return .texture(o)
        case .relief3D(var o): o.params = o.params.scaled(by: f); return .relief3D(o)
        }
    }
}

extension PlacedModel {
    func scaled(by f: Double) -> PlacedModel {
        var m = self
        m.mesh.vertices = mesh.vertices.map { $0 * f }
        m.offset = offset * f; m.depth *= f; m.zTop *= f
        return m
    }
}

extension Document {
    /// Same design expressed in `target` units (geometry, job, grid and models rescaled).
    func converted(to target: LengthUnit) -> Document {
        guard target != units else { return self }
        let f = units.factor(to: target)
        var d = self
        d.units = target
        d.job = job.scaled(by: f)
        d.gridSpacing = gridSpacing * f
        d.shapes = shapes.map { $0.transformed(.scale(f, f)) }
        d.models = models.map { $0.scaled(by: f) }
        return d
    }
}

extension KerfProject {
    /// Converts the design and every operation's lengths to `target` units.
    func converted(to target: LengthUnit) -> KerfProject {
        guard target != document.units else { return self }
        let f = document.units.factor(to: target)
        var p = self
        p.document = document.converted(to: target)
        p.operations = operations.map { $0.scaled(by: f) }
        return p
    }
}
