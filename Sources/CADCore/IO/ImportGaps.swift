import Foundation

/// The gap report shared by the importers that do not join loose entities (SVG, EPS, PDF): open
/// vectors whose ends nearly meet are almost always an outline that failed to close in the
/// drawing program, and the first sign of it would otherwise be a toolpath that refuses the vector.
/// DXF has its own wording, because it joins first and says so.
public enum ImportGaps {
    /// Ends further apart than this are "open on purpose"; nearer ones are reported. The join
    /// tolerance and the near-miss factor are the DXF importer's, so every format agrees.
    public static func tolerance(_ units: LengthUnit) -> Double { units == .inch ? 0.0005 : 0.01 }

    /// One warning per layer that has open vectors with nearly meeting ends.
    public static func warnings(shapes: [Shape], layers: [Layer], units: LengthUnit) -> [String] {
        let tol = tolerance(units)
        var out: [String] = []
        for layer in layers {
            let paths = shapes.filter { $0.layerID == layer.id }.flatMap(\.paths)
            guard let gaps = PathOps.nearlyMeetingEnds(paths, beyond: tol, upTo: tol * DXFImporter.nearMissFactor) else { continue }
            out.append(warning(layer: layer.name, gaps: gaps, units: units))
        }
        return out
    }

    /// "Layer "SVG Import": 1 open vector has ends that nearly meet, 0.2 mm apart; ..."
    static func warning(layer: String, gaps: PathOps.EndGapReport, units: LengthUnit) -> String {
        func length(_ v: Double) -> String { String(format: "%.2g", v) }
        let lo = length(gaps.smallestGap), hi = length(gaps.largestGap)
        let apart = lo == hi ? lo : "\(lo) to \(hi)"
        let n = gaps.vectorCount
        return "Layer \"\(layer)\": \(n) open vector\(n == 1 ? " has" : "s have") ends that nearly meet, "
            + "\(apart) \(units.abbreviation) apart; a gap in the source drawing is the usual cause. "
            + "Arrange \u{25B8} Join Open Vectors\u{2026} closes \(n == 1 ? "it" : "them")."
    }
}
