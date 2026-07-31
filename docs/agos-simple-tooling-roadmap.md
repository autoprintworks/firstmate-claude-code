# AGOS Simple Tooling Roadmap

This is the simple version of the AGOS plan.
Use it when you need to remember what each tool is for, what order we use them in, and what must be true before we start building AGOS features.

## The Big Idea

AGOS Prime is not just a coding workflow.
It is a business-first holding-company operating system.

The captain should be able to enter an idea, have AGOS review it like a holding company, create a Venture Cell, design a product, split it into GitHub issues, dispatch agents, review pull requests, ship, measure traction, and decide whether to kill, iterate, scale, or spin out the venture.

The core AGOS flow from the manual is:

```text
Signal or Founder idea
-> Opportunity Card
-> Holding Company Board Review
-> Venture Thesis
-> Experiment Charter
-> Venture Cell
-> Venture Board
-> Decision Map
-> UI/UX Design and Final UI Gate
-> Spec
-> GitHub Issues
-> AGOS Operator / FirstMate / Codex
-> Pull Request
-> Review and no-mistakes
-> Merge
-> Metrics
-> Kill / Iterate / Scale / Spin Out
```

This roadmap explains the tools that help us get there.

## The Simple Rule

Do not build a beautiful AGOS interface over an unclear process.

First we prove the process.
Then AGOS becomes the command centre over that process.

## The Main Tools

### AGOS Prime

AGOS Prime is the final product.
It should become the captain's operating system for ideas, companies, ventures, decisions, workers, PRs, metrics, and portfolio reviews.

AGOS will eventually show:

- Idea Inbox.
- Opportunity Cards.
- Holding Company Board sessions.
- Venture Cells.
- Venture Board sessions.
- Decision Maps.
- Specs.
- GitHub Issues.
- Agent runs.
- Pull requests.
- Review state.
- Metrics.
- Kill, iterate, scale, or spin-out decisions.

### Wayfinder

Wayfinder is for big unclear work.
It is the planning tool we use before a Spec when the route is not known yet.

Use Wayfinder for:

- Big product ideas.
- Venture strategy.
- Architecture uncertainty.
- Research questions.
- Prototype questions.
- Decisions too large for one agent session.

Wayfinder output is a decision map.
The decision map breaks the fog into research, prototype, and discussion tickets.

Move on when the path is clear enough to write a Spec.

### To Spec

To Spec turns resolved context into a buildable spec.

Use it after the decision map has cleared the important blockers.
The spec should describe what we are building, why it matters, what is in scope, what is out of scope, and how it will be tested.

In the AGOS manual, this is the Spec step.

### To Tickets

To Tickets turns the Spec into vertical GitHub issues.

Each issue should be small enough for one agent session.
Each issue should be a real slice of value, not a vague layer like "build backend".

Move on when we have agent-ready GitHub issues.

### GitHub Issues

GitHub Issues are the first canonical engineering task IDs.

Use GitHub Issues for:

- Specs.
- Build tickets.
- Research tickets.
- Prototype tickets.
- Review tasks.
- Stowed work.
- Implementation reports.

Do not invent a separate AGOS engineering numbering system.
AGOS can mirror GitHub issue IDs later.

### GitHub Projects

GitHub Projects is the first board.

Use it to see:

- Ready work.
- Blocked work.
- Agent-ready issues.
- In-agent issues.
- PR-open issues.
- Needs-review issues.
- Done work.

Later AGOS can show a better board, but GitHub Projects is the first reliable visible surface.

### FirstMate / AGOS Operator

FirstMate is the execution supervisor we are adapting.
In AGOS language, it becomes AGOS Operator.

It should handle:

- Worker launch.
- Worktree ownership.
- Context packs.
- Model routing.
- Worker reports.
- Validation.
- Teardown safety.
- Captain approval boundaries.

FirstMate is not the product.
It is the operating crew underneath AGOS.

### Codex

Codex is one of the coding agents.

Use Codex for:

- GitHub or cloud task implementation.
- PR review and fixes.
- Local Codex Desktop work on Windows.
- Worker runs through FirstMate when supported.

Codex should not make founder taste or board decisions by itself.

### Code Review

Code Review is the first independent QA pass.

It checks:

- Does the code follow repo standards?
- Does the work match the spec or issue?

The implementer should not review itself.

### No-Mistakes

No-Mistakes is the mandatory PR gate.

Use it after implementation and review.
It should prove the branch is ready for a clean PR, or tell us exactly why it is not.

### Wheelhouse

Wheelhouse is optional.

It is a GitHub maintainer decision inbox.
It is useful when decisions are scattered across multiple repos.

Use Wheelhouse later for:

- Merge this PR.
- Close this issue.
- Approve this CI run.
- Investigate this contributor change.
- Hold this GitHub decision.

Do not make Wheelhouse the main AGOS board.
Do not use Wheelhouse as the main planning system.
Do not make it mandatory until the core AGOS pipeline works.

### Design Tools

The AGOS manual puts design before the real Spec.

Use these tools for design:

- Claude Design for prototype tournaments and final UI references.
- Google Stitch for alternative visual directions.
- Lavish for click-level feedback on HTML artifacts.
- Impeccable for design critique and polish.
- Taste Skill for anti-slop layout, spacing, typography, and density review.

Design output should become:

- Final UI reference.
- `AGOS_DESIGN.md`.
- Visual acceptance criteria in GitHub issues.

## The Order We Should Follow

### Stage 1: Capture The Idea

Start with a signal or founder idea.

AGOS will eventually capture this in an Idea Inbox.
For now, we can capture it in a document or GitHub issue.

Output:

- Raw idea.
- Initial reason it matters.
- Obvious constraints.

### Stage 2: Create An Opportunity Card

Turn the idea into a structured business opportunity.

Output:

- Problem.
- Customer.
- Value.
- Distribution angle.
- Risk.
- Evidence.
- Missing evidence.

This is the first point where AGOS becomes business-first instead of task-first.

### Stage 3: Run Holding Company Board Review

The board reviews the Opportunity Card.

The board should include strategy, product, technology, growth, finance, risk, and red-team views.

Output:

- Board Resolution.
- Decision.
- Rationale.
- Evidence used.
- Evidence missing.
- Follow-up tasks.
- Founder approval needed or not.

No board session without a decision.

### Stage 4: Create Venture Thesis And Experiment Charter

If the board approves the opportunity, create the venture documents.

Output:

- Venture Thesis.
- Experiment Charter.
- Kill criteria.
- Success metric.
- Next review date.

No venture without a metric.

### Stage 5: Use Wayfinder

Use Wayfinder when the venture or product path is still unclear.

Wayfinder creates the decision map.
The map identifies research, prototype, and discussion tickets.

Output:

- Decision map.
- Resolved and unresolved decisions.
- Research tickets.
- Prototype tickets.
- Discussion tickets.

Move on when the route to a V1 Spec is clear.

### Stage 6: Design The Product Flow

For UI/product work, do not jump straight to implementation.

Follow this order:

```text
Business objective
-> User job
-> Golden path
-> Prototype tournament
-> Lavish feedback
-> Selected direction
-> Final UI design pass
-> AGOS_DESIGN.md
-> Data contract
```

Output:

- Final UI reference.
- Design feedback summary.
- `AGOS_DESIGN.md`.
- Data contract.

No UI task without a final UI reference.

### Stage 7: Create The Spec

Use To Spec after the decision map and design direction are clear.

Output:

- Spec.
- Scope.
- Non-goals.
- User stories.
- Acceptance criteria.
- Required checks.
- Required context pack.

No Spec should invent new scope that the decision map did not justify.

### Stage 8: Create GitHub Issues

Use To Tickets to create vertical GitHub issues from the Spec.

Each issue should include:

- Objective.
- Business or user outcome.
- Parent context.
- Acceptance criteria.
- Non-goals.
- Required context pack.
- Required checks.
- Required implementation report.

No coding task without a GitHub issue.

### Stage 9: Put Issues On The Board

Use GitHub Projects first.

Useful states:

- `state:needs-decision`.
- `state:needs-design`.
- `state:agent-ready`.
- `state:in-agent`.
- `state:pr-open`.
- `state:needs-review`.
- `state:blocked`.
- `state:done`.

AGOS can later display this more beautifully.

### Stage 10: Execute With AGOS Operator / FirstMate / Codex

Use FirstMate as the operator layer once issues are agent-ready.

Input:

- GitHub issue.
- Context pack.
- Required checks.
- Repo.
- Branch/worktree.

Output:

- Implementation.
- Commit.
- Worker report.
- Validation evidence.
- PR or blocked report.

No agent run without a context pack.

### Stage 11: Review And No-Mistakes

Run review before merge.

Use:

- Code Review for standards and spec fit.
- No-Mistakes as the required PR gate.

Output:

- Review result.
- No-Mistakes proof.
- PR link.
- Remaining risks.

No PR without implementation report.
No merge without review and memory update.

### Stage 12: Merge, Measure, Decide

After merge, update state and metrics.

The venture should then move to one of:

- Kill.
- Iterate.
- Scale.
- Spin out.

No product build without a metric.

## What We Need Before Building AGOS Features

We can scaffold the AGOS app early.
The manual recommends Next.js, TypeScript, Tailwind, shadcn/ui, Convex, Clerk, and Vercel.

But we should only build real AGOS product features after these are clear:

- The first V1 scope is decided.
- The first decision map is created.
- V1 blockers are resolved.
- Final UI direction is selected.
- `AGOS_DESIGN.md` exists.
- The V1 Spec exists.
- GitHub labels and issue templates exist.
- The first vertical GitHub issues exist.
- No-Mistakes is installed or its replacement path is agreed.
- FirstMate / AGOS Operator has been inspected and the Windows path is known.

After that, we can start building AGOS V1 features in order.

## Recommended V1 Build Order

Start with the smallest useful AGOS loop:

```text
Idea Inbox
-> Opportunity Card
-> Holding Board Review
-> Board Resolution
-> Venture Cell
-> Decision Log
```

Then add:

```text
Decision Map
-> Final UI Reference
-> Spec
-> GitHub Issue drafts
-> GitHub Issue sync
-> Context Pack Builder
-> AGOS Operator brief
-> Worker dispatch
-> PR tracking
-> Review Room
```

This matches the manual's practical sequence.

## What Not To Build First

Do not build every department dashboard first.
Do not build autonomous market ingestion first.
Do not build a custom agent runtime first.
Do not add a vector-memory system first.
Do not build billing first.
Do not make Wheelhouse mandatory first.
Do not build a giant AGOS UI before the V1 workflow is proven.

## Memory And Source Of Truth

Use structured memory first.

Highest authority:

- Founder-approved decisions.
- GitHub code and production data.
- Accepted ADRs and governance docs.
- Convex AGOS database.
- GitHub Issues and PRs.
- Venture Thesis, Experiment Charter, and Spec.
- Implementation reports.
- Board memos and review reports.

Lowest authority:

- Raw chats.
- Agent guesses.

Do not put every memory into every prompt.
Each agent should receive a small context pack with only relevant documents.

## Where Wheelhouse Fits

Wheelhouse becomes useful later if there are enough GitHub decisions to centralize.

For now, keep it optional.

Use it when:

- Multiple repos have PRs waiting for captain decisions.
- Fork CI approvals become noisy.
- Public issues need regular triage.
- We want a single GitHub decision inbox.

Do not use it as the foundation of AGOS strategy or venture planning.

## The Practical Near-Term Stack

Use this first:

```text
Wayfinder
-> To Spec
-> To Tickets
-> GitHub Issues
-> GitHub Projects
-> FirstMate / AGOS Operator
-> Codex / Claude Code workers
-> Code Review
-> No-Mistakes
-> GitHub PR
```

For AGOS app V1, use:

```text
Next.js
-> TypeScript
-> Tailwind
-> shadcn/ui
-> Convex
-> Clerk
-> Vercel
```

Add PostHog, Sentry, and Stripe later when the product is real enough to need them.

## The Simple Mental Model

Wayfinder clears uncertainty.
To Spec writes the contract.
To Tickets makes the work executable.
GitHub tracks the work.
FirstMate runs the workers.
Code Review checks the work.
No-Mistakes gates the PR.
AGOS shows the business, venture, board, execution, and metrics layer above all of it.

AGOS is the operating system.
The other tools are instruments inside it.

