# Current Pipeline Next Plan

This is the execution plan as of 2026-07-03.
Use this when deciding what to give a coding agent next.

## Current Diagnosis

We have enough GitHub issues for the next stage.
Do not create more broad planning issues right now.
The main problem is order.
If we start coding FirstMate execution before GitHub issue control is stable, the board will drift again.
If we start AGOS UI before execution proof exists, the UI will be a picture of an imagined system.

The correct move is:

```text
Wheelhouse GitHub control -> pipeline contract -> Windows readiness -> execution ledger -> one visible lane -> separate QA -> end-to-end smoke -> scale -> AGOS UI
```

## Repos In Play

`autoprintworks/wheelhouse` is the GitHub IssueOps engine.
It should own decision cards, hidden issue state, labels, reconcile, and safe GitHub issue mutation.

`autoprintworks/firstmate-gui-agnostic` is the execution supervisor and current AGOS foundation.
It should own worker dispatch, execution ledger, validation, no-mistakes proof, teardown safety, Stow, and the future AGOS Command Centre.

## Immediate Blockers

Bootstrap currently reports missing tooling and GitHub auth even though some tools work through the local bridge.
It also fails to find basic Git Bash helpers such as `dirname`, `sed`, and `head`.
Treat that as part of FirstMate #114 and #110.

Wheelhouse local validation partly passes.
The remaining Wheelhouse workflow tests need `PyYAML` installed or a documented Python dependency path.
Treat that as part of Wheelhouse #1.

Project 3 exists and has the right views, but automatic Project sync is not proven.
Treat that as Wheelhouse #3 plus FirstMate #116.

## Do Next

### 1. Code Wheelhouse #1

Issue: `autoprintworks/wheelhouse#1`.
Title: Configure Wheelhouse fork for AGOS fleet control.

Code:

- Edit `projects/wheelhouse/wheelhouse.config.yml`.
- Remove upstream placeholder repos.
- Start with only `firstmate-gui-agnostic`.
- Disable or clearly gate live actions until token scope is confirmed.
- Decide public versus private risk for decision cards.
- Add or document the Python dependency path for `PyYAML`.
- Run all Wheelhouse local tests that can run on this machine.

Done when:

- Wheelhouse config targets the real AGOS repo set.
- No placeholder fleet repo remains active.
- Required secrets and scopes are documented.
- Local validation result is posted to Wheelhouse #1.

### 2. Code Wheelhouse #2

Issue: `autoprintworks/wheelhouse#2`.
Title: Adapt Wheelhouse cards to AGOS issue state.

Code:

- Compare Wheelhouse `wheelhouse-state` with FirstMate `firstmate-state`.
- Decide one canonical AGOS issue-card contract.
- Add fixtures from FirstMate #85, #112, #116, #117, and #120.
- Add parser, renderer, and diff tests for AGOS state.
- Decide whether `fm-issues` becomes a bridge or is retired after the pilot.

Done when:

- Agents can read AGOS issue state without an LLM.
- Unmanaged, ready, blocked, stowed, superseded, and done states are deterministic.
- There is not a second competing FirstMate IssueOps engine.

### 3. Code Wheelhouse #3

Issue: `autoprintworks/wheelhouse#3`.
Title: Bridge Wheelhouse issue state to FirstMate Project 3.

Code:

- Read Project 3 fields and items.
- Detect missing ProjectV2 scope before mutation.
- Map AGOS issue state to Project 3 fields.
- Add missing open FirstMate issues to Project 3 in dry-run first.
- Save bounded readback artifacts.
- Verify the six Project views.

Done when:

- A dry-run reports Project 3 drift without changing GitHub.
- Apply mode is explicit and guarded.
- FirstMate #116 can consume this bridge instead of building a separate sync engine.

### 4. Code Wheelhouse #4

Issue: `autoprintworks/wheelhouse#4`.
Title: Run safe Wheelhouse pilot against FirstMate.

Code:

- Pick one low-risk FirstMate issue for the pilot.
- Produce a Wheelhouse card or adapter readback.
- Verify hidden state, labels, and Project projection expectations.
- Confirm no unexpected GitHub or Project mutation happened.
- Decide the fate of FirstMate #120 and #116.

Done when:

- The pilot has before and after evidence.
- Wheelhouse is proven safe enough for the current queue.
- FirstMate #120 and #116 are retargeted, superseded, or kept with a clear reason.

## Then Do FirstMate

### 5. Retarget FirstMate #120

Issue: `autoprintworks/firstmate-gui-agnostic#120`.

Do not code it as a full standalone IssueOps engine.
Turn it into the FirstMate-side bridge to Wheelhouse.
Keep `fm-issues` only if it remains useful as a bridge, migration helper, or readback tool.

### 6. Retarget FirstMate #116

Issue: `autoprintworks/firstmate-gui-agnostic#116`.

Make it the FirstMate acceptance issue for the Wheelhouse Project 3 bridge.
It should prove that Project 3 fields and views agree with Wheelhouse-backed issue state.

### 7. Code FirstMate #112

Issue: `autoprintworks/firstmate-gui-agnostic#112`.

Define the pipeline contract.
This should say exactly what enters and exits Idea, Research, Prototype, PRD, Kanban Board, Execution, QA, and Stow.

### 8. Code FirstMate #114, #110, and #111

Issues:

- `autoprintworks/firstmate-gui-agnostic#114`
- `autoprintworks/firstmate-gui-agnostic#110`
- `autoprintworks/firstmate-gui-agnostic#111`

Build the readiness and activation path.
This must fix or explain the bootstrap/tooling confusion.
The output should tell the captain what works, what is missing, and the exact repair command.

### 9. Resolve FirstMate #102 and #91

Issues:

- `autoprintworks/firstmate-gui-agnostic#102`
- `autoprintworks/firstmate-gui-agnostic#91`

PR #94 is still open and broad.
#102 should recut it to the TypeScript doctor runtime slice.
#91 should then track the remaining TypeScript runtime foundation.

### 10. Code FirstMate #115

Issue: `autoprintworks/firstmate-gui-agnostic#115`.

Build the execution ledger gate.
FirstMate must not launch duplicate, unsafe, unvalidated, or unowned work.

### 11. Code FirstMate #117

Issue: `autoprintworks/firstmate-gui-agnostic#117`.

Make Stow operational.
This means labels, issue states, artifacts, retrieval, and reactivation triggers.

### 12. Code FirstMate #96

Issue: `autoprintworks/firstmate-gui-agnostic#96`.

Prove one visible Codex issue execution lane.
Do not hide work in an unobservable path.

### 13. Code FirstMate #101 and #97

Issues:

- `autoprintworks/firstmate-gui-agnostic#101`
- `autoprintworks/firstmate-gui-agnostic#97`

Prove PR evidence and separate QA.
The implementation agent must not review itself.

### 14. Code FirstMate #98

Issue: `autoprintworks/firstmate-gui-agnostic#98`.

Run the full happy-path smoke.
This is the first proof that the MVP works from issue to safe PR boundary.

### 15. Then Scale

Issues:

- `autoprintworks/firstmate-gui-agnostic#39`
- `autoprintworks/firstmate-gui-agnostic#79`
- `autoprintworks/firstmate-gui-agnostic#118`
- `autoprintworks/firstmate-gui-agnostic#119`

Do model routing, secondmate orchestration, small-batch parallelism, and the AGOS Command Centre interface only after the single-lane MVP works.

## Do Not Code Yet

Do not code FirstMate #104 until FirstMate #100 proves it is still needed.
Do not code FirstMate #85 because it is the strategic parent, not a task.
Do not build the AGOS UI before FirstMate #98 proves the loop.
Do not let agents mutate labels, Project fields, or issue bodies through one-off manual actions.

## Exact Prompt For The Next Coding Agent

```text
Work on GitHub issue autoprintworks/wheelhouse#1.
Configure the Wheelhouse fork for AGOS fleet control.
Start with only autoprintworks/firstmate-gui-agnostic as the fleet repo.
Keep live acting workflows disabled or clearly gated until token scope and public/private risk are confirmed.
Resolve or document the PyYAML validation dependency.
Run the Wheelhouse local validation suite that can run on this Windows machine.
Post the config, validation output, required secrets, and remaining risk back to the issue.
```

## When To Stop And Ask

Stop before enabling any workflow that can merge, close, or mutate important FirstMate issues.
Stop before making the Wheelhouse fork private or public if that choice requires captain approval.
Stop if a GitHub token needs new scopes.
Stop if ProjectV2 access is missing.
Stop if the pilot would expose private operating information in public issues.
