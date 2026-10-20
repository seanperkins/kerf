import CADCore
import CAMCore
import PostCore
import SwiftUI

/// Main document window: sidebar (Design/Toolpaths), canvas (2D) or 3D preview, inspector.
struct ContentView: View {
    @ObservedObject var document: KerfDocument
    @EnvironmentObject var toolLibrary: ToolLibraryModel
    @ObservedObject private var catalog = PostProfileCatalog.shared
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.documentConfiguration) private var documentConfiguration
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView(document: document)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            VStack(spacing: 0) {
                center
                Divider()
                StatusBar(document: document)
            }
            .inspector(isPresented: $showInspector) {
                InspectorView(document: document)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
        }
        .toolbar { toolbarContent }
        .navigationTitle(document.document.name)
        .focusedSceneObject(document)
        .onAppear {
            document.undoManager = undoManager
            RecoveryCoordinator.shared.register(document)
        }
        .onDisappear { RecoveryCoordinator.shared.unregister(document) }
        .onChange(of: undoManager) { _, um in document.undoManager = um }
        .onAppear { document.fileURL = documentConfiguration?.fileURL }
        .onChange(of: documentConfiguration?.fileURL) { _, url in
            document.fileURL = url
            document.scheduleFileThumbnail()
        }
        .sheet(item: $document.sheet, onDismiss: { document.sheetDismissed() }) { sheet in
            switch sheet {
            case .jobSetup: JobSetupSheet(document: document)
            case .exportGCode(let scope): ExportGCodeSheet(document: document, scope: scope)
            case .offset: OffsetSheet(document: document)
            case .inlayWizard: InlayWizardSheet(document: document)
            case .placeModel(let form): ModelPlacementSheet(document: document, form: form)
            case .saveAllToolpaths: SaveAllToolpathsSheet(document: document)
            case .validation: ValidationSheet(document: document)
            case .keepOutZones: KeepOutZonesSheet(document: document)
            case .nesting: NestingSheet(document: document)
            case .fixtures: FixturesSheet(document: document)
            case .tiling: TilingSheet(document: document)
            case .partLabels: PartLabelsSheet(document: document)
            case .variables: DocumentVariablesSheet(document: document)
            case .drawing(let kind): DrawingSheetHost(document: document, kind: kind)
            case .io(let s): IOSheetHost(document: document, sheet: s)
            }
        }
        .alert(item: $document.alert) { a in
            Alert(title: Text(a.title), message: Text(a.message))
        }
        .environment(\.documentVariables, document.document.variableTable)
        .environment(\.expressionUnits, document.units)
        .environment(\.expressionRecorder, document.expressionRecorder)
    }

    @ViewBuilder private var center: some View {
        switch document.centerMode {
        case .design2D:
            designPane
        case .preview3D:
            Preview3DHost(document: document)
        case .split:
            HSplitView {
                designPane.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                Preview3DHost(document: document).frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var designPane: some View {
        ZStack(alignment: .topLeading) {
            DesignCanvas(document: document)
            ToolPalette(document: document).padding(.leading, 28).padding(.top, 28)
            if let id = document.tabEditingOperationID, let op = document.operation(id) {
                TabEditingBanner(name: op.setup.name, count: op.profileTabs?.manualTabs?.count ?? 0) {
                    document.tabEditingOperationID = nil
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 28)
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { document.sheet = .jobSetup } label: { Label("Job Setup", systemImage: "square.dashed") }
                .help("Job Setup (material, origin, Z zero)")
        }
        ToolbarItemGroup(placement: .principal) {
            Picker("View", selection: $document.centerMode) {
                Text("2D").tag(CenterMode.design2D)
                Text("2D | 3D").tag(CenterMode.split)
                Text("3D").tag(CenterMode.preview3D)
            }
            .pickerStyle(.segmented)
            .help("Design canvas, both side by side, or 3D preview")
        }
        ToolbarItemGroup {
            Button { document.requestCanvas(.fit) } label: { Label("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
                .help("Zoom to material (F)")
            Toggle(isOn: $document.snapToGrid) { Label("Snap", systemImage: "grid") }
                .help("Snap to grid")
            MachinePostPickers(document: document)
            Button { openWindow(id: ToolDatabaseView.windowID) } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .help("Tool Database")
            Button { document.calculateAll() } label: { Label("Calculate", systemImage: "play.fill") }
                .help("Calculate all toolpaths")
                .disabled(document.project.operations.isEmpty)
            Button { document.sheet = .exportGCode(.all) } label: { Label("Export G-code", systemImage: "square.and.arrow.up") }
                .help("Export G-code")
                .disabled(document.project.operations.isEmpty)
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help("Show or hide the inspector")
        }
    }
}

struct StatusBar: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        HStack(spacing: 14) {
            Text(GCodeExporter.materialDescription(document.document))
            Text("Z0: " + document.outputProject.document.job.zZero.displayName)
            Text("Origin: " + document.document.job.xyOrigin.displayName)
            if document.document.isMultiSheet { Text("Sheet: " + document.document.currentSheetName).bold() }
            if document.isTwoSided { Text("Side: " + document.activeSide.displayName).bold() }
            Text([document.machine?.name, document.postProfile.name].compactMap { $0 }.joined(separator: " · "))
            Spacer()
            if !document.selection.isEmpty { Text("\(document.selection.count) selected") }
            if let p = document.cursorPosition {
                Text("X \(RulerTicks.label((p.x * 1000).rounded() / 1000))  Y \(RulerTicks.label((p.y * 1000).rounded() / 1000))")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
