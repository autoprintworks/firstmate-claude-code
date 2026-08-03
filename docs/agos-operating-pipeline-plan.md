# AGOS Operating Pipeline Plan

This document describes how the current tools should move toward the AGOS end goal.
It is the planning map for turning ideas into shipped work through a controlled AI execution pipeline.

## End Goal

AGOS should become the captain's primary operating system.
The captain should make high-level decisions about companies, products, strategy, priorities, and exceptions.
The board of directors agents should analyze options, surface risks, and recommend paths.
Execution agents should turn approved work into validated pull requests.
The system should preserve context, evidence, decisions, and ownership at every stage.

The final operating loop should look like this:

```text
Idea -> Wayfinder map -> Research -> Prototype -> Spec -> Tickets -> Kanban -> Execution -> Code review -> no-mistakes -> PR -> captain decision -> Merge or Stow
```

## Current Systems

AGOS is the future top-level command centre.
It should eventually show strategy, portfolio decisions, product bets, active work, blocked work, QA evidence, and shipping status.

FirstMate is the current execution supervisor.
It should own worker dispatch, secondmate routing, execution ledgers, validation, handoff, teardown safety, and captain approval boundaries.

GitHub Issues should be the first durable tracker.
They are already visible, linkable, auditable, and easy for agents to read.

GitHub Projects or a later AGOS board should be the kanban surface.
The first board can be GitHub Projects because it reduces custom build work while the execution engine is still being proven.

Wheelhouse is an optional GitHub maintainer decision inbox.
It should not be the AGOS roadmap or primary execution board.
It can later collect cross-repo decisions such as merge, close, approve CI, investigate, and hold.

No-Mistakes is the final validation and shipping gate.
It should provide independent proof that work is ready before the captain is asked to merge.

Codex Desktop on Windows is the local operator environment.
It must be treated as a first-class supported runtime, not an accidental port from Unix assumptions.

## Pipeline Stages

### 1. Idea

Purpose: capture a raw opportunity, product idea, company direction, or operating problem.

Primary tool: AGOS, then Wayfinder when the idea is too large or uncertain for one session.

Input: a loose idea from the captain, a board recommendation, a market observation, or a product pain.

Output: either a small direct task, or a Wayfinder map with a named destination.

Evidence: source notes, assumptions, constraints, and the reason this idea matters.

Stop condition: the idea has either been rejected, stowed, sent to direct execution, or promoted into a Wayfinder map.

### 2. Wayfinder Map

Purpose: turn a large uncertain effort into a shared map of decision tickets.

Primary tool: `/wayfinder`.

Input: a destination that cannot be reached safely in one agent session.

Output: a map issue, child investigation tickets, blocking edges, and a frontier of next decisions.

Evidence: the map issue, decisions so far, unresolved fog, out-of-scope notes, and child issue links.

Stop condition: the path is clear enough to write a spec or to intentionally stow the effort.

### 3. Research

Purpose: answer factual questions that block planning.

Primary tool: `/wayfinder` research tickets.

Input: a sharp research question from the map.

Output: a research summary linked from the map ticket.

Evidence: sources, findings, tradeoffs, and remaining uncertainty.

Stop condition: the ticket has a resolved answer and any new questions have been added to the map.

### 4. Prototype

Purpose: create a cheap artifact to test behavior, user experience, architecture, or feasibility.

Primary tool: `/wayfinder` prototype tickets, optionally backed by a prototype skill or throwaway branch.

Input: a question where discussion alone is too abstract.

Output: a prototype, screenshot, sketch, state machine, local demo, or architecture spike.

Evidence: prototype link, what it proved, what it disproved, and what should not be carried forward.

Stop condition: the prototype has informed a decision and the decision is recorded on the map.

### 5. Spec

Purpose: turn the known plan into a stable build contract.

Primary tool: `/to-spec`.

Input: the current conversation, Wayfinder decisions, prototype evidence, and known constraints.

Output: a spec issue or spec document.

The spec should include:

- Problem statement.
- Solution from the user's perspective.
- User stories.
- Implementation decisions.
- Testing decisions.
- Out of scope.
- Further notes.

Evidence: linked map tickets, prototype artifacts, source discussions, and explicit scope boundaries.

Stop condition: the spec is clear enough to split into execution tickets.

### 6. Kanban Board

Purpose: break the spec into agent-grabbable work.

Primary tool: `/to-tickets`.

Input: an approved spec or plan.

Output: tracer-bullet tickets with blocking edges.

Each ticket should describe one narrow but complete vertical slice.
Each ticket should be demoable or verifiable on its own.
Each ticket should fit inside one fresh agent context window.

Evidence: issue links, blocking relationships, acceptance criteria, and board placement.

Stop condition: the board has a visible frontier of ready tickets and no hidden dependency confusion.

### 7. Execution

Purpose: implement one approved ticket through a supervised worker.

Primary tool: `/implement`, FirstMate, Codex Desktop, and secondmates when scoped delegation is needed.

Input: one ready ticket with acceptance criteria, blockers cleared, and validation expectations.

Output: code changes, tests, local validation evidence, and a worker report.

Evidence: branch, commits, test output, changed files, linked issue, and worker summary.

Stop condition: the implementation is ready for independent review or the task is blocked with evidence.

### 8. QA

Purpose: review the implementation separately from the implementer.

Primary tool: `/code-review`.

Input: a diff against a fixed point and the originating spec or issue.

Output: standards review, spec review, findings, residual risks, and rework instructions.

Evidence: diff base, commits reviewed, standards sources, spec source, and review findings.

Stop condition: findings are either fixed, accepted, or escalated to the captain.

### 9. Further QA

Purpose: run the stricter shipping gate.

Primary tool: No-Mistakes.

Input: the reviewed branch and current repo validation contract.

Output: automated review, tests, lint, docs checks where applicable, PR creation or PR update, and proof.

Evidence: no-mistakes output, PR link, CI state, test evidence, and any remaining exceptions.

Stop condition: the PR is clean enough for captain review, or blocked with concrete next steps.

### 10. Captain Decision

Purpose: decide whether to merge, hold, investigate, close, or stow.

Primary tool: AGOS, GitHub PRs, and optionally Wheelhouse if the decision is a cross-repo maintainer card.

Input: PR, QA evidence, business context, and risk summary.

Output: merge approval, hold decision, rework request, close decision, or Stow artifact.

Evidence: PR discussion, linked issue, review result, no-mistakes proof, and captain decision.

Stop condition: the work is merged, returned for rework, stowed, or closed.

## Role Of Wheelhouse

Wheelhouse should be treated as a decision inbox, not the whole AGOS operating system.

Use Wheelhouse for GitHub maintenance decisions:

- Merge a contributor PR.
- Approve a fork CI run.
- Close or decline an inbound issue.
- Investigate a PR or issue more deeply.
- Hold a decision for manual handling.

Do not use Wheelhouse for the main AGOS roadmap.
Do not use Wheelhouse as the board of directors layer.
Do not use Wheelhouse as the execution ledger.
Do not use Wheelhouse as the only kanban board.

Wheelhouse becomes worthwhile when GitHub decisions are scattered across enough repos that a single decision inbox saves attention.
If the captain is still the only GitHub operator and the repo count is small, Wheelhouse should remain optional.

## What Needs To Be Built

### A. AGOS Pipeline Contract

Define every stage with:

- Input.
- Output.
- Owner.
- System of record.
- Evidence requirement.
- Stop condition.
- Next allowed stage.

This prevents agents from inventing their own process.

### B. Unified Work Item Model

Define the shared object that AGOS, GitHub Issues, FirstMate, Wheelhouse, and no-mistakes all understand.

The model should include:

- Idea id.
- Spec id.
- Ticket id.
- Repo.
- Product or company.
- Stage.
- Status.
- Priority.
- Blockers.
- Owner.
- Worker assignment.
- Validation contract.
- QA state.
- PR link.
- Stow state.
- Decision history.

### C. Issue Tracker Adapter

Use GitHub Issues first.
Keep the adapter narrow so AGOS can later move to a self-owned board without rewriting the execution system.

The adapter should support:

- Create issue.
- Read issue.
- Update structured state.
- Add comment.
- Link blockers.
- Move project field.
- Query frontier work.
- Preserve audit history.

### D. Kanban Projection

The board should be a projection of structured issue state.
It should not be the only place truth lives.

Required columns or states:

- Idea.
- Research.
- Prototype.
- Spec.
- Ready.
- In progress.
- QA.
- no-mistakes.
- PR ready.
- Blocked.
- Stowed.
- Done.

### E. FirstMate Execution Bridge

FirstMate should consume one ready ticket at a time.
It should refuse work when prerequisites are missing.

The bridge should enforce:

- Dependencies cleared.
- No duplicate worker ownership.
- Validation command exists.
- Repo is registered.
- Worktree is safe.
- Model route is selected.
- Captain approval is required for merge.

### F. QA And no-mistakes Contract

The implementer should not review itself.
The QA lane should know the fixed diff base and the originating spec.
No-Mistakes should be the final proof gate before the captain sees a merge decision.

### G. AGOS Command Centre

Build this after the execution path is proven.
The first version should show real state, not imagined state.

It should display:

- Portfolio decisions.
- Active maps.
- Frontier research.
- Specs ready for tickets.
- Tickets ready for execution.
- Workers running.
- QA findings.
- PRs waiting for captain decision.
- Stowed work and reactivation triggers.

## Transition Plan

### Phase 1: Freeze The Pipeline Language

Create the canonical stage contract.
Use this document as the starting point.
Retire ambiguous stage names or map them to the stages above.

### Phase 2: Use GitHub Issues As The First System Of Record

Do not build a custom AGOS board before the work model is stable.
Use GitHub Issues and Projects as the first durable tracker and visible board.

### Phase 3: Prove One Issue Through FirstMate

Run one safe ticket from issue to worker to validation to PR.
Keep this small and visible.

### Phase 4: Add Independent QA

Run `/code-review` against the branch.
Run No-Mistakes after review.
Do not treat a PR as ready because the implementer says it is ready.

### Phase 5: Add Wheelhouse Only Where It Helps

Pilot Wheelhouse for GitHub maintainer decisions.
Do not make it mandatory for internal AGOS execution until the pilot proves it reduces friction.

### Phase 6: Build AGOS Dashboard Over Proven State

Once the issue flow, execution bridge, QA, and PR proof are real, build the AGOS Command Centre as the interface over those systems.

## Open Decisions

These decisions should be resolved before building the AGOS dashboard.

1. Should GitHub Issues remain the long-term work-item store, or only the bootstrap store?
2. Should GitHub Projects remain the kanban board, or should AGOS own the board later?
3. Which stages require captain approval before moving forward?
4. Which decisions belong to the board of directors agents versus FirstMate?
5. When should Wheelhouse become active, and for which repos?
6. Should Wheelhouse LLM features use Claude, GPT, or stay off until the core is proven?
7. What is the minimum evidence required before No-Mistakes can open or update a PR?
8. What should be stowed instead of closed?

## First Pilot

The first pilot should be deliberately small.

Use this path:

```text
One Idea -> one Spec -> three Tickets -> one Execution ticket -> one QA review -> one No-Mistakes run -> one PR -> one captain decision
```

Success means:

- Every stage has an artifact.
- Every handoff is visible.
- The captain can tell what happened without reading the whole conversation.
- The implementation agent did not review itself.
- The PR has current-head validation proof.
- The final decision is captured.

## References

- `docs/start-here-end-to-end-product-plan.md`.
- `docs/current-pipeline-next-plan.md`.
- `docs/wheelhouse-agos-integration-plan.md`.
- Wayfinder: https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md
- To Spec: https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md
- To Tickets: https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md
- Code Review: https://github.com/mattpocock/skills/blob/main/skills/engineering/code-review/SKILL.md
- No-Mistakes: https://github.com/kunchenguid/no-mistakes
