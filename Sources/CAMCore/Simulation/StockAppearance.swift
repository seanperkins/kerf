import Foundation

/// How the simulated stock is coloured: material preset (surface, machined colours, wood
/// grain), an optional painted top and an optional flat colour for machined areas.
/// Pure data so the colouring is testable without SceneKit. Owned by preview.
public struct StockAppearance: Hashable, Sendable {
    public enum Material: String, CaseIterable, Identifiable, Sendable {
        case pine, maple, oak, cherry, walnut, mdf, hdpe, aluminum

        public var id: Self { self }

        public var displayName: String {
            switch self {
            case .pine: return "Pine"
            case .maple: return "Maple"
            case .oak: return "Oak"
            case .cherry: return "Cherry"
            case .walnut: return "Walnut"
            case .mdf: return "MDF"
            case .hdpe: return "Plastic (HDPE)"
            case .aluminum: return "Aluminium"
            }
        }
    }

    /// Uncut top surface.
    public var surface: RGBColor
    /// Machined colour just below the surface and at full material depth.
    public var cutShallow: RGBColor
    public var cutDeep: RGBColor
    /// Outside walls and bottom.
    public var side: RGBColor
    /// Grain contrast, 0 = none (about 0.1–0.2 for wood).
    public var grain: Double
    /// Grain line spacing in inches (scaled to document units when meshing).
    public var grainSpacingInch: Double
    /// Specular strength 0...1 for the renderer.
    public var shininess: Double
    /// Paint on the uncut top (the classic painted sign: carving shows bare material).
    public var paint: RGBColor?
    /// Flat colour for every machined area (overrides the material ramp, no grain).
    public var machinedOverride: RGBColor?

    public init(surface: RGBColor, cutShallow: RGBColor, cutDeep: RGBColor, side: RGBColor,
                grain: Double = 0, grainSpacingInch: Double = 0.25, shininess: Double = 0.15,
                paint: RGBColor? = nil, machinedOverride: RGBColor? = nil) {
        self.surface = surface; self.cutShallow = cutShallow; self.cutDeep = cutDeep; self.side = side
        self.grain = grain; self.grainSpacingInch = grainSpacingInch; self.shininess = shininess
        self.paint = paint; self.machinedOverride = machinedOverride
    }

    /// The original look: light wood darkening with depth, no grain.
    public static let `default` = StockAppearance(
        surface: RGBColor(0.90, 0.76, 0.54), cutShallow: RGBColor(0.66, 0.47, 0.27),
        cutDeep: RGBColor(0.40, 0.26, 0.14), side: RGBColor(0.80, 0.64, 0.42))

    public static func preset(_ m: Material) -> StockAppearance {
        switch m {
        case .pine:
            return StockAppearance(surface: RGBColor(0.93, 0.80, 0.58), cutShallow: RGBColor(0.86, 0.71, 0.48),
                                   cutDeep: RGBColor(0.70, 0.54, 0.33), side: RGBColor(0.85, 0.70, 0.47),
                                   grain: 0.16, grainSpacingInch: 0.3)
        case .maple:
            return StockAppearance(surface: RGBColor(0.94, 0.86, 0.70), cutShallow: RGBColor(0.88, 0.78, 0.61),
                                   cutDeep: RGBColor(0.74, 0.62, 0.45), side: RGBColor(0.88, 0.79, 0.62),
                                   grain: 0.07, grainSpacingInch: 0.15)
        case .oak:
            return StockAppearance(surface: RGBColor(0.80, 0.63, 0.40), cutShallow: RGBColor(0.74, 0.56, 0.34),
                                   cutDeep: RGBColor(0.56, 0.40, 0.22), side: RGBColor(0.74, 0.57, 0.35),
                                   grain: 0.18, grainSpacingInch: 0.2)
        case .cherry:
            return StockAppearance(surface: RGBColor(0.74, 0.44, 0.28), cutShallow: RGBColor(0.78, 0.50, 0.33),
                                   cutDeep: RGBColor(0.58, 0.33, 0.20), side: RGBColor(0.70, 0.42, 0.27),
                                   grain: 0.09, grainSpacingInch: 0.18)
        case .walnut:
            return StockAppearance(surface: RGBColor(0.42, 0.29, 0.19), cutShallow: RGBColor(0.50, 0.36, 0.24),
                                   cutDeep: RGBColor(0.32, 0.21, 0.13), side: RGBColor(0.40, 0.28, 0.18),
                                   grain: 0.14, grainSpacingInch: 0.22)
        case .mdf:
            return StockAppearance(surface: RGBColor(0.72, 0.58, 0.42), cutShallow: RGBColor(0.62, 0.48, 0.34),
                                   cutDeep: RGBColor(0.55, 0.42, 0.29), side: RGBColor(0.60, 0.47, 0.33))
        case .hdpe:
            return StockAppearance(surface: RGBColor(0.95, 0.95, 0.93), cutShallow: RGBColor(0.88, 0.88, 0.86),
                                   cutDeep: RGBColor(0.80, 0.80, 0.78), side: RGBColor(0.90, 0.90, 0.88),
                                   shininess: 0.35)
        case .aluminum:
            return StockAppearance(surface: RGBColor(0.80, 0.81, 0.83), cutShallow: RGBColor(0.88, 0.89, 0.91),
                                   cutDeep: RGBColor(0.70, 0.71, 0.73), side: RGBColor(0.76, 0.77, 0.79),
                                   shininess: 0.8)
        }
    }

    /// Depth below which a cell counts as uncut (paint survives), in document units.
    public static let uncutTolerance = 1e-4

    /// Colour of the carved top at material-frame (x, y) for `depth` below the top.
    /// - Parameter unitsPerInch: 1 for inch documents, 25.4 for mm (grain spacing).
    public func topColor(x: Double, y: Double, depth: Double, thickness: Double,
                         unitsPerInch: Double = 1) -> RGBColor {
        if depth <= Self.uncutTolerance {
            if let paint { return paint }
            return grained(surface, x: x, y: y, depth: 0, unitsPerInch: unitsPerInch)
        }
        if let machinedOverride { return machinedOverride }
        let t = Float(min(max(depth / max(thickness, 1e-9), 0), 1))
        // A short blend from the surface colour keeps shallow cuts (V-carve edges) readable.
        let base = t < 0.15 ? surface.mixed(with: cutShallow, min(1, t / 0.15 + 0.5))
                            : cutShallow.mixed(with: cutDeep, (t - 0.15) / 0.85)
        return grained(base, x: x, y: y, depth: depth, unitsPerInch: unitsPerInch)
    }

    /// Wall/bottom colour with grain on the outside faces.
    public func sideColor(x: Double, y: Double, z: Double, unitsPerInch: Double = 1) -> RGBColor {
        grained(side, x: x, y: y, depth: -z, unitsPerInch: unitsPerInch)
    }

    /// Long-grain pattern running along X: wavy growth rings, darker latewood lines.
    func grained(_ c: RGBColor, x: Double, y: Double, depth: Double, unitsPerInch: Double) -> RGBColor {
        guard grain > 0, grainSpacingInch > 0 else { return c }
        let s = grainSpacingInch * max(unitsPerInch, 1e-9)
        // Rings are cylinders around an axis below the board, so cutting deeper shifts them.
        let wave = 0.9 * sin(x / s * 0.21) + 0.35 * sin(x / s * 0.057 + y / s * 0.13)
        let phase = (y + depth * 0.6) / s + wave
        let ring = 0.5 + 0.5 * sin(phase * 2 * .pi)
        let latewood = pow(ring, 6) // thin dark lines
        let f = Float(1 - grain * (0.35 * (1 - ring) + 1.4 * latewood))
        return RGBColor(c.r * f, c.g * f, c.b * f)
    }
}
