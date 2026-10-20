import CADCore
import CAMCore
import Foundation

public struct GCodeIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Hashable, Sendable { case warning, error }
    public var severity: Severity
    /// 1-based line number in the G-code, when applicable.
    public var line: Int?
    public var message: String

    public init(severity: Severity, line: Int? = nil, message: String) {
        self.severity = severity; self.line = line; self.message = message
    }

    public var description: String {
        "\(severity.rawValue)\(line.map { " line \($0)" } ?? ""): \(message)"
    }
}

/// Safety checks on toolpaths / generated G-code: travel extents, cut depth vs. material
/// bottom + spoilboard allowance, XY rapids below safe Z / inside the material, cutting with
/// the spindle off, missing feed, RPM range.
///
/// `job` is in `units` (the document's units). G-code is checked in the units it declares
/// (G20/G21, defaulting to the profile's units).
public struct GCodeValidator: Sendable {
    public var profile: PostProfile
    public var job: JobSetup
    public var units: LengthUnit

    public init(profile: PostProfile, job: JobSetup, units: LengthUnit) {
        self.profile = profile; self.job = job; self.units = units
    }

    /// Issues sorted errors first.
    public static func errors(in issues: [GCodeIssue]) -> [GCodeIssue] { issues.filter { $0.severity == .error } }

    // MARK: Toolpaths

    public func validate(toolpaths: [Toolpath]) -> [GCodeIssue] {
        var check = MotionChecker(profile: profile, job: job, jobUnits: units, units: units)
        var pos: Vec3?
        for tp in toolpaths {
            if tp.moves.isEmpty {
                check.issues.add("empty-\(tp.id)", .warning, line: nil, "Toolpath '\(tp.name)' has no moves")
                continue
            }
            check.rpm(tp.spindleRPM, min: profile.minRPM, max: profile.maxRPM, line: nil)
            for move in tp.moves {
                switch move {
                case .dwell: continue
                case .rapid(let p):
                    // The post retracts before a toolpath's first rapid, so an unknown start is fine.
                    if let s = pos {
                        check.rapid(from: s, to: p, xyMove: s.xy.distance(to: p.xy) > check.eps, line: nil)
                    } else {
                        check.visit(p, line: nil)
                    }
                case .linear(let p, let feed):
                    check.feedMove(from: pos, path: [p], feed: feed, spindleOn: true, line: nil)
                case .arcCW(let p, let c, let feed), .arcCCW(let p, let c, let feed):
                    let path = pos.map {
                        ArcGeometry.points(from: $0, to: p, center: c, clockwise: isCW(move), tolerance: check.eps)
                    } ?? [p]
                    check.feedMove(from: pos, path: path, feed: feed, spindleOn: true, line: nil)
                }
                pos = move.target ?? pos
            }
        }
        check.finish()
        return check.issues.issues
    }

    private func isCW(_ m: Move) -> Bool { if case .arcCW = m { return true } else { return false } }

    // MARK: G-code

    public func validate(gcode: String) -> [GCodeIssue] {
        let parsed = GCodeParser.parse(gcode)
        var gUnits: LengthUnit?
        var check = MotionChecker(profile: profile, job: job, jobUnits: units, units: profile.units)
        var carried = IssueCollector()
        for g in parsed.garbage {
            carried.add("garbage", .warning, line: g.line, "Unrecognised text '\(g.text)'")
        }
        var absolute = true
        var motion: Int?
        var x: Double?, y: Double?, z: Double?
        var feed: Double?
        var spindleOn = false
        var sawEnd = false

        for b in parsed.blocks {
            var nonMotion = false
            for g in b.values("G") {
                switch g {
                case 20, 21:
                    let u: LengthUnit = g == 20 ? .inch : .millimeter
                    if u != profile.units {
                        carried.add("units-mismatch", .warning, line: b.line,
                                    "Program units \(u.abbreviation) differ from the profile's \(profile.units.abbreviation)")
                    }
                    if u != (gUnits ?? profile.units) {
                        // Restart the checker in the new units, keeping what it found so far.
                        let old = check.issues
                        let f = (gUnits ?? profile.units).factor(to: u)
                        x = x.map { $0 * f }; y = y.map { $0 * f }; z = z.map { $0 * f }
                        feed = feed.map { $0 * f }
                        check = MotionChecker(profile: profile, job: job, jobUnits: units, units: u)
                        check.issues = old
                    }
                    gUnits = u
                case 90: absolute = true
                case 91:
                    absolute = false
                    carried.add("incremental", .warning, line: b.line, "Incremental positioning (G91) in program")
                case 0, 1, 2, 3: motion = Int(g)
                case 4, 10, 28, 30, 53, 92: nonMotion = true
                default: break
                }
            }
            for m in b.values("M") {
                switch m {
                case 3, 4: spindleOn = true
                case 5: spindleOn = false
                case 2, 30: sawEnd = true
                default: break
                }
            }
            if let s = b.value("S"), s > 0 || b.has("M", 3) || b.has("M", 4) {
                check.rpm(s, min: profile.minRPM, max: profile.maxRPM, line: b.line)
            }
            if let f = b.value("F") { feed = f }

            let bx = b.value("X"), by = b.value("Y"), bz = b.value("Z")
            guard !nonMotion, bx != nil || by != nil || bz != nil else { continue }
            guard let m = motion else {
                carried.add("no-motion-mode", .warning, line: b.line, "Axis words without a motion mode (G0/G1/G2/G3)")
                continue
            }
            func resolve(_ v: Double?, _ cur: Double?) -> Double? {
                guard let v else { return cur }
                return absolute ? v : (cur ?? 0) + v
            }
            let tx = resolve(bx, x), ty = resolve(by, y), tz = resolve(bz, z)
            let xyKnown = x != nil && y != nil
            let start: Vec3? = z.map { Vec3(x ?? tx ?? 0, y ?? ty ?? 0, $0) }
            let target = Vec3(tx ?? 0, ty ?? 0, tz ?? z ?? check.safeZ)

            switch m {
            case 0:
                let xyMove = (bx != nil || by != nil)
                    && (!xyKnown || Vec2(x ?? 0, y ?? 0).distance(to: target.xy) > check.eps)
                check.rapid(from: start, to: target, xyMove: xyMove, line: b.line)
            case 1:
                check.feedMove(from: start, path: [target], feed: feed, spindleOn: spindleOn, line: b.line)
            default:
                var path = [target]
                if let s = start, xyKnown {
                    let i = b.value("I"), j = b.value("J")
                    if i == nil && j == nil {
                        if b.value("R") == nil {
                            check.issues.add("arc-no-centre", .error, line: b.line, "Arc without I/J or R")
                        }
                    } else {
                        let c = profile.arcOutput == .absoluteIJ
                            ? Vec2(i ?? s.x, j ?? s.y)
                            : Vec2(s.x + (i ?? 0), s.y + (j ?? 0))
                        let r0 = s.xy.distance(to: c), r1 = target.xy.distance(to: c)
                        if abs(r0 - r1) > check.eps * 2 {
                            check.issues.add("arc-radius", .error, line: b.line,
                                             "Arc start/end radii differ (\(NumberFormat.compact(r0, maxDecimals: 4)) vs \(NumberFormat.compact(r1, maxDecimals: 4)))")
                        }
                        path = ArcGeometry.points(from: s, to: target, center: c, clockwise: m == 2,
                                                  tolerance: check.eps)
                    }
                }
                check.feedMove(from: start, path: path, feed: feed, spindleOn: spindleOn, line: b.line)
            }
            x = tx ?? x; y = ty ?? y; z = tz ?? z
        }
        check.finish()

        if gUnits == nil {
            carried.add("no-units", .warning, line: nil, "Program never sets units (G20/G21)")
        }
        if !sawEnd {
            carried.add("no-end", .warning, line: nil, "Program does not end with M30/M2")
        }
        var all = check.issues
        all.merge(carried)
        return all.issues
    }
}
