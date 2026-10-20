import CADCore
import CAMCore
import Foundation

/// Material and machine layout checks that complement `GCodeValidator`: vectors outside the
/// material, toolpaths that cut beyond the material edge, and material larger than the
/// machine's travel. All warnings (the cut itself may be intended); lengths in document units.
public enum LayoutChecks {
    /// Visible vectors that lie partly or wholly outside the material. Shapes on
    /// `ignoredLayers` (e.g. extra nesting sheets laid out beside the material) are skipped.
    public static func design(_ doc: Document, ignoredLayers: Set<UUID> = []) -> [GCodeIssue] {
        let eps = doc.units == .inch ? 0.0005 : 0.01
        let material = doc.job.materialBounds
        let hidden = Set(doc.layers.filter { !$0.isVisible }.map(\.id)).union(ignoredLayers)
        var outside: [String] = [], beyond: [String] = []
        for (i, s) in doc.shapes.enumerated() where !hidden.contains(s.layerID) {
            let b = s.bounds()
            guard !b.isEmpty else { continue }
            let name = s.name.isEmpty ? "#\(i + 1)" : s.name
            if !b.intersects(material.insetBy(-eps)) {
                outside.append(name)
            } else if b.min.x < -eps || b.min.y < -eps || b.max.x > material.max.x + eps || b.max.y > material.max.y + eps {
                beyond.append(name)
            }
        }
        var issues: [GCodeIssue] = []
        if !outside.isEmpty {
            issues.append(GCodeIssue(severity: .warning, message:
                "\(count(outside.count, "vector")) entirely outside the material: \(list(outside))"))
        }
        if !beyond.isEmpty {
            issues.append(GCodeIssue(severity: .warning, message:
                "\(count(beyond.count, "vector")) extend\(beyond.count == 1 ? "s" : "") past the material edge: \(list(beyond))"))
        }
        return issues
    }

    /// Material bigger than the machine's X/Y travel (profile limits, converted to `units`).
    public static func materialFits(_ job: JobSetup, units: LengthUnit, profile: PostProfile) -> [GCodeIssue] {
        let f = profile.units.factor(to: units)
        let tx = profile.limits.xTravel * f, ty = profile.limits.yTravel * f
        let eps = units == .inch ? 0.0005 : 0.01
        guard job.width > tx + eps || job.height > ty + eps else { return [] }
        func n(_ v: Double) -> String { NumberFormat.compact(v, maxDecimals: 3) }
        return [GCodeIssue(severity: .warning, message:
            "The material (\(n(job.width)) x \(n(job.height)) \(units.abbreviation)) is larger than the machine travel "
                + "(\(n(tx)) x \(n(ty)) \(units.abbreviation)); parts of it cannot be reached. Split the job into tiles or turn the sheet.")]
    }

    /// Cutting moves (below the material top) whose tool centre is further outside the
    /// material than the tool radius, i.e. the cutter is entirely off the stock.
    public static func toolpaths(_ toolpaths: [Toolpath], job: JobSetup, units: LengthUnit) -> [GCodeIssue] {
        let coords = MachineCoordinates(job: job)
        let eps = units == .inch ? 0.0005 : 0.01
        let m = job.materialBounds
        var issues: [GCodeIssue] = []
        for tp in toolpaths {
            let slack = tp.tool.converted(to: units).radius + eps
            var worst = 0.0
            for move in tp.moves {
                switch move {
                case .linear(let p, _), .arcCW(let p, _, _), .arcCCW(let p, _, _):
                    guard p.z < coords.materialTopZ - eps else { continue }
                    let q = coords.materialXY(fromMachine: p.xy)
                    let dx = max(m.min.x - q.x, 0, q.x - m.max.x)
                    let dy = max(m.min.y - q.y, 0, q.y - m.max.y)
                    worst = max(worst, (dx * dx + dy * dy).squareRoot())
                default: continue
                }
            }
            if worst > slack {
                issues.append(GCodeIssue(severity: .warning, message:
                    "Toolpath '\(tp.name)' cuts outside the material (up to \(NumberFormat.compact(worst - slack + eps, maxDecimals: 3)) \(units.abbreviation) beyond the edge)"))
            }
        }
        return issues
    }

    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private static func list(_ names: [String]) -> String {
        let shown = names.prefix(5).joined(separator: ", ")
        return names.count > 5 ? shown + " and \(names.count - 5) more" : shown
    }
}
