public enum SSHCommandQuoter {
    public static func quote(_ argument: String) -> String {
        guard !argument.isEmpty else {
            return "''"
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func join(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}
