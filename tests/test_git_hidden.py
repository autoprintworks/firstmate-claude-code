import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from firstmate_gui_agnostic import git_hidden


class GitHiddenTests(unittest.TestCase):
    def test_rejects_git_cmd_on_windows(self) -> None:
        with TemporaryDirectory() as temp_dir:
            git_cmd = Path(temp_dir) / "git.cmd"
            git_cmd.write_text("@echo off\r\nexit /b 0\r\n", encoding="utf-8")

            with (
                patch.object(git_hidden.os, "name", "nt"),
                patch.dict(git_hidden.os.environ, {"ProgramFiles": temp_dir}),
                patch.object(git_hidden.shutil, "which", return_value=str(git_cmd)),
            ):
                with self.assertRaises(git_hidden.GitHiddenError) as raised:
                    git_hidden.default_git_executable()

        self.assertIn("unsafe Git launcher rejected", str(raised.exception))

    def test_prefers_native_program_files_git(self) -> None:
        with TemporaryDirectory() as temp_dir:
            git_exe = Path(temp_dir) / "Git" / "mingw64" / "bin" / "git.exe"
            git_exe.parent.mkdir(parents=True)
            git_exe.write_text("", encoding="utf-8")

            with (
                patch.object(git_hidden.os, "name", "nt"),
                patch.dict(git_hidden.os.environ, {"ProgramFiles": temp_dir}),
                patch.object(git_hidden.shutil, "which", return_value=None),
            ):
                resolved = git_hidden.default_git_executable()

        self.assertEqual(resolved, git_exe.resolve(strict=False))

    def test_run_git_uses_hidden_no_shell_contract(self) -> None:
        completed = subprocess.CompletedProcess(
            args=["git.exe", "status"],
            returncode=0,
            stdout=b"ok",
            stderr=b"",
        )
        cwd = Path(__file__).resolve().parents[1]

        with (
            patch.object(
                git_hidden,
                "default_git_executable",
                return_value=Path("C:/Program Files/Git/mingw64/bin/git.exe"),
            ),
            patch.object(git_hidden.subprocess, "run", return_value=completed) as run,
        ):
            returned = git_hidden.run_git(["status"], cwd=cwd)

        self.assertEqual(returned.returncode, 0)
        kwargs = run.call_args.kwargs
        self.assertFalse(kwargs["shell"])
        self.assertTrue(kwargs["capture_output"])
        if os.name == "nt":
            self.assertTrue(kwargs["creationflags"] & subprocess.CREATE_NO_WINDOW)
            self.assertIsNotNone(kwargs["startupinfo"])


if __name__ == "__main__":
    unittest.main()
