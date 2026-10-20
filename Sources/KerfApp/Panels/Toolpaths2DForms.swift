import CADCore
import CAMCore
import SwiftUI

// Forms for the 2D toolpaths added in the VCarve-parity work (toolpaths-2d).

private func fmt(_ v: Double) -> String { RulerTicks.label((v * 1000).rounded() / 1000) }

struct EngraveForm: View {
    @Binding var params: EngraveParameters
    var units: LengthUnit
    /// The selected tool in document units (for the width preview).
    var tool: Tool?

    var body: some View {
        InspectorSection(title: "Cutting Depths") { DepthForm(depth: $params.depth, units: units) }
        Divider()
        InspectorSection(title: "Quick Engrave") {
            DirectionPicker(direction: $params.direction)
            if let tool {
                let w = EngraveOperation.cutWidth(tool: tool, depth: params.depth.cutDepth)
                Text("Groove width at \(fmt(params.depth.cutDepth)) \(units.abbreviation) deep: \(fmt(w)) \(units.abbreviation)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Cuts along each selected vector on its centreline (no offset). Open and closed vectors both work.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ChamferForm: View {
    @Binding var params: ChamferParameters
    var units: LengthUnit
    var tool: Tool?

    private var byDepth: Binding<Bool> {
        Binding(get: { params.depth != nil }, set: { on in
            if on {
                let fallback = units == .inch ? 0.125 : 3
                params.depth = tool.flatMap { try? ChamferOperation.size(tool: $0, params: params).depth } ?? fallback
            } else {
                params.depth = nil
            }
        })
    }

    var body: some View {
        InspectorSection(title: "Chamfer") {
            Picker("Side", selection: $params.side) {
                Text("Outside").tag(ProfileSide.outside)
                Text("Inside").tag(ProfileSide.inside)
                Text("On").tag(ProfileSide.on)
            }
            .pickerStyle(.segmented)
            Picker("Size by", selection: byDepth) {
                Text("Width").tag(false)
                Text("Depth").tag(true)
            }
            .pickerStyle(.segmented)
            if let d = params.depth {
                LengthField("Depth", value: Binding(get: { d }, set: { params.depth = $0 }), units: units,
                            help: "Depth of the bit tip below the start depth's surface")
            } else {
                LengthField("Width", value: $params.width, units: units, help: "Chamfer width on the top surface")
            }
            LengthField("Tip clearance", value: $params.tipClearance, units: units,
                        help: "How far the tip runs into the waste past the edge")
            LengthField("Start depth", value: $params.startDepth, units: units)
            OptionalLengthField(label: "Pass depth", value: $params.passDepth, units: units,
                                defaultValue: units == .inch ? 0.1 : 2.5)
            DirectionPicker(direction: $params.direction)
            summary
        }
    }

    @ViewBuilder private var summary: some View {
        if let (text, ok) = summaryText {
            Text(text).font(.caption).foregroundStyle(ok ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryText: (String, Bool)? {
        guard let tool else { return nil }
        do {
            let s = try ChamferOperation.size(tool: tool, params: params)
            let u = units.abbreviation
            return ("\(fmt(s.width)) \(u) wide × \(fmt(s.height)) \(u) high; tip \(fmt(s.depth)) \(u) deep.", true)
        } catch CAMError.invalidParameter(let message) {
            return (message, false)
        } catch {
            return nil
        }
    }
}
