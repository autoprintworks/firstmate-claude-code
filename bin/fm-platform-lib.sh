#!/usr/bin/env bash
# Shared platform compatibility policy for security-sensitive filesystem mode
# validation. This file is sourced, never executed.
#
# Usage after sourcing:
#   fm_platform_mode_compatible <expected-mode> <actual-mode> <file|dir> [uname]

# Git for Windows projects NTFS ACL-backed modes into a small POSIX-looking
# set. Mode compatibility never replaces callers' ordinary-file, no-symlink,
# single-link, device, identity, or content checks.

fm_platform_mode_compatible() {
  local expected=$1 actual=$2 kind=$3 platform=${4-}
  [ "$expected" = "$actual" ] && return 0
  [ -n "$platform" ] || platform=$(uname 2>/dev/null || true)
  case "$platform" in MINGW*|MSYS*|CYGWIN*) ;; *) return 1 ;; esac
  case "$kind" in
    file)
      case "$expected" in 600|700|755) ;; *) return 1 ;; esac
      case "$actual" in 600|644|700|755) return 0 ;; *) return 1 ;; esac
      ;;
    dir)
      [ "$expected" = 700 ] || return 1
      [ "$actual" = 755 ]
      ;;
    *) return 1 ;;
  esac
}
