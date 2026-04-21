# Codex Nomad Product Vision

## One-Line Positioning

Codex Nomad is a phone-first operations center for coding agents running locally and in the cloud.

It is not a mobile terminal, not a small IDE, and not a prettier clone of Happy. The product exists to keep coding agents moving when the developer leaves the desk.

## Core Promise

Your agents should not stop just because you closed the laptop, walked outside, got on a call, or only have your phone.

Codex Nomad lets a developer:

- Run Codex, Claude Code, OpenCode, and future agent CLIs from a trusted machine.
- Receive push alerts only when the agent is blocked or needs approval.
- Review diffs, tests, commands, and risks from the phone.
- Approve, reject, answer, interrupt, or escalate work from the phone.
- Move a session from a local machine to a cloud runner when the PC cannot stay on.
- Keep cloud usage controlled with visible runner hours, caps, and shutdown rules.

## Market Reality

Parts of this already exist.

- Happy has mobile/web control, E2EE, voice, push, and Codex/Claude support.
- HAPI and Happier are pushing local-first and multi-agent remote control.
- GitHub Mobile already exposes cloud coding agents for Copilot users.
- OpenAI and Anthropic will keep improving first-party agent experiences.

The gap is not "remote terminal on phone." That is already weak as a category.

The gap is a phone-native agent operations workflow:

- Action inbox instead of terminal spam.
- Safe approvals instead of raw `y` and `n`.
- Local privacy mode plus cloud continuation.
- Runner budget controls.
- Multi-machine and multi-agent visibility.
- Fast mobile review loops for diffs, tests, and blocked work.

## Happy Coder Review Lessons

Current public App Store signals show Happy is not theoretical competition. It has strong social proof and users are already using it for real production workflows from phones.

What users clearly love:

- Leaving the terminal while agents keep working.
- Continuing Claude/Codex sessions from airport lines, travel, and away-from-desk moments.
- Push notifications for permission requests and task completion.
- Clickable/suggested response options instead of typing everything into a terminal.
- Simple pairing with an existing local setup.

What users still reveal as opportunity:

- Permission prompts must be reliable. A review specifically called out Codex permission buttons becoming non-responsive and forcing unsafe "yolo" modes or session restarts.
- The phone UX must understand agent context, not just mirror terminal output.
- Codex patch rendering, command rendering, session resume, offline machine state, and worktree/session management are now table stakes.
- Free local mode is expected. Charging before proving a better local loop will lose.

Our response:

- Build Local Mode first and make it free.
- Do not ship approval buttons until they are adapter-backed and reliable.
- Make the Agent Inbox the primary screen.
- Treat permission requests, diffs, tests, and blocked states as structured events.
- Keep terminal access available, but do not make it the main product.

## Product Modes

### Local Mode

Local Mode is free.

It runs on the user's own laptop, desktop, or home server. It is the privacy-first mode and should be good enough that people recommend the app without paying.

Local Mode includes:

- Unlimited local sessions.
- One or more paired devices, based on account limits.
- Phone control of local Codex/Claude/OpenCode sessions.
- E2EE relay.
- Push alerts for blocked local agents.
- Basic diff/test/command review.
- No included cloud compute.

The reason Local Mode is free is simple: competitors are giving local control away. Charging for the basic local loop would slow adoption.

### Cloud Mode

Cloud Mode is paid because cloud compute has real cost.

It lets the user continue work when the PC is off, asleep, unreachable, or too weak for a long job.

Cloud Mode includes:

- Ephemeral isolated runners.
- Git repo clone or encrypted workspace snapshot restore.
- Agent execution inside the runner.
- Phone control through the same E2EE relay protocol.
- Auto-shutdown on idle.
- Per-session and monthly spend caps.
- Runner size selection.
- Optional encrypted session history and snapshots.

Blunt security truth: in Cloud Mode, the runner must see the workspace while it executes. The relay and backend should never see plaintext code, prompts, diffs, or terminal output.

## Platform Strategy

Build with Flutter for both Android and iOS from day one, but ship Android first.

Android first is the right execution order because:

- Faster testing and distribution.
- Easier side-loading and early power-user adoption.
- Fewer App Store payment constraints during validation.
- The current repo is already Android-first.

iOS should not be a separate rewrite. Keep the Flutter app production-grade and add iOS once the core local/cloud agent workflow is proven.

The first web surface is not the product. Web exists for:

- Marketing.
- Checkout and invoices.
- Account recovery.
- Downloading the daemon.
- Team admin.
- Cloud usage and spend controls.
- Documentation and enterprise trust pages.

Do not build a full web agent client until the phone product is already excellent.

## Product UX

The app opens to an Agent Inbox.

The default screen should show what needs the developer's attention:

- Permission requests.
- Blocked sessions.
- Failing tests.
- Diff reviews.
- Runner idle warnings.
- PR-ready sessions.
- Cloud budget alerts.

The main tabs:

- Inbox.
- Sessions.
- Review.
- Cloud.
- Machines.

The terminal is available, but it is not the primary product.

## Approval Model

Approvals must be real product objects, not terminal shortcuts.

Every approval should show:

- Agent.
- Project.
- Machine or cloud runner.
- Command or action requested.
- Risk level.
- Files touched.
- Recent agent summary.
- Allow once.
- Deny.
- Always allow this exact rule for this repo.
- Require confirmation for similar future actions.

Never market unsafe automation. The product should make users faster without making them reckless.

## Plans

Local usage should be free. Paid plans should monetize cloud, machine scale, history, teams, and control.

### Free Local

Price: $0.

Includes:

- Unlimited local sessions.
- 1 connected machine.
- 1 mobile device.
- Local E2EE relay.
- Basic push alerts.
- Basic diff and approval review.
- No cloud hours.

### Personal

Price target: $9/month or $90/year.

Includes:

- 3 connected machines.
- 2 mobile devices.
- Unlimited local sessions.
- Better notification controls.
- Longer encrypted local-session history.
- No included cloud hours.

This plan may be skipped at launch if simplicity matters. Free Local plus Pro Cloud is cleaner.

### Pro Cloud

Price target: $19/month or $190/year.

Includes:

- 5 connected machines.
- Unlimited local sessions.
- 100 standard cloud runner-hours/month.
- 1 parallel cloud runner.
- Standard runner by default.
- Performance runner available using credits.
- Encrypted cloud session history.
- Spend cap and auto-shutdown controls.

### Power

Price target: $49/month.

Includes:

- 10 connected machines.
- 500 standard cloud runner-hours/month.
- 3 parallel cloud runners.
- Standard, performance, and heavy runners.
- Longer encrypted history.
- Faster runner starts.
- Advanced automation rules.

### Team

Price target: $29/user/month plus cloud usage.

Includes:

- Shared projects.
- Pooled cloud usage.
- Team approval policies.
- Audit logs.
- Role-based access.
- Shared machines or BYO runners.

### Enterprise

Price: custom.

Includes:

- SSO.
- BYO cloud or private VPC runners.
- Retention controls.
- Compliance documentation.
- Dedicated support.
- Custom legal/security review.

## Cloud Add-Ons

Cloud must be metered. Unlimited cloud at low subscription prices will destroy margins.

Possible add-ons:

- 100 standard runner-hours: $5.
- 500 standard runner-hours: $20.
- 100 performance runner-hours: $12.
- 100 heavy runner-hours: $30.
- Extra connected machine: $2/month.
- Extra parallel cloud runner: $10/month.
- Extra encrypted storage: $2 per 10GB/month.

Every cloud screen must show current usage, estimated hourly cost, and hard monthly cap.

## Machine Model

Users should understand machines as first-class assets.

Each machine has:

- Name.
- OS.
- Online/offline status.
- Last seen.
- Local agent support.
- Cloud handoff eligibility.
- Allowed projects.
- Approval policy.
- Notification policy.

Pro Cloud allows 5 machines. Power allows 10 machines. Team uses per-seat or pooled machine limits.

## Visual Direction

The app should feel premium, dense, and operational.

Brand palette:

- Primary experience: premium dark mode.
- Base: near-black surfaces.
- Accent: electric purple.
- Secondary tones: muted violet panels, white text, neutral gray dividers.
- Status colors stay semantic: green for success, amber for warning, red for danger.
- No purple gradients, glow blobs, or decorative noise. Black carries the premium feel; purple is the action accent.

Typography:

- Primary font: Bricolage Grotesque.
- Use zero or normal letter spacing.
- Avoid tiny decorative labels.
- Prioritize strong hierarchy and readable mobile review screens.

Icon direction:

- Use a consistent premium rounded icon set.
- Icons must communicate actions quickly: approve, deny, diff, test, cloud, runner, machine, risk, pause, resume.
- Do not mix random icon styles.
- Material Symbols Rounded or Phosphor-style icons are acceptable directions.

UI principles:

- Agent Inbox first, not marketing text.
- Dense but clean.
- 8px card radius.
- Clear status colors, not a one-note palette.
- No decorative gradient blobs.
- No terminal-first experience.
- Every screen should help the user decide or act.

## Security Positioning

Use precise claims.

Allowed claim:

"End-to-end encrypted relay. Our relay and backend do not see plaintext code, prompts, diffs, commands, or terminal output. Cloud runners process your workspace only when you explicitly use Cloud Mode."

Do not claim:

"No data can ever leak."

Reality:

- Local Mode can be designed so backend and relay never see plaintext.
- Push payloads must not contain code or prompts.
- Cloud runners necessarily see workspace contents while running.
- Upstream AI providers see whatever the user's chosen agent sends to them.
- Crash logs and analytics must be scrubbed.
- Support staff must not have plaintext session access.

## Legal Positioning

Codex Nomad should be a control plane for official tools and user-authorized agents.

Rules:

- Do not impersonate OpenAI, Anthropic, GitHub, or any model provider.
- Do not proxy consumer Claude/OpenAI accounts in a way that violates provider terms.
- Prefer BYO API key, official CLI auth, team/enterprise auth, or direct provider partnerships.
- Do not bundle model usage unless the economics and provider terms are clear.
- Use web checkout first, then handle app-store billing only after policy review.

## What We Are Building

We are building the mobile operations layer for coding agents.

The app wins if developers say:

"I left my desk and my agent still finished the work because Codex Nomad told me exactly when to approve, reject, review, or move it to cloud."

That is the standard.
