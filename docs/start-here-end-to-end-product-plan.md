# Start Here: End-To-End Product Plan

This is the simple captain-facing plan for the whole AGOS-to-FirstMate product.
Use this document when the project feels confusing.
It tells you what exists, what is not finished, what to do next, and what "done" means.

## The Product We Are Building

We are building a repeatable product pipeline where the captain can start with an idea, turn it into clear work, run agents safely, review the result, and ship without losing context.

The finished flow is:

```text
Idea -> Research -> Prototype -> PRD -> GitHub Issues -> Project/Kanban -> tasks-axi -> FirstMate execution -> QA/no-mistakes -> PR -> captain-approved merge -> Stow or iterate
```

GitHub is the human audit surface.
Project 3 is the operating board.
Wheelhouse is now the preferred IssueOps engine for GitHub issues and decision cards.
The existing `fm-issues` prototype should become a bridge or temporary readback tool unless the Wheelhouse pilot fails.
`tasks-axi` and the execution ledger become the local execution truth.
FirstMate runs the work and keeps the captain out of the weeds.
AGOS Command Centre comes later as the business-facing interface over the proven pipeline.

## Current State

The active product repo is `autoprintworks/firstmate-gui-agnostic`.
Project 3 is called `FirstMate Execution MVP - Issue to Safe PR`.
Project 3 has the required views: `Pipeline Kanban`, `Execution Now`, `QA and Review`, `Model Routing`, `Stow and Parked`, and `AGOS Future`.
The manual board cleanup was completed and verified on 2026-07-03.
`tasks-axi@0.1.2` is installed and verified.
The `stow` skill exists in the repo and in the personal Codex skills directory.
The `autoprintworks/wheelhouse` fork exists, is cloned locally, and has GitHub Issues enabled.
Wheelhouse has four new setup issues: `autoprintworks/wheelhouse#1`, `#2`, `#3`, and `#4`.
The new `fm-issues` IssueOps command exists as an early FirstMate prototype.
Issue #120 is the first live FirstMate IssueOps-controlled GitHub issue, but it should now be retargeted around Wheelhouse.
The live board has 22 open issues.
At the last readback, 1 issue was IssueOps-controlled and 21 still needed hidden `firstmate-state`.

## Wheelhouse Decision

Use Wheelhouse as a separate GitHub control repo for now.
Do not copy it wholesale into FirstMate yet.
Do not keep building two full IssueOps engines.
First prove Wheelhouse can safely represent, reconcile, and project the FirstMate issue queue.
Then shrink or retire the local `fm-issues` work into a bridge.

The detailed analysis is in `docs/wheelhouse-agos-integration-plan.md`.

## The One Rule

Do not let agents hand-edit GitHub issues, labels, Project fields, or Kanban views as one-off manual actions.
All of that should go through a controlled command path.
The target path is Wheelhouse for GitHub issue cards, FirstMate for execution, and Project 3 as the visible board.
Right now `fm-issues` is only a prototype bridge.
The next work makes Wheelhouse the stable GitHub control layer.

## What To Do Next

Do these phases in order.
Do not jump to later phases because that creates confusion.
For the shorter current execution sequence, use `docs/current-pipeline-next-plan.md`.

## Exact AI Coding Queue

This is the order to give GitHub issues to coding agents.
Use this section when you want to know what to ask the AI to build next.

### Code These Next, In This Order

1. `autoprintworks/wheelhouse#1`: Configure Wheelhouse fork for AGOS fleet control.
   Make the fork target the correct AGOS repo set and document required secrets before live automation acts.

2. `autoprintworks/wheelhouse#2`: Adapt Wheelhouse cards to AGOS issue state.
   Map Wheelhouse state, FirstMate `firstmate-state`, labels, Stow, supersede, and AGOS pipeline fields into one contract.

3. `autoprintworks/wheelhouse#3`: Bridge Wheelhouse issue state to FirstMate Project 3.
   Make Project 3 and Kanban fields sync from the Wheelhouse-backed issue contract.

4. `autoprintworks/wheelhouse#4`: Run safe Wheelhouse pilot against FirstMate.
   Prove one safe pilot without unexpected issue, label, or Project drift.

5. #120: Build FirstMate IssueOps state machine.
   Retarget this to the FirstMate-side Wheelhouse bridge.
   Do not expand it into a second full IssueOps engine unless the Wheelhouse pilot fails.

6. #116: Create the Kanban/GitHub sync issue.
   Retarget this to consume Wheelhouse issue #3 as the Project 3 projection path.

7. #112: Define the AGOS-to-FirstMate pipeline contract.
   This is mostly planning and documentation, but it is required before deeper execution work.
   Use a stronger model for this if possible.

8. #114: Build Windows runner and dependency proof.
   Make the machine readiness checks real and deterministic.
   This proves the supported Windows path before dispatching workers.

9. #110: Harden setup readiness and dependency proof.
   Tighten setup and dependency checks after #114 gives the main readiness shape.

10. #111: Add captain-facing activation output.
   Make the readiness output understandable for the captain.
   This should say what works, what is missing, and what command fixes it.

11. #102: Recut PR 94 as the issue 91 TypeScript doctor slice.
   Finish or cleanly retire the active TypeScript doctor work.
   Do not let new foundation work duplicate or disturb this issue.

12. #91: Track TypeScript runtime foundation after active #102.
   Only code this after #102 is resolved.
   Use it to collect the remaining TypeScript runtime foundation work.

13. #100: Audit issue 89 closure and residual progress parity.
   This is an audit task, not a big code task.
   It decides whether #104 is needed.

14. #103: Preserve Windows-explicit runtime contract.
    Code this after #102 and the readiness work clarify the final Windows runtime contract.

15. #115: Create the execution ledger gate and ownership issue.
    Build the scheduler truth.
    This blocks unsafe dispatch, duplicate work, missing validation, ownership conflicts, and unsafe teardown.

16. #117: Add Stow workflow.
    Turn Stow into a real issue and artifact workflow.
    This lets us close or park irrelevant work without losing useful evidence.

17. #96: Prove visible Codex issue execution lane.
    Prove one issue can run through a visible Codex worker lane with validation and teardown.

18. #101: Create no-mistakes PR proof ownership issue.
    Make PR proof machine-verifiable.
    Handwritten PR text must not count as official proof.

19. #97: Prove separate no-mistakes and adversarial review lane.
    Prove implementation and review are separate identities or threads.

20. #98: Prove end-to-end FirstMate happy-path smoke.
    Run the whole MVP path once from issue to safe delivery boundary.

21. #39: Create model routing and token-efficiency policy issue.
    Make strong versus cheap model selection evidence-backed.

22. #79: Create secondmate orchestration proof issue.
    Prove one secondmate can own a scoped support lane.

23. #118: Prove parallel execution with a small batch.
    Prove two safe tasks can run in parallel without ownership or review confusion.

24. #119: Define AGOS Command Centre interface backlog.
    Do this after the execution MVP has real state to render.
    Do not build the AGOS UI before #98 works.

### Do Not Code Yet

- #104: Implement residual in-app no-mistakes progress parity.
  Do not start this until #100 proves it is still needed.

- #85: Strategic parent: AGOS-to-FirstMate execution MVP decision record.
  Do not treat this as a coding issue.
  Keep it as the top-level parent and decision record.

### Best Prompt To Give A Coding AI

Use this template:

```text
Work on GitHub issue #<number> in autoprintworks/firstmate-gui-agnostic.
Read the issue body and linked evidence.
Keep the change scoped to that issue.
Run the listed validation.
Update the issue with proof when done.
Do not mutate unrelated GitHub issues or Project fields except through Wheelhouse, the FirstMate bridge, or the approved sync command.
```

For the next coding agent, use:

```text
Work on GitHub issue autoprintworks/wheelhouse#1.
Configure the Wheelhouse fork for AGOS fleet control.
Do not mutate FirstMate Project 3 yet.
Keep live acting workflows disabled or clearly gated until token scope and target repos are confirmed.
When done, report the exact config, required secrets, validation output, and remaining risk.
```

## Phase 1: Make Wheelhouse The GitHub Control Layer

Goal: prove Wheelhouse can safely become the repeatable GitHub issue and decision-card system.

Build or run:

- Configure the Wheelhouse fork for the AGOS fleet.
- Map Wheelhouse cards to AGOS issue state.
- Build the Project 3 bridge.
- Run a safe pilot against the FirstMate issue queue.
- Decide whether `fm-issues` becomes a bridge or is retired.

Main issue:

- `autoprintworks/wheelhouse#1`: Configure Wheelhouse fork for AGOS fleet control.
- `autoprintworks/wheelhouse#2`: Adapt Wheelhouse cards to AGOS issue state.
- `autoprintworks/wheelhouse#3`: Bridge Wheelhouse issue state to FirstMate Project 3.
- `autoprintworks/wheelhouse#4`: Run safe Wheelhouse pilot against FirstMate.

Done when:

- Wheelhouse config names the correct AGOS repo set.
- A tested AGOS issue-state adapter exists.
- Project 3 sync has a dry-run and readback path.
- The pilot proves no unexpected GitHub issue, label, or Project mutation happened.
- FirstMate #120 and #116 have a clear retarget, supersede, or close decision.

First prompt:

```text
Work on GitHub issue autoprintworks/wheelhouse#1.
Configure the Wheelhouse fork for AGOS fleet control.
```

## Phase 2: Retarget FirstMate IssueOps And Project Sync

Goal: FirstMate uses Wheelhouse-backed GitHub state instead of a competing custom IssueOps engine.

Build:

- Retarget or supersede #120 based on Wheelhouse #2 and #4.
- Retarget or supersede #116 based on Wheelhouse #3 and #4.
- Keep `fm-issues` only if it is useful as a bridge or readback tool.
- Preserve all evidence in issue comments and readback artifacts.

Main issue:

- #120: Build FirstMate IssueOps state machine.
- #116: Create the Kanban/GitHub sync issue.

Done when:

- FirstMate has one GitHub issue-control path, not two.
- Project 3 sync consumes the Wheelhouse-backed state contract.
- Any old local IssueOps code has a clear purpose or is retired.

## Phase 3: Freeze The Pipeline Contract

Goal: define what each stage means so agents do not invent their own workflow.

Define:

- Idea.
- Research.
- Prototype.
- PRD.
- Kanban Board.
- Execution.
- QA.
- Stow.

Main issues:

- #112: Define the AGOS-to-FirstMate pipeline contract.
- #117: Add Stow workflow.
- #85: Strategic parent.

Done when:

- Each stage has an input, output, owner, evidence requirement, stop condition, and next step.
- Stow clearly means "preserve useful inactive work", not "delete" or "forget".

## Phase 4: Prove Windows Readiness

Goal: the machine can honestly say whether it is ready to run FirstMate work.

Build or verify:

- Node and npm paths.
- Python path.
- PowerShell policy.
- Git Bash or supported shell path.
- `gh-axi`.
- `tasks-axi`.
- `jq`.
- no-mistakes.
- Codex App backend.
- optional backend status for tmux and herdr.

Main issues:

- #114: Build Windows runner and dependency proof.
- #110: Harden setup readiness and dependency proof.
- #103: Preserve Windows-explicit runtime contract.
- #111: Add captain-facing activation output.
- #102 and #91: TypeScript runtime foundation.

Done when:

- One activation command tells the captain what works, what is missing, and how to fix it.
- Optional missing backends do not block the supported Codex App path.

## Phase 5: Build The Execution Ledger Gate

Goal: FirstMate cannot start unsafe or duplicate work.

Build:

- Source issue snapshot.
- Task id.
- Dependencies.
- Conflict keys.
- Validation commands.
- Model guidance.
- Attempt history.
- Worker ownership.
- PR links.
- Teardown state.

Main issue:

- #115: Create the execution ledger gate and ownership issue.

Done when:

- Dispatch is blocked if dependencies are unmet.
- Dispatch is blocked if validation is missing.
- Dispatch is blocked if a worktree or issue is already owned.
- Teardown is blocked if work is unlanded.

## Phase 6: Prove One Visible Work Lane

Goal: one real issue can run through a visible Codex App worker lane.

Build or prove:

- Select one approved issue.
- Create a bounded worker brief.
- Launch one visible Codex thread.
- Record the worker home or worktree.
- Run validation.
- Capture the worker report.
- Archive or clean up safely.

Main issue:

- #96: Prove visible Codex issue execution lane.

Done when:

- One issue reaches a validated worker result.
- The captain can see what happened.
- No hidden worktree confusion remains.

## Phase 7: Prove Separate QA And no-mistakes

Goal: the implementation agent does not review itself.

Build or prove:

- Separate implementation lane.
- Separate review or no-mistakes lane.
- PR proof readback.
- CI proof.
- Bounded rework loop.

Main issues:

- #97: Prove separate no-mistakes and adversarial review lane.
- #101: Create no-mistakes PR proof ownership issue.
- #100: Audit issue 89 closure and residual progress parity.
- #104 only if #100 proves residual work exists.

Done when:

- A PR cannot be marked ready because the implementer says it is ready.
- Proof comes from a separate lane and current-head evidence.

## Phase 8: Run The Full Happy Path

Goal: prove the whole MVP loop once from issue to safe delivery.

Run:

```text
GitHub issue -> Project card -> tasks-axi task -> FirstMate worker -> validation -> separate QA -> PR proof -> captain merge decision -> teardown -> final report
```

Main issue:

- #98: Prove end-to-end FirstMate happy-path smoke.

Done when:

- One complete task passes the loop.
- The final report names the issue, worker, validation, QA proof, PR state, and teardown result.

## Phase 9: Make Model Routing Cheap And Safe

Goal: use strong models only where they are needed.

Build:

- Requested model.
- Observed model.
- Confidence.
- Cost tier.
- Escalation reason.
- Fallback rule.

Main issue:

- #39: Create model routing and token-efficiency policy issue.

Done when:

- Cheap models can do bounded work safely.
- Strong models are reserved for planning, architecture, risk, and review.
- Failed cheap attempts escalate instead of looping.

## Phase 10: Scale With Secondmates And Parallel Work

Goal: run more than one safe work lane without losing control.

Build or prove:

- One secondmate with isolated state.
- One secondmate-owned crewmate flow.
- Two independent tasks running safely.
- Conflict detection for overlapping tasks.

Main issues:

- #79: Create secondmate orchestration proof issue.
- #118: Prove parallel execution with a small batch.

Done when:

- FirstMate can supervise a secondmate without losing state.
- Two safe tasks can run at the same time.
- Unsafe overlap is refused instead of guessed.

## Phase 11: Build AGOS Command Centre Later

Goal: create the business-facing interface after the execution state is real.

Do not build this too early.
The interface should sit over proven planning, GitHub, execution ledger, QA, and Stow state.

Main issue:

- #119: Define AGOS Command Centre interface backlog.

Done when:

- AGOS Command Centre has a clear backlog and data-source contract.
- It shows real orchestration state, not imagined state.

## What You Should Tell Codex Next

Use one of these exact instructions.

To continue the immediate work:

```text
Continue Phase 1.
Work through autoprintworks/wheelhouse#1, then #2, then #3, then #4.
Give me the readback after each issue.
```

After Phase 1 is clean:

```text
Continue Phase 2.
Retarget FirstMate #120 and #116 based on the Wheelhouse pilot evidence.
```

After Phase 2 is clean:

```text
Continue Phase 3.
Write and verify the pipeline contract so every stage has clear inputs, outputs, evidence, and stop conditions.
```

## What Not To Do Yet

Do not start parallel execution until the visible lane, QA lane, ledger gate, and model routing are proven.
Do not build the AGOS Command Centre UI before the end-to-end happy path works.
Do not let lower-intelligence models make broad product decisions without IssueOps, tests, and readback.
Do not close old knowledge unless Stow or a replacement issue preserves it.

## Definition Of Finished MVP

The MVP is finished when the captain can give FirstMate an approved issue and the system can:

- Verify the machine is ready.
- Import or select the issue.
- Create a local task.
- Choose a model route.
- Launch a visible worker.
- Validate the result.
- Run separate QA or no-mistakes.
- Open or update a PR.
- Read proof from GitHub.
- Ask the captain before merge.
- Archive and tear down safely.
- Produce a final report.

## Definition Of Finished Product Pipeline

The pipeline is finished when the captain can start from an idea and reliably choose one of these paths:

- Idea -> direct execution -> QA -> PR.
- Idea -> research -> decision -> execution or Stow.
- Idea -> prototype -> PRD -> issues -> execution -> QA -> PR.
- PRD -> issue graph -> ledger tasks -> parallel execution -> QA -> merge.
- Any stage -> Stow with source links and a reactivation trigger.

The finished pipeline must make the next step obvious at every stage.
It must preserve why each piece of work exists.
It must make safe parallelism visible.
It must make model cost decisions visible.
It must never rely on the implementation agent reviewing itself.
