import Testing
@testable import Keypress

@Suite("Ribbon Change Classification")
struct RibbonChangeTests {
    @Test("An unchanged row is a conveyor step")
    func unchangedRow() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["a", "b", "c"]) == .conveyor)
    }

    @Test("Appending at the tail is a conveyor step")
    func appendAtTail() {
        #expect(RibbonChange.classify(old: ["a", "b"], new: ["a", "b", "c"]) == .conveyor)
        #expect(RibbonChange.classify(old: ["a", "b"], new: ["a", "b", "c", "d"]) == .conveyor)
    }

    @Test("The first key of an empty ribbon is a conveyor step")
    func firstKey() {
        #expect(RibbonChange.classify(old: [], new: ["a"]) == .conveyor)
        #expect(RibbonChange.classify(old: [], new: []) == .conveyor)
    }

    @Test("Evicting the head while appending at the tail is a conveyor step")
    func headDropWithAppend() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["b", "c", "d"]) == .conveyor)
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["c", "d", "e"]) == .conveyor)
    }

    @Test("Dropping the head alone is a conveyor step")
    func pureHeadDrop() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["b", "c"]) == .conveyor)
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["c"]) == .conveyor)
    }

    @Test("Emptying the ribbon is a conveyor step")
    func emptyingRibbon() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: []) == .conveyor)
    }

    @Test("Replacing every entry is a conveyor step")
    func fullReplacement() {
        #expect(RibbonChange.classify(old: ["a", "b"], new: ["x", "y"]) == .conveyor)
    }

    @Test("Removing from the middle is discontinuous")
    func midQueueRemoval() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["a", "c"]) == .discontinuous)
        #expect(RibbonChange.classify(old: ["a", "b", "c", "d"], new: ["a", "b", "d"]) == .discontinuous)
    }

    @Test("Removing from the tail is discontinuous")
    func tailRemoval() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["a", "b"]) == .discontinuous)
    }

    @Test("A timeout that outlives its right-hand neighbour is discontinuous")
    func headOutlivesNeighbour() {
        // An autorepeat-extended head keeps "a" alive while the middle entry expires.
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["a", "c"]) == .discontinuous)
    }

    @Test("Reordering is discontinuous")
    func reorder() {
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["c", "b", "a"]) == .discontinuous)
        #expect(RibbonChange.classify(old: ["a", "b", "c"], new: ["b", "a", "c"]) == .discontinuous)
    }

    @Test("Prepending at the head is discontinuous")
    func prependAtHead() {
        #expect(RibbonChange.classify(old: ["b", "c"], new: ["a", "b", "c"]) == .discontinuous)
    }

    @Test("Inserting into the middle is discontinuous")
    func midQueueInsertion() {
        #expect(RibbonChange.classify(old: ["a", "c"], new: ["a", "b", "c"]) == .discontinuous)
    }

    @Test("A survivor reappearing after the appended tail is discontinuous")
    func survivorMovedBehindNewKeys() {
        #expect(RibbonChange.classify(old: ["a", "b"], new: ["x", "a", "b"]) == .discontinuous)
    }
}
