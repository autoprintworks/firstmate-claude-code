# Windows Codex App E2E Notes

Date: 2026-07-02.

Repo under test: `C:\AGOS\firstmate-gui-agnostic`.

Salvage repo compared: `C:\AGOS\firstmate-gui-agnostic-salvage-2026-07-02`.

SSB fork compared: `C:\AGOS\firstmate-codex-desktop`.

## What Is Working

`FM_BACKEND=codex-app bin/fm-bootstrap.sh` no longer asks for `tmux`, `treehouse`, or raw `gh-axi`.

The codex-app backend prepares FirstMate state first, then waits for Codex Desktop to create or fork the visible project thread.

The actual live smoke created a visible Codex Desktop thread under the saved `firstmate-gui-agnostic` project.

The live thread id was `019f2397-7cd6-75b0-810a-8ff35c4f084f`.

Codex Desktop created the worker in `C:\Users\Glyn\.codex\worktrees\5228\firstmate-gui-agnostic`.

That proves the worker was not running in the saved checkout at `C:\AGOS\firstmate-gui-agnostic`.

The worker appended `done: visible codex smoke complete` to `state/e2e-visible-codex-smoke.status`.

The worker wrote its report to `data/e2e-visible-codex-smoke/report.md`.

The visible thread was archived with `set_thread_archived`.

`bin/fm-codex-app mark-archived e2e-visible-codex-smoke` and `bin/fm-teardown.sh e2e-visible-codex-smoke` completed successfully.

## Problems Found

`gh` is installed, but `FM_BACKEND=codex-app bin/fm-bootstrap.sh` reports `NEEDS_GH_AUTH`.

`tasks-axi` is not installed, so bootstrap reports `MISSING: tasks-axi`.

`jq` is not installed, so `tests/fm-bootstrap.test.sh` stops at the crew-dispatch JSON validation tests.

The primary checkout is on `codex/port-codex-app-backend` instead of `main`, so the tangle guard correctly warns during bootstrap and teardown.

The watcher is not armed in this fresh reset flow, so guard output reports watcher supervision is off during in-flight E2E tasks.

There is no `data/projects.md` registry yet, so FirstMate defaults this project to `no-mistakes` mode.

Passing a native Windows path like `C:\Users\...` through Git Bash double quotes can strip backslashes and record `C:Users...`.

`bin/fm-codex-app` now rejects that malformed path shape and tells the operator to use `C:/Users/...` or single quotes in Git Bash.

## Salvage Comparison

The useful salvage fix for the Windows application-picker popup was the hidden no-shell process bridge.

That fix lives in salvage as `firstmate_gui_agnostic/gh_axi.py`, `firstmate_gui_agnostic/git_hidden.py`, and `firstmate_gui_agnostic/hidden_subprocess.py`.

Those files are now present in the official-base repo.

`git diff --no-index --stat` showed no content drift for `gh_axi.py` and `git_hidden.py` between salvage and this repo.

The salvage note in `docs/no-mistakes-reliability-baseline.md` says not to run `npx.cmd`, `gh.cmd`, `cmd.exe /c gh-axi`, or PowerShell wrapper shims directly.

The official-base repo now routes PR check and merge calls through `bin/fm-gh-axi`.

The official-base worker brief now tells workers to use `bin/fm-gh-axi` or `bin/fm-gh-axi.ps1`.

The useful SSB fork fix was the minimal `fm-codex-app` visible-thread ledger and skill.

`bin/fm-codex-app` and `.agents/skills/firstmate-codexapp/SKILL.md` match the SSB fork copy.

The official-base repo adds the backend integration around that helper, including spawn, backend routing, bootstrap, send, peek, archive, and teardown guards.

## Validation Run

`bash -n` passed for the touched shell scripts and focused shell tests.

`node --check bin/fm-codex-app` passed.

PowerShell parsing for `bin/fm-gh-axi.ps1` passed.

`python -m unittest tests.test_gh_axi tests.test_git_hidden` passed.

`bash tests/fm-codex-app-state.test.sh` passed.

`bash tests/fm-doc-codex-app-protocol.test.sh` passed.

`bash tests/fm-codex-app-e2e.test.sh` passed.

`bash tests/fm-pr-merge.test.sh` passed.

`bash tests/fm-teardown.test.sh` passed with a longer timeout.

`bash tests/fm-bootstrap.test.sh` passed its codex-app bootstrap regression, then stopped because `jq` is missing.

The live Codex Desktop visible-thread smoke passed and was torn down.

## Remaining Setup

Install `jq` to unblock the full bootstrap test file.

Install `tasks-axi` or set the backlog backend to manual for this reset phase.

Run `gh auth login` or otherwise repair GitHub CLI authentication before GitHub-backed FirstMate work.

Create or restore `data/projects.md` when ready to define project delivery modes.

Start or arm the watcher with the FirstMate-supported watch command before relying on supervision.

Move the primary checkout back to `main` after this branch is validated in an isolated worktree.
