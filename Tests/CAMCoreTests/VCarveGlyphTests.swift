import CADCore
import Foundation
import Testing
@testable import CAMCore

/// V-carve against real letters. A glyph is carved correctly when
///  - the operation produces a cut, and every piece of the letter (the dot of an i, the two halves of a %)
///    has some of it in it,
///  - the cut reaches the whole glyph: at every point inside it the V-bit has taken out the depth the outline
///    allows there (the distance to the nearest edge, up to the bit's own radius) to within a small fraction
///    of the letter's height, and every point of the outline lies within reach of a groove, so no stroke,
///    counter or serif is left uncarved, and
///  - the runs of the cut that touch (one groove reaches the other's axis) form as many connected cuts as the
///    glyph has connected pieces: an O is one ring, not two unrelated circles.
/// The expected letter is worked out from the font's own outlines, not from the region the operation builds.
/// Run for A-Z, a-z, 0-9 and & @ % in five fonts at three sizes.

private let glyphGroups: [[Character]] = ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", "0123456789&@%"].map(Array.init)
private let fonts = ["Times New Roman", "Helvetica", "Snell Roundhand", "Avenir Next Condensed", "Impact"]   // serif, sans, script, condensed, display
private let sizes = [0.25, 1.0, 2.0]                        // capital height, inches
private let slope = tan(30.0 * .pi / 180)                   // the 60 degree V-bit of VCarveFixture

/// One groove point: where the bit's axis passes and how wide the groove is there (depth x slope).
private struct Groove { var xy: Vec2; var radius: Double; var run: Int }

/// Cut points (xy, groove radius) of `tp` at or below the surface, densified to `step`; `run` numbers the
/// runs of cutting moves between rapids.
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

/// Grooves bucketed on a grid: a covered point finds its groove in the first few buckets. A plain scan of
/// every groove for every sample costs minutes in a debug build over the whole matrix.
private struct GrooveGrid {
    let cell: Double
    var buckets: [Int64: [Int]] = [:]

    init(_ points: [Groove], cell: Double) {
        self.cell = cell
        for (i, g) in points.enumerated() { buckets[Self.key(Int(floor(g.xy.x / cell)), Int(floor(g.xy.y / cell))), default: []].append(i) }
    }

    static func key(_ ix: Int, _ iy: Int) -> Int64 { Int64(ix) &* 1_000_003 &+ Int64(iy) }

    /// Visits the points whose cell lies within `r` of `p`, nearest cells first, until `visit` returns false.
    func forEachNear(_ p: Vec2, within r: Double, _ visit: (Int) -> Bool) {
        let span = Int(ceil(r / cell))
        let cx = Int(floor(p.x / cell)), cy = Int(floor(p.y / cell))
        for ring in 0...span {
            for ix in (cx - ring)...(cx + ring) {
                for iy in (cy - ring)...(cy + ring) where max(abs(ix - cx), abs(iy - cy)) == ring {
                    for i in buckets[Self.key(ix, iy)] ?? [] {
                        if !visit(i) { return }
                    }
                }
            }
        }
    }
}

private struct Verdict {
    var cutLength = 0.0
    /// The most any interior point is short of the depth the outline allows there, in inches of groove radius.
    var worstShortfall = 0.0
    var shortfallAt = Vec2.zero
    /// The farthest any point of the outline is from every groove's edge.
    var worstOutlineGap = 0.0
    var cuts = 0
    var pieces = 0
    /// Pieces of the glyph with no cut in them.
    var uncutPieces = 0
}

/// How well `tp` carves the glyph `paths`.
private func judge(_ tp: Toolpath, paths: [Path], context: CAMContext, size: Double) -> Verdict {
    var v = Verdict()
    // The letter from the font's contours alone (outer loops counter-clockwise, counters and islands
    // alternating inside them), not from the region the operation builds from them.
    let region = Polygon2D.region(fromLoops: paths.map { $0.flattened(tolerance: context.tolerance) }.filter { $0.count > 2 })
    func inside(_ p: Vec2) -> Bool { region.reduce(0) { $0 + (Polygon2D.contains($1, p) ? 1 : 0) } % 2 == 1 }
    func outlineDistance(_ p: Vec2) -> Double { region.map { Polygon2D.distance(from: p, toLoop: $0) }.min() ?? 0 }
    let outers = region.filter { Polygon2D.signedArea($0) > 0 }
    v.pieces = outers.count

    let g = grooves(tp, coords: context.coords, step: size * 0.01)
    for (a, b) in zip(g, g.dropFirst()) where a.run == b.run { v.cutLength += a.xy.distance(to: b.xy) }
    v.uncutPieces = outers.filter { outer in !g.contains { $0.radius > 0 && Polygon2D.contains(outer, $0.xy) } }.count

    let grid = GrooveGrid(g, cell: size * 0.05)
    let bitRadius = VCarveFixture.vbit60.radius
    let allowed = size * 0.02

    // Interior: at q the outline allows a groove of radius min(d, bit radius) (a stroke wider than the bit is
    // cleared flat at the bit's full depth); the groove at s leaves r_s - |q - s| of its radius at q.
    let bounds = Rect2(points: region.flatMap { $0 })
    let h = size / 18
    var y = bounds.min.y + h / 2
    while y < bounds.max.y {
        var x = bounds.min.x + h / 2
        while x < bounds.max.x {
            let q = Vec2(x, y)
            if inside(q) {
                // The thin rim is skipped (the groove narrows to nothing at the edge); the outline check
                // below covers it.
                let d = outlineDistance(q)
                if d > size * 0.02 {
                    let want = min(d, bitRadius)
                    var best = 0.0
                    grid.forEachNear(q, within: want + size * 0.3) { i in
                        best = max(best, g[i].radius - g[i].xy.distance(to: q))
                        return best < want - allowed   // enough: stop looking
                    }
                    if want - best > v.worstShortfall { v.worstShortfall = want - best; v.shortfallAt = q }
                }
            }
            x += h
        }
        y += h
    }

    // Outline: every point of every contour is within reach of some groove (its edge touches or passes it),
    // which also sees a thin stroke or serif the interior grid steps over.
    let step = size / 60
    for loop in region {
        var carried = 0.0
        for i in loop.indices {
            let a = loop[i], b = loop[(i + 1) % loop.count]
            let len = a.distance(to: b)
            var t = carried
            while t < len {
                let p = a.lerp(to: b, t / len)
                var gap = Double.infinity
                grid.forEachNear(p, within: size * 0.3) { j in
                    gap = min(gap, g[j].xy.distance(to: p) - g[j].radius)
                    return gap > size * 0.015   // reached: stop looking
                }
                v.worstOutlineGap = max(v.worstOutlineGap, gap)
                t += step
            }
            carried = t - len
        }
    }

    // Connected cuts: the runs of cutting moves, joined where one run's groove reaches the axis of another's
    // (a run starts at a junction of the skeleton, and at a reflex corner of a letter the next groove just
    // touches the first). This is stricter than two grooves overlapping, which two unrelated strokes close
    // together also do.
    var byRun: [[Groove]] = Array(Set(g.map(\.run))).sorted().map { id in g.filter { $0.run == id } }
    byRun = byRun.filter { !$0.isEmpty }
    var parent = Array(byRun.indices)
    func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
    let slack = size * 0.004
    let boxes = byRun.map { run in Rect2(points: run.map(\.xy)).insetBy(-((run.map(\.radius).max() ?? 0) + slack)) }
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
/// stops answering when a dozen test threads ask at once. nil when the font is not installed.
private let fontLock = NSLock()
private func glyphOutlines(_ text: String, font: String, size: Double) -> [Path]? {
    fontLock.withLock { try? TextOutliner().outlines(for: text, fontName: font, size: size, origin: Vec2(1, 1)) }
}

/// The glyph carved with the 60 degree V-bit, with its outlines and context.
private func carve(_ paths: [Path], shapesApart: [Int]? = nil, params: VCarveParameters = VCarveParameters()) throws
    -> (tp: Toolpath, context: CAMContext) {
    var doc = Document()
    var ids: [UUID] = []
    if let order = shapesApart {
        // Each contour a shape of its own, selected in this order.
        for i in order {
            let shape = Shape(layerID: doc.defaultLayerID, paths: [paths[i]])
            doc.add(shape); ids.append(shape.id)
        }
    } else {
        let shape = Shape(layerID: doc.defaultLayerID, paths: paths)
        doc.add(shape); ids.append(shape.id)
    }
    let context = CAMContext(document: doc, tools: .seeded)
    let setup = OperationSetup(name: "V", toolID: VCarveFixture.vbit60.id, shapeIDs: ids)
    return (try #require(try VCarveOperation(setup: setup, params: params).generate(in: context).first), context)
}

/// A size and a group of glyphs: the unit a test runs, so the work spreads over the cores.
struct VCarveGlyphCell: Sendable, CustomTestStringConvertible {
    var size: Double
    var group: Int
    var testDescription: String { "\(size) in, glyphs \(String(glyphGroups[group]))" }
}

let vcarveGlyphCells = sizes.flatMap { size in glyphGroups.indices.map { VCarveGlyphCell(size: size, group: $0) } }

/// The fonts ship with macOS; a machine that lacks them would otherwise pass by carving nothing.
@Test func vcarveGlyphFontsAreInstalled() {
    let present = fonts.filter { glyphOutlines("A", font: $0, size: 1) != nil }
    #expect(present.count >= 4, Comment(rawValue: "only \(present) of \(fonts) are installed"))
}

@Test(arguments: fonts, vcarveGlyphCells)
func vcarveCarvesEveryGlyph(font: String, cell: VCarveGlyphCell) throws {
    guard glyphOutlines("A", font: font, size: 1) != nil else { return }   // not installed: vcarveGlyphFontsAreInstalled decides
    for ch in glyphGroups[cell.group] {
        let name = "\(font) '\(ch)' at \(cell.size) in"
        guard let paths = glyphOutlines(String(ch), font: font, size: cell.size), !paths.isEmpty else {
            Issue.record(Comment(rawValue: "\(name): no outline")); continue
        }
        let (tp, context) = try carve(paths)
        let v = judge(tp, paths: paths, context: context, size: cell.size)
        #expect(v.cutLength > 0, Comment(rawValue: "\(name): no cut"))
        #expect(v.uncutPieces == 0, Comment(rawValue: "\(name): \(v.uncutPieces) of \(v.pieces) glyph piece(s) have no cut in them"))
        #expect(v.worstShortfall <= cell.size * 0.02,
                Comment(rawValue: "\(name): carve is \(v.worstShortfall) in short near \(v.shortfallAt)"))
        #expect(v.worstOutlineGap <= cell.size * 0.015, Comment(rawValue: "\(name): an outline point is \(v.worstOutlineGap) in from every groove"))
        #expect(v.cuts == v.pieces, Comment(rawValue: "\(name): \(v.cuts) connected cut(s) for \(v.pieces) glyph piece(s)"))
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
    guard let paths = glyphOutlines(glyph, font: font, size: 1) else { return }
    #expect(paths.count >= 2, Comment(rawValue: "\(font) \(glyph) should have a counter"))
    for order in permutations(Array(paths.indices)) {
        for startPoints in [false, true] {
            for selectionOrder in [false, true] {
                let params = VCarveParameters(useVectorStartPoints: startPoints, useSelectionOrder: selectionOrder)
                let (tp, context) = try carve(paths, shapesApart: order, params: params)
                let v = judge(tp, paths: paths, context: context, size: 1)
                let name = "\(font) '\(glyph)' contours \(order) startPoints=\(startPoints) selectionOrder=\(selectionOrder)"
                #expect(v.cutLength > 0, Comment(rawValue: "\(name): no cut"))
                #expect(v.worstShortfall <= 0.02, Comment(rawValue: "\(name): carve is \(v.worstShortfall) in short near \(v.shortfallAt)"))
                #expect(v.worstOutlineGap <= 0.015, Comment(rawValue: "\(name): an outline point is \(v.worstOutlineGap) in from every groove"))
                #expect(v.cuts == 1 && v.pieces == 1, Comment(rawValue: "\(name): \(v.cuts) connected cut(s) for \(v.pieces) glyph piece(s)"))
            }
        }
    }
}
