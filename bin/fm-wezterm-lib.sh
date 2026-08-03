#!/usr/bin/env bash
# fm-wezterm-lib.sh — shared WezTerm pane primitives for firstmate.
#
# The WezTerm counterpart of bin/fm-tmux-lib.sh: it owns the wezterm-cli capture
# I/O and delegates EVERY classification decision to bin/fm-composer-lib.sh, so
# the busy/composer verdicts are byte-for-byte the same ones the tmux path uses.
# There is deliberately no second copy of the ghost-stripper or the border logic
# here — that duplication is exactly what incident afk-invx-i5 taught this repo
# to avoid.
#
# Why WezTerm is a first-class backend (not a tmux fallback): on native Windows
# there is no tmux, and Claude Code Desktop exposes no create-session tool, so
# neither the reference backend nor a `claude-app` host-tool backend can spawn a
# VISIBLE crewmate. `wezterm cli` can, and it covers every primitive the tmux
# adapter exports — including the cursor row, which `wezterm cli list --format
# json` reports as `cursor_y` (the one primitive that looked missing until the
# JSON output was checked).
#
# Target identity: a WezTerm pane id (an integer), stored in a task's
# `state/<id>.meta` `window=` field exactly where the tmux adapter stores
# "session:window". Pane ids contain no colon, so fm_backend_resolve_selector's
# existing three-form dispatch keeps working unchanged.
#
# shellcheck source=bin/fm-composer-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/fm-composer-lib.sh"

# The wezterm binary; overridable for tests and non-PATH installs.
FM_WEZTERM_BIN="${FM_WEZTERM_BIN:-wezterm}"

# Workspace for crewmate windows. EMPTY BY DEFAULT, and that is deliberate:
# WezTerm shows one workspace at a time, so spawning crewmates into a dedicated
# workspace would HIDE them behind a workspace switch — the opposite of this
# backend's whole point. Empty means "the active workspace", where each crewmate
# is its own visible OS window. Set FM_WEZTERM_WORKSPACE to opt into isolation.
FM_WEZTERM_WORKSPACE="${FM_WEZTERM_WORKSPACE:-}"

# fm_wezterm_cli: every READ-ONLY wezterm call goes through here with
# --no-auto-start. Without it a read against a machine with no running WezTerm
# silently boots a headless mux server, and panes spawned into that server are
# invisible — a silent violation of the visibility contract. Reads must fail
# loudly instead.
fm_wezterm_cli() {  # <args...>
  "$FM_WEZTERM_BIN" cli --no-auto-start "$@" 2>/dev/null
}

# fm_wezterm_python: the interpreter used to parse `wezterm cli list --format
# json`. Delegates to the shared, execution-probed, cached fm_composer_python —
# see that function for why `command -v python3` is a trap on Windows. Empty when
# no interpreter runs, which every caller treats as an unreadable pane (verdict
# `unknown`) rather than a crash.
fm_wezterm_python() {
  fm_composer_python
}

# fm_wezterm_pane_record: print `key=value` lines for <pane-id>'s entry in the
# live pane inventory, or nothing when the pane is gone / unreadable. ONE
# wezterm call and ONE interpreter start per lookup, so a caller that needs
# several fields (cursor_y and cwd, say) pays for one round trip rather than
# several — the watcher polls this on every tick.
#
# `cwd` is normalized here from WezTerm's file:// URL to a plain path, because
# every firstmate consumer of it (worktree discovery in fm-spawn.sh, the tangle
# guard) expects the same shape tmux's #{pane_current_path} produces.
fm_wezterm_pane_record() {  # <pane-id>
  local pane=$1 py
  py=$(fm_wezterm_python)
  [ -n "$py" ] || return 0
  fm_wezterm_cli list --format json | "$py" -c '
import json, sys
from urllib.parse import unquote, urlparse

want = sys.argv[1]
try:
    panes = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in panes:
    if str(p.get("pane_id")) != want:
        continue
    for key in ("pane_id", "window_id", "tab_id", "workspace", "title",
                "tab_title", "cursor_y", "cursor_x", "is_active"):
        val = p.get(key)
        if val is not None:
            sys.stdout.write("%s=%s\n" % (key, val))
    cwd = p.get("cwd")
    if cwd:
        parsed = urlparse(cwd)
        path = unquote(parsed.path or "")
        # file:///C:/x -> C:/x ; file:///home/x -> /home/x
        if len(path) > 2 and path[0] == "/" and path[2] == ":":
            path = path[1:]
        sys.stdout.write("cwd=%s\n" % path.rstrip("/"))
    break
' "$pane" 2>/dev/null || true
}

# fm_wezterm_pane_field: one field from fm_wezterm_pane_record, or empty.
fm_wezterm_pane_field() {  # <pane-id> <key>
  fm_wezterm_pane_record "$1" | grep "^$2=" | tail -1 | cut -d= -f2- || true
}

# fm_wezterm_pane_exists: 0 iff <pane-id> is live in the inventory.
fm_wezterm_pane_exists() {  # <pane-id>
  [ -n "$(fm_wezterm_pane_field "$1" pane_id)" ]
}

# fm_wezterm_capture: bounded plain-text pane capture. The tmux analogue is
# `capture-pane -p -t T -S -N`; WezTerm uses the same line-numbering convention
# (0 = first row of the screen, negative = backwards into scrollback), so
# `--start-line -N` means the same "N lines back" the tmux adapter means.
fm_wezterm_capture() {  # <pane-id> <lines>
  fm_wezterm_cli get-text --pane-id "$1" --start-line "-$2"
}

# fm_wezterm_composer_state: the WezTerm twin of fm_tmux_composer_state, with
# identical verdicts (empty|pending|unknown) because the classification is the
# shared fm_composer_classify_line.
#
# cursor_y comes from the JSON inventory rather than a dedicated query (WezTerm
# has no `display-message -p` equivalent), and the single composer row is then
# captured WITH styling via `get-text --escapes` — the counterpart of
# `capture-pane -e`. As on the tmux path the styled capture is internal only and
# is never surfaced to a human or an LLM.
fm_wezterm_composer_state() {  # <pane-id> -> empty|pending|unknown
  local pane=$1 cy raw line
  cy=$(fm_wezterm_pane_field "$pane" cursor_y)
  case "$cy" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  raw=$(fm_wezterm_cli get-text --pane-id "$pane" --escapes \
          --start-line "$cy" --end-line "$cy") || { printf 'unknown'; return 0; }
  line=$(printf '%s\n' "$raw" | head -1 | fm_composer_strip_ghost)
  fm_composer_classify_line "$line"
}

# fm_wezterm_input_pending: 0 iff the composer holds real unsubmitted text.
# Same fail-safe bias as fm_pane_input_pending: unreadable is NOT pending.
fm_wezterm_input_pending() {  # <pane-id>
  [ "$(fm_wezterm_composer_state "$1")" = pending ]
}

# fm_wezterm_is_busy: 0 iff the pane's recent tail shows a busy footer.
fm_wezterm_is_busy() {  # <pane-id>
  local tail40
  tail40=$(fm_wezterm_capture "$1" 40) || return 1
  printf '%s' "$tail40" | fm_composer_tail_is_busy
}

# fm_wezterm_send_literal: send TEXT as literal bytes with no submission.
# --no-paste mirrors `tmux send-keys -l`: the harness sees keystrokes, not a
# bracketed paste. Text arrives on stdin so no quoting/length limit of the
# command line can truncate a brief.
fm_wezterm_send_literal() {  # <pane-id> <text>
  printf '%s' "$2" | "$FM_WEZTERM_BIN" cli send-text --pane-id "$1" --no-paste 2>/dev/null
}

# fm_wezterm_send_key: one named key, as the control byte the terminal expects.
# Covers the set fm-send.sh and the stuck-crewmate playbook actually use.
fm_wezterm_send_key() {  # <pane-id> <key>
  local pane=$1 key=$2 bytes
  case "$key" in
    Enter)  bytes=$'\r' ;;
    Escape) bytes=$'\033' ;;
    C-c)    bytes=$'\003' ;;
    C-d)    bytes=$'\004' ;;
    C-u)    bytes=$'\025' ;;
    Tab)    bytes=$'\t' ;;
    *) echo "error: unsupported WezTerm key '$key'" >&2; return 1 ;;
  esac
  printf '%s' "$bytes" | "$FM_WEZTERM_BIN" cli send-text --pane-id "$pane" --no-paste 2>/dev/null
}

# fm_wezterm_submit_enter_core / fm_wezterm_submit_core: the verify-and-retry
# submit, structurally identical to fm_tmux_submit_core and echoing the same
# verdicts (empty|pending|unknown|send-failed). Enter is retried; the text is
# NEVER retyped, because a swallowed Enter leaves our text in the composer and
# retyping would duplicate it.
fm_wezterm_submit_enter_core() {  # <pane-id> <retries> <enter-sleep>
  local pane=$1 retries=$2 sleep_s=$3 i=0 state
  while :; do
    fm_wezterm_send_key "$pane" Enter || true
    sleep "$sleep_s"
    state=$(fm_wezterm_composer_state "$pane")
    [ "$state" = pending ] || { printf '%s' "$state"; return 0; }
    i=$((i + 1))
    [ "$i" -lt "$retries" ] || { printf 'pending'; return 0; }
  done
}

fm_wezterm_submit_core() {  # <pane-id> <text> <retries> <enter-sleep> <settle>
  local pane=$1 text=$2 retries=$3 sleep_s=$4 settle=$5
  fm_wezterm_send_literal "$pane" "$text" || { printf 'send-failed'; return 0; }
  sleep "$settle"
  fm_wezterm_submit_enter_core "$pane" "$retries" "$sleep_s"
}
