#!/usr/bin/env bash
# bin/backends/wezterm.sh - the WezTerm session-provider adapter.
#
# The visible-crew backend for native Windows. It exports the SAME function set
# bin/backends/tmux.sh does, one-for-one, so every caller (fm-send.sh,
# fm-peek.sh, fm-watch.sh, fm-spawn.sh, fm-teardown.sh) reaches it through
# bin/fm-backend.sh's dispatchers with no call-site change. Sourced only through
# fm_backend_source, never directly.
#
# Why it exists: firstmate's reference backend needs a session provider that can
# CREATE a visible, scriptable endpoint. On Windows there is no tmux, and Claude
# Code Desktop exposes no create-session tool to an agent, so the codex-app
# pattern (host app creates the thread, firstmate records the id) has no Claude
# analogue. `wezterm cli` closes that gap: `spawn` returns a pane id on stdout,
# and `list --format json` reports cursor_y, cwd, and titles — every primitive
# the tmux adapter needs.
#
# Capture/composer/busy primitives live in bin/fm-wezterm-lib.sh, which shares
# bin/fm-composer-lib.sh with the tmux path so the two backends' verdicts cannot
# drift. This file is only the backend-facing naming layer plus the spawn-side
# operations (container ensure, task create, cwd discovery).
#
# ONE contract difference from tmux, and callers must honor it:
# fm_backend_wezterm_create_task PRINTS the new pane id on stdout. A tmux target
# is composed by the caller ("session:window") and is knowable before creation;
# a WezTerm target is ASSIGNED by the server at creation. fm-spawn.sh therefore
# captures create_task's stdout and records THAT in state/<id>.meta's `window=`
# field. Pane ids contain no colon, so fm_backend_resolve_selector's existing
# three-form dispatch keeps working untouched.
#
# shellcheck source=bin/fm-wezterm-lib.sh
. "$FM_BACKEND_LIB_DIR/fm-wezterm-lib.sh"

# fm_backend_wezterm_native_path: convert an MSYS/Git-Bash path to the native
# Windows form wezterm.exe needs. wezterm is a native Windows binary and does
# not understand "/c/AGOS/x"; passing one silently lands the pane in the wrong
# directory. Forward slashes are kept (accepted by Windows and immune to the
# backslash-stripping-through-double-quotes trap documented in
# docs/windows-codex-app-e2e-notes.md). A no-op off Windows.
fm_backend_wezterm_native_path() {  # <path>
  local p=$1
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

# fm_backend_wezterm_pane_by_title: the pane id whose tab title equals <name>,
# or empty. Backs both the bare-selector fallback and create_task's duplicate
# check — the WezTerm analogue of tmux's `list-windows -a | grep ":$name$"`.
fm_backend_wezterm_pane_by_title() {  # <name>
  local py
  py=$(fm_wezterm_python)
  [ -n "$py" ] || return 0
  fm_wezterm_cli list --format json | "$py" -c '
import json, sys
want = sys.argv[1]
try:
    panes = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in panes:
    if p.get("tab_title") == want or p.get("title") == want:
        sys.stdout.write(str(p.get("pane_id")))
        break
' "$1" 2>/dev/null || true
}

# fm_backend_wezterm_resolve_bare_selector: live-inventory fallback for a
# selector that is neither "session:window" nor a "fm-<id>" routed through meta.
# Mirrors fm_backend_tmux_resolve_bare_selector's contract, including failing
# loudly when nothing matches. A bare integer is accepted as a pane id directly.
fm_backend_wezterm_resolve_bare_selector() {  # <name>
  local name=$1 pane
  case "$name" in
    ''|*[!0-9]*) ;;
    *) if fm_wezterm_pane_exists "$name"; then printf '%s' "$name"; return 0; fi ;;
  esac
  pane=$(fm_backend_wezterm_pane_by_title "$name")
  [ -n "$pane" ] || { echo "error: no WezTerm pane titled $name" >&2; return 1; }
  printf '%s' "$pane"
}

# --- pull primitives (fm-peek.sh, fm-watch.sh, fm-crew-state.sh) -------------

fm_backend_wezterm_capture() {  # <target> <lines>
  fm_wezterm_capture "$1" "$2"
}

fm_backend_wezterm_current_path() {  # <target>
  fm_wezterm_pane_field "$1" cwd
}

# fm_backend_wezterm_busy_state: WezTerm exposes no native agent-state (it is a
# terminal, not an agent supervisor), so this reports `unknown` exactly as the
# tmux adapter does. That is the documented cue for fm-watch.sh to fall back to
# its own pane-hash + FM_BUSY_REGEX detection, which works here unchanged
# because fm_wezterm_capture returns the same plain text tmux capture-pane does.
fm_backend_wezterm_busy_state() {  # <target>
  printf 'unknown'
}

# --- push primitives (fm-send.sh, fm-spawn.sh) -------------------------------

fm_backend_wezterm_send_key() {  # <target> <key>
  fm_wezterm_send_key "$1" "$2"
}

fm_backend_wezterm_send_literal() {  # <target> <text>
  fm_wezterm_send_literal "$1" "$2"
}

fm_backend_wezterm_send_text_line() {  # <target> <text>
  fm_wezterm_send_literal "$1" "$2" || return 1
  fm_wezterm_send_key "$1" Enter
}

fm_backend_wezterm_send_text_submit() {  # <target> <text> <retries> <enter-sleep> <settle>
  fm_wezterm_submit_core "$@"
}

# --- lifecycle (fm-spawn.sh, fm-teardown.sh) ---------------------------------

# fm_backend_wezterm_container_ensure: guarantee a WezTerm instance exists to
# spawn into, and print the workspace crewmates land in.
#
# The subtle failure this guards: `wezterm cli` without --no-auto-start will
# happily start a HEADLESS MUX SERVER when no GUI is running, and panes spawned
# into that server are invisible — silently breaking the one property this
# backend exists to provide. So the probe uses --no-auto-start (via
# fm_wezterm_cli) and, on failure, launches a real GUI and waits for it.
fm_backend_wezterm_container_ensure() {
  local waited=0
  if fm_wezterm_cli list >/dev/null 2>&1; then
    printf '%s' "${FM_WEZTERM_WORKSPACE:-default}"
    return 0
  fi
  if [ -n "$FM_WEZTERM_WORKSPACE" ]; then
    ( "$FM_WEZTERM_BIN" start --workspace "$FM_WEZTERM_WORKSPACE" >/dev/null 2>&1 & ) || true
  else
    ( "$FM_WEZTERM_BIN" start >/dev/null 2>&1 & ) || true
  fi
  while [ "$waited" -lt 20 ]; do
    sleep 0.5
    if fm_wezterm_cli list >/dev/null 2>&1; then
      printf '%s' "${FM_WEZTERM_WORKSPACE:-default}"
      return 0
    fi
    waited=$((waited + 1))
  done
  echo "error: no WezTerm GUI instance available after 10s; start WezTerm and retry" >&2
  return 1
}

# fm_backend_wezterm_create_task: create the task's window in <proj-abs> and
# PRINT its pane id (see the contract note in this file's header). Refuses a
# duplicate <window-name>, mirroring the tmux adapter's guard and its intent:
# two crewmates must never share one endpoint.
#
# --new-window makes each crewmate a separate OS window, which is what keeps the
# crew visible at a glance. The tab title is set to the firstmate window name so
# fm_backend_wezterm_pane_by_title can find it and so a human scanning the
# taskbar can tell the crew apart.
fm_backend_wezterm_create_task() {  # <workspace> <window-name> <proj-abs>
  local ws=$1 wname=$2 proj_abs=$3 native pane
  if [ -n "$(fm_backend_wezterm_pane_by_title "$wname")" ]; then
    echo "error: WezTerm pane titled $wname already exists" >&2
    return 1
  fi
  native=$(fm_backend_wezterm_native_path "$proj_abs")
  if [ -n "$ws" ] && [ "$ws" != default ]; then
    pane=$("$FM_WEZTERM_BIN" cli spawn --new-window --workspace "$ws" --cwd "$native" 2>/dev/null)
  else
    pane=$("$FM_WEZTERM_BIN" cli spawn --new-window --cwd "$native" 2>/dev/null)
  fi
  pane=$(printf '%s' "$pane" | tr -d '[:space:]')
  case "$pane" in
    ''|*[!0-9]*) echo "error: wezterm cli spawn did not return a pane id (got '$pane')" >&2; return 1 ;;
  esac
  "$FM_WEZTERM_BIN" cli set-tab-title --pane-id "$pane" "$wname" >/dev/null 2>&1 || true
  printf '%s' "$pane"
}

# fm_backend_wezterm_kill: remove the task's pane, best-effort. Mirrors the tmux
# adapter's `kill-window ... || true`: an already-gone target is not an error,
# because fm-teardown.sh calls this on paths where the crewmate may have exited
# on its own.
fm_backend_wezterm_kill() {  # <target>
  "$FM_WEZTERM_BIN" cli kill-pane --pane-id "$1" >/dev/null 2>&1 || true
}
