# QA Scripts

## Local E2E Smoke

Run this before real phone QA:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\qa\local-e2e-smoke-windows.ps1
```

The smoke test:

- builds the relay and daemon binaries
- starts a local relay
- starts a demo daemon session using `powershell.exe` as the agent process
- captures the pairing URI from daemon stdout
- runs `daemon/cmd/mobile-smoke` as a simulated phone
- completes the mobile/daemon E2EE handshake
- sends stdin through encrypted relay frames
- verifies terminal output comes back encrypted
- fails if the relay logs the secret marker as plaintext

This does not replace real Android testing. It proves the local relay, daemon, pairing, E2EE envelope, stdin command path, and terminal-output path without needing a physical phone or the official Codex/Claude CLIs.
