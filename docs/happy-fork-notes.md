# Happy Coder Fork Notes

Source reference: https://github.com/slopus/happy

Happy Coder is MIT licensed. Its license is preserved at `LICENSES/happy-MIT-LICENSE.txt`.

Current state:

- The Happy repo was cloned locally into `vendor/happy` for reference.
- `vendor/happy` is intentionally ignored by Git to avoid committing an embedded repository.
- The Codex Nomad daemon currently uses a clean Go implementation with small direct dependencies.
- No Happy source files have been copied into the tracked daemon code yet.

Planned extraction points:

- Proven pairing flow details.
- E2EE protocol details and test vectors.
- Realtime streaming semantics for Codex and Claude Code.
- CLI wrapper behavior around approvals, diffs, and session resume.

Rule:

Only copy small, audited pieces with clear attribution and tests. Do not inherit Happy's UI or app structure.
