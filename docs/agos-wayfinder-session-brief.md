# AGOS Pipeline Pieces Overview

## 1. Orientation

### What This Document Is

This document is a simple map of the systems I am trying to connect.

It is not a prompt.

It is not a detailed build plan.

It is not written for an agent to blindly follow.

It is written so I can understand the moving parts before turning them into a proper planning session.

The core pieces are:

- Kun Chen workflow.
- Model routing.
- FirstMate.
- Secondmates.
- Crewmates.
- Wheelhouse.
- GitHub Issues.
- GitHub Projects.
- GitHub Actions.
- AXI tools and infrastructure.
- No-Mistakes.
- Codex and GPT.
- AGOS.

### Naming Boundary

AGOS will not use the sailor theme.

FirstMate, secondmates, crewmates, and captain are useful names inside the Kun Chen tooling while we are bootstrapping.

They are not the final AGOS brand language.

The long term direction is to rebrand and reshape the useful parts of Kun Chen's tools into a cohesive AGOS operating system and infrastructure.

For now, this document may mention FirstMate terms because those are the tools we are using.

When describing the future AGOS product, the language should move toward neutral operating system terms such as:

- Operator.
- Workers.
- Specialists.
- Supervisors.
- Work units.
- Decisions.
- Reviews.
- Approvals.
- Releases.

### The North Star

AGOS should become the operating system for building companies and products with AI.

I should be able to see high level decisions, product direction, company priorities, open risks, active work, and shipping status in one place.

The agents should handle the execution details without forcing me to manually babysit every command, every worker, and every GitHub page.

The basic shape is:

```text
Idea
-> Research
-> Prototype
-> Spec
-> Kanban Board
-> Execution
-> QA
-> Further QA with No-Mistakes
-> Pull Request
-> Founder Decision
-> Merge / Hold / Rework / Archive
```

The point is not to collect more tools.

The point is to make many tools behave like one understandable operating system.

### Reality Check

None of this is working properly yet.

That is the important truth.

The current job is not to pretend the pipeline works.

The current job is to make the pipeline work end to end on Windows, across different GUIs and agent harnesses, with no hidden fragility.

Kun Chen's workflow is the inspiration.

We are forking and adapting it for this operating environment.

The first proof is not AGOS itself.

The first proof is one real task moving through the full path from issue to clean PR without broken supervision, bad windows, missing context, or fake evidence.

## 2. Operating Model

The Kun Chen workflow is based on one main idea.

The human should not directly manage every worker.

The human should talk to one coordinating agent.

That coordinating agent should understand the work, route it, supervise it, and report back clearly.

### How Kun Chen Uses FirstMate

Kun Chen's working pattern is to mainly talk to one visible FirstMate thread.

That one thread hides the complexity of many other agent threads.

When project A finishes while project B is being discussed, the update is surfaced back into the same FirstMate thread.

The human then deals with queued decisions one by one.

FirstMate uses the strongest reasoning model because it carries strategy, context switching, routing, supervision, and user communication.

Secondmates are persistent specialist agents with charters.

A secondmate can own a project, repo group, or recurring lane of responsibility.

Crewmates are temporary execution agents.

Each crewmate receives one bounded task, works in an isolated workspace, reports back, and is removed when the work is safely landed or abandoned.

When FirstMate or a secondmate dispatches a crewmate, it chooses the harness, model, and reasoning effort for that task.

This is the key cost-control mechanism.

The strongest model is not used for every worker.

Simple bug fixes, mechanical edits, CI readback, and basic documentation can use cheaper or faster models when the issue is clear.

All PRs then go through a separate adversarial validation lane.

The implementation worker should not be the final reviewer of its own work.

For AGOS, we want to recreate this pattern in a Windows, GUI-agnostic, and harness-agnostic way.

The goal is not to copy the branding.

The goal is to copy the operating shape.

The temporary FirstMate pattern is:

```text
Founder
-> FirstMate
-> Secondmates
-> Crewmates
-> Reports / PRs / Decisions
-> Founder
```

### FirstMate

FirstMate is the current main operating agent.

It is the normal point of contact.

It should understand the repos, the current work, the state of workers, and the next decision needed.

In future AGOS language, this role is closer to an operator or execution supervisor.

### Secondmates

Secondmates are persistent specialist agents in the current FirstMate terminology.

They can own a product area, repo family, platform concern, or recurring responsibility.

They should reduce the load on FirstMate when the system grows.

In future AGOS language, these are specialists or domain supervisors.

### Crewmates

Crewmates are temporary task workers in the current FirstMate terminology.

They get one clear task, one brief, one workspace, and one expected result.

They do the work, report back, and then get torn down safely.

In future AGOS language, these are workers or execution agents.

## 3. Delivery Pipeline

The pipeline should be readable as a table before it becomes automation.

Each row should make clear what starts the stage, what comes out, which skill or tool helps, what model tier is likely, and what must be true before the next stage begins.

| Stage | Purpose | Main skill or tool | Output | Likely model route | Parallel and worktree notes |
| --- | --- | --- | --- | --- | --- |
| Idea | Capture the opportunity and why it matters | AGOS later, note or issue now, [Wayfinder](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md) for large ideas | Captured idea and unknowns | Strong when strategic, cheaper when simple capture | No worktree needed |
| Research | Turn unknowns into evidence and options | [Wayfinder](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md), browser tools, GitHub tools | Research summary and recommendation | Strong for synthesis, cheaper for source gathering | Research tickets can run in parallel |
| Prototype | Test a direction before full build | [Wayfinder](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md), Codex, design tools, Lavish | Demo, spike, mockup, or prototype finding | Workhorse or strong depending on ambiguity | Prototype work should use scratch branches or isolated worktrees |
| Spec | Convert resolved thinking into a build contract | [To Spec](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md) | Scope, non-goals, acceptance criteria, validation plan | Strong model preferred | No implementation worktree yet |
| Kanban Board | Split the spec into executable vertical slices | [To Tickets](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md), GitHub Issues, GitHub Projects | Issues, dependencies, blocked edges, ready states | Strong or high workhorse because planning quality controls cost later | Issues should be planned for safe parallel execution |
| Execution | Implement one issue or bounded unit | [Implement](https://github.com/mattpocock/skills/blob/main/skills/engineering/implement/SKILL.md), FirstMate, secondmates, crewmates | Branch, commits, validation evidence, worker report | Cheapest safe model for the issue | Every worker needs an isolated worktree and clear ownership |
| QA | Review the change independently | [Code Review](https://github.com/mattpocock/skills/blob/main/skills/engineering/code-review/SKILL.md), separate reviewer agent | Findings, fixes, risks, pass or fail decision | Workhorse for normal review, strong for risky review | Reviewer must not be the same worker that implemented the change |
| Further QA | Run the shipping gate | [No-Mistakes](https://github.com/kunchenguid/no-mistakes) | Review proof, tests, docs, lint, push, PR, CI evidence | Routed per sub-stage, not one frontier model for everything | Must read the correct branch and never confuse worktrees |
| Pull Request | Present evidence for review | GitHub CLI, GitHub PRs, FirstMate helpers | PR with issue links and validation notes | Cheap or deterministic tooling | PR head must match the worker branch |
| Founder Decision | Decide merge, hold, or rework | GitHub PR, Wheelhouse later, AGOS later | Merge approval, hold, or fix request | Human decision with agent summary | Merge only after evidence is understood |
| Merge / Hold / Rework / Archive | Close the loop safely | FirstMate merge helpers, GitHub, AGOS later | Landed work or clear next state | Mostly deterministic tooling | Teardown only after work is landed or intentionally abandoned |

The No-Mistakes sub-pipeline is:

| No-Mistakes step | Purpose | Suggested model tier | Why |
| --- | --- | --- | --- |
| Review | Find real defects and spec mismatches | Workhorse by default, strong for high-risk changes | This is the hardest judgment step |
| Test | Run and interpret relevant tests | Workhorse for diagnosis, cheap for simple command readback | Running tests is mechanical, interpreting failures may not be |
| Docs | Check whether documentation needs updating | Cheap or workhorse | This rarely needs the most expensive frontier model |
| Lint | Run lint, format, typecheck, or equivalent | Cheap or deterministic tooling | The command output usually decides the next step |
| Push | Push the branch | Deterministic tooling | No frontier reasoning needed |
| PR | Create or update the PR | Cheap or deterministic tooling | The hard thinking should already be in the evidence |
| CI | Read CI and summarize status | Cheap for green, workhorse for failures | Failure diagnosis may need more intelligence |

## 4. Tooling Stack

### Model Routing

Model routing is how the system decides which model should do which kind of work.

The strongest model should be used where judgment, uncertainty, or risk is high.

Cheaper or faster models should be used where the task is clear and bounded.

Good planning reduces model cost because workers do not need to guess.

Poor planning increases model cost because workers need to infer the missing strategy.

The model router should work at two levels.

First, it should route each task to the right harness, model, and effort before the worker starts.

Second, it should route sub-stages inside expensive workflows such as No-Mistakes.

No-Mistakes currently risks becoming expensive because one frontier model can be used across every stage.

That is not the target operating model for AGOS.

Review, failure diagnosis, and high-risk reasoning may justify a stronger model.

Documentation checks, lint, push, PR creation, and simple CI readback usually do not.

The routing policy should preserve quality where judgment matters and cut token cost where the work is mechanical.

#### Stronger Model Work

Use stronger models for:

- Company strategy.
- Product direction.
- Wayfinder maps.
- Complex research synthesis.
- Spec creation.
- Architecture decisions.
- Risky reviews.
- Hard debugging.
- High-stakes No-Mistakes review.

#### Cheaper Model Work

Use cheaper or faster models for:

- Small bug fixes.
- Mechanical edits.
- Formatting.
- Simple docs.
- Lint fixes.
- CI readback.
- Clear issue execution.

#### No-Mistakes Model Routing

No-Mistakes should become a routed pipeline rather than a single-model pipeline.

The default should not be the most expensive frontier model for every step.

| No-Mistakes area | Default route | Escalate when |
| --- | --- | --- |
| Adversarial review | Workhorse review model | Security, architecture, data loss, payment, auth, or complex regression risk |
| Test execution | Cheap command runner | Test failures need diagnosis |
| Test failure diagnosis | Workhorse model | Root cause is unclear or broad |
| Documentation check | Cheap or workhorse | Docs explain complex architecture or user-facing behavior |
| Lint and formatting | Deterministic tooling | Tool output conflicts or exposes deeper code problems |
| Push and PR | Deterministic tooling | Git state is confusing or branch safety is unclear |
| CI readback | Cheap model | CI fails or the failure affects release risk |

This keeps No-Mistakes adversarial without making every step equally expensive.

### Execution Supervisor

FirstMate is not the final AGOS product.

FirstMate is the operating engine underneath the future product.

It should handle:

- Reading ready issues.
- Creating worker briefs.
- Choosing a model route.
- Launching workers.
- Tracking secondmates and crewmates.
- Managing worktrees.
- Watching status.
- Receiving reports.
- Running validation.
- Blocking unsafe teardown.
- Asking the founder before merge.

It should not become a pile of manual commands.

It should become a reliable operating layer that AGOS can eventually control through a better interface.

### Parallel Work And Worktree Safety

Parallel work is essential.

The system cannot take thirty minutes per task and force everything else to wait.

The way to make parallelism safe is not to let agents improvise.

The way to make it safe is to give every task a clear owner, isolated workspace, branch, validation lane, and teardown rule.

Parallel execution should require:

- One issue or work unit per worker.
- One isolated worktree per worker.
- One branch per worker.
- One recorded owner per issue.
- One clear validation route.
- One PR or report outcome.
- No teardown until work is landed, merged, archived, or intentionally abandoned.

FirstMate should know which workers can run at the same time.

It should also know which workers cannot run at the same time because they touch the same files, share migrations, modify the same workflow, or depend on each other.

AGOS should eventually make that visible before dispatch.

### Specialist Supervisors

Secondmates should not be added just because they exist.

They become useful when an area needs persistent context and repeated supervision.

Possible secondmates for our workflow:

- AGOS Product secondmate for product direction, specs, and board structure.
- FirstMate Platform secondmate for the fork, harnesses, workers, watchers, and Windows compatibility.
- GitHub Ops secondmate for issues, PRs, CI, Wheelhouse, and repo hygiene.
- QA secondmate for No-Mistakes, review standards, tests, and release evidence.
- Docs and Memory secondmate for captured conversations, decisions, and durable project knowledge.
- Model Routing secondmate for cost, model choice, and dispatch profiles.

The first priority is still to make the primary FirstMate loop reliable.

Secondmates should be introduced after the basic loop is stable enough to supervise them without creating more confusion.

### AXI Infrastructure

AXI means Agent eXperience Interface.

AXI is the standard for tools that agents use through commands.

It matters because agents need tools that are predictable, non-interactive, token efficient, and easy to recover from.

An AXI tool should:

- Give compact structured output.
- Avoid interactive prompts.
- Provide clear errors.
- Make mutations idempotent where possible.
- Show useful current state by default.
- Offer exact next commands when helpful.
- Work from session hooks where ambient context is useful.
- Support Codex, Claude Code, and OpenCode where reasonable.

AXI is not just a single tool.

It is an infrastructure style for making tools agent-friendly.

The AGOS stack should use AXI-style interfaces for:

- GitHub work.
- Browser work.
- Task and issue state.
- Worker supervision.
- No-Mistakes evidence.
- Wheelhouse decisions.
- AGOS state later.

Useful AXI-related tools to consider:

- `gh-axi` for GitHub operations.
- `tasks-axi` for local task state where used.
- `lavish-axi` for rich review surfaces.
- Browser or Chrome AXI tools for inspecting web pages and UI flows.
- Future AGOS AXI commands for AGOS state and decisions.

The deeper goal is to give agents command surfaces that do not waste tokens, do not hang waiting for prompts, and do not depend on fragile UI behavior.

### Skill Toolkit

Skills are reusable operating procedures for agents.

They should make the pipeline more consistent.

Important skills and where they fit:

- `wayfinder` for large unclear work that needs investigation tickets.
- `to-spec` for turning resolved thinking into a spec.
- `to-tickets` for turning a spec into executable issues.
- `implement` for executing one ticket or bounded piece of work.
- `code-review` for independent QA.
- `no-mistakes` for the final quality gate.
- `afk` for away-mode supervision when I step away.
- `stow` for capturing an AI chat or useful conversation context so it can be recovered later.
- `updatefirstmate` for keeping our fork aligned with the upstream inspiration while preserving our changes.

The `afk` skill is important because it changes supervision behavior when I am away.

It should let routine worker wakes be handled without burning unnecessary model turns.

It must still escalate approval-relevant decisions.

Away mode must never mean automatic approval.

### GitHub Decision Layer

GitHub Issues should be the first practical task system.

They give work stable IDs.

They make tasks visible to both humans and agents.

GitHub Projects can be the first kanban board.

The board should show:

- Ready.
- Blocked.
- In progress.
- In QA.
- PR open.
- Done.
- Archived or deferred.

Wheelhouse is different.

Wheelhouse is not the main planning system.

Wheelhouse is a GitHub decision inbox.

It becomes useful when decisions are scattered across many repos and PRs.

Example Wheelhouse use:

```text
PR is ready
-> Wheelhouse creates a decision card
-> Founder reviews the card
-> Founder ticks merge, hold, close, or investigate
-> GitHub action happens
```

Wheelhouse probably does not need to be fully implemented first.

It becomes more valuable when we have enough repos, companies, products, issues, and PRs that decisions start scattering.

For now, GitHub Issues and Projects are probably the more important foundation.

### Quality Gate

No-Mistakes is the stricter quality gate before PRs are treated as clean.

It should be separate from the implementation worker.

The implementation worker should not be trusted as its own final reviewer.

No-Mistakes should produce evidence, not vibes.

The evidence should include:

- What was reviewed.
- What tests ran.
- What docs were checked.
- What lint or type checks ran.
- What branch was pushed.
- Which PR was created.
- What CI reported.

This is one of the most important stages because it protects the system from convincing but low-quality agent output.

## 5. Platform Foundation

The workflow must work properly on Windows.

It must be GUI-agnostic.

It must be harness-agnostic.

Codex Desktop is the first important environment to make reliable, but it should not be the only supported shape.

The same operating layer should be able to support Codex, Claude Code, OpenCode, and future AGOS interfaces through adapters.

It must not depend on Linux assumptions that break in this environment.

It must not create black CLI popup windows.

It must not steal focus or leave unusable terminal windows open.

It must not degrade the active GUI or agent harness over time.

It must not use unrelated application folders such as PDF application directories as working space.

Toolchain paths should be repo-local or user-toolchain paths that make sense.

For this repo, local helper tools should live under:

```text
C:\AGOS\firstmate-gui-agnostic\.tools\
```

The likely answer is an abstraction layer.

That layer should hide the differences between Windows process behavior, GUIs, agent harnesses, GitHub tooling, worker launchers, and future AGOS controls.

The abstraction should provide:

- No-popup process launching.
- Reliable hidden background workers.
- Clean stdout and stderr capture.
- Stable worker metadata.
- Safe teardown.
- Watcher lifecycle control.
- GUI-friendly behavior.
- Harness adapter boundaries.
- Repo-local configuration.
- Clear error messages.

This is not polish.

This is foundational.

If the launcher, watcher, and worker system are unreliable, AGOS cannot safely sit on top of it.

## 6. Transition Plan

### AGOS Transition

At first, the pieces can remain separate:

- Wayfinder for planning.
- GitHub Issues for tasks.
- GitHub Projects for board state.
- FirstMate for execution supervision.
- No-Mistakes for final QA.
- GitHub PRs for merge decisions.
- Wheelhouse as an optional decision inbox.

AGOS should not replace everything at once.

AGOS should first make the workflow visible.

Then it should make the workflow easier to operate.

Then it can become the main interface.

Eventually AGOS should show:

- Company priorities.
- Product ideas.
- Research.
- Prototypes.
- Specs.
- Issues.
- Board state.
- Active workers.
- Secondmates.
- Model routing.
- QA state.
- No-Mistakes state.
- PRs.
- Founder decisions.
- Archived or deferred work.
- Metrics.

### First Useful Loop

The first useful loop should be small but real.

It should prove the whole operating model.

A good first loop is:

```text
Create one real issue
-> Put it on the board
-> Dispatch it through FirstMate
-> Worker implements it
-> Independent QA reviews it
-> No-Mistakes runs the shipping gate
-> Branch is pushed
-> PR is created with real evidence
-> Founder reviews and decides
```

This loop should expose the actual problems.

Those problems should become the next tickets.

That is how we adapt the Kun Chen workflow into our own Windows and AGOS workflow.

### Open Decisions

These are the open questions that need deeper planning:

1. What is the smallest AGOS interface that is useful before AGOS becomes the full operating system?
2. Which stages should stay in GitHub first?
3. Which stages should AGOS own first?
4. When should Wheelhouse become part of the default flow?
5. Which secondmates are genuinely useful now?
6. Which secondmates should wait?
7. How should model routing be configured by stage?
8. How should No-Mistakes split work across models?
9. What should the Windows launcher abstraction look like?
10. How do we prevent black popup windows permanently?
11. How do we prevent GUI or harness performance degradation during long runs?
12. What should be stored in GitHub, FirstMate state, AGOS state, and captured conversation memory?
13. What does the founder need to see before approving merge?

## 7. Reference Links

These links are the public sources or working references for the tools and skills mentioned in this document.

### Kun Chen Tools

- [FirstMate](https://github.com/kunchenguid/firstmate).
- [Wheelhouse](https://github.com/kunchenguid/wheelhouse).
- [No-Mistakes](https://github.com/kunchenguid/no-mistakes).

### FirstMate Skills

- [FirstMate AFK skill](https://github.com/kunchenguid/firstmate/blob/main/.agents/skills/afk/SKILL.md).
- [FirstMate updatefirstmate skill](https://github.com/kunchenguid/firstmate/blob/main/.agents/skills/updatefirstmate/SKILL.md).
- [FirstMate public stow skill](https://github.com/kunchenguid/firstmate/blob/main/skills/stow/SKILL.md).
- [FirstMate internal stow skill](https://github.com/kunchenguid/firstmate/blob/main/.agents/skills/stow/SKILL.md).

### Matt Pocock Engineering Skills

- [Matt Pocock skills repo](https://github.com/mattpocock/skills).
- [Wayfinder skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md).
- [To Spec skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md).
- [To Tickets skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md).
- [Implement skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/implement/SKILL.md).
- [Code Review skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/code-review/SKILL.md).
- [Setup Matt Pocock Skills](https://github.com/mattpocock/skills/blob/main/skills/engineering/setup-matt-pocock-skills/SKILL.md).

### GitHub Tools

- [GitHub CLI](https://github.com/cli/cli).
- [GitHub Issues documentation](https://docs.github.com/en/issues/tracking-your-work-with-issues/about-issues).
- [GitHub Projects documentation](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects).
- [GitHub Actions documentation](https://docs.github.com/en/actions).

### Agent Harnesses

- [OpenAI Codex CLI](https://github.com/openai/codex).
- [Claude Code](https://github.com/anthropics/claude-code).
- [OpenCode](https://github.com/anomalyco/opencode).

### AXI And Local Tooling References

- `gh-axi` is the intended AXI-style GitHub command layer.
- `tasks-axi` is the intended AXI-style task command layer.
- `lavish-axi` is the intended AXI-style rich review surface.
- These AXI tools are referenced as part of the operating direction, but public GitHub repos for these exact names still need to be confirmed before implementation depends on them.
- The local AXI skill currently lives in the user toolchain rather than this repo.
