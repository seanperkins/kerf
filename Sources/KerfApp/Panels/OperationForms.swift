import CADCore
import CAMCore
import SwiftUI

// Parameter forms for every CAMCore operation. Each binds to its parameter struct.

struct DepthForm: View {
    @Binding var depth: DepthSettings
    var units: LengthUnit
    var showFinalPass = true
    /// The tool's stepdown in document units (for the pass list; nil = unknown).
    var toolStepdown: Double? = nil

    var body: some View {
        LengthField("Start depth", value: $depth.startDepth, units: units, help: "Depth below the material top where cutting starts")
        LengthField("Cut depth", value: $depth.cutDepth, units: units, help: "Final depth below the material top")
        PassEditor(depth: $depth, units: units, showFinalPass: showFinalPass, toolStepdown: toolStepdown)
        if depth.cutDepth <= depth.startDepth {
            Text("Cut depth must be deeper than the start depth.").font(.caption).foregroundStyle(.orange)
        }
    }
}

struct RampForm: View {
    @Binding var ramp: RampSettings
    var units: LengthUnit

    var body: some View {
        Toggle("Ramp plunges", isOn: $ramp.isEnabled)
        if ramp.isEnabled {
            Picker("Ramp type", selection: $ramp.type) {
                Text("Smooth").tag(RampType.smooth)
                Text("Zig-zag").tag(RampType.zigzag)
                Text("Spiral").tag(RampType.spiral)
            }
            LengthField("Ramp length", value: $ramp.length, units: units)
            NumberField("Max angle", value: $ramp.maxAngle, unit: "°")
        }
    }
}

struct DirectionPicker: View {
    @Binding var direction: CutDirection
    var body: some View {
        Picker("Direction", selection: $direction) {
            Text("Climb").tag(CutDirection.climb)
            Text("Conventional").tag(CutDirection.conventional)
        }
        .pickerStyle(.segmented)
    }
}

struct PocketStrategyForm: View {
    @Binding var strategy: PocketStrategy

    private var isRaster: Binding<Bool> {
        Binding(get: { if case .raster = strategy { return true } else { return false } },
                set: { strategy = $0 ? .raster(angle: 0, profilePass: true) : .offset })
    }
    private var angle: Binding<Double> {
        Binding(get: { if case .raster(let a, _) = strategy { return a } else { return 0 } },
                set: { a in if case .raster(_, let p) = strategy { strategy = .raster(angle: a, profilePass: p) } })
    }
    private var profilePass: Binding<Bool> {
        Binding(get: { if case .raster(_, let p) = strategy { return p } else { return false } },
                set: { p in if case .raster(let a, _) = strategy { strategy = .raster(angle: a, profilePass: p) } })
    }

    var body: some View {
        Picker("Clearing", selection: isRaster) {
            Text("Offset").tag(false)
            Text("Raster").tag(true)
        }
        .pickerStyle(.segmented)
        if isRaster.wrappedValue {
            NumberField("Raster angle", value: angle, unit: "°")
            Toggle("Final profile pass", isOn: profilePass)
        }
    }
}

struct ProfileForm: View {
    @Binding var params: ProfileParameters
    var units: LengthUnit
    /// The operation's vectors (to seed manual tabs).
    var shapes: [Shape] = []
    var isEditingTabs: Binding<Bool> = .constant(false)
    var toolStepdown: Double? = nil

    private var manualBinding: Binding<Bool> {
        Binding(get: { params.tabs.isManual }, set: { manual in
            params.tabs = manual ? TabEditor.makeManual(params.tabs, shapes: shapes) : TabEditor.makeAutomatic(params.tabs)
            if !manual { isEditingTabs.wrappedValue = false }
        })
    }

    var body: some View {
        InspectorSection(title: "Cutting Depths") { DepthForm(depth: $params.depth, units: units, toolStepdown: toolStepdown) }
        Divider()
        InspectorSection(title: "Machine Vectors") {
            Picker("Side", selection: $params.side) {
                Text("Outside").tag(ProfileSide.outside)
                Text("Inside").tag(ProfileSide.inside)
                Text("On").tag(ProfileSide.on)
            }
            .pickerStyle(.segmented)
            Picker("Open vectors", selection: Binding(get: { params.openVectorSide ?? .on },
                                                      set: { params.openVectorSide = $0 == .on ? nil : $0 })) {
                Text("On").tag(OpenVectorSide.on)
                Text("Left").tag(OpenVectorSide.left)
                Text("Right").tag(OpenVectorSide.right)
            }
            .help("Open vectors: cut on the line, or keep the tool to the left or right of the vector's direction")
            Picker("Start point", selection: Binding(get: { params.startPoint ?? .nearest },
                                                     set: { params.startPoint = $0 == .nearest ? nil : $0 })) {
                Text("Nearest (optimised)").tag(ProfileStartPoint.nearest)
                Text("Vector start node").tag(ProfileStartPoint.vectorStart)
                Text("Left side").tag(ProfileStartPoint.left)
                Text("Right side").tag(ProfileStartPoint.right)
                Text("Bottom side").tag(ProfileStartPoint.bottom)
                Text("Top side").tag(ProfileStartPoint.top)
            }
            .help("Where each closed loop starts cutting")
            DirectionPicker(direction: $params.direction)
            LengthField("Allowance", value: $params.allowance, units: units, help: "Material left on the part (negative removes more)")
            Toggle("Output arcs (G2/G3)", isOn: $params.preferArcs)
        }
        Divider()
        InspectorSection(title: "Last Pass") { ProfileLastPassForm(lastPass: $params.lastPass, side: params.side, units: units) }
        Divider()
        InspectorSection(title: "Tabs") {
            Toggle("Add tabs", isOn: $params.tabs.isEnabled)
            if params.tabs.isEnabled {
                LengthField("Length", value: $params.tabs.length, units: units)
                LengthField("Thickness", value: $params.tabs.thickness, units: units)
                Toggle("Triangular (3D) tabs", isOn: $params.tabs.isTriangular)
                Picker("Placement", selection: manualBinding) {
                    Text("Automatic").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.segmented)
                if let manual = params.tabs.manualTabs {
                    let n = manual.count
                    Text("\(n) tab\(n == 1 ? "" : "s") placed by hand").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Toggle(isOn: isEditingTabs) { Label("Edit on Canvas", systemImage: "pin") }
                            .toggleStyle(.button)
                        Button("Clear") { params.tabs.manualTabs = [] }.disabled(n == 0)
                    }
                } else {
                    IntField("Tabs per vector", value: $params.tabs.countPerPath, range: 1...64)
                    OptionalLengthField(label: "Spacing", value: $params.tabs.spacing, units: units,
                                        defaultValue: units == .inch ? 6 : 150)
                }
            }
        }
        Divider()
        InspectorSection(title: "Ramps & Leads") {
            RampForm(ramp: $params.ramp, units: units)
            Picker("Lead in/out", selection: $params.lead.type) {
                Text("None").tag(LeadType.none)
                Text("Linear").tag(LeadType.linear)
                Text("Arc").tag(LeadType.arc)
            }
            if params.lead.type != .none {
                LengthField(params.lead.type == .arc ? "Lead radius" : "Lead length", value: $params.lead.distance, units: units)
            }
            LengthField("Overcut", value: $params.lead.overcut, units: units)
        }
    }
}

struct PocketForm: View {
    @Binding var params: PocketParameters
    var units: LengthUnit
    var library: ToolLibrary
    var finishToolID: UUID?
    var toolStepdown: Double? = nil

    var body: some View {
        InspectorSection(title: "Cutting Depths") { DepthForm(depth: $params.depth, units: units, toolStepdown: toolStepdown) }
        Divider()
        InspectorSection(title: "Clearing") {
            PocketStrategyForm(strategy: $params.strategy)
            DirectionPicker(direction: $params.direction)
            LengthField("Allowance", value: $params.allowance, units: units)
        }
        Divider()
        InspectorSection(title: "Tools") {
            ClearanceToolsEditor(params: $params, library: library, finishToolID: finishToolID)
        }
        Divider()
        InspectorSection(title: "Ramps") { RampForm(ramp: $params.ramp, units: units) }
    }
}

struct DrillForm: View {
    @Binding var params: DrillParameters
    var units: LengthUnit

    var body: some View {
        InspectorSection(title: "Drilling") {
            LengthField("Start depth", value: $params.startDepth, units: units)
            LengthField("Cut depth", value: $params.cutDepth, units: units)
            Toggle("Peck drilling", isOn: Binding(get: { params.peckDepth > 0 }, set: { on in
                params.peckDepth = on ? (units == .inch ? 0.125 : 3) : 0
            }))
            if params.peckDepth > 0 {
                LengthField("Peck depth", value: $params.peckDepth, units: units, help: "Depth added by each peck")
                LengthField("Retract height", value: $params.retractHeight, units: units,
                            help: "Above the material top between pecks (clears chips)")
            }
            NumberField("Dwell at bottom", value: $params.dwellSeconds, unit: "s")
            Text(OperationHints.peckSummary(params, units: units)).font(.caption).foregroundStyle(.secondary)
            Text("Drills at the centre of each selected vector.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct VCarveForm: View {
    @Binding var params: VCarveParameters
    var units: LengthUnit
    var library: ToolLibrary

    var body: some View {
        InspectorSection(title: "V-Carve") {
            LengthField("Start depth", value: $params.startDepth, units: units)
            OptionalLengthField(label: "Flat depth", value: $params.flatDepth, units: units,
                                defaultValue: units == .inch ? 0.125 : 3)
            if params.flatDepth != nil {
                OptionalToolPicker(title: "Flat area tool", toolID: $params.flatClearanceToolID, library: library,
                                   kinds: [.endMill, .ballNose])
                if params.flatClearanceToolID != nil {
                    PocketStrategyForm(strategy: $params.flatClearanceStrategy)
                }
            }
            OptionalLengthField(label: "Max pass depth", value: $params.passDepth, units: units,
                                defaultValue: units == .inch ? 0.1 : 2.5)
        }
    }
}

struct InlayForm: View {
    @Binding var params: InlayParameters
    var units: LengthUnit
    var library: ToolLibrary

    var body: some View {
        InspectorSection(title: "Inlay") {
            Picker("Part", selection: $params.part) {
                Text("Pocket (female)").tag(InlayPart.female)
                Text("Plug (male)").tag(InlayPart.male)
                Text("Both").tag(InlayPart.both)
            }
            LengthField("Pocket depth", value: $params.pocketDepth, units: units)
            LengthField("Plug start depth", value: $params.maleStartDepth, units: units)
            LengthField("Glue gap", value: $params.glueGap, units: units)
            Toggle("Mirror plug", isOn: $params.mirrorMale)
            LengthField("Plug boundary margin", value: $params.maleBoundaryMargin, units: units)
            OptionalToolPicker(title: "Flat area tool", toolID: $params.flatClearanceToolID, library: library,
                               kinds: [.endMill, .ballNose])
            let gap = params.pocketDepth - params.maleStartDepth
            if params.maleStartDepth + params.glueGap > params.pocketDepth + 1e-9 {
                Text("Plug start depth + glue gap must not exceed the pocket depth.").font(.caption).foregroundStyle(.orange)
            } else {
                Text("Gap under the plug: \(RulerTicks.label((gap * 1000).rounded() / 1000)) \(units.abbreviation)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FlutingForm: View {
    @Binding var params: FlutingParameters
    var units: LengthUnit

    var body: some View {
        InspectorSection(title: "Cutting Depths") { DepthForm(depth: $params.depth, units: units, showFinalPass: false) }
        Divider()
        InspectorSection(title: "Fluting") {
            Picker("Ramp", selection: $params.ramp) {
                Text("Start").tag(FluteRamp.start)
                Text("End").tag(FluteRamp.end)
                Text("Both").tag(FluteRamp.both)
            }
            .pickerStyle(.segmented)
            NumberField("Ramp length", value: Binding(get: { params.rampFraction * 100 },
                                                      set: { params.rampFraction = min(max($0 / 100, 0), 0.5) }), unit: "%")
            Toggle("Smooth ramp", isOn: $params.smoothRamp)
            Text("Each selected vector is cut once, plunging gradually over the ramp length to full depth. Use a ball nose or V-bit for tapered flutes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TextureForm: View {
    @Binding var params: TextureParameters
    var units: LengthUnit

    var body: some View {
        InspectorSection(title: "Texture") {
            LengthField("Max depth", value: $params.maxDepth, units: units)
            LengthField("Spacing", value: $params.spacing, units: units)
            LengthField("Min stroke", value: $params.minStrokeLength, units: units)
            LengthField("Max stroke", value: $params.maxStrokeLength, units: units)
            NumberField("Angle", value: $params.angle, unit: "°")
            NumberField("Variation", value: Binding(get: { params.variation * 100 },
                                                    set: { params.variation = min(max($0 / 100, 0), 1) }), unit: "%")
            LabeledContent("Seed") {
                HStack {
                    Text("\(params.seed)").monospacedDigit()
                    Button("Shuffle") { params.seed = UInt64.random(in: 1...999_999) }
                }
            }
            Text("Fills the selected closed vectors with short random strokes at the given spacing and angle.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Relief3DForm: View {
    @Binding var params: Relief3DParameters
    var units: LengthUnit
    var library: ToolLibrary
    var models: [PlacedModel]
    var selection: [UUID]

    var body: some View {
        InspectorSection(title: "3D Model") {
            Picker("Model", selection: $params.modelID) {
                if !models.contains(where: { $0.id == params.modelID }) { Text("Missing model").tag(params.modelID) }
                ForEach(models) { Text($0.name).tag($0.id) }
            }
            LengthField("Resolution", value: $params.resolution, units: units, help: "Heightmap cell size")
            Text(params.boundaryShapeIDs.isEmpty ? "Boundary: whole model" : "Boundary: \(params.boundaryShapeIDs.count) vector(s)")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Use Selection as Boundary") { params.boundaryShapeIDs = selection }.disabled(selection.isEmpty)
                Button("Clear") { params.boundaryShapeIDs = [] }.disabled(params.boundaryShapeIDs.isEmpty)
            }
        }
        Divider()
        InspectorSection(title: "Roughing") {
            Toggle("Rough first", isOn: $params.roughing.isEnabled)
            if params.roughing.isEnabled {
                OptionalToolPicker(title: "Roughing tool", toolID: $params.roughing.toolID, library: library, kinds: [.endMill])
                LengthField("Allowance", value: $params.roughing.allowance, units: units)
                OptionalLengthField(label: "Pass depth", value: $params.roughing.passDepth, units: units,
                                    defaultValue: units == .inch ? 0.125 : 3)
                PocketStrategyForm(strategy: $params.roughing.strategy)
            }
        }
        Divider()
        InspectorSection(title: "Finishing") {
            Toggle("Finish", isOn: $params.finishing.isEnabled)
            if params.finishing.isEnabled {
                OptionalLengthField(label: "Stepover", value: $params.finishing.stepover, units: units,
                                    defaultValue: units == .inch ? 0.02 : 0.5)
                NumberField("Raster angle", value: $params.finishing.angle, unit: "°")
            }
        }
    }
}

/// Separate last pass (finishing lap that removes a side allowance).
struct ProfileLastPassForm: View {
    @Binding var lastPass: ProfileLastPass?
    var side: ProfileSide
    var units: LengthUnit

    private var enabled: Binding<Bool> {
        Binding(get: { lastPass != nil }, set: { on in
            lastPass = on ? ProfileLastPass(allowance: units == .inch ? 0.01 : 0.25) : nil
        })
    }

    private func field<T>(_ kp: WritableKeyPath<ProfileLastPass, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { lastPass?[keyPath: kp] ?? fallback }, set: { v in lastPass?[keyPath: kp] = v })
    }

    var body: some View {
        Toggle("Separate last pass", isOn: enabled)
        if lastPass != nil {
            LengthField("Last pass allowance", value: field(\.allowance, 0), units: units,
                        help: "Material the roughing passes leave on the wall for the last pass")
            Toggle("Reverse direction", isOn: field(\.reverseDirection, false))
            Toggle("Last pass at full depth", isOn: field(\.fullDepth, true))
            Text(side == .on
                 ? "Not used when cutting on the line."
                 : "Roughing passes stay the allowance away from the wall; one more lap then cuts the wall to size.")
                .font(.caption).foregroundStyle(side == .on ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Ordered list of pocket clearance tools (largest first). Writes `clearanceToolIDs` and keeps
/// the legacy `clearanceToolID` equal to the first entry.
struct ClearanceToolsEditor: View {
    @Binding var params: PocketParameters
    var library: ToolLibrary
    var finishToolID: UUID?

    private var ids: [UUID] { params.clearanceTools }

    private func set(_ new: [UUID]) {
        params.clearanceToolIDs = new
        params.clearanceToolID = new.first
    }

    private func row(_ i: Int) -> Binding<UUID> {
        Binding(get: { ids[i] }, set: { v in var n = ids; n[i] = v; set(n) })
    }

    private var candidates: [Tool] {
        library.tools.filter { $0.kind == .endMill || $0.kind == .ballNose }
    }

    var body: some View {
        let problems = OperationHints.pocketClearanceProblems(finish: finishToolID.flatMap { library.tool(id: $0) },
                                                              clearance: ids.map { library.tool(id: $0) })
        ForEach(Array(ids.enumerated()), id: \.offset) { i, _ in
            HStack {
                Picker("Clearance \(i + 1)", selection: row(i)) {
                    if library.tool(id: ids[i]) == nil { Text("Missing tool").tag(ids[i]) }
                    ForEach(candidates) { t in Text("T\(t.number) · \(t.name)").tag(t.id) }
                }
                Button { var n = ids; n.remove(at: i); set(n) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove this clearance tool")
            }
            if let problem = problems[i] {
                Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        Button { if let t = nextSuggestion { set(ids + [t.id]) } } label: { Label("Add Clearance Tool", systemImage: "plus") }
            .disabled(nextSuggestion == nil)
        Text(ids.isEmpty
             ? "The finish tool clears the whole pocket."
             : "Clearance tools cut largest first; each one only machines what the tools before it could not reach. The finish tool then cleans up the walls and corners.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// Largest unused tool that is smaller than the last clearance tool and larger than the finish tool.
    private var nextSuggestion: Tool? {
        func inch(_ t: Tool) -> Double { t.diameter * t.units.factor(to: .inch) }
        let finish = finishToolID.flatMap { library.tool(id: $0) }.map(inch) ?? 0
        let limit = ids.last.flatMap { library.tool(id: $0) }.map(inch) ?? .infinity
        let fits = candidates.filter { !ids.contains($0.id) && $0.id != finishToolID && inch($0) > finish + 1e-9 && inch($0) < limit - 1e-9 }
        return fits.max { inch($0) < inch($1) } ?? candidates.first { !ids.contains($0.id) && $0.id != finishToolID }
    }
}
