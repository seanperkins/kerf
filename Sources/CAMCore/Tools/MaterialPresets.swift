import CADCore
import Foundation

/// A common material with a starting chip load for a sharp two-flute cutter. The chip load
/// grows with the cutter's diameter (a 1/8 in bit takes about half the bite of a 1/4 in bit), so
/// each preset is a rate per inch of diameter, capped at 1/2 in where the growth stops.
public struct MaterialPreset: Hashable, Sendable, Identifiable {
    public var name: String
    /// Chip load per inch of cutter diameter, inches per tooth: 0.040 gives a 1/4 in cutter 0.010 in/tooth.
    public var chipLoadPerInch: Double
    /// Lowercase words that name this material in a job's material field ("Baltic birch ply").
    public var keywords: [String]
    public var id: String { name }
}

/// Starting points for the feeds calculator, from the ranges bit makers publish for wood routers;
/// each sits at the conservative end, because the material, the cutter and the machine's
/// rigidity all move the right number, and a light cut is the safe first try.
public enum MaterialPresets {
    public static let all: [MaterialPreset] = [
        MaterialPreset(name: "Softwood", chipLoadPerInch: 0.048, keywords: ["softwood", "pine", "cedar", "fir", "spruce", "poplar"]),
        MaterialPreset(name: "Hardwood", chipLoadPerInch: 0.040,
                       keywords: ["hardwood", "oak", "maple", "walnut", "cherry", "ash", "birch", "beech", "mahogany", "hickory"]),
        MaterialPreset(name: "Plywood", chipLoadPerInch: 0.044, keywords: ["plywood", "ply", "baltic"]),
        MaterialPreset(name: "MDF", chipLoadPerInch: 0.052, keywords: ["mdf", "hdf", "fiberboard", "particleboard", "particle"]),
        MaterialPreset(name: "Acrylic", chipLoadPerInch: 0.028, keywords: ["acrylic", "plexi", "pmma", "polycarb", "lexan"]),
        MaterialPreset(name: "HDPE", chipLoadPerInch: 0.044, keywords: ["hdpe", "polyethylene", "uhmw", "delrin", "acetal", "plastic"]),
        MaterialPreset(name: "Aluminum", chipLoadPerInch: 0.014, keywords: ["alumin"]),
        MaterialPreset(name: "Foam", chipLoadPerInch: 0.070, keywords: ["foam", "eps", "xps", "styro"]),
    ]

    /// Diameters above this take the 1/2 in chip load: big cutters do not keep scaling up.
    public static let diameterCap = 0.5

    public static func preset(named name: String) -> MaterialPreset? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Starting chip load for `preset` with a cutter of `diameter`, in `units` per tooth.
    public static func chipLoad(_ preset: MaterialPreset, diameter: Double, units: LengthUnit) -> Double {
        let inches = min(max(diameter, 0) * units.factor(to: .inch), diameterCap)
        return preset.chipLoadPerInch * inches * LengthUnit.inch.factor(to: units)
    }

    /// The preset a job's material name refers to ("3/4 Baltic birch ply" is plywood; "Oak" is
    /// hardwood), or nil when no word of it is known. The preset's own name wins over keywords, and
    /// sheet goods and non-wood materials are checked before the wood species, so "birch plywood"
    /// is plywood even though birch is a hardwood.
    public static func preset(matching material: String?) -> MaterialPreset? {
        guard let material else { return nil }
        if let exact = preset(named: material.trimmingCharacters(in: .whitespaces)) { return exact }
        let words = material.lowercased().split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return nil }
        let order = ["Plywood", "MDF", "Foam", "Acrylic", "HDPE", "Aluminum", "Hardwood", "Softwood"]
        return order.compactMap(preset(named:)).first { p in
            words.contains { w in p.keywords.contains { k in w == k || (k.count >= 4 && w.hasPrefix(k)) } }
        }
    }
}
