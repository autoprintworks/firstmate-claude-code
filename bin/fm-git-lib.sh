#!/usr/bin/env bash
# shellcheck shell=bash
# Shared git runtime helpers for FirstMate on Windows/Codex Desktop.
#
# - Keeps git callable even when a caller trims PATH to a minimal toolchain.
# - Trusts the active firstmate repo/worktree for this process only, so git can
#   operate inside Codex Desktop's sandbox user without requiring a global
#   safe.directory mutation.

[ -n "${FM_GIT_LIB_LOADED:-}" ] && return 0
FM_GIT_LIB_LOADED=1

fm_git_append_path() {
  local dir=$1
  [ -n "$dir" ] || return 1
  [ -x "$dir/git" ] || [ -x "$dir/git.exe" ] || return 1
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
  esac
  PATH="$dir:$PATH"
  export PATH
}

fm_git_ensure_path() {
  command -v git >/dev/null 2>&1 && return 0
  local dir
  for dir in \
    /mingw64/bin \
    /usr/bin \
    "/c/Program Files/Git/mingw64/bin" \
    "/c/Program Files/Git/cmd" \
    "/c/Program Files/Git/bin"
  do
    fm_git_append_path "$dir" && break
  done
  command -v git >/dev/null 2>&1
}

fm_git_add_runtime_config() {
  local key=$1 value=$2 idx
  [ -n "$key" ] || return 0
  [ -n "$value" ] || return 0
  idx=${GIT_CONFIG_COUNT:-0}
  eval "GIT_CONFIG_KEY_$idx=\$key"
  eval "GIT_CONFIG_VALUE_$idx=\$value"
  export "GIT_CONFIG_KEY_$idx" "GIT_CONFIG_VALUE_$idx"
  GIT_CONFIG_COUNT=$((idx + 1))
  export GIT_CONFIG_COUNT
}

fm_git_trust_literal() {
  local path=$1 native=
  [ -n "$path" ] || return 0
  case "${FM_GIT_SAFE_DIRS:-|}" in
    *"|$path|"*) ;;
    *)
      FM_GIT_SAFE_DIRS="${FM_GIT_SAFE_DIRS:-|}$path|"
      export FM_GIT_SAFE_DIRS
      fm_git_add_runtime_config safe.directory "$path"
      ;;
  esac
  if command -v cygpath >/dev/null 2>&1; then
    native=$(cygpath -m "$path" 2>/dev/null || true)
    if [ -n "$native" ] && [ "$native" != "$path" ]; then
      case "${FM_GIT_SAFE_DIRS:-|}" in
        *"|$native|"*) ;;
        *)
          FM_GIT_SAFE_DIRS="${FM_GIT_SAFE_DIRS:-|}$native|"
          export FM_GIT_SAFE_DIRS
          fm_git_add_runtime_config safe.directory "$native"
          ;;
      esac
    fi
  fi
}

fm_git_trust_path() {
  local path=$1 resolved=
  [ -n "$path" ] || return 0
  fm_git_trust_literal "$path"
  case "$path" in
    */.git|.git) ;;
    *)
      fm_git_trust_literal "$path/.git"
      ;;
  esac
  if [ -d "$path" ]; then
    resolved=$(cd "$path" 2>/dev/null && pwd -P || true)
  elif [ -e "$path" ]; then
    resolved=$(cd "$(dirname "$path")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")" || true)
  fi
  if [ -n "$resolved" ] && [ "$resolved" != "$path" ]; then
    fm_git_trust_literal "$resolved"
    case "$resolved" in
      */.git|.git) ;;
      *)
        fm_git_trust_literal "$resolved/.git"
        ;;
    esac
  fi
}

fm_git_prepare_runtime() {
  fm_git_ensure_path || return 0
  fm_git_trust_path "${FM_ROOT:-}"
  fm_git_trust_path "${FM_HOME:-}"
}

fm_git_prepare_runtime
