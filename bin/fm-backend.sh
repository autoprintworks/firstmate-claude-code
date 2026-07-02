#!/usr/bin/env bash
# fm-backend.sh - runtime-backend selection, meta helpers, selector resolution,
# and dispatch for firstmate's session-provider abstraction.
#
# Design: data/fm-backend-design-d7/report.md ("Backend Interface") and
# data/fm-backend-design-d7/herdr-addendum.md ("Events as the core
# abstraction"). P1 extracted the tmux command sequences that fm-send.sh,
# fm-peek.sh, fm-watch.sh, fm-spawn.sh, and fm-teardown.sh already ran inline
# into bin/backends/tmux.sh, with those SAME command sequences, so the default
# (tmux) path stays byte-identical. P2 adds bin/backends/herdr.sh, an
# EXPERIMENTAL backend behind `--backend herdr`/`FM_BACKEND=herdr`/
# `config/backend`, and behind runtime auto-detection when firstmate itself is
# running inside herdr with no explicit backend setting; see herdr-addendum.md and
# data/fm-backend-design-d7/herdr-verification-p2.md for its empirical basis.
#
# Compatibility contract: a task's meta may omit `backend=`; every reader here
# treats that as `tmux` (fm_backend_of_meta), and fm-spawn.sh does not write
# `backend=tmux` for a default-backend task, so existing and newly spawned
# default-path metas stay byte-identical. Only a task spawned on a non-tmux
# backend, currently experimental herdr, carries an explicit `backend=` line.
#
# Event-source framing (herdr-addendum "Events as the core abstraction"): a
# backend's supervision surface is conceptually an EVENT SOURCE - it produces
# task events (status-changed, went-stale, exited) that map onto firstmate's
# existing signal/stale/check/heartbeat wake vocabulary. The tmux adapter has
# no native event push, so fm-watch.sh's poll loop over the pull primitives
# below (capture, list-live, busy-state via regex) IS the default event-source
# implementation that synthesizes those events; P1 only names that seam, it
# does not change the loop's behavior. The pull primitives also stay available
# on their own for on-demand reads (fm-peek.sh, fm-crew-state.sh).

FM_BACKEND_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_BACKEND_DEFAULT_ROOT="$(cd "$FM_BACKEND_LIB_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$FM_BACKEND_DEFAULT_ROOT}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
FM_BACKEND_CONFIG_DIR="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
FM_BACKEND_STATE_DIR="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# Verified backend adapters. Extend only after a backend gets its own
# bin/backends/<name>.sh and empirical verification, mirroring AGENTS.md
# section 4's harness-verification discipline. herdr is EXPERIMENTAL (P2;
# data/fm-backend-design-d7/herdr-addendum.md) - verified against the real
# v0.7.1/protocol-14 binary (data/fm-backend-design-d7/herdr-verification-p2.md)
# but newer than tmux's long-proven default path.
FM_BACKEND_KNOWN="tmux herdr codex-app"

# fm_backend_is_known: 0 iff <name> has a verified adapter.
fm_backend_is_known() {  # <name>
  local name=$1 known
  for known in $FM_BACKEND_KNOWN; do
    [ "$name" = "$known" ] && return 0
  done
  return 1
}

# fm_backend_detect: detect the runtime firstmate itself is CURRENTLY executing
# inside, from verified environment markers (mirrors bin/fm-harness.sh's
# env-marker detection layer for harnesses). Prints the detected backend name
# and returns 0, or returns 1 when nothing is detected. Nesting resolves
# INNERMOST-first: tmux sets $TMUX in every process running inside it, even a
# tmux started inside a herdr pane, so $TMUX is checked first and wins over
# HERDR_ENV=1 in that nested case. herdr injects HERDR_ENV=1 (plus
# HERDR_SOCKET_PATH/HERDR_PANE_ID) into every process it manages a pane for;
# HERDR_ENV=1 alone (no $TMUX) selects herdr. Both markers empirically verified
# on the reference dev machine.
fm_backend_detect() {
  if [ -n "${TMUX:-}" ]; then
    printf 'tmux'
    return 0
  fi
  if [ "${HERDR_ENV:-}" = "1" ]; then
    printf 'herdr'
    return 0
  fi
  return 1
}

# fm_backend_name: resolve the ACTIVE backend for a NEW spawn, absent an
# explicit per-task override. Precedence: FM_BACKEND env, then config/backend
# (a single word on its first non-empty line, mirroring config/crew-harness),
# then runtime auto-detection (fm_backend_detect), then default tmux. A
# per-task `--backend` flag is parsed by the caller (fm-spawn.sh) and takes
# precedence over this resolution entirely; it is not read here. Auto-detect
# fires only when nothing was explicitly configured, so an explicit setting
# always wins. Selecting herdr via auto-detect prints one loud stderr notice
# (it is experimental); auto-detecting tmux stays silent - it is today's
# default-path behavior and callers must see zero change.
fm_backend_name() {
  local line v detected
  if [ -n "${FM_BACKEND:-}" ]; then
    printf '%s' "$FM_BACKEND"
    return 0
  fi
  if [ -f "$FM_BACKEND_CONFIG_DIR/backend" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      v=$(printf '%s' "$line" | tr -d '[:space:]')
      if [ -n "$v" ]; then
        printf '%s' "$v"
        return 0
      fi
    done < "$FM_BACKEND_CONFIG_DIR/backend"
  fi
  if detected=$(fm_backend_detect); then
    if [ "$detected" = herdr ]; then
      echo "NOTICE: auto-detected herdr runtime (HERDR_ENV=1) - spawning into the EXPERIMENTAL herdr backend. Set config/backend or pass --backend tmux to opt out." >&2
    fi
    printf '%s' "$detected"
    return 0
  fi
  printf 'tmux'
}

# fm_backend_validate: refuse an unknown backend LOUDLY. Silent on success.
fm_backend_validate() {  # <name>
  local name=$1
  if ! fm_backend_is_known "$name"; then
    echo "error: unknown backend '$name' (known: $FM_BACKEND_KNOWN)" >&2
    return 1
  fi
  return 0
}

# fm_meta_get: the LAST value of `key=` in <meta-file>, or empty (never
# errors) if the file or key is absent. Mirrors the ad hoc `grep '^key=' |
# tail -1 | cut -d= -f2-` snippet every fm-*.sh script used to repeat inline.
fm_meta_get() {  # <meta-file> <key>
  local meta=$1 key=$2
  [ -f "$meta" ] || return 0
  grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# fm_backend_of_meta: the backend recorded in <meta-file>, defaulting to
# `tmux` when the field is absent - the P1 compatibility contract.
fm_backend_of_meta() {  # <meta-file>
  local v
  v=$(fm_meta_get "$1" backend)
  printf '%s' "${v:-tmux}"
}

fm_backend_meta_for_window() {  # <target> <state-dir>
  local target=$1 state=$2 meta window thread_id
  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    window=$(fm_meta_get "$meta" window)
    thread_id=$(fm_meta_get "$meta" thread_id)
    [ "$window" = "$target" ] || [ "$thread_id" = "$target" ] || continue
    printf '%s' "$meta"
    return 0
  done
  return 1
}

fm_backend_codex_app_helper() {
  printf '%s/bin/fm-codex-app' "$FM_ROOT"
}

fm_backend_codex_app_meta_for_target() {  # <target>
  local target=$1 meta id window thread_id
  case "$target" in
    fm-*)
      meta="$FM_BACKEND_STATE_DIR/${target#fm-}.meta"
      [ -f "$meta" ] && { printf '%s' "$meta"; return 0; }
      ;;
  esac
  for meta in "$FM_BACKEND_STATE_DIR"/*.meta; do
    [ -e "$meta" ] || continue
    id=$(basename "$meta" .meta)
    window=$(fm_meta_get "$meta" window)
    thread_id=$(fm_meta_get "$meta" thread_id)
    [ "$target" = "$window" ] || [ "$target" = "$thread_id" ] || [ "$target" = "fm-$id" ] || continue
    printf '%s' "$meta"
    return 0
  done
  return 1
}

fm_backend_codex_app_thread_id() {  # <target>
  local meta thread_id
  meta=$(fm_backend_codex_app_meta_for_target "$1" 2>/dev/null || true)
  [ -n "$meta" ] || return 1
  thread_id=$(fm_meta_get "$meta" thread_id)
  [ -n "$thread_id" ] || return 1
  printf '%s' "$thread_id"
}

fm_backend_of_selector() {  # <raw-target> <resolved-target> <state-dir>
  local raw=$1 resolved=$2 state=$3 meta
  case "$raw" in
    fm-*)
      meta="$state/${raw#fm-}.meta"
      [ -f "$meta" ] && { fm_backend_of_meta "$meta"; return 0; }
      ;;
  esac
  if [ -n "$resolved" ]; then
    meta=$(fm_backend_meta_for_window "$resolved" "$state" 2>/dev/null || true)
    [ -n "$meta" ] && { fm_backend_of_meta "$meta"; return 0; }
  fi
  printf 'tmux'
}

# fm_backend_source: source the named backend's adapter file, once per shell.
fm_backend_source() {  # <name>
  local name=$1
  fm_backend_validate "$name" || return 1
  case "$name" in
    tmux)
      if [ -z "${_FM_BACKEND_TMUX_SOURCED:-}" ]; then
        # shellcheck source=bin/backends/tmux.sh
        . "$FM_BACKEND_LIB_DIR/backends/tmux.sh"
        _FM_BACKEND_TMUX_SOURCED=1
      fi
      ;;
    herdr)
      if [ -z "${_FM_BACKEND_HERDR_SOURCED:-}" ]; then
        # shellcheck source=bin/backends/herdr.sh
        . "$FM_BACKEND_LIB_DIR/backends/herdr.sh"
        _FM_BACKEND_HERDR_SOURCED=1
      fi
      ;;
    codex-app)
      ;;
  esac
}

# fm_backend_resolve_selector: resolve a raw fm-send.sh/fm-peek.sh style
# selector to a live session-provider target. Three forms, in order:
#   target with ":"   used as-is (the escape hatch for a window/pane outside
#                      this firstmate home) - backend-independent, a literal string.
#   "fm-<id>"          routed through <state-dir>/<id>.meta's `window=` field -
#                      backend-independent, a stored value, NOT re-verified
#                      against a live backend inventory (matches today's
#                      behavior: tmux window names can be trusted from meta
#                      without a live re-check).
#   anything else      an ad hoc bare window name with no meta, resolved by
#                      searching the legacy tmux live inventory. This remains
#                      the compatibility fallback; herdr tasks should be
#                      targeted by fm-<id> metadata or an explicit recorded
#                      target.
fm_backend_resolve_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 meta window
  case "$raw" in
    *:*)
      printf '%s' "$raw"
      return 0
      ;;
    fm-*)
      meta="$state/${raw#fm-}.meta"
      if [ ! -f "$meta" ]; then
        echo "error: no metadata for $raw in $state; pass session:window to target a window outside this firstmate home" >&2
        return 1
      fi
      window=$(fm_meta_get "$meta" window)
      [ -n "$window" ] || { echo "error: no window recorded in $meta" >&2; return 1; }
      printf '%s' "$window"
      return 0
      ;;
    *)
      meta=$(fm_backend_meta_for_window "$raw" "$state" 2>/dev/null || true)
      if [ -n "$meta" ]; then
        window=$(fm_meta_get "$meta" window)
        [ -n "$window" ] || { echo "error: no window recorded in $meta" >&2; return 1; }
        printf '%s' "$window"
        return 0
      fi
      fm_backend_source tmux || return 1
      fm_backend_tmux_resolve_bare_selector "$raw"
      ;;
  esac
}

# --- generic per-op dispatch -------------------------------------------------
#
# Thin case-dispatch wrappers so a caller names an operation and a backend
# rather than hand-writing `case "$backend" in tmux) fm_backend_tmux_x ;; esac`
# at every call site. Each verified backend adds its own arm here, without
# changing call sites.

# fm_backend_capture: bounded plain-text session capture.
fm_backend_capture() {  # <backend> <target> <lines>
  local backend=$1 thread_id
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    tmux) fm_backend_tmux_capture "$@" ;;
    herdr) fm_backend_herdr_capture "$@" ;;
    codex-app)
      thread_id=$(fm_backend_codex_app_thread_id "$1" 2>/dev/null || true)
      [ -n "$thread_id" ] || { echo "error: no thread_id recorded for Codex App target '$1'" >&2; return 1; }
      "$(fm_backend_codex_app_helper)" capture "$thread_id" "$2"
      ;;
    *) echo "error: no capture implementation for backend '$backend'" >&2; return 1 ;;
  esac
}

# fm_backend_send_key: one named special key (Enter, Escape, C-c, ...).
fm_backend_send_key() {  # <backend> <target> <key>
  local backend=$1 thread_id key
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    tmux) fm_backend_tmux_send_key "$@" ;;
    herdr) fm_backend_herdr_send_key "$@" ;;
    codex-app)
      thread_id=$(fm_backend_codex_app_thread_id "$1" 2>/dev/null || true)
      [ -n "$thread_id" ] || { echo "error: no thread_id recorded for Codex App target '$1'" >&2; return 1; }
      key=$2
      case "$key" in
        Escape|C-c) "$(fm_backend_codex_app_helper)" interrupt "$thread_id" ;;
        Enter) "$(fm_backend_codex_app_helper)" send "$thread_id" "" ;;
        *) echo "error: unsupported Codex App key '$key'" >&2; return 1 ;;
      esac
      ;;
    *) echo "error: no send-key implementation for backend '$backend'" >&2; return 1 ;;
  esac
}

# fm_backend_send_text_submit: type text once, then submit and verify,
# retrying only the submission (never retyping). Echoes the verdict
# (empty|pending|unknown|send-failed for the tmux and herdr adapters).
fm_backend_send_text_submit() {  # <backend> <target> <text> <retries> <enter-sleep> <settle>
  local backend=$1 thread_id
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    tmux) fm_backend_tmux_send_text_submit "$@" ;;
    herdr) fm_backend_herdr_send_text_submit "$@" ;;
    codex-app)
      thread_id=$(fm_backend_codex_app_thread_id "$1" 2>/dev/null || true)
      if [ -z "$thread_id" ]; then
        echo "error: no thread_id recorded for Codex App target '$1'" >&2
        printf 'send-failed'
        return 0
      fi
      if "$(fm_backend_codex_app_helper)" send "$thread_id" "$2"; then
        printf ''
      else
        printf 'send-failed'
      fi
      ;;
    *) echo "error: no send-text implementation for backend '$backend'" >&2; return 1 ;;
  esac
}

# fm_backend_kill: remove the task's session endpoint (best-effort; a
# nonexistent/already-gone target is not an error - callers already swallow
# failures here exactly as the inline `tmux kill-window ... || true` did).
fm_backend_kill() {  # <backend> <target>
  local backend=$1
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    tmux) fm_backend_tmux_kill "$@" ;;
    herdr) fm_backend_herdr_kill "$@" ;;
    codex-app) return 0 ;;
    *) echo "error: no kill implementation for backend '$backend'" >&2; return 1 ;;
  esac
}

# fm_backend_busy_state: semantic busy/idle/unknown for backends that expose
# native agent-state (herdr-addendum "busy state" row - the first backend
# where this gets real semantics beyond pane-regex). Backends with no such
# primitive (tmux) report unknown, the fm-watch.sh contract's cue to fall back
# to its own pane-hash + FM_BUSY_REGEX detection, unchanged from P1.
fm_backend_busy_state() {  # <backend> <target>
  local backend=$1
  shift
  fm_backend_source "$backend" || { printf 'unknown'; return 0; }
  case "$backend" in
    herdr) fm_backend_herdr_busy_state "$@" ;;
    *) printf 'unknown' ;;
  esac
}
