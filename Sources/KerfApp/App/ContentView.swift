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
        .onAppear { document.undoManager = undoManager }
        .onChange(of: undoManager) { _, um in document.undoManager = um }
        .sheet(item: $document.sheet, onDismiss: { document.sheetDismissed() }) { sheet in
            switch sheet {
            case .jobSetup: JobSetupSheet(document: document)
            case .exportGCode(let scope): ExportGCodeSheet(document: document, scope: scope)
            case .offset: OffsetSheet(document: document)
            case .inlayWizard: InlayWizardSheet(document: document)
            case .placeModel(let form): ModelPlacementSheet(document: document, form: form)
            case .saveAllToolpaths: SaveAllToolpathsSheet(document: document)
            case .validation: ValidationSheet(document: document)
            }
        }
        .alert(item: $document.alert) { a in
            Alert(title: Text(a.title), message: Text(a.message))
        }
    }

    @ViewBuilder private var center: some View {
        switch document.centerMode {
        case .design2D:
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
        case .preview3D:
            Preview3DHost(document: document)
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
                Text("3D").tag(CenterMode.preview3D)
            }
            .pickerStyle(.segmented)
            .help("Design canvas or 3D preview")
        }
        ToolbarItemGroup {
            Button { document.requestCanvas(.fit) } label: { Label("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
                .help("Zoom to material (F)")
            Toggle(isOn: $document.snapToGrid) { Label("Snap", systemImage: "grid") }
                .help("Snap to grid")
            Picker("Machine", selection: Binding(get: { document.postProfile.id }, set: { document.setPostProfile($0) })) {
                ForEach(catalog.profiles) { Text($0.name).tag($0.id) }
            }
            .frame(width: 210)
            .help("Machine / post processor")
            Button { openWindow(id: ToolDatabaseView.windowID) } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .help("Tool Database")
            Button { document.calculateAll() } label: { Label("Calculate", systemImage: "play.fill") }
                .help("Calculate all toolpaths")
                .disabled(document.project.operations.isEmpty)
            Button { document.sheet = .exportGCode(.all) } label: { Label("Export G-code", systemImage: "square.and.arrow.up") }
                .help("Export G-code")
                .disabled(document.project.operations.isEmpty)
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
        }
    }
}

struct StatusBar: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        HStack(spacing: 14) {
            Text(GCodeExporter.materialDescription(document.document))
            Text("Z0: " + document.document.job.zZero.displayName)
            Text("Origin: " + document.document.job.xyOrigin.displayName)
            Text(document.postProfile.name)
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
