#!/usr/bin/env bash
# Shared session-lock harness identity.
#
# ONE owner of the "which verified-harness process holds this home's session
# lock, and does the current process descend from that same harness?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock;
# bin/fm-claude-stop-autoarm.sh uses it to prove a Stop hook fires inside the
# lock-owning primary session before it may arm or rewake.
# This file is sourced by scripts and has no side effects on source.

# Known harness command names; extend when a new adapter is verified.
FM_HARNESS_RE='claude|codex|opencode|grok|kimi|^pi$|^pi-signed$'

# --- Windows arm ------------------------------------------------------------
#
# On MSYS/Git Bash the harness is a NATIVE Windows process living in a pid
# namespace the shell does not share, so every POSIX primitive the rest of this
# file relies on misses it: `kill -0` reports no such process, /proc/<pid> does
# not exist, and `ps -o comm= -p` cannot see it at all. The functions below are
# the Windows substitutes for the two operations that matter - resolve this
# session's harness pid, and decide whether a recorded pid is still a live
# harness.
#
# Applicability returns 2 for "not this platform" so a caller falls THROUGH to
# the POSIX path instead of treating it as a failure. It reads $OSTYPE rather
# than spawning `uname`, because fm_session_lock_owned_by_self runs on every
# Claude Stop hook and that spawn dominated its measured cost.

fm_win_applicable() {
  case "$OSTYPE" in
    msys* | cygwin* | mingw*) return 0 ;;
    *) return 2 ;;
  esac
}

fm_win_ancestry_helper() {
  local lib_dir
  lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  printf '%s/../firstmate_gui_agnostic/win_ancestry.py\n' "$lib_dir"
}

# The full native image path of a live native pid, or empty.
# `ps -W` columns are PID PPID PGID WINPID TTY UID STIME COMMAND, and COMMAND is
# a Windows path that contains spaces, so take fields 8..NF rather than $8.
# PPID is reported as 0 for every native process, so this is a liveness and
# image source only, never an ancestry source.
fm_win_image_of() {
  local pid=$1
  case "$pid" in '' | *[!0-9]*) return 1 ;; esac
  ps -W 2>/dev/null | awk -v p="$pid" '
    $4 == p { for (i = 8; i <= NF; i++) printf "%s%s", $i, (i < NF ? " " : "\n"); exit }
  '
}

# Compare Windows paths: separators differ between sources and the filesystem is
# case-insensitive.
fm_win_path_norm() {
  printf '%s' "$1" | tr '\\A-Z' '/a-z'
}

# The harness pid owning this session, or empty.
#
# The claude CLI exports its own pid as CLAUDE_PID into every Bash tool call and
# every hook invocation, which is exactly the pid an ancestry walk finds, so
# take it for free where it is present. Harnesses that do not export a pid fall
# back to the native Toolhelp32 walk.
#
# This deliberately does NOT check that the pid is alive. It is this process's
# own ancestor, so it is trivially alive, and fm_session_lock_owned_by_self runs
# on every Stop hook - keeping resolution spawn-free is what makes that cheap.
fm_win_harness_pid() {
  fm_win_applicable || return $?
  case "${CLAUDE_PID:-}" in
    '' | *[!0-9]*) ;;
    *)
      printf '%s\n' "$CLAUDE_PID"
      return 0
      ;;
  esac
  local helper start
  helper=$(fm_win_ancestry_helper)
  [ -r "$helper" ] || return 1
  command -v python >/dev/null 2>&1 || return 1
  start=$$
  [ ! -r "/proc/$$/winpid" ] || start=$(cat "/proc/$$/winpid" 2>/dev/null || printf '%s' "$$")
  python "$helper" --start "$start" --match-re "$FM_HARNESS_RE" 2>/dev/null
}

# The image path a live harness of THIS session runs from, used as the expected
# value for every Windows liveness check.
fm_win_expected_image() {
  if [ -n "${CLAUDE_CODE_EXECPATH:-}" ]; then
    printf '%s\n' "$CLAUDE_CODE_EXECPATH"
    return 0
  fi
  local self
  self=$(fm_win_harness_pid) || return 1
  fm_win_image_of "$self"
}

# True if $1 is a live harness process.
#
# Matches the FULL IMAGE PATH, not the basename. Claude Desktop ships its own
# claude.exe and runs about twenty of them, so a basename match accepts an
# unrelated process: a lock left by a dead session whose pid is later reused by
# one of those reads as held-by-a-live-harness forever, and acquisition is
# refused permanently with no diagnosable cause.
#
# Known limit: the expected image is this session's own harness, so a lock held
# by a live session running a DIFFERENT harness reads as stale. Two harnesses
# driving one FM_HOME concurrently is not a supported configuration today.
fm_win_pid_alive() {
  local pid=$1 expect image
  case "$pid" in '' | *[!0-9]*) return 1 ;; esac
  expect=$(fm_win_expected_image) || return 1
  [ -n "$expect" ] || return 1
  image=$(fm_win_image_of "$pid") || return 1
  [ -n "$image" ] || return 1
  [ "$(fm_win_path_norm "$image")" = "$(fm_win_path_norm "$expect")" ]
}

# Walk the current process ancestry (up to 16 hops) and print a harness pid.
# For every harness except Claude, the first match wins (innermost pid), which
# is where e.g. Pi's shared signed-wrapper ancestry actually holds the session:
# a "pi-signed" launcher can be the direct parent of the inner "pi" engine
# pid that owns the lock, and the wrapper pid above it is not that owner.
# Claude Code's bg-spare hook worker chain is the opposite shape: it nests
# several claude-named processes directly parent-child with no non-harness
# process between them, and the lock is held by the outermost pid of that
# run. So once a claude-named match is found, this keeps walking past it
# looking for a still-more-ancestral claude-named match, and stops the
# instant a non-match follows - never walking past that gap to an unrelated
# claude-named process further up the real process tree (e.g. the live
# session that launched a test as its own subprocess). The harness pid lives
# as long as the session, unlike the transient subshell pid of any one tool
# call.
fm_harness_ancestry_pid() {
  local pid=$$ comm args best='' bc extending=0 hit=0 is_claude=0 win_pid win_rc
  # Windows resolves natively; a shell-visible walk cannot leave the MSYS pid
  # namespace. Applicable-but-unresolved must not fall through to that walk.
  if win_pid=$(fm_win_harness_pid); then
    case "$win_pid" in
      '' | *[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$win_pid"
    return 0
  else
    win_rc=$?
  fi
  [ "$win_rc" -eq 2 ] || return 1
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    bc=$(basename -- "$comm")
    hit=0; is_claude=0
    if printf '%s' "$bc" | grep -qE "$FM_HARNESS_RE"; then
      hit=1
      case "$bc" in *claude*) is_claude=1 ;; esac
    else
      # Bare interpreter (e.g. node): match the harness name in its script path.
      case "$comm" in
        *node*|*python*)
          if printf '%s' "$args" | grep -qE "$FM_HARNESS_RE"; then
            hit=1
            case "$args" in *claude*) is_claude=1 ;; esac
          fi
          ;;
      esac
    fi
    if [ "$hit" -eq 1 ]; then
      best="$pid"
      if [ "$is_claude" -eq 1 ]; then
        extending=1
      else
        break
      fi
    elif [ "$extending" -eq 1 ]; then
      break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
  done
  [ -n "$best" ] && { echo "$best"; return 0; }
  return 1
}

# True if $1 is a live process that looks like a verified harness.
fm_harness_pid_alive() {
  local pid=$1 comm args
  if fm_win_applicable; then
    fm_win_pid_alive "$pid"
    return
  fi
  kill -0 "$pid" 2>/dev/null || return 1
  comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
  if printf '%s' "$(basename -- "$comm")" | grep -qE "$FM_HARNESS_RE"; then
    return 0
  fi
  case "$comm" in
    *node*|*python*)
      args=$(ps -o args= -p "$pid" 2>/dev/null)
      printf '%s' "$args" | grep -qE "$FM_HARNESS_RE"
      ;;
    *) return 1 ;;
  esac
}

# True when state dir $1 holds a session lock whose pid is the harness ancestor
# of the current process: this script runs inside the session that owns the
# home's fleet lock. A missing lock, a lock held by another live harness, or an
# ancestry that cannot be resolved all fail closed.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid my_pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  my_pid=$(fm_harness_ancestry_pid) || return 1
  [ "$my_pid" = "$lock_pid" ]
}
