import Foundation

public struct KeyboardModifierState: Equatable, Sendable {
    private var ctrlOneShot = false
    private var shiftOneShot = false

    public private(set) var isCtrlLocked = false
    public private(set) var isShiftLocked = false

    public var isCtrlActive: Bool { ctrlOneShot || isCtrlLocked }
    public var isShiftActive: Bool { shiftOneShot || isShiftLocked }

    public init() {}

    mutating func tapCtrl() {
        ctrlOneShot = true
    }

    mutating func longPressCtrl() {
        isCtrlLocked.toggle()
        ctrlOneShot = false
    }

    mutating func tapShift() {
        shiftOneShot = true
    }

    mutating func longPressShift() {
        isShiftLocked.toggle()
        shiftOneShot = false
    }

    mutating func consumeOneShots() {
        ctrlOneShot = false
        shiftOneShot = false
    }
}

public struct KeyboardInputController: Equatable, Sendable {
    public private(set) var modifierState: KeyboardModifierState

    public init(modifierState: KeyboardModifierState = KeyboardModifierState()) {
        self.modifierState = modifierState
    }

    public mutating func tapCtrl() {
        modifierState.tapCtrl()
    }

    public mutating func longPressCtrl() {
        modifierState.longPressCtrl()
    }

    public mutating func tapShift() {
        modifierState.tapShift()
    }

    public mutating func longPressShift() {
        modifierState.longPressShift()
    }

    public mutating func encodeTextInput(_ input: String) -> String {
        if modifierState.isCtrlActive, let control = TerminalEscapeSequences.control(input) {
            modifierState.consumeOneShots()
            return control
        }

        modifierState.consumeOneShots()
        return input
    }

    public mutating func encodeSpecialKey(_ key: TerminalSpecialKey) -> String {
        let output = TerminalEscapeSequences.specialKey(key, shifted: modifierState.isShiftActive)
        modifierState.consumeOneShots()
        return output
    }

    public func encodePaste(_ text: String, bracketedPasteEnabled: Bool = true) -> String {
        bracketedPasteEnabled ? TerminalEscapeSequences.bracketedPaste(text) : text
    }
}
