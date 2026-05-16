import Foundation

public enum SSHKeyAlgorithm: String, CaseIterable, Equatable, Hashable, Sendable {
    case ecdsaP256 = "ecdsa-sha2-nistp256"
    case ed25519 = "ssh-ed25519"
    case rsa = "ssh-rsa"
}

public enum SSHKeyError: Error, Equatable, LocalizedError, Sendable {
    case malformedPublicKey
    case unsupportedPublicKeyAlgorithm(String)
    case invalidPublicKeyBlob
    case invalidPrivateKeyMaterial
    case algorithmMismatch(expected: SSHKeyAlgorithm, actual: SSHKeyAlgorithm)

    public var errorDescription: String? {
        switch self {
        case .malformedPublicKey:
            return "OpenSSH public key is malformed."
        case .unsupportedPublicKeyAlgorithm(let algorithm):
            return "OpenSSH public key algorithm is unsupported: \(algorithm)."
        case .invalidPublicKeyBlob:
            return "OpenSSH public key blob does not match the declared OpenSSH algorithm."
        case .invalidPrivateKeyMaterial:
            return "SSH private key material is not a valid PEM-looking private key block."
        case .algorithmMismatch(let expected, let actual):
            return "Generated SSH key algorithm \(actual.rawValue) did not match preferred algorithm \(expected.rawValue)."
        }
    }
}

public struct OpenSSHPublicKey: Equatable, Hashable, Sendable {
    public let rawValue: String
    public let algorithm: SSHKeyAlgorithm
    public let base64Blob: String
    public let comment: String?

    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .newlines) == nil else {
            throw SSHKeyError.malformedPublicKey
        }

        let parts = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            throw SSHKeyError.malformedPublicKey
        }

        guard let algorithm = SSHKeyAlgorithm(rawValue: parts[0]) else {
            throw SSHKeyError.unsupportedPublicKeyAlgorithm(parts[0])
        }

        let blob = parts[1]
        guard let decodedBlob = decodeBase64(blob), Self.isValidOpenSSHBlob(decodedBlob, for: algorithm) else {
            throw SSHKeyError.invalidPublicKeyBlob
        }

        let comment = parts.count > 2 ? parts.dropFirst(2).joined(separator: " ") : nil
        self.algorithm = algorithm
        self.base64Blob = blob
        self.comment = comment

        if let comment {
            self.rawValue = "\(algorithm.rawValue) \(blob) \(comment)"
        } else {
            self.rawValue = "\(algorithm.rawValue) \(blob)"
        }
    }

    private static func isValidOpenSSHBlob(_ data: Data, for algorithm: SSHKeyAlgorithm) -> Bool {
        var reader = SSHBinaryReader(data: data)
        guard let blobAlgorithm = reader.readUTF8String(), blobAlgorithm == algorithm.rawValue else {
            return false
        }

        switch algorithm {
        case .ecdsaP256:
            guard let curveName = reader.readUTF8String(),
                  curveName == "nistp256",
                  let publicPoint = reader.readDataString(),
                  !publicPoint.isEmpty else {
                return false
            }
        case .ed25519:
            guard let publicKey = reader.readDataString(), !publicKey.isEmpty else {
                return false
            }
        case .rsa:
            guard let exponent = reader.readDataString(), !exponent.isEmpty,
                  let modulus = reader.readDataString(), !modulus.isEmpty else {
                return false
            }
        }

        return reader.isAtEnd
    }
}

public struct SSHPrivateKeyMaterial: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let pemString: String

    public init(pemString: String) throws {
        let trimmed = pemString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SSHKeyError.invalidPrivateKeyMaterial
        }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.count >= 3,
              let beginLabel = Self.pemBoundaryLabel(from: lines[0], marker: "BEGIN"),
              let endLabel = Self.pemBoundaryLabel(from: lines[lines.count - 1], marker: "END"),
              beginLabel == endLabel,
              beginLabel.uppercased().hasSuffix("PRIVATE KEY") else {
            throw SSHKeyError.invalidPrivateKeyMaterial
        }

        let bodyLines = lines.dropFirst().dropLast()
        guard !bodyLines.isEmpty, bodyLines.allSatisfy({ !$0.isEmpty }) else {
            throw SSHKeyError.invalidPrivateKeyMaterial
        }

        let body = bodyLines.joined()
        guard let decodedBody = decodeBase64(body) else {
            throw SSHKeyError.invalidPrivateKeyMaterial
        }
        if beginLabel.uppercased() == "OPENSSH PRIVATE KEY" {
            guard decodedBody.starts(with: Self.openSSHPrivateKeyMagic) else {
                throw SSHKeyError.invalidPrivateKeyMaterial
            }
        }

        self.pemString = ([lines[0]] + Array(bodyLines) + [lines[lines.count - 1]]).joined(separator: "\n")
    }

    public var description: String {
        "SSHPrivateKeyMaterial(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    private static let openSSHPrivateKeyMagic = Data(Array("openssh-key-v1".utf8) + [0])

    private static func pemBoundaryLabel(from line: String, marker: String) -> String? {
        let prefix = "-----\(marker) "
        let suffix = "-----"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix), line.count > prefix.count + suffix.count else {
            return nil
        }

        let start = line.index(line.startIndex, offsetBy: prefix.count)
        let end = line.index(line.endIndex, offsetBy: -suffix.count)
        let label = String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }
}

public struct SSHKeyPair: Equatable, Sendable {
    public let publicKey: OpenSSHPublicKey
    public let privateKey: SSHPrivateKeyMaterial

    public init(publicKey: OpenSSHPublicKey, privateKey: SSHPrivateKeyMaterial) {
        self.publicKey = publicKey
        self.privateKey = privateKey
    }

    public var algorithm: SSHKeyAlgorithm {
        publicKey.algorithm
    }
}

private struct SSHBinaryReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readUTF8String() -> String? {
        guard let data = readDataString() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    mutating func readDataString() -> Data? {
        guard let length = readUInt32Length(), length >= 0, offset + length <= data.count else {
            return nil
        }
        let start = offset
        offset += length
        return data.subdata(in: start..<offset)
    }

    private mutating func readUInt32Length() -> Int? {
        guard offset + 4 <= data.count else { return nil }
        var length = 0
        for byte in data[offset..<(offset + 4)] {
            length = (length << 8) | Int(byte)
        }
        offset += 4
        return length
    }
}

private let base64CharacterSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")

private func decodeBase64(_ value: String) -> Data? {
    guard !value.isEmpty,
          value.rangeOfCharacter(from: base64CharacterSet.inverted) == nil else {
        return nil
    }

    var padded = value
    let remainder = padded.count % 4
    if remainder == 1 {
        return nil
    }
    if remainder > 0 {
        padded += String(repeating: "=", count: 4 - remainder)
    }

    guard let data = Data(base64Encoded: padded), !data.isEmpty else {
        return nil
    }
    return data
}
