import Foundation
import Testing
@testable import CADCore

private func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-9) -> Bool { a.isApproximatelyEqual(to: b, tolerance: tol) }

@Suite struct PathNodesTests {
    let square = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)

    @Test func editableClosesExplicitlyAndConvertsArcs() {
        let e = PathNodes.editable(square)
        #expect(e.segments.count == 4)
        #expect(e.end == e.start)
        #expect(PathNodes.anchorCount(e) == 4)
        let circle = PathNodes.editable(ShapeFactory.circle(center: .zero, radius: 1))
        #expect(PathNodes.isEditable(circle))
        #expect(circle.segments.allSatisfy { if case .cubic = $0 { return true }; return false })
        #expect(abs(circle.bounds(tolerance: 1e-4).width - 2) < 1e-3)
    }

    @Test func openPathAnchors() {
        let p = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: false)
        #expect(PathNodes.anchors(p) == [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)])
        #expect(PathNodes.incomingSegment(p, 0) == nil)
        #expect(PathNodes.outgoingSegment(p, 2) == nil)
    }

    @Test func movingFirstAnchorOfClosedPathMovesClosingPoint() {
        let e = PathNodes.editable(square)
        let m = PathNodes.moveAnchor(e, 0, to: Vec2(-1, -1))
        #expect(m.start == Vec2(-1, -1))
        #expect(m.end == Vec2(-1, -1))
        #expect(PathNodes.anchor(m, 1) == Vec2(2, 0))
    }

    @Test func movingAnchorCarriesItsHandles() {
        let p = Path(start: .zero, segments: [.cubic(to: Vec2(3, 0), control1: Vec2(1, 1), control2: Vec2(2, 1)),
                                              .cubic(to: Vec2(6, 0), control1: Vec2(4, -1), control2: Vec2(5, -1))])
        let m = PathNodes.moveAnchor(p, 1, to: Vec2(3, 2))
        #expect(PathNodes.handle(m, 1, .incoming) == Vec2(2, 3))
        #expect(PathNodes.handle(m, 1, .outgoing) == Vec2(4, 1))
        #expect(PathNodes.handle(m, 0, .outgoing) == Vec2(1, 1)) // neighbours untouched
    }

    @Test func smoothHandleDragMirrorsDirection() {
        let p = Path(start: .zero, segments: [.cubic(to: Vec2(3, 0), control1: Vec2(1, 1), control2: Vec2(2, 0)),
                                              .cubic(to: Vec2(6, 0), control1: Vec2(5, 0), control2: Vec2(5, 1))])
        let m = PathNodes.moveHandle(p, 1, .incoming, to: Vec2(3, 1), keepSmooth: true)
        #expect(PathNodes.handle(m, 1, .incoming) == Vec2(3, 1))
        #expect(close(PathNodes.handle(m, 1, .outgoing)!, Vec2(3, -2)))
        #expect(PathNodes.isSmooth(m, 1))
        let free = PathNodes.moveHandle(p, 1, .incoming, to: Vec2(3, 1), keepSmooth: false)
        #expect(PathNodes.handle(free, 1, .outgoing) == Vec2(5, 0))
    }

    @Test func insertingOnCurveKeepsShape() {
        let p = Path(start: .zero, segments: [.cubic(to: Vec2(3, 0), control1: Vec2(0, 2), control2: Vec2(3, 2))])
        let m = PathNodes.insertAnchor(p, segment: 0, t: 0.5)
        #expect(m.segments.count == 2)
        #expect(close(PathNodes.anchor(m, 1), Flattening.cubicPoint(.zero, Vec2(0, 2), Vec2(3, 2), Vec2(3, 0), 0.5)))
        let a = p.flattened(tolerance: 1e-5), b = m.flattened(tolerance: 1e-5)
        #expect(abs(Rect2(points: a).height - Rect2(points: b).height) < 1e-4)
    }

    @Test func insertingOnLineSplitsIt() {
        let m = PathNodes.insertAnchor(PathNodes.editable(square), segment: 0, t: 0.25)
        #expect(PathNodes.anchorCount(m) == 5)
        #expect(PathNodes.anchor(m, 1) == Vec2(0.5, 0))
    }

    @Test func deletingAnchors() {
        let e = PathNodes.editable(square)
        let m = PathNodes.deleteAnchor(e, 2)!
        #expect(PathNodes.anchors(m) == [Vec2(0, 0), Vec2(2, 0), Vec2(0, 2)])
        #expect(m.end == m.start)
        #expect(PathNodes.deleteAnchor(m, 0) == nil) // triangle cannot lose a corner
        let first = PathNodes.deleteAnchor(e, 0)!
        #expect(PathNodes.anchors(first) == [Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)])
        #expect(first.end == first.start)
        let open = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(2, 0)], closed: false)
        #expect(PathNodes.anchors(PathNodes.deleteAnchor(open, 0)!) == [Vec2(1, 0), Vec2(2, 0)])
        #expect(PathNodes.anchors(PathNodes.deleteAnchor(open, 2)!) == [Vec2(0, 0), Vec2(1, 0)])
    }

    @Test func deletingBetweenCurvesKeepsOuterHandles() {
        let p = Path(start: .zero, segments: [.cubic(to: Vec2(3, 0), control1: Vec2(1, 1), control2: Vec2(2, 1)),
                                              .cubic(to: Vec2(6, 0), control1: Vec2(4, -1), control2: Vec2(5, -1))])
        let m = PathNodes.deleteAnchor(p, 1)!
        #expect(m.segments == [.cubic(to: Vec2(6, 0), control1: Vec2(1, 1), control2: Vec2(5, -1))])
    }

    @Test func convertLineAndCurve() {
        let e = PathNodes.editable(square)
        let c = PathNodes.convertSegment(e, 1, toCurve: true)
        #expect(PathNodes.handle(c, 1, .outgoing) != nil)
        #expect(PathNodes.handle(c, 2, .incoming) != nil)
        let back = PathNodes.convertSegment(c, 1, toCurve: false)
        #expect(back == e)
    }

    @Test func makeSmoothCreatesCollinearHandles() {
        let s = PathNodes.makeSmooth(PathNodes.editable(square), 1)
        #expect(PathNodes.isSmooth(s, 1))
        #expect(PathNodes.anchor(s, 1) == Vec2(2, 0))
    }

    @Test func nearestSegmentFindsClosestPoint() {
        let h = PathNodes.nearestSegment(PathNodes.editable(square), to: Vec2(2.1, 1.5))!
        #expect(h.segment == 1)
        #expect(abs(h.t - 0.75) < 1e-9)
        #expect(abs(h.distance - 0.1) < 1e-9)
    }
}

@Suite struct ShapeNodesTests {
    let layer = UUID()

    @Test func nodeEditDropsParametricOrigin() {
        let s = Shape(layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 2, height: 1))],
                      origin: .rectangle(width: 2, height: 1, cornerRadius: 0))
        let r = NodeRef(shapeID: s.id, path: 0, node: 2)
        let m = ShapeNodes.moveNode(s, r, to: Vec2(3, 3))
        #expect(m.origin == .drawn)
        #expect(m.bounds().max == Vec2(3, 3))
        #expect(m.id == s.id)
    }

    @Test func hitTestsNodesHandlesAndSegments() {
        let s = Shape(layerID: layer, paths: [Path(start: .zero, segments: [
            .cubic(to: Vec2(4, 0), control1: Vec2(1, 2), control2: Vec2(3, 2)), .line(to: Vec2(4, -2)),
        ])])
        #expect(ShapeNodes.hitNode(s, at: Vec2(4.05, 0), tolerance: 0.1) == NodeRef(shapeID: s.id, path: 0, node: 1))
        #expect(ShapeNodes.hitHandle(s, at: Vec2(3, 2.05), tolerance: 0.1)?.1 == .incoming)
        let seg = ShapeNodes.hitSegment(s, at: Vec2(4.02, -1), tolerance: 0.1)
        #expect(seg?.0.segment == 1)
    }

    @Test func deleteSeveralNodesFromHighestIndex() {
        let s = Shape(layerID: layer, paths: [Path(points: (0..<6).map { Vec2(Double($0), 0) }, closed: false)])
        let refs: Set<NodeRef> = [NodeRef(shapeID: s.id, path: 0, node: 1), NodeRef(shapeID: s.id, path: 0, node: 3)]
        let m = ShapeNodes.deleteNodes(s, refs)!
        #expect(PathNodes.anchors(m.paths[0]) == [Vec2(0, 0), Vec2(2, 0), Vec2(4, 0), Vec2(5, 0)])
    }

    @Test func moveNodesByDelta() {
        let s = Shape(layerID: layer, paths: [Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: false)])
        let m = ShapeNodes.moveNodes(s, [NodeRef(shapeID: s.id, path: 0, node: 1)], by: Vec2(0, -1))
        #expect(PathNodes.anchors(m.paths[0]) == [Vec2(0, 0), Vec2(1, -1), Vec2(1, 1)])
    }

    @Test func breakOpensClosedPathAndSplitsOpenPath() {
        let sq = Shape(layerID: layer, paths: [Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)])
        let opened = ShapeNodes.breakAt(sq, NodeRef(shapeID: sq.id, path: 0, node: 2))
        #expect(!opened.paths[0].isClosed)
        #expect(opened.paths[0].start == Vec2(2, 2) && opened.paths[0].end == Vec2(2, 2))
        #expect(opened.paths[0].segments.count == 4)
        let split = ShapeNodes.breakAt(opened, NodeRef(shapeID: sq.id, path: 0, node: 2))
        #expect(split.paths.count == 2)
        #expect(split.paths[0].end == split.paths[1].start)
    }

    @Test func smoothAndCornerConversion() {
        let sq = Shape(layerID: layer, paths: [Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)])
        let r = NodeRef(shapeID: sq.id, path: 0, node: 1)
        let smooth = ShapeNodes.setNodes(sq, [r], smooth: true)
        #expect(PathNodes.isSmooth(smooth.paths[0], 1))
        let corner = ShapeNodes.setNodes(smooth, [r], smooth: false)
        #expect(PathNodes.handle(corner.paths[0], 1, .incoming) == nil)
    }
}

@Suite struct TransformHandlesTests {
    let box = Rect2(x: 0, y: 0, width: 4, height: 2)

    @Test func cornerScalesAboutOppositeCorner() {
        let t = TransformHandles.transform(dragging: .topRight, box: box, from: Vec2(4, 2), to: Vec2(8, 3),
                                           keepAspect: false, fromCenter: false)
        #expect(close(t.apply(Vec2(0, 0)), Vec2(0, 0)))
        #expect(close(t.apply(Vec2(4, 2)), Vec2(8, 3)))
    }

    @Test func keepAspectUsesDominantScale() {
        let t = TransformHandles.transform(dragging: .topRight, box: box, from: Vec2(4, 2), to: Vec2(8, 2.5),
                                           keepAspect: true, fromCenter: false)
        #expect(close(t.apply(Vec2(4, 2)), Vec2(8, 4)))
    }

    @Test func edgeScalesOneAxis() {
        let t = TransformHandles.transform(dragging: .left, box: box, from: Vec2(0, 1), to: Vec2(-2, 5),
                                           keepAspect: true, fromCenter: false)
        #expect(close(t.apply(Vec2(0, 0)), Vec2(-2, 0)))
        #expect(close(t.apply(Vec2(4, 2)), Vec2(4, 2)))
    }

    @Test func fromCenterScalesSymmetrically() {
        let t = TransformHandles.transform(dragging: .right, box: box, from: Vec2(4, 1), to: Vec2(6, 1),
                                           keepAspect: false, fromCenter: true)
        #expect(close(t.apply(Vec2(0, 0)), Vec2(-2, 0)))
    }

    @Test func dragPastPivotMirrors() {
        let t = TransformHandles.transform(dragging: .right, box: box, from: Vec2(4, 1), to: Vec2(-4, 1),
                                           keepAspect: false, fromCenter: false)
        #expect(t.isMirroring)
    }

    @Test func rotateAboutCentreWithSnap() {
        let c = box.center
        let t = TransformHandles.transform(dragging: .rotate, box: box, from: c + Vec2(0, 3), to: c + Vec2(-3, 0.2),
                                           keepAspect: false, fromCenter: false, angleSnap: 15)
        #expect(close(t.apply(c + Vec2(1, 0)), c + Vec2(0, 1), 1e-9))
    }

    @Test func hitFindsRotateHandleAboveTop() {
        #expect(TransformHandles.hit(Vec2(2, 2.5), box: box, rotateOffset: 0.5, tolerance: 0.1) == .rotate)
        #expect(TransformHandles.hit(Vec2(0.05, 0), box: box, rotateOffset: 0.5, tolerance: 0.1) == .bottomLeft)
        #expect(TransformHandles.hit(Vec2(1, 1), box: box, rotateOffset: 0.5, tolerance: 0.1) == nil)
    }
}

@Suite struct SnapEngineTests {
    let layer = UUID()

    @Test func objectPointsBeatGrid() {
        let s = Shape(layerID: layer, paths: [Path(points: [Vec2(0.1, 0.1), Vec2(2.1, 0.1)], closed: false)])
        let e = SnapEngine(shapes: [s])
        #expect(e.snap(Vec2(0.15, 0.12), tolerance: 0.1, grid: 0.25) == .init(point: Vec2(0.1, 0.1), kind: .node))
        #expect(e.snap(Vec2(1.12, 0.05), tolerance: 0.1, grid: 0.25) == .init(point: Vec2(1.1, 0.1), kind: .midpoint))
        #expect(e.snap(Vec2(3.1, 3.1), tolerance: 0.1, grid: 0.25) == .init(point: Vec2(3, 3), kind: .grid))
        #expect(e.snap(Vec2(3.1, 3.1), tolerance: 0.1, grid: 0).kind == SnapEngine.Kind.none)
    }

    @Test func centresAndImplicitClosingMidpoints() {
        let s = Shape(layerID: layer, paths: [Path(points: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 2)], closed: true)])
        let e = SnapEngine(shapes: [s])
        #expect(e.targets.contains(.init(point: Vec2(2, 1), kind: .midpoint))) // closing segment
        #expect(e.targets.contains(.init(point: Vec2(2, 1), kind: .center)))
    }

    @Test func snapDeltaAlignsAnchorToTarget() {
        let e = SnapEngine(targets: [.init(point: Vec2(5, 5), kind: .node)])
        let d = e.snapDelta(Vec2(2.95, 3.02), anchors: [Vec2(2, 2)], tolerance: 0.1, grid: 0.25)
        #expect(close(d, Vec2(3, 3)))
        #expect(e.snapDelta(Vec2(0.3, 0.1), anchors: [Vec2(2, 2)], tolerance: 0.1, grid: 0.25) == Vec2(0.25, 0))
    }
}

@Suite struct PenPathTests {
    @Test func cornersMakeLines() {
        var pen = PenPath()
        pen.addNode(.zero); pen.addNode(Vec2(1, 0)); pen.addNode(Vec2(1, 1))
        #expect(pen.path(closed: false) == Path(points: [.zero, Vec2(1, 0), Vec2(1, 1)], closed: false))
        let closed = pen.path(closed: true)!
        #expect(closed.isClosed && closed.end == closed.start)
    }

    @Test func dragMakesSmoothNodeWithMirroredHandle() {
        var pen = PenPath()
        pen.addNode(.zero)
        pen.addNode(Vec2(2, 0)); pen.dragLastHandle(to: Vec2(3, 1))
        pen.addNode(Vec2(4, 0))
        let p = pen.path(closed: false)!
        #expect(p.segments[0] == .cubic(to: Vec2(2, 0), control1: .zero, control2: Vec2(1, -1)))
        #expect(p.segments[1] == .cubic(to: Vec2(4, 0), control1: Vec2(3, 1), control2: Vec2(4, 0)))
    }

    @Test func closesNearFirstNode() {
        var pen = PenPath()
        pen.addNode(.zero); pen.addNode(Vec2(1, 0))
        #expect(pen.closes(at: Vec2(0.01, 0), tolerance: 0.05))
        #expect(pen.path(closed: true) == nil) // two corner nodes cannot close
        #expect(PenPath(nodes: [.init(point: .zero)]).path(closed: false) == nil)
    }
}

@Suite struct GroupingTests {
    @Test func groupExpandAndUngroup() {
        var doc = Document()
        let l = doc.defaultLayerID
        let a = Shape(layerID: l, paths: []), b = Shape(layerID: l, paths: []), c = Shape(layerID: l, paths: [])
        [a, b, c].forEach { doc.add($0) }
        let g = doc.group([a.id, b.id])
        #expect(g != nil)
        #expect(doc.expandToGroups([b.id]) == [b.id, a.id])
        #expect(doc.groupMembers(of: c.id) == [c.id])
        // Grouping a group member with another shape nests the whole group inside the new one.
        let g2 = doc.group([a.id, c.id])!
        #expect(doc.shapes.allSatisfy { $0.groupID == g2 })
        #expect(doc.groupDepth(of: a.id) == 2 && doc.groupDepth(of: c.id) == 1)
        #expect(doc.group([a.id, b.id, c.id]) == nil)  // already exactly one group
        // Ungroup peels one level: a and b are back in their own group.
        doc.ungroup([c.id])
        #expect(doc.shape(id: a.id)?.groupID == g && doc.shape(id: b.id)?.groupID == g)
        #expect(doc.shape(id: c.id)?.groupID == nil)
        doc.ungroup([a.id])
        #expect(doc.shapes.allSatisfy { $0.groupID == nil && $0.innerGroupIDs == nil })
        #expect(doc.group([a.id]) == nil)
    }

    @Test func ungroupAllLevelsAndPruning() {
        var doc = Document()
        let l = doc.defaultLayerID
        let a = Shape(layerID: l, paths: []), b = Shape(layerID: l, paths: []), c = Shape(layerID: l, paths: [])
        [a, b, c].forEach { doc.add($0) }
        let inner = doc.group([a.id, b.id])!
        doc.group([a.id, c.id])
        doc.ungroupAllLevels([b.id])
        #expect(doc.shapes.allSatisfy { $0.groupID == nil && $0.innerGroupIDs == nil })
        // Deleting the outer group's other member leaves a and b in their inner group.
        doc.group([a.id, b.id])
        doc.group([a.id, c.id])
        doc.removeShapes(ids: [c.id])
        doc.pruneSingletonGroups()
        #expect(doc.groupDepth(of: a.id) == 2)  // the outer group still has two members
        doc.removeShapes(ids: [b.id])
        doc.pruneSingletonGroups()
        #expect(doc.shape(id: a.id)?.groupID == nil)
        _ = inner
    }

    @Test func singletonGroupsArePruned() {
        var doc = Document()
        let l = doc.defaultLayerID
        let a = Shape(layerID: l, paths: []), b = Shape(layerID: l, paths: [])
        doc.add(a); doc.add(b)
        doc.group([a.id, b.id])
        doc.removeShapes(ids: [b.id])
        doc.pruneSingletonGroups()
        #expect(doc.shape(id: a.id)?.groupID == nil)
    }

    @Test func groupIDIsOptionalInJSON() throws {
        let s = Shape(layerID: UUID(), paths: [])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json.removeValue(forKey: "groupID")
        let back = try JSONDecoder().decode(Shape.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.groupID == nil)
    }
}
