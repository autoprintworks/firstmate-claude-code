#!/usr/bin/env bash
# Firstmate watcher.
# Classifies supervision wakes in bash. In normal mode it absorbs benign wakes
# and keeps blocking; it queues and exits only for actionable wakes. The no-verb
# turn-end / non-terminal-stale path is absorb-only-when-provably-working: a wake
# is absorbed only when the crew shows POSITIVE evidence it is still working (an
# actively-running no-mistakes step, or a backend busy signal), and surfaced
# otherwise, so a crew that finishes (or stops and waits) without a
# captain-relevant status is never silently swallowed. While state/.afk exists,
# the daemon owns triage and
# this watcher queues and exits on every wake. Printed reason lines:
#   signal: <file>...      status/turn-end signals, surfaced when a listed status
#                          has a captain-relevant verb OR a no-verb signal's crew
#                          is not provably working, unless afk is active
#   stale: <window>        terminal stale endpoint, a non-terminal stale whose crew is
#                          not provably working (surfaced at once), or a provably-
#                          working stale past the wedge threshold, unless afk active
#   check: <script>: <out> per-task check output, always actionable
#   heartbeat              fleet-scan backstop found an unsurfaced captain-relevant
#                          status, unless afk is active
# For normal supervision, re-arm after each printed reason by running
# bin/fm-watch-arm.sh through the harness's tracked background mechanism. Direct
# duplicate invocations of this script still no-op through the watcher singleton
# lock.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
mkdir -p "$STATE"

fm_watch_debug() {
  [ -n "${FM_WATCH_DEBUG:-}" ] || return 0
  printf '%s\t%s\n' \
    "$(date +%s.%N 2>/dev/null || date +%s)" \
    "$*" >> "${FM_WATCH_DEBUG_LOG:-$STATE/.watch-debug.log}"
}

# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
WATCH_LOCK="$STATE/.watch.lock"
WATCH_PATH="$SCRIPT_DIR/fm-watch.sh"
WATCH_SIGNAL_FASTPATH_PY="$SCRIPT_DIR/fm-watch-signal-fastpath.py"
WATCH_STALE_FASTPATH_PY="$SCRIPT_DIR/fm-watch-stale-fastpath.py"
WATCHER_STALE_GRACE=${FM_WATCHER_STALE_GRACE:-${FM_GUARD_GRACE:-300}}

run_signal_fastpath() {
  fm_lock_directory_only_platform || return 2
  command -v python >/dev/null 2>&1 || return 2
  [ -f "$WATCH_SIGNAL_FASTPATH_PY" ] || return 2
  python "$WATCH_SIGNAL_FASTPATH_PY"
}

run_stale_fastpath() {
  fm_lock_directory_only_platform || return 2
  command -v python >/dev/null 2>&1 || return 2
  [ -f "$WATCH_STALE_FASTPATH_PY" ] || return 2
  python "$WATCH_STALE_FASTPATH_PY"
}

state_has_meta() {
  compgen -G "$STATE/*.meta" >/dev/null
}

watch_lock_try_acquire() {
  local lockdir=$1 pid
  if ! fm_lock_directory_only_platform; then
    fm_lock_try_acquire "$lockdir"
    return "$?"
  fi

  FM_LOCK_HELD_PID=
  if mkdir "$lockdir" 2>/dev/null; then
    printf '%s\n' "${BASHPID:-$$}" > "$lockdir/pid" 2>/dev/null || {
      rm -f "$lockdir/pid" 2>/dev/null || true
      rmdir "$lockdir" 2>/dev/null || true
      return 1
    }
    return 0
  fi

  pid=$(fm_read_file_line "$lockdir/pid")
  if fm_pid_alive "$pid"; then
    FM_LOCK_HELD_PID=$pid
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$pid"; then
    FM_LOCK_HELD_PID=$pid
    return 1
  fi

  rm -rf -- "$lockdir" 2>/dev/null || true
  if mkdir "$lockdir" 2>/dev/null; then
    printf '%s\n' "${BASHPID:-$$}" > "$lockdir/pid" 2>/dev/null || {
      rm -f "$lockdir/pid" 2>/dev/null || true
      rmdir "$lockdir" 2>/dev/null || true
      return 1
    }
    return 0
  fi

  FM_LOCK_HELD_PID=$(fm_read_file_line "$lockdir/pid")
  return 1
}

watch_lock_release() {
  local lockdir=$1
  if ! fm_lock_directory_only_platform; then
    fm_lock_release "$lockdir"
    return 0
  fi
  if [ "$(fm_read_file_line "$lockdir/pid")" != "${BASHPID:-$$}" ]; then
    return 0
  fi
  rm -rf -- "$lockdir" 2>/dev/null || true
}

if ! watch_lock_try_acquire "$WATCH_LOCK"; then
  BEAT="$STATE/.last-watcher-beat"
  if [ -n "${FM_LOCK_HELD_PID:-}" ]; then
    if [ -e "$BEAT" ]; then
      beat_age=$(fm_path_age "$BEAT")
      if [ "$beat_age" -ge "$WATCHER_STALE_GRACE" ]; then
        echo "watcher: lock held by live pid $FM_LOCK_HELD_PID but heartbeat is stale for ${beat_age}s (>${WATCHER_STALE_GRACE}s); inspect or stop that watcher before re-arming." >&2
        exit 1
      fi
    elif [ "$(fm_path_age "$WATCH_LOCK")" -ge "$WATCHER_STALE_GRACE" ]; then
      echo "watcher: lock held by live pid $FM_LOCK_HELD_PID but no heartbeat exists; inspect or stop that watcher before re-arming." >&2
      exit 1
    fi
    echo "watcher: already running pid $FM_LOCK_HELD_PID"
  else
    echo "watcher: already running"
  fi
  exit 0
fi
watch_cleanup() {
  fm_watch_debug "exit-trap-start"
  watch_lock_release "$WATCH_LOCK"
  fm_watch_debug "exit-trap-done"
}
trap watch_cleanup EXIT
fm_watch_debug "lock-acquired pid=${BASHPID:-$$}"
# This watcher's own pid, as recorded in the lock by fm_lock_claim (which writes
# ${BASHPID:-$$} from this same main shell). Read directly, never via a command
# substitution, so it matches the stored holder pid for the self-eviction check.
WATCHER_PID=${BASHPID:-$$}
if state_has_meta; then
  if fastpath_reason=$(run_stale_fastpath 2>/dev/null); then
    fm_watch_debug "startup-stale-fastpath actionable"
    printf '%s\n' "$fastpath_reason"
    exit 0
  else
    fastpath_rc=$?
    case "$fastpath_rc" in
      10) fm_watch_debug "startup-stale-fastpath pending=no" ;;
      11) fm_watch_debug "startup-stale-fastpath absorbed" ;;
    esac
  fi
fi
if fastpath_reason=$(run_signal_fastpath 2>/dev/null); then
  fm_watch_debug "startup-fastpath actionable"
  printf '%s\n' "$fastpath_reason"
  exit 0
else
  fastpath_rc=$?
  case "$fastpath_rc" in
    10) fm_watch_debug "startup-fastpath pending=no" ;;
    11) fm_watch_debug "startup-fastpath absorbed" ;;
  esac
fi
# Shared wake classifier (captain-relevant verbs + signal/stale/heartbeat
# predicates), the SAME library the away-mode daemon uses, so the triage policy
# has one definition.
# shellcheck source=bin/fm-classify-lib.sh
. "$SCRIPT_DIR/fm-classify-lib.sh"
printf '%s\n' "$FM_HOME" > "$WATCH_LOCK/fm-home" || true
printf '%s\n' "$WATCH_PATH" > "$WATCH_LOCK/watcher-path" || true
fm_pid_identity "$WATCHER_PID" > "$WATCH_LOCK/pid-identity" 2>/dev/null || true
fm_watch_debug "identity-written pid=$WATCHER_PID"

# Portable stat. macOS (BSD) stat uses `-f <fmt>`; Linux (GNU) stat uses `-c <fmt>`.
# Do NOT use the `stat -f <fmt> ... || stat -c <fmt> ...` fallback form: on Linux
# `stat -f` is *filesystem* stat and writes a partial filesystem dump ("File: ...",
# "Blocks: ...") to stdout before failing, so the fallback's correct output gets
# appended to that garbage. Arithmetic under `set -u` then aborts on the stray
# token (e.g. the word "File" read as an unset variable), which silently kills the
# watcher mid-cycle. Detect the platform once and pick the right form.
if [ "$(uname)" = Darwin ]; then
  stat_mtime() { stat -f %m "$1" 2>/dev/null; }        # epoch seconds of mtime
  stat_sig()   { stat -f '%z:%Fm' "$1" 2>/dev/null; }   # size:mtime signature
else
  stat_mtime() { stat -c %Y "$1" 2>/dev/null; }
  stat_sig()   { stat -c '%s:%Y' "$1" 2>/dev/null; }
fi

POLL=${FM_POLL:-15}                   # seconds between cycles
HEARTBEAT=${FM_HEARTBEAT:-600}        # base seconds between heartbeat scans
HEARTBEAT_MAX=${FM_HEARTBEAT_MAX:-7200}  # heartbeat backoff cap
CHECK_INTERVAL=${FM_CHECK_INTERVAL:-300}  # seconds between *.check.sh sweeps
CHECK_TIMEOUT=${FM_CHECK_TIMEOUT:-30}     # seconds allowed per *.check.sh
SIGNAL_GRACE=${FM_SIGNAL_GRACE:-30}   # seconds to linger after a signal so trailing
                                      # signals (a status write, then the same turn's
                                      # turn-end hook) coalesce into one wake
# Busy signatures per harness, OR-ed. Extend via env when new adapters are verified.
# claude/codex: "esc to interrupt"; opencode: "esc interrupt"; pi: "Working...";
# grok: "Ctrl+c:cancel" (the mid-turn cancel hint in grok's keybind bar, shown iff a
# turn is running; absent when idle - verified grok 0.2.73, ASCII to avoid the
# locale fragility of matching grok's braille spinner glyph directly).
BUSY_REGEX=${FM_BUSY_REGEX:-'esc (to )?interrupt|Working\.\.\.|Ctrl\+c:cancel'}
# Always-on wake triage: most wakes during a long crew validation are benign (a
# working: note or turn-end while a pipeline runs, a no-change heartbeat). Rather
# than wake firstmate's LLM for each, this watcher classifies every wake in bash
# and ABSORBS the benign majority - it advances the suppression marker, logs to a
# debug log, and keeps blocking WITHOUT enqueuing or exiting. The no-verb turn-end
# / non-terminal-stale path is absorb-only-when-provably-working: such a wake is
# absorbed ONLY while the crew shows positive evidence it is still working (an
# actively-running no-mistakes step, or a busy pane, via crew_is_provably_working
# over fm-crew-state.sh); a crew that stopped its turn with no running pipeline and
# no busy pane is SURFACED, so a finish reported only through interactive pane menus
# (no done: status) is never swallowed. An ACTIONABLE wake (a captain-relevant
# signal, a no-verb signal whose crew is not provably working, any check, a
# terminal stale, a not-provably-working stale, a provably-working stale past the
# threshold, or anything unknown) is written to the durable queue and exits, which
# is what wakes the LLM through the background-task completion. The same classifier
# (fm-classify-lib.sh) backs the away-mode daemon; while state/.afk exists the
# daemon owns triage, so this watcher reverts to one-shot (enqueue + exit on every
# wake) and never double-triages - and never runs the costly provably-working read.
STALE_ESCALATE_SECS=${FM_STALE_ESCALATE_SECS:-240}  # idle secs before a non-terminal stale escalates as a possible wedge
TRIAGE_LOG="$STATE/.watch-triage.log"
TRIAGE_LOG_MAX_BYTES=${FM_WATCH_TRIAGE_LOG_MAX_BYTES:-262144}

# afk_present: 0 while the away-mode flag exists. When set, the daemon wraps this
# watcher and owns triage, so the watcher must behave one-shot (enqueue + exit on
# every wake) and let the daemon classify - never absorb here, or the daemon's
# digest/injection layer would never see the wake.
afk_present() { [ -e "$STATE/.afk" ]; }

# Append one line to the triage debug log explaining an absorbed (benign) wake,
# size-capped so a long benign stretch cannot grow it without bound. Best-effort:
# a logging hiccup never affects supervision.
triage_log() {
  local sz
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" >> "$TRIAGE_LOG" 2>/dev/null || return 0
  sz=$(wc -c < "$TRIAGE_LOG" 2>/dev/null | tr -d '[:space:]')
  case "$sz" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$sz" -ge "$TRIAGE_LOG_MAX_BYTES" ]; then
    tail -n 2000 "$TRIAGE_LOG" > "$TRIAGE_LOG.tmp" 2>/dev/null && mv -f "$TRIAGE_LOG.tmp" "$TRIAGE_LOG" 2>/dev/null
    rm -f "$TRIAGE_LOG.tmp" 2>/dev/null || true
  fi
}

hash_pane() {
  if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | cut -d' ' -f1; fi
}

# window_is_busy: 0 (busy) iff the task's harness is actively working. Prefers
# a backend's native semantic busy state (fm_backend_busy_state - herdr's
# agent.get; herdr-addendum "busy state" row, "the first backend where
# fm_session_busy_state gets real semantics"); falls back to the existing
# pane-tail regex ONLY when the backend reports unknown (tmux always does, so
# its path is unchanged byte-for-byte). <tail40> is the same bounded capture
# already read for hashing, so this adds no extra backend calls on the
# regex-fallback path.
window_is_busy() {  # <window> <tail40>
  local w=$1 tail40=$2 bs
  bs=$(fm_backend_busy_state "$(window_backend "$w")" "$w" 2>/dev/null)
  case "$bs" in
    busy) return 0 ;;
    idle) return 1 ;;
    *)
      printf '%s' "$tail40" | grep -v '^[[:space:]]*$' | tail -6 | grep -qiE "$BUSY_REGEX"
      ;;
  esac
}

window_kind() {
  local w=$1 meta mw kind
  for meta in "$STATE"/*.meta; do
    [ -e "$meta" ] || continue
    mw=$(grep '^window=' "$meta" | cut -d= -f2- || true)
    [ "$mw" = "$w" ] || continue
    kind=$(grep '^kind=' "$meta" | cut -d= -f2- || true)
    [ -n "$kind" ] || kind=ship
    echo "$kind"
    return 0
  done
  echo unknown
}

# window_backend: the backend recorded in the meta whose window= matches <w>,
# defaulting to tmux (absent backend= means tmux; the P1 compatibility
# contract) when no matching meta carries the field, or none matches at all.
window_backend() {
  local w=$1 meta mw backend
  for meta in "$STATE"/*.meta; do
    [ -e "$meta" ] || continue
    mw=$(grep '^window=' "$meta" | cut -d= -f2- || true)
    [ "$mw" = "$w" ] || continue
    backend=$(grep '^backend=' "$meta" | cut -d= -f2- || true)
    [ -n "$backend" ] || backend=tmux
    echo "$backend"
    return 0
  done
  echo tmux
}

recorded_windows() {
  local meta w seen=
  for meta in "$STATE"/*.meta; do
    [ -e "$meta" ] || continue
    w=$(grep '^window=' "$meta" | cut -d= -f2- || true)
    [ -n "$w" ] || continue
    case "$seen" in
      *"|$w|"*) continue ;;
    esac
    seen="$seen|$w|"
    printf '%s\n' "$w"
  done
}

# Exit reporting a wake. Consecutive heartbeats with no other wake in between
# mean an idle fleet, so the heartbeat interval backs off exponentially
# (base * 2^streak, capped at HEARTBEAT_MAX); any real wake resets the cadence.
wake() {
  case "$1" in
    heartbeat*) echo $(( $(fm_read_file_line "$STATE/.heartbeat-streak" || echo 0) + 1 )) > "$STATE/.heartbeat-streak" ;;
    *) echo 0 > "$STATE/.heartbeat-streak" ;;
  esac
  echo "$1"
  fm_watch_debug "wake-exit reason=$1"
  exit 0
}

# Check and heartbeat cadence must survive actionable exits and restarts: the
# watcher may be relaunched before in-memory counters reach their threshold on a
# busy fleet. Persist the schedule as file mtimes instead.
age_of() {  # seconds since file mtime; "due immediately" if missing
  local f=$1 m
  m=$(stat_mtime "$f") || { echo 999999; return; }
  echo $(( $(fm_epoch_seconds) - m ))
}

mark_time_file() {  # <file>
  printf '%s\n' "$(fm_epoch_seconds)" > "$1"
}

[ -e "$STATE/.last-heartbeat" ] || mark_time_file "$STATE/.last-heartbeat"

# Layer 2 + 3 signal scan: status files and turn-end markers. Each file is
# compared against a persisted size:mtime signature (.seen-*) rather than
# mtime-vs-a-startup-touch, so signals that land while no watcher is running
# are caught by the next one, and same-second writes cannot slip through a
# strict -nt comparison. Pure read: prints one "<seen-file>\t<sig>\t<file>"
# line per changed file. .seen-* is updated only after the wake is either
# surfaced or intentionally absorbed, so a watcher killed mid-cycle never
# swallows a signal.
scan_signals() {
  local f sig sf base seen
  for f in "$STATE"/*.status "$STATE"/*.turn-ended; do
    [ -e "$f" ] || continue
    sig=$(stat_sig "$f") || continue
    base=${f##*/}
    sf="$STATE/.seen-${base//./_}"
    seen=$(fm_read_file_line "$sf")
    [ "$sig" = "$seen" ] || printf '%s\t%s\t%s\n' "$sf" "$sig" "$f"
  done
  return 0
}

process_pending_signals() {
  local files reason pending_count i found f sf sig
  files=""
  pending_count=0
  pending_sfs=()
  pending_sigs=()
  pending_files=()
  while IFS=$(printf '\t') read -r sf sig f; do
    [ -n "$sf" ] || continue
    found=
    i=0
    while [ "$i" -lt "$pending_count" ]; do
      if [ "${pending_files[$i]}" = "$f" ]; then
        found=$i
        break
      fi
      i=$((i + 1))
    done
    if [ -n "${found:-}" ]; then
      pending_sfs[$found]=$sf
      pending_sigs[$found]=$sig
      continue
    fi
    pending_sfs[$pending_count]=$sf
    pending_sigs[$pending_count]=$sig
    pending_files[$pending_count]=$f
    pending_count=$((pending_count + 1))
    files="$files $f"
  done <<EOF
$pending
EOF
  [ "$pending_count" -gt 0 ] || return 1
  reason="signal:$files"
  # shellcheck disable=SC2086  # $files is a space-separated status-path list (ids carry no spaces)
  if afk_present || signal_reason_is_actionable $files || ! signal_crew_provably_working $files; then
    fm_watch_debug "signals-actionable files=$files"
    i=0
    while [ "$i" -lt "$pending_count" ]; do
      f=${pending_files[$i]}
      fm_wake_append signal "${f##*/}" "$reason" || exit 1
      i=$((i + 1))
    done
    fm_watch_debug "signals-enqueued"
    i=0
    while [ "$i" -lt "$pending_count" ]; do
      sf=${pending_sfs[$i]}
      sig=${pending_sigs[$i]}
      f=${pending_files[$i]}
      printf '%s' "$sig" > "$sf"
      mark_surfaced "$f"
      i=$((i + 1))
    done
    fm_watch_debug "signals-marked"
    wake "$reason"
  else
    i=0
    while [ "$i" -lt "$pending_count" ]; do
      sf=${pending_sfs[$i]}
      sig=${pending_sigs[$i]}
      printf '%s' "$sig" > "$sf"
      i=$((i + 1))
    done
    triage_log "absorbed benign $reason"
  fi
  return 0
}

run_check() {
  local c=$1
  if command -v timeout >/dev/null 2>&1; then
    timeout "$CHECK_TIMEOUT" bash "$c" 2>/dev/null || true
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$CHECK_TIMEOUT" bash "$c" 2>/dev/null || true
  else
    # shellcheck disable=SC2016  # single quotes are deliberate: Perl expands its own variables.
    perl -e 'my $t = shift; my $pid = fork; die "fork failed" unless defined $pid; if (!$pid) { setpgrp(0, 0); exec @ARGV } local $SIG{ALRM} = sub { kill "TERM", -$pid; select undef, undef, undef, 0.2; kill "KILL", -$pid; exit 124 }; alarm $t; waitpid $pid, 0; exit($? >> 8)' "$CHECK_TIMEOUT" bash "$c" 2>/dev/null || true
  fi
}

# Surfaced-marker bookkeeping for the heartbeat backstop. The watcher records the
# captain-relevant status line it SURFACED (woke firstmate for) in
# .hb-surfaced-<task>, the watcher's analogue of the daemon's
# .subsuper-seen-status. Unlike .seen-* (a size:mtime signature advanced on BOTH
# surface and absorb), .hb-surfaced is advanced ONLY on surface, so the heartbeat
# fleet-scan can tell apart a captain-relevant status that already woke firstmate
# from one that has not - the latter being a per-wake-path miss it must surface.
_hb_surfaced_path() {
  local task=$1
  task=${task//:/_}
  task=${task//\//_}
  task=${task//./_}
  printf '%s/.hb-surfaced-%s' "$STATE" "$task"
}

# Record a status file's captain-relevant last line as surfaced (no-op for a
# non-captain-relevant or empty status). Call AFTER the wake is enqueued, so the
# enqueue-before-suppress ordering holds for this marker too.
mark_surfaced() {  # <status-file>
  local f=$1 task last
  task=${f##*/}
  task=${task%.status}
  last=$(last_status_line "$f")
  [ -n "$last" ] || return 0
  status_is_captain_relevant "$last" || return 0
  printf '%s' "$last" > "$(_hb_surfaced_path "$task")"
}

# Mark every current captain-relevant status as surfaced. Called after the
# heartbeat backstop enqueues its wake, so the same statuses are not re-surfaced
# by the next heartbeat.
mark_all_captain_relevant_surfaced() {
  local f task last
  while IFS=$(printf '\t') read -r f task last; do
    [ -n "$f" ] || continue
    printf '%s' "$last" > "$(_hb_surfaced_path "$task")"
  done < <(scan_captain_relevant_statuses "$STATE")
}

# Cheap heartbeat fleet-scan (the always-on twin of the daemon's catch-all). 0 if
# any captain-relevant status has NOT already been surfaced to firstmate (its
# content differs from the .hb-surfaced-<task> marker). Pure detect, no side
# effects: the caller enqueues first, then marks surfaced. Because every
# captain-relevant signal/stale already marks itself surfaced when it wakes
# firstmate, this normally finds nothing and the heartbeat is absorbed; it
# surfaces only a captain-relevant status the per-wake path absorbed by mistake -
# the fail-safe backstop.
heartbeat_scan_finds_actionable() {
  local f task last surfaced
  while IFS=$(printf '\t') read -r f task last; do
    [ -n "$f" ] || continue
    surfaced=$(cat "$(_hb_surfaced_path "$task")" 2>/dev/null || true)
    [ "$surfaced" = "$last" ] && continue
    return 0
  done < <(scan_captain_relevant_statuses "$STATE")
  return 1
}

while :; do
  fm_watch_debug "loop-start pid=$WATCHER_PID"
  # Self-eviction: if the singleton lock no longer names this process, a second
  # watcher has taken over (e.g. a transient duplicate from a racy arm). Stand
  # down so the rightful singleton continues alone. The EXIT trap's release
  # no-ops because the lock pid is not ours, so the survivor's lock is untouched.
  # This makes any duplicate self-resolve within one poll instead of persisting
  # and doubling every wake.
  if [ "$(cat "$WATCH_LOCK/pid" 2>/dev/null || true)" != "$WATCHER_PID" ]; then
    exit 0
  fi

  # Liveness beacon for fm-guard.sh: a fresh mtime here means a watcher is
  # alive. Supervision scripts warn when this goes stale with tasks in flight.
  mark_time_file "$STATE/.last-watcher-beat"
  fm_watch_debug "beat-touched"

  # Slow per-task checks (firstmate writes these, e.g. a merged-PR poll).
  # Time-based via .last-check mtime so the cadence survives watcher restarts.
  # Evaluated BEFORE the signal scan: wake() exits the cycle, so a check placed
  # after the signal scan would be starved whenever a chatty sibling crewmate
  # keeps producing signals - the slow poll (e.g. merge detection) would then
  # never run until the fleet went quiet. Checks are due only every
  # CHECK_INTERVAL, so most cycles skip this block and fall straight through.
  if [ "$(age_of "$STATE/.last-check")" -ge "$CHECK_INTERVAL" ]; then
    for c in "$STATE"/*.check.sh; do
      [ -e "$c" ] || continue
      out=$(run_check "$c")
      if [ -n "$out" ]; then
        reason="check: $c: $out"
        fm_wake_append check "$c" "$reason" || exit 1
        mark_time_file "$STATE/.last-check"
        wake "$reason"
      fi
    done
    mark_time_file "$STATE/.last-check"
  fi

  # On the first changed signal, linger one grace period and re-scan before
  # classifying: a crewmate's final status write and the same turn's turn-end
  # hook land seconds apart, and reporting them as separate actionable wakes
  # costs a full firstmate turn each. The re-scan also picks up a newer
  # signature for an already-pending file (last write wins below).
  stale_fastpath_done=false
  if state_has_meta; then
    if fastpath_reason=$(run_stale_fastpath 2>/dev/null); then
      fm_watch_debug "stale-fastpath actionable"
      printf '%s\n' "$fastpath_reason"
      exit 0
    else
      fastpath_rc=$?
      case "$fastpath_rc" in
        10)
          stale_fastpath_done=true
          fm_watch_debug "stale-fastpath pending=no"
          ;;
        11)
          stale_fastpath_done=true
          fm_watch_debug "stale-fastpath absorbed"
          ;;
      esac
    fi
  fi
  signal_fastpath_done=false
  if fastpath_reason=$(run_signal_fastpath 2>/dev/null); then
    fm_watch_debug "signals-fastpath actionable"
    printf '%s\n' "$fastpath_reason"
    exit 0
  else
    fastpath_rc=$?
    case "$fastpath_rc" in
      10)
        signal_fastpath_done=true
        fm_watch_debug "signals-fastpath pending=no"
        ;;
      11)
        signal_fastpath_done=true
        fm_watch_debug "signals-fastpath absorbed"
        ;;
    esac
  fi
  if [ "$signal_fastpath_done" = false ]; then
    pending=$(scan_signals)
    if [ -n "$pending" ]; then
      fm_watch_debug "signals-scan pending=yes"
    else
      fm_watch_debug "signals-scan pending=no"
    fi
    if [ -n "$pending" ]; then
      sleep "$SIGNAL_GRACE"
      fm_watch_debug "signals-grace-complete"
      pending=$(printf '%s\n%s' "$pending" "$(scan_signals)")
      process_pending_signals
    fi
  fi

  # Layer 1 backbone: pane staleness. Two consecutive identical hashes with no busy
  # signature means the crewmate finished, is waiting, or is wedged. Each distinct
  # stale hash is surfaced, absorbed, or timed toward escalation once (.stale-*
  # remembers the hash already classified).
  if [ "$stale_fastpath_done" = false ] && [ -z "${FM_WATCH_BACKEND_LOADED:-}" ]; then
    # The DEFAULT EVENT SOURCE: this watcher's poll loop over the pull primitives
    # (capture, recorded windows, backend busy-state, and the BUSY_REGEX fallback)
    # synthesizes the signal/stale/check/heartbeat wake vocabulary for backends with
    # no native event push. tmux always reports unknown busy-state, preserving the
    # original regex path. herdr contributes native semantic busy-state through the
    # same poll loop until a future push subscription replaces this default source;
    # see bin/fm-backend.sh and docs/herdr-backend.md.
    # shellcheck source=bin/fm-backend.sh
    . "$SCRIPT_DIR/fm-backend.sh"
    FM_WATCH_BACKEND_LOADED=1
  fi
  while [ "$stale_fastpath_done" = false ] && IFS= read -r w; do
    # A secondmate idling on its own watcher is healthy. Its parent supervises
    # it through status writes and heartbeats, not pane-idle staleness.
    [ "$(window_kind "$w")" = secondmate ] && continue
    tail40=$(fm_backend_capture "$(window_backend "$w")" "$w" 40 2>/dev/null) || continue
    h=$(printf '%s' "$tail40" | hash_pane)
    key=$(printf '%s' "$w" | tr ':/.' '___')
    hf="$STATE/.hash-$key"
    cf="$STATE/.count-$key"
    sf="$STATE/.stale-$key"
    ssf="$STATE/.stale-since-$key"
    prev=$(cat "$hf" 2>/dev/null || true)
    if [ "$h" = "$prev" ]; then
      n=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 ))
      echo "$n" > "$cf"
      # Busy match: a backend's native semantic state when available (herdr),
      # else the last 6 non-blank lines only (the TUI footer area, where every
      # verified harness renders its busy indicator) so busy-looking strings
      # in displayed content cannot suppress stale detection.
      if [ "$n" -ge 2 ] && ! window_is_busy "$w" "$tail40"; then
        # The pane is idle/stale at hash $h. Triage decides whether this wakes
        # firstmate. Detection itself is unchanged from above.
        if afk_present; then
          # Daemon owns triage: one-shot per distinct stale hash, as before.
          if [ "$(cat "$sf" 2>/dev/null || true)" != "$h" ]; then
            fm_wake_append stale "$w" "stale: $w" || exit 1
            printf '%s' "$h" > "$sf"
            wake "stale: $w"
          fi
        elif stale_is_terminal "$w" "$STATE"; then
          # Terminal status under a stale pane: actionable -> enqueue + exit.
          if [ "$(cat "$sf" 2>/dev/null || true)" != "$h" ]; then
            fm_wake_append stale "$w" "stale: $w" || exit 1
            printf '%s' "$h" > "$sf"
            rm -f "$ssf"
            mark_surfaced "$STATE/$(window_to_task "$w" "$STATE").status"
            wake "stale: $w"
          fi
        else
          # Non-terminal stale: a crew gone quiet without a captain-relevant status.
          # Absorb-only-when-provably-working, decided once per distinct stale hash
          # (the costly run-step read runs only on first sight, never every poll):
          #   - provably working: an actively-running pipeline legitimately sits on a
          #     static pane (e.g. waiting on CI), so absorb and start the wedge timer
          #     so a genuinely frozen run still escalates past STALE_ESCALATE_SECS;
          #   - NOT provably working: no running pipeline, idle pane, no busy
          #     signature - the crew has STOPPED. Surface immediately so firstmate
          #     peeks (it may be done via an interactive menu that wrote no done:
          #     status, waiting on a decision, or wedged) instead of leaving the
          #     finish to wait out the timer.
          if [ "$(cat "$sf" 2>/dev/null || true)" != "$h" ]; then
            if crew_is_provably_working "$(window_to_task "$w" "$STATE")"; then
              printf '%s' "$h" > "$sf"
              date +%s > "$ssf"
              triage_log "absorbed non-terminal stale (provably working): $w"
            else
              fm_wake_append stale "$w" "stale: $w" || exit 1
              printf '%s' "$h" > "$sf"
              rm -f "$ssf"
              wake "stale: $w"
            fi
          else
            since=$(cat "$ssf" 2>/dev/null || true)
            case "$since" in
              ''|*[!0-9]*)
                date +%s > "$ssf"
                triage_log "absorbed non-terminal stale timer reset: $w"
                ;;
              *)
                age=$(( $(date +%s) - since ))
                if [ "$age" -ge "$STALE_ESCALATE_SECS" ]; then
                  fm_wake_append stale "$w" "stale: $w (idle ${age}s, possible wedge)" || exit 1
                  rm -f "$ssf"
                  wake "stale: $w (idle ${age}s, possible wedge)"
                fi
                ;;
            esac
          fi
        fi
      else
        # Pane busy or not yet stably stale: it is alive, so clear any pending
        # non-terminal-stale escalation timer.
        rm -f "$ssf"
      fi
    else
      printf '%s' "$h" > "$hf"
      echo 0 > "$cf"
      # Pane content changed: the crew is active again, so reset the escalation timer.
      rm -f "$ssf"
    fi
  done < <(recorded_windows)

  # Heartbeat: the watcher runs a cheap fleet-scan at a regular cadence no matter
  # what. Time-based via .last-heartbeat mtime; interval doubles per consecutive
  # no-change heartbeat (idle fleet) up to HEARTBEAT_MAX, and resets on any
  # surfaced non-heartbeat wake.
  streak=$(cat "$STATE/.heartbeat-streak" 2>/dev/null || echo 0)
  [ "$streak" -gt 12 ] && streak=12
  hb=$(( HEARTBEAT * (1 << streak) ))
  [ "$hb" -gt "$HEARTBEAT_MAX" ] && hb=$HEARTBEAT_MAX
  if [ "$(age_of "$STATE/.last-heartbeat")" -ge "$hb" ]; then
    # Triage: in always-on mode a heartbeat is benign unless the cheap fleet-scan
    # turns up a captain-relevant status the per-wake path missed. Absorb the
    # no-change case (advance the schedule and back off exactly as wake() would,
    # without exiting); the away-mode daemon, when present, owns triage and wants
    # every heartbeat.
    if afk_present; then
      fm_wake_append heartbeat heartbeat heartbeat || exit 1
      mark_time_file "$STATE/.last-heartbeat"
      wake "heartbeat"
    elif heartbeat_scan_finds_actionable; then
      # Backstop: a captain-relevant status the per-wake path absorbed by mistake.
      # Enqueue first, then mark every captain-relevant status surfaced so the next
      # heartbeat does not re-fire them (enqueue-before-suppress preserved).
      fm_wake_append heartbeat heartbeat heartbeat || exit 1
      mark_time_file "$STATE/.last-heartbeat"
      mark_all_captain_relevant_surfaced
      wake "heartbeat"
    else
      mark_time_file "$STATE/.last-heartbeat"
      echo $(( $(cat "$STATE/.heartbeat-streak" 2>/dev/null || echo 0) + 1 )) > "$STATE/.heartbeat-streak"
      triage_log "absorbed heartbeat (no captain-relevant change)"
    fi
  fi

  sleep "$POLL"
done
