import CADCore
import PostCore
import SwiftUI

/// Toolbar pickers: the machine (bed size, limits) and the post processor that drives it.
struct MachinePostPickers: View {
    @ObservedObject var document: KerfDocument
    @ObservedObject private var machines = MachineCatalog.shared

    var body: some View {
        Picker("Machine", selection: Binding(get: { document.machine?.id ?? "" },
                                             set: { if !$0.isEmpty { document.setMachine($0) } })) {
            if document.machine == nil { Text("Custom (post limits)").tag("") }
            ForEach(machines.machines) { Text($0.name).tag($0.id) }
        }
        .frame(width: 190)
        .help("Machine: bed size, travel limits and the post processors that drive it")
        .accessibilityLabel("Machine")
        PostProfilePicker(title: "Post", selection: Binding(get: { document.postProfile.id },
                                                            set: { document.setPostProfile($0) }),
                          machine: document.machine)
            .frame(width: 210)
            .help("Post processor (G-code dialect) for the selected machine")
            .accessibilityLabel("Post processor")
    }
}

/// Post picker listing the machine's own posts first, then any others.
struct PostProfilePicker: View {
    var title: String
    @Binding var selection: String
    var machine: MachineDefinition?
    @ObservedObject private var posts = PostProfileCatalog.shared

    var body: some View {
        let split = MachineResolver.orderedPosts(posts.profiles, machine: machine)
        Picker(title, selection: $selection) {
            ForEach(split.compatible) { Text($0.name).tag($0.id) }
            if !split.other.isEmpty {
                Divider()
                ForEach(split.other) { Text($0.name + " (other machine)").tag($0.id) }
            }
        }
    }
}
