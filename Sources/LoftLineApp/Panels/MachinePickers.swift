import CADCore
import PostCore
import SwiftUI

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
