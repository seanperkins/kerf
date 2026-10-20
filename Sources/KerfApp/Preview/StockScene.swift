// SceneKit scene for the 3D material-removal preview. Owned by the preview workstream.
import AppKit
import CADCore
import CAMCore
import SceneKit

/// Owns the SceneKit scene: lit stock mesh, cutter marker and an orbit camera.
/// The content node uses the material frame with Z up (top at z = 0); it is rotated so that
/// material Z becomes SceneKit's +Y.
@MainActor
final class StockScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let content = SCNNode()
    private let stockNode = SCNNode()
    private let toolNode = SCNNode()
    private let measureNode = SCNNode()
    private(set) var job = JobSetup()
    /// Specular strength of the stock (0...1), from the material appearance.
    var shininess = 0.15
    /// The on-screen view (for its camera when saving an image).
    weak var attachedView: SCNView?

    init() {
        scene.background.contents = NSColor(calibratedWhite: 0.16, alpha: 1)
        content.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(content)
        content.addChildNode(stockNode)
        content.addChildNode(toolNode)
        content.addChildNode(measureNode)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 10_000
        camera.fieldOfView = 40
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 800
        key.light?.castsShadow = false
        key.eulerAngles = SCNVector3(-1.0, 0.9, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 300
        fill.eulerAngles = SCNVector3(-0.4, -2.4, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 160
        scene.rootNode.addChildNode(ambient)
    }

    /// Material centre in scene coordinates (orbit target).
    var center: SCNVector3 {
        SCNVector3(job.width / 2, -job.thickness / 2, -job.height / 2)
    }

    /// Resets the camera to a three-quarter view of the whole stock.
    func configure(job: JobSetup) {
        self.job = job
        resetCamera()
    }

    func resetCamera() {
        let size = max(job.width, job.height, job.thickness * 4)
        let c = center
        cameraNode.position = SCNVector3(c.x, c.y + CGFloat(size) * 0.9, c.z + CGFloat(size) * 1.1)
        cameraNode.look(at: c, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    func updateStock(_ mesh: HeightfieldMesh) {
        stockNode.geometry = Self.geometry(from: mesh, shininess: shininess)
    }

    /// Shows the cutter with its tip at material-frame `tip` (depth below top as negative z).
    func updateTool(tip: Vec3?, shape: ToolShape?) {
        guard let tip, let shape else { toolNode.isHidden = true; return }
        toolNode.isHidden = false
        if toolNode.name != Self.key(shape) {
            toolNode.childNodes.forEach { $0.removeFromParentNode() }
            toolNode.addChildNode(Self.cutterNode(shape, units: job))
            toolNode.name = Self.key(shape)
        }
        toolNode.position = SCNVector3(tip.x, tip.y, tip.z)
    }

    private static func key(_ s: ToolShape) -> String { "\(s)" }

    // MARK: Measuring

    /// True for hits on the stock mesh (not the cutter or markers).
    func isStock(_ node: SCNNode) -> Bool { node === stockNode }

    /// Material-frame point (z = -depth) for a scene (world) position.
    func materialPoint(fromWorld p: SCNVector3) -> Vec3 {
        let l = content.convertPosition(p, from: nil)
        return Vec3(Double(l.x), Double(l.y), Double(l.z))
    }

    /// Marker spheres at material-frame `points` and a line between the first two.
    func showMeasurement(_ points: [Vec3]) {
        measureNode.childNodes.forEach { $0.removeFromParentNode() }
        guard !points.isEmpty else { return }
        let size = CGFloat(max(job.width, job.height, 1e-3)) * 0.004
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.systemYellow
        mat.emission.contents = NSColor.systemYellow.withAlphaComponent(0.6)
        mat.lightingModel = .constant
        mat.readsFromDepthBuffer = false
        for p in points {
            let s = SCNSphere(radius: size)
            s.materials = [mat]
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(p.x, p.y, p.z)
            n.renderingOrder = 10
            measureNode.addChildNode(n)
        }
        if points.count == 2 {
            let a = points[0], b = points[1]
            let src = SCNGeometrySource(vertices: [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z)])
            let el = SCNGeometryElement(indices: [UInt32(0), UInt32(1)], primitiveType: .line)
            let g = SCNGeometry(sources: [src], elements: [el])
            g.materials = [mat]
            let n = SCNNode(geometry: g)
            n.renderingOrder = 10
            measureNode.addChildNode(n)
        }
    }

    private static func cutterNode(_ shape: ToolShape, units job: JobSetup) -> SCNNode {
        let r = CGFloat(shape.radius)
        let shankLength = CGFloat(max(job.thickness * 2, shape.radius * 8))
        let steel = SCNMaterial()
        steel.diffuse.contents = NSColor(calibratedWhite: 0.78, alpha: 1)
        steel.specular.contents = NSColor.white
        steel.lightingModel = .blinn

        // Built along +Y with the tip at the origin, then rotated so +Y becomes material +Z.
        let root = SCNNode()
        root.eulerAngles.x = .pi / 2
        var shankBase: CGFloat = 0
        switch shape {
        case .flat:
            break
        case .ball:
            let s = SCNSphere(radius: r)
            s.materials = [steel]
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(0, r, 0)
            root.addChildNode(n)
            shankBase = r
        case .vee(_, let tip, let half):
            let h = CGFloat((shape.radius - tip) / tan(half))
            let cone = SCNCone(topRadius: r, bottomRadius: CGFloat(tip), height: max(h, 1e-4))
            cone.materials = [steel]
            let n = SCNNode(geometry: cone)
            n.position = SCNVector3(0, h / 2, 0)
            root.addChildNode(n)
            shankBase = h
        case .shaped:
            // Stack of frustums following the outline (lowest height at each radius).
            let n = 24
            var prev: (r: Double, h: Double) = (0, shape.heightAboveTip(atRadius: 0) ?? 0)
            for k in 1...n {
                let rk = shape.radius * Double(k) / Double(n)
                let hk = shape.heightAboveTip(atRadius: rk) ?? prev.h
                let dh = hk - prev.h
                if dh > 1e-6 {
                    let f = SCNCone(topRadius: CGFloat(rk), bottomRadius: CGFloat(prev.r), height: CGFloat(dh))
                    f.materials = [steel]
                    let node = SCNNode(geometry: f)
                    node.position = SCNVector3(0, CGFloat(prev.h + dh / 2), 0)
                    root.addChildNode(node)
                }
                prev = (rk, hk)
            }
            shankBase = CGFloat(prev.h)
        }
        let shank = SCNCylinder(radius: r, height: shankLength)
        shank.materials = [steel]
        let sn = SCNNode(geometry: shank)
        sn.position = SCNVector3(0, shankBase + shankLength / 2, 0)
        root.addChildNode(sn)
        return root
    }

    static func geometry(from mesh: HeightfieldMesh, shininess: Double = 0.15) -> SCNGeometry {
        let n = mesh.vertexCount
        func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
            let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data, semantic: semantic, vectorCount: n,
                                     usesFloatComponents: true, componentsPerVector: 3,
                                     bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                     dataStride: 3 * MemoryLayout<Float>.size)
        }
        let indexData = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles,
                                         primitiveCount: mesh.triangleCount,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let geo = SCNGeometry(sources: [source(mesh.positions, .vertex), source(mesh.normals, .normal),
                                        source(mesh.colors, .color)],
                              elements: [element])
        let m = SCNMaterial()
        m.diffuse.contents = NSColor.white // multiplied by the vertex colours
        m.specular.contents = NSColor(calibratedWhite: CGFloat(min(max(shininess, 0), 1)), alpha: 1)
        m.shininess = CGFloat(0.1 + 0.6 * min(max(shininess, 0), 1))
        m.lightingModel = .blinn
        m.isDoubleSided = true
        geo.materials = [m]
        return geo
    }
}
