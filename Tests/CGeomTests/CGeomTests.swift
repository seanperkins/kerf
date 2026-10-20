import CGeom
import Testing

private func square(_ size: Double) -> [Double] {
    [0, 0, size, 0, size, size, 0, size]
}

private func area(_ xy: UnsafePointer<Double>, _ n: Int32) -> Double {
    var a = 0.0
    let n = Int(n)
    for i in 0..<n {
        let j = (i + 1) % n
        a += xy[2 * i] * xy[2 * j + 1] - xy[2 * j] * xy[2 * i + 1]
    }
    return abs(a) / 2
}

@Test func offsetGrowsSquare() throws {
    let xy = square(10)
    let counts: [Int32] = [4]
    let result = try #require(kg_offset(xy, counts, 1, 1.0, KG_JOIN_MITER, KG_END_POLYGON, 2.0, 0, 6))
    defer { kg_paths_free(result) }
    #expect(kg_paths_count(result) == 1)
    let n = kg_paths_point_count(result, 0)
    let pts = try #require(kg_paths_points(result, 0))
    #expect(abs(area(pts, n) - 144) < 1e-6)
}

@Test func booleanDifferenceOfSquares() throws {
    let subj = square(10)
    let clip: [Double] = [5, -1, 11, -1, 11, 11, 5, 11]
    let counts: [Int32] = [4]
    let result = try #require(kg_boolean(KG_OP_DIFFERENCE, KG_FILL_NONZERO, subj, counts, 1, 0, clip, counts, 1, 6))
    defer { kg_paths_free(result) }
    #expect(kg_paths_count(result) == 1)
    let pts = try #require(kg_paths_points(result, 0))
    #expect(abs(area(pts, kg_paths_point_count(result, 0)) - 50) < 1e-6)
}

@Test func voronoiOfSquareHasCentreVertex() throws {
    // Four segments forming a 10x10 square: medial axis meets at (5,5) with radius 5.
    let segs: [Double] = [0, 0, 10, 0, 10, 0, 10, 10, 10, 10, 0, 10, 0, 10, 0, 0]
    let vd = try #require(kg_voronoi_build(nil, 0, segs, 4, 1000, 0.5))
    defer { kg_voronoi_free(vd) }
    let count = Int(kg_voronoi_vertex_count(vd))
    let verts = try #require(kg_voronoi_vertices(vd))
    let centre = (0..<count).map { verts[$0] }.first { abs($0.x - 5) < 1e-6 && abs($0.y - 5) < 1e-6 }
    #expect(centre != nil)
    #expect(abs((centre?.radius ?? 0) - 5) < 1e-6)
    #expect(kg_voronoi_edge_count(vd) > 0)
    #expect(kg_voronoi_sample_count(vd) > 0)
}
