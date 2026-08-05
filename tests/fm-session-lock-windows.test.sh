#!/usr/bin/env bash
# Behavior tests for the Windows arm of bin/fm-session-lock-lib.sh.
#
# On MSYS/Git Bash the harness is a native Windows process the shell's own pid
# namespace cannot see, so the library resolves and liveness-checks it through a
# separate path. These tests drive that path through the library's public
# functions with a stubbed `ps` and a forced $OSTYPE, so they run identically on
# Windows and on POSIX.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-session-lock-windows)
# fm_test_tmproot registers its cleanup trap inside the command substitution's
# own subshell, so the directory is removed the moment it is echoed back. Other
# suites hide this by immediately mkdir -p'ing fixture subdirectories; this one
# writes a file at the root first, so it recreates the root explicitly.
mkdir -p "$TMP_ROOT"
LIB="$ROOT/bin/fm-session-lock-lib.sh"

# A CLI claude and a Claude Desktop claude, as `ps -W` reports them:
# PID PPID PGID WINPID TTY UID STIME COMMAND, COMMAND a path containing spaces.
CLI_IMAGE='C:\Users\Glyn\.local\bin\claude.exe'
DESKTOP_IMAGE='C:\Program Files\WindowsApps\Claude_1.0.0.0_x64\app\claude.exe'
PS_W_TABLE="$TMP_ROOT/ps-w.txt"
cat > "$PS_W_TABLE" <<EOF
     4048       1    4048      19556  ?    197609 01:02:03 $CLI_IMAGE
     4049       1    4049      20804  ?    197609 01:02:03 $DESKTOP_IMAGE
EOF

# Stub `ps`, recording every call so a test can prove a path stayed spawn-free.
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
PS_MARKER="$TMP_ROOT/ps-called"
cat > "$FAKEBIN/ps" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_PS_MARKER"
[ "${1:-}" != "-W" ] || cat "$FM_TEST_PS_W"
exit 0
SH
chmod +x "$FAKEBIN/ps"
export FM_TEST_PS_MARKER="$PS_MARKER" FM_TEST_PS_W="$PS_W_TABLE"
PATH="$FAKEBIN:$PATH"

# Call a library function under a chosen platform. $OSTYPE cannot be inherited
# from the environment - bash assigns it at startup - so the probe sets the real
# variable from FM_TEST_OSTYPE before sourcing the library it is testing.
PROBE="$TMP_ROOT/probe.sh"
cat > "$PROBE" <<'SH'
#!/usr/bin/env bash
set -u
[ -z "${FM_TEST_OSTYPE:-}" ] || OSTYPE=$FM_TEST_OSTYPE
# shellcheck source=/dev/null
. "$FM_LIB"
"$@"
SH
chmod +x "$PROBE"

# probe <ostype> <lib> <fn> [args...] leaves stdout in $PROBE_OUT and the exit
# code in $RC. It must be called directly, never inside a command substitution,
# or both globals would be set in a subshell and lost.
#
# Set PENV to extra VAR=VALUE assignments for the probed session: an assignment
# prefix on a shell function reaches the function but not the child process it
# runs, so those must go through env.
RC=0
PROBE_OUT=
PENV=(FM_TEST_PROBE=1) # never empty: "${PENV[@]}" under set -u needs one element
probe() {
  local ostype=$1 lib=$2
  shift 2
  RC=0
  PROBE_OUT=$(env FM_TEST_OSTYPE="$ostype" FM_LIB="$lib" "${PENV[@]}" bash "$PROBE" "$@" 2>/dev/null) || RC=$?
}

# --- applicability ----------------------------------------------------------

for os in msys cygwin mingw64; do
  probe "$os" "$LIB" fm_win_applicable
  [ "$RC" -eq 0 ] || fail "fm_win_applicable must apply on $os (got rc $RC)"
done
for os in linux-gnu darwin24; do
  probe "$os" "$LIB" fm_win_applicable
  [ "$RC" -eq 2 ] || fail "fm_win_applicable must return 2 (not this platform) on $os (got rc $RC)"
done
pass "applicability covers MSYS/Cygwin/MinGW and defers elsewhere"

# --- resolution takes the harness-exported pid, without spawning -------------

: > "$PS_MARKER"
PENV=(CLAUDE_PID=19556)
probe msys "$LIB" fm_harness_ancestry_pid
[ "$RC" -eq 0 ] || fail "resolution must succeed from CLAUDE_PID (rc $RC)"
[ "$PROBE_OUT" = "19556" ] || fail "resolution must return CLAUDE_PID, got '$PROBE_OUT'"
[ ! -s "$PS_MARKER" ] || fail "resolution must not spawn ps; it runs on every Stop hook"
pass "Windows resolution returns the harness-exported pid without spawning"

# --- resolution fails closed rather than falling back to the POSIX walk ------

ISOLATED="$TMP_ROOT/isolated/bin"
mkdir -p "$ISOLATED"
cp "$LIB" "$ISOLATED/fm-session-lock-lib.sh"
PENV=(CLAUDE_PID=)
probe msys "$ISOLATED/fm-session-lock-lib.sh" fm_harness_ancestry_pid
[ "$RC" -ne 0 ] || fail "resolution with no exported pid and no native helper must fail"
[ -z "$PROBE_OUT" ] || fail "failed resolution must print nothing, got '$PROBE_OUT'"
PENV=(CLAUDE_PID=not-a-pid)
probe msys "$ISOLATED/fm-session-lock-lib.sh" fm_harness_ancestry_pid
[ "$RC" -ne 0 ] || fail "a malformed CLAUDE_PID must not resolve"
pass "Windows resolution fails closed when no harness pid can be proved"

# --- liveness matches the full image path, not the basename -----------------

PENV=(CLAUDE_CODE_EXECPATH= CLAUDE_PID=)
probe msys "$LIB" fm_harness_pid_alive 19556
[ "$RC" -ne 0 ] || fail "liveness must not pass without an expected image to compare against"

alive() {
  PENV=(CLAUDE_CODE_EXECPATH="$CLI_IMAGE")
  probe msys "$LIB" fm_harness_pid_alive "$1"
  return "$RC"
}
alive 19556 || fail "liveness must accept the CLI claude this session runs from"
! alive 20804 || fail "liveness must reject Claude Desktop's own claude.exe: a basename match makes a recycled pid read as a live harness forever"
! alive 31337 || fail "liveness must reject a pid absent from the process table"
! alive "not-a-pid" || fail "liveness must reject a non-numeric pid"
! alive "" || fail "liveness must reject an empty pid"
pass "Windows liveness matches the full image path and rejects a same-named bystander"

# --- POSIX platforms are untouched ------------------------------------------

: > "$PS_MARKER"
PENV=(CLAUDE_PID=19556)
probe linux-gnu "$LIB" fm_harness_ancestry_pid
[ "$PROBE_OUT" != "19556" ] || fail "a POSIX session must resolve by ancestry walk, never from CLAUDE_PID"
! grep -q -- '-W' "$PS_MARKER" 2>/dev/null || fail "a POSIX session must never consult ps -W"

: > "$PS_MARKER"
PENV=(CLAUDE_CODE_EXECPATH="$CLI_IMAGE")
probe linux-gnu "$LIB" fm_harness_pid_alive 19556
! grep -q -- '-W' "$PS_MARKER" 2>/dev/null || fail "POSIX liveness must never consult ps -W"
pass "POSIX platforms fall through to the unchanged ancestry walk and liveness check"
