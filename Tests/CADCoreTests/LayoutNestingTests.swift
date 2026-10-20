import CADCore
import Foundation
import Testing

/// Coarse grid keeps the debug-build tests quick.
private let fast = 40_000

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [Vec2] {
    [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)]
}

private func placed(_ part: NestPart, _ p: NestPlacement) -> [[Vec2]] {
    part.outline.map { $0.map(p.transform.apply) }
}

/// Area of overlap between two parts each grown by `gap / 2` (0 when they are `gap` apart).
private func overlapArea(_ a: [[Vec2]], _ b: [[Vec2]], gap: Double) -> Double {
    func grow(_ p: [[Vec2]]) -> [[Vec2]] {
        GeomKernel.offset(GeomKernel.boolean(.union, subject: p, clip: [], fillRule: .evenOdd), by: gap / 2 * 0.999)
    }
    let ga = grow(a), gb = grow(b)
    return GeomKernel.boolean(.intersection, subject: ga, clip: gb).reduce(0) { $0 + abs(PathGeometry.area($1)) }
}

/// Checks margins and spacing of every placement of one sheet.
private func checkLayout(_ parts: [NestPart], _ r: NestResult, _ s: NestSettings) {
    for sheet in 0..<max(r.sheetsUsed, 1) {
        let on = r.placements.filter { $0.sheet == sheet }
        let outlines = on.map { placed(parts[$0.part], $0) }
        for o in outlines {
            let b = Rect2(points: o.joined())
            #expect(b.min.x >= s.margin - 1e-6 && b.min.y >= s.margin - 1e-6)
            #expect(b.max.x <= s.sheetWidth - s.margin + 1e-6 && b.max.y <= s.sheetHeight - s.margin + 1e-6)
        }
        for i in outlines.indices {
            for j in outlines.indices where j > i {
                #expect(overlapArea(outlines[i], outlines[j], gap: s.spacing) < 1e-6)
            }
        }
    }
}

@Suite struct LayoutNestingTests {
    @Test func packsRectanglesWithSpacingAndMargin() {
        let parts = [NestPart(outline: [rect(100, 100, 10, 10)], quantity: 4)]
        let s = NestSettings(sheetWidth: 24, sheetHeight: 24, margin: 0.5, spacing: 0.5, precision: fast)
        let r = Nester.nest(parts, settings: s)
        #expect(r.placements.count == 4)
        #expect(r.unplacedCount == 0)
        #expect(r.sheetsUsed == 1)
        checkLayout(parts, r, s)
        // Bottom-left first: the first copy sits at the margin corner (within one grid cell).
        let first = Rect2(points: placed(parts[0], r.placements[0]).joined())
        #expect(first.min.x < 0.5 + s.resolvedCellSize + 1e-9)
        #expect(first.min.y < 0.5 + s.resolvedCellSize + 1e-9)
    }

    @Test func rotatesALongPartToFit() {
        let parts = [NestPart(outline: [rect(0, 0, 20, 2)])]
        let fixed = Nester.nest(parts, settings: NestSettings(sheetWidth: 4, sheetHeight: 22, margin: 0.25,
                                                              spacing: 0.25, rotationStep: 0, precision: fast))
        #expect(fixed.placements.isEmpty)
        #expect(fixed.unplaced[0] == 1)
        let s = NestSettings(sheetWidth: 4, sheetHeight: 22, margin: 0.25, spacing: 0.25, rotationStep: 90, precision: fast)
        let r = Nester.nest(parts, settings: s)
        #expect(r.placements.count == 1)
        #expect([90.0, 270.0].contains(r.placements[0].rotation))
        checkLayout(parts, r, s)
    }

    @Test func trianglesInterlockWhereBoundingBoxesCannot() {
        // Two right triangles with 10" legs only fit an 11" square when one is turned 180°.
        let tri: [Vec2] = [Vec2(0, 0), Vec2(10, 0), Vec2(0, 10)]
        let parts = [NestPart(outline: [tri], quantity: 2)]
        let s = NestSettings(sheetWidth: 11, sheetHeight: 11, margin: 0, spacing: 0.1, rotationStep: 90)
        let r = Nester.nest(parts, settings: s)
        #expect(r.placements.count == 2)
        checkLayout(parts, r, s)
    }

    @Test func extraCopiesOverflowOntoMoreSheets() {
        let parts = [NestPart(outline: [rect(0, 0, 10, 10)], quantity: 10)]
        var s = NestSettings(sheetWidth: 24, sheetHeight: 24, margin: 0.5, spacing: 0.5, precision: fast)
        let one = Nester.nest(parts, settings: s)
        #expect(one.placements.count == 4)
        #expect(one.unplacedCount == 6)
        s.maxSheets = 5
        let many = Nester.nest(parts, settings: s)
        #expect(many.placements.count == 10)
        #expect(many.sheetsUsed == 3)
        #expect(many.utilisation.count == 3)
        checkLayout(parts, many, s)
    }

    @Test func partsLargerThanTheSheetNeverOpenSheets() {
        let parts = [NestPart(outline: [rect(0, 0, 30, 30)])]
        let r = Nester.nest(parts, settings: NestSettings(sheetWidth: 24, sheetHeight: 24, maxSheets: 4))
        #expect(r.placements.isEmpty)
        #expect(r.sheetsUsed == 0)
        #expect(r.unplaced[0] == 1)
    }

    @Test func smallPartsGoIntoHolesOnlyWhenAllowed() {
        let frame = NestPart(outline: [rect(0, 0, 20, 20), rect(2, 2, 16, 16)])
        let small = NestPart(outline: [rect(0, 0, 4, 4)])
        var s = NestSettings(sheetWidth: 20.5, sheetHeight: 20.5, margin: 0, spacing: 0.25, precision: fast)
        let r = Nester.nest([frame, small], settings: s)
        #expect(r.placements.count == 2)
        checkLayout([frame, small], r, s)
        s.nestInHoles = false
        let blocked = Nester.nest([frame, small], settings: s)
        #expect(blocked.placements.count == 1)
        #expect(blocked.unplaced[1] == 1)
    }

    @Test func keepsClearOfObstacles() {
        let parts = [NestPart(outline: [rect(0, 0, 5, 5)])]
        let s = NestSettings(sheetWidth: 12, sheetHeight: 6, margin: 0, spacing: 0.5, precision: fast)
        let r = Nester.nest(parts, settings: s, firstSheetObstacles: [rect(0, 0, 6, 6)])
        #expect(r.placements.count == 1)
        let b = Rect2(points: placed(parts[0], r.placements[0]).joined())
        #expect(b.min.x >= 6.5 - 1e-6)
    }

    @Test func partBuilderKeepsFeaturesWithTheirPart() {
        let layer = UUID()
        let plate = Shape(name: "plate", layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 10, height: 6))])
        let hole = Shape(name: "hole", layerID: layer, paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: 1)])
        let slot = Shape(name: "slot", layerID: layer, paths: [Path(points: [Vec2(6, 2), Vec2(8, 2)], closed: false)])
        let other = Shape(name: "other", layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: 20, y: 0, width: 4, height: 4))])
        let g = UUID()
        var a = Shape(name: "a", layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: 30, y: 0, width: 1, height: 1))])
        var b = Shape(name: "b", layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: 33, y: 0, width: 1, height: 1))])
        a.groupID = g; b.groupID = g
        let parts = NestPartBuilder.parts(from: [hole, plate, slot, other, a, b])
        #expect(parts.count == 3)
        let plateParts = parts.first { $0.shapeIDs.contains(plate.id) }
        #expect(Set(plateParts?.shapeIDs ?? []) == [plate.id, hole.id, slot.id])
        #expect(parts.contains { Set($0.shapeIDs) == [a.id, b.id] })
        // The plate's outline is the plate, not the hole.
        let area = plateParts.map { NestPart(outline: $0.outline).area } ?? 0
        #expect(abs(area - 60) < 1e-6)
    }
}
