# Project status and handoff

Updated: 2026-05-16 10:41:39 UTC
Branch: `feat/ssh-key-management-core`
Base branch: `main`
Latest reviewed commit before this documentation update: `c3844b3`

## Why this document exists

This is the handoff note for continuing work on a server that can actually run Swift/Xcode tests. The current environment used for final review and docs did not have `swift` or `xcodebuild`, so code-level validation here was limited to static review and Git checks.

## Current project shape

The repo is currently a Swift Package named `MobileCloudShellTerminal` exposing the `MobileCloudShellCore` library. It is not yet a full iOS app project with SwiftUI screens.

Implemented core areas:

- Auth/session domain contracts.
- Cloud Shell API client and operation polling.
- Cloud Shell environment/error mapping.
- Workspace/tmux pure domain logic.
- Terminal keyboard/control-sequence helpers.
- SSH/key-management core domain and orchestration contracts.

The product target remains the PRD-defined iPhone portrait native SSH terminal for Google Cloud Shell, with long-running work preserved in Cloud Shell `tmux` workspaces.

## Current branch contents

`feat/ssh-key-management-core` contains two implementation commits before this docs handoff:

- `bc73452 feat: add SSH key management core`
- `c3844b3 fix: resolve SSH core CI compile errors`

Files added by the branch relative to `main`:

```text
Sources/MobileCloudShellCore/SSH/SSHClientProtocol.swift
Sources/MobileCloudShellCore/SSH/SSHCommandQuoter.swift
Sources/MobileCloudShellCore/SSH/SSHConnectionManager.swift
Sources/MobileCloudShellCore/SSH/SSHKeyBootstrapper.swift
Sources/MobileCloudShellCore/SSH/SSHKeyManager.swift
Sources/MobileCloudShellCore/SSH/SSHKeyTypes.swift
Tests/MobileCloudShellCoreTests/OpenSSHPublicKeyTests.swift
Tests/MobileCloudShellCoreTests/SSHCommandQuoterTests.swift
Tests/MobileCloudShellCoreTests/SSHConnectionManagerTests.swift
Tests/MobileCloudShellCoreTests/SSHKeyBootstrapperTests.swift
Tests/MobileCloudShellCoreTests/SSHKeyManagerTests.swift
Tests/MobileCloudShellCoreTests/SSHPrivateKeyMaterialTests.swift
```

## What the SSH/key-management slice provides

### Public adapter protocols

- `SSHClientProtocol`: creates SSH connections from `SSHConnectionConfiguration`.
- `SSHConnectionProtocol`: supports exec, PTY open, and close.
- `SSHPTYChannelProtocol`: supports PTY read/write/close.

These intentionally hide the future concrete SSH library from the core domain.

### Connection orchestration

- `SSHEndpoint` validates/trims username and host, validates port `1...65535`, and maps from `CloudShellEnvironment`.
- `SSHConnectionManager` creates configured connections, runs one-shot exec commands, and opens managed PTY channels.
- `SSHManagedPTYChannel` closes both the PTY channel and the underlying SSH connection.

Important lifecycle fix already applied:

- If `openPTY` fails after the SSH connection opens, the connection is closed before rethrowing.

### Key domain and validation

- `OpenSSHPublicKey` parses and normalizes one-line OpenSSH public keys.
- Supported algorithms: `ecdsa-sha2-nistp256`, `ssh-ed25519`, `ssh-rsa`.
- Public key blobs are base64-decoded and checked against the declared OpenSSH wire algorithm.
- `SSHPrivateKeyMaterial` accepts PEM-looking private key material, validates OpenSSH private key magic for `OPENSSH PRIVATE KEY`, and redacts `description`/`debugDescription`.

Important validation fix already applied:

- Public keys containing literal newlines are rejected; tests use escaped `\n` strings correctly.

### Key manager/bootstrapper

- `SSHKeyManager` loads an existing key pair or generates/saves a new one.
- Generated algorithm mismatches are rejected before saving.
- `SSHKeyBootstrapper` registers newly created keys through Cloud Shell `AddPublicKey` and waits for the returned operation.
- Existing keys are not re-registered by default, but can be registered with `registerExistingKey: true`.

Important rollback fix already applied:

- If registration or operation polling fails for a newly created key, the local key pair is deleted.
- If deletion itself fails, `SSHKeyBootstrapError.rollbackFailed` is thrown instead of silently leaving an unregistered generated key.

### Command quoting

- `SSHCommandQuoter.quote(_:)` wraps each shell argument in single quotes.
- Embedded single quotes are escaped with the POSIX shell close-quote/backslash-quote/reopen-quote sequence. For example, `a'b` becomes `'a'\''b'`.
- `SSHCommandQuoter.join(_:)` joins quoted arguments with spaces.

Use this for future management exec commands. Do not inject management commands into the interactive PTY.

## Review status

Final static code-quality re-review result for this slice:

- Critical issues: none.
- Important issues: none.
- Minor note: `SSHKeyBootstrapError.rollbackFailed` could optionally implement `LocalizedError` for better user-facing descriptions, but this is not merge-blocking.
- Verdict: approved, pending test execution in a Swift-capable environment.

Local checks that were run here:

```bash
git diff --check
```

Result: passed.

Checks not run here because tools were unavailable:

```bash
swift test
xcodebuild test ...
```

## How to continue on the next server

Use a macOS or Swift-capable environment.

```bash
git clone https://github.com/dudupunch0-sketch/google-cloud-shell-ios.git
cd google-cloud-shell-ios
git fetch origin
git checkout feat/ssh-key-management-core
swift test
```

If using GitHub CLI:

```bash
gh pr view --json number,title,state,url,headRefName,baseRefName,statusCheckRollup
```

If tests pass:

1. Confirm CI is green on the PR.
2. Merge `feat/ssh-key-management-core` into `main` using the repo's preferred merge strategy.
3. Start the next slice from updated `main`.

If tests fail:

1. Fix compile/test errors on `feat/ssh-key-management-core`.
2. Re-run `swift test`.
3. Push the fix to the same branch so the PR updates.

## Recommended next slice after merge

Recommended order:

1. SSH/key/terminal compatibility spike.
   - Pick candidate SSH library and terminal renderer.
   - Verify iOS support for private-key auth, exec, PTY shell, and PTY resize.
   - Verify generated key format compatibility with Cloud Shell `AddPublicKey` and the SSH library.
2. Keychain-backed key store and real key generation/export.
   - Implement `SSHKeyPairStore` using Keychain.
   - Implement `SSHKeyGenerating` with the selected algorithm/library path.
   - Keep private key material redacted in logs and errors.
3. Workspace repository over management exec channel.
   - Use `SSHConnectionManager.execute` for `tmux list/new/kill` and metadata read/write.
   - Quote all shell arguments with `SSHCommandQuoter`.
   - Keep all management commands out of interactive terminal PTY.
4. Terminal UI skeleton.
   - Session picker.
   - Terminal screen.
   - Keyboard accessory bar.
   - Top-down sessions drawer.
5. Reconnect/lifecycle coordinator.
   - Foreground reconnect.
   - Last workspace reattach if tmux session exists.
   - Picker fallback if the session is gone.

## Known open decisions

- Final concrete SSH library.
- Final terminal renderer.
- Real key algorithm if ECDSA P-256 export/auth compatibility is poor.
- Bundle identifier and Google OAuth client configuration.
- Keychain accessibility policy; default candidate is a `ThisDeviceOnly` class.
- Whether to add `LocalizedError` to `SSHKeyBootstrapError` before user-facing UI consumes it.

## Merge readiness checklist

- [ ] PR opened against `main`.
- [ ] `swift test` passes on macOS or CI.
- [ ] No private key/OAuth token material appears in logs or error descriptions.
- [ ] Reviewer accepts rollback semantics for failed key registration/polling.
- [ ] Reviewer accepts that this slice is adapter/domain core only, not a real SSH library implementation.
