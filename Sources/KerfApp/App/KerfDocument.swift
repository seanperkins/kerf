import CADCore
import CAMCore
import Combine
import Foundation
import PostCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Native project file (JSON). Declared in Info.plist by scripts/bundle.sh.
    static let kerfProject = UTType(exportedAs: "com.seanperkins.kerf.project", conformingTo: .json)
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case design = "Design", toolpaths = "Toolpaths"
    var id: String { rawValue }
}

enum CenterMode: String, CaseIterable, Identifiable {
    case design2D = "2D", preview3D = "3D"
    /// 2D design and 3D preview side by side.
    case split = "2D | 3D"
    var id: String { rawValue }

    var showsDesign: Bool { self != .preview3D }
    var showsPreview: Bool { self != .design2D }
}

enum DocumentSheet: Identifiable, Equatable {
    case jobSetup
    case exportGCode(GCodeExportScope)
    case offset
    case inlayWizard
    case placeModel(ModelPlacementForm)
    case saveAllToolpaths
    case validation
    case keepOutZones
    case nesting
    case fixtures
    case tiling
    case partLabels
    case variables
    case productionPlates
    /// Drawing-tool dialogs (dog-bones, arrays, validator, …).
    case drawing(DrawingSheet)
    /// File / IO dialogs (model parts, job notes, clipart…), see `IOSheets.swift`.
    case io(IOSheet)

    var id: String {
        switch self {
        case .jobSetup: return "job"
        case .exportGCode: return "export"
        case .offset: return "offset"
        case .inlayWizard: return "inlay"
        case .placeModel(let f): return "place-\(f.modelID)"
        case .saveAllToolpaths: return "saveAll"
        case .validation: return "validation"
        case .keepOutZones: return "keepOut"
        case .nesting: return "nesting"
        case .fixtures: return "fixtures"
        case .tiling: return "tiling"
        case .partLabels: return "partLabels"
        case .variables: return "variables"
        case .productionPlates: return "productionPlates"
        case .drawing(let d): return "drawing-\(d.rawValue)"
        case .io(let s): return "io-\(s.id)"
        }
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Requests from menus/toolbar to the canvas (zoom etc.). `serial` makes repeats observable.
struct CanvasRequest: Equatable {
    enum Kind: Equatable { case fit, zoomIn, zoomOut, fitSelection }
    var kind: Kind
    var serial: Int
}

/// One open `.kerf` document: the project plus per-window editing state. All project edits go
/// through `perform`, which registers snapshot-based undo with the window's undo manager.
final class KerfDocument: ReferenceFileDocument {
    typealias Snapshot = KerfProject

    static var readableContentTypes: [UTType] { [.kerfProject] }
    static var writableContentTypes: [UTType] { [.kerfProject] }

    @Published private(set) var project: KerfProject
    /// Bumped whenever the design (not the operations) changes; toolpaths compare against it.
    @Published private(set) var designRevision = 0

    // Editing state (not saved).
    @Published var selection: Set<UUID> = []
    /// Selection order (first = primary, e.g. the shape others are subtracted from).
    private(set) var selectionOrder: [UUID] = []
    @Published var selectedOperationID: UUID?
    @Published var hiddenToolpaths: Set<UUID> = []
    /// Profile operation whose tabs the canvas is editing (click to add, drag to move).
    @Published var tabEditingOperationID: UUID?
    /// Envelope distortion with draggable corners in progress on the canvas.
    @Published var envelopeEdit: EnvelopeEdit?
    /// Live text whose letters are being dragged on the canvas (interactive kerning).
    @Published var kerningShapeID: UUID?
    /// STL imports waiting for the placement dialog (shown one after another).
    var pendingPlacements: [ModelPlacementForm] = []
    var deferredAlert: AlertMessage?
    /// Expressions typed into numeric fields, linked to parameters on the next edit (io).
    let expressionRecorder = ExpressionRecorder()
    @Published var showToolpaths = true
    @Published var results: [UUID: ToolpathResult] = [:]
    /// The last job summary, rebuilt only when what it is made from changes (`jobSummary(groupByTool:settings:)`).
    let jobSummaryMemo = JobSummary.Memo()
    @Published var calculating: Set<UUID> = []
    /// Operations asked to recalculate while already calculating.
    private var pendingRecalculation: Set<UUID> = []
    /// Monotonic stamp per calculation; a result is stored only if newer than the current one.
    private var generationCounter = 0
    private var resultGeneration: [UUID: Int] = [:]
    @Published var activeTool: CanvasTool = .select {
        didSet { if activeTool != .nodeEdit { nodeSelection = [] } }
    }
    /// Selected anchors while the node-edit tool is active.
    @Published var nodeSelection: Set<NodeRef> = []
    /// Snap to nodes, midpoints and centres of other shapes (before falling back to the grid).
    @Published var snapToObjects = true
    @Published var drawingOptions = DrawingOptions()
    @Published var snapToGrid = true
    @Published var sidebarTab: SidebarTab = .design
    @Published var centerMode: CenterMode = .design2D
    /// Side shown and edited in a two-sided job.
    @Published var activeSide: JobSide = .top
    @Published var sheet: DocumentSheet?
    @Published var alert: AlertMessage?
    @Published var canvasRequest = CanvasRequest(kind: .fit, serial: 0)
    /// Cursor position in document units (for the status bar).
    @Published var cursorPosition: Vec2?
    /// Problem locations circled on the canvas (vector validator); cleared by the user.
    @Published var highlightMarkers: [Vec2] = []
    /// Snap to guides (and, with object snapping, to horizontal/vertical lines through nodes).
    @Published var snapToGuides = true
    /// Last Measure-tool reading (shown on the canvas and in the inspector).
    @Published var measurement: Measurement?

    weak var undoManager: UndoManager?
    /// Where the document is saved (from the window's document configuration), for the Finder icon.
    var fileURL: URL?
    /// Bumped by every undoable change (including undo/redo).
    private var editSerial = 0
    /// The operation whose live edits are being merged into the current undo step.
    private var liveOperationEdit: (id: UUID, serial: Int)?
    let toolLibrary: ToolLibraryModel
    private var cancellables: Set<AnyCancellable> = []

    /// Identifies this window's crash-recovery copy.
    let recoveryID = UUID()
    /// The project as last opened or saved; unsaved changes = `project` differs from it.
    private(set) var lastSavedProject: KerfProject
    var needsRecovery: Bool { project != lastSavedProject }

    init(project: KerfProject, toolLibrary: ToolLibraryModel = .shared) {
        self.project = project
        self.lastSavedProject = project
        self.toolLibrary = toolLibrary
        toolLibrary.$revision.dropFirst().sink { [weak self] _ in self?.designRevision += 1 }.store(in: &cancellables)
        toolLibrary.$library.dropFirst().sink { [weak self] lib in self?.showToolNames(of: lib) }.store(in: &cancellables)
    }

    convenience init() {
        let prefs = PreferencesModel.shared.prefs
        self.init(project: prefs.newProject(machines: MachineCatalog.shared.machines,
                                            profiles: PostProfileCatalog.shared.profiles))
        applyWindowPreferences(prefs)
    }

    required convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(project: try KerfProject.decode(from: data))
        applyWindowPreferences(PreferencesModel.shared.prefs)
    }

    /// Per-window editing defaults from Preferences (snapping).
    func applyWindowPreferences(_ prefs: AppPreferences) {
        snapToGrid = prefs.snapToGrid
        snapToObjects = prefs.snapToObjects
    }

    func snapshot(contentType: UTType) throws -> KerfProject {
        // After a save, the next live toolpath edit opens a new undo step (re-dirtying the file).
        liveOperationEdit = nil
        lastSavedProject = project
        scheduleFileThumbnail()
        var p = project
        p.refreshToolSnapshot(from: toolLibrary.library)
        return p
    }

    func fileWrapper(snapshot: KerfProject, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: FileThumbnail.withQuickLookThumbnail(try snapshot.encoded(), for: snapshot.document))
    }

    // MARK: Undoable edits

    /// Applies `change` to a copy of the project; registers undo only if something changed.
    func perform(_ actionName: String, _ change: (inout KerfProject) -> Void) {
        var p = project
        change(&p)
        VariableLinks.reconcile(&p, old: project, pending: expressionRecorder.take())
        guard p != project else { return }
        replaceProject(p, actionName: actionName)
    }

    private func replaceProject(_ new: KerfProject, actionName: String) {
        editSerial += 1
        let old = project
        if old.document != new.document { designRevision += 1 }
        project = new
        undoManager?.registerUndo(withTarget: self) { doc in doc.replaceProject(old, actionName: actionName) }
        undoManager?.setActionName(actionName)
        pruneState()
    }

    private func pruneState() {
        let ids = Set(project.document.shapes.map(\.id))
        if !selection.isSubset(of: ids) { setSelection(selectionOrder.filter(ids.contains)) }
        let nodes = project.validNodes(nodeSelection)
        if nodes != nodeSelection { nodeSelection = nodes }
        let opIDs = Set(project.operations.map(\.id))
        if let sel = selectedOperationID, !opIDs.contains(sel) { selectedOperationID = nil }
        if let t = tabEditingOperationID, operation(t)?.profileTabs == nil { tabEditingOperationID = nil }
        results = results.filter { opIDs.contains($0.key) }
    }

    // MARK: Derived

    var document: Document { project.document }
    var units: LengthUnit { project.document.units }
    var mergedLibrary: ToolLibrary { project.mergedTools(with: toolLibrary.library) }

    /// The post profile with the job's machine limits applied (what validation and export use).
    var postProfile: PostProfile {
        effectiveProfile(id: project.postProfileID ?? PostProfileStore.defaultID(for: units))
    }

    /// The machine this job is set up for (nil = a custom post with its own limits).
    var machine: MachineDefinition? { MachineCatalog.shared.machine(for: project) }

    /// An error when the project's post profile is not installed on this Mac: `postProfile`
    /// then falls back to the default, which may be a different dialect and machine.
    var postProfileIssues: [GCodeIssue] {
        guard let id = project.postProfileID, !PostProfileCatalog.shared.profiles.contains(where: { $0.id == id })
        else { return [] }
        return [GCodeIssue(severity: .error,
                           message: "The project's post \"\(id)\" is not installed; \"\(postProfile.name)\" is shown instead. Pick a post before saving.")]
    }

    /// Post `id` with this job's machine limits applied.
    func effectiveProfile(id: String?) -> PostProfile {
        MachineResolver.effectiveProfile(PostProfileCatalog.shared.profile(id: id), machine: machine)
    }

    /// Profile rapid rate converted to document units per minute.
    var rapidRateInDocumentUnits: Double {
        postProfile.rapidRate * postProfile.units.factor(to: units)
    }

    func operation(_ id: UUID?) -> AnyOperation? {
        guard let id else { return nil }
        return project.operations.first { $0.id == id }
    }

    var selectedShapes: [Shape] { project.document.shapes(ids: selectionOrder) }

    // MARK: Selection

    func setSelection(_ ids: [UUID]) {
        var seen = Set<UUID>()
        selectionOrder = ids.filter { seen.insert($0).inserted }
        selection = Set(selectionOrder)
    }

    /// Selects a shape (and its group mates). Extending toggles the whole group.
    func select(_ id: UUID, extending: Bool) {
        let members = project.document.expandToGroups([id])
        if extending {
            if selection.contains(id) {
                let drop = Set(members)
                setSelection(selectionOrder.filter { !drop.contains($0) })
            } else {
                setSelection(selectionOrder + members)
            }
        } else {
            setSelection(members)
        }
    }

    func addToSelection(_ ids: [UUID]) { setSelection(selectionOrder + project.document.expandToGroups(ids)) }

    func selectAll() {
        setSelection(project.document.shapes.filter { project.isEditable($0) && isOnActiveSide($0) }.map(\.id))
    }

    func clearSelection() { setSelection([]) }

    // MARK: Shape edits

    func addShape(_ shape: Shape, actionName: String) {
        var s = shape
        if project.document.layer(id: s.layerID) == nil { s.layerID = currentLayerID }
        perform(actionName) { $0.document.add(s) }
        setSelection([s.id])
    }

    /// Layer new shapes go to: the layer of the primary selection, else the first unlocked visible one.
    var currentLayerID: UUID {
        if let first = selectedShapes.first { return first.layerID }
        let onSide = currentSheetLayers.filter { !isTwoSided || ($0.side ?? .top) == activeSide }
        return onSide.first { $0.isVisible && !$0.isLocked }?.id ?? onSide.first?.id ?? project.document.defaultLayerID
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        perform(ids.count == 1 ? "Delete Shape" : "Delete Shapes") { $0.deleteShapes(ids) }
    }

    func translateSelection(by d: Vec2, actionName: String = "Move") {
        guard !selection.isEmpty, d != .zero else { return }
        let ids = selection
        perform(actionName) { $0.transformShapes(ids, by: .translation(d)) }
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let shapes = selectedShapes
        var newIDs: [UUID] = []
        let g = project.document.gridSpacing, layer = currentLayerID
        perform("Duplicate") { newIDs = $0.paste(shapes, offset: Vec2(g, -g), fallbackLayer: layer) }
        setSelection(newIDs)
    }

    /// Pastes clipboard shapes (offset when the originals are still in the document).
    func pasteShapes(_ shapes: [Shape]) {
        guard !shapes.isEmpty else { return }
        let offset = ShapeClipboard.pasteOffset(for: shapes, existing: Set(project.document.shapes.map(\.id)),
                                                grid: project.document.gridSpacing)
        var newIDs: [UUID] = []
        let layer = currentLayerID
        perform("Paste") { newIDs = $0.paste(shapes, offset: offset, fallbackLayer: layer) }
        setSelection(newIDs)
    }

    func groupSelection() {
        let order = selectionOrder
        perform("Group") { _ = DesignCommands.group(order, in: &$0) }
    }

    func ungroupSelection() {
        let order = selectionOrder
        perform("Ungroup") { DesignCommands.ungroup(order, in: &$0) }
    }

    /// Applies `change` to the whole selection as one undoable step.
    func editSelection(_ actionName: String, _ change: @escaping (Set<UUID>, inout KerfProject) -> Void) {
        guard !selection.isEmpty else { return }
        let ids = selection
        perform(actionName) { change(ids, &$0) }
    }

    func transformSelection(by t: Transform2D, actionName: String) {
        editSelection(actionName) { ids, p in p.transformShapes(ids, by: t) }
    }

    // MARK: Node edits

    func moveSelectedNodes(by d: Vec2) {
        guard !nodeSelection.isEmpty, d != .zero else { return }
        let refs = nodeSelection, mirror = drawingOptions.nodeMirror
        perform("Move Nodes") { $0.moveNodes(refs, by: d, mirror: mirror) }
    }

    func deleteSelectedNodes() {
        guard !nodeSelection.isEmpty else { return }
        let refs = nodeSelection
        perform("Delete Nodes") { $0.deleteNodes(refs) }
        nodeSelection = []
    }

    func setSelectedNodes(smooth: Bool) {
        let refs = nodeSelection
        perform(smooth ? "Smooth Nodes" : "Corner Nodes") { $0.setNodes(refs, smooth: smooth) }
    }

    func convertSegmentsAfterSelectedNodes(toCurve: Bool) {
        let refs = nodeSelection
        perform(toCurve ? "Convert to Curve" : "Convert to Line") { $0.convertSegments(after: refs, toCurve: toCurve) }
    }

    func insertNodesAfterSelection() {
        let refs = nodeSelection
        var new: Set<NodeRef> = []
        perform("Insert Nodes") { new = $0.insertNodesAfter(refs) }
        nodeSelection = new
    }

    func breakAtSelectedNode() {
        guard nodeSelection.count == 1, let r = nodeSelection.first else { return }
        perform("Break Path") { _ = $0.editNodes(of: r.shapeID) { ShapeNodes.breakAt($0, r) } }
        nodeSelection = []
    }

    /// Replaces one shape (node drags, handle drags, inserts on the canvas).
    func replaceShape(_ shape: Shape, actionName: String) {
        perform(actionName) { p in p.editNodes(of: shape.id) { _ in shape } }
    }

    // MARK: Operations

    func addOperation(_ kind: OperationKind) {
        if kind == .inlay { sheet = .inlayWizard; return }
        if kind == .straightInlay { addStraightInlayPair(); return }
        guard let op = OperationFactory.make(kind: kind, project: project, library: mergedLibrary,
                                             shapeIDs: selectionOrder) else {
            alert = AlertMessage(title: "No 3D model",
                                 message: "Import an STL model (File > Import) before adding a 3D toolpath.")
            return
        }
        perform("New \(kind.displayName) Toolpath") { $0.upsertOperation(op) }
        sidebarTab = .toolpaths
        selectedOperationID = op.id
    }

    func updateOperation(_ op: AnyOperation) {
        perform("Edit Toolpath") { $0.upsertOperation(op) }
    }

    /// Live edit from the toolpath editor: committed immediately so Calculate All, export and
    /// save always see what the form shows. Consecutive edits of the same operation, with no
    /// other change (or save) in between, merge into one "Edit Toolpath" undo step.
    func updateOperationLive(_ op: AnyOperation) {
        guard operation(op.id) != nil else { return }  // deleted meanwhile: never resurrect it
        if let live = liveOperationEdit, live.id == op.id, live.serial == editSerial {
            var p = project
            p.upsertOperation(op)
            VariableLinks.reconcile(&p, old: project, pending: expressionRecorder.take())
            guard p != project else { return }
            project = p  // the open undo step already restores the state before the first edit
            return
        }
        perform("Edit Toolpath") { $0.upsertOperation(op) }
        liveOperationEdit = (op.id, editSerial)
    }

    /// Adds several operations as one undo step and selects the first.
    func addOperations(_ ops: [AnyOperation], actionName: String) {
        guard let first = ops.first else { return }
        perform(actionName) { p in ops.forEach { p.upsertOperation($0) } }
        sidebarTab = .toolpaths
        selectedOperationID = first.id
    }

    /// Inlay wizard: female pocket + male plug toolpaths.
    func addInlay(_ wizard: InlayWizardModel) {
        addOperations(wizard.makeOperations(), actionName: "New Inlay Toolpaths")
    }

    /// Replaces the tab settings of a Profile operation (one undo step).
    func setProfileTabs(_ tabs: TabSettings, for id: UUID, actionName: String = "Edit Tabs") {
        guard let op = operation(id), op.profileTabs != nil else { return }
        let new = op.withProfileTabs(tabs)
        perform(actionName) { $0.upsertOperation(new) }
    }

    // MARK: 3D models

    /// Adds (or updates) a placed model and creates the form's Roughing/Finishing toolpaths.
    func applyPlacement(_ form: ModelPlacementForm) {
        let model = form.placedModel
        let ops = form.makeOperations(existing: project.operations, units: units)
        let isNew = project.document.model(id: model.id) == nil
        perform(isNew ? "Place 3D Model" : "Edit 3D Model") { p in
            if let i = p.document.models.firstIndex(where: { $0.id == model.id }) {
                p.document.models[i] = model
            } else {
                p.document.models.append(model)
            }
            ops.forEach { p.upsertOperation($0) }
        }
        if let first = ops.first {
            sidebarTab = .toolpaths
            selectedOperationID = first.id
        }
    }

    /// Shows the next queued placement dialog (after an STL import).
    func showNextPlacement() {
        guard sheet == nil, !pendingPlacements.isEmpty else { return }
        sheet = .placeModel(pendingPlacements.removeFirst())
    }

    func editPlacement(of modelID: UUID) {
        guard let m = project.document.model(id: modelID) else { return }
        sheet = .placeModel(ModelPlacementForm(editing: m, job: project.document.job, library: mergedLibrary))
    }

    func deleteOperation(_ id: UUID) {
        perform("Delete Toolpath") { $0.deleteOperation(id) }
    }

    func duplicateOperation(_ id: UUID) {
        guard var op = operation(id) else { return }
        var s = op.editableSetup
        s.id = UUID()
        s.name = OperationFactory.defaultName(for: op.kind, existing: project.operations)
        op.editableSetup = s
        let copy = op
        perform("Duplicate Toolpath") { $0.operations.append(copy) }
        selectedOperationID = copy.id
    }

    func setOperationEnabled(_ id: UUID, _ enabled: Bool) {
        guard var op = operation(id) else { return }
        var s = op.editableSetup
        s.isEnabled = enabled
        op.editableSetup = s
        let o = op
        perform(enabled ? "Enable Toolpath" : "Disable Toolpath") { $0.upsertOperation(o) }
    }

    func toggleToolpathVisibility(_ id: UUID) {
        if hiddenToolpaths.contains(id) { hiddenToolpaths.remove(id) } else { hiddenToolpaths.insert(id) }
    }

    /// True when the operation has no result or was edited after its last calculation.
    func isStale(_ id: UUID) -> Bool {
        guard let r = results[id], let op = operation(id) else { return true }
        // The pause is applied when the program is posted, so editing it leaves the result valid.
        return r.operation.withoutPause != op.withoutPause || r.designRevision != designRevision
    }

    /// Generates toolpaths off the main thread; results arrive asynchronously. A request for an
    /// operation that is already calculating is queued and runs when the current one finishes.
    func calculate(_ ids: [UUID]) {
        let snapshot = project, library = toolLibrary.library, rev = designRevision
        let rapid = rapidRateInDocumentUnits
        for id in ids {
            guard let op = operation(id) else { continue }
            if calculating.contains(id) { pendingRecalculation.insert(id); continue }
            calculating.insert(id)
            let generation = nextGeneration()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let r = ToolpathCalculator.calculate(op, project: snapshot, library: library, designRevision: rev,
                                                     rapidRate: rapid)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.calculating.remove(id)
                    self.store(r, for: id, generation: generation)
                    if self.pendingRecalculation.remove(id) != nil { self.calculate([id]) }
                }
            }
        }
    }

    func calculateAll() { calculate(project.operations.filter(\.setup.isEnabled).map(\.id)) }

    /// Calculates synchronously (tests and small jobs). The UI uses `calculateAndWait`.
    func calculateNow(_ ids: [UUID]) {
        for id in ids {
            guard let op = operation(id) else { continue }
            let generation = nextGeneration()
            let r = ToolpathCalculator.calculate(op, project: project, library: toolLibrary.library,
                                                 designRevision: designRevision, rapidRate: rapidRateInDocumentUnits)
            store(r, for: id, generation: generation)
        }
    }

    /// Calculates `ids` on a background queue and returns when all results are stored. Returns
    /// false when the calling task was cancelled (results finished so far are still kept).
    @MainActor
    func calculateAndWait(_ ids: [UUID]) async -> Bool {
        let snapshot = project, library = toolLibrary.library, rev = designRevision
        let rapid = rapidRateInDocumentUnits
        let jobs = ids.compactMap { id in operation(id).map { (id, $0, nextGeneration()) } }
        let flag = CancellationFlag()
        let finished: [(UUID, ToolpathResult, Int)] = await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    var out: [(UUID, ToolpathResult, Int)] = []
                    for (id, op, g) in jobs {
                        if flag.isCancelled { break }
                        out.append((id, ToolpathCalculator.calculate(op, project: snapshot, library: library,
                                                                     designRevision: rev, rapidRate: rapid), g))
                    }
                    cont.resume(returning: out)
                }
            }
        } onCancel: {
            flag.cancel()
        }
        for (id, r, g) in finished { store(r, for: id, generation: g) }
        return !Task.isCancelled && finished.count == jobs.count
    }

    private func nextGeneration() -> Int {
        generationCounter += 1
        return generationCounter
    }

    /// Stores a result unless a newer calculation of the same operation already landed.
    private func store(_ r: ToolpathResult, for id: UUID, generation: Int) {
        guard operation(id) != nil, generation > resultGeneration[id] ?? 0 else { return }
        results[id] = r.renamingTools(from: toolLibrary.library) ?? r
        resultGeneration[id] = generation
    }

    /// A rename in the Tool Database does not make toolpaths stale (the name is a label), so the
    /// calculated toolpaths, which carry a copy of their tool, take the new name in place. The
    /// program comments, the job sheet and the checks then read the current name.
    private func showToolNames(of library: ToolLibrary) {
        for (id, r) in results {
            if let renamed = r.renamingTools(from: library) { results[id] = renamed }
        }
    }

    var totalEstimatedSeconds: TimeInterval {
        project.operations.filter(\.setup.isEnabled).compactMap { results[$0.id]?.estimatedSeconds }.reduce(0, +)
    }

    func setPostProfile(_ id: String) {
        perform("Change Post Processor") { $0.postProfileID = id }
    }

    /// Picks the machine (and its default post if the current post does not drive it).
    func setMachine(_ id: String) {
        guard let m = MachineCatalog.shared.machine(id: id) else { return }
        let profiles = PostProfileCatalog.shared.profiles
        perform("Change Machine") { MachineResolver.select(machine: m, in: &$0, profiles: profiles) }
    }

    // MARK: Job setup

    func applyJobSetup(_ form: JobSetupForm) {
        perform("Job Setup") { $0 = form.apply(to: $0) }
        if !isTwoSided { activeSide = .top }
        requestCanvas(.fit)
    }

    /// Makes sure the 2D canvas is on screen (keeps the side-by-side view if it is showing).
    func showDesignCanvas() {
        if !centerMode.showsDesign { centerMode = .design2D }
    }

    func requestCanvas(_ kind: CanvasRequest.Kind) {
        canvasRequest = CanvasRequest(kind: kind, serial: canvasRequest.serial + 1)
    }

    // MARK: Import / export

    func importFiles(_ urls: [URL]) {
        var messages: [String] = []
        var newShapes: [UUID] = []
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                if ImportService.isMesh(url.lastPathComponent) {
                    pendingPlacements.append(try ImportService.placementForm(
                        data: data, fileName: url.lastPathComponent, project: project, library: mergedLibrary))
                    continue
                }
                var outcome = ImportOutcome()
                var p = project
                outcome = try ImportService.importFile(data: data, fileName: url.lastPathComponent, into: &p)
                let imported = p
                perform("Import \(url.lastPathComponent)") { $0 = imported }
                newShapes += outcome.shapeIDs
                if !outcome.imageIDs.isEmpty && outcome.shapeIDs.isEmpty { requestCanvas(.fit) }
                messages += outcome.warnings.map { "\(url.lastPathComponent): \($0)" }
            } catch {
                messages.append("\(url.lastPathComponent): \(ImportService.describe(error))")
            }
        }
        if !newShapes.isEmpty { setSelection(newShapes); sidebarTab = .design; requestCanvas(.fit) }
        let message = messages.isEmpty ? nil : AlertMessage(title: "Import", message: messages.joined(separator: "\n"))
        if pendingPlacements.isEmpty {
            alert = message
        } else {
            // A sheet and an alert cannot show together: report after the placement dialogs.
            deferredAlert = message
            showDesignCanvas()
            showNextPlacement()
        }
    }

    /// Called when any sheet closes. Expressions typed into a sheet but never applied are dropped
    /// (an applied sheet consumed them in its edit; the Job Setup sheet also drops them when it
    /// opens), so they cannot latch onto whatever parameter next takes their value. Then the next
    /// queued placement, then any deferred import report.
    func sheetDismissed() {
        _ = expressionRecorder.take()
        if !pendingPlacements.isEmpty {
            showNextPlacement()
        } else if let a = deferredAlert {
            deferredAlert = nil
            alert = a
        }
    }

    func exportVectors(to url: URL, selectionOnly: Bool) {
        let ext = url.pathExtension.lowercased()
        let shapes = selectionOnly && !selection.isEmpty ? selectedShapes : project.document.shapes
        do {
            guard let exporter = FileFormats.exporter(forExtension: ext) else { throw KerfIOError.unsupportedFormat(ext) }
            let data = try exporter.export(shapes: shapes, layers: project.document.layers, units: units)
            try data.write(to: url, options: .atomic)
        } catch {
            alert = AlertMessage(title: "Export failed", message: ImportService.describe(error))
        }
    }
}

/// App-wide list of post profiles (built-ins + user JSON). Loaded once; `reload()` re-reads.
final class PostProfileCatalog: ObservableObject {
    static let shared = PostProfileCatalog()
    @Published private(set) var profiles: [PostProfile]
    let store: PostProfileStore

    init(store: PostProfileStore = PostProfileStore()) {
        self.store = store
        profiles = store.allProfiles()
    }

    func reload() { profiles = store.allProfiles() }

    func profile(id: String?) -> PostProfile {
        profiles.first { $0.id == id } ?? profiles.first { $0.id == PostProfileStore.defaultProfileID }
            ?? BuiltInPosts.avidMach4Inch
    }
}

/// Thread-safe cancel flag shared with a background calculation.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
