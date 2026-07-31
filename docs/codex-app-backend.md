# Codex App backend

The Windows-maintained build supports `codex-app` as a host-assisted runtime backend for visible Codex Desktop threads.
It deliberately does not proxy Codex Desktop's private transport from shell code.
Firstmate prepares and records durable task state, while the running Codex Desktop conversation performs thread operations with its host tools.

## Requirements

- Run Firstmate from Codex Desktop on Windows with the thread tools available.
- Save the target repository as a Codex Desktop project before dispatching work.
- Select the backend with `FM_BACKEND=codex-app`, `config/backend`, or `fm-spawn.sh --backend codex-app`.
- Use the `codex` harness.
- Use ship or scout tasks only because secondmates are not supported by this backend yet.

## Lifecycle

1. Run `bin/fm-brief.sh` normally.
2. Run `bin/fm-spawn.sh <id> <project> codex --backend codex-app`.
3. Firstmate writes pending task metadata and prints the brief path without launching a console process or calling `treehouse get`.
4. Codex Desktop calls `create_thread` for the saved project, or `fork_thread` when the current conversation context must be retained.
5. Record the returned identity with `bin/fm-codex-app record-thread <id> <thread-id> --worktree <thread-cwd>`.
6. Use `read_thread` for live truth and cache bounded text with `bin/fm-codex-app record-capture` when shell-side `fm-peek.sh` needs it.
7. Use `send_message_to_thread` to steer the worker.
8. When work is landed or the scout report is complete, call `set_thread_archived`, then run `bin/fm-codex-app mark-archived <id>` before teardown.

`bin/fm-codex-app adopt-thread` reconciles an already-visible thread into Firstmate state.
The helper rejects duplicate thread ownership and malformed Windows drive paths.

## Supervision boundary

The Desktop host owns thread creation, reading, steering, interruption, and archive operations.
The shell adapter never claims those operations succeeded merely because it recorded a ledger entry.
Shell-side send, interrupt, capture, and archive requests fail with the exact Desktop host action required.

A managed thread must also write ordinary lifecycle lines to the authorized `state/<id>.status` path.
Use only `working:`, `needs-decision:`, `blocked:`, `paused:`, `done:`, and `failed:` prefixes.
If the thread cannot write that return channel, treat it as a visible companion thread rather than a completely supervised task.

## Worktree and teardown safety

Codex Desktop creates and owns the worker's isolated cwd.
Never direct a worker to edit the saved project checkout.
For ship tasks, record the Desktop worktree path and land its work before teardown.
For scout tasks, the durable product remains `data/<id>/report.md` plus the required decision inventory.

Teardown refuses an unarchived visible thread.
After `mark-archived`, teardown clears Firstmate metadata and cached capture state without sending the Desktop-owned worktree through treehouse.

## Windows behavior

This backend prepares state and returns control to the Codex Desktop host instead of launching a child console.
The maintained Windows Git and GitHub helpers use hidden no-shell subprocess settings, so routine integration does not open a black console window.
Tracked shell entry points are forced to LF line endings so Git Bash can execute them after checkout.

`codex app-server` is a separate headless protocol and is not evidence that the visible Codex Desktop lifecycle works.
The lifecycle tests must prove pending preparation, host thread recording, capture routing, steering refusal, archive enforcement, and cleanup.
