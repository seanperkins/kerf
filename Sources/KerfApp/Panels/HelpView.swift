import SwiftUI

/// Which help topic the Help window shows; shared so "?" buttons can jump to a topic.
final class HelpNavigator: ObservableObject {
    static let shared = HelpNavigator()
    @Published var topic: HelpTopic? = .gettingStarted
}

/// Help ▸ Kerf Help: searchable topic list and the selected topic.
struct HelpView: View {
    static let windowID = "kerf-help"
    @ObservedObject var navigator = HelpNavigator.shared
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.search(query), selection: $navigator.topic) { t in
                Label(t.title, systemImage: t.systemImage).tag(t)
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search help")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let t = navigator.topic {
                HelpTopicView(topic: t) { navigator.topic = $0 }
            } else {
                Text("Choose a topic").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

struct HelpTopicView: View {
    let topic: HelpTopic
    var open: (HelpTopic) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(topic.title, systemImage: topic.systemImage).font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                    Text(p).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if !topic.related.isEmpty {
                    Divider()
                    Text("See also").font(.headline)
                    ForEach(topic.related) { r in
                        Button { open(r) } label: { Label(r.title, systemImage: r.systemImage) }
                            .buttonStyle(.link)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    /// Markdown paragraphs; list items are kept as separate lines.
    private var paragraphs: [AttributedString] {
        topic.body.components(separatedBy: "\n\n").map { block in
            let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            return (try? AttributedString(markdown: block, options: opts)) ?? AttributedString(block)
        }
    }
}

/// The round "?" button: opens the Help window at `topic`.
struct HelpButton: View {
    let topic: HelpTopic
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HelpLink {
            HelpNavigator.shared.topic = topic
            openWindow(id: HelpView.windowID)
        }
        .help("Help: \(topic.title)")
        .accessibilityLabel("Help for \(topic.title)")
    }
}
