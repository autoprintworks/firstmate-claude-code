# Divergence audit: `local-gui-agnostic/windows-main` vs `claude-app-backend`

Resolves issue #2. Merge-base: `30a89bc` ("feat(bin): auto-detect runtime backend (#188)").

- `claude-app-backend`: 8 unique commits, 68 files, +8,972/-329.
- `local-gui-agnostic/windows-main`: 224 unique commits, 313 files, +95,759/-4,137. Includes upstream firstmate merges up to #1358 and "seamless Windows support" (#125).
- `git cherry windows-main claude-app-backend 30a89bc`: **all 8 local commits are `+`** — none exist upstream as patch-equivalent commits. However, content inspection shows several local commits are byte-identical or near-identical to code that windows-main independently carries (details below), because windows-main is itself a Windows-maintained line that absorbed earlier versions of this same local work.

## Overlap map

- Files changed on **both** sides: **50** (44 with differing content, 6 identical blobs).
- Only-upstream: **263** files — trivially take-upstream. Dominated by: the full `bin/backends/` adapter suite (tmux, herdr, zellij, orca, cmux, codex-app + herdr event helpers), `bin/fm-busy-lib.sh` (semantic lifecycle state, #1327), `bin/fm-crew-state.sh` rewrite, lock/platform/transition/supervision libraries, afk daemon split, X-mode script suite, docs, and ~90 test files.
- Only-local: **18** files — trivially take-local. Dominated by: `bin/backends/wezterm.sh`, `bin/backends/claude-bg.sh`, `bin/fm-wezterm-lib.sh`, `bin/fm-watch-signal-fastpath.py`, `bin/fm-watch-stale-fastpath.py`, `bin/fm-git-lib.sh`, `bin/fm-tangle-lib.sh`, `bin/fm-issues`(+`.ps1`), `firstmate_gui_agnostic/issueops.py` + tests, and 7 AGOS planning docs.

## Verdict table (overlapping areas)

| Area / files | Local side | Upstream side | Verdict | Rationale |
|---|---|---|---|---|
| Watcher core: `bin/fm-watch.sh`, `fm-watch-arm.sh` | Lockdir-based Windows lock fix (8c4816f); python fastpath hooks + triage-log integration (0affd9f) | Full rework: semantic lifecycle state via `fm-busy-lib.sh` (#1327), event-wait splice for push-capable backends, MSYS-aware lock claim with pid-identity + heartbeat-stale detection (#1212), native triage_log absorption | **take-upstream + hand-synthesis** | Upstream's lock claim (`fm_lock_claim`, owner-dir links, MSYS pid handling in `fm-wake-lib.sh`) subsumes the local lock fix; the local python fastpaths (`fm-watch-*-fastpath.py`, local-only) target MSYS fork cost and have no upstream equivalent — re-port them onto upstream's restructured loop |
| Wake queue: `bin/fm-wake-lib.sh`, `fm-wake-drain.sh` | Spool-file wake backend (`fm_wake_use_spool_backend` etc.) + directory-mutex locks for Windows atomicity (6b9403c) | MSYS-aware `fm_lock_*` owner-dir claim machinery; no spool backend (`grep spool` = 0) | **hand-synthesis** | Upstream locking is more evolved, but the local spool backend (Windows append-atomicity workaround) is unique local value; port it onto upstream's wake-lib or verify upstream's claim machinery makes it redundant |
| Classification / dispatch: `bin/fm-classify-lib.sh`, `fm-crew-state.sh` | 15-line tweak (part of 6b9403c) | +319 lines classify, +467 lines crew-state: evidence-based dispatch eligibility (#1358), quota-window pace routing (#1172) | **take-upstream** | Upstream is a functional superset; local delta is a minor hardening tweak within code upstream rewrote |
| Backend dispatch: `bin/fm-backend.sh`, `fm-spawn.sh`, `fm-teardown.sh`, `fm-tmux-lib.sh` | Extracted tmux adapter, added wezterm/claude-bg/codex-app to `FM_BACKEND_KNOWN` (1b55caa, d825167) | Same extraction done independently and further: spawn-capable herdr/zellij/orca/cmux + codex-app, per-backend adapters, richer contract | **take-upstream + re-register local backends** | Same design (both cite `fm-backend-design-d7`); upstream is the maintained superset — carry over only the `wezterm`/`claude-bg` adapter files and add them to upstream's `FM_BACKEND_KNOWN` |
| Codex App backend: `bin/fm-codex-app`, `.agents/skills/firstmate-codexapp/`, `bin/fm-composer-lib.sh` | Local ledger with prepare/record-thread/adopt-thread etc. | Same ledger evolved: +exec bit, capture/send/interrupt/archive/status subcommands, `bin/backends/codex-app.sh` adapter, `docs/codex-app-backend.md` protocol | **take-upstream** | Direct diff of `fm-codex-app` is only 88 lines and upstream is strictly the newer superset ("Windows-maintained build" per its own header); composer-lib upstream is +56 lines over local |
| Sandboxed gh auth: `bin/fm-bootstrap.sh` | `gh_auth_ready()` treating network-only `gh auth status` failures as inconclusive (70aea06) | **Byte-identical** `gh_auth_ready()` already present | **take-upstream** | Local commit fully subsumed |
| Local tool installs: `bin/fm-tasks-axi-lib.sh` | `.tools/bin` PATH injection (fc53778) | Same `.tools/bin` PATH injection present | **take-upstream** | Subsumed |
| `firstmate_gui_agnostic/` (gh_axi, git_hidden, hidden_subprocess) | Present | gh_axi + hidden_subprocess identical blobs; git_hidden adds a CLI `main()` bridge | **take-upstream** | Superset; `issueops.py` is local-only and rides along untouched |
| `bin/fm-gh-axi` / `.ps1` | Present | Same + exec bit + usage comment (22-line diff) | **take-upstream** | Cosmetic superset |
| `.agents/skills/stow/SKILL.md` | "Preserve inactive work" skill (IssueOps-flavored) | **Different skill under the same name**: session-knowledge sweep before context reset | **hand-synthesis** | True semantic collision, not drift — keep upstream's `stow`, rename the local one (e.g. `shelve`) so the IssueOps workflow survives |
| `AGENTS.md`, `CONTRIBUTING.md`, `README.md` | +19 lines total (codex-app spawn docs) | Restructured wholesale (-895/+584 on AGENTS.md alone) and already documents codex-app | **take-upstream** | Local delta's only content (codex-app protocol) exists upstream in newer form (`docs/codex-app-backend.md` + `firstmate-codexapp` skill trigger) |
| Windows runtime hardening (misc): `fm-ff-lib.sh`, `fm-fleet-sync.sh`, `fm-home-seed.sh`, `fm-config-inherit-lib.sh`, `fm-x-lib.sh`, `fm-brief.sh`, `fm-pr-check/merge` | Small hardening deltas (6b9403c) | Larger independent rework incl. `fm-platform-lib.sh` NTFS-mode compatibility, `fm-pr-lib`/`fm-pr-poll` refactor | **take-upstream** | Half of these auto-merge cleanly (`config-inherit`, `ff-lib`, `home-seed`, `tasks-axi-lib` per merge-tree); the conflicted rest are upstream rewrites of areas where local made minor tweaks |
| Tests (14 overlapping `tests/*.test.sh` + `tests/lib.sh`) | Adjusted for local hardening | Rewritten for upstream architecture | **take-upstream** | Tests follow the implementation; local-only `test_issueops.py` and the wezterm/claude-bg coverage come across with their features |

## Local-only work to preserve across any convergence

1. `bin/backends/wezterm.sh` + `bin/fm-wezterm-lib.sh` — visible-crew backend for native Windows.
2. `bin/backends/claude-bg.sh` — headless `claude --bg` backend with real busy_state.
3. `bin/fm-watch-signal-fastpath.py` / `fm-watch-stale-fastpath.py` — MSYS fork-cost mitigation (needs re-porting to upstream's watcher shape).
4. `bin/fm-git-lib.sh` — git PATH resilience + per-process `safe.directory` for the Codex Desktop sandbox (no upstream equivalent; upstream has zero `safe.directory` handling in `bin/`).
5. `firstmate_gui_agnostic/issueops.py`, `bin/fm-issues`(+`.ps1`), `tests/test_issueops.py` — IssueOps tooling.
6. `bin/fm-tangle-lib.sh` 2-line delta; wake-spool backend (pending redundancy check against upstream locking).
7. AGOS planning docs (7 files under `docs/`), `docs/windows-baseline-verification-2026-07-02.md`, local `stow` skill content (renamed).

## Conflict-proneness of `git merge local-gui-agnostic/windows-main`

`git merge-tree --write-tree claude-app-backend windows-main`: **34 conflicted files** — including every core script (`fm-watch.sh`, `fm-watch-arm.sh`, `fm-wake-lib.sh`, `fm-wake-drain.sh`, `fm-spawn.sh`, `fm-teardown.sh`, `fm-backend.sh`, `fm-bootstrap.sh`, `fm-classify-lib.sh`, `fm-tmux-lib.sh`, `fm-fleet-sync.sh`, `fm-pr-check.sh`, `fm-pr-merge.sh`), 8 add/add whole-file conflicts (`fm-codex-app`, `fm-composer-lib.sh`, `fm-gh-axi`+`.ps1`, both skills, e2e docs), `AGENTS.md`/`README.md`/`CONTRIBUTING.md`, `git_hidden.py`, and 9 tests. Verdict: **highly conflict-prone as a naive merge, but low-risk as a directed one** — in nearly every conflicted file upstream is a superset or byte-equal evolution of the local change, so the resolution policy is mechanical: resolve conflicts toward upstream everywhere, then re-apply the short preserve-list above on top. Estimated genuine hand-synthesis: the two python fastpaths' hook points in `fm-watch.sh`, the wake-spool decision, `FM_BACKEND_KNOWN` re-registration, and the `stow` skill rename — roughly a day of careful work, dominated by re-verifying the watcher on Windows, not by textual conflict resolution.

## Overall verdict

**Converge on `windows-main` as the base (take-upstream by default) and cherry-pick the ~7-item local-only preserve list on top.** The local branch's "Preserve ..." commits are largely already present upstream (sandboxed gh auth and `.tools/bin` support are byte-identical); the durable local value is the wezterm/claude-bg backends, the MSYS watcher fastpaths, `fm-git-lib.sh`, and the IssueOps stack.
