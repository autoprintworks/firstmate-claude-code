#!/usr/bin/env bash
# fm-composer-lib.sh — backend-agnostic composer/busy classification.
#
# ONE source of truth for the parts of composer detection that depend only on
# the CAPTURED TEXT, not on how it was captured. bin/fm-tmux-lib.sh and
# bin/fm-wezterm-lib.sh each own their backend's capture I/O (tmux capture-pane
# vs wezterm cli get-text) and delegate every classification decision here, so
# the two cannot drift apart the way the daemon and fm-send.sh once did.
#
# Extracted from bin/fm-tmux-lib.sh with NO behavior change: fm_tmux_strip_ghost
# and fm_tmux_composer_state still exist under their old names and still return
# the same verdicts for the same input. The incident history that shaped this
# logic (afk-invx-i5 bordered-composer false "pending"; composer-robust dim
# ghost text) lives in fm-tmux-lib.sh's header and applies verbatim here.
#
# All functions are `set -u` / `set -e` safe so they can be sourced into either
# the away-mode daemon or a backend adapter.

# Busy footers per harness (mirror fm-watch.sh). claude/codex: "esc to
# interrupt"; opencode: "esc interrupt"; pi: "Working..."; grok: "Ctrl+c:cancel"
# (grok's mid-turn cancel hint, shown iff a turn is running - verified grok 0.2.73).
FM_COMPOSER_BUSY_REGEX_DEFAULT='esc (to )?interrupt|Working\.\.\.|Ctrl\+c:cancel'

# fm_composer_busy_regex: the active busy-footer pattern, honoring the
# FM_BUSY_REGEX per-harness override that fm-watch.sh and the daemon also read.
fm_composer_busy_regex() {
  printf '%s' "${FM_BUSY_REGEX:-$FM_COMPOSER_BUSY_REGEX_DEFAULT}"
}

# fm_composer_python: a python interpreter that ACTUALLY RUNS, or empty.
#
# `command -v python3` is not sufficient on Windows: Microsoft ships an App
# Execution Alias at
# %LOCALAPPDATA%\Microsoft\WindowsApps\python3 that exists as a file, satisfies
# command -v, and then refuses to execute with "Python was not found; run
# without arguments to install from the Microsoft Store". A backend that trusts
# command -v silently loses every JSON lookup it makes — the wezterm adapter
# read an empty pane record and reported composer state `unknown` forever, which
# degrades to "crewmate unreadable" rather than failing loudly. So each candidate
# is probed by RUNNING it.
#
# The result is cached in FM_COMPOSER_PYTHON for the life of the shell: the
# watcher calls this on every poll and a per-tick interpreter probe would double
# the cost of the loop. Set FM_PYTHON to pin an interpreter explicitly.
fm_composer_python() {
  if [ -n "${FM_COMPOSER_PYTHON:-}" ]; then
    printf '%s' "$FM_COMPOSER_PYTHON"
    return 0
  fi
  local cand
  for cand in ${FM_PYTHON:-} python3 python py; do
    if "$cand" -c 'import sys, json' >/dev/null 2>&1; then
      FM_COMPOSER_PYTHON="$cand"
      printf '%s' "$cand"
      return 0
    fi
  done
  return 0
}

# fm_composer_strip_ghost: remove dim/faint (ANSI SGR 2) styled runs from one
# captured composer line, then drop any remaining escape sequences, leaving only
# the plain, normal-intensity text — the text a human actually typed. Dim/faint
# runs are ghost/placeholder text (e.g. claude's predicted-next-prompt
# suggestion) that fills an otherwise-empty composer and must never read as
# pending input. Reads the styled line on stdin (from a backend's styled capture)
# and prints plain text on stdout. LC_ALL=C makes awk walk bytes, so multibyte
# glyphs (e.g. ❯) and dim runs alike pass through or drop intact without
# locale-dependent character classes. A reset (SGR 0) or normal-intensity
# (SGR 22) ends a dim run; codes are processed left to right within a sequence
# so "ESC[0;2m" (reset then dim) reads as dim.
#
# Backend-agnostic by construction: it consumes ANSI-styled text, which both
# `tmux capture-pane -e` and `wezterm cli get-text --escapes` produce.
fm_composer_strip_ghost() {
  LC_ALL=C awk '
    function sgr_code(v, b) {
      b = v
      sub(/:.*/, "", b)
      if (b == "") b = "0"
      return b
    }
    function skip_color_payload(a, p, k, mode, code) {
      if (index(a[p], ":") > 0) return p
      if (p >= k) return p
      mode = a[p + 1]
      code = sgr_code(mode)
      if (index(mode, ":") > 0) return p + 1
      if (code == "5") return p + 2
      if (code == "2") return p + 4
      return p + 1
    }
    {
      line = $0; out = ""; dim = 0; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\033") {            # ESC: consume a CSI ... final-byte sequence
          j = i + 1
          if (substr(line, j, 1) == "[") {
            j++; params = ""
            while (j <= n) {
              cc = substr(line, j, 1)
              if (cc ~ /[@-~]/) break
              params = params cc; j++
            }
            if (j <= n && substr(line, j, 1) == "m") {   # SGR: update dim/faint state
              if (params == "") params = "0"
              k = split(params, a, ";")
              for (p = 1; p <= k; p++) {
                v = a[p]; code = sgr_code(v)
                if (code == "38" || code == "48" || code == "58") {
                  p = skip_color_payload(a, p, k)
                } else if (code == "2") dim = 1
                else if (code == "0" || code == "22") dim = 0
              }
            }
            if (j <= n) { i = j + 1; continue }
          }
          i = i + 1; continue          # lone/other ESC: drop the ESC byte only
        }
        if (dim == 0) out = out c        # keep only normal-intensity bytes
        i++
      }
      print out
    }
  '
}

# fm_composer_classify_line: classify ONE already-ghost-stripped composer line as
# `empty` (no pending input — safe to inject, and the positive acknowledgement
# that a submit landed) or `pending` (real, unsubmitted text). Pure text
# classification: no capture, no backend calls, no I/O.
#
# Strips the harness's box-drawing composer borders ("│ … │", heavy "┃", or a
# plain ASCII "|") using literal-string substitution (bash 3.2 safe,
# locale-independent — no \u escapes, no multibyte character classes), then asks
# whether anything real is left.
fm_composer_classify_line() {  # <ghost-stripped-line> -> empty|pending
  local line=$1 stripped
  stripped=${line//│/}      # U+2502 light vertical (claude)
  stripped=${stripped//┃/}  # U+2503 heavy vertical
  stripped=${stripped//|/}  # ASCII pipe
  # Trim surrounding whitespace.
  stripped="${stripped#"${stripped%%[![:space:]]*}"}"
  stripped="${stripped%"${stripped##*[![:space:]]}"}"
  # Nothing left inside the box = empty composer.
  [ -n "$stripped" ] || { printf 'empty'; return 0; }
  if [ -n "${FM_COMPOSER_IDLE_RE:-}" ] \
     && printf '%s' "$stripped" | grep -qiE "$FM_COMPOSER_IDLE_RE"; then
    printf 'empty'; return 0
  fi
  # Just a bare prompt glyph = empty composer (idle).
  case "$stripped" in
    '>'|'❯'|'$'|'%'|'#') printf 'empty'; return 0 ;;
  esac
  # A busy footer landing on the cursor line is not pending input.
  if printf '%s' "$stripped" | grep -qiE "$(fm_composer_busy_regex)"; then
    printf 'empty'; return 0
  fi
  printf 'pending'; return 0
}

# fm_composer_tail_is_busy: 0 iff the last few non-blank lines of a captured
# tail show a busy footer (an agent mid-turn). Reads the tail on stdin. Mirrors
# the 6-of-40-line scan fm-watch.sh and fm_pane_is_busy already performed.
fm_composer_tail_is_busy() {
  grep -v '^[[:space:]]*$' | tail -6 | grep -qiE "$(fm_composer_busy_regex)"
}
