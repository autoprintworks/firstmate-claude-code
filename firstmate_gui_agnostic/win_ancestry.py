"""Native Windows process ancestry for MSYS/Git Bash, via Toolhelp32 + ctypes.

Fallback resolver for bin/fm-session-lock-lib.sh on Windows, used only when the
harness does not hand its own pid over through the environment. MSYS keeps a pid
namespace of its own, so `ps -o ppid=` cannot climb out of the shell into the
native process tree; a Toolhelp32 snapshot can.

Usage:
  python win_ancestry.py --start <native-pid> --match-re <regex>
      Print the harness pid owning the session that <native-pid> runs in.
      Exit 1 when no ancestor matches.
  python win_ancestry.py --start <native-pid> --chain
      Print the whole ancestry as "<pid>\\t<image>" lines, for diagnosis.

--match-re is the caller's harness pattern (FM_HARNESS_RE), applied to each
image's stem so "claude.exe" matches "claude". The shell library owns that
pattern; this script never carries a copy of it.
"""
from __future__ import annotations

import argparse
import ctypes
import re
import sys
from ctypes import wintypes
from pathlib import PureWindowsPath

TH32CS_SNAPPROCESS = 0x00000002


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.c_void_p),
        ("th32ModuleID", wintypes.DWORD),
        ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD),
        ("pcPriClassBase", wintypes.LONG),
        ("dwFlags", wintypes.DWORD),
        ("szExeFile", wintypes.WCHAR * 260),
    ]


def snapshot():
    """Map every live pid to (parent pid, image name)."""
    k = ctypes.WinDLL("kernel32", use_last_error=True)
    k.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    k.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    k.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    k.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    k.CloseHandle.argtypes = [wintypes.HANDLE]
    h = k.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if h == wintypes.HANDLE(-1).value:
        raise OSError(ctypes.get_last_error(), "CreateToolhelp32Snapshot failed")
    table = {}
    e = PROCESSENTRY32W()
    e.dwSize = ctypes.sizeof(e)
    try:
        ok = k.Process32FirstW(h, ctypes.byref(e))
        while ok:
            table[int(e.th32ProcessID)] = (int(e.th32ParentProcessID), e.szExeFile)
            ok = k.Process32NextW(h, ctypes.byref(e))
    finally:
        k.CloseHandle(h)
    return table


def chain(start, table, limit=64):
    """The ancestry of <start>, innermost first, stopping at a cycle or the root."""
    pid, seen, out = start, set(), []
    for _ in range(limit):
        if pid <= 1 or pid in seen or pid not in table:
            break
        seen.add(pid)
        ppid, name = table[pid]
        out.append((pid, name))
        pid = ppid
    return out


def harness_pid(links, pattern):
    """The harness pid in an ancestry, or None.

    Mirrors fm_harness_ancestry_pid's rule exactly: the first match wins for
    every harness except Claude, whose bg-spare hook workers nest several
    claude-named processes directly parent-child, with the lock held by the
    outermost pid of that run. So a claude match keeps climbing for a
    still-more-ancestral claude match and stops the instant a non-match follows,
    never crossing that gap to an unrelated claude further up the tree.
    """
    rx = re.compile(pattern)
    best = None
    extending = False
    for pid, name in links:
        stem = PureWindowsPath(name).stem.lower()
        if rx.search(stem):
            best = pid
            if "claude" not in stem:
                break
            extending = True
        elif extending:
            break
    return best


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--start", type=int, required=True)
    p.add_argument("--match-re", dest="match_re", default="")
    p.add_argument("--chain", action="store_true")
    a = p.parse_args(argv)
    links = chain(a.start, snapshot())
    if a.chain:
        for pid, name in links:
            print(f"{pid}\t{name}")
        return 0
    if not a.match_re:
        p.error("--match-re is required unless --chain is given")
    best = harness_pid(links, a.match_re)
    if best is None:
        return 1
    print(best)
    return 0


if __name__ == "__main__":
    sys.exit(main())
