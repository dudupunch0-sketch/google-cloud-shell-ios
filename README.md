# google-cloud-shell-ios

Mobile Cloud Shell Terminal is an iPhone-first native terminal app concept for Google Cloud Shell. The product goal is to connect to Cloud Shell through the Cloud Shell API plus native SSH, then keep long-running agent work alive inside `tmux` workspaces rather than relying on iOS background socket lifetime.

Current repository status: Swift Package core library, not a complete iOS app UI yet.

## Product direction

See the PRD for the full product definition:

- `Mobile Cloud Shell Terminal PRD.md`
- `Mobile Cloud Shell Terminal PRD v0.2.html`

Core MVP principles:

1. Do not wrap Cloud Shell WebView. Use Cloud Shell API + native SSH.
2. Keep agent work in Cloud Shell `tmux` sessions named `mobile-agent_YYYYMMDD-HHmm_{letter}`.
3. On app start, show live app-managed workspaces and let the user choose; do not auto-attach to the last session.
4. Separate interactive terminal PTY traffic from management exec commands.
5. Keep private keys and OAuth tokens out of logs.

## Package layout

```text
Package.swift
Sources/MobileCloudShellCore/
  Auth/          OAuth/session abstractions and secure session storage contracts
  CloudShell/    Cloud Shell REST client, environment model, operation polling, API errors
  SSH/           SSH/key-management domain contracts and managers
  Support/       Shared support utilities such as RedactedLogger
  Terminal/      Keyboard/control-sequence helpers
  Workspace/     tmux workspace models, parsers, metadata, and name generation
Tests/MobileCloudShellCoreTests/
  XCTest coverage for the pure core slices above
```

## Implemented core slices

Current core library coverage:

- Auth session domain and storage contracts.
- Cloud Shell API client with `GetEnvironment`, `StartEnvironment`, `AddPublicKey`, `AuthorizeEnvironment`, operation polling, and redacted API error mapping.
- Workspace/tmux pure logic: workspace model, name generator, tmux session parser, metadata store.
- Terminal keyboard/control-sequence helpers.
- Redacted logging for OAuth/private-key-like material.
- `SSHClientProtocol`, `SSHConnectionProtocol`, `SSHPTYChannelProtocol` adapter protocols.
- `SSHExecResult` and `SSHPTYRequest` value types.
- `SSHEndpoint`, `SSHConnectionCredential`, `SSHConnectionConfiguration`.
- `SSHConnectionManager` and `SSHManagedPTYChannel` lifecycle helpers.
- `SSHCommandQuoter` for safe single-shell-argument quoting.
- `SSHKeyAlgorithm`, `OpenSSHPublicKey`, `SSHPrivateKeyMaterial`, and `SSHKeyPair` domain types.
- `SSHKeyManager` for load-or-create/delete orchestration.
- `SSHKeyBootstrapper` for key creation + Cloud Shell public-key registration + rollback on registration/polling failure.
- `WorkspaceRepository` management-channel orchestration for listing, creating, renaming, and killing app-managed tmux workspaces through an injected exec adapter.
- XCTest coverage for public key parsing, private key redaction/validation, command quoting, connection manager behavior, key manager behavior, bootstrap rollback paths, and workspace repository command orchestration.

Not implemented yet:

- Real iOS Keychain-backed `SSHKeyPairStore`.
- Real SSH key generation/export adapter.
- Concrete SSH library adapter.
- Terminal renderer/UI.
- iOS app project/screen skeleton.
- Real Cloud Shell smoke tests.

## Development and test commands

This repo is a Swift package. On a machine with Swift/Xcode installed:

```bash
swift test
```

The GitHub Actions workflow also runs:

```bash
swift test
```

on `macos-latest` for pushes to `main`, `feat/**`, and `hermes/**`, and for pull requests into `main`.

The current Linux handoff environment used for this documentation update did not have `swift` or `xcodebuild` installed, so only static review and `git diff --check` were run locally. Use macOS/Xcode or CI as the source of truth for compile/test validation.

## Handoff to a test-capable server

From a fresh environment:

```bash
git clone https://github.com/dudupunch0-sketch/google-cloud-shell-ios.git
cd google-cloud-shell-ios
git fetch origin
git checkout feat/ssh-key-management-core
swift test
```

If the PR is already open, inspect it with:

```bash
gh pr view --web
# or
gh pr view --json number,title,state,url,headRefName,baseRefName,statusCheckRollup
```

Recommended gate before merge:

1. `swift test` passes on macOS or CI.
2. Review confirms no sensitive material is logged by the new SSH/key code.
3. Review confirms PTY lifecycle still closes the underlying SSH connection on open/close failures.
4. Review confirms new-key rollback behavior is acceptable when public-key registration or operation polling fails.

## Next implementation slice

The SSH/key/terminal compatibility spike is captured in:

```text
docs/spikes/ssh-terminal-key-evaluation.md
```

Current recommendation from that spike:

1. Use SwiftTerm for the native terminal renderer.
2. Prefer a direct `apple/swift-nio-ssh` adapter for SSH transport, with Citadel only as a fallback wrapper.
3. Keep ECDSA P-256 as the first key algorithm and validate Keychain/Secure Enclave behavior on a real Apple device.
4. Run the documented macOS/iOS Cloud Shell smoke test before building the full SwiftUI app shell.

After the smoke test passes, the next high-value slice is Keychain-backed key storage plus the real NIOSSH connection/PTY adapter.
