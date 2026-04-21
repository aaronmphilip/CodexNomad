# Local V1 Build Scope

## Goal

Ship the best free local phone companion for Codex and Claude Code before building paid cloud.

Local V1 must let a developer keep working from a phone while the laptop or desktop is still on. It should feel premium, fast, secure, and more focused than a terminal mirror.

## Non-Negotiable User Story

A developer starts a Codex or Claude Code session on a computer, leaves the desk, receives a push alert when the agent needs attention, opens the phone, reviews the request with enough context, approves or rejects safely, and sees the session continue.

## Keep From Current Repo

- Go daemon as the local machine process.
- Flutter app as the phone client.
- Go relay as the E2EE transport layer.
- QR pairing.
- X25519 plus XChaCha20-Poly1305 session encryption.
- Codex and Claude launch support.

## Replace Or Redesign

- Terminal-first home screen.
- Raw terminal scraping as the main event model.
- `approve = y` and `reject = n` as the product approval layer.
- Fragile diff extraction from terminal text.
- Cloud-first screens before local reliability is solved.

## Local V1 Product Surface

### Phone App

Main tabs:

- Inbox.
- Sessions.
- Review.
- Terminal.
- Machines.

The app opens to Inbox.

Inbox cards:

- Permission request.
- Agent blocked.
- Task complete.
- Tests failed.
- Diff ready.
- Session disconnected.

Session screen:

- Agent name.
- Machine name.
- Project path.
- Status.
- Last event.
- Prompt composer.
- Approval queue.
- Terminal drawer.

Review screen:

- Changed files.
- Inline diff.
- Test result.
- Approve/reject actions.

Machines screen:

- Paired machines.
- Online/offline status.
- Agent availability.
- Last seen.
- Remove machine.

### Desktop Daemon

Required commands:

```sh
codexnomad pair
codexnomad pair claude
codexnomad codex [args...]
codexnomad claude [args...]
codexnomad status
codexnomad logs
codexnomad devices
codexnomad devices revoke DEVICE_ID
```

Daemon responsibilities:

- Maintain machine identity.
- Pair phone securely.
- Start Codex/Claude under a PTY.
- Stream encrypted terminal output.
- Detect structured approval opportunities.
- Detect changed files through git.
- Send structured session events.
- Receive typed phone commands.
- Handle reconnect without losing session state.

### Relay

Relay responsibilities:

- Route encrypted frames only.
- Authenticate sessions with short-lived tickets or local development token.
- Never store plaintext.
- Never inspect prompt/code/diff content.
- Support reconnect.
- Support fanout to paired phone devices.

## Agent Adapter Requirements

Local V1 must introduce adapters even if the first version still falls back to PTY for hard cases.

Adapter output events:

- `session_started`
- `terminal_output`
- `permission_requested`
- `permission_resolved`
- `diff_ready`
- `file_changed`
- `tests_started`
- `tests_finished`
- `blocked`
- `task_complete`
- `session_disconnected`

Approval actions:

- `approve_once`
- `approve_for_session`
- `reject`
- `interrupt`
- `send_text`

Do not expose "approve all" as a main button in V1.

## Security Acceptance

Local V1 can claim:

"End-to-end encrypted local agent control. The relay cannot read prompts, code, diffs, commands, or terminal output."

Requirements:

- Phone and machine each generate device keys.
- Every session uses fresh ephemeral keys.
- Relay frames are ciphertext except handshake metadata.
- Push notification payloads contain no code, prompts, diffs, or terminal text.
- Encrypted sequence numbers have replay protection.
- Pairing QR expires.
- Lost phone can be revoked from the machine with `codexnomad devices revoke DEVICE_ID`.

## UX Acceptance

Local V1 is good enough only if:

- Pairing takes under 60 seconds.
- Starting Codex/Claude from the daemon is one command.
- Permission prompts appear as native cards.
- Terminal remains readable but secondary.
- Diffs are readable on phone.
- A disconnected phone can reconnect to the live session.
- The app feels premium with Bricolage Grotesque typography and a consistent rounded icon system.

## Build Order

1. Machine identity and pairing.
2. Session list and reconnect.
3. Codex/Claude PTY launch.
4. E2EE relay messages.
5. Terminal stream.
6. Structured event protocol.
7. Permission request cards.
8. Diff/file review.
9. Push notification bridge.
10. Production packaging and release channel.

## Explicitly Out Of Scope For Local V1

- Paid cloud runners.
- Team accounts.
- Web agent client.
- Full IDE editing.
- Multi-agent orchestration.
- Bundled model usage.
