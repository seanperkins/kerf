import CADCore
import CAMCore
import Foundation

enum AlignMode: String, CaseIterable, Identifiable {
    case left, centerX, right, bottom, centerY, top, materialCenter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: return "Align Left"
        case .centerX: return "Align Centres Horizontally"
        case .right: return "Align Right"
        case .bottom: return "Align Bottom"
        case .centerY: return "Align Centres Vertically"
        case .top: return "Align Top"
        case .materialCenter: return "Centre on Material"
        }
    }
}

enum BooleanMode: String, CaseIterable, Identifiable {
    case union, subtract, intersect
    var id: String { rawValue }
    var title: String {
        switch self {
        case .union: return "Weld (Union)"
        case .subtract: return "Subtract"
        case .intersect: return "Intersect"
        }
    }
}

/// Design-menu operations on the selection. Each returns the new selection (or nil if nothing
/// changed) and mutates `project` in place.
enum DesignCommands {
    /// Aligns each shape to the selection bounds (or the material for `.materialCenter`).
    static func align(_ ids: Set<UUID>, mode: AlignMode, in project: inout KerfProject) {
        let shapes = project.document.shapes.filter { ids.contains($0.id) && !$0.isLocked }
        guard !shapes.isEmpty else { return }
        if mode == .materialCenter {
            let all = project.bounds(of: Set(shapes.map(\.id)))
            let d = project.document.job.materialBounds.center - all.center
            project.transformShapes(Set(shapes.map(\.id)), by: .translation(d))
            return
        }
        let ref = project.bounds(of: Set(shapes.map(\.id)))
        for s in shapes {
            let b = s.bounds()
            var d = Vec2.zero
            switch mode {
            case .left: d.x = ref.min.x - b.min.x
            case .right: d.x = ref.max.x - b.max.x
            case .centerX: d.x = ref.center.x - b.center.x
            case .bottom: d.y = ref.min.y - b.min.y
            case .top: d.y = ref.max.y - b.max.y
            case .centerY: d.y = ref.center.y - b.center.y
            case .materialCenter: break
            }
            project.transformShapes([s.id], by: .translation(d))
        }
    }

    /// Spreads shape centres evenly between the outermost two along X (or Y).
    static func distribute(_ ids: Set<UUID>, horizontally: Bool, in project: inout KerfProject) {
        let shapes = project.document.shapes.filter { ids.contains($0.id) && !$0.isLocked }
        guard shapes.count >= 3 else { return }
        let key: (Shape) -> Double = { horizontally ? $0.bounds().center.x : $0.bounds().center.y }
        let sorted = shapes.sorted { key($0) < key($1) }
        let lo = key(sorted.first!), hi = key(sorted.last!)
        let step = (hi - lo) / Double(sorted.count - 1)
        for (i, s) in sorted.enumerated() {
            let target = lo + step * Double(i)
            let d = target - key(s)
            project.transformShapes([s.id], by: .translation(horizontally ? Vec2(d, 0) : Vec2(0, d)))
        }
    }

    /// Boolean of closed shapes. Union/intersect combine all; subtract removes the others from
    /// the first-selected (`primary`). Result replaces the inputs. Returns the new shape's id.
    static func boolean(_ mode: BooleanMode, ids: [UUID], in project: inout KerfProject) -> UUID? {
        let shapes = project.document.shapes(ids: ids).filter { $0.isClosed && !$0.isLocked }
        guard shapes.count >= 2 else { return nil }
        let tol = project.document.units == .inch ? 0.0005 : 0.01
        let first = shapes[0], rest = Array(shapes.dropFirst())
        let paths: [Path]
        switch mode {
        case .union: paths = PathOps.union(shapes.flatMap(\.paths), tolerance: tol)
        case .subtract: paths = PathOps.subtract(first.paths, minus: rest.flatMap(\.paths), tolerance: tol)
        case .intersect:
            paths = rest.reduce(first.paths) { PathOps.intersect($0, with: $1.paths, tolerance: tol) }
        }
        project.deleteShapes(Set(shapes.map(\.id)))
        guard !paths.isEmpty else { return nil }
        let s = Shape(name: mode.title, layerID: first.layerID, paths: paths, origin: .derived(operation: mode.rawValue))
        project.document.add(s)
        return s.id
    }

    /// Offsets closed shapes outward (+) / inward (−), adding new shapes. Returns their ids.
    static func offset(_ ids: [UUID], distance: Double, sharpCorners: Bool, in project: inout KerfProject) -> [UUID] {
        let tol = project.document.units == .inch ? 0.0005 : 0.01
        var newIDs: [UUID] = []
        for s in project.document.shapes(ids: ids) where s.isClosed {
            let paths = PathOps.offset(s.paths, by: distance, join: sharpCorners ? .miter(limit: 4) : .round, tolerance: tol)
            guard !paths.isEmpty else { continue }
            let n = Shape(name: (s.name.isEmpty ? "Shape" : s.name) + " offset", layerID: s.layerID, paths: paths,
                          origin: .derived(operation: "offset"))
            project.document.add(n)
            newIDs.append(n.id)
        }
        return newIDs
    }

    /// Joins open vectors of the selection into as few paths as possible (one new shape).
    static func join(_ ids: [UUID], tolerance: Double, in project: inout KerfProject) -> UUID? {
        let shapes = project.document.shapes(ids: ids).filter { !$0.isLocked }
        let open = shapes.flatMap(\.paths).filter { !$0.isClosed }
        guard !open.isEmpty, let first = shapes.first else { return nil }
        let closed = shapes.flatMap(\.paths).filter(\.isClosed)
        let joined = PathOps.joinOpenPaths(open, tolerance: tolerance)
        project.deleteShapes(Set(shapes.map(\.id)))
        let s = Shape(name: "Joined", layerID: first.layerID, paths: closed + joined, origin: .derived(operation: "join"))
        project.document.add(s)
        return s.id
    }

    /// Closes every open path in the selection with a straight segment.
    static func close(_ ids: Set<UUID>, in project: inout KerfProject) {
        for i in project.document.shapes.indices where ids.contains(project.document.shapes[i].id) {
            for j in project.document.shapes[i].paths.indices where !project.document.shapes[i].paths[j].isClosed {
                if project.document.shapes[i].paths[j].segments.count >= 2 {
                    project.document.shapes[i].paths[j].isClosed = true
                }
            }
        }
    }

    /// Explodes multi-path shapes into one shape per path.
    static func explode(_ ids: Set<UUID>, in project: inout KerfProject) -> [UUID] {
        var newIDs: [UUID] = []
        for s in project.document.shapes where ids.contains(s.id) && s.paths.count > 1 && !s.isLocked {
            project.deleteShapes([s.id])
            for p in s.paths {
                let n = Shape(name: s.name, layerID: s.layerID, paths: [p], origin: .derived(operation: "explode"))
                project.document.add(n)
                newIDs.append(n.id)
            }
        }
        return newIDs
    }

    /// Groups (merges) selected shapes into one multi-path shape.
    static func combine(_ ids: [UUID], in project: inout KerfProject) -> UUID? {
        let shapes = project.document.shapes(ids: ids).filter { !$0.isLocked }
        guard shapes.count >= 2 else { return nil }
        project.deleteShapes(Set(shapes.map(\.id)))
        let s = Shape(name: "Group", layerID: shapes[0].layerID, paths: shapes.flatMap(\.paths),
                      origin: .derived(operation: "combine"))
        project.document.add(s)
        return s.id
    }
}

/// Numeric transform requests from the inspector.
enum TransformCommands {
    /// Moves/resizes the selection so its bounds become `target` (anchor: lower-left).
    static func fit(_ ids: Set<UUID>, to target: Rect2, keepAspect: Bool, in project: inout KerfProject) {
        let b = project.bounds(of: ids)
        guard !b.isEmpty else { return }
        var sx = b.width > 1e-12 ? target.width / b.width : 1
        var sy = b.height > 1e-12 ? target.height / b.height : 1
        if keepAspect {
            let s = (abs(sx - 1) > abs(sy - 1)) ? sx : sy
            sx = s; sy = s
        }
        let t = Transform2D.scale(sx, sy, about: b.min).concatenating(.translation(target.min - b.min))
        project.transformShapes(ids, by: t)
    }

    static func rotate(_ ids: Set<UUID>, degrees: Double, in project: inout KerfProject) {
        let c = project.bounds(of: ids).center
        project.transformShapes(ids, by: .rotation(degrees * .pi / 180, about: c))
    }

    static func mirror(_ ids: Set<UUID>, horizontally: Bool, in project: inout KerfProject) {
        let c = project.bounds(of: ids).center
        // horizontalAxis: true mirrors across a horizontal line (flips Y).
        project.transformShapes(ids, by: .mirror(horizontalAxis: !horizontally, about: c))
    }
}
