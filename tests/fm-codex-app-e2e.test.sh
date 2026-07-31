#!/usr/bin/env bash
# End-to-end Windows/Codex Desktop backend lifecycle smoke.
# This exercises FirstMate's real brief, spawn, backend routing, archive gate,
# and teardown path without pretending the shell can create a visible app thread.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TEST_TMP_ROOT="${FM_TEST_TMPDIR:-$ROOT/state/tmp}"
mkdir -p "$TEST_TMP_ROOT"
TMP=$(mktemp -d "$TEST_TMP_ROOT/fm-codex-app-e2e.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

assert_grep() {
  local pattern=$1 file=$2 message=$3
  grep -q "$pattern" "$file" || fail "$message"
}

FM_TEST_HOME="$TMP/home"
PROJECT="$TMP/project"
THREAD_WT="$TMP/codex-thread-worktree"
ID=e2e-codex-scout

mkdir -p "$FM_TEST_HOME" "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email test@example.invalid
git -C "$PROJECT" config user.name "FirstMate E2E"
git -C "$PROJECT" commit -q --allow-empty -m "init"

FM_HOME="$FM_TEST_HOME" FM_BACKEND=codex-app "$ROOT/bin/fm-brief.sh" "$ID" "$(basename "$PROJECT")" --scout > "$TMP/brief.out"
BRIEF="$FM_TEST_HOME/data/$ID/brief.md"
printf '\n# Test task\nVerify the Codex App backend lifecycle without editing the saved checkout.\n' >> "$BRIEF"

FM_HOME="$FM_TEST_HOME" FM_BACKEND=codex-app "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJECT" codex --scout > "$TMP/spawn.out"
assert_grep "prepared $ID" "$TMP/spawn.out" "spawn did not prepare a codex-app task"
assert_grep "create_thread or fork_thread" "$TMP/spawn.out" "spawn did not ask for a visible Codex App thread"

META="$FM_TEST_HOME/state/$ID.meta"
assert_grep '^backend=codex-app$' "$META" "meta did not record codex-app backend"
assert_grep '^codex_app_thread_state=pending$' "$META" "meta did not record pending thread state"
assert_grep '^codex_app_pending_action=create_thread_or_fork_thread$' "$META" "meta did not record pending app action"
BRIEF_LINE=$(grep '^codex_app_brief=' "$META" | sed 's/^codex_app_brief=//')
case "$BRIEF_LINE" in
  */data/$ID/brief.md|*\\data\\$ID\\brief.md) ;;
  *) fail "meta did not record this task's brief path: $BRIEF_LINE" ;;
esac
pass "fm-spawn prepares visible Codex App task state without treehouse"

mkdir -p "$THREAD_WT"
FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-codex-app" record-thread "$ID" thread-e2e --worktree "$THREAD_WT" --turn-id turn-e2e > "$TMP/record.out"
assert_grep '^thread_id=thread-e2e$' "$META" "record-thread did not store the thread id"
WORKTREE_LINE=$(grep '^worktree=' "$META" | sed 's/^worktree=//')
case "$WORKTREE_LINE" in
  "$THREAD_WT"|*/codex-thread-worktree|*\\codex-thread-worktree) ;;
  *) fail "record-thread did not store the app worktree: $WORKTREE_LINE" ;;
esac
assert_grep '^codex_app_thread_state=visible$' "$META" "record-thread did not mark the thread visible"
pass "fm-codex-app records the visible thread and app worktree"

if FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-peek.sh" "fm-$ID" > "$TMP/peek.out" 2> "$TMP/peek.err"; then
  fail "fm-peek succeeded without cached app thread text"
fi
assert_grep "Use read_thread" "$TMP/peek.err" "fm-peek did not point to read_thread for app-owned capture"

printf 'first line\nsecond line\nthird line\n' | FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-codex-app" record-capture "$ID" - > "$TMP/capture-record.out"
FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-peek.sh" "fm-$ID" 2 > "$TMP/peek-cached.out"
grep -qxF "second line" "$TMP/peek-cached.out" || fail "cached peek missed second line"
grep -qxF "third line" "$TMP/peek-cached.out" || fail "cached peek missed third line"
pass "fm-peek routes codex-app capture through the app ledger"

if FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-send.sh" "fm-$ID" "please continue" > "$TMP/send.out" 2> "$TMP/send.err"; then
  fail "fm-send succeeded instead of deferring to Codex Desktop thread tools"
fi
assert_grep "send_message_to_thread" "$TMP/send.err" "fm-send did not point to send_message_to_thread for app-owned send"
pass "fm-send refuses shell imitation and points to Codex Desktop thread send"

printf 'done: e2e scout report\n' > "$FM_TEST_HOME/data/$ID/report.md"
FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-decision-hold.sh" complete "$ID" --none > "$TMP/decision.out"
if FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-teardown.sh" "$ID" > "$TMP/teardown-unarchived.out" 2> "$TMP/teardown-unarchived.err"; then
  fail "teardown succeeded before the visible thread was archived"
fi
assert_grep "set_thread_archived" "$TMP/teardown-unarchived.err" "teardown did not require archiving the visible thread"

FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-codex-app" mark-archived "$ID" > "$TMP/archive.out"
FM_HOME="$FM_TEST_HOME" "$ROOT/bin/fm-teardown.sh" "$ID" > "$TMP/teardown.out"
[ ! -e "$META" ] || fail "teardown left task meta behind"
[ ! -e "$FM_TEST_HOME/state/$ID.codex-app.capture" ] || fail "teardown left cached capture behind"
pass "fm-teardown requires archive first and then cleans codex-app state"
