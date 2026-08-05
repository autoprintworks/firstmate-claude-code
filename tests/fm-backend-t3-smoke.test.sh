#!/usr/bin/env bash
# tests/fm-backend-t3-smoke.test.sh - real T3 Code smoke test for the t3 adapter
# (bin/backends/t3.sh + bin/fm-t3). Mirrors tests/fm-backend-cmux-smoke.test.sh's
# posture: every other suite fakes the CLI, this one talks to the REAL app.
#
# Like cmux there is no isolated throwaway instance to spin up - T3 Code is one
# shared, GUI-first application holding the developer's real work. So this test
# creates ONLY its own scratch git repo, its own project rooted there, and one
# thread inside it; it never enumerates-and-closes, never touches a thread it did
# not create, and purges everything it made on the way out. A crash mid-run
# leaves at most one archived `fm-test-t3-*` thread in a scratch project.
#
# It runs a REAL turn against a REAL model, so it costs tokens and about a
# minute. Skips cleanly when the T3 Code server is not running or no bearer
# token is installed, so CI and machines without T3 Code are unaffected.
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

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-t3-smoke.XXXXXX") || exit 1
PROJ="$TMP_ROOT/proj"
THREAD=""

cleanup_all() {
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

echo "# all t3 adapter smoke checks passed"
