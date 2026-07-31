#!/usr/bin/env bash
# Host-assisted Codex Desktop backend.
#
# Codex Desktop owns visible thread creation, messaging, reading, and archive
# operations. This adapter binds those host operations to FirstMate's durable
# task ledger. Shell calls never imitate or proxy private Desktop transports.

FM_BACKEND_CODEX_APP_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
FM_BACKEND_CODEX_APP_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_BACKEND_CODEX_APP_ROOT}}"
FM_BACKEND_CODEX_APP_STATE="${FM_STATE_OVERRIDE:-$FM_BACKEND_CODEX_APP_HOME/state}"

fm_backend_codex_app_helper() {
  printf '%s/bin/fm-codex-app' "$FM_BACKEND_CODEX_APP_ROOT"
}

fm_backend_codex_app_meta_for_target() {  # <target>
  local target=$1 meta id window thread_id
  case "$target" in
    fm-*)
      meta="$FM_BACKEND_CODEX_APP_STATE/${target#fm-}.meta"
      [ -f "$meta" ] && { printf '%s' "$meta"; return 0; }
      ;;
  esac
  for meta in "$FM_BACKEND_CODEX_APP_STATE"/*.meta; do
    [ -f "$meta" ] || continue
    id=$(basename "$meta" .meta)
    window=$(fm_meta_get "$meta" window)
    thread_id=$(fm_meta_get "$meta" thread_id)
    [ "$target" = "$id" ] || [ "$target" = "fm-$id" ] \
      || [ "$target" = "$window" ] || [ "$target" = "$thread_id" ] || continue
    printf '%s' "$meta"
    return 0
  done
  return 1
}

fm_backend_codex_app_thread_id() {  # <target>
  local meta thread_id
  meta=$(fm_backend_codex_app_meta_for_target "$1") || return 1
  thread_id=$(fm_meta_get "$meta" thread_id)
  [ -n "$thread_id" ] || return 1
  printf '%s' "$thread_id"
}

fm_backend_codex_app_capture() {  # <target> <lines> [expected-label]
  local thread_id
  thread_id=$(fm_backend_codex_app_thread_id "$1") || {
    echo "error: no thread_id recorded for Codex App target '$1'" >&2
    return 1
  }
  "$(fm_backend_codex_app_helper)" capture "$thread_id" "$2"
}

fm_backend_codex_app_send_key() {  # <target> <key> [expected-label]
  local thread_id key=$2
  thread_id=$(fm_backend_codex_app_thread_id "$1") || {
    echo "error: no thread_id recorded for Codex App target '$1'" >&2
    return 1
  }
  case "$key" in
    Escape|C-c) "$(fm_backend_codex_app_helper)" interrupt "$thread_id" ;;
    Enter) "$(fm_backend_codex_app_helper)" send "$thread_id" "" ;;
    *) echo "error: unsupported Codex App key '$key'" >&2; return 1 ;;
  esac
}

fm_backend_codex_app_send_text_submit() {  # <target> <text> ...
  local thread_id
  thread_id=$(fm_backend_codex_app_thread_id "$1") || {
    printf 'send-failed'
    return 0
  }
  if "$(fm_backend_codex_app_helper)" send "$thread_id" "$2"; then
    printf ''
  else
    printf 'send-failed'
  fi
}

fm_backend_codex_app_kill() {  # <target>
  local meta state thread_id
  meta=$(fm_backend_codex_app_meta_for_target "$1") || return 0
  state=$(fm_meta_get "$meta" codex_app_thread_state)
  [ "$state" = archived ] && return 0
  thread_id=$(fm_meta_get "$meta" thread_id)
  [ -n "$thread_id" ] || return 0
  "$(fm_backend_codex_app_helper)" archive "$thread_id"
}

fm_backend_codex_app_target_exists() {  # <target>
  local meta state thread_id
  meta=$(fm_backend_codex_app_meta_for_target "$1") || return 1
  state=$(fm_meta_get "$meta" codex_app_thread_state)
  thread_id=$(fm_meta_get "$meta" thread_id)
  [ -n "$thread_id" ] || return 1
  [ "$state" != archived ]
}

fm_backend_codex_app_agent_state() {  # <target>
  local meta state thread_id
  meta=$(fm_backend_codex_app_meta_for_target "$1") || { printf 'missing'; return 0; }
  state=$(fm_meta_get "$meta" codex_app_thread_state)
  thread_id=$(fm_meta_get "$meta" thread_id)
  case "$state:$thread_id" in
    archived:*) printf 'dead' ;;
    visible:?*) printf 'alive' ;;
    *) printf 'unverified' ;;
  esac
}
