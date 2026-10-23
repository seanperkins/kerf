import CADCore
import Foundation

/// Hole milling: helical boring of holes larger than the tool, or internal thread milling, at the
/// centre of each selected closed vector.
public struct HoleMillOperation: ToolpathOperation {
    public static let kind = OperationKind.holeMill
    public var setup: OperationSetup
    public var params: HoleMillParameters

    public init(setup: OperationSetup, params: HoleMillParameters = HoleMillParameters()) {
        self.setup = setup
        self.params = params
    }

    /// The steepest a boring helix may descend, in degrees from horizontal: the default ramp angle. A hole barely
    /// larger than the tool has a helix so small that the pitch would make it a straight drop at the feed rate.
    public static let maxHelixAngle = RampSettings().maxAngle
    /// More turns than this at the steepest allowed angle and the helix is a drill in all but name: the hole is
    /// peck-drilled instead.
    static let maxHelixTurns = 50.0
    /// Most turns a helix may take, so a huge depth or a tiny pitch cannot ask for an unbounded number of points. More is
    /// refused: spreading the depth over fewer turns would make the helix steeper than `maxHelixAngle`.
    static let maxTotalTurns = 10_000.0

    /// A hole to mill: centre and finished diameter.
    public struct Hole: Hashable, Sendable {
        public var centre: Vec2
        public var diameter: Double

        public init(centre: Vec2, diameter: Double) { self.centre = centre; self.diameter = diameter }
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        guard params.cutDepth > params.startDepth + 1e-9, params.cutDepth.isFinite, params.startDepth.isFinite else {
            throw CAMError.invalidParameter("Cut depth must be deeper than start depth")
        }
        if let pitch = params.helixPitch, !(pitch.isFinite && pitch > 0) {
            throw CAMError.invalidParameter("Helix pitch must be a positive number")
        }
        if let d = params.holeDiameter, !(d.isFinite && d > 0) {
            throw CAMError.invalidParameter("Hole diameter must be a positive number")
        }
        guard tool.diameter.isFinite, tool.diameter > 0 else {
            throw CAMError.invalidParameter("Tool diameter must be a positive number")
        }
        let tol = context.tolerance
        var holes = Self.holes(shapes, tolerance: tol)
        guard !holes.isEmpty else { throw CAMError.invalidGeometry("Hole milling needs closed vectors (circles)") }
        if let d = params.holeDiameter { holes = holes.map { Hole(centre: $0.centre, diameter: d) } }
        let tooSmall = holes.filter { $0.diameter < tool.diameter - tol }.count
        holes.removeAll { $0.diameter < tool.diameter - tol }
        guard !holes.isEmpty else { throw CAMError.invalidGeometry("Every hole is smaller than the tool") }
        if params.mode == .thread {
            guard params.threadPitch > tol else { throw CAMError.invalidParameter("Thread pitch must be positive") }
        }

        let coords = context.coords
        let home = coords.materialXY(fromMachine: context.document.job.home)
        let order = ChainOrdering.nearestNeighbour(holes.map { Chain2D(points: [$0.centre], isClosed: false) }, from: home)
            .map(\.start)
        var builder = ToolpathBuilder(coords: coords, tool: tool, units: context.units, tolerance: tol, fitArcs: true)
        var clamped = 0, pecked = 0, noRoom = 0
        for c in order {
            guard let hole = holes.first(where: { $0.centre.distance(to: c) <= tol }) else { continue }
            let radius = (hole.diameter - tool.diameter) / 2
            switch params.mode {
            case .helical:
                switch try bore(hole, radius: radius, tool: tool, tolerance: tol, builder: &builder) {
                case .helix: break
                case .clamped: clamped += 1
                case .pecked: pecked += 1
                }
            case .thread:
                if try !thread(hole, radius: radius, tolerance: tol, builder: &builder) { noRoom += 1 }
            }
        }
        var meta = ["holes": "\(order.count)"]
        var warnings: [String] = []
        if tooSmall > 0 { warnings.append("\(tooSmall) hole(s) smaller than the tool skipped") }
        if clamped > 0 {
            warnings.append("\(clamped) hole(s) are barely larger than the tool: the helix is held to a \(Int(Self.maxHelixAngle))° ramp, "
                            + "so it turns more often than the pitch asks")
        }
        if pecked > 0 {
            warnings.append("\(pecked) hole(s) are too close to the tool's size for a helix (it would drop almost straight down): "
                            + "peck-drilled instead")
        }
        if noRoom > 0 { warnings.append("\(noRoom) hole(s) are as large as the tool: no room to mill a thread, skipped") }
        if !warnings.isEmpty { meta["warning"] = warnings.joined(separator: "; ") }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .holeMill, tool: tool,
                         moves: builder.finish(), metadata: meta)]
    }

    /// Helix down at `radius` around the centre and a flat lap at the bottom. When the tool path
    /// clears the whole hole (diameter up to twice the tool) the tool then moves to the centre to lift
    /// clear of the wall; for bigger holes a core is left standing in the middle, so it lifts in place.
    ///
    /// The helix descends no steeper than `maxHelixAngle`: where the pitch asked for would be steeper (a small
    /// radius, a big pitch) it turns more often. Where that takes more than `maxHelixTurns` turns, or the hole is
    /// the size of the tool, there is no helix to make and the hole is peck-drilled at its centre.
    private enum Bore { case helix, clamped, pecked }

    private func bore(_ hole: Hole, radius: Double, tool: Tool, tolerance tol: Double, builder: inout ToolpathBuilder) throws -> Bore {
        let c = hole.centre
        let pitch = max(params.helixPitch ?? tool.stepdown, tol)
        let drop = params.cutDepth - params.startDepth
        // The most it may drop per turn, measured along the chords the helix is cut in (they are shorter than the arc).
        let perTurn = Double(Self.segmentsPerTurn(radius: radius, tolerance: tol))
        let steepest = perTurn * 2 * max(radius, 0) * sin(Double.pi / perTurn) * tan(Self.maxHelixAngle * .pi / 180)
        let allowed = min(pitch, steepest)
        let held = allowed < pitch - 1e-12
        let turns = max(1, ceil(drop / max(allowed, 1e-12) - 1e-9))
        // Peck only where the ramp limit is what asks for the turns (a fine pitch the user chose stays a helix).
        guard radius > tol, !(held && turns > Self.maxHelixTurns) else {
            guard drop / pitch <= Self.maxTotalTurns else {
                throw CAMError.invalidParameter("The cut is too deep for the peck depth: it would take more than \(Int(Self.maxTotalTurns)) pecks; "
                                                + "raise the pitch")
            }
            builder.travel(to: c)
            var cleared = min(params.startDepth, 0)
            let pecks = DrillOperation.peckDepths(start: params.startDepth, end: params.cutDepth, peck: pitch)
            let bottom = pecks.last ?? params.cutDepth
            for d in pecks {
                builder.plunge(to: d, clearedDepth: cleared)
                cleared = d
                // A lap at the hole's own radius at the bottom of each peck, so the hole comes out its size.
                if radius > tol {
                    builder.feed(to: Self.helix(centre: c, radius: radius, fromDepth: d, toDepth: d, turns: 1,
                                                ccw: params.direction == .climb, tolerance: tol) + [CutPoint(c, depth: d)])
                }
                if d < bottom - 1e-12 { builder.retract() }
            }
            return .pecked
        }
        guard turns <= Self.maxTotalTurns else {
            throw CAMError.invalidParameter("The cut is too deep for the helix pitch: it would take more than \(Int(Self.maxTotalTurns)) turns; "
                                            + "raise the pitch or the depth per turn")
        }
        // Climb inside a hole (clockwise spindle) = counter-clockwise.
        let ccw = params.direction == .climb
        var pts = Self.helix(centre: c, radius: radius, fromDepth: params.startDepth, toDepth: params.cutDepth,
                             turns: turns, ccw: ccw, tolerance: tol)
        pts += Self.helix(centre: c, radius: radius, fromDepth: params.cutDepth, toDepth: params.cutDepth,
                          turns: 1, ccw: ccw, tolerance: tol).dropFirst()
        if Self.leavesNoCore(hole, tool: tool, tolerance: tol) { pts.append(CutPoint(c, depth: params.cutDepth)) }
        builder.cutChain(pts)
        return held ? .clamped : .helix
    }

    /// Thread milling: plunge at the centre (pilot hole), out to the radius, one helix turn per
    /// pitch over the thread length, back to the centre. Climb turns counter-clockwise and conventional
    /// clockwise; a right-hand thread rises while turning counter-clockwise (climb goes up, conventional comes
    /// down) and a left-hand thread does the opposite (climb comes down, conventional goes up).
    /// Whether the thread was milled (false: the hole is as large as the tool, so there is nothing to thread).
    private func thread(_ hole: Hole, radius: Double, tolerance tol: Double, builder: inout ToolpathBuilder) throws -> Bool {
        let c = hole.centre
        guard radius > tol else { return false }
        let length = params.cutDepth - params.startDepth
        let turns = max(1, ceil(length / params.threadPitch - 1e-9))
        guard turns <= Self.maxTotalTurns else {
            throw CAMError.invalidParameter("The thread is too long for its pitch: it would take more than \(Int(Self.maxTotalTurns)) turns")
        }
        // Climb inside a bore is counter-clockwise (clockwise spindle), whatever the thread's hand. The hand sets
        // which way along Z that turn goes: counter-clockwise while rising is a right-hand thread.
        let climb = params.direction == .climb
        let ccw = climb
        let upward = climb == params.rightHandThread
        // A whole number of turns at the thread pitch, ending at the cut depth when going down.
        let span = turns * params.threadPitch
        let (from, to) = upward ? (params.cutDepth, params.cutDepth - span) : (params.cutDepth - span, params.cutDepth)
        builder.cutChain([CutPoint(c, depth: from)])
        let pts = Self.helix(centre: c, radius: radius, fromDepth: from, toDepth: to, turns: turns, ccw: ccw, tolerance: tol)
        builder.feed(to: pts + [CutPoint(c, depth: to)])
        return true
    }

    /// True when a ring at radius (D - d)/2 sweeps the whole hole, so nothing is left at the centre.
    public static func leavesNoCore(_ hole: Hole, tool: Tool, tolerance: Double) -> Bool {
        hole.diameter <= 2 * tool.diameter + tolerance
    }

    /// How many straight pieces one turn of a helix of radius `r` is cut in (chord error within `tolerance`, at least 16).
    static func segmentsPerTurn(radius r: Double, tolerance: Double) -> Int {
        guard r > 0 else { return 16 }
        let step = 2 * acos(max(-1, min(1, 1 - min(tolerance, r) / r)))
        return max(16, Int(ceil(2 * .pi / max(step, 1e-3))))
    }

    /// Helix samples starting at angle 0 (centre + (radius, 0)).
    static func helix(centre c: Vec2, radius r: Double, fromDepth: Double, toDepth: Double, turns: Double,
                      ccw: Bool, tolerance: Double) -> [CutPoint] {
        let perTurn = segmentsPerTurn(radius: r, tolerance: tolerance)
        let n = max(1, Int((Double(perTurn) * turns).rounded(.up)))
        let total = 2 * .pi * turns
        return (0...n).map { i in
            let t = Double(i) / Double(n)
            let a = (ccw ? 1 : -1) * total * t
            return CutPoint(c + Vec2(cos(a), sin(a)) * r, depth: fromDepth + (toDepth - fromDepth) * t)
        }
    }

    /// One hole per closed path: arc-only paths use their exact centre and radius; others the
    /// bounds centre and the smaller bounds side. Concentric paths keep the largest.
    public static func holes(_ shapes: [Shape], tolerance: Double) -> [Hole] {
        var out: [Hole] = []
        for s in shapes {
            for path in s.paths where path.isClosed {
                let b = path.bounds(tolerance: tolerance)
                guard !b.isEmpty else { continue }
                let centre = DrillOperation.arcCentre(path)
                let diameter = centre.map { 2 * path.start.distance(to: $0) } ?? min(b.width, b.height)
                let c = centre ?? b.center
                if let i = out.firstIndex(where: { $0.centre.distance(to: c) <= tolerance }) {
                    out[i].diameter = max(out[i].diameter, diameter)
                } else {
                    out.append(Hole(centre: c, diameter: diameter))
                }
            }
        }
        return out
    }
}
