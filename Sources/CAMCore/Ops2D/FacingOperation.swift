import CADCore
import Foundation

/// Facing (surfacing): takes a layer off the top of a rectangle, the bounding box of the selected vectors or the
/// whole material. The tool's center covers the area grown by (overhang − tool radius), so with the default overhang
/// it rides the area's edge and the cutter's edge reaches a radius past it; the first pass is led in from a point
/// where the cutter is clear of the area, instead of plunging into the surface, and the last cut runs out the same way.
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
    /// Widest the rings of a spiral are kept apart, as a fraction of the diameter. At an outside corner of the inner ring the
    /// round footprint leaves a spot 0.586 × the spacing from the nearest cut, so the spacing may be at most a radius
    /// over 0.586 (1.707 radii, 85.4% of a diameter); parallel raster passes have no such corner and go to `maxStepover`.
    public static let maxSpiralStepover = 0.85
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
        guard params.depth.startDepth.isFinite, params.depth.cutDepth.isFinite,
              (params.depth.cutDepth - params.depth.startDepth).isFinite else {
            throw CAMError.invalidParameter("Depths must be numbers")
        }
        try params.depth.validatePassDepth(toolStepdown: tool.stepdown)
        let passes = params.depth.passDepths(toolStepdown: tool.stepdown)
        guard !passes.isEmpty else { throw CAMError.invalidParameter("Cut depth must be deeper than start depth") }
        // A computed list is capped by the helper; a hand-edited custom list is not.
        guard passes.count <= DepthSettings.maxComputedPasses else {
            throw CAMError.invalidParameter("Too many depth passes: at most \(DepthSettings.maxComputedPasses)")
        }

        let tol = context.tolerance
        let units = context.units
        let area = try facedArea(in: context)
        // Finite edges can still be a span that overflows (-1e308 to 1e308).
        guard [area.min.x, area.min.y, area.max.x, area.max.y, area.width, area.height].allSatisfy(\.isFinite) else {
            throw CAMError.invalidGeometry("The area to face is not a finite size")
        }
        guard area.width > tol, area.height > tol else {
            throw CAMError.invalidGeometry("The area to face has no width or no height")
        }
        let r = tool.radius
        let overhang = params.overhang ?? r
        let step = tool.diameter * params.stepover
        let centre = Self.centreRect(area: area, toolRadius: r, overhang: overhang)

        var warnings: [String] = []
        // One layer of the pattern at a depth, as tool-center points; the same XY every layer.
        let flat: [Vec2]
        switch params.pattern {
        case .rasterX, .rasterY:
            let alongX = params.pattern == .rasterX
            let (lo, hi) = alongX ? (centre.min.y, centre.max.y) : (centre.min.x, centre.max.x)
            guard let rows = Self.positions(from: lo, to: hi, step: step, limit: Self.maxRows) else {
                throw CAMError.invalidParameter("Too many passes across the area: raise the stepover")
            }
            flat = Self.raster(centre, rows: rows, alongX: alongX, area: area, toolRadius: r)
        case .spiral:
            let ringStep = min(step, Self.maxSpiralStepover * tool.diameter)
            if ringStep < step { warnings.append("the spiral keeps its rings \(Int(Self.maxSpiralStepover * 100))% of the tool apart at most: any more would leave the corners between them uncut") }
            let size = min(centre.width, centre.height)
            guard size / ringStep <= Double(2 * Self.maxRows) else {
                throw CAMError.invalidParameter("Too many passes across the area: raise the stepover")
            }
            flat = Self.spiral(centre, step: ringStep, toolRadius: r, clockwise: params.direction == .climb, area: area,
                               tolerance: tol)
        }
        guard flat.count > 1 else { throw CAMError.invalidGeometry("The area to face leaves nothing to cut") }
        guard flat.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw CAMError.invalidGeometry("The area to face is too large")
        }
        // The lead-in (and a raster's lead-out) must really put the cutter clear of the area: far from the origin a lead
        // of a tool radius can round away to nothing.
        let leads = params.pattern == .spiral ? [flat[0]] : [flat[0], flat[flat.count - 1]]
        guard leads.allSatisfy({ Self.isClear($0, of: area, toolRadius: r, tolerance: tol) }) else {
            throw CAMError.invalidGeometry("The area to face is too far from the origin to lead the tool in")
        }
        guard flat.count * passes.count <= Self.maxPoints else {
            throw CAMError.invalidParameter("Too many passes: raise the stepover or the depth per pass")
        }

        var builder = ToolpathBuilder(coords: context.coords, tool: tool, units: units, tolerance: tol, fitArcs: false)
        for (k, d) in passes.enumerated() {
            builder.cutChain(flat.map { CutPoint($0, depth: d) }, clearedDepth: k == 0 ? 0 : passes[k - 1])
        }

        var meta = ["area": "\(Self.fmt(area.width, units)) × \(Self.fmt(area.height, units))",
                    "note": surfaceNote(job: context.document.job, units: units)]
        if Self.leavesRoundedCorners(area: area, centre: centre, toolRadius: r, tolerance: tol) {
            warnings.append("the overhang is too small to reach the corners of the area: they are left rounded")
        }
        if Self.reachesBeyondArea(area: area, overhang: overhang, toolRadius: r, job: context.document.job, tolerance: tol) {
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

    /// True when the cutter (with its lead-in and lead-out) can touch material outside the area. The cutter's edge goes
    /// `overhang` past the area; a lead-in or lead-out puts the center a radius or more outside it (as far as the
    /// overhang takes it, never less), so its far edge is a radius further. `r + max(overhang, r)` on every side
    /// bounds every pattern.
    static func reachesBeyondArea(area: Rect2, overhang: Double, toolRadius r: Double, job: JobSetup,
                                  tolerance: Double) -> Bool {
        func clipped(_ a: Rect2) -> Rect2 {
            let m = job.materialBounds
            return Rect2(min: Vec2(max(a.min.x, m.min.x), max(a.min.y, m.min.y)),
                         max: Vec2(min(a.max.x, m.max.x), min(a.max.y, m.max.y)))
        }
        let out = r + max(overhang, r)
        let reach = clipped(Rect2(min: area.min - Vec2(out, out), max: area.max + Vec2(out, out)))
        guard !reach.isEmpty else { return false }
        let faced = clipped(area)
        if faced.isEmpty { return true }
        return reach.min.x < faced.min.x - tolerance || reach.min.y < faced.min.y - tolerance
            || reach.max.x > faced.max.x + tolerance || reach.max.y > faced.max.y + tolerance
    }

    /// Whether a cutter centered at `p` touches none of `area`.
    static func isClear(_ p: Vec2, of area: Rect2, toolRadius r: Double, tolerance: Double) -> Bool {
        // Differences, not `area.min.x - r` compared with `p.x`: far from the origin both would round to the same number.
        area.min.x - p.x >= r - tolerance || p.x - area.max.x >= r - tolerance
            || area.min.y - p.y >= r - tolerance || p.y - area.max.y >= r - tolerance
    }

    /// How far to lead from `p` along the axis direction `dir` (a unit vector) before the cutter is clear of `area`: a
    /// tool radius at least, and as far as it takes for the center to be a radius outside the area, so the cutter touches
    /// none of it however small the overhang.
    static func leadLength(from p: Vec2, toward dir: Vec2, clearOf area: Rect2, toolRadius r: Double) -> Double {
        let needed: Double
        if dir.x > 0.5 { needed = area.max.x + r - p.x }
        else if dir.x < -0.5 { needed = p.x - (area.min.x - r) }
        else if dir.y > 0.5 { needed = area.max.y + r - p.y }
        else { needed = p.y - (area.min.y - r) }
        return max(r, needed)
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
    /// joined at the ends (where the cutter has already been). Led in before the first cut and out after the last, each
    /// clear of `area` by a tool radius.
    static func raster(_ c: Rect2, rows: [Double], alongX: Bool, area: Rect2, toolRadius r: Double) -> [Vec2] {
        let (uLo, uHi) = alongX ? (c.min.x, c.max.x) : (c.min.y, c.max.y)
        func point(_ u: Double, _ v: Double) -> Vec2 { alongX ? Vec2(u, v) : Vec2(v, u) }
        func axis(_ sign: Double) -> Vec2 { alongX ? Vec2(sign, 0) : Vec2(0, sign) }
        let entry = point(uLo, rows[0])
        var out: [Vec2] = [entry + axis(-1) * leadLength(from: entry, toward: axis(-1), clearOf: area, toolRadius: r)]
        for (j, v) in rows.enumerated() {
            let forward = j % 2 == 0
            out.append(point(forward ? uLo : uHi, v))
            out.append(point(forward ? uHi : uLo, v))
        }
        let forward = (rows.count - 1) % 2 == 0
        let exit = point(forward ? uHi : uLo, rows[rows.count - 1])
        let away = axis(forward ? 1 : -1)
        out.append(exit + away * leadLength(from: exit, toward: away, clearOf: area, toolRadius: r))
        return out
    }

    /// Rectangular rings from the outside in, `step` apart, each started at its lower-left corner and linked to the
    /// next by a diagonal through cut stock; a last pass along the middle when the rings leave a core wider than the
    /// tool. Led in along the line of the first side from a point a tool radius clear of `area`. The rings are at most
    /// `size / (2 × step)` of them (the caller bounds that), five points each.
    static func spiral(_ c: Rect2, step: Double, toolRadius r: Double, clockwise: Bool, area: Rect2,
                       tolerance: Double) -> [Vec2] {
        var out: [Vec2] = []
        var k = 0.0
        // The caller bounds the rings; the loop is bounded here as well, whatever the arithmetic does.
        while k <= Double(Self.maxRows) {
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
        // The first side is along an axis (a ring's side, or a ring shrunk to a line): its direction without a length,
        // so nothing overflows however large the area.
        let toward = out.dropFirst().first { max(abs($0.x - first.x), abs($0.y - first.y)) > 1e-9 }
        let direction: Vec2 = toward.map { t in
            abs(t.x - first.x) >= abs(t.y - first.y) ? Vec2(t.x > first.x ? 1 : -1, 0) : Vec2(0, t.y > first.y ? 1 : -1)
        } ?? Vec2(1, 0)
        let lead = leadLength(from: first, toward: direction * -1, clearOf: area, toolRadius: r)
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
