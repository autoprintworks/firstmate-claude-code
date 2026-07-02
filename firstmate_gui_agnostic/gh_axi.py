"""Run gh-axi through a Windows-hidden no-shell subprocess contract."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from firstmate_gui_agnostic.hidden_subprocess import hidden_subprocess_kwargs


class GhAxiError(RuntimeError):
    """Raised when the hidden gh-axi bridge cannot run."""


def _default_node() -> Path:
    candidate = (
        Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
        / "nodejs"
        / "node.exe"
    )
    if candidate.exists() and not candidate.is_dir():
        return candidate
    resolved = shutil.which("node")
    if resolved:
        return Path(resolved)
    raise GhAxiError("node executable was not found for gh-axi")


def _default_npx_cli() -> Path:
    candidate = (
        Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
        / "nodejs"
        / "node_modules"
        / "npm"
        / "bin"
        / "npx-cli.js"
    )
    if candidate.exists() and not candidate.is_dir():
        return candidate
    raise GhAxiError(f"npx CLI entrypoint was not found: {candidate}")


def default_gh_axi_command() -> list[str]:
    """Resolve gh-axi without using console-window `.cmd` shims on Windows."""

    if os.name == "nt":
        return [str(_default_node()), str(_default_npx_cli()), "-y", "gh-axi"]

    npx = shutil.which("npx")
    if not npx:
        raise GhAxiError("npx executable was not found for gh-axi")
    return [npx, "-y", "gh-axi"]


def run_gh_axi(
    args: list[str],
    *,
    cwd: Path,
    timeout_seconds: int = 120,
) -> subprocess.CompletedProcess[str]:
    """Run gh-axi with captured output and hidden Windows launch settings."""

    if not args:
        raise GhAxiError("missing gh-axi arguments")
    command = [*default_gh_axi_command(), *args]
    return subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=cwd,
        encoding="utf-8",
        errors="replace",
        text=True,
        timeout=timeout_seconds,
        **hidden_subprocess_kwargs(),
    )


def run_gh_axi_text(
    args: list[str],
    *,
    cwd: Path,
    timeout_seconds: int = 120,
) -> str:
    """Run gh-axi and raise with stderr/stdout details on failure."""

    completed = run_gh_axi(args, cwd=cwd, timeout_seconds=timeout_seconds)
    if completed.returncode != 0:
        details = (completed.stderr or completed.stdout or "").strip()
        raise GhAxiError(
            f"gh-axi command failed ({completed.returncode})"
            + (f": {details}" if details else "")
        )
    return completed.stdout


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run gh-axi through FirstMate's hidden Windows-safe launcher."
    )
    parser.add_argument("--cwd", default=".", help="Working directory for gh-axi.")
    parser.add_argument(
        "--timeout-seconds",
        default=120,
        type=int,
        help="Maximum gh-axi runtime.",
    )
    parser.add_argument(
        "gh_axi_args",
        nargs=argparse.REMAINDER,
        help="Arguments passed to gh-axi. Prefix with -- when needed.",
    )
    parsed = parser.parse_args(argv)

    gh_axi_args = list(parsed.gh_axi_args)
    if gh_axi_args[:1] == ["--"]:
        gh_axi_args = gh_axi_args[1:]

    try:
        completed = run_gh_axi(
            gh_axi_args,
            cwd=Path(parsed.cwd).resolve(strict=False),
            timeout_seconds=parsed.timeout_seconds,
        )
    except GhAxiError as error:
        print(f"gh-axi bridge error: {error}", file=sys.stderr)
        return 1

    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
