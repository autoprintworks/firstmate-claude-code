#!/usr/bin/env python3
from __future__ import annotations

import os
import random
import re
import subprocess
import sys
import time
from pathlib import Path


CAPTAIN_RE_DEFAULT = r"done:|needs-decision:|blocked:|failed:|PR ready|checks green|ready in branch|merged"


def state_dir() -> Path:
    state = os.environ.get("FM_STATE_OVERRIDE") or os.environ.get("STATE")
    if not state:
        raise RuntimeError("FM_STATE_OVERRIDE or STATE is required")
    return Path(state)


def signal_grace() -> float:
    raw = os.environ.get("FM_SIGNAL_GRACE", "30")
    try:
        return float(raw)
    except ValueError:
        return 30.0


def captain_re() -> re.Pattern[str]:
    return re.compile(os.environ.get("FM_CAPTAIN_RE", CAPTAIN_RE_DEFAULT), re.IGNORECASE)


def seen_file_for(state: Path, path: Path) -> Path:
    return state / f".seen-{path.name.replace('.', '_')}"


def hb_surfaced_path(state: Path, task: str) -> Path:
    return state / f".hb-surfaced-{task.replace(':', '_').replace('/', '_').replace('.', '_')}"


def msys_path(path: Path) -> str:
    text = str(path)
    if len(text) >= 2 and text[1] == ":":
        drive = text[0].lower()
        rest = text[2:].replace("\\", "/").lstrip("/")
        return f"/{drive}/{rest}"
    return text.replace("\\", "/")


def last_nonblank_line(path: Path) -> str:
    last = ""
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.rstrip("\r\n")
                if line.strip():
                    last = line
    except OSError:
        return ""
    return last


def is_captain_relevant(line: str, pattern: re.Pattern[str]) -> bool:
    return bool(line and pattern.search(line))


def task_from_signal_path(path: Path) -> str:
    name = path.name
    if name.endswith(".status"):
        return name[:-7]
    if name.endswith(".turn-ended"):
        return name[:-11]
    return ""


def read_seen(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def scan_signals(state: Path) -> list[tuple[Path, str]]:
    pending: list[tuple[Path, str]] = []
    for pattern in ("*.status", "*.turn-ended"):
        for path in sorted(state.glob(pattern)):
            try:
                stat = path.stat()
            except OSError:
                continue
            sig = f"{stat.st_size}:{int(stat.st_mtime)}"
            if sig != read_seen(seen_file_for(state, path)):
                pending.append((path, sig))
    return pending


def dedupe_pending(pending: list[tuple[Path, str]]) -> list[tuple[Path, str]]:
    ordered: list[tuple[Path, str]] = []
    positions: dict[Path, int] = {}
    for path, sig in pending:
        idx = positions.get(path)
        if idx is None:
            positions[path] = len(ordered)
            ordered.append((path, sig))
        else:
            ordered[idx] = (path, sig)
    return ordered


def crew_state_bin() -> Path:
    raw = os.environ.get("FM_CREW_STATE_BIN")
    if raw:
        return Path(raw)
    return Path(__file__).with_name("fm-crew-state.sh")


def git_bash_exe() -> str:
    candidates = (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    )
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    return "bash.exe"


def msys_to_windows(path: str) -> str:
    if len(path) >= 3 and path[0] == "/" and path[2] == "/":
        drive = path[1].upper()
        rest = path[3:].replace("/", "\\")
        return f"{drive}:\\{rest}"
    return path


def resolve_msys_command(name: str) -> str:
    raw_path = os.environ.get("PATH", "")
    for entry in raw_path.split(":"):
        if not entry:
            continue
        candidate_dir = Path(msys_to_windows(entry))
        if not candidate_dir.exists():
            continue
        for suffix in ("", ".exe", ".cmd", ".bat"):
            candidate = candidate_dir / f"{name}{suffix}"
            if candidate.exists():
                return str(candidate)
    return name


def run_msys(args: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    command = resolve_msys_command(args[0])
    if Path(command).suffix.lower() in {".exe", ".cmd", ".bat"}:
        return subprocess.run(
            [command, *args[1:]],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    return subprocess.run(
        [git_bash_exe(), command, *args[1:]],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        check=False,
    )


def crew_is_provably_working(task: str) -> bool:
    if not task:
        return False
    try:
        proc = run_msys([str(crew_state_bin()), task], timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return False
    line = ""
    for candidate in proc.stdout.splitlines():
        if candidate:
            line = candidate
    if not line.startswith("state:"):
        return False
    state = line.split("state:", 1)[1].strip().split(" ", 1)[0]
    if state != "working":
        return False
    if "source:" not in line:
        return False
    source = line.split("source:", 1)[1].strip().split(" ", 1)[0]
    return source in {"run-step", "pane"}


def pending_is_actionable(entries: list[tuple[Path, str]], pattern: re.Pattern[str]) -> bool:
    if (state_dir() / ".afk").exists():
        return True
    tasks: list[str] = []
    for path, _ in entries:
        if path.suffix == ".status":
            if is_captain_relevant(last_nonblank_line(path), pattern):
                return True
        task = task_from_signal_path(path)
        if task and task not in tasks:
            tasks.append(task)
    if not tasks:
        return True
    return not all(crew_is_provably_working(task) for task in tasks)


def write_signal_queue(state: Path, reason: str, entries: list[tuple[Path, str]], pattern: re.Pattern[str]) -> None:
    queue_dir = state / ".wake-queue.d"
    queue_dir.mkdir(parents=True, exist_ok=True)
    queue_marker = state / ".wake-queue"
    epoch = int(time.time())
    pid = os.getpid()
    for path, _ in entries:
        seq = str(time.time_ns())
        entry = queue_dir / f"{seq}.{pid}.{random.randint(0, 99999)}.wake"
        payload = f"{epoch}\t{seq}\tsignal\t{path.name}\t{reason}\n"
        entry.write_text(payload, encoding="utf-8")
    queue_marker.write_text("1\n", encoding="utf-8")
    for path, sig in entries:
        seen_file_for(state, path).write_text(sig, encoding="utf-8")
        if path.suffix == ".status":
            last = last_nonblank_line(path)
            if is_captain_relevant(last, pattern):
                hb_surfaced_path(state, task_from_signal_path(path)).write_text(last, encoding="utf-8")


def absorb_signal(entries: list[tuple[Path, str]]) -> None:
    state = state_dir()
    for path, sig in entries:
        seen_file_for(state, path).write_text(sig, encoding="utf-8")


def main() -> int:
    state = state_dir()
    pattern = captain_re()
    pending = scan_signals(state)
    if not pending:
      return 10
    time.sleep(signal_grace())
    pending = dedupe_pending(pending + scan_signals(state))
    if not pending:
        return 10
    reason = "signal:" + "".join(f" {msys_path(path)}" for path, _ in pending)
    if pending_is_actionable(pending, pattern):
        write_signal_queue(state, reason, pending, pattern)
        sys.stdout.write(reason)
        return 0
    absorb_signal(pending)
    return 11


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pragma: no cover
        print(f"fastpath error: {exc}", file=sys.stderr)
        sys.exit(20)
