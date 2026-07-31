#!/usr/bin/env bash
# Atomically drain durable watcher wake records, then assert watcher liveness.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"

DRAIN_TMP=
DRAIN_LOCK_HELD=false

# Defense in depth for the watcher re-arm chain: this script runs at the top of
# every wake-handling and recovery turn, so assert watcher liveness here too. A
# lapsed supervision chain then surfaces on a plain drain-and-handle turn, not
# only when a guarded supervision script (fm-peek/fm-send/...) happens to run.
# Reuse fm-guard.sh's existing graced, beacon-based banner (FM_GUARD_GRACE) - do
# not duplicate the beacon math. Because the watcher touches its beacon every
# poll cycle, a normal fire leaves a recent beacon well inside grace and stays
# silent; only a genuine stale-beyond-grace lapse with work in flight warns. Call
# after the queue is emptied so guard never re-prints its own queued-wakes notice
# for the records this run just drained, and never let a guard hiccup change the
# drain's exit status.
assert_watcher_liveness() {
  "$SCRIPT_DIR/fm-guard.sh" || true
}

# shellcheck disable=SC2317,SC2329 # Invoked by trap handlers below.
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$DRAIN_LOCK_HELD" = true ] && [ -n "$DRAIN_TMP" ] && [ -e "$DRAIN_TMP" ]; then
    fm_wake_restore_queue "$DRAIN_TMP" || true
  fi
  if [ "$DRAIN_LOCK_HELD" = true ]; then
    fm_lock_release "$FM_WAKE_QUEUE_LOCK"
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fm_lock_acquire_wait "$FM_WAKE_QUEUE_LOCK"
DRAIN_LOCK_HELD=true
fm_lock_debug "drain acquired"

if fm_wake_use_spool_backend; then
  mkdir -p "$FM_WAKE_QUEUE_DIR"
  if ! fm_wake_spool_has_entries; then
    fm_wake_clear_pending
    fm_lock_debug "drain empty-spool"
    assert_watcher_liveness
    fm_lock_debug "drain empty-spool-after-guard"
    exit 0
  fi

  DRAIN_TMP="$STATE/.wake-queue.drain.$(fm_current_pid).${RANDOM:-0}"
  rm -rf -- "$DRAIN_TMP" 2>/dev/null || true
  fm_lock_debug "drain moving spool tmp=$DRAIN_TMP"
  mv "$FM_WAKE_QUEUE_DIR" "$DRAIN_TMP" || exit 1
  fm_lock_debug "drain moved spool tmp=$DRAIN_TMP"
  mkdir -p "$FM_WAKE_QUEUE_DIR" || exit 1
  fm_wake_clear_pending
  fm_lock_debug "drain reset spool tmp=$DRAIN_TMP"

  fm_wake_print_deduped_spool "$DRAIN_TMP" || exit "$?"
  fm_lock_debug "drain printed spool tmp=$DRAIN_TMP"
  rm -rf -- "$DRAIN_TMP"
  DRAIN_TMP=
  fm_lock_debug "drain removed spool tmp"
  assert_watcher_liveness
  fm_lock_debug "drain spool after guard"
  fm_lock_debug "drain spool finished"
  exit 0
fi

if [ ! -s "$FM_WAKE_QUEUE" ]; then
  : > "$FM_WAKE_QUEUE"
  fm_lock_debug "drain empty-queue"
  assert_watcher_liveness
  fm_lock_debug "drain empty-queue-after-guard"
  exit 0
fi

DRAIN_TMP="$STATE/.wake-queue.drain.$(fm_current_pid)"
rm -f "$DRAIN_TMP"
fm_lock_debug "drain moving queue tmp=$DRAIN_TMP"
mv "$FM_WAKE_QUEUE" "$DRAIN_TMP" || exit 1
fm_lock_debug "drain moved queue tmp=$DRAIN_TMP"
: > "$FM_WAKE_QUEUE" || exit 1
fm_lock_debug "drain reset queue tmp=$DRAIN_TMP"

fm_wake_print_deduped "$DRAIN_TMP" || exit "$?"
fm_lock_debug "drain printed tmp=$DRAIN_TMP"
rm -f "$DRAIN_TMP"
DRAIN_TMP=
fm_lock_debug "drain removed tmp"
assert_watcher_liveness
fm_lock_debug "drain after guard"
fm_lock_debug "drain finished"
exit 0
