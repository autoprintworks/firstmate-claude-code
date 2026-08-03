#!/usr/bin/env python3
# NOTE (carried from claude-app-backend; NOT YET WIRED): this MSYS fork-cost
# fastpath was hooked into that branch's bin/fm-watch.sh, whose triage policy it
# replicates. The reworked upstream watcher adds semantic busy-state records
# (bin/fm-busy-lib.sh), a wedge-escalation ladder (.wedge-escalations-* markers),
# and an event-wait splice that this script does not model, so wiring it in
# unchanged could absorb wakes the shell policy now treats as actionable. It is
# kept unwired until it is re-ported onto the reworked loop - see issue #4.
from __future__ import annotations

import hashlib
import os
import random
import re
import subprocess
import sys
import time
from pathlib import Path


CAPTAIN_RE_DEFAULT = r"done:|needs-decision:|blocked:|failed:|PR ready|checks green|ready in branch|merged"
BUSY_RE_DEFAULT = r"esc (to )?interrupt|Working\.\.\.|Ctrl\+c:cancel"


def state_dir() -> Path:
    state = os.environ.get("FM_STATE_OVERRIDE") or os.environ.get("STATE")
    if not state:
        raise RuntimeError("FM_STATE_OVERRIDE or STATE is required")
    return Path(state)


def captain_re() -> re.Pattern[str]:
    return re.compile(os.environ.get("FM_CAPTAIN_RE", CAPTAIN_RE_DEFAULT), re.IGNORECASE)


def busy_re() -> re.Pattern[str]:
    return re.compile(os.environ.get("FM_BUSY_REGEX", BUSY_RE_DEFAULT), re.IGNORECASE)


def stale_escalate_secs() -> int:
    raw = os.environ.get("FM_STALE_ESCALATE_SECS", "240")
    try:
        return int(raw)
    except ValueError:
        return 240


def msys_path(path: Path) -> str:
    text = str(path)
    if len(text) >= 2 and text[1] == ":":
        drive = text[0].lower()
        rest = text[2:].replace("\\", "/").lstrip("/")
        return f"/{drive}/{rest}"
    return text.replace("\\", "/")


def sanitize_key(value: str) -> str:
    return value.replace(":", "_").replace("/", "_").replace(".", "_")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def write_text(path: Path, value: str) -> None:
    path.write_text(value, encoding="utf-8")


def remove_path(path: Path) -> None:
    try:
        path.unlink()
    except OSError:
        pass


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


def queue_marker(state: Path) -> Path:
    return state / ".wake-queue"


def queue_dir(state: Path) -> Path:
    return state / ".wake-queue.d"


def append_wake(state: Path, kind: str, key: str, payload: str) -> None:
    qdir = queue_dir(state)
    qdir.mkdir(parents=True, exist_ok=True)
    epoch = int(time.time())
    seq = str(time.time_ns())
    entry = qdir / f"{seq}.{os.getpid()}.{random.randint(0, 99999)}.wake"
    entry.write_text(f"{epoch}\t{seq}\t{kind}\t{key}\t{payload}\n", encoding="utf-8")
    queue_marker(state).write_text("1\n", encoding="utf-8")


def mark_surfaced(state: Path, task: str, status_file: Path, pattern: re.Pattern[str]) -> None:
    last = last_nonblank_line(status_file)
    if is_captain_relevant(last, pattern):
        write_text(state / f".hb-surfaced-{sanitize_key(task)}", last)


def meta_value(meta: Path, key: str) -> str:
    value = ""
    try:
        with meta.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith(f"{key}="):
                    value = line.split("=", 1)[1].rstrip("\r\n")
    except OSError:
        return ""
    return value


def recorded_windows(state: Path) -> list[tuple[str, str, str]]:
    windows: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for meta in sorted(state.glob("*.meta")):
        window = meta_value(meta, "window")
        if not window or window in seen:
            continue
        kind = meta_value(meta, "kind") or "ship"
        backend = meta_value(meta, "backend") or "tmux"
        seen.add(window)
        windows.append((window, kind, backend))
    return windows


def capture_pane(window: str, backend: str) -> str | None:
    if backend != "tmux":
        return None
    try:
        proc = run_msys(["tmux", "capture-pane", "-pe", "-t", window], timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return proc.stdout


def pane_hash(text: str) -> str:
    return hashlib.md5(text.encode("utf-8", errors="replace")).hexdigest()


def pane_is_busy(text: str, pattern: re.Pattern[str]) -> bool:
    lines = [line for line in text.splitlines() if line.strip()]
    tail = "\n".join(lines[-6:])
    return bool(pattern.search(tail))


def main() -> int:
    state = state_dir()
    captain = captain_re()
    busy = busy_re()
    any_absorbed = False
    now = int(time.time())
    for window, kind, backend in recorded_windows(state):
        if kind == "secondmate":
            continue
        tail = capture_pane(window, backend)
        if tail is None:
            continue
        key = sanitize_key(window)
        hash_file = state / f".hash-{key}"
        count_file = state / f".count-{key}"
        stale_file = state / f".stale-{key}"
        stale_since_file = state / f".stale-since-{key}"
        current_hash = pane_hash(tail)
        prev_hash = read_text(hash_file)
        if current_hash != prev_hash:
            write_text(hash_file, current_hash)
            write_text(count_file, "0")
            remove_path(stale_since_file)
            continue

        try:
            count = int(read_text(count_file) or "0")
        except ValueError:
            count = 0
        count += 1
        write_text(count_file, str(count))
        if count < 2 or pane_is_busy(tail, busy):
            remove_path(stale_since_file)
            continue

        task = window.split(":", 1)[-1]
        if task.startswith("fm-"):
            task = task[3:]
        status_file = state / f"{task}.status"
        reason = f"stale: {window}"

        if (state / ".afk").exists():
            if read_text(stale_file) != current_hash:
                append_wake(state, "stale", window, reason)
                write_text(stale_file, current_hash)
                sys.stdout.write(reason)
                return 0
            continue

        if is_captain_relevant(last_nonblank_line(status_file), captain):
            if read_text(stale_file) != current_hash:
                append_wake(state, "stale", window, reason)
                write_text(stale_file, current_hash)
                remove_path(stale_since_file)
                mark_surfaced(state, task, status_file, captain)
                sys.stdout.write(reason)
                return 0
            continue

        if read_text(stale_file) != current_hash:
            if crew_is_provably_working(task):
                write_text(stale_file, current_hash)
                write_text(stale_since_file, str(now))
                any_absorbed = True
                continue
            append_wake(state, "stale", window, reason)
            write_text(stale_file, current_hash)
            remove_path(stale_since_file)
            sys.stdout.write(reason)
            return 0

        raw_since = read_text(stale_since_file)
        if not raw_since.isdigit():
            write_text(stale_since_file, str(now))
            any_absorbed = True
            continue
        age = now - int(raw_since)
        if age >= stale_escalate_secs():
            reason = f"stale: {window} (idle {age}s, possible wedge)"
            append_wake(state, "stale", window, reason)
            remove_path(stale_since_file)
            sys.stdout.write(reason)
            return 0

    return 11 if any_absorbed else 10


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pragma: no cover
        print(f"stale fastpath error: {exc}", file=sys.stderr)
        sys.exit(20)
