# Windows Baseline Verification - July 2, 2026

This document records what has been verified in `C:\AGOS\firstmate-gui-agnostic` on Windows under Codex Desktop.
It is meant to be a hard baseline, not a wish list.
Anything not listed as proven here should be treated as unproven or environment-blocked.

## Goal

The practical question for this pass was simple.
Can this Windows and Codex Desktop install act like a trustworthy FirstMate baseline that we can productize instead of a pile of one-off fixes.

As of July 2, 2026, the answer is now mostly yes.
The important Windows and Codex Desktop paths are no longer hand-wavy.
They have direct automated proof behind them.

## Surface Inventory

Local FirstMate skills currently present in `.agents/skills`:

- `afk`
- `firstmate-codexapp`
- `fmx-respond`
- `harness-adapters`
- `secondmate-provisioning`
- `stuck-crewmate-recovery`
- `updatefirstmate`

Core feature areas currently present in the repo:

- bootstrap and tool detection
- watcher, wake queue, guard, and supervision daemon
- Codex App backend and visible-thread state ledger
- secondmate home seeding, sync, lifecycle, and safety checks
- secondmate harness selection, config inheritance, bootstrap sweep, and config push
- backlog backend selection via `tasks-axi` or manual mode
- PR recording and merge helpers
- send and peek helpers
- X mode relay flow
- backend abstraction for tmux and herdr
- hidden Windows GitHub helpers in `firstmate_gui_agnostic/`

## Proven On This Machine

These checks completed successfully on this Windows machine in this repo.

- `tests/fm-bootstrap.test.sh` passes.
- `tests/fm-backend.test.sh` passes.
- `tests/fm-backend-herdr.test.sh` passes.
- `tests/fm-codex-app-state.test.sh` passes.
- `tests/fm-doc-codex-app-protocol.test.sh` passes.
- `tests/fm-codex-app-e2e.test.sh` passes.
- `tests/fm-crew-state.test.sh` passes.
- `tests/fm-fleet-sync.test.sh` passes.
- `tests/fm-gotmp.test.sh` passes.
- `tests/fm-pr-merge.test.sh` passes.
- `tests/fm-send-settle.test.sh` passes.
- `tests/fm-send-popup-settle.test.sh` passes.
- `tests/fm-send-secondmate-marker.test.sh` passes.
- `tests/fm-teardown.test.sh` passes.
- `tests/fm-update.test.sh` passes.
- `tests/fm-wake-queue.test.sh` passes.
- `tests/fm-watcher-lock.test.sh` passes.
- `tests/fm-secondmate-lifecycle-e2e.test.sh` passes.
- `tests/fm-secondmate-sync.test.sh` passes.
- `python -m unittest tests.test_gh_axi tests.test_git_hidden` passes.

Secondmate safety is now proven on Windows, but the proof had to be collected in grouped runs because the full monolithic shell file exceeds this Codex harness timeout budget.
Across grouped executions, every safety block passed, including:

- home seeding path-boundary checks
- relative-origin cloning and reseed equivalence
- treehouse-acquired home handling and rollback behavior
- no-mistakes clone initialization safeguards
- symlink and junction refusal paths
- spawn validation and secondmate send routing
- teardown and force-teardown boundary checks
- backlog handoff safety

Secondmate harness and config inheritance behavior is also proven, again through grouped runs rather than one giant uninterrupted shell command.
The following areas passed:

- harness resolution and fallback behavior
- optional secondmate model and effort tokens
- spawn-time inheritance and explicit override behavior
- bootstrap sweep propagation, reconvergence, and absence mirroring
- bootstrap sweep deferral on unignored config
- config-push reporting, warnings, and hard error handling

X mode is proven on this machine when the workspace-local real `jq.exe` at `C:\AGOS\firstmate-gui-agnostic\.tools\jq.exe` is on `PATH`.
With that real binary available, `tests/fm-x-mode.test.sh` passes end to end, including:

- inert polling when off
- 204 silent polling
- inbox stashing and follow-up context preservation
- safe answer, follow-up, and dismiss posting
- dry-run outbox behavior
- thread splitting
- image payload handling
- bootstrap activation and opt-out cleanup

Previously committed Windows and Codex fixes that are part of this baseline:

- `d825167 Add Windows Codex App backend`
- `fc53778 Support local FirstMate tool installs`
- `8c4816f Fix Windows watcher locking`
- `70aea06 Handle sandboxed gh auth checks`

## What Changed In This Pass

This pass closed the specific Windows gaps that were still preventing an honest FirstMate baseline claim.

- Added `bin/fm-git-lib.sh` and wired runtime `safe.directory` handling through the Windows Git-sensitive paths.
- Hardened watcher locking and wake queue behavior for Windows directory-only locking.
- Added Windows fast paths for watcher signal and stale detection.
- Fixed relative-origin secondmate seeding on Windows path normalization.
- Made config inheritance trust and validate secondmate worktrees correctly on Windows.
- Standardized Windows test symlink behavior so the safety suites exercise real link semantics instead of Git Bash copy fallbacks.
- Added a workspace-local real `jq.exe` so X mode could be tested honestly without needing a machine-wide install.
- Fixed X mode dry-run image preview path preservation under native Windows `jq.exe`.

## Remaining Blockers

These are the things that are still not honestly proven or still depend on environment conditions.

1. Real native `tmux` and `herdr` smoke coverage is still not proven on this machine.
`tests/fm-backend-herdr-smoke.test.sh` and `tests/fm-backend-tmux-smoke.test.sh` still depend on those real tools being present.
The Codex App path is proven.
The real native tool path is not.

2. The machine still does not have a clean system-wide `jq` install.
Attempting a Chocolatey install from this shell failed because of Windows permission and Chocolatey lock constraints.
X mode proof is therefore currently tied to the workspace-local real binary at `.tools/jq.exe`, not a machine-wide install.

3. The very large shell suites are still too long for a single uninterrupted Codex command budget.
That is a harness limitation, not a correctness failure.
The actual feature coverage is proven through grouped runs.

## What This Means

We are no longer in the state of wondering whether Windows FirstMate basically works.
The important Windows and Codex Desktop behavior now has real proof behind it.

More specifically:

- watcher and wake supervision are proven
- Codex App backend behavior is proven
- secondmate seeding, lifecycle, sync, safety, and config propagation are proven
- X mode client behavior is proven with a real local `jq`

What remains is narrower and more honest:

- native real-tool smoke for `tmux` and `herdr`
- a machine-wide dependency story for `jq`
- possibly a better long-run harness for giant shell suites

## Bottom Line

This repo now qualifies as a credible Windows and Codex Desktop FirstMate baseline.
It is good enough to stop treating the whole setup as speculative.

The next phase should not be more blind setup churn.
It should be product work on top of a baseline we can now actually point to and defend.
