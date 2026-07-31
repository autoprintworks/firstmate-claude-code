import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from firstmate_gui_agnostic import gh_axi


class GhAxiHiddenBridgeTests(unittest.TestCase):
    def test_hidden_bridge_uses_no_shell_launch_contract(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["node", "npx-cli.js", "-y", "gh-axi", "issue", "list"],
            returncode=0,
            stdout="ok\n",
            stderr="",
        )
        cwd = Path(__file__).resolve().parents[1]

        with (
            patch.object(
                gh_axi,
                "default_gh_axi_command",
                return_value=["node", "npx-cli.js", "-y", "gh-axi"],
            ),
            patch.object(gh_axi.subprocess, "run", return_value=completed) as run,
        ):
            returned = gh_axi.run_gh_axi(["issue", "list"], cwd=cwd)

        self.assertEqual(returned.stdout, "ok\n")
        kwargs = run.call_args.kwargs
        self.assertFalse(kwargs["shell"])
        self.assertTrue(kwargs["capture_output"])
        self.assertEqual(kwargs["encoding"], "utf-8")
        self.assertEqual(kwargs["errors"], "replace")
        if os.name == "nt":
            self.assertTrue(kwargs["creationflags"] & subprocess.CREATE_NO_WINDOW)
            self.assertIsNotNone(kwargs["startupinfo"])

    def test_windows_bridge_refuses_npx_cmd_fallback(self) -> None:
        with TemporaryDirectory() as temp_dir:
            node = Path(temp_dir) / "nodejs" / "node.exe"
            node.parent.mkdir(parents=True)
            node.write_text("", encoding="utf-8")
            npx_cmd = Path(temp_dir) / "npx.cmd"
            npx_cmd.write_text("@echo off\r\nexit /b 0\r\n", encoding="utf-8")

            def fake_which(command: str) -> str | None:
                if command == "npx":
                    return str(npx_cmd)
                return None

            with (
                patch.object(gh_axi.os, "name", "nt"),
                patch.dict(gh_axi.os.environ, {"ProgramFiles": temp_dir}),
                patch.object(gh_axi.shutil, "which", side_effect=fake_which),
            ):
                with self.assertRaises(gh_axi.GhAxiError) as raised:
                    gh_axi.default_gh_axi_command()

        self.assertIn("npx CLI entrypoint was not found", str(raised.exception))

    def test_cli_preserves_gh_axi_stdout_and_exit_code(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["gh-axi"],
            returncode=7,
            stdout="needs auth\n",
            stderr="gh auth login\n",
        )

        with (
            patch.object(gh_axi, "run_gh_axi", return_value=completed),
            patch.object(gh_axi.sys.stdout, "write") as stdout_write,
            patch.object(gh_axi.sys.stderr, "write") as stderr_write,
        ):
            exit_code = gh_axi.main(["--cwd", ".", "--", "repo", "view"])

        self.assertEqual(exit_code, 7)
        stdout_write.assert_called_once_with("needs auth\n")
        stderr_write.assert_called_once_with("gh auth login\n")


if __name__ == "__main__":
    unittest.main()
