import Foundation

public enum WorkspaceNameGenerationError: Error, Equatable, LocalizedError, Sendable {
    case suffixesExhausted(prefix: String)

    public var errorDescription: String? {
        switch self {
        case .suffixesExhausted(let prefix):
            return "No available one-letter workspace suffix remains for \(prefix). Ask the user to enter a name or wait until the next minute."
        }
    }
}

public struct WorkspaceNameGenerator: Sendable {
    public static let managedPrefix = "mobile-agent"

    private static let suffixes = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }

    private let calendar: Calendar

    public init(
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
    }

    public func makeName(for date: Date, existingSessionNames: Set<String>) throws -> String {
        let prefix = "\(Self.managedPrefix)_\(Self.timestamp(from: date, calendar: calendar))"

        for suffix in Self.suffixes {
            let candidate = "\(prefix)_\(suffix)"
            if !existingSessionNames.contains(candidate) {
                return candidate
            }
        }

        throw WorkspaceNameGenerationError.suffixesExhausted(prefix: prefix)
    }

    public static func isManagedSessionName(_ name: String) -> Bool {
        let expectedPrefix = "\(managedPrefix)_"
        guard name.hasPrefix(expectedPrefix) else { return false }

        let rest = name.dropFirst(expectedPrefix.count)
        let pieces = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return false }

        return isValidTimestamp(String(pieces[0])) && isValidSuffix(String(pieces[1]))
    }

    private static func isValidTimestamp(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.count == 13 else { return false }
        guard characters[8] == "-" else { return false }

        let dateCharacters = characters[0..<8]
        let timeCharacters = characters[9..<13]
        return dateCharacters.allSatisfy(isASCIIIntegerDigit) && timeCharacters.allSatisfy(isASCIIIntegerDigit)
    }

    private static func isASCIIIntegerDigit(_ character: Character) -> Bool {
        guard let scalar = String(character).unicodeScalars.first else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }

    private static func isValidSuffix(_ value: String) -> Bool {
        guard value.count == 1, let scalar = value.unicodeScalars.first else { return false }
        return (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func timestamp(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}
