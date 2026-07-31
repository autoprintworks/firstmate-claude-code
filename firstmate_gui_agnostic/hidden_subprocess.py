"""Shared hidden subprocess settings for Windows helper commands."""

from __future__ import annotations

import os
import subprocess
from typing import Any


WINDOWS_CREATE_NO_WINDOW = int(
    getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)
)
WINDOWS_BELOW_NORMAL_PRIORITY_CLASS = int(
    getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0x00004000)
)


def hidden_creationflags() -> int:
    """Return creation flags that avoid visible console windows on Windows."""

    if os.name != "nt":
        return 0
    return WINDOWS_CREATE_NO_WINDOW | WINDOWS_BELOW_NORMAL_PRIORITY_CLASS


def hidden_startupinfo() -> subprocess.STARTUPINFO | None:
    """Return startup info that asks Windows to hide the child window."""

    if os.name != "nt":
        return None
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= int(getattr(subprocess, "STARTF_USESHOWWINDOW", 0))
    startupinfo.wShowWindow = int(getattr(subprocess, "SW_HIDE", 0))
    return startupinfo


def hidden_subprocess_kwargs() -> dict[str, Any]:
    """Return subprocess kwargs for no-shell hidden helper launches."""

    kwargs: dict[str, Any] = {"shell": False}
    if os.name == "nt":
        kwargs["creationflags"] = hidden_creationflags()
        kwargs["startupinfo"] = hidden_startupinfo()
    return kwargs
