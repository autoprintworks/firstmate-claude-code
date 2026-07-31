---
name: stow
description: Preserve valuable but inactive work without keeping it on the active board when an issue, report, plan, prototype, or idea should be shelved, linked, and made retrievable instead of deleted, left open, or treated as done.
---

# Stow

Use Stow when valuable context should be preserved but should not stay in the active execution flow.
Stow is for dormant knowledge, deferred scope, superseded plans, failed attempts with useful evidence, reusable research, design alternatives, and issue content that would otherwise clutter the board.

Stow is not delete.
Stow is not done.
Stow is not a hidden backlog.
Stowed material should be easy to find later, but it should not create active execution pressure.

## When To Stow

Stow an item when all of these are true:

- The material has durable value.
- The material is not needed for the current deliverable.
- Keeping it open would confuse prioritization or duplicate another active issue.
- Future retrieval has a plausible trigger.

Do not stow secrets, credentials, live blockers, production incidents, required QA evidence, or work that someone is actively executing.
Do not use Stow to avoid making a clear close, merge, or fix decision.

## Workflow

1. Identify the source item.
2. Decide why it should leave the active flow.
3. Extract the durable knowledge.
4. Record where it can be found again.
5. Link the stowed record from the source before closing, replacing, or moving the source item.
6. Define a concrete reactivation trigger.

For GitHub issues, comment with the Stow summary before closing or relabeling the issue.
Use a Stow label when one exists, such as `pipeline:stow`.
If the stowed material replaces an issue, link the active replacement issue.
If the old issue should stay open because it still contains required work, do not stow it.

For FirstMate private fleet records, write stowed artifacts under `data/stow/`.
For product-shared knowledge, ask a crewmate to place the artifact in the project documentation through the normal delivery pipeline.

## Artifact Shape

Use this shape for a stowed record:

```markdown
# <Short Title>

Stowed on: <YYYY-MM-DD>
Source: <issue, PR, report, thread, or file link>
Status: Stowed
Owner: <project or workflow owner>

## Why This Is Stowed

<One short paragraph explaining why it is valuable but inactive.>

## What To Keep

- <Reusable fact, decision, evidence, or idea.>
- <Another preserved detail if needed.>

## Active Replacement

<Link to the active issue or plan, or "None".>

## Reactivation Trigger

<Specific future condition that should bring this back.>
```

## Quality Bar

The reader should be able to answer three questions from a stowed record:

- Why is this not active?
- What useful knowledge did we preserve?
- What exact condition should make us look at it again?

If any answer is vague, tighten the stow before closing the source item.
