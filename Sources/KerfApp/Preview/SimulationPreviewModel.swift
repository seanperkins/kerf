// Drives the 3D preview: background simulation, play/scrub state. Owned by preview.
import CADCore
import CAMCore
import Foundation
import SwiftUI

/// One rendered simulation state.
struct SimulationFrame: Sendable {
    var mesh: HeightfieldMesh
    /// Cutter tip in the material frame (z = -depth) and its toolpath index.
    var tip: Vec3?
    var toolpathIndex: Int?
}

/// Owns the `SimulationPlayer` off the main thread.
actor SimulationEngine {
    private var player: SimulationPlayer
    private let thickness: Double
    private let coords: MachineCoordinates
    private let maxVertices: Int
    private var appearance: StockAppearance
    private let unitsPerInch: Double

    init(player: SimulationPlayer, job: JobSetup, maxVertices: Int, appearance: StockAppearance = .default,
         unitsPerInch: Double = 1) {
        self.player = player
        thickness = job.thickness
        coords = MachineCoordinates(job: job)
        self.maxVertices = maxVertices
        self.appearance = appearance
        self.unitsPerInch = unitsPerInch
    }

    func setAppearance(_ a: StockAppearance) { appearance = a }

    func frame(at time: TimeInterval) -> SimulationFrame {
        player.seek(to: time)
        let mesh = HeightfieldMesh(heightfield: player.heightfield, thickness: thickness,
                                   maxVertices: maxVertices, appearance: appearance, unitsPerInch: unitsPerInch)
        guard let pos = player.timeline.toolPosition(at: time) else {
            return SimulationFrame(mesh: mesh)
        }
        let m = coords.material(fromMachine: pos.point)
        return SimulationFrame(mesh: mesh, tip: Vec3(m.xy, z: -m.depth), toolpathIndex: pos.toolpathIndex)
    }
}

enum PlaybackSpeed: Hashable, CaseIterable, Identifiable {
    case realTime, x10, x50, x250, fit20s

    var id: Self { self }

    var label: String {
        switch self {
        case .realTime: return "1x"
        case .x10: return "10x"
        case .x50: return "50x"
        case .x250: return "250x"
        case .fit20s: return "Fit (20 s)"
        }
    }

    func multiplier(totalTime: TimeInterval) -> Double {
        switch self {
        case .realTime: return 1
        case .x10: return 10
        case .x50: return 50
        case .x250: return 250
        case .fit20s: return max(1, totalTime / 20)
        }
    }
}

@MainActor
final class SimulationPreviewModel: ObservableObject {
    @Published var time: TimeInterval = 0 { didSet { if time != oldValue { requestFrame() } } }
    @Published private(set) var totalTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published var speed: PlaybackSpeed = .fit20s
    @Published var showTool = true { didSet { applyTool() } }
    @Published private(set) var activeToolpathName: String?
    @Published private(set) var cellSize: Double = 0
    @Published private(set) var isBusy = false

    let stockScene = StockScene()
    private var engine: SimulationEngine?
    private var toolpaths: [Toolpath] = []
    private var shapes: [ToolShape] = []
    private var pendingTime: TimeInterval?
    private var rendering = false
    private var playTask: Task<Void, Never>?
    private var lastFrame: SimulationFrame?
    private var configuredKey: Int?
    private(set) var appearance = StockAppearance.default

    /// Recolours the stock without re-simulating.
    func setAppearance(_ a: StockAppearance) {
        guard a != appearance else { return }
        appearance = a
        stockScene.shininess = a.shininess
        guard let engine else { return }
        Task { [weak self] in
            await engine.setAppearance(a)
            self?.requestFrame()
        }
    }

    /// Rebuilds the simulation when the inputs change (cheap no-op otherwise).
    func configure(job: JobSetup, toolpaths: [Toolpath], rapidRate: Double, units: LengthUnit,
                   timeSettings: TimeEstimateSettings = TimeEstimateSettings()) {
        let motion = timeSettings.motion(units: units)
        var hasher = Hasher()
        hasher.combine(job); hasher.combine(toolpaths); hasher.combine(rapidRate)
        hasher.combine(motion); hasher.combine(timeSettings.toolChangeSeconds)
        let key = hasher.finalize()
        guard key != configuredKey else { return }
        configuredKey = key
        pause()
        self.toolpaths = toolpaths
        shapes = toolpaths.map { ToolShape(tool: $0.tool) }
        let minCell = units == .inch ? 0.004 : 0.1
        let cell = Heightfield.automaticCellSize(width: job.width, height: job.height,
                                                 targetCells: 800_000, minimum: minCell)
        cellSize = cell
        let player = SimulationPlayer(job: job, toolpaths: toolpaths, rapidRate: rapidRate, cellSize: cell,
                                      toolChangeSeconds: timeSettings.toolChangeSeconds, motion: motion)
        totalTime = player.timeline.totalTime
        engine = SimulationEngine(player: player, job: job, maxVertices: 200_000, appearance: appearance,
                                  unitsPerInch: LengthUnit.inch.factor(to: units))
        stockScene.configure(job: job)
        // Show the finished result by default; scrub back to watch it being cut.
        if time == totalTime { requestFrame() } else { time = totalTime }
    }

    var progress: Double {
        get { totalTime > 0 ? time / totalTime : 0 }
        set { time = min(max(newValue, 0), 1) * totalTime }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard totalTime > 0 else { return }
        if time >= totalTime { time = 0 }
        isPlaying = true
        playTask?.cancel()
        playTask = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                guard let self, self.isPlaying else { return }
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                let next = self.time + dt * self.speed.multiplier(totalTime: self.totalTime)
                if next >= self.totalTime {
                    self.time = self.totalTime
                    self.pause()
                    return
                }
                self.time = next
            }
        }
    }

    func pause() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    func rewind() { pause(); time = 0 }
    func jumpToEnd() { pause(); time = totalTime }
    func resetCamera() { stockScene.resetCamera() }

    private func requestFrame() {
        guard engine != nil else { return }
        if rendering { pendingTime = time; return }
        render(at: time)
    }

    private func render(at t: TimeInterval) {
        guard let engine else { return }
        rendering = true
        isBusy = true
        Task { [weak self] in
            let frame = await engine.frame(at: t)
            guard let self else { return }
            self.apply(frame)
            self.rendering = false
            if let next = self.pendingTime {
                self.pendingTime = nil
                self.render(at: next)
            } else {
                self.isBusy = false
            }
        }
    }

    private func apply(_ frame: SimulationFrame) {
        lastFrame = frame
        stockScene.updateStock(frame.mesh)
        activeToolpathName = frame.toolpathIndex.flatMap { toolpaths.indices.contains($0) ? toolpaths[$0].name : nil }
        applyTool()
    }

    private func applyTool() {
        guard showTool, let f = lastFrame, let i = f.toolpathIndex, shapes.indices.contains(i) else {
            stockScene.updateTool(tip: nil, shape: nil)
            return
        }
        stockScene.updateTool(tip: f.tip, shape: shapes[i])
    }
}
