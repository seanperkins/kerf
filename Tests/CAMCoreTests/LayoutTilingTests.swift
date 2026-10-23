import CADCore
import CAMCore
import Foundation
import Testing

@Suite struct LayoutTilingTests {
    let job = JobSetup(width: 120, height: 48, thickness: 0.75, xyOrigin: .lowerLeft, zZero: .materialTop, safeZ: 0.5)
    var coords: MachineCoordinates { MachineCoordinates(job: job) }
    let tool = ToolLibrary.seeded.tools.first { $0.kind == .endMill }!.converted(to: .inch)

    func line(_ a: Vec2, _ b: Vec2, depth: Double = 0.25) -> Toolpath {
        Toolpath(name: "L", kind: .profile, tool: tool, moves: [
            .rapid(to: coords.machineAtSafeZ(a)),
            .linear(to: coords.machine(a, depth: depth), feed: 30),
            .linear(to: coords.machine(b, depth: depth), feed: 150),
            .rapid(to: coords.machineAtSafeZ(b)),
        ])
    }

    /// Rapids never change XY below safe Z; programs end at safe Z.
    func checkSafe(_ tp: Toolpath, safe: Double) {
        var pos: Vec3?
        for m in tp.moves {
            if case .rapid(let p) = m, let s = pos, s.xy.distance(to: p.xy) > 1e-9 {
                #expect(min(s.z, p.z) >= safe - 1e-9)
            }
            pos = m.target ?? pos
        }
        #expect((pos?.z ?? 0) >= safe - 1e-9)
    }

    @Test func gridUsesEqualTilesWithOverlapOnSharedEdges() {
        let cells = ToolpathTiling.cells(job: job, settings: TilingSettings(tileWidth: 61, tileHeight: 96, overlap: 1))
        #expect(cells.count == 2)
        #expect(abs(cells[0].region.min.x) < 1e-9 && abs(cells[0].region.max.x - 60.5) < 1e-9)
        #expect(abs(cells[1].region.min.x - 59.5) < 1e-9 && abs(cells[1].region.max.x - 120) < 1e-9)
        #expect(cells[0].clip.min.x < -100 && cells[1].clip.max.x > 1000)
        #expect(ToolpathTiling.cells(job: job, settings: TilingSettings(tileWidth: 50, tileHeight: 30)).count == 3 * 2)
    }

    @Test func aCutAcrossTheSeamIsSplitAndReEntered() {
        let tiles = ToolpathTiling.tile([line(Vec2(10, 10), Vec2(110, 10))], job: job, units: .inch,
                                        settings: TilingSettings(tileWidth: 61, tileHeight: 96, overlap: 1))
        #expect(tiles.count == 2)
        for t in tiles {
            #expect(t.toolpaths.count == 1)
            let tp = t.toolpaths[0]
            checkSafe(tp, safe: MachineCoordinates(job: t.job).safeZ)
            let b = tp.xyBounds
            #expect(b.min.x >= -1e-6 && b.max.x <= t.region.width + 1e-6)
            #expect(abs((tp.minZ ?? 0) + 0.25) < 1e-9)
        }
        // Tile 2 is zeroed at x = 59.5 on the material: the cut ends at 110 - 59.5.
        #expect(abs(tiles[1].toolpaths[0].xyBounds.max.x - 50.5) < 1e-6)
        #expect(abs(tiles[0].toolpaths[0].xyBounds.max.x - 60.5) < 1e-6)
        #expect(tiles[1].job.width == 60.5 && tiles[1].job.xyOrigin == .lowerLeft)
        // The re-entry plunges at the plunge rate (never a rapid into the material).
        let plunge = tool.plungeRate
        #expect(tiles[1].toolpaths[0].moves.contains { if case .linear(_, let f) = $0 { return f == plunge } else { return false } })
    }

    @Test func toolpathsOutsideATileAreLeftOut() {
        let tiles = ToolpathTiling.tile([line(Vec2(5, 5), Vec2(20, 5))], job: job, units: .inch,
                                        settings: TilingSettings(tileWidth: 60, tileHeight: 96))
        #expect(tiles[0].toolpaths.count == 1)
        #expect(tiles[1].toolpaths.isEmpty)
    }

    @Test func arcsInsideATileStayArcs() {
        let c = Vec2(80, 20)
        let a = Vec2(85, 20), b = Vec2(75, 20)
        let tp = Toolpath(name: "A", kind: .profile, tool: tool, moves: [
            .rapid(to: coords.machineAtSafeZ(a)),
            .linear(to: coords.machine(a, depth: 0.1), feed: 30),
            .arcCCW(to: coords.machine(b, depth: 0.1), center: coords.machineXY(c), feed: 100),
            .rapid(to: coords.machineAtSafeZ(b)),
        ])
        let tiles = ToolpathTiling.tile([tp], job: job, units: .inch, settings: TilingSettings(tileWidth: 60, tileHeight: 96))
        let arcs = tiles[1].toolpaths[0].moves.compactMap { m -> Vec2? in
            if case .arcCCW(_, let cc, _) = m { return cc } else { return nil }
        }
        #expect(arcs.count == 1)
        #expect(arcs[0].distance(to: Vec2(20, 20)) < 1e-9)
    }

    @Test func anArcAcrossTheSeamIsSplitIntoLines() {
        let c = Vec2(60, 20)
        let a = Vec2(65, 20), b = Vec2(55, 20)
        let tp = Toolpath(name: "A", kind: .profile, tool: tool, moves: [
            .rapid(to: coords.machineAtSafeZ(a)),
            .linear(to: coords.machine(a, depth: 0.1), feed: 30),
            .arcCCW(to: coords.machine(b, depth: 0.1), center: coords.machineXY(c), feed: 100),
            .rapid(to: coords.machineAtSafeZ(b)),
        ])
        let tiles = ToolpathTiling.tile([tp], job: job, units: .inch, settings: TilingSettings(tileWidth: 60, tileHeight: 96))
        #expect(tiles.allSatisfy { $0.toolpaths.count == 1 })
        for t in tiles {
            checkSafe(t.toolpaths[0], safe: MachineCoordinates(job: t.job).safeZ)
            let b = t.toolpaths[0].xyBounds
            #expect(b.min.x >= -1e-6 && b.max.x <= t.region.width + 1e-6)
        }
    }
}

/// Issue #96. "Largest tile" is what the machine can reach, and a tile's region includes the overlap into its
/// neighbours, so the grid has to leave room for it: the tile count used to ignore the overlap, and a 120 in job on a
/// 60 in machine got 60.5 in tiles that the export then refused for exceeding the travel.
@Test(arguments: [
    (120.0, 60.0, 1.0, 3), (120.0, 60.0, 4.0, 3), (100.0, 60.0, 10.0, 2), (48.0, 60.0, 5.0, 1),
    (96.0, 48.0, 2.0, 3), (200.0, 60.0, 0.0, 4), (120.0, 60.0, 0.0, 2),
])
func tilesWithOverlapNeverExceedTheLargestTile(width: Double, tile: Double, overlap: Double, count: Int) {
    for horizontal in [true, false] {
        let job = horizontal ? JobSetup(width: width, height: 10, thickness: 0.75)
                             : JobSetup(width: 10, height: width, thickness: 0.75)
        let settings = horizontal ? TilingSettings(tileWidth: tile, tileHeight: 96, overlap: overlap)
                                  : TilingSettings(tileWidth: 96, tileHeight: tile, overlap: overlap)
        let cells = ToolpathTiling.cells(job: job, settings: settings)
        #expect(cells.count == count)
        let extent: (Cell) -> (Double, Double) = { c in
            horizontal ? (c.region.min.x, c.region.max.x) : (c.region.min.y, c.region.max.y)
        }
        let sorted = cells.sorted { extent($0).0 < extent($1).0 }
        for c in sorted { #expect(extent(c).1 - extent(c).0 <= tile + 1e-9, "a \(extent(c).1 - extent(c).0) in tile on a \(tile) in machine") }
        #expect(abs(extent(sorted.first!).0) < 1e-9 && abs(extent(sorted.last!).1 - width) < 1e-9)
        // Neighbours share a band of exactly the overlap, so the seam is cut by both.
        for (a, b) in zip(sorted, sorted.dropFirst()) { #expect(abs((extent(a).1 - extent(b).0) - overlap) < 1e-9) }
    }
}

private typealias Cell = ToolpathTiling.Cell
