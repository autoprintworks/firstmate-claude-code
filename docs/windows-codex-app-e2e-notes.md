# Windows Codex App E2E Notes

Date: 2026-07-31.

This evidence is deliberately redacted.
It retains no account names, local checkout paths, worktree paths, thread ids, task ids, or authentication details.

## Verified behavior

- `FM_BACKEND=codex-app bin/fm-bootstrap.sh` does not require tmux or treehouse.
- The backend prepares durable Firstmate state before Codex Desktop creates or forks the visible project thread.
- Codex Desktop creates the worker in an isolated Desktop-owned worktree rather than the saved checkout.
- The worker can append lifecycle status and write its task report at authorized Firstmate paths.
- Firstmate can recover the durable task-to-thread association, send a follow-up through the host, read the completed response, and archive the exact visible thread.
- Teardown requires host-confirmed archival and preserves Desktop ownership of physical worktree removal.
- Missing, unknown, legacy-unlabelled, and newly registered projects resolve to `direct-PR off`; `no-mistakes` is retained only when explicitly registered.
- Native Windows paths with stripped separators are rejected with guidance to use forward slashes or safe quoting.
- Windows Git and GitHub subprocesses use hidden child-process integration so routine operation does not display a black console window.

## Supported bridge

`bin/fm-codex-app` is the durable ledger and protocol boundary.
It does not impersonate the Codex Desktop host API.
It records pending and visible thread state and tells the host exactly which thread operation is required.
Codex Desktop owns thread creation, messaging, reading, interruption, and archival through its thread tools.

GitHub operations route through the repository's `fm-gh-axi` entrypoint.
Windows child processes are created with hidden-window flags.
The same hidden subprocess foundation is used for production Git execution where the Windows integration needs to invoke Git without a console.

## Validation

The focused validation set is:

```sh
node --check bin/fm-codex-app
python -m unittest tests.test_gh_axi tests.test_git_hidden
bash tests/fm-codex-app-state.test.sh
bash tests/fm-doc-codex-app-protocol.test.sh
bash tests/fm-codex-app-e2e.test.sh
bash tests/fm-pr-merge.test.sh
bash tests/fm-teardown.test.sh
```

The live Desktop smoke covers visible thread creation, isolated worktree use, lifecycle writes, follow-up, readback, exact archival, and guarded teardown.
Environment-specific identifiers from that smoke are not committed.
