import Testing
@testable import KerfApp

/// Collapsible inspector sections remember whether they are open, per section title.
@Suite struct InspectorSectionTests {
    @Test func theStorageKeyIsADeterministicSlugOfTheTitle() {
        #expect(SectionState.key(for: "Ramps & Leads") == "kerf.inspector.expanded.ramps-leads")
        #expect(SectionState.key(for: "Last Pass") == "kerf.inspector.expanded.last-pass")
        #expect(SectionState.key(for: "  Array   Copies ") == "kerf.inspector.expanded.array-copies")
    }

    @Test func collapsedSectionsStartClosedAndOthersOpen() {
        #expect(SectionState.initiallyExpanded(collapsedByDefault: true) == false)
        #expect(SectionState.initiallyExpanded(collapsedByDefault: false) == true)
    }

    @Test func theCollapsibleTitlesDoNotShareAKey() {
        let titles = ["Last Pass", "Ramps & Leads", "Order & Corners", "Ramps", "Array Copies"]
        #expect(Set(titles.map(SectionState.key(for:))).count == titles.count)
    }
}
