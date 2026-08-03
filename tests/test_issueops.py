import contextlib
import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from firstmate_gui_agnostic import issueops


SAMPLE_STATE = {
    "schema_version": 1,
    "repo": "autoprintworks/firstmate-gui-agnostic",
    "issue_number": 120,
    "pipeline_stage": "Kanban Board",
    "product_outcome": "Planning system",
    "work_state": "Ready to start",
    "priority": "Do now",
    "dependency_state": "Unblocked",
    "target_model_tier": "Strong planning",
    "review_lane": "Human decision",
    "parallelization_class": "Serial gate",
    "stow_state": "Active",
    "source_issues": [116],
    "replacement_issues": [],
    "last_reconciled_at": "2026-07-03T12:00:00Z",
    "project_number": 3,
    "project_item_id": "PVTI_example",
    "execution_task_id": None,
    "current_pr": None,
    "state_revision": "example",
}


def sample_body(state: dict | None = None) -> str:
    return "## Purpose\n\nBuild the system.\n\n" + issueops.render_state_block(
        state or SAMPLE_STATE
    )


def issue_list_output(labels: str = "ready-for-agent") -> str:
    return "\n".join(
        [
            "count: 2",
            "issues[2]{number,title,state,author,created,labels,url}:",
            (
                "  120,IssueOps,open,autoprintworks,1m ago,"
                f'"{labels}",'
                '"https://github.com/autoprintworks/firstmate-gui-agnostic/issues/120"'
            ),
            (
                "  119,Loose card,open,autoprintworks,2m ago,"
                '"ready-for-human",'
                '"https://github.com/autoprintworks/firstmate-gui-agnostic/issues/119"'
            ),
        ]
    )


def issue_view_output(number: int, title: str, body: str) -> str:
    return "\n".join(
        [
            "issue:",
            f"  number: {number}",
            f"  title: {title}",
            "  state: open",
            "  author: autoprintworks",
            "  created: 1m ago",
            f"  body: {json.dumps(body)}",
        ]
    )


class FakeGhAxiRunner:
    def __init__(self, *, labels: str = "ready-for-agent") -> None:
        self.labels = labels
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str]) -> str:
        self.calls.append(args)
        if args[:2] == ["issue", "list"]:
            return issue_list_output(labels=self.labels)
        if args[:2] == ["issue", "view"] and args[2] == "120":
            return issue_view_output(120, "IssueOps", sample_body())
        if args[:2] == ["issue", "view"] and args[2] == "119":
            return issue_view_output(119, "Loose card", "## Purpose\n\nNo state.\n")
        if args[:2] == ["issue", "edit"]:
            return "issue:\n  number: 120\n"
        raise AssertionError(f"unexpected fake gh-axi call: {args}")


class IssueOpsTests(unittest.TestCase):
    def test_parses_hidden_firstmate_state_block(self) -> None:
        parsed = issueops.parse_state_from_body(sample_body())

        self.assertEqual(parsed["schema_version"], 1)
        self.assertEqual(parsed["issue_number"], 120)
        self.assertEqual(parsed["pipeline_stage"], "Kanban Board")

    def test_replace_state_block_preserves_human_body(self) -> None:
        updated = dict(SAMPLE_STATE, work_state="Blocked")
        rendered = issueops.replace_state_block(sample_body(), updated)

        self.assertIn("## Purpose", rendered)
        self.assertEqual(
            issueops.parse_state_from_body(rendered)["work_state"],
            "Blocked",
        )
        self.assertEqual(rendered.count("firstmate-state"), 1)

    def test_validate_issue_reports_missing_state(self) -> None:
        diagnostics = issueops.validate_issue(
            {
                "number": 120,
                "title": "Missing state",
                "body": "## Purpose\n\nLoose text only.\n",
                "labels": [],
            }
        )

        self.assertEqual(len(diagnostics), 1)
        self.assertEqual(diagnostics[0].code, "missing-state")

    def test_expected_labels_follow_existing_board_contract(self) -> None:
        labels = issueops.expected_labels_for_state(SAMPLE_STATE)

        self.assertIn("pipeline:kanban-board", labels)
        self.assertIn("priority:do now", labels)
        self.assertIn("outcome:planning system", labels)
        self.assertIn("ready-for-agent", labels)

    def test_plan_adds_missing_projected_labels(self) -> None:
        plan = issueops.plan_issue(
            {
                "number": 120,
                "title": "IssueOps",
                "body": sample_body(),
                "labels": [],
            }
        )

        actions = {(action.action, action.label) for action in plan.actions}
        self.assertIn(("add-label", "pipeline:kanban-board"), actions)
        self.assertIn(("add-label", "priority:do now"), actions)
        self.assertIn(("add-label", "outcome:planning system"), actions)
        self.assertIn(("add-label", "ready-for-agent"), actions)

    def test_plan_removes_conflicting_work_state_label(self) -> None:
        plan = issueops.plan_issue(
            {
                "number": 120,
                "title": "IssueOps",
                "body": sample_body(),
                "labels": [
                    "ready-for-agent",
                    "work state:blocked",
                    "pipeline:kanban-board",
                    "priority:do now",
                    "outcome:planning system",
                ],
            }
        )

        actions = {(action.action, action.label) for action in plan.actions}
        diagnostics = {diagnostic.code for diagnostic in plan.diagnostics}
        self.assertIn("conflicting-work-state-labels", diagnostics)
        self.assertIn(("remove-label", "work state:blocked"), actions)
        self.assertNotIn(("remove-label", "ready-for-agent"), actions)

    def test_reconcile_cli_requires_dry_run_for_now(self) -> None:
        with TemporaryDirectory() as temp_dir:
            issues_path = Path(temp_dir) / "issues.json"
            issues_path.write_text("[]", encoding="utf-8")
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                exit_code = issueops.main(
                    ["reconcile", "--issues-file", str(issues_path)]
                )

        self.assertEqual(exit_code, 1)
        self.assertIn("live reconcile is not implemented yet", output.getvalue())

    def test_reconcile_cli_prints_dry_run_actions(self) -> None:
        with TemporaryDirectory() as temp_dir:
            issues_path = Path(temp_dir) / "issues.json"
            issues_path.write_text(
                json.dumps(
                    [
                        {
                            "number": 120,
                            "title": "IssueOps",
                            "body": sample_body(),
                            "labels": ["priority:do now"],
                        }
                    ]
                ),
                encoding="utf-8",
            )
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                exit_code = issueops.main(
                    ["reconcile", "--issues-file", str(issues_path), "--dry-run"]
                )

        self.assertEqual(exit_code, 0)
        self.assertIn("mode: dry-run", output.getvalue())
        self.assertIn("add-label: ready-for-agent", output.getvalue())

    def test_parses_gh_axi_issue_list_with_labels(self) -> None:
        issues = issueops.parse_gh_axi_issue_list(
            issue_list_output(labels="ready-for-agent,priority:do now")
        )

        self.assertEqual(len(issues), 2)
        self.assertEqual(issues[0]["number"], 120)
        self.assertEqual(
            issues[0]["labels"],
            ["priority:do now", "ready-for-agent"],
        )

    def test_parses_gh_axi_issue_view_full_body(self) -> None:
        parsed = issueops.parse_gh_axi_issue_view(
            issue_view_output(120, "IssueOps", sample_body())
        )

        self.assertEqual(parsed["number"], 120)
        self.assertEqual(parsed["title"], "IssueOps")
        self.assertEqual(
            issueops.parse_state_from_body(parsed["body"])["issue_number"],
            120,
        )

    def test_reconcile_github_dry_run_skips_unmanaged_by_default(self) -> None:
        runner = FakeGhAxiRunner()
        result = issueops.reconcile_github(
            repo="autoprintworks/firstmate-gui-agnostic",
            project_number=3,
            limit=100,
            apply=False,
            require_controlled=False,
            cwd=Path.cwd(),
            runner=runner,
        )

        self.assertEqual(result.fetched_count, 2)
        self.assertEqual(len(result.controlled_plans), 1)
        self.assertEqual(len(result.unmanaged_issues), 1)
        self.assertEqual(result.project_status, "project-sync-not-implemented")
        actions = {
            (action.action, action.label)
            for plan in result.controlled_plans
            for action in plan.actions
        }
        self.assertIn(("add-label", "priority:do now"), actions)
        self.assertIn(("add-label", "outcome:planning system"), actions)
        self.assertIn(("add-label", "pipeline:kanban-board"), actions)

    def test_reconcile_github_apply_runs_label_edits_and_writes_readback(self) -> None:
        with TemporaryDirectory() as temp_dir:
            readback_file = Path(temp_dir) / "readback.json"
            runner = FakeGhAxiRunner()
            result = issueops.reconcile_github(
                repo="autoprintworks/firstmate-gui-agnostic",
                project_number=None,
                limit=100,
                apply=True,
                require_controlled=False,
                cwd=Path.cwd(),
                readback_file=readback_file,
                runner=runner,
            )

            edit_calls = [call for call in runner.calls if call[:2] == ["issue", "edit"]]

            self.assertEqual(len(result.applied_actions), 3)
            self.assertEqual(len(edit_calls), 3)
            self.assertTrue(readback_file.exists())
            readback = json.loads(readback_file.read_text(encoding="utf-8"))
            self.assertEqual(readback["mode"], "apply")
            self.assertEqual(readback["applied_actions"][0]["issue_number"], 120)

    def test_reconcile_github_require_controlled_reports_missing_state(self) -> None:
        runner = FakeGhAxiRunner()
        result = issueops.reconcile_github(
            repo="autoprintworks/firstmate-gui-agnostic",
            project_number=None,
            limit=100,
            apply=False,
            require_controlled=True,
            cwd=Path.cwd(),
            runner=runner,
        )

        self.assertEqual(len(result.unmanaged_issues), 0)
        missing = [
            diagnostic.code
            for plan in result.controlled_plans
            for diagnostic in plan.diagnostics
        ]
        self.assertIn("missing-state", missing)


if __name__ == "__main__":
    unittest.main()
