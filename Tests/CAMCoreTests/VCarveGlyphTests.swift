import CADCore
import Foundation
import Testing
@testable import CAMCore

/// V-carve against real letters. A glyph is carved correctly when
///  - the operation produces a cut,
///  - the cut reaches the whole glyph: at every point inside it the V-bit has taken out the depth the
///    outline allows there (distance to the nearest edge / tan(half angle)), to within a small fraction
///    of the letter's height, so no stroke, counter or serif is left uncarved, and
///  - the pieces of the cut that touch (a groove reaches the next one) form as many connected cuts as the
///    glyph has connected pieces: an O is one ring, not two unrelated circles.
/// Run for A-Z, a-z, 0-9 and & @ % in five fonts at three sizes.

private let glyphGroups: [[Character]] = ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", "0123456789&@%"].map(Array.init)
private let fonts = ["Times New Roman", "Helvetica", "Snell Roundhand", "Avenir Next Condensed", "Impact"]   // serif, sans, script, condensed, display
private let sizes = [0.25, 1.0, 2.0]                        // capital height, inches
private let slope = tan(30.0 * .pi / 180)                   // the 60 degree V-bit of VCarveFixture

/// One groove point: where the bit's axis passes and how wide the groove is there (depth x slope).
private struct Groove { var xy: Vec2; var radius: Double; var run: Int }

/// Cut points (xy, groove radius) of `tp` below the surface, densified to `step`; `run` numbers the runs of
/// cutting moves between rapids.
private func grooves(_ tp: Toolpath, coords: MachineCoordinates, step: Double) -> [Groove] {
    var out: [Groove] = []
    var run = 0
    var last: Vec3?
    var open = false
    for m in tp.moves {
        guard let t = m.target else { continue }
        defer { last = t }
        if m.isRapid { if open { run += 1; open = false }; continue }
        guard let a = last else { continue }
        let n = max(1, Int((a.xy.distance(to: t.xy) / step).rounded(.up)))
        for k in 0...n {
            let mat = coords.material(fromMachine: a + (t - a) * (Double(k) / Double(n)))
            if mat.depth > -1e-9 { out.append(Groove(xy: mat.xy, radius: max(0, mat.depth) * slope, run: run)) }
        }
        open = true
    }
    return out
}

/// Grooves bucketed on a grid for neighbour queries.
private struct GrooveGrid {
    let cell: Double
    var buckets: [Int64: [Int]] = [:]
    init(_ points: [Groove], cell: Double) {
        self.cell = cell
        for (i, g) in points.enumerated() { buckets[Self.key(g.xy, cell), default: []].append(i) }
    }

    static func key(_ p: Vec2, _ cell: Double) -> Int64 {
        Int64(Int(floor(p.x / cell))) &* 1_000_003 &+ Int64(Int(floor(p.y / cell)))
    }

    /// Visits the points whose cell lies within `r` of `p`, nearest cells first, until `visit` says stop.
    func forEachNear(_ p: Vec2, within r: Double, _ visit: (Int) -> Bool) {
        let span = Int(ceil(r / cell))
        let cx = Int(floor(p.x / cell)), cy = Int(floor(p.y / cell))
        for ring in 0...span {
            for ix in (cx - ring)...(cx + ring) {
                for iy in (cy - ring)...(cy + ring) where max(abs(ix - cx), abs(iy - cy)) == ring {
                    for i in buckets[Int64(ix) &* 1_000_003 &+ Int64(iy)] ?? [] where !visit(i) { return }
                }
            }
        }
    }
}

private struct Verdict {
    var cutLength = 0.0
    /// The most any interior point is short of the depth the outline allows, in inches of groove radius.
    var worstShortfall = 0.0
    var shortfallAt = Vec2.zero
    var cuts = 0
    var pieces = 0
}

/// How well `tp` carves the glyph `paths`.
private func judge(_ tp: Toolpath, paths: [Path], context: CAMContext, size: Double) -> Verdict {
    var v = Verdict()
    // The V-bit's radius is the widest groove it can cut; a warning says some stroke is wider.
    let reach = (tp.metadata["warning"] ?? "").contains("wider than the V-bit") ? 0.98 * VCarveFixture.vbit60.radius : .infinity
    let region = VCarveRegion(paths: paths, tolerance: context.tolerance, units: context.units)
    let g = grooves(tp, coords: context.coords, step: size * 0.01)
    for (a, b) in zip(g, g.dropFirst()) where a.run == b.run { v.cutLength += a.xy.distance(to: b.xy) }
    v.pieces = region.polygons.filter { Polygon2D.signedArea($0) > 0 }.count

    // Interior sample points and the distance from each to the outline.
    let grid = GrooveGrid(g, cell: size * 0.05)
    let bounds = region.bounds
    let h = size / 18
    let allowed = size * 0.02
    var y = bounds.min.y + h / 2
    while y < bounds.max.y {
        var x = bounds.min.x + h / 2
        while x < bounds.max.x {
            let q = Vec2(x, y)
            if region.contains(q) {
                let d = region.polygons.map { Polygon2D.distance(from: q, toLoop: $0) }.min() ?? 0
                // Skip the thin rim (the groove narrows to nothing at the edge) and, where the strokes are
                // wider than the bit (the operation says so), the part the bit cannot reach: it needs the
                // flat-area clearance the operation offers for that.
                if d > size * 0.02, d <= reach {
                    // The groove at s reaches q with r_s - |q - s| of its radius left; the outline allows d.
                    // Enough is a groove that leaves d less the allowed shortfall; stop looking once found.
                    var best = 0.0
                    let enough = d - allowed
                    grid.forEachNear(q, within: d + size * 0.3) { i in
                        best = max(best, g[i].radius - g[i].xy.distance(to: q))
                        return best < enough
                    }
                    if d - best > v.worstShortfall { v.worstShortfall = d - best; v.shortfallAt = q }
                }
            }
            x += h
        }
        y += h
    }

    // Connected cuts: the runs of cutting moves, joined where one run's groove reaches a groove of another
    // (a run starts at a junction of the skeleton, and at a thin neck the next groove just touches the first).
    let runIDs = Array(Set(g.map(\.run))).sorted()
    var byRun: [[Groove]] = runIDs.map { id in g.filter { $0.run == id } }
    byRun = byRun.filter { !$0.isEmpty }
    var parent = Array(byRun.indices)
    func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
    let boxes = byRun.map { run -> Rect2 in
        let reach = (run.map(\.radius).max() ?? 0) + size * 0.004
        return Rect2(points: run.map(\.xy)).insetBy(-reach)
    }
    let slack = size * 0.004
    for a in byRun.indices {
        for b in byRun.indices where b > a && find(a) != find(b) && boxes[a].intersects(boxes[b]) {
            search: for p in byRun[a] {
                for q in byRun[b] where p.xy.distance(to: q.xy) <= max(p.radius, q.radius) + slack {
                    parent[find(a)] = find(b)
                    break search
                }
            }
        }
    }
    v.cuts = Set(byRun.indices.map(find)).count
    return v
}

/// Glyph outlines, asked of CoreText one at a time: the font daemon answers each request over XPC and
/// stops answering when a dozen test threads ask at once.
private final class GlyphCache: @unchecked Sendable {
    static let shared = GlyphCache()
    private let lock = NSLock()
    private var store: [String: [Path]] = [:]
    private var missing: Set<String> = []

    /// The outlines of `text` at capital height `size` with the baseline origin at (1, 1); nil when the font is not installed.
    func outlines(_ text: String, font: String, size: Double) -> [Path]? {
        lock.lock(); defer { lock.unlock() }
        let key = "\(font)|\(size)|\(text)"
        if let hit = store[key] { return hit }
        if missing.contains(font) { return nil }
        guard let paths = try? TextOutliner().outlines(for: text, fontName: font, size: size, origin: Vec2(1, 1)) else {
            missing.insert(font)
            return nil
        }
        store[key] = paths
        return paths
    }
}

private func carve(_ ch: String, font: String, size: Double,
                   params: VCarveParameters = VCarveParameters()) throws -> (tp: Toolpath, paths: [Path], context: CAMContext)? {
    guard let paths = GlyphCache.shared.outlines(ch, font: font, size: size), !paths.isEmpty else { return nil }
    let (ctx, setup) = VCarveFixture.context(paths)
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    return (tps[0], paths, ctx)
}

private func installed(_ font: String) -> Bool { GlyphCache.shared.outlines("A", font: font, size: 1) != nil }

/// A size and a group of glyphs: the unit a test runs, so the work spreads over the cores.
struct VCarveGlyphCell: Sendable, CustomTestStringConvertible {
    var size: Double
    var group: Int
    var testDescription: String { "\(size) in, glyphs \(String(glyphGroups[group]))" }
}

let vcarveGlyphCells = sizes.flatMap { size in glyphGroups.indices.map { VCarveGlyphCell(size: size, group: $0) } }

@Test(arguments: fonts, vcarveGlyphCells)
func vcarveCarvesEveryGlyph(font: String, cell: VCarveGlyphCell) throws {
    guard installed(font) else { return }   // a machine without the font has nothing to carve
    let size = cell.size
    do {
        for ch in glyphGroups[cell.group] {
            let t0 = Date()
            guard let (tp, paths, ctx) = try carve(String(ch), font: font, size: size) else {
                Issue.record("\(font) \(ch) \(size): no outline"); continue
            }
            let t1 = Date()
            let v = judge(tp, paths: paths, context: ctx, size: size)
            _ = (t0, t1)
            let name = "\(font) '\(ch)' at \(size) in"
            #expect(v.cutLength > 0, Comment(rawValue: "\(name): no cut"))
            #expect(v.worstShortfall <= size * 0.02,
                    Comment(rawValue: "\(name): carve is \(v.worstShortfall) in short near \(v.shortfallAt)"))
            #expect(v.cuts == v.pieces, Comment(rawValue: "\(name): \(v.cuts) connected cut(s) for \(v.pieces) glyph piece(s)"))
        }
    }
}

private func permutations<T>(_ items: [T]) -> [[T]] {
    guard items.count > 1 else { return [items] }
    return items.indices.flatMap { i -> [[T]] in
        var rest = items
        let head = rest.remove(at: i)
        return permutations(rest).map { [head] + $0 }
    }
}

/// O, B and 8 have an outline and one or two counters. Each contour as a shape of its own, selected in every
/// order, with and without "start at the vectors' start points" and "in selection order": the carve is
/// the same whole letter, one connected cut, every time.
@Test(arguments: ["Times New Roman", "Helvetica"], ["O", "B", "8"])
func vcarveKeepsAMultiContourGlyphWholeInEveryOrder(font: String, glyph: String) throws {
    guard let paths = GlyphCache.shared.outlines(glyph, font: font, size: 1) else { return }
    #expect(paths.count >= 2, Comment(rawValue: "\(font) \(glyph) should have a counter"))
    for order in permutations(Array(paths.indices)) {
        for startPoints in [false, true] {
            for selectionOrder in [false, true] {
                var doc = Document()
                var ids: [UUID] = []
                for i in order {
                    let shape = Shape(layerID: doc.defaultLayerID, paths: [paths[i]])
                    doc.add(shape)
                    ids.append(shape.id)
                }
                let setup = OperationSetup(name: "V", toolID: VCarveFixture.vbit60.id, shapeIDs: ids)
                let ctx = CAMContext(document: doc, tools: .seeded)
                let params = VCarveParameters(useVectorStartPoints: startPoints, useSelectionOrder: selectionOrder)
                let tp = try #require(try VCarveOperation(setup: setup, params: params).generate(in: ctx).first)
                let v = judge(tp, paths: paths, context: ctx, size: 1)
                let name = "\(font) '\(glyph)' contours \(order) startPoints=\(startPoints) selectionOrder=\(selectionOrder)"
                #expect(v.cutLength > 0, Comment(rawValue: "\(name): no cut"))
                #expect(v.worstShortfall <= 0.02, Comment(rawValue: "\(name): carve is \(v.worstShortfall) in short near \(v.shortfallAt)"))
                #expect(v.cuts == 1 && v.pieces == 1, Comment(rawValue: "\(name): \(v.cuts) connected cut(s) for \(v.pieces) glyph piece(s)"))
            }
        }
    }
}
