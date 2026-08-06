#!/usr/bin/env bash
# tests/fm-backend-t3-smoke.test.sh - real T3 Code smoke test for the t3 adapter
# (bin/backends/t3.sh + bin/fm-t3). Mirrors tests/fm-backend-cmux-smoke.test.sh's
# posture: every other suite fakes the CLI, this one talks to the REAL app.
#
# Like cmux there is no isolated throwaway instance to spin up - T3 Code is one
# shared, GUI-first application holding the developer's real work. So this test
# clones its own scratch project from a persistent GitHub repo (see below) into
# a disposable local checkout; it never enumerates-and-closes, never touches a
# thread it did not create, and purges everything it made on the way out. A
# crash mid-run leaves at most a couple of archived `fm-test-t3-*`/`fm-t3spawn*`
# threads in a scratch project.
#
# Four threads get created. The first drives the t3 arm primitives directly
# (bin/backends/t3.sh, bin/fm-t3) - the low-level surface. The second goes
# through the real bin/fm-spawn.sh, bin/fm-send.sh and bin/fm-teardown.sh -
# a real treehouse worktree lease, a real brief as the crewmate's first
# prompt, a second turn via the send path, and a real teardown - because that
# is the path firstmate's crew actually runs, and driving the arms alone never
# proves it. The third and fourth are issue #55's live bridge proof: a
# direct-PR crewmate that pushes a branch and opens a real PR through
# bin/fm-gh-axi - proving node, npx and the bridge all resolve inside a T3
# thread - and reports the URL through the status file, never the thread, and
# a local-only crewmate proving the reverse state on the same real remote:
# given the same tools, told not to push, it never does.
#
# The GitHub side of that proof runs against ONE persistent private scratch
# repo, autoprintworks/fm-t3-adapter-smoke, created once by hand and never
# recreated or deleted. This test only ever creates and removes its own
# per-run branch (fm/<task-id>) and PR on that repo, so it never needs the gh
# CLI's delete_repo scope. See "Setup, once" below.
#
# It runs REAL turns against a REAL model, so it costs tokens and a handful of
# minutes. Skips cleanly when the T3 Code server is not running, no bearer
# token is installed, treehouse is missing, or gh is missing or not logged in,
# so CI and machines without T3 Code are unaffected. Every branch and PR this
# run opens on the persistent scratch repo is closed/deleted on the way out
# and that cleanup is verified; a crash mid-run leaves at most one open PR and
# its `fm/<task-id>` branch on autoprintworks/fm-t3-adapter-smoke to close by
# hand - never a new repo.
#
# Setup, once:
#   t3 auth session issue --token-only --ttl 30d > config/t3-token
#   gh auth login   (needs repo scope; used only for the #55 checks below)
#   gh repo create autoprintworks/fm-t3-adapter-smoke --private   (one time, never repeated)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_REPO="autoprintworks/fm-t3-adapter-smoke"
GH_REMOTE="https://github.com/$GH_REPO.git"

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
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "skip: gh not found or not logged in (required by the #55 GitHub-bridge checks)"
  exit 0
fi

# fm-spawn.sh, fm-send.sh and fm-teardown.sh all refuse to run for a gate agent
# unless this test-harness escape hatch is set; see bin/fm-gate-refuse-lib.sh.
export FM_GATE_REFUSE_BYPASS=1

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-t3-smoke.XXXXXX") || exit 1
PROJ="$TMP_ROOT/proj"
THREAD=""
SP_THREAD=""
SP_WT=""
BR_THREAD=""
BR_WT=""
BR_ID=""
LO_THREAD=""
LO_WT=""
LO_ID=""

cleanup_all() {
  if [ -n "$SP_THREAD" ]; then
    fm_backend_t3_kill "$SP_THREAD" >/dev/null 2>&1 || true
    fm_backend_t3_sweep_checkpoint_refs "$SP_THREAD" "$PROJ" >/dev/null 2>&1 || true
    node "$ROOT/bin/fm-t3" purge --thread "$SP_THREAD" >/dev/null 2>&1 || true
  fi
  if [ -n "$SP_WT" ] && command -v treehouse >/dev/null 2>&1; then
    ( cd "$PROJ" && treehouse return --force "$SP_WT" ) >/dev/null 2>&1 || true
  fi
  if [ -n "$BR_THREAD" ]; then
    fm_backend_t3_kill "$BR_THREAD" >/dev/null 2>&1 || true
    fm_backend_t3_sweep_checkpoint_refs "$BR_THREAD" "$PROJ" >/dev/null 2>&1 || true
    node "$ROOT/bin/fm-t3" purge --thread "$BR_THREAD" >/dev/null 2>&1 || true
  fi
  if [ -n "$BR_WT" ] && command -v treehouse >/dev/null 2>&1; then
    ( cd "$PROJ" && treehouse return --force "$BR_WT" ) >/dev/null 2>&1 || true
  fi
  if [ -n "$LO_THREAD" ]; then
    fm_backend_t3_kill "$LO_THREAD" >/dev/null 2>&1 || true
    fm_backend_t3_sweep_checkpoint_refs "$LO_THREAD" "$PROJ" >/dev/null 2>&1 || true
    node "$ROOT/bin/fm-t3" purge --thread "$LO_THREAD" >/dev/null 2>&1 || true
  fi
  if [ -n "$LO_WT" ] && command -v treehouse >/dev/null 2>&1; then
    ( cd "$PROJ" && treehouse return --force "$LO_WT" ) >/dev/null 2>&1 || true
  fi
  if [ -n "$THREAD" ]; then
    node "$ROOT/bin/fm-t3" purge --thread "$THREAD" --project-root "$(fm_backend_t3_native_path "$PROJ")" \
      >/dev/null 2>&1 || true
  fi
  # Best-effort: if a failure struck before the BR/LO sections closed their own
  # PR and deleted their own branch, remove them from the persistent scratch
  # repo here rather than leaving them behind. A no-op when already clean.
  if [ -n "$BR_ID" ]; then
    git push "$GH_REMOTE" --delete "fm/$BR_ID" >/dev/null 2>&1 || true
  fi
  if [ -n "$LO_ID" ]; then
    git push "$GH_REMOTE" --delete "fm/$LO_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup_all EXIT

# --- fixture -----------------------------------------------------------------

git clone -q "$GH_REMOTE" "$PROJ" >/dev/null 2>&1 \
  || fail "could not clone the persistent scratch repo $GH_REPO"
git -C "$PROJ" config user.email smoke@firstmate.local
git -C "$PROJ" config user.name 'firstmate smoke'

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

# --- #55: the GitHub bridge resolves inside a t3 thread, reported via the ---
# --- status file, and the reverse state (local-only) never pushes or PRs. --
#
# The persistent scratch repo (autoprintworks/fm-t3-adapter-smoke, cloned
# into $PROJ above) backs both checks below: a direct-PR crewmate that proves
# bin/fm-gh-axi (and the node/npx it depends on) resolve inside a T3 thread
# by actually pushing a branch and opening a PR, and a local-only crewmate
# proving the opposite - given the same tools, told not to push, it never
# does. Both report through the status file, never the thread; bin/fm-brief.sh
# (not hand-written brief text) supplies the mode-specific done-line contract
# so this test never duplicates it.

PROJ_NAME=$(basename "$PROJ")

# --- direct-PR: the bridge resolves inside the thread and reports via the file

BR_ID="t3bridge$$"
BR_STATE="$TMP_ROOT/bridge-state"
BR_DATA="$TMP_ROOT/bridge-data"
mkdir -p "$BR_STATE" "$BR_DATA/$BR_ID" || fail "could not create the bridge fixture dirs"

# No data/projects.md in this data dir: fm-project-mode.sh defaults an
# unregistered project to direct-PR, exactly the mode this check needs.
BR_MARKER="firstmate-t3-bridge-smoke-$$"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$BR_STATE" FM_DATA_OVERRIDE="$BR_DATA" \
  "$ROOT/bin/fm-brief.sh" "$BR_ID" "$PROJ_NAME" >/dev/null \
  || fail "fm-brief.sh failed to scaffold the direct-PR brief"
BR_BRIEF="$BR_DATA/$BR_ID/brief.md"
grep -q 'done: PR {url}' "$BR_BRIEF" || fail "the scaffolded brief lost the direct-PR done-line contract"
cat >> "$BR_BRIEF" <<EOF

# Test task
Create a new file named bridge-proof.txt containing exactly this one line:
$BR_MARKER
Stage and commit it with message "bridge smoke: $BR_MARKER".
Push your branch to origin, then open a pull request from your branch into
main using Firstmate's hidden-window GitHub bridge, titled "bridge smoke:
$BR_MARKER" with an empty body. Make no other changes.
EOF

BR_SPAWN_OUT="$TMP_ROOT/bridge-spawn.out"; BR_SPAWN_ERR="$TMP_ROOT/bridge-spawn.err"
env -u TMUX -u FM_BACKEND PATH="$PATH" \
  FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$BR_STATE" FM_DATA_OVERRIDE="$BR_DATA" \
  FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" \
  "$ROOT/bin/fm-spawn.sh" "$BR_ID" "$PROJ" --backend t3 --harness claude \
  >"$BR_SPAWN_OUT" 2>"$BR_SPAWN_ERR"
status=$?
[ "$status" -eq 0 ] \
  || fail "fm-spawn.sh failed for $BR_ID"$'\n'"$(cat "$BR_SPAWN_OUT")"$'\n'"$(cat "$BR_SPAWN_ERR")"

BR_META="$BR_STATE/$BR_ID.meta"
BR_THREAD=$(grep '^t3_thread=' "$BR_META" | cut -d= -f2-)
BR_WT=$(grep '^worktree=' "$BR_META" | cut -d= -f2-)
[ -n "$BR_THREAD" ] && [ -n "$BR_WT" ] || fail "fm-spawn.sh meta is missing a thread or worktree for $BR_ID"

for _ in $(seq 1 480); do
  case "$(fm_backend_t3_busy_state "$BR_THREAD")" in
    idle|exited) break ;;
  esac
  sleep 1
done
[ "$(fm_backend_t3_busy_state "$BR_THREAD")" = idle ] \
  || fail "the direct-PR crewmate's turn did not settle to idle"

BR_STATUS_FILE="$BR_STATE/$BR_ID.status"
[ -f "$BR_STATUS_FILE" ] || fail "the direct-PR crewmate never wrote a status file"
BR_DONE_LINE=$(grep '^done: PR ' "$BR_STATUS_FILE" | tail -1) \
  || fail "the status file has no 'done: PR <url>' line"$'\n'"$(cat "$BR_STATUS_FILE")"
BR_PR_URL=${BR_DONE_LINE#done: PR }
case "$BR_PR_URL" in
  "https://github.com/$GH_REPO/pull/"*) ;;
  *) fail "the reported PR URL is not a pull request on the scratch repo (got '$BR_PR_URL')" ;;
esac
pass "the direct-PR crewmate resolves node, npx and the bridge, and reports the PR URL through the status file"

BR_CAP=$(fm_backend_t3_capture "$BR_THREAD" 200) || fail "capture failed for the bridge thread"
case "$BR_CAP" in
  *"$BR_MARKER"*) ;;
  *) fail "the bridge thread's own transcript is missing the task marker (sanity check)" ;;
esac

BR_PR_STATE=$(gh pr view "$BR_PR_URL" --json state -q .state 2>/dev/null) \
  || fail "gh could not read back the reported PR; the bridge did not really open one"
[ "$BR_PR_STATE" = OPEN ] || fail "the reported PR is not open on GitHub (state=$BR_PR_STATE)"
BR_PR_HEAD=$(gh pr view "$BR_PR_URL" --json headRefName -q .headRefName 2>/dev/null)
[ "$BR_PR_HEAD" = "fm/$BR_ID" ] \
  || fail "the reported PR's head branch is not fm/$BR_ID (got '$BR_PR_HEAD')"
pass "the reported PR URL is a real, open pull request on the scratch repo, from the crewmate's own branch"

BR_TEARDOWN_OUT="$TMP_ROOT/bridge-teardown.out"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$BR_STATE" FM_DATA_OVERRIDE="$BR_DATA" \
  "$ROOT/bin/fm-teardown.sh" "$BR_ID" >"$BR_TEARDOWN_OUT" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "fm-teardown.sh failed for $BR_ID"$'\n'"$(cat "$BR_TEARDOWN_OUT")"
BR_WT=
pass "fm-teardown.sh tears down the direct-PR crewmate"

gh pr close "$BR_PR_URL" --delete-branch </dev/null >/dev/null 2>&1 \
  || fail "could not close the scratch PR"
BR_PR_STATE_AFTER=$(gh pr view "$BR_PR_URL" --json state -q .state 2>/dev/null)
[ "$BR_PR_STATE_AFTER" = CLOSED ] || fail "the scratch PR did not close (state=$BR_PR_STATE_AFTER)"
pass "the scratch PR is closed and its branch deleted, verified by reading GitHub back"

# --- local-only: the same crewmate, told not to push, never does ------------

LO_ID="t3local$$"
LO_STATE="$TMP_ROOT/local-state"
LO_DATA="$TMP_ROOT/local-data"
mkdir -p "$LO_STATE" "$LO_DATA/$LO_ID" || fail "could not create the local-only fixture dirs"

# A data/projects.md scoped to this thread's own data dir registers the same
# project as local-only, without touching the direct-PR thread's own mode.
printf -- '- %s [local-only] - local-only reverse-state fixture (added 2026-08-05)\n' \
  "$PROJ_NAME" > "$LO_DATA/projects.md"

LO_MARKER="firstmate-t3-local-smoke-$$"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$LO_STATE" FM_DATA_OVERRIDE="$LO_DATA" \
  "$ROOT/bin/fm-brief.sh" "$LO_ID" "$PROJ_NAME" >/dev/null \
  || fail "fm-brief.sh failed to scaffold the local-only brief"
LO_BRIEF="$LO_DATA/$LO_ID/brief.md"
grep -q "done: ready in branch fm/$LO_ID" "$LO_BRIEF" \
  || fail "the scaffolded brief lost the local-only done-line contract"
grep -q 'Never push to any remote and never open a PR' "$LO_BRIEF" \
  || fail "the scaffolded brief lost the local-only never-push rule"
cat >> "$LO_BRIEF" <<EOF

# Test task
Create a new file named local-proof.txt containing exactly this one line:
$LO_MARKER
Stage and commit it with message "local smoke: $LO_MARKER". Make no other
changes, and do not touch any remote.
EOF

LO_SPAWN_OUT="$TMP_ROOT/local-spawn.out"; LO_SPAWN_ERR="$TMP_ROOT/local-spawn.err"
env -u TMUX -u FM_BACKEND PATH="$PATH" \
  FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$LO_STATE" FM_DATA_OVERRIDE="$LO_DATA" \
  FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" \
  "$ROOT/bin/fm-spawn.sh" "$LO_ID" "$PROJ" --backend t3 --harness claude \
  >"$LO_SPAWN_OUT" 2>"$LO_SPAWN_ERR"
status=$?
[ "$status" -eq 0 ] \
  || fail "fm-spawn.sh failed for $LO_ID"$'\n'"$(cat "$LO_SPAWN_OUT")"$'\n'"$(cat "$LO_SPAWN_ERR")"

LO_META="$LO_STATE/$LO_ID.meta"
LO_THREAD=$(grep '^t3_thread=' "$LO_META" | cut -d= -f2-)
LO_WT=$(grep '^worktree=' "$LO_META" | cut -d= -f2-)
[ -n "$LO_THREAD" ] && [ -n "$LO_WT" ] || fail "fm-spawn.sh meta is missing a thread or worktree for $LO_ID"

for _ in $(seq 1 480); do
  case "$(fm_backend_t3_busy_state "$LO_THREAD")" in
    idle|exited) break ;;
  esac
  sleep 1
done
[ "$(fm_backend_t3_busy_state "$LO_THREAD")" = idle ] \
  || fail "the local-only crewmate's turn did not settle to idle"

LO_STATUS_FILE="$LO_STATE/$LO_ID.status"
[ -f "$LO_STATUS_FILE" ] || fail "the local-only crewmate never wrote a status file"
grep -q "^done: ready in branch fm/$LO_ID\$" "$LO_STATUS_FILE" \
  || fail "the status file has no 'done: ready in branch fm/$LO_ID' line"$'\n'"$(cat "$LO_STATUS_FILE")"
grep -qi 'PR ' "$LO_STATUS_FILE" && fail "the local-only status file mentions a PR; it must never open one"
pass "the local-only crewmate reports the reverse state through the status file: ready, no PR"

git ls-remote "$GH_REMOTE" "refs/heads/fm/$LO_ID" > "$TMP_ROOT/lo-remote-check.out" 2>/dev/null
[ -s "$TMP_ROOT/lo-remote-check.out" ] \
  && fail "the local-only crewmate's branch reached the real remote; it must never push"
gh pr list --repo "$GH_REPO" --head "fm/$LO_ID" --json url -q '.[].url' \
  > "$TMP_ROOT/lo-pr-check.out" 2>/dev/null
[ -s "$TMP_ROOT/lo-pr-check.out" ] \
  && fail "the local-only crewmate opened a PR; it must never open one"
pass "no push and no PR reached the real remote for the local-only crewmate, verified by reading GitHub back"

# The captain's merge authority approves and lands the ready branch before
# teardown - fm-teardown.sh correctly refuses an unmerged local-only worktree,
# so this step is not optional (bin/fm-merge-local.sh is the guarded
# fast-forward path; see its header comment).
LO_MERGE_OUT="$TMP_ROOT/local-merge.out"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$LO_STATE" FM_DATA_OVERRIDE="$LO_DATA" \
  "$ROOT/bin/fm-merge-local.sh" "$LO_ID" >"$LO_MERGE_OUT" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "fm-merge-local.sh failed for $LO_ID"$'\n'"$(cat "$LO_MERGE_OUT")"
git -C "$PROJ" log -1 --format=%s | grep -q "local smoke: $LO_MARKER" \
  || fail "local main does not carry the local-only crewmate's commit after the merge"
pass "fm-merge-local.sh fast-forwards local main to the approved local-only branch"

LO_TEARDOWN_OUT="$TMP_ROOT/local-teardown.out"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$LO_STATE" FM_DATA_OVERRIDE="$LO_DATA" \
  "$ROOT/bin/fm-teardown.sh" "$LO_ID" >"$LO_TEARDOWN_OUT" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "fm-teardown.sh failed for $LO_ID"$'\n'"$(cat "$LO_TEARDOWN_OUT")"
LO_WT=
pass "fm-teardown.sh tears down the local-only crewmate"

# --- purge everything this run created, verified by reading the server -----
#
# The captain's own T3 projects and threads are untouched by construction:
# this whole file only ever calls create_task/spawn on ids it minted itself
# and never enumerates or lists what else the server holds.

VERIFY_THREAD="$THREAD"
VERIFY_SP_THREAD="$SP_THREAD"
VERIFY_BR_THREAD="$BR_THREAD"
VERIFY_LO_THREAD="$LO_THREAD"
if ! cleanup_all; then
  trap - EXIT
  fail "cleanup failed to purge the scratch project and threads"
fi
trap - EXIT
THREAD=""
SP_THREAD=""
SP_WT=""
BR_THREAD=""
BR_WT=""
LO_THREAD=""
LO_WT=""

node "$ROOT/bin/fm-t3" exists "$VERIFY_THREAD" >/dev/null 2>&1
status=$?
[ "$status" -eq 1 ] || fail "the arm-level scratch thread is still visible to the server after purge (exit=$status)"

node "$ROOT/bin/fm-t3" exists "$VERIFY_SP_THREAD" >/dev/null 2>&1
status=$?
[ "$status" -eq 1 ] || fail "the spawned scratch thread is still visible to the server after purge (exit=$status)"

node "$ROOT/bin/fm-t3" exists "$VERIFY_BR_THREAD" >/dev/null 2>&1
status=$?
[ "$status" -eq 1 ] || fail "the direct-PR scratch thread is still visible to the server after purge (exit=$status)"

node "$ROOT/bin/fm-t3" exists "$VERIFY_LO_THREAD" >/dev/null 2>&1
status=$?
[ "$status" -eq 1 ] || fail "the local-only scratch thread is still visible to the server after purge (exit=$status)"

pass "the scratch project and all four threads are purged, verified by reading the server afterwards"

# cleanup_all above already removed $TMP_ROOT, so these two checks capture
# into variables rather than files.
FINAL_BR_REMOTE=$(git ls-remote "$GH_REMOTE" "refs/heads/fm/$BR_ID" 2>/dev/null)
[ -z "$FINAL_BR_REMOTE" ] \
  || fail "the direct-PR crewmate's branch is still on the persistent scratch repo after cleanup"
FINAL_LO_REMOTE=$(git ls-remote "$GH_REMOTE" "refs/heads/fm/$LO_ID" 2>/dev/null)
[ -z "$FINAL_LO_REMOTE" ] \
  || fail "the local-only crewmate's branch reached the persistent scratch repo"
BR_ID=""
LO_ID=""
pass "no branch from this run remains on the persistent scratch repo, verified by reading GitHub back"

echo "# all t3 adapter smoke checks passed"
