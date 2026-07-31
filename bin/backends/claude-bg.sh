#!/usr/bin/env bash
# bin/backends/claude-bg.sh - the headless Claude Code background-agent adapter.
#
# The UNATTENDED counterpart to bin/backends/wezterm.sh. Where the WezTerm
# backend puts each crewmate in a visible OS window and supervises it by
# scraping rendered text, this backend runs crewmates as `claude --bg` processes
# and supervises them from STRUCTURED STATE (`claude agents --json`). It trades
# watchability for reliability: no terminal, no ANSI, no composer heuristics, and
# it survives closing every GUI on the machine.
#
# Backend comparison, so the choice is explicit at config time:
#
#   property            wezterm                   claude-bg
#   -----------------   -----------------------   --------------------------
#   crewmate is         a visible OS window       a headless process
#   human can type in   yes                       no
#   busy detection      pane regex + composer     JSON `state` field
#   survives GUI close  no                        yes
#   permission prompts  answered in the pane      MUST be pre-authorized
#   teardown            kill-pane (exact)         best-effort (see kill below)
#
# Target identity: the session UUID. Unlike WezTerm (where the server ASSIGNS a
# pane id at creation) `claude --session-id <uuid>` lets firstmate CHOOSE the id
# up front, so create is deterministic and a crash between spawn and record
# cannot orphan a crewmate. UUIDs contain no colon, so fm_backend_resolve_selector's
# existing three-form dispatch keeps working untouched.
#
# shellcheck source=bin/fm-composer-lib.sh
. "$FM_BACKEND_LIB_DIR/fm-composer-lib.sh"

FM_CLAUDE_BIN="${FM_CLAUDE_BIN:-claude}"

# Permission mode for unattended crewmates. A background agent has NO UI to
# answer a permission prompt, so a crewmate launched in "manual" blocks forever
# on its first gated tool call and reads to the watcher as a stalled task.
#
# The default matches what firstmate ALREADY grants a claude crewmate on the
# terminal backends: fm-spawn.sh's claude launch template is
# `claude --dangerously-skip-permissions ... "$(cat <brief>)"`. Using a weaker
# mode here would not be safer in any meaningful sense — it would just convert
# the existing autonomy into a hang — so this mirrors the established posture
# rather than inventing a different one. Crewmates are confined to a disposable
# treehouse worktree and land work only behind the captain's merge approval,
# which is where the actual gate lives.
FM_CLAUDE_BG_PERMISSION_MODE="${FM_CLAUDE_BG_PERMISSION_MODE:-bypassPermissions}"

# Delegates to the shared, execution-probed, cached fm_composer_python: on
# Windows `command -v python3` finds a Microsoft Store alias that exists but
# refuses to run. See fm-composer-lib.sh.
fm_backend_claude_bg_python() {
  fm_composer_python
}

# fm_backend_claude_bg_agents_json: the live session inventory, or empty.
fm_backend_claude_bg_agents_json() {
  "$FM_CLAUDE_BIN" agents --json 2>/dev/null || true
}

# fm_backend_claude_bg_record: `key=value` lines for <session-id>'s inventory
# entry, or nothing when the session is gone. One `claude agents` call and one
# interpreter start per lookup, matching fm_wezterm_pane_record's shape.
fm_backend_claude_bg_record() {  # <session-id>
  local want=$1 py
  py=$(fm_backend_claude_bg_python)
  [ -n "$py" ] || return 0
  fm_backend_claude_bg_agents_json | "$py" -c '
import json, sys
want = sys.argv[1]
try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in rows:
    if r.get("sessionId") != want and str(r.get("id")) != want:
        continue
    for key in ("id", "sessionId", "kind", "state", "name", "cwd", "pid", "startedAt"):
        val = r.get(key)
        if val is not None:
            sys.stdout.write("%s=%s\n" % (key, val))
    break
' "$want" 2>/dev/null || true
}

fm_backend_claude_bg_field() {  # <session-id> <key>
  fm_backend_claude_bg_record "$1" | grep "^$2=" | tail -1 | cut -d= -f2- || true
}

# fm_backend_claude_bg_transcript: the on-disk JSONL transcript for <session-id>
# under <cwd>, or empty. Claude Code stores it at
# ~/.claude/projects/<slug>/<session-id>.jsonl where <slug> is the cwd with every
# non-alphanumeric run replaced by "-" (verified: "C:\AGOS\suite" ->
# "C--AGOS-suite").
fm_backend_claude_bg_transcript() {  # <session-id> [cwd]
  local sid=$1 cwd=${2:-} slug base
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  if [ -n "$cwd" ]; then
    slug=$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')
    [ -f "$base/$slug/$sid.jsonl" ] && { printf '%s' "$base/$slug/$sid.jsonl"; return 0; }
  fi
  # cwd unknown or slug mismatch: fall back to a bounded search by session id.
  find "$base" -maxdepth 2 -name "$sid.jsonl" -type f 2>/dev/null | head -1
}

# --- pull primitives ---------------------------------------------------------

# fm_backend_claude_bg_capture: render the last <lines> conversational lines of
# the crewmate's transcript as plain text. This is the analogue of a pane
# capture, and it is what fm-peek.sh and the watcher read.
#
# It renders from the JSONL rather than any terminal buffer, so the output is
# inherently escape-free — the "no raw -e bytes reach firstmate context"
# guarantee the tmux path has to enforce deliberately is free here.
fm_backend_claude_bg_capture() {  # <session-id> <lines>
  local sid=$1 lines=$2 cwd file py
  py=$(fm_backend_claude_bg_python)
  [ -n "$py" ] || return 1
  cwd=$(fm_backend_claude_bg_field "$sid" cwd)
  file=$(fm_backend_claude_bg_transcript "$sid" "$cwd")
  [ -n "$file" ] || { echo "error: no transcript for claude-bg session $sid" >&2; return 1; }
  "$py" -c '
import json, sys
path, limit = sys.argv[1], int(sys.argv[2])
out = []
try:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            msg = rec.get("message") or {}
            role = msg.get("role") or rec.get("type") or ""
            content = msg.get("content")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                parts = []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        parts.append(block.get("text", ""))
                    elif block.get("type") == "tool_use":
                        parts.append("[tool: %s]" % block.get("name", "?"))
                    elif block.get("type") == "tool_result":
                        parts.append("[tool result]")
                text = "\n".join(p for p in parts if p)
            else:
                continue
            if not text.strip():
                continue
            for line in text.splitlines():
                out.append("%s: %s" % (role, line) if role else line)
except OSError:
    sys.exit(1)
sys.stdout.write("\n".join(out[-limit:]))
sys.stdout.write("\n")
' "$file" "$lines"
}

fm_backend_claude_bg_current_path() {  # <session-id>
  fm_backend_claude_bg_field "$1" cwd
}

# fm_backend_claude_bg_busy_state: REAL busy semantics, not `unknown`.
#
# This is the backend's main advantage. tmux and wezterm both return `unknown`
# and force fm-watch.sh into pane-hash + FM_BUSY_REGEX scraping; here the
# supervisor reports state directly, so a crewmate mid-turn is distinguished
# from an idle one without parsing a single rendered byte. Mapping:
#   running / in_progress / active -> busy
#   blocked                        -> blocked  (awaiting input or a permission
#                                               gate; the watcher must escalate,
#                                               NOT wait it out)
#   absent from the inventory      -> exited
fm_backend_claude_bg_busy_state() {  # <session-id>
  local state
  state=$(fm_backend_claude_bg_field "$1" state)
  if [ -z "$state" ]; then
    if [ -n "$(fm_backend_claude_bg_field "$1" sessionId)" ]; then
      printf 'idle'
    else
      printf 'exited'
    fi
    return 0
  fi
  case "$state" in
    running|in_progress|active|busy) printf 'busy' ;;
    blocked)                         printf 'blocked' ;;
    idle|ready|waiting)              printf 'idle' ;;
    *)                               printf 'unknown' ;;
  esac
}

# --- push primitives ---------------------------------------------------------

# fm_backend_claude_bg_send_text_submit: deliver <text> as one new turn to the
# crewmate. There is no composer and no Enter key, so there is nothing to verify
# and nothing to retry — the verdict is `empty` (delivered) or `send-failed`,
# the two outcomes callers already handle. The <retries>/<enter-sleep>/<settle>
# arguments are accepted and ignored to keep the dispatcher signature uniform.
fm_backend_claude_bg_send_text_submit() {  # <session-id> <text> <retries> <enter-sleep> <settle>
  local sid=$1 text=$2
  if printf '%s' "$text" | "$FM_CLAUDE_BIN" --resume "$sid" --bg -p >/dev/null 2>&1; then
    printf 'empty'
  else
    printf 'send-failed'
  fi
}

# fm_backend_claude_bg_send_key: a headless agent has no keyboard. Escape/C-c
# (interrupt) has no supported equivalent for a background session, so this
# fails loudly rather than silently no-op'ing and letting the stuck-crewmate
# playbook believe it interrupted something. Enter is a no-op success because
# submission already happened in send_text_submit.
fm_backend_claude_bg_send_key() {  # <session-id> <key>
  case "$2" in
    Enter) return 0 ;;
    *) echo "error: claude-bg has no key channel; '$2' is unsupported (background sessions cannot be interrupted — see fm_backend_claude_bg_kill)" >&2; return 1 ;;
  esac
}

fm_backend_claude_bg_send_literal() {  # <session-id> <text>
  echo "error: claude-bg has no composer; use send_text_submit to deliver a turn" >&2
  return 1
}

fm_backend_claude_bg_send_text_line() {  # <session-id> <text>
  fm_backend_claude_bg_send_text_submit "$1" "$2" 1 0 0 >/dev/null
}

# --- lifecycle ---------------------------------------------------------------

# fm_backend_claude_bg_container_ensure: nothing to ensure. Background agents
# need no terminal, no multiplexer, and no GUI — which is the point.
fm_backend_claude_bg_container_ensure() {
  printf 'claude-bg'
}

# fm_backend_claude_bg_create_task: launch the crewmate and PRINT its session id.
#
# TWO divergences from the terminal backends that callers must honor:
#
#  1. The worktree must already EXIST. The tmux/wezterm flow creates an empty
#     pane, runs `treehouse get` inside it, then launches the harness. A
#     background agent has no shell to run that in, so fm-spawn.sh must acquire
#     the worktree first and pass the final path as <proj-abs>.
#  2. Creation and the first prompt are ONE call. There is no "spawn, then send
#     the brief" gap, so <brief> is required here rather than sent afterwards.
#
# The session id is chosen by firstmate rather than parsed back, so a crash
# between launch and record cannot orphan a crewmate: the id is already known.
fm_backend_claude_bg_create_task() {  # <container> <session-id> <proj-abs> <brief>
  local sid=$2 proj_abs=$3 brief=$4
  case "$sid" in
    ????????-????-????-????-????????????) ;;
    *) echo "error: claude-bg needs a UUID session id (got '$sid')" >&2; return 1 ;;
  esac
  if [ -n "$(fm_backend_claude_bg_field "$sid" sessionId)" ]; then
    echo "error: claude-bg session $sid already exists" >&2
    return 1
  fi
  [ -d "$proj_abs" ] || { echo "error: claude-bg requires an existing worktree at $proj_abs" >&2; return 1; }
  (
    cd "$proj_abs" || exit 1
    "$FM_CLAUDE_BIN" --bg \
      --session-id "$sid" \
      --permission-mode "$FM_CLAUDE_BG_PERMISSION_MODE" \
      "$brief" >/dev/null 2>&1
  ) || { echo "error: claude --bg failed to launch session $sid in $proj_abs" >&2; return 1; }
  printf '%s' "$sid"
}

# fm_backend_claude_bg_kill: best-effort endpoint removal.
#
# `claude agents` exposes no stop/kill verb, and background entries in its JSON
# carry no pid (only interactive ones do), so this function alone cannot
# guarantee a stop: it signals a pid when one is present and otherwise returns
# success without having stopped anything, exactly as the codex-app adapter's
# kill does.
#
# That is NOT a teardown hole, because it is not the only mechanism. A claude-bg
# crewmate lives inside a leased treehouse worktree, and fm-teardown.sh's
# `treehouse return --force` kills every remaining process in that worktree
# before releasing it — which reaps the agent whether or not a pid was visible
# here. The ordering matters: teardown returns the worktree BEFORE calling
# fm_backend_kill, so by the time this runs the agent is normally already gone.
#
# As on every other backend, the real completion signal is landed git/PR state,
# not endpoint disappearance.
fm_backend_claude_bg_kill() {  # <session-id>
  local pid
  pid=$(fm_backend_claude_bg_field "$1" pid)
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  kill "$pid" 2>/dev/null || true
  return 0
}

# fm_backend_claude_bg_resolve_bare_selector: sessions are addressed by UUID or
# by the name shown in `claude agents`. Mirrors the other adapters' contract of
# failing loudly when nothing matches.
fm_backend_claude_bg_resolve_bare_selector() {  # <name>
  local name=$1 py sid
  if [ -n "$(fm_backend_claude_bg_field "$name" sessionId)" ]; then
    printf '%s' "$name"
    return 0
  fi
  py=$(fm_backend_claude_bg_python)
  [ -n "$py" ] || { echo "error: no python available to resolve claude-bg selector" >&2; return 1; }
  sid=$(fm_backend_claude_bg_agents_json | "$py" -c '
import json, sys
want = sys.argv[1]
try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in rows:
    if r.get("name") == want:
        sys.stdout.write(r.get("sessionId") or "")
        break
' "$name" 2>/dev/null)
  [ -n "$sid" ] || { echo "error: no claude-bg session named $name" >&2; return 1; }
  printf '%s' "$sid"
}
