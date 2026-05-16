import Foundation

public enum TerminalArrowKey: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

public enum TerminalSpecialKey: Equatable, Sendable {
    case tab
    case escape
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
    case home
    case end
}

public enum TerminalEscapeSequences {
    public static let escape = "\u{1B}"
    public static let tab = "\t"
    public static let shiftTab = "\u{1B}[Z"
    public static let home = "\u{1B}[H"
    public static let end = "\u{1B}[F"

    public static func control(_ input: String) -> String? {
        guard input.count == 1, let scalar = input.lowercased().unicodeScalars.first else {
            return nil
        }
        guard scalar.value >= 97 && scalar.value <= 122 else {
            return nil
        }
        return String(UnicodeScalar(scalar.value & 0x1F)!)
    }

    public static func arrow(_ key: TerminalArrowKey) -> String {
        switch key {
        case .up:
            return "\u{1B}[A"
        case .down:
            return "\u{1B}[B"
        case .right:
            return "\u{1B}[C"
        case .left:
            return "\u{1B}[D"
        }
    }

    public static func shiftedArrow(_ key: TerminalArrowKey) -> String {
        switch key {
        case .up:
            return "\u{1B}[1;2A"
        case .down:
            return "\u{1B}[1;2B"
        case .right:
            return "\u{1B}[1;2C"
        case .left:
            return "\u{1B}[1;2D"
        }
    }

    public static func specialKey(_ key: TerminalSpecialKey, shifted: Bool = false) -> String {
        switch key {
        case .tab:
            return shifted ? shiftTab : tab
        case .escape:
            return escape
        case .upArrow:
            return shifted ? shiftedArrow(.up) : arrow(.up)
        case .downArrow:
            return shifted ? shiftedArrow(.down) : arrow(.down)
        case .leftArrow:
            return shifted ? shiftedArrow(.left) : arrow(.left)
        case .rightArrow:
            return shifted ? shiftedArrow(.right) : arrow(.right)
        case .home:
            return home
        case .end:
            return end
        }
    }

    public static func bracketedPaste(_ text: String) -> String {
        "\u{1B}[200~\(text)\u{1B}[201~"
    }
}
