import Foundation
import Testing
@testable import CADCore

/// Looking up thousands of shapes by id (an imported drawing, all selected) must not scan the document for each one.
@Suite struct DocumentLookupTests {
    static func shape(_ x: Double, in layer: UUID) -> Shape {
        Shape(layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: x, y: 0, width: 1, height: 1))])
    }

    /// `count` shapes; a few ids repeated, a few groups (some of them holding a repeated id).
    static func document(count: Int, seed: UInt64) -> Document {
        var rng = seed
        func next(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(n)) }
        var doc = Document()
        let layer = doc.defaultLayerID
        let groups = (0..<6).map { _ in UUID() }
        for i in 0..<count {
            var s = shape(Double(i), in: layer)
            if i > 10, next(10) == 0 { s.id = doc.shapes[next(i)].id }                   // a repeated id
            if next(3) == 0 { s.groupID = groups[next(groups.count)] }
            doc.add(s)
        }
        return doc
    }

    static func ids(from doc: Document, count: Int, seed: UInt64) -> [UUID] {
        var rng = seed
        func next(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(n)) }
        return (0..<count).map { _ in next(12) == 0 ? UUID() : doc.shapes[next(doc.shapes.count)].id }   // some unknown, some repeated
    }

    @Test(arguments: [0, 1, 5, 16, 17, 40, 200])
    func shapesByIdsAreTheScanFindsThem(count: Int) {
        let doc = Self.document(count: 150, seed: UInt64(count) + 1)
        let ids = Self.ids(from: doc, count: count, seed: UInt64(count) + 7)
        #expect(doc.shapes(ids: ids) == ids.compactMap { id in doc.shapes.first { $0.id == id } })
    }

    @Test(arguments: [0, 1, 5, 16, 17, 40, 200])
    func groupExpansionIsWhatTheScanGives(count: Int) {
        let doc = Self.document(count: 150, seed: UInt64(count) + 3)
        let ids = Self.ids(from: doc, count: count, seed: UInt64(count) + 11)
        // The expansion as it was written before the index: each id, then the members of the group of its first shape.
        var seen = Set<UUID>()
        var expected: [UUID] = []
        for id in ids {
            let mates: [UUID]
            if let g = doc.shapes.first(where: { $0.id == id })?.groupID { mates = doc.shapes.filter { $0.groupID == g }.map(\.id) } else { mates = [id] }
            for m in [id] + mates where seen.insert(m).inserted { expected.append(m) }
        }
        #expect(doc.expandToGroups(ids) == expected)
    }

    @Test func ungroupingManyShapesIsWhatTheScanDoes() {
        var a = Self.document(count: 150, seed: 5)
        var b = a
        let ids = Self.ids(from: a, count: 60, seed: 9)
        a.ungroup(ids)
        let groups = Set(ids.compactMap { id in b.shapes.first { $0.id == id }?.groupID })
        for i in b.shapes.indices where b.shapes[i].groupID.map(groups.contains) == true {
            var inner = b.shapes[i].innerGroupIDs ?? []
            b.shapes[i].groupID = inner.isEmpty ? nil : inner.removeFirst()
            b.shapes[i].innerGroupIDs = inner.isEmpty ? nil : inner
        }
        #expect(a == b)
    }

    @Test func aSelectionOfEverythingInABigDrawingIsNotQuadratic() {
        // 40,000 shapes: a scan per id is 1.6 billion comparisons (minutes in a debug build); the index is milliseconds
        // (the bound is loose because the suite runs beside heavy tests).
        var doc = Document()
        let layer = doc.defaultLayerID
        let g = UUID()
        for i in 0..<40_000 {
            var s = Self.shape(Double(i), in: layer)
            if i % 4 == 0 { s.groupID = g }
            doc.add(s)
        }
        let ids = doc.shapes.map(\.id)
        let start = ContinuousClock.now
        #expect(doc.shapes(ids: ids).count == 40_000)
        #expect(doc.expandToGroups(ids).count == 40_000)
        var copy = doc
        copy.ungroup(ids)
        #expect(copy.shapes.allSatisfy { $0.groupID == nil })
        #expect(ContinuousClock.now - start < .seconds(25), "took \(ContinuousClock.now - start)")
    }
}
