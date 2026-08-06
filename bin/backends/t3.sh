#!/usr/bin/env bash
# bin/backends/t3.sh - the T3 Code adapter.
#
# A second UNATTENDED backend alongside bin/backends/claude-bg.sh, and the first
# one whose crewmates live inside somebody else's application. A T3 Code
# crewmate is a THREAD in the T3 Code desktop app: the human can see it, scroll
# it, and type into it while firstmate supervises it, which is the thing
# claude-bg gives up and wezterm pays for with a whole OS window per crewmate.
#
# Backend comparison, so the choice is explicit at config time:
#
#   property            wezterm                   claude-bg          t3
#   -----------------   -----------------------   ----------------   ----------------
#   crewmate is         a visible OS window       a headless proc    a T3 Code thread
#   human can type in   yes                       no                 yes (in the app)
#   busy detection      pane regex + composer     JSON `state`       session.status
#   survives GUI close  no                        yes                no (server owns it)
#   permission prompts  answered in the pane      pre-authorized     answered in the app
#   teardown            kill-pane (exact)         best-effort        stop + archive
#
# Target identity: the T3 THREAD UUID, which firstmate mints rather than parses
# back — the same deterministic-identity trick claude-bg uses, so a crash between
# spawn and record cannot orphan an unfindable crewmate. UUIDs contain no colon,
# so fm_backend_resolve_selector's three-form dispatch keeps working untouched.
#
# Every wire operation goes through bin/fm-t3, which owns the HTTP surface, the
# bearer credential, and the exit-code contract. This file's only job is to speak
# firstmate's vocabulary on top of it, so the words `empty`, `send-failed`,
# `busy`, `blocked`, `idle`, `exited` and `unknown` are produced HERE and never
# travel over the wire.
#
# shellcheck source=bin/fm-composer-lib.sh
. "$FM_BACKEND_LIB_DIR/fm-composer-lib.sh"

FM_T3_NODE="${FM_T3_NODE:-node}"
FM_T3_HELPER="${FM_T3_HELPER:-$FM_BACKEND_LIB_DIR/fm-t3}"

# fm_backend_t3_helper: one helper invocation. Exit codes pass through
# unchanged, because callers here distinguish 3 (target gone) from 1 (transport
# or credential failure) and must not have them flattened.
fm_backend_t3_helper() {  # <mode> [args...]
  "$FM_T3_NODE" "$FM_T3_HELPER" "$@"
}

# --- pull primitives ---------------------------------------------------------

# fm_backend_t3_capture: render the last <lines> conversational lines of the
# thread as plain text. The analogue of a pane capture, and what fm-peek.sh and
# the watcher read.
#
# It renders from the thread's structured snapshot rather than any terminal
# buffer, so the output is inherently escape-free — the "no raw -e bytes reach
# firstmate context" guarantee the tmux path has to enforce deliberately is free
# here, exactly as it is on claude-bg.
fm_backend_t3_capture() {  # <thread-id> <lines> [expected-label]
  fm_backend_t3_helper capture "$1" "${2:-40}"
}

fm_backend_t3_current_path() {  # <thread-id>
  fm_backend_t3_helper worktree "$1" 2>/dev/null || true
}

# fm_backend_t3_busy_state: REAL busy semantics, not `unknown`.
#
# The T3 server reports a session status directly, so a crewmate mid-turn is
# distinguished from an idle one without parsing a single rendered byte. The
# `blocked` arm is the one that matters most: T3 surfaces pending approvals and
# pending user input as first-class flags, so a crewmate waiting on a permission
# gate is reported as blocked rather than quietly read as idle. A supervisor must
# escalate that, not wait it out.
#
# A brand-new thread has no session until its first turn and reads as `unknown`;
# every spawn passes through that state, so it is not an error condition.
fm_backend_t3_busy_state() {  # <thread-id>
  local state
  state=$(fm_backend_t3_helper busy "$1" 2>/dev/null) || state=
  case "$state" in
    busy|blocked|idle|exited) printf '%s' "$state" ;;
    *) printf 'unknown' ;;
  esac
}

# --- push primitives ---------------------------------------------------------

# fm_backend_t3_send_text_submit: deliver <text> as one new turn.
#
# There is no composer and no Enter key: a turn is a single command that the
# server either accepts or rejects, so there is nothing to retype and nothing to
# retry. The <retries>/<enter-sleep>/<settle> arguments are accepted and ignored
# to keep the dispatcher signature uniform, exactly as on claude-bg.
#
# The verdict is the literal word `empty` (delivered) or `send-failed`, and the
# function exits 0 either way — callers treat an exact `empty` as confirmed
# delivery and anything else as a failed send.
fm_backend_t3_send_text_submit() {  # <thread-id> <text> <retries> <enter-sleep> <settle> [expected-label]
  local id=$1 text=$2
  if fm_backend_t3_helper send "$id" "$text" >/dev/null 2>&1; then
    printf 'empty'
  else
    printf 'send-failed'
  fi
}

# fm_backend_t3_send_key: a thread has no keyboard. Escape/C-c (interrupt) has no
# supported equivalent on this surface, so this fails loudly rather than silently
# no-op'ing and letting the stuck-crewmate playbook believe it interrupted
# something. Enter is a no-op success because submission already happened in
# send_text_submit.
fm_backend_t3_send_key() {  # <thread-id> <key> [expected-label]
  case "$2" in
    Enter) return 0 ;;
    *) echo "error: t3 has no key channel; '$2' is unsupported (a T3 thread cannot be interrupted from firstmate — see fm_backend_t3_kill)" >&2; return 1 ;;
  esac
}

fm_backend_t3_send_literal() {  # <thread-id> <text>
  echo "error: t3 has no composer; use send_text_submit to deliver a turn" >&2
  return 1
}

fm_backend_t3_send_text_line() {  # <thread-id> <text>
  fm_backend_t3_send_text_submit "$1" "$2" 1 0 0 >/dev/null
}

# --- lifecycle ---------------------------------------------------------------

# fm_backend_t3_container_ensure: nothing to ensure. The T3 Code server is the
# container, it is already running, and firstmate neither starts nor stops it.
fm_backend_t3_container_ensure() {
  printf 't3'
}

# fm_backend_t3_create_task: create the thread, send the brief, PRINT the id.
#
# The same two divergences from the terminal backends that claude-bg documents
# apply here, for the same reasons:
#
#  1. The worktree must already EXIST. There is no shell to run `treehouse get`
#     in, so fm-spawn.sh acquires the worktree first and passes the final path.
#  2. Creation and the first prompt are ONE spawn. A thread with no turn has no
#     session and reads as `unknown` forever, so the brief goes in here rather
#     than being sent afterwards.
#
# A third is specific to T3: the worktree path is handed to another Windows
# application, so it is canonicalised to a forward-slash absolute path once,
# here, rather than being sent in whatever form the caller happened to hold.
fm_backend_t3_create_task() {  # <container> <thread-id> <worktree-abs> <brief-file> [project-abs] [title]
  local id=$2 worktree=$3 brief_file=$4 project=${5:-$3} title=${6:-fm-$2}
  case "$id" in
    ????????-????-????-????-????????????) ;;
    *) echo "error: t3 needs a UUID thread id (got '$id')" >&2; return 1 ;;
  esac
  [ -d "$worktree" ] || { echo "error: t3 requires an existing worktree at $worktree" >&2; return 1; }
  [ -f "$brief_file" ] || { echo "error: t3 requires a readable brief at $brief_file" >&2; return 1; }
  worktree=$(fm_backend_t3_native_path "$worktree")
  project=$(fm_backend_t3_native_path "$project")
  fm_backend_t3_helper spawn \
    --thread-id "$id" \
    --project-root "$project" \
    --worktree "$worktree" \
    --brief-file "$brief_file" \
    --title "$title" >/dev/null || return 1
  printf '%s' "$id"
}

# fm_backend_t3_native_path: the path form the T3 server stores and hands back.
# Git Bash paths (/c/...) mean nothing to a native Windows application, so they
# are converted once at the boundary. `cygpath -m` yields C:/... which round-trips
# through the server unchanged; without cygpath the path is already native.
fm_backend_t3_native_path() {  # <path>
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

# fm_backend_t3_kill: stop the session, then archive the thread.
#
# The order is forced and cannot be reversed: archiving first silently drops the
# stop, leaving a running agent with no thread to reach it through. That is a
# permanent orphan, not a slow cleanup.
#
# Neither command's status is trusted. An invariant rejection reaches an HTTP
# caller as a reasonless 500, and on the shipped build the identical mistake
# arrives as a misleading 200, so the helper confirms the outcome by reading the
# thread back — absent is the intended end state.
#
# Extra arguments (the zellij tab id and the fm-<id> label every teardown call
# passes) are accepted and ignored, matching the other adapters.
fm_backend_t3_kill() {  # <thread-id> [ignored...]
  fm_backend_t3_helper kill "$1" >/dev/null 2>&1 || return 0
  return 0
}

# fm_backend_t3_checkpoint_refs_prefix: the ref namespace T3 fills for a thread.
#
# T3 pins every turn with a hidden ref in the project's COMMON ref store — the
# primary checkout's, not the crewmate's worktree — and each ref holds a snapshot
# of the crewmate's whole working tree, uncommitted files included. Only
# `thread.delete` sweeps them, and firstmate's teardown archives rather than
# deletes, so nothing else will ever clean them up. fm-teardown.sh does it.
fm_backend_t3_checkpoint_refs_prefix() {  # <thread-id>
  fm_backend_t3_helper checkpoint-refs "$1"
}

# fm_backend_t3_sweep_checkpoint_refs: delete every checkpoint ref for <thread-id>
# from <project-abs>. Run from the PROJECT, not the worktree: linked worktrees
# share the common ref store, but resolving it from the primary checkout is the
# form that works whether or not the worktree still exists at teardown time.
fm_backend_t3_sweep_checkpoint_refs() {  # <thread-id> <project-abs>
  local id=$1 proj=$2 prefix ref swept=0
  [ -n "$id" ] && [ -d "$proj" ] || return 0
  prefix=$(fm_backend_t3_checkpoint_refs_prefix "$id" 2>/dev/null | tr -d '\r\n') || return 0
  [ -n "$prefix" ] || return 0
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    git -C "$proj" update-ref -d "$ref" 2>/dev/null && swept=$((swept + 1))
  done <<EOF
$(git -C "$proj" for-each-ref --format='%(refname)' "$prefix" 2>/dev/null)
EOF
  [ "$swept" = 0 ] || echo "swept $swept T3 checkpoint ref(s) for $id from $proj"
  return 0
}

# fm_backend_t3_target_exists: is the thread still live?
#
# Archived and deleted threads are indistinguishable over this surface — both are
# simply absent — and both are correctly read as "gone": an archived thread
# swallows turns silently, so treating it as live would strand the supervisor.
#
# [expected-worktree], when given, adds one more way to read "gone": a thread
# whose worktree no longer matches the one firstmate leased for it. That
# worktree can vanish or get re-pointed entirely outside firstmate's control —
# `treehouse return`, a human reusing the lease, a rebase tool moving it — and a
# thread aimed at the wrong tree is not a live crewmate, it is a stale address.
# Reading it as gone (rather than idle) is deliberate: nothing here repairs or
# re-adopts the mismatch, it only stops the supervisor from mistaking it for a
# working endpoint. Omit the argument for the cheap existence-only read every
# other caller uses; the extra info round-trip only runs when a caller asks for
# the identity check too.
fm_backend_t3_target_exists() {  # <thread-id> [expected-worktree]
  local id=$1 expected=${2:-} live
  if [ -z "$expected" ]; then
    fm_backend_t3_helper exists "$id" >/dev/null 2>&1
    return $?
  fi
  live=$(fm_backend_t3_helper info "$id" 2>/dev/null | sed -n 's/^worktree=//p') || return 1
  [ -n "$live" ] || return 1
  [ "$live" = "$expected" ]
}

# fm_backend_t3_identity_status: has a human touched this thread's identity
# since firstmate spawned it? Prints exactly one of:
#   ok          - the live title still matches <expected-title>
#   renamed:X   - the live title is now X
#   gone        - the thread cannot be read at all (existence is
#                 fm_backend_t3_target_exists's job; callers check that first)
#
# firstmate never supplies titleSeed on the create call, so the T3 server's
# canReplaceThreadTitle guard refuses every rename EXCEPT one a human makes
# directly in the app. A title change is therefore proof of a human hand on the
# thread, not ambiguous signal needing corroboration - the caller can treat
# `renamed:` as a one-way captain-held transfer without a second check.
fm_backend_t3_identity_status() {  # <thread-id> <expected-title>
  local id=$1 expected=$2 live
  live=$(fm_backend_t3_helper info "$id" 2>/dev/null | sed -n 's/^title=//p') || { printf 'gone'; return 0; }
  [ -n "$live" ] || { printf 'gone'; return 0; }
  if [ "$live" = "$expected" ]; then
    printf 'ok'
  else
    printf 'renamed:%s' "$live"
  fi
}
