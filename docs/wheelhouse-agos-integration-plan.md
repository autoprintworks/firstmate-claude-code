# Wheelhouse And AGOS Integration Plan

This document records the decision made on 2026-07-03 after forking and inspecting Wheelhouse.
Use it when deciding what GitHub issues to give coding agents next.

## Setup Done

The Wheelhouse fork exists at `autoprintworks/wheelhouse`.
It is cloned locally under `C:\AGOS\firstmate-gui-agnostic\projects\wheelhouse`.
It is registered in FirstMate's private fleet registry at `data/projects.md`.
GitHub Issues are enabled on the fork.
The fork now has four setup and integration issues.

## Local Validation

The Wheelhouse clone was clean after setup and offline tests.
These tests passed with `PYTHONDONTWRITEBYTECODE=1`:

- `python tests\test_decision.py`
- `python tests\test_reconcile.py`
- `python tests\test_card_refresh.py`
- `python tests\test_qualify_refs.py`
- `python tests\test_author_filter.py`
- `python tests\test_merge_conflict.py`

These tests could not run because `PyYAML` is missing from `C:\Python313\python.exe`:

- `python tests\test_ci_autoapprove.py`
- `python tests\test_auto_triage.py`
- `python tests\test_deep_review.py`
- `python tests\test_nl_decisions_search.py`
- `python tests\test_workflow_lint.py`

Wheelhouse issue #1 should either install or document the Python dependency path before claiming local validation is complete.

## What Wheelhouse Is

Wheelhouse is a GitHub-native IssueOps machine.
It uses GitHub Issues as decision cards.
It uses hidden machine-readable state blocks inside issue bodies.
It uses labels as a compact state projection.
It uses GitHub Actions to ingest, reconcile, refresh, and execute owner-approved decisions.
It can run without a hosted server or database.
It has optional Claude features for auto triage, deep review, and natural-language decisions, but the deterministic core does not require an LLM.

## What Wheelhouse Is Not

Wheelhouse is not the AGOS product UI.
Wheelhouse is not the FirstMate worker runtime.
Wheelhouse is not the local execution ledger.
Wheelhouse should not decide product strategy by itself.
Wheelhouse should not replace FirstMate's supervision, validation, teardown, or captain approval rules.

## The Three Layers

| Layer | Job | Current repo | Why it exists |
| --- | --- | --- | --- |
| AGOS | The eventual command centre the captain uses every day. | `firstmate-gui-agnostic` for now. | Gives the captain one clean interface for ideas, plans, workers, evidence, and shipping. |
| FirstMate | The execution supervisor and safety system. | `firstmate-gui-agnostic`. | Spawns workers, tracks execution, validates work, supervises QA, protects merges and teardown. |
| Wheelhouse | The GitHub IssueOps and decision-card engine. | `wheelhouse`. | Keeps GitHub issues, decisions, labels, cards, and reconcile behavior consistent and repeatable. |

The target architecture is AGOS over FirstMate over Wheelhouse-backed GitHub state.
AGOS is the thing the captain ultimately uses.
FirstMate remains the operating crew.
Wheelhouse becomes the GitHub control engine underneath.

## Main Decision

Use Wheelhouse as a separate repo for now.
Do not copy it directly into FirstMate yet.
Do not keep expanding a competing custom FirstMate IssueOps implementation unless the Wheelhouse pilot fails.
The current `fm-issues` work should become a thin bridge, compatibility layer, or temporary readback tool.
The real GitHub issue-card and reconcile engine should come from the Wheelhouse fork.

This gives us cleaner control because Wheelhouse can evolve as a focused GitHub automation engine.
FirstMate can stay focused on execution.
AGOS can later call both through a single product interface.

## Live Wheelhouse Issues To Code

Code these Wheelhouse issues first, in this exact order:

1. `autoprintworks/wheelhouse#1` - Configure Wheelhouse fork for AGOS fleet control.
2. `autoprintworks/wheelhouse#2` - Adapt Wheelhouse cards to AGOS issue state.
3. `autoprintworks/wheelhouse#3` - Bridge Wheelhouse issue state to FirstMate Project 3.
4. `autoprintworks/wheelhouse#4` - Run safe Wheelhouse pilot against FirstMate.

Do not start with broad AGOS UI work.
Do not start by rewriting FirstMate's whole issue system again.
First prove that the Wheelhouse fork can safely represent and reconcile the current FirstMate issue queue.

## FirstMate Issue Decisions

Keep `autoprintworks/firstmate-gui-agnostic#85` as the strategic parent.
Keep `autoprintworks/firstmate-gui-agnostic#112` as the AGOS-to-FirstMate pipeline contract.
Keep `autoprintworks/firstmate-gui-agnostic#115` as the execution ledger gate.
Keep `autoprintworks/firstmate-gui-agnostic#117` as the Stow workflow.
Keep the execution proof issues `#96`, `#97`, `#98`, `#39`, `#79`, `#118`, and `#119`.

Retarget `autoprintworks/firstmate-gui-agnostic#120`.
It should stop being "build a whole FirstMate IssueOps replacement."
It should become "bridge FirstMate issue state to Wheelhouse, and retire or shrink the local `fm-issues` prototype once Wheelhouse proves itself."

Retarget `autoprintworks/firstmate-gui-agnostic#116`.
It should stop being a standalone Project/Kanban sync implementation that competes with Wheelhouse.
It should become the FirstMate-side acceptance issue for Wheelhouse issue #3.

Do not close `#120` or `#116` yet.
Close or supersede them only after Wheelhouse issues #2, #3, and #4 produce readback evidence.

Keep `#104` parked until `#100` proves whether it is still needed.
Do not code `#85` as a task.

## Correct Coding Order From Here

1. Code `autoprintworks/wheelhouse#1`.
2. Code `autoprintworks/wheelhouse#2`.
3. Code `autoprintworks/wheelhouse#3`.
4. Code `autoprintworks/wheelhouse#4`.
5. Retarget or supersede FirstMate `#120` based on the pilot evidence.
6. Retarget or supersede FirstMate `#116` based on the Project 3 bridge evidence.
7. Continue FirstMate `#112` to freeze the overall product pipeline contract.
8. Continue FirstMate `#114`, `#110`, and `#111` to prove Windows readiness and activation output.
9. Continue FirstMate `#115` to build the execution ledger gate.
10. Continue FirstMate `#117` to make Stow operational.
11. Continue the visible execution and QA proofs in `#96`, `#97`, `#98`, and `#101`.
12. Continue model routing, secondmates, parallel work, and AGOS interface backlog through `#39`, `#79`, `#118`, and `#119`.

## How Wheelhouse Helps

Wheelhouse gives us a proven pattern for machine-readable GitHub issues.
It reduces the risk that every agent invents a different issue format.
It gives us reconcile instead of one-off manual cleanup.
It keeps decision state visible in GitHub while still parseable by tools.
It separates deterministic handlers from LLM advice.
It gives AGOS a future backend for "what needs a decision" without building a new queue from scratch.

## Immediate Prompt To Use

Use this prompt for the next coding agent:

```text
Work on GitHub issue autoprintworks/wheelhouse#1.
Configure the Wheelhouse fork for AGOS fleet control.
Do not mutate FirstMate Project 3 yet.
Keep live acting workflows disabled or clearly gated until token scope and target repos are confirmed.
When done, report the exact config, required secrets, validation output, and remaining risk.
```

After `#1` is complete, use:

```text
Work on GitHub issue autoprintworks/wheelhouse#2.
Adapt Wheelhouse cards to AGOS issue state.
Compare Wheelhouse `wheelhouse-state` with FirstMate `firstmate-state`.
Decide whether `fm-issues` becomes a bridge or is retired after the pilot.
Use fixtures from current FirstMate issues #85, #112, #116, #117, and #120.
```

## Stop Conditions

Stop and ask the captain before enabling any workflow that can merge, close, or mutate important FirstMate issues.
Stop if the Wheelhouse fork needs secrets the captain has not created.
Stop if ProjectV2 access is missing and print the exact GitHub auth repair command.
Stop if the pilot would create public decision cards containing private operating information.
