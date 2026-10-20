import CADCore
import Foundation

/// THE single place that maps material-frame geometry to machine coordinates.
///
/// * XY: document geometry has (0,0) at the material's lower-left; machine XY is relative to
///   `job.xyOrigin` (corner or centre).
/// * Z: generators think in "depth below material top" (positive = into the material).
///   - `.materialTop`:  machineZ = -depth            (top = 0, bottom = -thickness)
///   - `.spoilboard`:   machineZ = thickness - depth (top = thickness, bottom = 0)
public struct MachineCoordinates: Hashable, Sendable {
    public var job: JobSetup

    public init(job: JobSetup) { self.job = job }

    // MARK: Z

    /// Machine Z for a point `depth` below the material top.
    public func z(depth: Double) -> Double {
        switch job.zZero {
        case .materialTop: return -depth
        case .spoilboard: return job.thickness - depth
        }
    }

    /// Machine Z for a point `height` above the material top.
    public func z(aboveTop height: Double) -> Double { z(depth: -height) }

    /// Inverse of `z(depth:)`.
    public func depth(ofMachineZ machineZ: Double) -> Double {
        switch job.zZero {
        case .materialTop: return -machineZ
        case .spoilboard: return job.thickness - machineZ
        }
    }

    public var materialTopZ: Double { z(depth: 0) }
    public var materialBottomZ: Double { z(depth: job.thickness) }
    /// Rapid clearance plane.
    public var safeZ: Double { z(aboveTop: job.safeZ) }
    /// Start/end parking height.
    public var homeZ: Double { z(aboveTop: job.homeZ) }

    // MARK: XY

    public func machineXY(_ p: Vec2) -> Vec2 { p - job.originInMaterialFrame }
    public func materialXY(fromMachine p: Vec2) -> Vec2 { p + job.originInMaterialFrame }

    /// Machine position for material-frame `p` at `depth` below the top.
    public func machine(_ p: Vec2, depth: Double) -> Vec3 { Vec3(machineXY(p), z: z(depth: depth)) }

    /// Machine position for material-frame `p` at the safe Z plane.
    public func machineAtSafeZ(_ p: Vec2) -> Vec3 { Vec3(machineXY(p), z: safeZ) }

    /// Material-frame XY and depth for a machine position (used by preview/simulation).
    public func material(fromMachine p: Vec3) -> (xy: Vec2, depth: Double) {
        (materialXY(fromMachine: p.xy), depth(ofMachineZ: p.z))
    }
}
