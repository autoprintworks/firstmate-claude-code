#!/usr/bin/env bash
# tests/fm-backend-t3-smoke.test.sh - real T3 Code smoke test for the t3 adapter
# (bin/backends/t3.sh + bin/fm-t3). Mirrors tests/fm-backend-cmux-smoke.test.sh's
# posture: every other suite fakes the CLI, this one talks to the REAL app.
#
# Like cmux there is no isolated throwaway instance to spin up - T3 Code is one
# shared, GUI-first application holding the developer's real work. So this test
# creates ONLY its own scratch git repo and its own project rooted there; it
# never enumerates-and-closes, never touches a thread it did not create, and
# purges everything it made on the way out. A crash mid-run leaves at most a
# couple of archived `fm-test-t3-*`/`fm-t3spawn*` threads in a scratch project.
#
# Two threads get created. The first drives the t3 arm primitives directly
# (bin/backends/t3.sh, bin/fm-t3) - the low-level surface. The second goes
# through the real bin/fm-spawn.sh, bin/fm-send.sh and bin/fm-teardown.sh -
# a real treehouse worktree lease, a real brief as the crewmate's first
# prompt, a second turn via the send path, and a real teardown - because that
# is the path firstmate's crew actually runs, and driving the arms alone never
# proves it.
#
# It runs REAL turns against a REAL model, so it costs tokens and a couple of
# minutes. Skips cleanly when the T3 Code server is not running, no bearer
# token is installed, or treehouse is missing, so CI and machines without
# T3 Code are unaffected.
#
# Setup, once:
#   t3 auth session issue --token-only --ttl 30d > config/t3-token
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'not ok - %s\n' "$1" >&2; cleanup_all; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { echo "skip: node not found (required by the t3 adapter)"; exit 0; }

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
fm_backend_source t3 || { echo "skip: could not source the t3 adapter"; exit 0; }

node "$ROOT/bin/fm-t3" token-info >/dev/null 2>&1 \
  || { echo "skip: no usable T3 Code bearer token (see the header of this file)"; exit 0; }
# Any thread id will do for a reachability probe: `exists` returns 1 for an
# absent thread and only errors when the server itself cannot be reached.
node "$ROOT/bin/fm-t3" exists 00000000-0000-4000-8000-000000000000 >/dev/null 2>&1
case $? in
  0|1) ;;
  *) echo "skip: the T3 Code server is not reachable (start the desktop app)"; exit 0 ;;
esac
command -v treehouse >/dev/null 2>&1 \
  || { echo "skip: treehouse not found (required by fm-spawn.sh)"; exit 0; }

# fm-spawn.sh, fm-send.sh and fm-teardown.sh all refuse to run for a gate agent
# unless this test-harness escape hatch is set; see bin/fm-gate-refuse-lib.sh.
export FM_GATE_REFUSE_BYPASS=1

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-t3-smoke.XXXXXX") || exit 1
PROJ="$TMP_ROOT/proj"
THREAD=""
SP_THREAD=""
SP_WT=""

cleanup_all() {
  if [ -n "$SP_THREAD" ]; then
    fm_backend_t3_kill "$SP_THREAD" >/dev/null 2>&1 || true
    fm_backend_t3_sweep_checkpoint_refs "$SP_THREAD" "$PROJ" >/dev/null 2>&1 || true
    node "$ROOT/bin/fm-t3" purge --thread "$SP_THREAD" >/dev/null 2>&1 || true
  fi
  if [ -n "$SP_WT" ] && command -v treehouse >/dev/null 2>&1; then
    ( cd "$PROJ" && treehouse return --force "$SP_WT" ) >/dev/null 2>&1 || true
  fi
  if [ -n "$THREAD" ]; then
    node "$ROOT/bin/fm-t3" purge --thread "$THREAD" --project-root "$(fm_backend_t3_native_path "$PROJ")" \
      >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup_all EXIT

# --- fixture -----------------------------------------------------------------

mkdir -p "$PROJ" || exit 1
git -C "$PROJ" init -q -b main >/dev/null 2>&1 || fail "could not init the scratch repo"
printf 'scratch project for the t3 adapter smoke test\n' > "$PROJ/README.md"
git -C "$PROJ" add -A >/dev/null 2>&1
git -C "$PROJ" -c user.email=smoke@firstmate.local -c user.name='firstmate smoke' \
  commit -qm 'scratch' >/dev/null 2>&1 || fail "could not commit the scratch repo"

MARKER="firstmate-t3-smoke-$$"
BRIEF="$TMP_ROOT/brief.txt"
printf 'Reply with exactly this one word and nothing else: %s\nDo not use any tools.\n' "$MARKER" > "$BRIEF"

[ "$(fm_backend_t3_container_ensure)" = t3 ] || fail "container_ensure should print t3"
pass "container_ensure needs no container and says so"

# --- create_task -------------------------------------------------------------

fm_backend_t3_create_task t3 not-a-uuid "$PROJ" "$BRIEF" >/dev/null 2>&1 \
  && fail "create_task should refuse a non-UUID thread id"
pass "create_task refuses a non-UUID thread id"

THREAD=$(node -e 'process.stdout.write(require("node:crypto").randomUUID())')
OUT=$(fm_backend_t3_create_task t3 "$THREAD" "$PROJ" "$BRIEF" "$PROJ" "fm-test-t3-$$") \
  || fail "create_task failed for $THREAD"
[ "$OUT" = "$THREAD" ] || fail "create_task should print the thread id (got '$OUT')"
pass "create_task creates the project and thread and prints the id"

fm_backend_t3_create_task t3 "$THREAD" "$PROJ" "$BRIEF" >/dev/null 2>&1 \
  && fail "create_task should refuse a thread id that already exists"
pass "create_task refuses a duplicate thread id"

fm_backend_t3_target_exists "$THREAD" || fail "target_exists should be true for a live thread"
pass "target_exists is true for a live thread"

# --- supervision through a real turn ----------------------------------------

SAW_BUSY=0
STATE=unknown
for _ in $(seq 1 240); do
  STATE=$(fm_backend_t3_busy_state "$THREAD")
  case "$STATE" in
    busy) SAW_BUSY=1 ;;
    idle|exited) [ "$SAW_BUSY" = 1 ] && break ;;
  esac
  sleep 1
done
[ "$SAW_BUSY" = 1 ] || fail "busy_state never reported busy during a real turn (last='$STATE')"
[ "$STATE" = idle ] || fail "busy_state should settle to idle at a clean turn end (got '$STATE')"
pass "busy_state reports busy during a turn and idle at a clean end"

CAP=$(fm_backend_t3_capture "$THREAD" 40) || fail "capture failed"
case "$CAP" in
  *"$MARKER"*) ;;
  *) fail "capture did not contain the crewmate's reply (marker $MARKER)" ;;
esac
case "$CAP" in
  *$'\033'*) fail "capture leaked escape bytes into firstmate context" ;;
esac
pass "capture renders the transcript as plain, escape-free text"

# A closed pipe is the normal case: callers tail the capture.
fm_backend_t3_capture "$THREAD" 40 2>/dev/null | head -1 >/dev/null \
  || fail "capture should survive a closed pipe"
pass "capture is SIGPIPE-safe"

WTP=$(fm_backend_t3_current_path "$THREAD" | tr -d '\r\n')
[ -n "$WTP" ] || fail "current_path returned nothing for a live thread"
pass "current_path reports the thread's worktree"

# --- push primitives ---------------------------------------------------------

VERDICT=$(fm_backend_t3_send_text_submit "$THREAD" 'Reply with exactly: OK' 1 0 0)
[ "$VERDICT" = empty ] || fail "send_text_submit should print the literal word empty (got '$VERDICT')"
pass "send_text_submit delivers a turn and prints the literal word empty"

fm_backend_t3_send_key "$THREAD" Enter || fail "send_key Enter should be a no-op success"
fm_backend_t3_send_key "$THREAD" Escape 2>/dev/null \
  && fail "send_key should refuse a key it cannot deliver"
pass "send_key accepts Enter and refuses everything else loudly"

fm_backend_t3_send_literal "$THREAD" text 2>/dev/null \
  && fail "send_literal should refuse: there is no composer"
pass "send_literal refuses loudly"

# --- endpoint validation -----------------------------------------------------

META="$TMP_ROOT/task.meta"
TASK_ID=t3smoke$$
{
  echo "window=$THREAD"
  echo "endpoint_task_id=$TASK_ID"
  echo "worktree=$PROJ"
  echo "project=$PROJ"
  echo "backend=t3"
  echo "t3_thread=$THREAD"
  echo "t3_checkpoint_refs=1"
} > "$META"
fm_backend_validate_task_endpoint "$META" "$TASK_ID" >/dev/null \
  || fail "validate_task_endpoint should accept well-formed t3 metadata"
[ "$FM_BACKEND_VALIDATED_BACKEND" = t3 ] || fail "validator should report backend t3"
[ "$FM_BACKEND_VALIDATED_TARGET" = "$THREAD" ] || fail "validator should report the thread as the target"
pass "validate_task_endpoint accepts well-formed t3 metadata"

sed 's/^t3_thread=.*/t3_thread=00000000-0000-4000-8000-000000000000/' "$META" > "$META.bad"
fm_backend_validate_task_endpoint "$META.bad" "$TASK_ID" >/dev/null 2>&1 \
  && fail "validator should refuse metadata whose t3_thread disagrees with window"
pass "validate_task_endpoint refuses a t3_thread that disagrees with the window"

sed 's/^window=.*/window=fm-not-a-uuid/' "$META" > "$META.bad2"
fm_backend_validate_task_endpoint "$META.bad2" "$TASK_ID" >/dev/null 2>&1 \
  && fail "validator should refuse a non-UUID t3 target"
pass "validate_task_endpoint refuses a non-UUID t3 target"

# --- checkpoint refs ---------------------------------------------------------

# Wait out the second turn so its checkpoint ref exists before the sweep.
for _ in $(seq 1 240); do
  case "$(fm_backend_t3_busy_state "$THREAD")" in
    idle|exited) break ;;
  esac
  sleep 1
done

PREFIX=$(fm_backend_t3_checkpoint_refs_prefix "$THREAD" | tr -d '\r\n')
case "$PREFIX" in
  refs/t3/checkpoints/*) ;;
  *) fail "checkpoint_refs_prefix should name the refs/t3/checkpoints namespace (got '$PREFIX')" ;;
esac
BEFORE=$(git -C "$PROJ" for-each-ref --format='%(refname)' "$PREFIX" 2>/dev/null | grep -c . || true)
[ "$BEFORE" -gt 0 ] || fail "T3 left no checkpoint refs to sweep; the sweep would be untestable"
pass "T3 leaves $BEFORE checkpoint ref(s) in the project repo after a turn"

# --- teardown ----------------------------------------------------------------

# Three arguments, exactly what fm_backend_kill hands the t3 arm from teardown's
# four: the thread, an empty zellij tab id, and the pane label it will never use.
fm_backend_t3_kill "$THREAD" "" "fm-$TASK_ID" || fail "kill should return 0"
fm_backend_t3_target_exists "$THREAD" && fail "target_exists should be false after kill"
pass "kill stops the session, archives the thread, and the target is gone"

[ "$(fm_backend_t3_busy_state "$THREAD")" = exited ] \
  || fail "busy_state should report exited for a torn-down thread"
pass "busy_state reports exited for a torn-down thread"

fm_backend_t3_sweep_checkpoint_refs "$THREAD" "$PROJ" >/dev/null || fail "checkpoint sweep failed"
AFTER=$(git -C "$PROJ" for-each-ref --format='%(refname)' "$PREFIX" 2>/dev/null | grep -c . || true)
[ "$AFTER" = 0 ] || fail "the checkpoint sweep left $AFTER ref(s) behind"
pass "the checkpoint sweep removes every ref the thread left in the project repo"

# Killing an already-gone thread is not an error: teardown may run twice.
fm_backend_t3_kill "$THREAD" || fail "kill should be idempotent"
fm_backend_t3_sweep_checkpoint_refs "$THREAD" "$PROJ" >/dev/null || fail "sweep should be idempotent"
pass "kill and the checkpoint sweep are both idempotent"

# --- real spawn through bin/fm-spawn.sh, a real turn, then real teardown ----
#
# Everything above drives the t3 arm primitives directly. This section proves
# the higher-level scripts firstmate's crew actually runs, in the same scratch
# project: a real treehouse worktree lease, a real fm-spawn.sh launch with the
# brief as the first prompt, steering through fm-send.sh, and a real
# fm-teardown.sh teardown - stop, archive (never delete), sweep, then return
# the lease.

SP_ID="t3spawn$$"
SP_STATE="$TMP_ROOT/spawn-state"
SP_DATA="$TMP_ROOT/spawn-data"
mkdir -p "$SP_STATE" "$SP_DATA/$SP_ID" || fail "could not create the spawn fixture dirs"

SPAWN_MARKER="firstmate-t3-spawn-smoke-$$"
printf 'Reply with exactly this one word and nothing else: %s\nDo not use any tools.\n' \
  "$SPAWN_MARKER" > "$SP_DATA/$SP_ID/brief.md"

# FM_CONFIG_OVERRIDE is deliberately NOT set: it falls through to
# $ROOT/config, the real bearer token, exactly like the arm-level calls above.
SPAWN_OUT="$TMP_ROOT/spawn.out"; SPAWN_ERR="$TMP_ROOT/spawn.err"
env -u TMUX -u FM_BACKEND PATH="$PATH" \
  FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$SP_STATE" FM_DATA_OVERRIDE="$SP_DATA" \
  FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" \
  "$ROOT/bin/fm-spawn.sh" "$SP_ID" "$PROJ" --backend t3 --harness claude \
  >"$SPAWN_OUT" 2>"$SPAWN_ERR"
status=$?
[ "$status" -eq 0 ] \
  || fail "fm-spawn.sh failed for $SP_ID"$'\n'"--- stdout ---"$'\n'"$(cat "$SPAWN_OUT")"$'\n'"--- stderr ---"$'\n'"$(cat "$SPAWN_ERR")"

SP_META="$SP_STATE/$SP_ID.meta"
[ -f "$SP_META" ] || fail "fm-spawn.sh did not write a meta file for $SP_ID"
SP_THREAD=$(grep '^t3_thread=' "$SP_META" | cut -d= -f2-)
SP_WT=$(grep '^worktree=' "$SP_META" | cut -d= -f2-)
case "$SP_THREAD" in
  ????????-????-????-????-????????????) ;;
  *) fail "fm-spawn.sh meta has no well-formed t3_thread (got '$SP_THREAD')" ;;
esac
[ -n "$SP_WT" ] && [ -d "$SP_WT" ] || fail "fm-spawn.sh meta has no real worktree (got '$SP_WT')"
[ "$SP_WT" != "$PROJ" ] || fail "the leased worktree is the project itself, not an isolated lease"
pass "fm-spawn.sh leases a real treehouse worktree, writes meta first, and mints a t3 thread"

LEASE_STATUS=$(cd "$PROJ" && treehouse status 2>&1)
case "$LEASE_STATUS" in
  *"held by fm-$SP_ID"*) ;;
  *) fail "treehouse does not show the leased worktree held by fm-$SP_ID"$'\n'"$LEASE_STATUS" ;;
esac
pass "the spawn's worktree lease is held by fm-$SP_ID in the treehouse pool"

INFO=$(node "$ROOT/bin/fm-t3" info "$SP_THREAD") || fail "fm-t3 info failed for the spawned thread"
case "$INFO" in
  *"title=fm-$SP_ID"*) ;;
  *) fail "the spawned thread is not titled fm-$SP_ID"$'\n'"$INFO" ;;
esac
pass "the spawned thread is titled fm-$SP_ID"

# --- supervision through the real first turn ---------------------------------

SP_SAW_BUSY=0
SP_STATE_SEEN=unknown
for _ in $(seq 1 240); do
  SP_STATE_SEEN=$(fm_backend_t3_busy_state "$SP_THREAD")
  case "$SP_STATE_SEEN" in
    busy) SP_SAW_BUSY=1 ;;
    idle|exited) [ "$SP_SAW_BUSY" = 1 ] && break ;;
  esac
  sleep 1
done
[ "$SP_SAW_BUSY" = 1 ] || fail "the spawned turn never reported busy (last='$SP_STATE_SEEN')"
[ "$SP_STATE_SEEN" = idle ] || fail "the spawned turn did not settle to idle (got '$SP_STATE_SEEN')"
pass "the real spawn's first turn reports busy during and idle after"

SP_CAP=$(fm_backend_t3_capture "$SP_THREAD" 40) || fail "capture failed for the spawned thread"
case "$SP_CAP" in
  *"$SPAWN_MARKER"*) ;;
  *) fail "the brief did not arrive as the crewmate's first prompt (marker $SPAWN_MARKER missing)" ;;
esac
pass "the brief arrives as the crewmate's first prompt and the reply arrives through capture"

# --- a second turn via the real send path proves steering --------------------

SEND_MARKER="firstmate-t3-send-smoke-$$"
FM_HOME="$ROOT" FM_STATE_OVERRIDE="$SP_STATE" \
  "$ROOT/bin/fm-send.sh" "$SP_ID" \
  "Reply with exactly this one word and nothing else: $SEND_MARKER. Do not use any tools." \
  >"$TMP_ROOT/send.out" 2>"$TMP_ROOT/send.err"
status=$?
[ "$status" -eq 0 ] || fail "fm-send.sh failed to steer $SP_ID"$'\n'"$(cat "$TMP_ROOT/send.err")"

for _ in $(seq 1 240); do
  case "$(fm_backend_t3_busy_state "$SP_THREAD")" in
    idle|exited) break ;;
  esac
  sleep 1
done
SEND_CAP=$(fm_backend_t3_capture "$SP_THREAD" 40) || fail "capture failed after the send-path turn"
case "$SEND_CAP" in
  *"$SEND_MARKER"*) ;;
  *) fail "fm-send.sh did not steer a second turn (marker $SEND_MARKER missing)" ;;
esac
pass "a second turn via fm-send.sh proves steering after the first turn completes"

# --- a real teardown: stop, archive (never delete), sweep, then return lease -

SP_PREFIX=$(fm_backend_t3_checkpoint_refs_prefix "$SP_THREAD" | tr -d '\r\n')
SP_REFS_BEFORE=$(git -C "$PROJ" for-each-ref --format='%(refname)' "$SP_PREFIX" 2>/dev/null | grep -c . || true)
[ "$SP_REFS_BEFORE" -gt 0 ] || fail "the spawned thread left no checkpoint refs; the sweep would be untestable"

TEARDOWN_OUT="$TMP_ROOT/teardown.out"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$SP_STATE" FM_DATA_OVERRIDE="$SP_DATA" \
  "$ROOT/bin/fm-teardown.sh" "$SP_ID" >"$TEARDOWN_OUT" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "fm-teardown.sh failed for $SP_ID"$'\n'"$(cat "$TEARDOWN_OUT")"
[ -f "$SP_META" ] && fail "fm-teardown.sh did not remove $SP_META"
pass "fm-teardown.sh tears down the spawned crewmate and clears its meta"

fm_backend_t3_target_exists "$SP_THREAD" && fail "the thread should be stopped and gone from the live shell"
ARCHIVED=$(node "$ROOT/bin/fm-t3" archived "$SP_THREAD") \
  || fail "fm-teardown.sh deleted the thread instead of archiving it (no record in the archived snapshot)"
case "$ARCHIVED" in
  archived_at=*) ;;
  *) fail "the archived snapshot reports no archived_at for $SP_THREAD (got '$ARCHIVED')" ;;
esac
pass "fm-teardown.sh stops the crewmate and archives the thread rather than deleting it"

SP_REFS_AFTER=$(git -C "$PROJ" for-each-ref --format='%(refname)' "$SP_PREFIX" 2>/dev/null | grep -c . || true)
[ "$SP_REFS_AFTER" = 0 ] || fail "fm-teardown.sh left $SP_REFS_AFTER checkpoint ref(s) behind"
pass "fm-teardown.sh sweeps every checkpoint ref the spawned thread left in the project repo"

LEASE_STATUS_AFTER=$(cd "$PROJ" && treehouse status 2>&1)
case "$LEASE_STATUS_AFTER" in
  *"held by fm-$SP_ID"*) fail "fm-teardown.sh did not return the worktree lease"$'\n'"$LEASE_STATUS_AFTER" ;;
esac
pass "fm-teardown.sh returns the worktree lease only after the crewmate is stopped, archived, and swept"
SP_WT=

# Teardown idempotency for the real script's own operations (kill, archive,
# sweep) is the "kill and the checkpoint sweep are both idempotent" check
# above: fm-teardown.sh's t3 branch calls exactly those two arm functions, and
# both already tolerate a second call. A second LITERAL fm-teardown.sh
# invocation with the same task id is a different question - the meta file
# fm-teardown.sh just removed IS the record of a live task, and every backend
# (not just t3) refuses teardown of an id with no meta, on purpose, so a typo'd
# id fails loudly instead of silently doing nothing.

# --- purge everything this run created, verified by reading the server -----
#
# The captain's own T3 projects and threads are untouched by construction:
# this whole file only ever calls create_task/spawn on ids it minted itself
# and never enumerates or lists what else the server holds.

VERIFY_THREAD="$THREAD"
VERIFY_SP_THREAD="$SP_THREAD"
if ! cleanup_all; then
  trap - EXIT
  fail "cleanup failed to purge the scratch project and threads"
fi
trap - EXIT
THREAD=""
SP_THREAD=""
SP_WT=""

node "$ROOT/bin/fm-t3" exists "$VERIFY_THREAD" >/dev/null 2>&1
status=$?
[ "$status" -eq 1 ] || fail "the arm-level scratch thread is still visible to the server after purge (exit=$status)"

node "$ROOT/bin/fm-t3" exists "$VERIFY_SP_THREAD" >/dev/null 2>&1
status=$?
[ "$status" -eq 1 ] || fail "the spawned scratch thread is still visible to the server after purge (exit=$status)"

pass "the scratch project and both threads are purged, verified by reading the server afterwards"

echo "# all t3 adapter smoke checks passed"
