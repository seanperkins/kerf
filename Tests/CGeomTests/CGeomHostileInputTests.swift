import CGeom
import Testing

/// Clipper2 throws C++ exceptions for coordinates it cannot scale to int64 (inf, or beyond
/// about 2e12 at precision 6). The wrapper must swallow them: an exception crossing the C
/// boundary would abort the app.
@Test func offsetWithInfiniteCoordinateReturnsNilInsteadOfAborting() {
    let xy: [Double] = [0, 0, .infinity, 0, 10, 10]
    let counts: [Int32] = [3]
    let r = kg_offset(xy, counts, 1, 1.0, KG_JOIN_ROUND, KG_END_POLYGON, 2.0, 0, 6)
    #expect(r == nil)
}

@Test func booleanWithHugeCoordinateReturnsNilInsteadOfAborting() {
    let subj: [Double] = [0, 0, 5e12, 0, 5e12, 5e12, 0, 5e12]
    let clip: [Double] = [0, 0, 1, 0, 1, 1, 0, 1]
    let counts: [Int32] = [4]
    let r = kg_boolean(KG_OP_UNION, KG_FILL_NONZERO, subj, counts, 1, 0, clip, counts, 1, 6)
    #expect(r == nil)
}

@Test func emptyInputIsAnEmptyResult() throws {
    let r = try #require(kg_offset(nil, nil, 0, 1.0, KG_JOIN_ROUND, KG_END_POLYGON, 2.0, 0, 6))
    defer { kg_paths_free(r) }
    #expect(kg_paths_count(r) == 0)
    #expect(kg_paths_points(r, 0) == nil)
    #expect(kg_paths_point_count(r, -1) == 0)
}
