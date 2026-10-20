import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingArrayTests {
    @Test func rectangularOffsetsSkipOriginal() {
        let o = ArrayLayout.rectangular(rows: 2, columns: 3, x: 1, y: 2, spacing: .offset, size: Vec2(5, 5))
        #expect(o.count == 5)
        #expect(!o.contains(.zero))
        #expect(o.contains(Vec2(2, 2)) && o.contains(Vec2(1, 0)))
    }

    @Test func gapAddsSelectionSize() {
        let o = ArrayLayout.rectangular(rows: 1, columns: 2, x: 0.5, y: 0, spacing: .gap, size: Vec2(2, 1))
        #expect(o == [Vec2(2.5, 0)])
        #expect(ArrayLayout.rectangular(rows: 0, columns: 2, x: 1, y: 1, spacing: .gap, size: .zero).isEmpty)
    }

    @Test func circularRotatesAroundCentre() {
        let ts = ArrayLayout.circular(count: 4, center: .zero, stepDegrees: 90, rotateCopies: true, selectionCenter: Vec2(1, 0))
        #expect(ts.count == 3)
        #expect(ts[0].apply(Vec2(1, 0)).isApproximatelyEqual(to: Vec2(0, 1), tolerance: 1e-9))
        // Without rotation copies only translate.
        let tr = ArrayLayout.circular(count: 2, center: .zero, stepDegrees: 180, rotateCopies: false, selectionCenter: Vec2(1, 0))
        #expect(tr[0].isConformal && tr[0].a == 1 && tr[0].d == 1)
        #expect(tr[0].apply(Vec2(1, 0)).isApproximatelyEqual(to: Vec2(-1, 0), tolerance: 1e-9))
    }

    @Test func evenStepOverFullCircleDoesNotRepeatFirst() {
        #expect(ArrayLayout.evenStep(count: 6, sweepDegrees: 360) == 60)
        #expect(ArrayLayout.evenStep(count: 3, sweepDegrees: 90) == 45)
    }
}
