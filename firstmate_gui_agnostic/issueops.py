"""FirstMate IssueOps schema, validation, and dry-run reconciliation."""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


SCHEMA_VERSION = 1
STATE_BLOCK_RE = re.compile(
    r"<!--\s*firstmate-state:\s*(\{.*?\})\s*-->",
    re.DOTALL,
)

PIPELINE_STAGES = {
    "Idea",
    "Research",
    "Prototype",
    "PRD",
    "Kanban Board",
    "Execution",
    "QA",
    "Stow",
    "Product Foundation",
    "AGOS Command Centre",
}

PRIORITIES = {
    "Do now",
    "Do next",
    "Park for later",
}

PRODUCT_OUTCOMES = {
    "Product foundation",
    "Windows runner",
    "Execution ledger",
    "Kanban sync",
    "No-mistakes QA",
    "No-mistakes quality gate",
    "Model routing",
    "Secondmate orchestration",
    "Parallel execution",
    "AGOS Command Centre",
    "Stow",
    "Agent workspace",
    "Work tracking",
    "Planning system",
    "Future scale-ups",
}

WORK_STATES = {
    "Needs clarity",
    "Ready to start",
    "In progress",
    "Blocked",
    "Needs captain decision",
    "Quality review",
    "Ready to merge",
    "Done",
    "Stow candidate",
    "Stowed",
    "Superseded",
    "Closed not planned",
}

DEPENDENCY_STATES = {
    "Unblocked",
    "Blocked",
    "Conditional",
    "Waiting on active work",
    "Needs captain decision",
}

TARGET_MODEL_TIERS = {
    "Strong planning",
    "Cheap bounded execution",
    "Strong review",
    "Deterministic tooling",
    "Mixed",
}

REVIEW_LANES = {
    "None",
    "Human decision",
    "Separate QA",
    "No-mistakes",
    "Ready for review",
}

PARALLELIZATION_CLASSES = {
    "Serial gate",
    "Can run in parallel",
    "Conflict risk",
    "Batch proof",
}

STOW_STATES = {
    "Active",
    "Stow candidate",
    "Stowed",
    "Superseded",
}

ENUM_FIELDS = {
    "pipeline_stage": PIPELINE_STAGES,
    "priority": PRIORITIES,
    "product_outcome": PRODUCT_OUTCOMES,
    "work_state": WORK_STATES,
    "dependency_state": DEPENDENCY_STATES,
    "target_model_tier": TARGET_MODEL_TIERS,
    "review_lane": REVIEW_LANES,
    "parallelization_class": PARALLELIZATION_CLASSES,
    "stow_state": STOW_STATES,
}

REQUIRED_FIELDS = {
    "schema_version",
    "repo",
    "issue_number",
    "pipeline_stage",
    "product_outcome",
    "work_state",
    "priority",
    "dependency_state",
    "target_model_tier",
    "review_lane",
    "parallelization_class",
    "stow_state",
}

OPTIONAL_LIST_FIELDS = {
    "source_issues",
    "replacement_issues",
}

READY_LABELS = {
    "ready-for-agent",
    "ready-for-human",
    "ready-for-review",
    "ready-for-no-mistakes",
    "ready-to-merge",
    "needs-triage",
}

WORK_STATE_LABELS = {
    "Needs clarity": "needs-triage",
    "Ready to start": "ready-for-agent",
    "In progress": "work state:in progress",
    "Blocked": "work state:blocked",
    "Needs captain decision": "ready-for-human",
    "Quality review": "ready-for-review",
    "Ready to merge": "ready-to-merge",
    "Done": "work state:done",
    "Stow candidate": "work state:stow candidate",
    "Stowed": "work state:stowed",
    "Superseded": "work state:superseded",
    "Closed not planned": "work state:closed not planned",
}


class IssueOpsError(RuntimeError):
    """Raised when IssueOps input cannot be parsed or planned safely."""


class MissingStateBlock(IssueOpsError):
    """Raised when an issue body does not contain FirstMate state."""


@dataclass(frozen=True)
class Diagnostic:
    code: str
    message: str
    severity: str = "error"
    field: str | None = None


@dataclass(frozen=True)
class ReconcileAction:
    action: str
    issue_number: int | None
    label: str
    reason: str


@dataclass(frozen=True)
class IssuePlan:
    issue_number: int | None
    title: str
    diagnostics: tuple[Diagnostic, ...]
    actions: tuple[ReconcileAction, ...]


@dataclass(frozen=True)
class UnmanagedIssue:
    issue_number: int | None
    title: str
    reason: str


@dataclass(frozen=True)
class GitHubReconcileResult:
    repo: str
    project_number: int | None
    mode: str
    fetched_count: int
    controlled_plans: tuple[IssuePlan, ...]
    unmanaged_issues: tuple[UnmanagedIssue, ...]
    applied_actions: tuple[ReconcileAction, ...]
    readback_file: str | None
    project_status: str


GhAxiRunner = Callable[[list[str]], str]


def _label_value(text: str) -> str:
    return " ".join(text.casefold().split())


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.casefold()).strip("-")


def render_state_block(state: dict[str, Any]) -> str:
    """Render the hidden FirstMate issue state block."""

    payload = json.dumps(state, indent=2, sort_keys=True)
    return f"<!-- firstmate-state:\n{payload}\n-->"


def replace_state_block(body: str, state: dict[str, Any]) -> str:
    """Replace an existing state block, or append one to a body."""

    block = render_state_block(state)
    if STATE_BLOCK_RE.search(body):
        return STATE_BLOCK_RE.sub(block, body, count=1)
    stripped = body.rstrip()
    if stripped:
        return f"{stripped}\n\n{block}\n"
    return f"{block}\n"


def parse_state_from_body(body: str) -> dict[str, Any]:
    """Parse the hidden FirstMate issue state block from a body."""

    match = STATE_BLOCK_RE.search(body or "")
    if not match:
        raise MissingStateBlock("issue body is missing hidden firstmate-state block")
    try:
        parsed = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        raise IssueOpsError(f"firstmate-state JSON is invalid: {error}") from error
    if not isinstance(parsed, dict):
        raise IssueOpsError("firstmate-state JSON must be an object")
    return parsed


def body_has_state_block(body: str) -> bool:
    """Return whether a body advertises FirstMate controlled state."""

    return bool(STATE_BLOCK_RE.search(body or ""))


def label_names(raw_labels: Any) -> set[str]:
    """Normalize labels from gh-style objects, strings, or lists."""

    if raw_labels is None:
        return set()
    if isinstance(raw_labels, str):
        if "," in raw_labels:
            return {part.strip() for part in raw_labels.split(",") if part.strip()}
        return {raw_labels.strip()} if raw_labels.strip() else set()
    names: set[str] = set()
    if isinstance(raw_labels, list):
        for item in raw_labels:
            if isinstance(item, str) and item.strip():
                names.add(item.strip())
            elif isinstance(item, dict):
                name = item.get("name")
                if isinstance(name, str) and name.strip():
                    names.add(name.strip())
    return names


def issue_number(issue: dict[str, Any]) -> int | None:
    """Read an issue number from common GitHub payload shapes."""

    raw = issue.get("number", issue.get("issue_number"))
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def validate_state(
    state: dict[str, Any],
    *,
    expected_issue_number: int | None = None,
) -> list[Diagnostic]:
    """Validate a parsed FirstMate state object."""

    diagnostics: list[Diagnostic] = []
    for field in sorted(REQUIRED_FIELDS):
        if field not in state:
            diagnostics.append(
                Diagnostic(
                    code="missing-field",
                    field=field,
                    message=f"required field is missing: {field}",
                )
            )

    if state.get("schema_version") != SCHEMA_VERSION:
        diagnostics.append(
            Diagnostic(
                code="invalid-schema-version",
                field="schema_version",
                message=(
                    "schema_version must be "
                    f"{SCHEMA_VERSION}, got {state.get('schema_version')!r}"
                ),
            )
        )

    if "repo" in state and not isinstance(state["repo"], str):
        diagnostics.append(
            Diagnostic(
                code="invalid-type",
                field="repo",
                message="repo must be an owner/name string",
            )
        )

    if "issue_number" in state:
        if not isinstance(state["issue_number"], int):
            diagnostics.append(
                Diagnostic(
                    code="invalid-type",
                    field="issue_number",
                    message="issue_number must be an integer",
                )
            )
        elif (
            expected_issue_number is not None
            and state["issue_number"] != expected_issue_number
        ):
            diagnostics.append(
                Diagnostic(
                    code="issue-number-mismatch",
                    field="issue_number",
                    message=(
                        "issue_number does not match payload number: "
                        f"{state['issue_number']} != {expected_issue_number}"
                    ),
                )
            )

    for field, allowed in ENUM_FIELDS.items():
        if field not in state:
            continue
        value = state[field]
        if not isinstance(value, str):
            diagnostics.append(
                Diagnostic(
                    code="invalid-type",
                    field=field,
                    message=f"{field} must be a string",
                )
            )
        elif value not in allowed:
            allowed_values = ", ".join(sorted(allowed))
            diagnostics.append(
                Diagnostic(
                    code="invalid-enum-value",
                    field=field,
                    message=f"{field} has unsupported value {value!r}: {allowed_values}",
                )
            )

    for field in OPTIONAL_LIST_FIELDS:
        if field in state and not isinstance(state[field], list):
            diagnostics.append(
                Diagnostic(
                    code="invalid-type",
                    field=field,
                    message=f"{field} must be a list when present",
                )
            )

    return diagnostics


def expected_labels_for_state(state: dict[str, Any]) -> set[str]:
    """Project hidden state into canonical GitHub labels."""

    expected: set[str] = set()
    pipeline_stage = state.get("pipeline_stage")
    priority = state.get("priority")
    product_outcome = state.get("product_outcome")
    work_state = state.get("work_state")
    stow_state = state.get("stow_state")

    if isinstance(pipeline_stage, str) and pipeline_stage in PIPELINE_STAGES:
        expected.add(f"pipeline:{_slug(pipeline_stage)}")
    if isinstance(priority, str) and priority in PRIORITIES:
        expected.add(f"priority:{_label_value(priority)}")
    if isinstance(product_outcome, str) and product_outcome in PRODUCT_OUTCOMES:
        expected.add(f"outcome:{_label_value(product_outcome)}")
    if isinstance(work_state, str) and work_state in WORK_STATE_LABELS:
        expected.add(WORK_STATE_LABELS[work_state])
    if (
        isinstance(stow_state, str)
        and stow_state != "Active"
        and stow_state in STOW_STATES
    ):
        expected.add(f"stow:{_slug(stow_state)}")

    return expected


def _label_family(label: str) -> str | None:
    lowered = label.casefold()
    if lowered.startswith("pipeline:"):
        return "pipeline"
    if lowered.startswith("priority:"):
        return "priority"
    if lowered.startswith("outcome:"):
        return "outcome"
    if lowered.startswith("work state:") or lowered in READY_LABELS:
        return "work_state"
    if lowered.startswith("stow:"):
        return "stow"
    return None


def _managed_labels(labels: set[str]) -> dict[str, set[str]]:
    by_family: dict[str, set[str]] = {}
    for label in labels:
        family = _label_family(label)
        if family:
            by_family.setdefault(family, set()).add(label)
    return by_family


def validate_label_projection(
    *,
    labels: set[str],
    expected_labels: set[str],
) -> list[Diagnostic]:
    """Report label conflicts inside managed FirstMate families."""

    diagnostics: list[Diagnostic] = []
    managed = _managed_labels(labels)
    for family, family_labels in sorted(managed.items()):
        wrong = family_labels - expected_labels
        if family == "work_state" and len(family_labels) > 1:
            diagnostics.append(
                Diagnostic(
                    code="conflicting-work-state-labels",
                    field="labels",
                    message=(
                        "issue has multiple work-state labels: "
                        + ", ".join(sorted(family_labels))
                    ),
                    severity="warning",
                )
            )
        elif len(wrong) > 1:
            diagnostics.append(
                Diagnostic(
                    code="conflicting-label-family",
                    field="labels",
                    message=(
                        f"issue has multiple {family} labels: "
                        + ", ".join(sorted(family_labels))
                    ),
                    severity="warning",
                )
            )
    return diagnostics


def validate_issue(issue: dict[str, Any]) -> list[Diagnostic]:
    """Validate an issue payload as a FirstMate-controlled issue."""

    number = issue_number(issue)
    try:
        state = parse_state_from_body(str(issue.get("body") or ""))
    except MissingStateBlock as error:
        return [Diagnostic(code="missing-state", message=str(error), field="body")]
    except IssueOpsError as error:
        return [Diagnostic(code="invalid-state", message=str(error), field="body")]

    diagnostics = validate_state(state, expected_issue_number=number)
    if not any(diagnostic.severity == "error" for diagnostic in diagnostics):
        expected = expected_labels_for_state(state)
        diagnostics.extend(
            validate_label_projection(
                labels=label_names(issue.get("labels")),
                expected_labels=expected,
            )
        )
    return diagnostics


def plan_issue(issue: dict[str, Any]) -> IssuePlan:
    """Return a deterministic dry-run repair plan for one issue."""

    number = issue_number(issue)
    title = str(issue.get("title") or "")
    diagnostics = validate_issue(issue)
    if any(diagnostic.severity == "error" for diagnostic in diagnostics):
        return IssuePlan(
            issue_number=number,
            title=title,
            diagnostics=tuple(diagnostics),
            actions=(),
        )

    state = parse_state_from_body(str(issue.get("body") or ""))
    expected = expected_labels_for_state(state)
    actual = label_names(issue.get("labels"))
    actions: list[ReconcileAction] = []

    for label in sorted(expected - actual):
        actions.append(
            ReconcileAction(
                action="add-label",
                issue_number=number,
                label=label,
                reason="missing projected FirstMate label",
            )
        )

    for label in sorted(actual):
        family = _label_family(label)
        if family and label not in expected:
            actions.append(
                ReconcileAction(
                    action="remove-label",
                    issue_number=number,
                    label=label,
                    reason=f"label conflicts with hidden state family {family}",
                )
            )

    return IssuePlan(
        issue_number=number,
        title=title,
        diagnostics=tuple(diagnostics),
        actions=tuple(actions),
    )


def plan_issues(issues: list[dict[str, Any]]) -> list[IssuePlan]:
    """Plan dry-run repairs for many issues."""

    return [plan_issue(issue) for issue in issues]


def _parse_toon_scalar(raw: str) -> Any:
    raw = raw.strip()
    if raw == "null":
        return None
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        try:
            return json.loads(raw)
        except json.JSONDecodeError as error:
            raise IssueOpsError(f"could not parse quoted GitHub field: {error}") from error
    return raw


def parse_gh_axi_issue_list(output: str) -> list[dict[str, Any]]:
    """Parse the compact gh-axi issue list shape used by reconcile-github."""

    headers: list[str] | None = None
    issues: list[dict[str, Any]] = []
    for line in output.splitlines():
        if line.startswith("issues["):
            match = re.search(r"\{([^}]+)\}", line)
            if not match:
                raise IssueOpsError("GitHub issue list output is missing headers")
            headers = [header.strip() for header in match.group(1).split(",")]
            continue
        if headers is None or not line.startswith("  "):
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("Run `"):
            continue
        try:
            row = next(csv.reader([stripped]))
        except csv.Error:
            continue
        if len(row) != len(headers):
            continue
        issue = dict(zip(headers, row))
        if "number" in issue:
            try:
                issue["number"] = int(str(issue["number"]))
            except ValueError as error:
                raise IssueOpsError(
                    f"GitHub issue list has invalid issue number: {issue['number']}"
                ) from error
        if "labels" in issue:
            issue["labels"] = sorted(label_names(issue["labels"]))
        issues.append(issue)
    if headers is None:
        raise IssueOpsError("GitHub issue list output did not contain an issues block")
    return issues


def parse_gh_axi_issue_view(output: str) -> dict[str, Any]:
    """Parse the gh-axi issue view shape used for full bodies."""

    issue: dict[str, Any] = {}
    for line in output.splitlines():
        match = re.match(r"^  ([A-Za-z_]+):\s*(.*)$", line)
        if not match:
            continue
        key = match.group(1)
        value = _parse_toon_scalar(match.group(2))
        if key == "number":
            try:
                value = int(str(value))
            except ValueError as error:
                raise IssueOpsError(
                    f"GitHub issue view has invalid issue number: {value}"
                ) from error
        issue[key] = value
    if "number" not in issue:
        raise IssueOpsError("GitHub issue view output is missing issue number")
    issue.setdefault("body", "")
    return issue


def _default_gh_axi_runner(
    *,
    cwd: Path,
    timeout_seconds: int,
) -> GhAxiRunner:
    from firstmate_gui_agnostic.gh_axi import GhAxiError, run_gh_axi_text

    def runner(args: list[str]) -> str:
        try:
            return run_gh_axi_text(
                args,
                cwd=cwd,
                timeout_seconds=timeout_seconds,
            )
        except GhAxiError as error:
            details = str(error).replace("gh-axi", "GitHub")
            raise IssueOpsError(details) from error

    return runner


def fetch_github_issues(
    *,
    repo: str,
    limit: int,
    runner: GhAxiRunner,
) -> list[dict[str, Any]]:
    """Fetch open issues with labels and full bodies through gh-axi."""

    summaries = parse_gh_axi_issue_list(
        runner(
            [
                "issue",
                "list",
                f"--repo={repo}",
                "--state",
                "open",
                "--limit",
                str(limit),
                "--fields",
                "labels,url",
            ]
        )
    )
    issues: list[dict[str, Any]] = []
    for summary in summaries:
        number = summary.get("number")
        if not isinstance(number, int):
            continue
        detail = parse_gh_axi_issue_view(
            runner(
                [
                    "issue",
                    "view",
                    str(number),
                    "--full",
                    f"--repo={repo}",
                ]
            )
        )
        detail["labels"] = summary.get("labels", [])
        detail["url"] = summary.get("url")
        if summary.get("title"):
            detail["title"] = summary["title"]
        if summary.get("state"):
            detail["state"] = summary["state"]
        issues.append(detail)
    return issues


def plan_github_issues(
    issues: list[dict[str, Any]],
    *,
    require_controlled: bool = False,
) -> tuple[list[IssuePlan], list[UnmanagedIssue]]:
    """Plan repairs for controlled issues and report unmanaged ones."""

    plans: list[IssuePlan] = []
    unmanaged: list[UnmanagedIssue] = []
    for issue in issues:
        body = str(issue.get("body") or "")
        if not body_has_state_block(body) and not require_controlled:
            unmanaged.append(
                UnmanagedIssue(
                    issue_number=issue_number(issue),
                    title=str(issue.get("title") or ""),
                    reason="missing firstmate-state block",
                )
            )
            continue
        plans.append(plan_issue(issue))
    return plans, unmanaged


def apply_github_actions(
    *,
    repo: str,
    actions: list[ReconcileAction],
    runner: GhAxiRunner,
) -> list[ReconcileAction]:
    """Apply planned label actions through gh-axi issue edit."""

    applied: list[ReconcileAction] = []
    for action in actions:
        if action.issue_number is None:
            continue
        if action.action == "add-label":
            flag = "--add-label"
        elif action.action == "remove-label":
            flag = "--remove-label"
        else:
            raise IssueOpsError(f"unsupported GitHub action: {action.action}")
        runner(
            [
                "issue",
                "edit",
                str(action.issue_number),
                f"--repo={repo}",
                flag,
                action.label,
            ]
        )
        applied.append(action)
    return applied


def _diagnostic_to_dict(diagnostic: Diagnostic) -> dict[str, Any]:
    return {
        "severity": diagnostic.severity,
        "code": diagnostic.code,
        "field": diagnostic.field,
        "message": diagnostic.message,
    }


def _action_to_dict(action: ReconcileAction) -> dict[str, Any]:
    return {
        "action": action.action,
        "issue_number": action.issue_number,
        "label": action.label,
        "reason": action.reason,
    }


def _plan_to_dict(plan: IssuePlan) -> dict[str, Any]:
    return {
        "issue_number": plan.issue_number,
        "title": plan.title,
        "diagnostics": [_diagnostic_to_dict(item) for item in plan.diagnostics],
        "actions": [_action_to_dict(item) for item in plan.actions],
    }


def _unmanaged_to_dict(issue: UnmanagedIssue) -> dict[str, Any]:
    return {
        "issue_number": issue.issue_number,
        "title": issue.title,
        "reason": issue.reason,
    }


def _result_to_dict(result: GitHubReconcileResult) -> dict[str, Any]:
    return {
        "repo": result.repo,
        "project_number": result.project_number,
        "mode": result.mode,
        "fetched_count": result.fetched_count,
        "controlled_plans": [_plan_to_dict(plan) for plan in result.controlled_plans],
        "unmanaged_issues": [
            _unmanaged_to_dict(issue) for issue in result.unmanaged_issues
        ],
        "applied_actions": [
            _action_to_dict(action) for action in result.applied_actions
        ],
        "readback_file": result.readback_file,
        "project_status": result.project_status,
    }


def _default_readback_file(cwd: Path) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    return cwd / "data" / f"issueops-github-readback-{timestamp}.json"


def _write_readback(path: Path, result: GitHubReconcileResult) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(_result_to_dict(result), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def reconcile_github(
    *,
    repo: str,
    project_number: int | None,
    limit: int,
    apply: bool,
    require_controlled: bool,
    cwd: Path,
    timeout_seconds: int = 120,
    readback_file: Path | None = None,
    runner: GhAxiRunner | None = None,
) -> GitHubReconcileResult:
    """Fetch, plan, and optionally apply GitHub issue label reconciliation."""

    if "/" not in repo or repo.startswith("/") or repo.endswith("/"):
        raise IssueOpsError("repo must be in owner/name form")
    active_runner = runner or _default_gh_axi_runner(
        cwd=cwd,
        timeout_seconds=timeout_seconds,
    )
    issues = fetch_github_issues(repo=repo, limit=limit, runner=active_runner)
    plans, unmanaged = plan_github_issues(
        issues,
        require_controlled=require_controlled,
    )
    actionable = [
        action
        for plan in plans
        if not any(item.severity == "error" for item in plan.diagnostics)
        for action in plan.actions
    ]
    applied: list[ReconcileAction] = []
    if apply and actionable:
        applied = apply_github_actions(
            repo=repo,
            actions=actionable,
            runner=active_runner,
        )
    result = GitHubReconcileResult(
        repo=repo,
        project_number=project_number,
        mode="apply" if apply else "dry-run",
        fetched_count=len(issues),
        controlled_plans=tuple(plans),
        unmanaged_issues=tuple(unmanaged),
        applied_actions=tuple(applied),
        readback_file=None,
        project_status=(
            "project-sync-not-implemented" if project_number is not None else "none"
        ),
    )
    if apply or readback_file is not None:
        target = readback_file or _default_readback_file(cwd)
        result = GitHubReconcileResult(
            repo=result.repo,
            project_number=result.project_number,
            mode=result.mode,
            fetched_count=result.fetched_count,
            controlled_plans=result.controlled_plans,
            unmanaged_issues=result.unmanaged_issues,
            applied_actions=result.applied_actions,
            readback_file=str(target),
            project_status=result.project_status,
        )
        _write_readback(target, result)
    return result


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise IssueOpsError(f"could not read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise IssueOpsError(f"{path} is not valid JSON: {error}") from error


def _read_body(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise IssueOpsError(f"could not read {path}: {error}") from error


def _print_error(code: str, message: str, *, hint: str | None = None) -> None:
    print("error:")
    print(f"  code: {code}")
    print(f"  message: {message}")
    if hint:
        print(f"  hint: {hint}")


def _print_diagnostics(diagnostics: list[Diagnostic] | tuple[Diagnostic, ...]) -> None:
    if not diagnostics:
        print("diagnostics: []")
        return
    print(f"diagnostics[{len(diagnostics)}]{{severity,code,field,message}}:")
    for diagnostic in diagnostics:
        field = diagnostic.field or ""
        print(
            "  "
            f"{diagnostic.severity},{diagnostic.code},{field},{diagnostic.message}"
        )


def _print_state(state: dict[str, Any]) -> None:
    print("state:")
    for key in sorted(state):
        value = state[key]
        if isinstance(value, (dict, list)):
            rendered = json.dumps(value, sort_keys=True)
        else:
            rendered = str(value)
        print(f"  {key}: {rendered}")


def _toon_cell(value: Any) -> str:
    text = "" if value is None else str(value).replace("\n", " ")
    if any(character in text for character in (",", '"', ":")):
        return json.dumps(text)
    return text


def _github_error_count(result: GitHubReconcileResult) -> int:
    return sum(
        1
        for plan in result.controlled_plans
        for diagnostic in plan.diagnostics
        if diagnostic.severity == "error"
    )


def _print_github_reconcile_result(result: GitHubReconcileResult) -> None:
    diagnostics = [
        (plan, diagnostic)
        for plan in result.controlled_plans
        for diagnostic in plan.diagnostics
    ]
    actions = [
        action
        for plan in result.controlled_plans
        for action in plan.actions
    ]
    print(f"mode: {result.mode}")
    print(f"repo: {result.repo}")
    if result.project_number is not None:
        print(f"project: {result.project_number}")
    print(f"project_status: {result.project_status}")
    print(f"fetched_issues: {result.fetched_count}")
    print(f"controlled_issues: {len(result.controlled_plans)}")
    print(f"unmanaged_issues: {len(result.unmanaged_issues)}")
    print(f"planned_actions: {len(actions)}")
    print(f"applied_actions: {len(result.applied_actions)}")
    print(f"diagnostics: {len(diagnostics)}")
    print(f"errors: {_github_error_count(result)}")
    if result.readback_file:
        print(f"readback_file: {result.readback_file}")

    if result.controlled_plans:
        print(
            "controlled["
            f"{len(result.controlled_plans)}"
            "]{issue,title,status,actions,diagnostics}:"
        )
        for plan in result.controlled_plans:
            status = "clean"
            if any(item.severity == "error" for item in plan.diagnostics):
                status = "invalid"
            elif plan.actions:
                status = "planned"
            print(
                "  "
                f"{plan.issue_number},"
                f"{_toon_cell(plan.title)},"
                f"{status},"
                f"{len(plan.actions)},"
                f"{len(plan.diagnostics)}"
            )

    if actions:
        print(f"actions[{len(actions)}]{{action,issue,label,reason}}:")
        for action in actions:
            print(
                "  "
                f"{action.action},"
                f"{action.issue_number},"
                f"{_toon_cell(action.label)},"
                f"{_toon_cell(action.reason)}"
            )

    if diagnostics:
        print(f"diagnostics[{len(diagnostics)}]{{severity,issue,code,field,message}}:")
        for plan, diagnostic in diagnostics:
            field = diagnostic.field or ""
            print(
                "  "
                f"{diagnostic.severity},"
                f"{plan.issue_number},"
                f"{diagnostic.code},"
                f"{_toon_cell(field)},"
                f"{_toon_cell(diagnostic.message)}"
            )

    unmanaged_limit = 10
    shown_unmanaged = result.unmanaged_issues[:unmanaged_limit]
    if shown_unmanaged:
        print(
            "unmanaged["
            f"{len(shown_unmanaged)} of {len(result.unmanaged_issues)}"
            "]{issue,title,reason}:"
        )
        for issue in shown_unmanaged:
            print(
                "  "
                f"{issue.issue_number},"
                f"{_toon_cell(issue.title)},"
                f"{_toon_cell(issue.reason)}"
            )
    if len(result.unmanaged_issues) > unmanaged_limit:
        print(
            "help[1]: "
            "Run `fm-issues reconcile-github --require-controlled --dry-run` "
            "to fail on every unmanaged issue"
        )


def _issue_payloads_from_json(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict) and isinstance(payload.get("issues"), list):
        payload = payload["issues"]
    if not isinstance(payload, list):
        raise IssueOpsError("issues file must contain a list or an object with issues")
    issues: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise IssueOpsError(f"issue payload at index {index} is not an object")
        issues.append(item)
    return issues


def _cmd_parse(args: argparse.Namespace) -> int:
    body = _read_body(Path(args.body_file))
    state = parse_state_from_body(body)
    diagnostics = validate_state(state)
    if any(diagnostic.severity == "error" for diagnostic in diagnostics):
        print("status: invalid")
        _print_diagnostics(diagnostics)
        return 1
    print("status: parsed")
    _print_state(state)
    return 0


def _cmd_validate(args: argparse.Namespace) -> int:
    body = _read_body(Path(args.body_file))
    issue = {
        "number": args.issue_number,
        "title": "",
        "body": body,
        "labels": args.label or [],
    }
    diagnostics = validate_issue(issue)
    if diagnostics:
        print("status: invalid")
        _print_diagnostics(diagnostics)
        return 1
    print("status: valid")
    state = parse_state_from_body(body)
    expected_labels = expected_labels_for_state(state)
    print(f"expected_labels[{len(expected_labels)}]:")
    for label in sorted(expected_labels):
        print(f"  {label}")
    return 0


def _cmd_render_state(args: argparse.Namespace) -> int:
    state = _read_json(Path(args.state_file))
    if not isinstance(state, dict):
        raise IssueOpsError("state file must contain a JSON object")
    diagnostics = validate_state(state)
    if any(diagnostic.severity == "error" for diagnostic in diagnostics):
        print("status: invalid")
        _print_diagnostics(diagnostics)
        return 1
    print(render_state_block(state))
    return 0


def _cmd_render_body(args: argparse.Namespace) -> int:
    body = _read_body(Path(args.body_file))
    state = _read_json(Path(args.state_file))
    if not isinstance(state, dict):
        raise IssueOpsError("state file must contain a JSON object")
    diagnostics = validate_state(state)
    if any(diagnostic.severity == "error" for diagnostic in diagnostics):
        print("status: invalid")
        _print_diagnostics(diagnostics)
        return 1
    print(replace_state_block(body, state), end="")
    return 0


def _cmd_reconcile(args: argparse.Namespace) -> int:
    if not args.dry_run:
        raise IssueOpsError(
            "live reconcile is not implemented yet; rerun with --dry-run"
        )
    payload = _read_json(Path(args.issues_file))
    plans = plan_issues(_issue_payloads_from_json(payload))
    action_count = sum(len(plan.actions) for plan in plans)
    diagnostic_count = sum(len(plan.diagnostics) for plan in plans)
    print("mode: dry-run")
    print(f"issues: {len(plans)}")
    print(f"actions: {action_count}")
    print(f"diagnostics: {diagnostic_count}")
    if plans:
        print("plans:")
    for plan in plans:
        number = plan.issue_number if plan.issue_number is not None else ""
        print(f"  - issue: {number}")
        if plan.title:
            print(f"    title: {plan.title}")
        if plan.diagnostics:
            print(f"    diagnostics: {len(plan.diagnostics)}")
            for diagnostic in plan.diagnostics:
                field = diagnostic.field or ""
                print(
                    "      - "
                    f"{diagnostic.severity}:{diagnostic.code}:{field}:"
                    f"{diagnostic.message}"
                )
        if plan.actions:
            print(f"    actions: {len(plan.actions)}")
            for action in plan.actions:
                print(
                    "      - "
                    f"{action.action}: {action.label} "
                    f"({action.reason})"
                )
        if not plan.actions and not plan.diagnostics:
            print("    status: clean")
    return 1 if diagnostic_count else 0


def _cmd_reconcile_github(args: argparse.Namespace) -> int:
    result = reconcile_github(
        repo=args.repo,
        project_number=args.project,
        limit=args.limit,
        apply=args.apply,
        require_controlled=args.require_controlled,
        cwd=Path.cwd(),
        timeout_seconds=args.timeout_seconds,
        readback_file=Path(args.readback_file) if args.readback_file else None,
    )
    _print_github_reconcile_result(result)
    return 1 if _github_error_count(result) else 0


def _cmd_home(_args: argparse.Namespace) -> int:
    print("bin: fm-issues")
    print("description: FirstMate IssueOps schema and dry-run reconciliation.")
    print("commands[6]{name,summary}:")
    print("  parse,Read hidden FirstMate state from an issue body")
    print("  validate,Validate hidden state and labels for one issue")
    print("  render-state,Render a hidden state block from JSON")
    print("  render-body,Refresh or append a hidden state block in a body")
    print("  reconcile,Dry-run repair planning for issue payload JSON")
    print("  reconcile-github,Fetch live GitHub issues and repair controlled labels")
    print("hint: run fm-issues <command> --help")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="FirstMate IssueOps schema and dry-run reconciliation.",
    )
    subparsers = parser.add_subparsers(dest="command")

    parse = subparsers.add_parser("parse", help="Parse hidden state from a body file.")
    parse.add_argument("--body-file", required=True)
    parse.set_defaults(func=_cmd_parse)

    validate = subparsers.add_parser(
        "validate",
        help="Validate hidden state and projected labels for one issue.",
    )
    validate.add_argument("--body-file", required=True)
    validate.add_argument("--issue-number", type=int)
    validate.add_argument("--label", action="append", default=[])
    validate.set_defaults(func=_cmd_validate)

    render_state = subparsers.add_parser(
        "render-state",
        help="Render a hidden state block from a JSON state file.",
    )
    render_state.add_argument("--state-file", required=True)
    render_state.set_defaults(func=_cmd_render_state)

    render_body = subparsers.add_parser(
        "render-body",
        help="Refresh or append hidden state in an issue body.",
    )
    render_body.add_argument("--body-file", required=True)
    render_body.add_argument("--state-file", required=True)
    render_body.set_defaults(func=_cmd_render_body)

    reconcile = subparsers.add_parser(
        "reconcile",
        help="Dry-run repair planning for issue payload JSON.",
    )
    reconcile.add_argument("--issues-file", required=True)
    reconcile.add_argument("--dry-run", action="store_true")
    reconcile.set_defaults(func=_cmd_reconcile)

    reconcile_github_parser = subparsers.add_parser(
        "reconcile-github",
        help="Fetch live GitHub issues and repair controlled labels.",
    )
    reconcile_github_parser.add_argument("--repo", required=True)
    reconcile_github_parser.add_argument("--project", type=int)
    reconcile_github_parser.add_argument("--limit", type=int, default=100)
    mode = reconcile_github_parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    reconcile_github_parser.add_argument(
        "--require-controlled",
        action="store_true",
        help="Treat missing firstmate-state blocks as errors.",
    )
    reconcile_github_parser.add_argument(
        "--readback-file",
        help="Write a bounded JSON readback artifact to this path.",
    )
    reconcile_github_parser.add_argument(
        "--timeout-seconds",
        default=120,
        type=int,
        help="Maximum runtime for each GitHub command.",
    )
    reconcile_github_parser.set_defaults(func=_cmd_reconcile_github)

    parser.set_defaults(func=_cmd_home)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except IssueOpsError as error:
        _print_error(
            "issueops-error",
            str(error),
            hint="Run fm-issues <command> --help for the required non-interactive flags.",
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
