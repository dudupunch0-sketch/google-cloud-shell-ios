# Spike: SSH / terminal / key compatibility for iOS Cloud Shell

Updated: 2026-05-23 05:39:46 UTC
Branch: hermes/ssh-terminal-key-spike
Base: origin/main at fd8c0ba

## Question

Can this app use a native Swift stack for Google Cloud Shell SSH on iOS, including:

- private-key SSH authentication,
- non-interactive exec commands for workspace management,
- interactive PTY shell for the terminal screen,
- terminal resize events,
- OpenSSH public key generation/registration compatibility,
- iOS-safe private key storage?

## Verdict: PARTIAL

The Swift/iOS library stack looks feasible, but the final answer still needs one macOS/iOS smoke test against a real Cloud Shell environment.

Recommended default stack:

1. Terminal renderer: `migueldeicaza/SwiftTerm`.
2. SSH transport: direct `apple/swift-nio-ssh` adapter first.
3. Key type: ECDSA P-256 (`ecdsa-sha2-nistp256`) first, matching the current core default.
4. Key storage: Keychain `ThisDeviceOnly` P-256 key material first; evaluate Secure Enclave P-256 as a stronger follow-up if the UX is acceptable.
5. Fallback SSH wrapper: `orlandos-nl/Citadel` only if direct NIOSSH implementation becomes too slow or brittle.

## Evidence checked

Local research clones were inspected under `/tmp/hermes-ssh-spike`.

Repository metadata from GitHub API:

| Candidate | Stars | Last push checked | License | Notes |
| --- | ---: | --- | --- | --- |
| `apple/swift-nio-ssh` | 497 | 2026-05-15 | Apache-2.0 | Official SwiftNIO SSH implementation. |
| `migueldeicaza/SwiftTerm` | 1546 | 2026-05-18 | MIT | Native Swift terminal emulator. Includes iOS + NIOSSH sample. |
| `orlandos-nl/Citadel` | 363 | 2026-04-04 | MIT | High-level SSH client/server wrapper built on NIOSSH. |
| `NMSSH/NMSSH` | 767 | 2024-03-17 | MIT | Objective-C libssh2 wrapper with vendored libssh2/OpenSSL. |
| `jakeheis/Shout` | 376 | 2024-06-10 | MIT | Swift libssh2 wrapper, Package.swift is macOS-only. |

Package/source findings:

- `apple/swift-nio-ssh`
  - Package declares iOS support from iOS 13.
  - Provides `NIOSSHPrivateKey` initializers for Ed25519, P-256, P-384, P-521, and Darwin Secure Enclave P-256.
  - `String(openSSHPublicKey:)` exports an OpenSSH-style public key string (`algorithm base64blob`).
  - Tests include public-key client auth and channel request round trips for `ExecRequest`, `PseudoTerminalRequest`, `ShellRequest`, and `WindowChangeRequest`.
  - Current main branch uses `swift-tools-version:6.1`; production dependency must be pinned to a version compatible with the chosen Xcode/CI toolchain.
- `SwiftTerm`
  - Package declares iOS support from iOS 14.
  - Provides native `TerminalView`/UIKit integration and terminal delegate callbacks.
  - Its iOS sample connects `TerminalView` to NIOSSH, forwards user input as `SSHChannelData`, and sends `WindowChangeRequest` from `sizeChanged`.
- `Citadel`
  - Package declares iOS support from iOS 17.
  - Provides higher-level `SSHClient.executeCommand`, `executeCommandStream`, `withPTY`, `withTTY`, `withExec`, and `TTYStdinWriter.changeSize` APIs.
  - Provides auth helpers for RSA, Ed25519, P-256, P-384, and P-521 private keys.
  - Risk: its Package.swift depends on `Wellz26/swift-nio-ssh` (`0.3.4 ..< 0.4.0`), a fork, not directly on `apple/swift-nio-ssh`.
- `NMSSH`
  - CocoaPods spec uses vendored `libssh2`, `libssl`, and `libcrypto` static libraries for iOS/macOS.
  - This adds signing, architecture, OpenSSL, and App Store review surface area that the native Swift stack avoids.
- `Shout`
  - Swift Package declares only macOS support and a system `libssh2` dependency.
  - Not suitable for this iOS app as the primary path.

## Feasibility questions

### 1. Can we do SSH private-key auth on iOS?

Likely yes.

Direct NIOSSH supports public-key auth through a `NIOSSHClientUserAuthenticationDelegate` that returns:

```swift
NIOSSHUserAuthenticationOffer(
    username: sshUsername,
    serviceName: "ssh-connection",
    offer: .privateKey(.init(privateKey: nioPrivateKey))
)
```

Relevant key options:

| Option | Fit | Pros | Cons / Unknowns |
| --- | --- | --- | --- |
| CryptoKit `P256.Signing.PrivateKey` stored in Keychain | Best first implementation | Simple, matches existing `.ecdsaP256` default, can reconstruct `NIOSSHPrivateKey(p256Key:)`, public key can be exported as OpenSSH string. | Private scalar is exportable into app memory during auth. Must store only in Keychain and redact logs. |
| CryptoKit `SecureEnclave.P256.Signing.PrivateKey` | Strong follow-up | NIOSSH has `secureEnclaveP256Key` initializer; private key can remain hardware-backed. | Needs device testing; may trigger user-presence/biometry UX depending access control; simulator support may be limited. |
| Ed25519 | Possible fallback | Good SSH algorithm and NIOSSH supports it. | Secure Enclave does not support Ed25519; existing core default is P-256. Need confirm Cloud Shell accepts it. |
| RSA | Avoid unless required | Broad legacy SSH support. | Larger/slower; `ssh-rsa` can be disabled on modern servers due SHA-1 concerns. |

Recommendation: keep `.ecdsaP256` as the default. Implement the first app adapter using Keychain-stored P-256 raw key material, then run a second smoke test for Secure Enclave P-256 before deciding whether to upgrade.

### 2. Can we register the public key with Cloud Shell?

Likely yes, but must be smoke-tested.

The project already has `CloudShellAPIClient.addPublicKey(_:)`, and current key domain supports OpenSSH public key strings for:

- `ecdsa-sha2-nistp256`
- `ssh-ed25519`
- `ssh-rsa`

NIOSSH can produce the OpenSSH public string for its key:

```swift
let nioKey = NIOSSHPrivateKey(p256Key: p256PrivateKey)
let publicKey = String(openSSHPublicKey: nioKey.publicKey) + " cloud-shell-ios"
```

Cloud Shell server-side policy still needs actual validation because `addPublicKey` accepts a string, but acceptance by the API and acceptance by the SSH daemon can differ.

### 3. Can we run non-interactive management commands?

Yes in the stack.

Direct NIOSSH can open a session channel and send `SSHChannelRequestEvent.ExecRequest(command:wantReply:)`.
Citadel wraps the same concept with `executeCommand` and `executeCommandStream`.

This is enough for the existing `WorkspaceManagementExecuting` adapter used by `WorkspaceRepository`:

- `tmux list-sessions ...`
- `tmux new-session ...`
- metadata read/write commands under `~/.mobile-cloud-shell`
- `tmux kill-session ...`

Implementation constraint: keep management exec channels separate from the interactive PTY channel. Do not multiplex terminal keystrokes and repository commands through the same channel.

### 4. Can we run an interactive PTY shell and resize it?

Likely yes.

Direct NIOSSH supports these channel events:

- `PseudoTerminalRequest`
- `ShellRequest`
- `WindowChangeRequest`
- `ExecRequest`

SwiftTerm's iOS sample already demonstrates the needed shape:

- create a NIOSSH session channel,
- send `PseudoTerminalRequest(term: "xterm-256color", cols, rows, ...)`,
- send `ShellRequest`,
- feed remote `SSHChannelData` bytes into `TerminalView.feed(byteArray:)`,
- send user input from `TerminalViewDelegate.send(...)` back as `SSHChannelData`,
- send `WindowChangeRequest` from `TerminalViewDelegate.sizeChanged(...)`.

Citadel also provides `withPTY` / `withTTY` and `TTYStdinWriter.changeSize`, so it is a viable wrapper if direct NIOSSH proves too verbose.

### 5. Is SwiftTerm the right terminal renderer?

Yes for the first native app.

Pros:

- native Swift package,
- iOS support from iOS 14,
- already exposes UIKit `TerminalView`,
- has delegate methods for input, paste/copy, title, range changes, and terminal size changes,
- includes an iOS NIOSSH example that maps naturally to this app.

Risks / follow-up:

- The sample is UIKit-first; if the app uses SwiftUI, wrap `TerminalView` in `UIViewRepresentable`.
- Need custom keyboard accessory bar for mobile terminal keys: Esc, Tab, Ctrl, arrows, slash/tilde, paste.
- Need test rendering with tmux, vim/nano, full-screen TUIs, ANSI colors, and Japanese/Korean text input.

Avoid a custom terminal renderer for MVP. Avoid `xterm.js` in WKWebView unless SwiftTerm hits a blocker.

## Candidate comparison

| Area | Preferred | Backup | Avoid for MVP |
| --- | --- | --- | --- |
| Terminal UI | SwiftTerm | xterm.js in WKWebView | Custom renderer |
| SSH transport | Direct `apple/swift-nio-ssh` | Citadel | NMSSH/Shout |
| Key algorithm | ECDSA P-256 | Ed25519 | RSA unless required |
| Key storage | Keychain `ThisDeviceOnly` P-256 raw material | Secure Enclave P-256 after smoke test | Plain files/UserDefaults |
| Workspace commands | Separate exec channels | Citadel `executeCommand` | Running commands through interactive shell text |

## Proposed app-layer interfaces

Keep `MobileCloudShellCore` mostly dependency-light. Put NIOSSH/SwiftTerm adapters in the future iOS app target or a separate adapter target.

Suggested protocols:

```swift
public protocol SSHSessionConnecting {
    func connect(endpoint: CloudShellSSHEndpoint, key: AppSSHPrivateKey) async throws -> SSHSession
}

public protocol SSHSession {
    func execute(_ command: String) async throws -> SSHExecResult
    func openPTY(term: String, cols: Int, rows: Int) async throws -> PTYSession
    func close() async
}

public protocol PTYSession {
    var output: AsyncThrowingStream<Data, Error> { get }
    func send(_ data: Data) async throws
    func resize(cols: Int, rows: Int) async throws
    func close() async
}
```

Then implement adapters:

- `NIOSSHSessionConnector`: Cloud Shell endpoint + NIOSSH auth delegate.
- `NIOSSHWorkspaceManagementExecutor`: conforms to existing `WorkspaceManagementExecuting`.
- `SwiftTermTerminalView`: UI wrapper that binds `PTYSession.output` to `TerminalView.feed(...)` and delegate input to `PTYSession.send(...)`.
- `KeychainP256SSHKeyStore`: stores/reloads key material under a service/account name, using `ThisDeviceOnly` accessibility.

## Required smoke test before production implementation

Run this on macOS with Xcode and, ideally, a real iPhone. Simulator is useful, but Secure Enclave must be device-tested.

### Key smoke test

- [ ] Generate P-256 key in app code.
- [ ] Export OpenSSH public key string.
- [ ] Register it with `CloudShellAPIClient.addPublicKey`.
- [ ] Poll operation completion.
- [ ] Connect to `sshHost:sshPort` as `sshUsername` using NIOSSH public-key auth.
- [ ] Run `whoami` or `echo cloud-shell-ios-ok` via exec channel.
- [ ] Confirm no private key material appears in logs/errors.

### PTY smoke test

- [ ] Open PTY with `xterm-256color`, 80x24.
- [ ] Attach to shell.
- [ ] Feed output into SwiftTerm.
- [ ] Type simple commands from software keyboard.
- [ ] Resize terminal and verify `stty size` changes remotely.
- [ ] Run `tmux new -A -s mobile-cloud-shell-smoke`.
- [ ] Run a full-screen command (`top`, `vim`, or `nano`) and verify input/rendering.
- [ ] Background/foreground app and verify reconnect behavior is understandable, even if not final.

### Workspace management smoke test

- [ ] Use separate exec channel to run `tmux list-sessions` while PTY is open.
- [ ] Use `WorkspaceRepository` through the NIOSSH executor to list/create/rename/kill a test workspace.
- [ ] Confirm interactive PTY output is not contaminated by management command output.
- [ ] Confirm command failure errors include operation names, not full shell command strings.

## Risks

1. Toolchain mismatch
   - Latest `apple/swift-nio-ssh` main uses Swift tools 6.1.
   - Pin to a released version compatible with the Xcode used by `macos-latest` and the eventual local Mac.
2. Citadel dependency fork
   - Citadel is convenient but currently depends on a forked `swift-nio-ssh` package.
   - Prefer direct Apple NIOSSH unless implementation cost becomes the blocker.
3. Secure Enclave UX
   - Strong security, but access-control settings may introduce prompts or device-only restore limitations.
   - Use Keychain-stored P-256 first for MVP if Secure Enclave interrupts SSH auth UX.
4. Cloud Shell algorithm policy
   - P-256 should fit OpenSSH, but actual Cloud Shell acceptance must be tested.
5. Terminal mobile UX
   - SSH feasibility is not the same as usable terminal UX.
   - Keyboard accessory keys, paste behavior, safe area, and font sizing are MVP-critical.

## Decision

Proceed with direct NIOSSH + SwiftTerm design.

Next implementation slice that can still mostly be prepared from WSL:

1. Add a design doc or adapter skeleton for `SSHSession` / `PTYSession` protocols without pulling NIOSSH into the core package yet.
2. Add `docs/spikes/ssh-terminal-key-evaluation.md` as the source of truth for the future macOS/iOS smoke test.
3. When a macOS runner/device is available, create the minimal app-target spike and execute the smoke checklist above.

Do not start a full SwiftUI app skeleton until this smoke test has confirmed the SSH/key/PTY path.
