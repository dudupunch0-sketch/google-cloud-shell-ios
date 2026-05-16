import XCTest
@testable import MobileCloudShellCore

final class KeyboardInputControllerTests: XCTestCase {
    func testCtrlShortTapAppliesToOneTextInputOnly() {
        var controller = KeyboardInputController()

        controller.tapCtrl()

        XCTAssertEqual(controller.encodeTextInput("c"), "\u{03}")
        XCTAssertFalse(controller.modifierState.isCtrlActive)
        XCTAssertEqual(controller.encodeTextInput("c"), "c")
    }

    func testCtrlLongPressTogglesLockAndPersistsAcrossInputs() {
        var controller = KeyboardInputController()

        controller.longPressCtrl()

        XCTAssertTrue(controller.modifierState.isCtrlLocked)
        XCTAssertEqual(controller.encodeTextInput("r"), "\u{12}")
        XCTAssertTrue(controller.modifierState.isCtrlLocked)
        XCTAssertEqual(controller.encodeTextInput("l"), "\u{0C}")

        controller.longPressCtrl()

        XCTAssertFalse(controller.modifierState.isCtrlLocked)
        XCTAssertEqual(controller.encodeTextInput("r"), "r")
    }

    func testCtrlShortTapSupportsRequiredControlCharacters() {
        var controller = KeyboardInputController()

        controller.tapCtrl()
        XCTAssertEqual(controller.encodeTextInput("d"), "\u{04}")

        controller.tapCtrl()
        XCTAssertEqual(controller.encodeTextInput("l"), "\u{0C}")
    }

    func testShiftShortTapAppliesToNextSpecialKeyOnly() {
        var controller = KeyboardInputController()

        controller.tapShift()

        XCTAssertEqual(controller.encodeSpecialKey(.tab), "\u{1B}[Z")
        XCTAssertFalse(controller.modifierState.isShiftActive)
        XCTAssertEqual(controller.encodeSpecialKey(.tab), "\t")
    }

    func testShiftLongPressTogglesLockAndPersistsAcrossSpecialKeys() {
        var controller = KeyboardInputController()

        controller.longPressShift()

        XCTAssertTrue(controller.modifierState.isShiftLocked)
        XCTAssertEqual(controller.encodeSpecialKey(.leftArrow), "\u{1B}[1;2D")
        XCTAssertTrue(controller.modifierState.isShiftLocked)
        XCTAssertEqual(controller.encodeSpecialKey(.rightArrow), "\u{1B}[1;2C")

        controller.longPressShift()

        XCTAssertFalse(controller.modifierState.isShiftLocked)
        XCTAssertEqual(controller.encodeSpecialKey(.leftArrow), "\u{1B}[D")
    }

    func testTextInputConsumesBothCtrlAndShiftOneShotModifiers() {
        var controller = KeyboardInputController()

        controller.tapCtrl()
        controller.tapShift()

        XCTAssertEqual(controller.encodeTextInput("c"), "\u{03}")
        XCTAssertFalse(controller.modifierState.isCtrlActive)
        XCTAssertFalse(controller.modifierState.isShiftActive)
        XCTAssertEqual(controller.encodeSpecialKey(.tab), "\t")
    }

    func testTerminalEscapeSequencesCoverRequiredAccessoryKeys() {
        XCTAssertEqual(TerminalEscapeSequences.escape, "\u{1B}")
        XCTAssertEqual(TerminalEscapeSequences.tab, "\t")
        XCTAssertEqual(TerminalEscapeSequences.arrow(.up), "\u{1B}[A")
        XCTAssertEqual(TerminalEscapeSequences.arrow(.down), "\u{1B}[B")
        XCTAssertEqual(TerminalEscapeSequences.arrow(.right), "\u{1B}[C")
        XCTAssertEqual(TerminalEscapeSequences.arrow(.left), "\u{1B}[D")
        XCTAssertEqual(TerminalEscapeSequences.shiftedArrow(.left), "\u{1B}[1;2D")
        XCTAssertEqual(TerminalEscapeSequences.shiftedArrow(.right), "\u{1B}[1;2C")
        XCTAssertEqual(TerminalEscapeSequences.home, "\u{1B}[H")
        XCTAssertEqual(TerminalEscapeSequences.end, "\u{1B}[F")
    }

    func testBracketedPasteWrapsMultilineText() {
        let paste = TerminalEscapeSequences.bracketedPaste("line 1\nline 2")

        XCTAssertEqual(paste, "\u{1B}[200~line 1\nline 2\u{1B}[201~")
    }
}
