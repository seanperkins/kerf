import CADCore
import Foundation

/// Facing (surfacing): takes a layer off the top of a rectangle, the bounding box of the selected vectors or the
/// whole material. The tool's center covers the area grown by (overhang − tool radius), so with the default overhang
/// it rides the area's edge and the cutter's edge reaches a radius past it; the first pass is led in from outside the
/// area (a radius before the first cut) instead of plunging into the surface.
public struct FacingOperation: ToolpathOperation {
    public static let kind = OperationKind.facing
    public var setup: OperationSetup
    public var params: FacingParameters

    public init(setup: OperationSetup, params: FacingParameters = FacingParameters()) {
        self.setup = setup
        self.params = params
    }

    /// Widest stepover allowed, as a fraction of the diameter: the passes must overlap.
    public static let maxStepover = 0.95
    /// Most passes (rows or rings) across the area, and most points in all (one layer's points × depth passes), so a typo
    /// in a stepover cannot ask for an unbounded toolpath.
    static let maxRows = 10_000
    static let maxPoints = 1_000_000

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        guard tool.diameter.isFinite, tool.diameter > 0 else {
            throw CAMError.invalidParameter("Tool diameter must be a positive number")
        }
        guard params.stepover.isFinite, params.stepover > 0, params.stepover <= Self.maxStepover else {
            throw CAMError.invalidParameter("Stepover must be more than 0 and at most \(Int(Self.maxStepover * 100))% of the tool diameter")
        }
        if let o = params.overhang, !(o.isFinite && o >= 0) {
            throw CAMError.invalidParameter("Overhang must be zero or more")
        }
        guard params.depth.startDepth.isFinite, params.depth.cutDepth.isFinite else {
            throw CAMError.invalidParameter("Depths must be numbers")
        }
        try params.depth.validatePassDepth(toolStepdown: tool.stepdown)
        let passes = params.depth.passDepths(toolStepdown: tool.stepdown)
        guard !passes.isEmpty else { throw CAMError.invalidParameter("Cut depth must be deeper than start depth") }

        let tol = context.tolerance
        let units = context.units
        let area = try facedArea(in: context)
        guard area.width > tol, area.height > tol else {
            throw CAMError.invalidGeometry("The area to face has no width or no height")
        }
        let r = tool.radius
        let overhang = params.overhang ?? r
        let step = tool.diameter * params.stepover
        let centre = Self.centreRect(area: area, toolRadius: r, overhang: overhang)

        // One layer of the pattern at a depth, as tool-center points; the same XY every layer.
        let flat: [Vec2]
        switch params.pattern {
        case .rasterX, .rasterY:
            let alongX = params.pattern == .rasterX
            let (lo, hi) = alongX ? (centre.min.y, centre.max.y) : (centre.min.x, centre.max.x)
            guard let rows = Self.positions(from: lo, to: hi, step: step, limit: Self.maxRows) else {
                throw CAMError.invalidParameter("Too many passes across the area: raise the stepover")
            }
            flat = Self.raster(centre, rows: rows, alongX: alongX, lead: r)
        case .spiral:
            let size = min(centre.width, centre.height)
            guard size / step <= Double(2 * Self.maxRows) else {
                throw CAMError.invalidParameter("Too many passes across the area: raise the stepover")
            }
            flat = Self.spiral(centre, step: step, toolRadius: r, clockwise: params.direction == .climb, lead: r,
                               tolerance: tol)
        }
        guard flat.count > 1 else { throw CAMError.invalidGeometry("The area to face leaves nothing to cut") }
        guard flat.count * passes.count <= Self.maxPoints else {
            throw CAMError.invalidParameter("Too many passes: raise the stepover or the depth per pass")
        }

        var builder = ToolpathBuilder(coords: context.coords, tool: tool, units: units, tolerance: tol, fitArcs: false)
        for (k, d) in passes.enumerated() {
            builder.cutChain(flat.map { CutPoint($0, depth: d) }, clearedDepth: k == 0 ? 0 : passes[k - 1])
        }

        var meta = ["area": "\(Self.fmt(area.width, units)) × \(Self.fmt(area.height, units))",
                    "note": surfaceNote(job: context.document.job, units: units)]
        var warnings: [String] = []
        if Self.leavesRoundedCorners(area: area, centre: centre, toolRadius: r, tolerance: tol) {
            warnings.append("the overhang is too small to reach the corners of the area: they are left rounded")
        }
        if Self.reachesBeyondArea(area: area, centre: centre, toolRadius: r, job: context.document.job, tolerance: tol) {
            warnings.append("the cutter reaches past the area into material that is not being faced "
                            + "(the overhang and the lead-in); face the whole material or lower the overhang")
        }
        if !warnings.isEmpty { meta["warning"] = warnings.joined(separator: "; ") }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .facing, tool: tool,
                         moves: builder.finish(), metadata: meta)]
    }

    // MARK: Area

    private func facedArea(in context: CAMContext) throws -> Rect2 {
        switch params.area {
        case .material:
            return context.document.job.materialBounds
        case .vectors:
            let shapes = context.shapes(for: setup)
            guard !shapes.isEmpty else {
                throw CAMError.invalidGeometry("Select the vectors to face, or face the whole material")
            }
            var box = Rect2.empty
            for shape in shapes { for path in shape.paths { box = box.union(path.bounds(tolerance: context.tolerance)) } }
            guard !box.isEmpty else { throw CAMError.invalidGeometry("The selected vectors have no extent") }
            return box
        }
    }

    /// The rectangle the tool's center covers: the area grown by `overhang − toolRadius` on every side (shrunk when the
    /// overhang is under a radius; an axis that would turn inside out collapses to its middle).
    static func centreRect(area: Rect2, toolRadius r: Double, overhang: Double) -> Rect2 {
        let e = overhang - r
        func axis(_ lo: Double, _ hi: Double) -> (Double, Double) {
            lo - e <= hi + e ? (lo - e, hi + e) : ((lo + hi) / 2, (lo + hi) / 2)
        }
        let x = axis(area.min.x, area.max.x), y = axis(area.min.y, area.max.y)
        return Rect2(min: Vec2(x.0, y.0), max: Vec2(x.1, y.1))
    }

    /// True when a corner of `area` is farther than a tool radius from every point the center covers, so the round
    /// cutter leaves it standing.
    static func leavesRoundedCorners(area: Rect2, centre: Rect2, toolRadius r: Double, tolerance: Double) -> Bool {
        let corners = [area.min, Vec2(area.max.x, area.min.y), area.max, Vec2(area.min.x, area.max.y)]
        return corners.contains { c in
            let nearest = Vec2(min(max(c.x, centre.min.x), centre.max.x), min(max(c.y, centre.min.y), centre.max.y))
            return c.distance(to: nearest) > r + tolerance
        }
    }

    /// True when the cutter (with its lead-in) can touch material outside the area.
    static func reachesBeyondArea(area: Rect2, centre: Rect2, toolRadius r: Double, job: JobSetup, tolerance: Double) -> Bool {
        func clipped(_ a: Rect2) -> Rect2 {
            let m = job.materialBounds
            return Rect2(min: Vec2(max(a.min.x, m.min.x), max(a.min.y, m.min.y)),
                         max: Vec2(min(a.max.x, m.max.x), min(a.max.y, m.max.y)))
        }
        let reach = clipped(Rect2(min: centre.min - Vec2(2 * r, 2 * r), max: centre.max + Vec2(2 * r, 2 * r)))
        guard !reach.isEmpty else { return false }
        let faced = clipped(area)
        if faced.isEmpty { return true }
        return reach.min.x < faced.min.x - tolerance || reach.min.y < faced.min.y - tolerance
            || reach.max.x > faced.max.x + tolerance || reach.max.y > faced.max.y + tolerance
    }

    // MARK: Patterns

    /// Evenly spaced positions from `lo` to `hi`, no more than `step` apart (one when they coincide); nil when that
    /// would take more than `limit`.
    static func positions(from lo: Double, to hi: Double, step: Double, limit: Int) -> [Double]? {
        let length = hi - lo
        guard length > 1e-9 else { return [lo] }
        let gaps = (length / step - 1e-9).rounded(.up)
        guard gaps.isFinite, gaps < Double(limit) else { return nil }
        let n = max(1, Int(gaps))
        return (0...n).map { lo + length * Double($0) / Double(n) }
    }

    /// Passes along an axis at each of `rows`, the first from the low end, each the reverse of the one before and
    /// joined at the ends (where the cutter has already been). Led in and out by `lead` past the first and last cut.
    static func raster(_ c: Rect2, rows: [Double], alongX: Bool, lead: Double) -> [Vec2] {
        let (uLo, uHi) = alongX ? (c.min.x, c.max.x) : (c.min.y, c.max.y)
        func point(_ u: Double, _ v: Double) -> Vec2 { alongX ? Vec2(u, v) : Vec2(v, u) }
        var out: [Vec2] = [point(uLo - lead, rows[0])]
        for (j, v) in rows.enumerated() {
            let forward = j % 2 == 0
            out.append(point(forward ? uLo : uHi, v))
            out.append(point(forward ? uHi : uLo, v))
        }
        let forward = (rows.count - 1) % 2 == 0
        out.append(point(forward ? uHi + lead : uLo - lead, rows[rows.count - 1]))
        return out
    }

    /// Rectangular rings from the outside in, `step` apart, each started at its lower-left corner and linked to the
    /// next by a diagonal through cut stock; a last pass along the middle when the rings leave a core wider than the
    /// tool. Led in by `lead` along the line of the first side.
    static func spiral(_ c: Rect2, step: Double, toolRadius r: Double, clockwise: Bool, lead: Double,
                       tolerance: Double) -> [Vec2] {
        var out: [Vec2] = []
        var k = 0.0
        while true {
            let l = c.min.x + k * step, b = c.min.y + k * step
            let w = max(0, c.width - 2 * k * step), h = max(0, c.height - 2 * k * step)
            let right = l + w, top = b + h
            if w <= 1e-9 || h <= 1e-9 {
                // A ring that has shrunk to a line (or a point).
                out += [Vec2(l, b), Vec2(right, top)]
            } else if clockwise {
                out += [Vec2(l, b), Vec2(l, top), Vec2(right, top), Vec2(right, b), Vec2(l, b)]
            } else {
                out += [Vec2(l, b), Vec2(right, b), Vec2(right, top), Vec2(l, top), Vec2(l, b)]
            }
            if min(w, h) >= 2 * step - 1e-9 {
                k += 1
                continue
            }
            if min(w, h) > 2 * r + tolerance {
                // The rings leave a core of stock more than a cutter wide: one pass down its middle.
                if w >= h {
                    out += [Vec2(l, b + h / 2), Vec2(right, b + h / 2)]
                } else {
                    out += [Vec2(l + w / 2, b), Vec2(l + w / 2, top)]
                }
            }
            break
        }
        let first = out[0]
        let toward = out.dropFirst().first { $0.distance(to: first) > 1e-9 }
        let direction = toward.map { ($0 - first) * (1 / $0.distance(to: first)) } ?? Vec2(1, 0)
        return [first - direction * lead] + out
    }

    // MARK: Wording

    private func surfaceNote(job: JobSetup, units: LengthUnit) -> String {
        let down = Self.fmt(params.depth.cutDepth, units)
        let left = job.thickness - params.depth.cutDepth
        let thickness = left > 0 ? " (\(Self.fmt(left, units)) thick there afterward)" : ""
        switch job.zZero {
        case .materialTop:
            return "Faces down to \(down) below the original top\(thickness). Later steps still measure depth from that "
                + "top, so touch off Z0 once, before this step, and do not re-zero after it."
        case .spoilboard:
            return "Faces down to \(down) below the original top\(thickness). Later steps measure from the spoilboard as usual."
        }
    }

    static func fmt(_ v: Double, _ units: LengthUnit) -> String {
        String(format: "%.4g", v) + " " + units.abbreviation
    }
}
