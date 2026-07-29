import Testing
@testable import KeypressCore

@Suite("Keyboard Presentation")
struct KeyboardPresentationTests {
    @Test("Stored display fields map to one presentation")
    func storedFieldsMapToPresentation() {
        #expect(
            KeyboardSettings(
                displayMode: .single,
                historyLayout: .horizontal)
                .presentation == .latest)
        #expect(
            KeyboardSettings(
                displayMode: .single,
                historyLayout: .stacked)
                .presentation == .latest)
        #expect(
            KeyboardSettings(
                displayMode: .history,
                historyLayout: .horizontal)
                .presentation == .horizontalHistory)
        #expect(
            KeyboardSettings(
                displayMode: .history,
                historyLayout: .stacked)
                .presentation == .stackedHistory)
    }

    @Test("Presentation writes canonical display fields")
    func presentationWritesCanonicalFields() {
        let cases = [
            (
                KeyboardPresentation.latest,
                DisplayMode.single,
                HistoryLayout.horizontal),
            (
                KeyboardPresentation.horizontalHistory,
                DisplayMode.history,
                HistoryLayout.horizontal),
            (
                KeyboardPresentation.stackedHistory,
                DisplayMode.history,
                HistoryLayout.stacked),
        ]

        for (presentation, displayMode, historyLayout) in cases {
            var settings = KeyboardSettings(
                displayMode: .single,
                historyLayout: .stacked)

            settings.presentation = presentation

            #expect(settings.displayMode == displayMode)
            #expect(settings.historyLayout == historyLayout)
        }
    }
}

@Suite("Stacked History Layout")
struct StackedHistoryLayoutTests {
    @Test("Preset positions map to stable screen-edge anchors")
    func presetPositionMapping() {
        let cases = [
            (
                OverlayPosition.topLeft,
                StackedHistoryHorizontalAnchor.leading,
                StackedHistoryVerticalAnchor.top),
            (
                OverlayPosition.topCenter,
                StackedHistoryHorizontalAnchor.center,
                StackedHistoryVerticalAnchor.top),
            (
                OverlayPosition.topRight,
                StackedHistoryHorizontalAnchor.trailing,
                StackedHistoryVerticalAnchor.top),
            (
                OverlayPosition.centerLeft,
                StackedHistoryHorizontalAnchor.leading,
                StackedHistoryVerticalAnchor.center),
            (
                OverlayPosition.centerRight,
                StackedHistoryHorizontalAnchor.trailing,
                StackedHistoryVerticalAnchor.center),
            (
                OverlayPosition.bottomLeft,
                StackedHistoryHorizontalAnchor.leading,
                StackedHistoryVerticalAnchor.bottom),
            (
                OverlayPosition.bottomCenter,
                StackedHistoryHorizontalAnchor.center,
                StackedHistoryVerticalAnchor.bottom),
            (
                OverlayPosition.bottomRight,
                StackedHistoryHorizontalAnchor.trailing,
                StackedHistoryVerticalAnchor.bottom),
        ]

        for (position, horizontalAnchor, verticalAnchor) in cases {
            let layout = StackedHistoryLayout(
                .anchor(
                    position: position,
                    horizontalOffset: 137,
                    verticalOffset: -42))

            #expect(layout.horizontalAnchor == horizontalAnchor)
            #expect(layout.verticalAnchor == verticalAnchor)
        }
    }

    @Test("Custom placement uses center alignment anchors")
    func customPlacementUsesCenterAnchors() {
        let layout = StackedHistoryLayout(
            .custom(
                center: NormalizedPoint(x: 0.17, y: 0.83),
                fallbackAnchor: .bottomRight))

        #expect(layout.horizontalAnchor == .center)
        #expect(layout.verticalAnchor == .center)
    }
}
