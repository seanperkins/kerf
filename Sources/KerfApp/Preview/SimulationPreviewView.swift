// 3D material-removal preview with play/scrub controls. Owned by the preview workstream.
import AppKit
import CADCore
import CAMCore
import PostCore
import SceneKit
import SwiftUI

/// SCNView wrapper with built-in orbit (drag), zoom (scroll/pinch) and pan (option-drag).
struct StockSceneView: NSViewRepresentable {
    let stockScene: StockScene
    /// When set, a click on the stock reports its material-frame point (z = -depth).
    var onPick: ((Vec3) -> Void)? = nil

    final class Coordinator: NSObject {
        var parent: StockSceneView
        weak var view: SCNView?
        init(_ parent: StockSceneView) { self.parent = parent }

        @MainActor @objc func clicked(_ g: NSClickGestureRecognizer) {
            guard let view, let onPick = parent.onPick else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue,
                                                   .ignoreHiddenNodes: true])
            guard let hit = hits.first(where: { parent.stockScene.isStock($0.node) }) else { return }
            onPick(parent.stockScene.materialPoint(fromWorld: hit.worldCoordinates))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        context.coordinator.view = v
        stockScene.attachedView = v
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        v.addGestureRecognizer(click)
        v.scene = stockScene.scene
        v.pointOfView = stockScene.cameraNode
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        v.autoenablesDefaultLighting = false
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.parent = self
        if v.scene !== stockScene.scene { v.scene = stockScene.scene }
        v.defaultCameraController.target = stockScene.center
        v.defaultCameraController.worldUp = SCNVector3(0, 1, 0)
    }
}

/// 3D simulation of the given toolpaths on the job's stock.
/// `rapidRate` is in document units per minute (see `rapidRate(for:units:)`).
struct SimulationPreviewView: View {
    var job: JobSetup
    var units: LengthUnit
    var toolpaths: [Toolpath]
    var rapidRate: Double
    /// When set, a picker chooses which toolpaths are simulated (all / visible / selected).
    var scope: Binding<PreviewScope>? = nil
    var emptyMessage = "No toolpaths to simulate"
    /// Used for the default file name when saving an image.
    var documentName = "Untitled"

    @StateObject private var model = SimulationPreviewModel()
    @ObservedObject private var timeStore = TimeEstimateStore.shared
    @State private var showTimeSettings = false
    @ObservedObject private var appearanceStore = PreviewAppearanceStore.shared
    @State private var showAppearance = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                StockSceneView(stockScene: model.stockScene, onPick: pickHandler)
                infoBadge.padding(8)
                if model.isMeasuring {
                    measureBadge.padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            Divider()
            controls.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .onAppear(perform: configure)
        .onChange(of: toolpaths) { _, _ in configure() }
        .onChange(of: job) { _, _ in configure() }
        .onChange(of: rapidRate) { _, _ in configure() }
        .onChange(of: timeStore.settings) { _, _ in configure() }
        .onChange(of: appearanceStore.settings) { _, s in model.setAppearance(s.appearance) }
    }

    private var pickHandler: ((Vec3) -> Void)? {
        guard model.isMeasuring else { return nil }
        let m = model
        return { p in m.pick(p) }
    }

    private func configure() {
        model.setAppearance(appearanceStore.settings.appearance)
        model.configure(job: job, toolpaths: toolpaths, rapidRate: rapidRate, units: units,
                        timeSettings: timeStore.settings)
    }

    private var infoBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            if toolpaths.isEmpty {
                Text(emptyMessage).font(.callout.bold())
            } else {
                Text(model.activeToolpathName ?? "—").font(.callout.bold())
                Text("Estimated time \(MachiningTimeEstimator.format(model.totalTime))")
                Text(String(format: "Resolution %.3g %@", model.cellSize, units.abbreviation))
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    private var measureBadge: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.measurement.lines(units: units, thickness: job.thickness), id: \.self) { Text($0) }
            }
            .font(.caption.monospacedDigit())
            if !model.measurement.isEmpty {
                Button("Clear") { model.clearMeasurement() }.controlSize(.small)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if let scope {
                Picker("Simulate", selection: scope) {
                    ForEach(PreviewScope.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                .help("Which toolpaths to simulate")
            }
            playbackControls
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Button(action: model.rewind) { Image(systemName: "backward.end.fill") }
                .help("Back to start")
            Button(action: model.togglePlay) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause" : "Play")
            Button(action: model.jumpToEnd) { Image(systemName: "forward.end.fill") }
                .help("Show finished result")
            Slider(value: Binding(get: { model.progress }, set: { model.pause(); model.progress = $0 }),
                   in: 0...1)
                .frame(minWidth: 160)
            Text("\(MachiningTimeEstimator.format(model.time)) / \(MachiningTimeEstimator.format(model.totalTime))")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 110, alignment: .trailing)
            Picker("Speed", selection: $model.speed) {
                ForEach(PlaybackSpeed.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            Toggle("Tool", isOn: $model.showTool).toggleStyle(.checkbox)
            Button { PreviewImageExport.runSavePanel(stockScene: model.stockScene, documentName: documentName) } label: {
                Image(systemName: "camera")
            }
            .help("Save the preview as an image…")
            Toggle(isOn: $model.isMeasuring) { Image(systemName: "ruler") }
                .toggleStyle(.button)
                .help("Measure: click the stock for a depth, click again for a distance")
            Button { showAppearance.toggle() } label: { Image(systemName: "paintpalette") }
                .help("Material appearance")
                .popover(isPresented: $showAppearance) { PreviewAppearancePopover(store: appearanceStore) }
            Button { showTimeSettings.toggle() } label: { Image(systemName: "stopwatch") }
                .help("Time estimate settings (acceleration, calibration)")
                .popover(isPresented: $showTimeSettings) {
                    TimeEstimatePopover(store: timeStore, toolpaths: toolpaths, rapidRate: rapidRate, units: units)
                }
            Button(action: model.resetCamera) { Image(systemName: "camera.metering.center.weighted") }
                .help("Reset view")
            if model.isBusy { ProgressView().controlSize(.small) }
        }
        .disabled(toolpaths.isEmpty)
    }

    /// Profile rapid rate converted to `units` per minute.
    static func rapidRate(for profile: PostProfile, units: LengthUnit) -> Double {
        profile.units.convert(profile.rapidRate, to: units)
    }
}

/// Preview panel with 2D overlay and 3D simulation tabs, for the app shell to embed.
struct ToolpathPreviewPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case twoD = "2D Toolpaths", threeD = "3D Simulation"
        var id: Self { self }
    }

    var document: Document
    var toolpaths: [Toolpath]
    var postProfile: PostProfile = BuiltInPosts.avidMach4Inch
    @State private var mode: Mode = .threeD
    @State private var showRapids = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
                Spacer()
                if mode == .twoD { Toggle("Rapids", isOn: $showRapids).toggleStyle(.checkbox) }
            }
            .padding(8)
            Divider()
            switch mode {
            case .twoD:
                ToolpathOverlayView(document: document, toolpaths: toolpaths, showRapids: showRapids)
            case .threeD:
                SimulationPreviewView(
                    job: document.job, units: document.units, toolpaths: toolpaths,
                    rapidRate: SimulationPreviewView.rapidRate(for: postProfile, units: document.units))
            }
        }
    }
}
