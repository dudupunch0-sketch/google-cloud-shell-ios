# Mobile Cloud Shell iOS Architecture / Implementation Plan

> **For Hermes:** Use `subagent-driven-development` skill to implement this plan task-by-task after the user approves execution.

**Goal:** PRD v0.2를 기준으로 iPhone 세로모드 전용 Google Cloud Shell 네이티브 SSH 터미널 앱의 구현 가능한 아키텍처와 단계별 개발 계획을 확정한다.

**Architecture:** 앱은 Google OAuth + Cloud Shell API로 `default` environment를 준비하고, iOS Keychain에 저장한 SSH key로 Cloud Shell VM에 직접 접속한다. 사용자의 interactive terminal PTY와 tmux/session 관리용 management exec channel을 분리하고, 장기 작업 생존성은 iOS socket이 아니라 Cloud Shell 내부 `tmux` Workspace에 맡긴다.

**Tech Stack:** Swift, SwiftUI, async/await, Security/Keychain, URLSession REST client, ASWebAuthenticationSession/AppAuth 계열 OAuth, SwiftTerm 계열 terminal view, iOS-capable SSH adapter(구체 라이브러리는 Phase 1 spike로 확정), XCTest.

---

## 1. 읽은 최신 자료

최신화 후 확인한 커밋:

- `8fac0c1 Mobile Cloud Shell Terminal PRD v0.2.html 만들기`
- `7696854 Mobile Cloud Shell Terminal PRD.md 만들기`

설계 기준 문서:

- `Mobile Cloud Shell Terminal PRD.md`
- `Mobile Cloud Shell Terminal PRD v0.2.html`
- `README.md`는 현재 제목만 있는 빈 repo 수준 문서

핵심 요구 요약:

1. WebView/Cloud Shell Editor가 아니라 Cloud Shell API + 네이티브 SSH 직접 접속 앱.
2. 앱 시작 시 마지막 세션 자동 attach 금지. 살아있는 `mobile-agent_*` tmux Workspace 목록을 보여주고 사용자가 선택.
3. Workspace가 없으면 “새로 열기”만 표시.
4. 세션명은 `mobile-agent_YYYYMMDD-HHmm_{letter}`.
5. display name은 tmux session name과 분리하고 `~/.mobile-cloud-shell/workspaces.json`에 저장.
6. 세션 목록/생성/kill/metadata read-write는 interactive PTY가 아닌 management exec channel에서 실행.
7. 터미널 화면에는 상단 상태바 오른쪽 `Sessions` 버튼과 top-down drawer가 필요.
8. Ctrl/Shift one-shot/lock, Tab, Esc, 방향키, Home, End, Paste는 MVP 필수.
9. 백그라운드에서 SSH socket 생존을 보장하지 않는다. foreground 복귀 시 Cloud Shell 상태 확인, SSH 재접속, 같은 tmux session attach를 자동화한다.

---

## 2. 현재 repo 상태와 설계 전제

현재 repo에는 아직 Xcode project/app source가 없다. 따라서 이 문서는 greenfield iOS app 생성부터 시작하는 설계다.

전제:

- 초기 대상은 개인 사용자 1명, Google 개인 계정 1개.
- iPhone portrait를 우선한다. iPad/split view는 MVP 제외.
- Codex/Hermes 자동 실행은 하지 않는다. 사용자가 terminal 안에서 직접 실행한다.
- Push 알림, session output snapshot, 기존 non-app tmux session import는 MVP 이후.
- 현재 작업 환경은 Linux라 Xcode/iOS Simulator 검증은 불가하다. 실제 빌드/테스트는 macOS + Xcode 환경에서 수행해야 한다.

---

## 3. 상위 아키텍처

### 3.1 Layering

```text
SwiftUI Screens
  ↓
App Coordinators / ViewModels
  ↓
Domain Services
  - AuthSessionStore
  - CloudShellAPIClient
  - SSHKeyStore
  - SSHConnectionManager
  - WorkspaceRepository
  - TerminalSessionController
  - ReconnectCoordinator
  - KeyboardInputController
  ↓
Adapters
  - OAuth adapter
  - URLSession REST adapter
  - Keychain adapter
  - SSH library adapter
  - Terminal renderer adapter
```

핵심 규칙:

- UI는 Cloud Shell REST/SSH/tmux command를 직접 호출하지 않는다.
- concrete SSH library는 `SSHClientProtocol` 뒤에 숨긴다.
- terminal PTY channel과 management exec channel은 API 타입부터 분리한다.
- Workspace display name은 앱 domain model에서만 사용자 표시 이름이고, tmux session name은 immutable ID로 취급한다.

### 3.2 Runtime channel 분리

```text
InteractiveTerminalChannel
- tmux attach-session 결과와 연결된 PTY
- 사용자 키 입력, paste, terminal resize만 전달
- 세션 관리 명령 절대 주입 금지

ManagementExecChannel
- tmux list/new/kill
- workspaces.json read/write
- tmux has-session 확인
- 짧은 command 실행 후 stdout/stderr/exit code 반환
```

세션 전환은 `tmux switch-client`를 사용하지 않는다. 현재 PTY를 닫거나 detach한 뒤 선택 session에 새 PTY로 `tmux attach-session -t <session>`을 실행한다.

---

## 4. 제안 파일 구조

초기 Xcode project 생성 후 다음 구조를 목표로 한다.

```text
MobileCloudShellTerminal/
  App/
    MobileCloudShellTerminalApp.swift
    AppEnvironment.swift
    AppRouter.swift
  Auth/
    AuthSession.swift
    AuthSessionStore.swift
    OAuthClient.swift
  CloudShell/
    CloudShellAPIClient.swift
    CloudShellEnvironment.swift
    CloudShellOperationPoller.swift
    CloudShellErrors.swift
  SSH/
    SSHClientProtocol.swift
    SSHConnectionManager.swift
    SSHKeyStore.swift
    SSHKeyFormatter.swift
    SSHCommandQuoter.swift
  Workspace/
    Workspace.swift
    WorkspaceMetadataStore.swift
    WorkspaceRepository.swift
    TmuxSessionParser.swift
    WorkspaceNameGenerator.swift
  Terminal/
    TerminalSessionController.swift
    TerminalResizeModel.swift
    KeyboardInputController.swift
    TerminalEscapeSequences.swift
  Reconnect/
    ReconnectCoordinator.swift
    ConnectionState.swift
    LifecycleObserver.swift
  UI/
    LoginView.swift
    CloudShellStartingView.swift
    SessionPickerView.swift
    TerminalView.swift
    SessionsDrawerView.swift
    RenameWorkspaceView.swift
    KillConfirmationView.swift
    KeyboardAccessoryBar.swift
    SettingsView.swift
  Support/
    RedactedLogger.swift
    Clock.swift
    JSONCoding.swift

MobileCloudShellTerminalTests/
  CloudShellAPIClientTests.swift
  SSHCommandQuoterTests.swift
  TmuxSessionParserTests.swift
  WorkspaceMetadataStoreTests.swift
  WorkspaceNameGeneratorTests.swift
  KeyboardInputControllerTests.swift
  ReconnectCoordinatorTests.swift
```

---

## 5. Domain model 설계

### 5.1 Cloud Shell environment

```swift
struct CloudShellEnvironment: Equatable {
    enum State: String, Codable {
        case unspecified
        case suspended
        case pending
        case running
        case deleting
        case unknown
    }

    let name: String                 // users/me/environments/default
    let state: State
    let sshUsername: String?
    let sshHost: String?
    let sshPort: Int?
}
```

정책:

- `sshUsername`, `sshHost`, `sshPort`가 모두 있어야 SSH connect 가능 상태로 간주.
- API가 unknown/new state를 반환해도 앱이 crash하지 않도록 `unknown`으로 보존.

### 5.2 Workspace

```swift
struct Workspace: Identifiable, Equatable {
    var id: String { sessionName }
    let sessionName: String
    var displayName: String
    let createdAt: Date?
    let lastActivityAt: Date?
    let windowCount: Int
    let attachedClientCount: Int
    var lastOpenedAt: Date?
}
```

정책:

- UI 목록에는 live tmux session만 표시한다.
- live session에 metadata가 없으면 fallback display name을 만든다. 예: `Workspace 15:30 a`.
- 앱이 kill한 session은 metadata에서 제거한다.
- metadata에는 있지만 live session이 없으면 stale로 취급하고 UI에 표시하지 않는다.

### 5.3 Metadata schema

Cloud Shell VM 안의 파일:

```text
~/.mobile-cloud-shell/workspaces.json
```

Schema v1:

```json
{
  "schemaVersion": 1,
  "workspaces": {
    "mobile-agent_20260516-1530_a": {
      "displayName": "Codex: iOS PRD 정리",
      "createdAt": "2026-05-16T06:30:00Z",
      "updatedAt": "2026-05-16T06:45:12Z",
      "lastOpenedAt": "2026-05-16T07:01:03Z"
    }
  }
}
```

원격 write 정책:

1. management exec channel로 현재 JSON read.
2. 앱에서 JSON decode/merge.
3. 새 JSON을 원격 temp file에 write.
4. `mv`로 atomic replace.
5. parse 실패 시 기존 파일을 timestamp backup으로 옮기고 빈 schema v1 생성.

Cloud Shell에 `jq`가 있다고 가정하지 않는다. JSON merge는 앱 안에서 한다.

---

## 6. 핵심 service 설계

### 6.1 AuthSessionStore / OAuthClient

책임:

- Google 개인 계정 OAuth sign-in.
- `https://www.googleapis.com/auth/cloud-platform` scope 요청.
- access token refresh.
- token/keychain 저장과 로그 redaction.

권장 구현:

- MVP는 ASWebAuthenticationSession/AppAuth 계열 adapter로 시작.
- OAuth state/refresh capability는 Keychain에 저장.
- `RedactedLogger`를 통해 authorization header, access token, id token, private key 로그를 금지한다.

### 6.2 CloudShellAPIClient

REST API를 직접 감싼다.

필수 operation:

- `getDefaultEnvironment()`
- `startDefaultEnvironment(publicKeys:)`
- `pollOperation(name:)`
- `addPublicKey(_:)`
- `authorizeEnvironment(idToken:expireTime:)`

정책:

- Cloud Shell start는 polling + timeout + backoff를 둔다.
- quota/disabled/unavailable error는 user-facing error로 매핑한다.
- API response DTO와 domain model을 분리한다.

### 6.3 SSHKeyStore / SSHKeyFormatter

책임:

- 최초 실행 시 SSH key pair 생성.
- private key는 Keychain에 저장.
- public key는 Cloud Shell `AddPublicKey`에 전달 가능한 OpenSSH public key format으로 export.
- SSH library adapter가 사용할 private key representation 제공.

중요 spike:

- PRD는 `ecdsa-sha2-nistp256`을 권장한다.
- iOS Security/CryptoKit key와 선택 SSH library가 같은 key format을 안정적으로 다룰 수 있는지 먼저 검증한다.
- ECDSA P-256 export가 복잡하거나 SSH library 지원이 부족하면, 사용 가능한 key type을 근거와 함께 재결정한다. 단, private key는 계속 Keychain에 둔다.

### 6.4 SSHConnectionManager

책임:

- Cloud Shell SSH endpoint에 connect.
- management exec channel 생성/재사용.
- terminal PTY channel 생성.
- foreground 복귀 시 dead socket 감지 및 reconnect.
- terminal size change 시 PTY window size 전달.

Protocol sketch:

```swift
protocol SSHClientProtocol {
    func connect(endpoint: SSHEndpoint, key: SSHPrivateKeyMaterial) async throws
    func disconnect()
    func exec(_ command: String, timeout: Duration) async throws -> SSHExecResult
    func openPTY(term: String, columns: Int, rows: Int) async throws -> SSHPTYChannel
}
```

### 6.5 WorkspaceRepository

책임:

- `tmux list-sessions` stdout parse.
- `mobile-agent_` prefix filtering.
- session name 생성.
- `tmux new-session -d -s <name>` 실행.
- `tmux kill-session -t <name>` 실행.
- metadata read/write와 live session merge.

Management commands:

```bash
tmux list-sessions -F '#{session_name}|#{session_created}|#{session_activity}|#{session_windows}|#{session_attached}'
tmux has-session -t '<session-name>'
tmux new-session -d -s '<session-name>'
tmux kill-session -t '<session-name>'
```

명령어 quoting은 반드시 `SSHCommandQuoter`를 통해 단일 shell argument로 처리한다.

### 6.6 TerminalSessionController

책임:

- 선택 Workspace에 PTY attach.
- terminal renderer에 stdout/stderr stream 전달.
- keyboard accessory input을 escape sequence로 변환해 PTY stdin에 write.
- disconnect/reconnect 상태를 ViewModel에 전달.

Attach command:

```bash
exec tmux attach-session -t '<session-name>'
```

### 6.7 ReconnectCoordinator

상태 machine:

```text
idle
→ preparingCloudShell
→ connectingManagement
→ showingSessionPicker
→ connectingTerminal(session)
→ connected(session)
→ backgrounded(session)
→ reconnecting(session)
→ sessionMissing
→ error
```

Foreground 복귀 플로우:

1. 마지막 active workspace ID와 terminal size load.
2. SSH socket alive check.
3. dead면 Cloud Shell API로 environment 상태 확인.
4. environment가 꺼져 있으면 start/poll.
5. management SSH reconnect.
6. `tmux has-session -t <lastWorkspace>` 확인.
7. 있으면 terminal PTY attach.
8. 없으면 live sessions refresh 후 picker로 이동.

---

## 7. UI 설계

### 7.1 LoginView

- Google sign-in 버튼.
- 실패 시 retry와 상세 원인 표시.
- 로그인 성공 후 Cloud Shell starting flow로 이동.

### 7.2 CloudShellStartingView

상태 문구:

- `Google 로그인 확인 중...`
- `Cloud Shell 상태 확인 중...`
- `Cloud Shell 시작 중...`
- `SSH 키 등록 중...`
- `SSH 연결 중...`
- `Workspace 목록 읽는 중...`

### 7.3 SessionPickerView

두 상태:

- live mobile sessions 있음: row list + display name edit + open + 새로 열기.
- live mobile sessions 없음: empty state + 새로 열기.

정책:

- 자동 마지막 attach 없음.
- `activity`, `windows`, tmux session name을 secondary text로 표시.
- display name edit는 시작 화면에서도 가능.

### 7.4 TerminalView

구성:

```text
Top Status Bar: ● Connected · {displayName}                       [Sessions]
Terminal Renderer
Keyboard Accessory Bar: Ctrl Shift Tab Esc ← ↑ ↓ → Home End Paste
```

상태바 상태:

- `● Connected · {displayName}`
- `↻ Reconnecting · {displayName}`
- `Cloud Shell starting...`
- `Disconnected · reconnecting...`
- `Switching workspace...`

### 7.5 SessionsDrawerView

- top-down drawer만 사용. bottom sheet 금지.
- 현재 Workspace section.
- 다른 live Workspace list.
- 각 row: 전환, 이름 변경, 종료.
- `+ 새로 열기`.
- management command 중에는 terminal PTY에 어떤 문자열도 쓰지 않는다.

### 7.6 KeyboardAccessoryBar

Ctrl:

- 짧게 탭: 다음 입력 1회에만 Ctrl 적용.
- 길게 누름: Ctrl lock toggle.

Shift:

- 짧게 탭: 다음 입력 1회에만 Shift 적용.
- 길게 누름: Shift lock toggle.

필수 sequence test:

- Ctrl+C, Ctrl+D, Ctrl+R, Ctrl+L
- Tab, Shift+Tab
- Esc
- arrow keys
- Home/End
- multiline paste

Paste 정책:

- bracketed paste mode 감지/지원이 가능하면 사용.
- 대량 paste는 chunking/flow control을 adapter에서 처리.

---

## 8. 구현 단계 계획

### Phase 0: Repo bootstrap

**Objective:** iOS app skeleton과 테스트 target을 만든다.

**Files:**

- Create: `MobileCloudShellTerminal.xcodeproj`
- Create: `MobileCloudShellTerminal/App/MobileCloudShellTerminalApp.swift`
- Create: `MobileCloudShellTerminalTests/`

**Steps:**

1. Xcode에서 iOS App project 생성: SwiftUI, XCTest 포함.
2. Bundle identifier와 deployment target을 정한다.
3. 빈 앱이 simulator에서 뜨는지 확인한다.
4. 첫 commit: `chore: bootstrap iOS app project`

**Verify:**

```bash
xcodebuild test -scheme MobileCloudShellTerminal -destination 'platform=iOS Simulator,name=iPhone 15'
```

Expected: build succeeds, tests pass.

### Phase 1: dependency/feasibility spike

**Objective:** SSH + terminal + key format 조합을 확정한다.

**Files:**

- Create: `docs/spikes/ssh-terminal-key-evaluation.md`
- Modify: dependency manifest/package settings

**Steps:**

1. Terminal renderer 후보를 1개 선택하고 minimal screen에 붙인다. 기본 후보는 SwiftTerm 계열.
2. SSH library 후보가 iOS에서 다음을 지원하는지 검증한다: private key auth, PTY shell, exec command, window resize.
3. ECDSA P-256 public key OpenSSH export와 private key auth를 검증한다.
4. 실패 시 대체 key type/library 결정을 문서화한다.
5. 선택한 adapter API를 `SSHClientProtocol`에 맞춘다.

**Verify:**

- Simulator/device에서 local/fake SSH endpoint 또는 test server에 PTY open 가능.
- exec command stdout/stderr/exit code 수신 가능.
- public key format이 Cloud Shell `AddPublicKey`에 넣을 문자열로 생성 가능.

### Phase 2: pure domain models and tests

**Objective:** 네트워크/SSH 없이 검증 가능한 core logic부터 만든다.

**Files:**

- Create: `CloudShell/CloudShellEnvironment.swift`
- Create: `Workspace/Workspace.swift`
- Create: `Workspace/WorkspaceNameGenerator.swift`
- Create: `Workspace/TmuxSessionParser.swift`
- Create: `Workspace/WorkspaceMetadataStore.swift`
- Create: `Terminal/TerminalEscapeSequences.swift`
- Create: `Terminal/KeyboardInputController.swift`
- Tests under `MobileCloudShellTerminalTests/`

**Test first:**

- same-minute session names allocate `_a`, `_b`, `_c`.
- after `_z`, use `_A`.
- 52 suffixes exhausted returns user-actionable error.
- `tmux list-sessions` output parses fields correctly.
- non-`mobile-agent_` sessions are filtered out.
- metadata missing session uses fallback display name.
- Ctrl/Shift one-shot and lock behavior matches PRD.

**Verify:**

```bash
xcodebuild test -scheme MobileCloudShellTerminal -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MobileCloudShellTerminalTests/WorkspaceNameGeneratorTests
xcodebuild test -scheme MobileCloudShellTerminal -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MobileCloudShellTerminalTests/KeyboardInputControllerTests
```

### Phase 3: Auth + Cloud Shell API

**Objective:** Google login, token refresh, Cloud Shell environment 준비를 구현한다.

**Files:**

- Create: `Auth/AuthSession.swift`
- Create: `Auth/AuthSessionStore.swift`
- Create: `Auth/OAuthClient.swift`
- Create: `CloudShell/CloudShellAPIClient.swift`
- Create: `CloudShell/CloudShellOperationPoller.swift`
- Create: `CloudShell/CloudShellErrors.swift`
- Tests: fake URLProtocol or injected HTTP client tests

**Steps:**

1. OAuth adapter interface와 fake implementation test 작성.
2. Cloud Shell DTO decode test 작성.
3. `GetEnvironment` client 구현.
4. `StartEnvironment` + operation polling 구현.
5. `AddPublicKey` 구현.
6. `AuthorizeEnvironment` 구현.
7. quota/disabled/unavailable error mapping 구현.
8. token redaction logger test 작성.

**Verify:**

- Fake HTTP tests pass.
- No log contains token/private key-like fields.

### Phase 4: Keychain + SSH management channel

**Objective:** private key storage와 management exec path를 완성한다.

**Files:**

- Create: `SSH/SSHKeyStore.swift`
- Create: `SSH/SSHKeyFormatter.swift`
- Create: `SSH/SSHClientProtocol.swift`
- Create: `SSH/SSHConnectionManager.swift`
- Create: `SSH/SSHCommandQuoter.swift`
- Tests: key generation/format if feasible, command quoting tests

**Steps:**

1. Keychain create/load/delete tests 가능한 wrapper 작성.
2. OpenSSH public key formatter test 작성.
3. shell argument quoter test 작성: spaces, quotes, semicolon, newline injection.
4. SSH adapter implementation 연결.
5. management exec command timeout과 error mapping 구현.

**Verify:**

- `SSHCommandQuoterTests` passes.
- test SSH endpoint에서 `exec("printf ok")` returns `ok`.

### Phase 5: Workspace management

**Objective:** session picker에 필요한 live Workspace list/create/rename/kill을 구현한다.

**Files:**

- Create/Modify: `Workspace/WorkspaceRepository.swift`
- Create/Modify: `Workspace/WorkspaceMetadataStore.swift`
- UI: `SessionPickerView.swift`, `RenameWorkspaceView.swift`, `KillConfirmationView.swift`

**Steps:**

1. `listLiveWorkspaces()` fake SSH tests 작성.
2. `createWorkspace()` session name collision tests 작성.
3. metadata read/write parse failure backup behavior test 작성.
4. `renameWorkspace()` metadata update 구현.
5. `killWorkspace()` y/n confirmation UI와 command 실행 구현.
6. stale metadata handling 구현.

**Verify:**

- Fake management channel tests pass.
- Manual Cloud Shell smoke: create/list/rename/kill 동작.

### Phase 6: Terminal screen and keyboard

**Objective:** 선택 Workspace에 attach하고 Codex/Hermes TUI 조작 가능한 terminal UI를 만든다.

**Files:**

- Create: `Terminal/TerminalSessionController.swift`
- Create: `UI/TerminalView.swift`
- Create: `UI/KeyboardAccessoryBar.swift`
- Create: `UI/SessionsDrawerView.swift`

**Steps:**

1. terminal renderer adapter를 SwiftUI view에 embed.
2. PTY stdout stream을 renderer에 연결.
3. keyboard accessory bar input을 PTY stdin에 연결.
4. terminal resize를 PTY window change로 전달.
5. Sessions button/drawer overlay를 구현.
6. session switch 시 기존 PTY를 닫고 새 session attach.

**Verify:**

- Shell prompt 표시.
- `codex`/`hermes` TUI 화면 깨짐 최소화.
- Ctrl+C, Ctrl+R, Tab, Shift+Tab, Esc, arrows, Home/End, paste manual test 통과.

### Phase 7: Reconnect and lifecycle

**Objective:** background/foreground/network change 후 자동 복구한다.

**Files:**

- Create: `Reconnect/ReconnectCoordinator.swift`
- Create: `Reconnect/ConnectionState.swift`
- Create: `Reconnect/LifecycleObserver.swift`
- Modify: `AppRouter.swift`, `TerminalSessionController.swift`, `SSHConnectionManager.swift`

**Steps:**

1. state machine unit tests 작성.
2. app background 시 current workspace ID와 terminal size 저장.
3. foreground 복귀 시 socket health check.
4. dead socket이면 Cloud Shell API state 확인/start.
5. management SSH reconnect.
6. last workspace `tmux has-session` 후 auto attach.
7. missing이면 picker로 이동.
8. status bar reconnect state 표시.

**Verify:**

- T-13: 앱 background 10분 후 session 살아있으면 자동 attach.
- T-14: Cloud Shell VM 종료 후 복귀 시 picker empty 또는 새로 열기 안내.
- T-15: Wi-Fi ↔ 5G 전환 후 reconnect attach.

### Phase 8: settings, polish, security pass

**Objective:** 개인용 MVP 사용 안정성을 높인다.

**Files:**

- Create: `UI/SettingsView.swift`
- Modify: `Support/RedactedLogger.swift`
- Modify: error views/toasts

**Steps:**

1. 로그아웃 구현.
2. SSH key 재생성 option 구현.
3. font size setting 구현.
4. Cloud Shell quota/key/auth/tmux error 문구 정리.
5. token/private key redaction audit.
6. README에 local build/run 방법 추가.

**Verify:**

- 로그아웃 후 token/key state 정리.
- key 재생성 후 AddPublicKey + reconnect 성공.
- README 절차로 새 checkout에서 빌드 가능.

---

## 9. Acceptance test mapping

PRD T-01~T-15를 다음 테스트로 매핑한다.

| PRD ID | 자동화/수동 | 검증 위치 |
|---|---|---|
| T-01 session 없음 | UI test + fake repo | SessionPickerView empty state |
| T-02 새로 열기 | unit + integration | WorkspaceNameGenerator, WorkspaceRepository |
| T-03 같은 분 반복 | unit | WorkspaceNameGeneratorTests |
| T-04 시작 화면 이름 변경 | UI/integration | SessionPickerView + metadata fake |
| T-05 drawer 이름 변경 | UI/integration | SessionsDrawerView + metadata fake |
| T-06 Workspace 전환 | real Cloud Shell smoke | PTY close/new attach, old session alive |
| T-07 현재 Workspace kill Y | integration + real smoke | kill command + picker route |
| T-08 kill N | UI test | no command executed |
| T-09 Ctrl tap + c | unit + manual | KeyboardInputController |
| T-10 Ctrl lock + r | unit + manual | KeyboardInputController |
| T-11 Shift+Tab | unit + manual | TerminalEscapeSequences |
| T-12 multiline paste | unit + manual | paste chunking/bracketed paste |
| T-13 background 10분 | real device manual | ReconnectCoordinator |
| T-14 VM 종료 후 복귀 | real Cloud Shell manual | CloudShellAPIClient + picker fallback |
| T-15 Wi-Fi/5G 전환 | real device manual | reconnect attach |

---

## 10. 리스크와 대응

### R-01 SSH library 선택 리스크

문제: iOS에서 private key auth + PTY + exec + resize를 모두 안정적으로 지원하는 SSH library 선택이 MVP의 최대 기술 리스크다.

대응: Phase 1에서 앱 구조 구현 전에 SSH/terminal/key spike를 먼저 끝낸다. concrete library를 직접 UI/domain에 노출하지 않고 adapter 뒤에 둔다.

### R-02 ECDSA key format 리스크

문제: iOS Keychain/CryptoKit key를 OpenSSH public/private key format으로 변환하는 과정이 복잡할 수 있다.

대응: `SSHKeyFormatter`를 독립 모듈로 만들고, key type은 spike 결과로 확정한다. PRD 권장값은 ECDSA P-256이지만, 실제 library compatibility가 우선이다.

### R-03 Cloud Shell lifecycle external limits

문제: Cloud Shell quota/inactivity/session cap은 앱이 우회할 수 없다.

대응: UX copy에서 “작업은 tmux에 유지되지만 Cloud Shell 자체 제한은 존재”를 명확히 표시하고, quota/unavailable error를 별도 상태로 노출한다.

### R-04 management command injection

문제: session name/display name이 shell command에 섞일 때 injection 위험이 있다.

대응: display name은 shell command argument로 직접 쓰지 않는다. session name은 generator/validator를 통과한 값만 사용한다. 그래도 모든 shell argument는 `SSHCommandQuoter`로 quote한다.

### R-05 terminal UX 품질

문제: Codex/Hermes TUI는 control keys, resize, paste, alternate screen 동작에 민감하다.

대응: keyboard mapping unit test와 real TUI manual suite를 MVP gate로 둔다. terminal renderer/library는 Phase 1에서 TUI smoke까지 확인한다.

---

## 11. 열린 결정 사항

1. Bundle identifier와 Google OAuth client 설정값.
2. 최종 SSH library/terminal renderer 조합.
3. minimum iOS version.
4. Cloud Shell API `AuthorizeEnvironment`에 필요한 id token 획득 방식.
5. private key keychain accessibility 정책: 기본 후보는 `ThisDeviceOnly` 계열.
6. App Store 배포 여부. 개인용 빌드면 OAuth 검수/정책 범위를 최소화할 수 있다.

---

## 12. 다음 행동 제안

1. 먼저 Phase 1 spike를 진행한다. SSH/terminal/key 조합이 확정되지 않으면 이후 UI 구현이 되돌아갈 수 있다.
2. spike 성공 기준을 만족하면 Xcode project skeleton과 pure domain tests를 만든다.
3. 구현은 작은 PR 단위로 나눈다.
   - PR 1: Xcode project + domain tests.
   - PR 2: Auth + Cloud Shell API fake tests.
   - PR 3: SSH/key/management channel.
   - PR 4: Workspace picker/session management.
   - PR 5: Terminal UI/keyboard.
   - PR 6: reconnect/lifecycle/security polish.

이 문서는 설계/계획만 포함한다. 앱 코드 구현은 사용자 승인 후 별도 작업으로 진행한다.
