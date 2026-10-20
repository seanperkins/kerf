import CADCore
import SwiftUI

/// Job Setup: material size, units, XY origin, Z zero, safe Z and home position.
struct JobSetupSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @State private var form: JobSetupForm

    init(document: KerfDocument) {
        self.document = document
        _form = State(initialValue: JobSetupForm(document: document.document))
    }

    var body: some View {
        let u = form.units
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Job Setup").font(.title2.bold()); Spacer(); HelpButton(topic: .jobSetup) }.padding([.horizontal, .top], 20)
            Form {
                Section("Job") {
                    TextField("Job name", text: $form.name)
                    if form.isMultiSheet { TextField("Sheet name", text: $form.sheetName) }
                    Picker("Units", selection: Binding(get: { form.units }, set: { form.setUnits($0) })) {
                        ForEach(LengthUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Material") {
                    LengthField("Width (X)", value: $form.job.width, units: u)
                    LengthField("Height (Y)", value: $form.job.height, units: u)
                    LengthField("Thickness (Z)", value: $form.job.thickness, units: u)
                    MaterialNameField(material: $form.job.material,
                                      known: ToolGrouping.materialNames(document.mergedLibrary.tools))
                }
                Section("Z zero") {
                    Picker("Z zero", selection: $form.job.zZero) {
                        ForEach(ZZeroMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    Text(form.job.zZero == .materialTop
                         ? "Touch off on top of the material. Cuts have negative Z."
                         : "Touch off on the spoilboard. The material top is Z = thickness.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("XY origin") {
                    HStack(alignment: .top, spacing: 20) {
                        OriginPicker(origin: $form.job.xyOrigin)
                        Text("Machine X0 Y0 is at the \(form.job.xyOrigin.displayName.lowercased()) of the material.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Offset the datum", isOn: Binding(get: { form.job.datumOffset != nil },
                                                             set: { form.job.datumOffset = $0 ? (form.job.datumOffset ?? .zero) : nil }))
                    if form.job.datumOffset != nil {
                        LengthField("Offset X", value: Binding(get: { form.job.datumOffset?.x ?? 0 },
                                                               set: { form.job.datumOffset?.x = $0 }), units: u,
                                    help: "Distance from the chosen corner/centre to machine X0 (right is positive)")
                        LengthField("Offset Y", value: Binding(get: { form.job.datumOffset?.y ?? 0 },
                                                               set: { form.job.datumOffset?.y = $0 }), units: u,
                                    help: "Distance from the chosen corner/centre to machine Y0 (up is positive)")
                    }
                }
                TwoSidedSection(job: $form.job)
                Section("Rapid heights (above material top)") {
                    LengthField("Safe Z", value: $form.job.safeZ, units: u)
                    OptionalLengthField(label: "Plunge Z (rapid down to)", value: $form.job.plungeGap, units: u,
                                        defaultValue: u == .inch ? 0.1 : 2.5)
                    LengthField("Home Z", value: $form.job.homeZ, units: u)
                    LengthField("Home X", value: $form.job.home.x, units: u, help: "Machine coordinates")
                    LengthField("Home Y", value: $form.job.home.y, units: u, help: "Machine coordinates")
                }
                Section("Drawing") {
                    LengthField("Grid spacing", value: $form.gridSpacing, units: u)
                }
                let fit = MachineResolver.fitProblems(job: form.job, units: form.units, machine: document.machine)
                if !fit.isEmpty {
                    Section("Machine") {
                        ForEach(fit, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
                if !form.problems.isEmpty {
                    Section {
                        ForEach(form.problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if form.units != document.units {
                    Text("Changing units converts the design and toolpath parameters.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { document.applyJobSetup(form); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.problems.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520, height: 680)
    }
}

/// 3×3 grid of radio dots over a material outline; only corners and centre are selectable.
struct OriginPicker: View {
    @Binding var origin: XYOrigin

    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor)).border(Color.secondary)
                .frame(width: 120, height: 80)
            VStack {
                HStack { dot(.upperLeft); Spacer(); dot(.upperRight) }
                Spacer()
                dot(.center)
                Spacer()
                HStack { dot(.lowerLeft); Spacer(); dot(.lowerRight) }
            }
            .frame(width: 136, height: 96)
        }
        .frame(width: 140, height: 100)
    }

    private func dot(_ o: XYOrigin) -> some View {
        Button { origin = o } label: {
            Image(systemName: origin == o ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(origin == o ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(o.displayName)
    }
}

/// Job Setup: double-sided machining (flip axis and the bottom side's Z zero).
struct TwoSidedSection: View {
    @Binding var job: JobSetup

    var body: some View {
        Section("Sides") {
            Toggle("Two-sided job", isOn: Binding(get: { job.twoSided != nil },
                                                  set: { job.twoSided = $0 ? (job.twoSided ?? TwoSidedSetup()) : nil }))
            if let t = job.twoSided {
                Picker("Flip the material", selection: Binding(get: { t.flip }, set: { job.twoSided?.flip = $0 })) {
                    ForEach(FlipAxis.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Bottom side Z zero", selection: Binding(get: { t.bottomZZero }, set: { job.twoSided?.bottomZZero = $0 })) {
                    Text("Same as top side").tag(ZZeroMode?.none)
                    ForEach(ZZeroMode.allCases, id: \.self) { Text($0.displayName).tag(ZZeroMode?.some($0)) }
                }
                Text("Each side is drawn as seen from above while it faces up; the other side shows mirrored and dashed. Use the centre origin, or stock cut exactly to size, so the second side registers to the first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
