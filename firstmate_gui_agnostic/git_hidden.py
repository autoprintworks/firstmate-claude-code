"""Hidden no-shell Git helper for Windows-safe FirstMate commands."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from firstmate_gui_agnostic.hidden_subprocess import hidden_subprocess_kwargs


class GitHiddenError(RuntimeError):
    """Raised when a safe Git executable cannot be resolved or launched."""


def default_git_executable() -> Path:
    """Resolve native git.exe without accepting `.cmd` or shell wrapper shims."""

    program_files = Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    for relative in (
        ("Git", "mingw64", "bin", "git.exe"),
        ("Git", "bin", "git.exe"),
        ("Git", "cmd", "git.exe"),
    ):
        candidate = program_files.joinpath(*relative)
        if candidate.exists() and not candidate.is_dir():
            return candidate.resolve(strict=False)

    resolved = shutil.which("git")
    if not resolved:
        raise GitHiddenError("git executable was not found")
    candidate = Path(resolved)
    if os.name == "nt" and candidate.suffix.casefold() != ".exe":
        raise GitHiddenError(
            f"unsafe Git launcher rejected; expected git.exe, got: {candidate}"
        )
    return candidate.resolve(strict=False)


def run_git(
    args: list[str],
    *,
    cwd: Path,
    timeout_seconds: int = 120,
    text: bool = False,
    check: bool = False,
    extra_kwargs: dict[str, Any] | None = None,
) -> subprocess.CompletedProcess[Any]:
    """Run Git with direct executable path, hidden window flags, and shell disabled."""

    if not args:
        raise GitHiddenError("missing git arguments")
    kwargs: dict[str, Any] = {
        "capture_output": True,
        "check": check,
        "cwd": cwd,
        "timeout": timeout_seconds,
        "text": text,
    }
    kwargs.update(hidden_subprocess_kwargs())
    if extra_kwargs:
        kwargs.update(extra_kwargs)
    return subprocess.run(
        [str(default_git_executable()), *args],
        **kwargs,
    )


def run_git_text(
    args: list[str],
    *,
    cwd: Path,
    timeout_seconds: int = 120,
) -> str:
    """Run Git and return UTF-8 text, raising with details on failure."""

    completed = run_git(
        args,
        cwd=cwd,
        timeout_seconds=timeout_seconds,
        text=True,
        extra_kwargs={"encoding": "utf-8", "errors": "replace"},
    )
    if completed.returncode != 0:
        details = (completed.stderr or completed.stdout or "").strip()
        raise GitHiddenError(
            f"git command failed ({completed.returncode})"
            + (f": {details}" if details else "")
        )
    return str(completed.stdout).strip()
