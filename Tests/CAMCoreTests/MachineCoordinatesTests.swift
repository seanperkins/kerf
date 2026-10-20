import CADCore
import Foundation
import Testing
@testable import CAMCore

@Test func zMappingMaterialTop() {
    let c = MachineCoordinates(job: JobSetup(thickness: 0.75, zZero: .materialTop, safeZ: 0.2))
    #expect(c.z(depth: 0.25) == -0.25)
    #expect(c.materialTopZ == 0)
    #expect(c.materialBottomZ == -0.75)
    #expect(c.safeZ == 0.2)
    #expect(c.depth(ofMachineZ: -0.25) == 0.25)
}

@Test func zMappingSpoilboard() {
    let c = MachineCoordinates(job: JobSetup(thickness: 0.75, zZero: .spoilboard, safeZ: 0.2))
    #expect(c.z(depth: 0.25) == 0.5)
    #expect(c.materialTopZ == 0.75)
    #expect(c.materialBottomZ == 0)
    #expect(abs(c.safeZ - 0.95) < 1e-12)
    #expect(c.depth(ofMachineZ: 0.5) == 0.25)
}

@Test func xyOriginMapping() {
    var job = JobSetup(width: 24, height: 18)
    job.xyOrigin = .center
    let c = MachineCoordinates(job: job)
    #expect(c.machineXY(Vec2(12, 9)) == .zero)
    #expect(c.materialXY(fromMachine: Vec2(-12, -9)) == .zero)
    job.xyOrigin = .upperRight
    #expect(MachineCoordinates(job: job).machineXY(Vec2(0, 0)) == Vec2(-24, -18))
}

@Test func passDepthsAreEvenAndBounded() {
    let d = DepthSettings(startDepth: 0, cutDepth: 0.75, passDepth: 0.2)
    let passes = d.passDepths(toolStepdown: 1)
    #expect(passes.count == 4)
    #expect(abs(passes.last! - 0.75) < 1e-12)
    let withFinal = DepthSettings(startDepth: 0, cutDepth: 0.5, passDepth: 0.25, finalPassDepth: 0.02)
    #expect(withFinal.passDepths(toolStepdown: 1).suffix(2).map { ($0 * 1000).rounded() } == [480, 500])
}

@Test func projectRoundTripsWithOperations() throws {
    let doc = Document()
    let tool = ToolLibrary.seeded.tools[0]
    let op = AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "Cut out", toolID: tool.id)))
    let project = KerfProject(document: doc, operations: [op, .pocket(PocketOperation(setup: OperationSetup(name: "P", toolID: tool.id)))],
                              tools: [tool], postProfileID: "avid-pro6096-mach4-inch")
    let back = try KerfProject.decode(from: project.encoded())
    #expect(back == project)
    #expect(back.operations.map(\.kind) == [.profile, .pocket])
}

@Test func stubOperationsReportNotImplemented() {
    let ctx = CAMContext(document: Document(), tools: .seeded)
    let op = VCarveOperation(setup: OperationSetup(name: "V", toolID: ToolLibrary.seeded.tools[5].id))
    #expect(throws: CAMError.self) { try op.generate(in: ctx) }
}
