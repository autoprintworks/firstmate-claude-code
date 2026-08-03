---
name: shelve
description: Preserve valuable but inactive work without keeping it on the active board when an issue, report, plan, prototype, or idea should be shelved, linked, and made retrievable instead of deleted, left open, or treated as done.
---

# Shelve

Use Shelve when valuable context should be preserved but should not stay in the active execution flow.
Shelve is for dormant knowledge, deferred scope, superseded plans, failed attempts with useful evidence, reusable research, design alternatives, and issue content that would otherwise clutter the board.

Shelve is not delete.
Shelve is not done.
Shelve is not a hidden backlog.
Shelved material should be easy to find later, but it should not create active execution pressure.

## When To Shelve

Shelve an item when all of these are true:

- The material has durable value.
- The material is not needed for the current deliverable.
- Keeping it open would confuse prioritization or duplicate another active issue.
- Future retrieval has a plausible trigger.

Do not shelve secrets, credentials, live blockers, production incidents, required QA evidence, or work that someone is actively executing.
Do not use Shelve to avoid making a clear close, merge, or fix decision.

## Workflow

1. Identify the source item.
2. Decide why it should leave the active flow.
3. Extract the durable knowledge.
4. Record where it can be found again.
5. Link the shelved record from the source before closing, replacing, or moving the source item.
6. Define a concrete reactivation trigger.

For GitHub issues, comment with the Shelve summary before closing or relabeling the issue.
Use a Shelve label when one exists, such as `pipeline:shelve`.
Note: this skill was previously named `stow`, and the AGOS IssueOps taxonomy (`bin/fm-issues`, `firstmate_gui_agnostic/issueops.py`) still uses the historical names - the `Stow candidate`/`Stowed` work states and `stow:*` labels. Those labels are this workflow; the skill was renamed only because `.agents/skills/stow/` now holds the separate session-knowledge sweep skill.
If the shelved material replaces an issue, link the active replacement issue.
If the old issue should stay open because it still contains required work, do not shelve it.

For FirstMate private fleet records, write shelved artifacts under `data/shelve/`.
For product-shared knowledge, ask a crewmate to place the artifact in the project documentation through the normal delivery pipeline.

## Artifact Shape

Use this shape for a shelved record:

```markdown
# <Short Title>

Shelved on: <YYYY-MM-DD>
Source: <issue, PR, report, thread, or file link>
Status: Shelved
Owner: <project or workflow owner>

## Why This Is Shelved

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

The reader should be able to answer three questions from a shelved record:

- Why is this not active?
- What useful knowledge did we preserve?
- What exact condition should make us look at it again?

If any answer is vague, tighten the shelve before closing the source item.
