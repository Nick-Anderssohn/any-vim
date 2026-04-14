import XCTest
import AppKit
import Carbon.HIToolbox
@testable import AnyVim

// MARK: - SelectorRecorder

/// An NSView subclass that accepts first responder status and records
/// the names of Edit selectors it receives via @objc paste:/copy:/selectAll:/cut:.
final class SelectorRecorder: NSView {

    var receivedSelectors: [String] = []

    override var acceptsFirstResponder: Bool { true }

    @objc func paste(_ sender: Any?) {
        receivedSelectors.append("paste:")
    }

    @objc func copy(_ sender: Any?) {
        receivedSelectors.append("copy:")
    }

    @objc override func selectAll(_ sender: Any?) {
        receivedSelectors.append("selectAll:")
    }

    @objc func cut(_ sender: Any?) {
        receivedSelectors.append("cut:")
    }
}

// MARK: - VimPanelTests

@MainActor
final class VimPanelTests: XCTestCase {

    private var panel: VimPanel!
    private var recorder: SelectorRecorder!

    override func setUp() {
        super.setUp()
        panel = VimPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        recorder = SelectorRecorder(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        panel.contentView?.addSubview(recorder)
        panel.makeFirstResponder(recorder)
    }

    override func tearDown() {
        panel.close()
        panel = nil
        recorder = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    // MARK: - Tests

    func test_performKeyEquivalent_CmdV_dispatchesPasteAction() {
        let event = makeEvent(
            characters: "v",
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command],
            keyCode: UInt16(kVK_ANSI_V)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertTrue(result, "performKeyEquivalent should return true for Cmd+V")
        XCTAssertEqual(recorder.receivedSelectors, ["paste:"],
            "Recorder should receive paste: selector for Cmd+V")
    }

    func test_performKeyEquivalent_CmdC_dispatchesCopyAction() {
        let event = makeEvent(
            characters: "c",
            charactersIgnoringModifiers: "c",
            modifierFlags: [.command],
            keyCode: UInt16(kVK_ANSI_C)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertTrue(result, "performKeyEquivalent should return true for Cmd+C")
        XCTAssertEqual(recorder.receivedSelectors, ["copy:"],
            "Recorder should receive copy: selector for Cmd+C")
    }

    func test_performKeyEquivalent_CmdA_dispatchesSelectAllAction() {
        let event = makeEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifierFlags: [.command],
            keyCode: UInt16(kVK_ANSI_A)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertTrue(result, "performKeyEquivalent should return true for Cmd+A")
        XCTAssertEqual(recorder.receivedSelectors, ["selectAll:"],
            "Recorder should receive selectAll: selector for Cmd+A")
    }

    func test_performKeyEquivalent_CmdX_dispatchesCutAction() {
        let event = makeEvent(
            characters: "x",
            charactersIgnoringModifiers: "x",
            modifierFlags: [.command],
            keyCode: UInt16(kVK_ANSI_X)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertTrue(result, "performKeyEquivalent should return true for Cmd+X")
        XCTAssertEqual(recorder.receivedSelectors, ["cut:"],
            "Recorder should receive cut: selector for Cmd+X")
    }

    func test_performKeyEquivalent_CmdShiftV_fallsThroughToSuper() {
        let event = makeEvent(
            characters: "V",
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command, .shift],
            keyCode: UInt16(kVK_ANSI_V)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertFalse(result,
            "performKeyEquivalent should fall through (return false) for Cmd+Shift+V")
        XCTAssertTrue(recorder.receivedSelectors.isEmpty,
            "Recorder should NOT receive paste: for Cmd+Shift+V")
    }

    func test_performKeyEquivalent_plainV_fallsThroughToSuper() {
        let event = makeEvent(
            characters: "v",
            charactersIgnoringModifiers: "v",
            modifierFlags: [],
            keyCode: UInt16(kVK_ANSI_V)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertFalse(result,
            "performKeyEquivalent should fall through (return false) for plain v (no Command)")
        XCTAssertTrue(recorder.receivedSelectors.isEmpty,
            "Recorder should NOT receive paste: for plain v without Command")
    }

    func test_performKeyEquivalent_CmdOptionV_fallsThroughToSuper() {
        let event = makeEvent(
            characters: "√",
            charactersIgnoringModifiers: "v",
            modifierFlags: [.command, .option],
            keyCode: UInt16(kVK_ANSI_V)
        )

        let result = panel.performKeyEquivalent(with: event)

        XCTAssertFalse(result,
            "performKeyEquivalent should fall through (return false) for Cmd+Option+V")
        XCTAssertTrue(recorder.receivedSelectors.isEmpty,
            "Recorder should NOT receive paste: for Cmd+Option+V")
    }
}
