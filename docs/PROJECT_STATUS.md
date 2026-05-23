# Project status and handoff

Updated: 2026-05-23 07:07:18 UTC
Branch: `hermes/keychain-ssh-key-store`
Base branch: `main`
Latest reviewed commit before this update: `e64cab5`

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
- Workspace repository core over an injected management exec adapter: live list, create, rename metadata, kill, malformed metadata backup.
- SSH/key/terminal compatibility spike document.
- Apple Keychain-backed SSH key pair store slice in this branch.

The product target remains the PRD-defined iPhone portrait native SSH terminal for Google Cloud Shell, with long-running work preserved in Cloud Shell `tmux` workspaces.

## Current branch contents

`main` already contains the SSH/key/terminal compatibility spike merge. Current branch `hermes/keychain-ssh-key-store` adds the Keychain-backed SSH key pair store slice:

```text
Sources/MobileCloudShellCore/SSH/KeychainSSHKeyPairStore.swift
Tests/MobileCloudShellCoreTests/KeychainSSHKeyPairStoreTests.swift
```

This slice keeps private key persistence behind the existing `SSHKeyPairStore` protocol before real key generation and NIOSSH adapters are added.

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
- `KeychainSSHKeyPairStore` persists `SSHKeyPair` JSON envelopes as a generic-password item in Apple Keychain.
- Default Keychain accessibility is `whenUnlockedThisDeviceOnly`; `afterFirstUnlockThisDeviceOnly` is also exposed for future lifecycle testing.
- Store configuration rejects empty service/account values; app integration should pass a stable per-Google-account identifier as the Keychain account.
- Keychain OSStatus errors report fixed operation names and status codes, not key material or arbitrary command strings.
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

## What the workspace repository slice provides

- `WorkspaceManagementExecuting`: an injected management exec abstraction so workspace commands stay separate from interactive PTY traffic.
- `SSHWorkspaceManagementExecutor`: production bridge from `SSHConnectionManager.execute` to the repository.
- `WorkspaceRepository.listLiveWorkspaces()`: runs `tmux list-sessions` via management exec, parses app-managed sessions, reads metadata, and merges fallback display names.
- `WorkspaceRepository.createWorkspace()`: allocates the next `mobile-agent_YYYYMMDD-HHmm_{letter}` name, creates a detached tmux session, and persists display metadata.
- `WorkspaceRepository.renameWorkspace()`: updates metadata only; it does not send tmux/session-management strings to a terminal PTY.
- `WorkspaceRepository.killWorkspace()`: kills the app-managed tmux session and removes its metadata.
- Malformed metadata is backed up to `workspaces.json.invalid.$(date +%Y%m%d%H%M%S)` before replacement during mutating operations.
- All session-name inputs are validated as app-managed names before command construction, shell arguments use `SSHCommandQuoter`, and command-failure errors report operation labels instead of full metadata-bearing shell commands.

## Review status

Current Keychain store slice status:

- Implementation and XCTest coverage have been added.
- Tests use an injected fake Keychain accessor; they do not touch the developer or CI login Keychain.
- Local WSL environment still has no `swift` or `xcodebuild`, so compile/test validation must run on macOS, CI, or another Swift-capable host.
- `swift test --filter KeychainSSHKeyPairStoreTests` was attempted locally and failed at tool discovery with `swift: command not found`.
- `git diff --check` passed locally.

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
git checkout hermes/keychain-ssh-key-store
swift test --filter KeychainSSHKeyPairStoreTests
swift test
```

If using GitHub CLI after a PR is open:

```bash
gh pr view --json number,title,state,url,headRefName,baseRefName,statusCheckRollup
```

If tests pass:

1. Confirm CI is green on the PR.
2. Merge `hermes/keychain-ssh-key-store` into `main` using the repo's preferred merge strategy.
3. Start the next slice from updated `main`.

If tests fail:

1. Fix compile/test errors on `hermes/keychain-ssh-key-store`.
2. Re-run `swift test --filter KeychainSSHKeyPairStoreTests` and `swift test`.
3. Push the fix to the same branch so the PR updates.

## Recommended next slice after merge

Recommended order:

1. Real ECDSA P-256 key generation/export.
   - Implement `SSHKeyGenerating` with CryptoKit P-256.
   - Export the generated public key in OpenSSH `ecdsa-sha2-nistp256` format.
   - Keep generated private key material out of logs and failure messages.
2. Direct NIOSSH connection/PTY adapter skeleton.
   - Pin an `apple/swift-nio-ssh` version compatible with the active Xcode/CI toolchain.
   - Map `SSHClientProtocol`, `SSHConnectionProtocol`, and `SSHPTYChannelProtocol` to NIOSSH session channels.
   - Keep management exec channels separate from interactive PTY channels.
3. Terminal UI skeleton when a macOS/Xcode environment is available.
   - Session picker.
   - Terminal screen.
   - Keyboard accessory bar.
   - Top-down sessions drawer.
4. Reconnect/lifecycle coordinator.
   - Foreground reconnect.
   - Last workspace reattach if tmux session exists.
   - Picker fallback if the session is gone.

## Known open decisions

- Final concrete SSH library version pin.
- Final terminal renderer.
- Whether Secure Enclave P-256 should replace Keychain-stored P-256 after device smoke testing.
- Bundle identifier and Google OAuth client configuration.
- Exact Google user subject/account identifier to use as the Keychain account.
- Whether `whenUnlockedThisDeviceOnly` or `afterFirstUnlockThisDeviceOnly` is better after app lifecycle testing.
- Whether to add `LocalizedError` to `SSHKeyBootstrapError` before user-facing UI consumes it.

## Merge readiness checklist

- [ ] PR opened against `main`.
- [ ] `swift test --filter KeychainSSHKeyPairStoreTests` passes on macOS, CI, or another Swift-capable host.
- [ ] Full `swift test` passes on macOS, CI, or another Swift-capable host.
- [ ] No private key/OAuth token material appears in logs or error descriptions.
- [ ] Reviewer accepts Keychain accessibility defaults and non-synchronizing device-only storage.
- [ ] Reviewer accepts that this slice stores existing key material only; it does not generate keys or connect over SSH yet.
