#!/usr/bin/env bash
# Shared durable wake queue and portable lock helpers.

FM_WAKE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_WAKE_DEFAULT_ROOT="$(cd "$FM_WAKE_LIB_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$FM_WAKE_DEFAULT_ROOT}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-${STATE:-$FM_HOME/state}}"
FM_WAKE_QUEUE="${FM_WAKE_QUEUE:-$STATE/.wake-queue}"
FM_WAKE_QUEUE_DIR="${FM_WAKE_QUEUE_DIR:-$STATE/.wake-queue.d}"
FM_WAKE_QUEUE_LOCK="${FM_WAKE_QUEUE_LOCK:-$STATE/.wake-queue.lock}"
FM_LOCK_STALE_AFTER="${FM_LOCK_STALE_AFTER:-2}"
mkdir -p "$STATE"

fm_lock_directory_only_platform() {
  local sys
  sys=$(uname -s 2>/dev/null || uname 2>/dev/null) || sys=unknown
  case "$sys" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

fm_current_pid() {
  printf '%s\n' "${BASHPID:-$$}"
}

fm_epoch_seconds() {
  if [ -n "${EPOCHSECONDS:-}" ]; then
    printf '%s\n' "$EPOCHSECONDS"
    return 0
  fi
  date +%s
}

fm_now_stamp() {
  local stamp=${EPOCHREALTIME:-}
  if [ -n "$stamp" ]; then
    stamp=${stamp//[^0-9]/}
    printf '%s\n' "$stamp"
    return 0
  fi
  printf '%s%05d%05d\n' "$(fm_epoch_seconds)" "${RANDOM:-0}" "${RANDOM:-0}"
}

fm_pid_alive() {
  local pid=$1
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null
}

fm_pid_identity() {
  local pid=$1 out statf cmdf statline cmdline rest starttime
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  statf="/proc/$pid/stat"
  cmdf="/proc/$pid/cmdline"
  if [ -r "$statf" ]; then
    IFS= read -r statline < "$statf" 2>/dev/null || statline=
    cmdline=$(tr '\0' ' ' < "$cmdf" 2>/dev/null || true)
    rest=${statline#*) }
    set -- $rest
    starttime=${20:-}
    if [ -n "$starttime$cmdline" ]; then
      printf '%s\t%s\n' "$starttime" "$cmdline"
      return 0
    fi
  fi
  out=$(ps -p "$pid" -o lstart= -o command= 2>/dev/null || true)
  if [ -z "$out" ]; then
    out=$(ps -p "$pid" -f 2>/dev/null | sed '1d') || return 1
  fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out" | sed 's/^[[:space:]]*//'
}

fm_path_mtime() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %m "$1" 2>/dev/null
  else
    stat -c %Y "$1" 2>/dev/null
  fi
}

fm_path_age() {
  local path=$1 m
  m=$(fm_path_mtime "$path") || { echo 999999; return; }
  echo $(( $(fm_epoch_seconds) - m ))
}

fm_lock_stale_after_seconds() {
  local stale=${FM_LOCK_STALE_AFTER:-2}
  case "$stale" in
    ''|*[!0-9]*) stale=2 ;;
  esac
  if fm_lock_directory_only_platform; then
    [ "$stale" -lt 5 ] && stale=5
  else
    [ "$stale" -lt 2 ] && stale=2
  fi
  printf '%s\n' "$stale"
}

fm_lock_debug() {
  [ -n "${FM_LOCK_DEBUG:-}" ] || return 0
  printf '%s\tpid=%s\t%s\n' \
    "$(date +%s.%N 2>/dev/null || date +%s)" \
    "$(fm_current_pid)" \
    "$*" >> "${FM_LOCK_DEBUG_LOG:-$STATE/.wake-lock-debug.log}"
}

fm_lock_clean_known_files() {
  local lockdir=$1
  rm -f \
    "$lockdir/pid" \
    "$lockdir/token" \
    "$lockdir/hold-until" \
    "$lockdir/fm-home" \
    "$lockdir/pid-identity" \
    "$lockdir/watcher-path" \
    2>/dev/null || true
}

fm_lock_abs_path() {
  local path=$1 dir base
  dir=$(dirname "$path")
  base=$(basename "$path")
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$base"
}

fm_lock_owner_dir() {
  local lockdir=$1 lock_abs
  lock_abs=$(fm_lock_abs_path "$lockdir") || return 1
  mktemp -d "${lock_abs}.owner.XXXXXX" 2>/dev/null
}

fm_lock_token_var_name() {
  local path=$1
  printf 'FM_LOCK_TOKEN_%s\n' "$(printf '%s' "$path" | tr -c 'A-Za-z0-9' '_')"
}

fm_lock_store_local_token() {
  local path=$1 token=$2 var
  var=$(fm_lock_token_var_name "$path")
  printf -v "$var" '%s' "$token"
}

fm_lock_local_token() {
  local path=$1 var
  var=$(fm_lock_token_var_name "$path")
  eval "printf '%s' \"\${$var:-}\""
}

fm_lock_clear_local_token() {
  local path=$1 var
  var=$(fm_lock_token_var_name "$path")
  unset "$var"
}

fm_lock_new_token() {
  printf '%s:%s:%s:%s\n' \
    "${BASHPID:-$$}" \
    "${RANDOM:-0}" \
    "${RANDOM:-0}" \
    "$(fm_now_stamp)"
}

fm_read_file_line() {
  local file=$1 line=
  [ -r "$file" ] || { printf '%s' "$line"; return 0; }
  IFS= read -r line < "$file" 2>/dev/null || true
  printf '%s' "$line"
}

fm_lock_wait_sleep_seconds() {
  if [ -n "${FM_LOCK_WAIT_SLEEP:-}" ]; then
    printf '%s\n' "$FM_LOCK_WAIT_SLEEP"
    return 0
  fi
  if fm_lock_directory_only_platform; then
    printf '1\n'
    return 0
  fi
  printf '0.1\n'
}

fm_lock_recent_holder_grace_seconds() {
  local grace
  if [ -n "${FM_LOCK_RECENT_HOLDER_GRACE:-}" ]; then
    grace=$FM_LOCK_RECENT_HOLDER_GRACE
  elif fm_lock_directory_only_platform; then
    grace=60
  else
    grace=6
  fi
  case "$grace" in
    ''|*[!0-9]*) grace=6 ;;
  esac
  [ "$grace" -lt 1 ] && grace=1
  printf '%s\n' "$grace"
}

fm_lock_recent_holder_is_fresh() {
  local lockdir=$1 pid=$2 deadline now
  fm_pid_alive "$pid" && return 1
  deadline=$(fm_read_file_line "$lockdir/hold-until")
  case "$deadline" in
    ''|*[!0-9]*) return 1 ;;
  esac
  now=$(fm_epoch_seconds)
  [ "$now" -lt "$deadline" ]
}

fm_lock_prepare_owner() {
  local ownerdir=$1 mypid token
  mypid=${BASHPID:-$$}
  token=$(fm_lock_new_token)
  { printf '%s\n' "$mypid" > "$ownerdir/pid"; } 2>/dev/null || return 1
  { printf '%s\n' "$token" > "$ownerdir/token"; } 2>/dev/null || return 1
  { printf '%s\n' "$(( $(fm_epoch_seconds) + $(fm_lock_recent_holder_grace_seconds) ))" > "$ownerdir/hold-until"; } 2>/dev/null || true
  fm_lock_store_local_token "$ownerdir" "$token"
  return 0
}

fm_lock_link_owner() {
  local lockdir=$1 owner
  if [ -d "$lockdir" ] && [ ! -L "$lockdir" ]; then
    printf '%s\n' "$lockdir"
    return 0
  fi
  owner=$(readlink "$lockdir" 2>/dev/null) || return 1
  [ -n "$owner" ] || return 1
  case "$owner" in
    /*) printf '%s\n' "$owner" ;;
    *) printf '%s/%s\n' "$(dirname "$lockdir")" "$owner" ;;
  esac
}

fm_lock_points_to_owner() {
  local lockdir=$1 ownerdir=$2 actual
  if [ -d "$lockdir" ] && [ ! -L "$lockdir" ]; then
    [ "$lockdir" = "$ownerdir" ]
    return
  fi
  actual=$(readlink "$lockdir" 2>/dev/null) || return 1
  [ "$actual" = "$ownerdir" ]
}

fm_lock_discard_owner() {
  local ownerdir=$1
  [ -n "$ownerdir" ] || return 0
  fm_lock_clear_local_token "$ownerdir"
  fm_lock_clean_known_files "$ownerdir"
  rmdir "$ownerdir" 2>/dev/null || true
}

fm_lock_remove_stray_owner_link() {
  local lockdir=$1 ownerdir=$2 stray
  stray="$lockdir/$(basename "$ownerdir")"
  if [ -L "$stray" ] && [ "$(readlink "$stray" 2>/dev/null || true)" = "$ownerdir" ]; then
    rm -f "$stray" 2>/dev/null || true
  fi
  if [ -d "$stray" ] && [ ! -L "$stray" ]; then
    fm_lock_discard_owner "$stray"
  fi
}

fm_lock_claim_blocked_by_steal() {
  local lockdir=$1 allowed_steal_owner=${2:-} steal
  steal="$lockdir.steal"
  [ -e "$steal" ] || [ -L "$steal" ] || return 1
  if [ -n "$allowed_steal_owner" ] && fm_lock_points_to_owner "$steal" "$allowed_steal_owner"; then
    return 1
  fi
  return 0
}

fm_lock_claim() {
  local lockdir=$1 ownerdir=$2 allowed_steal_owner=${3:-} mypid token
  mypid=${BASHPID:-$$}
  token=$(fm_lock_new_token)
  if ! { printf '%s\n' "$mypid" > "$ownerdir/pid"; } 2>/dev/null; then
    fm_lock_discard_owner "$ownerdir"
    return 1
  fi
  if ! { printf '%s\n' "$token" > "$ownerdir/token"; } 2>/dev/null; then
    fm_lock_discard_owner "$ownerdir"
    return 1
  fi
  fm_lock_store_local_token "$ownerdir" "$token"
  if ! fm_lock_points_to_owner "$lockdir" "$ownerdir"; then
    fm_lock_remove_stray_owner_link "$lockdir" "$ownerdir"
    if [ -d "$lockdir" ] && [ ! -L "$lockdir" ] && [ ! -e "$lockdir/pid" ]; then
      rmdir "$lockdir" 2>/dev/null || true
    fi
    fm_lock_discard_owner "$ownerdir"
    return 1
  fi
  if fm_lock_claim_blocked_by_steal "$lockdir" "$allowed_steal_owner"; then
    if fm_lock_points_to_owner "$lockdir" "$ownerdir"; then
      rm -f "$lockdir" 2>/dev/null || true
    fi
    fm_lock_discard_owner "$ownerdir"
    return 1
  fi
  return 0
}

fm_lock_try_create_directory_lock() {
  local lockdir=$1 allowed_steal_owner=${2:-}
  FM_LOCK_OWNER_DIR=
  if mkdir "$lockdir" 2>/dev/null; then
    if fm_lock_prepare_owner "$lockdir"; then
      if fm_lock_claim_blocked_by_steal "$lockdir" "$allowed_steal_owner"; then
        fm_lock_discard_owner "$lockdir"
        return 1
      fi
      FM_LOCK_OWNER_DIR=$lockdir
      return 0
    fi
    fm_lock_discard_owner "$lockdir"
    return 1
  fi
  return 1
}

fm_lock_try_create() {
  local lockdir=$1 allowed_steal_owner=${2:-} ownerdir
  if fm_lock_try_create_directory_lock "$lockdir" "$allowed_steal_owner"; then
    return 0
  fi
  if fm_lock_directory_only_platform; then
    return 1
  fi
  ownerdir=$(fm_lock_owner_dir "$lockdir") || return 1
  if [ -e "$lockdir" ] || [ -L "$lockdir" ]; then
    fm_lock_discard_owner "$ownerdir"
    return 1
  fi
  if ! fm_lock_prepare_owner "$ownerdir"; then
    fm_lock_discard_owner "$ownerdir"
    return 1
  fi
  if ln -s "$ownerdir" "$lockdir" 2>/dev/null; then
    if fm_lock_points_to_owner "$lockdir" "$ownerdir"; then
      if fm_lock_claim "$lockdir" "$ownerdir" "$allowed_steal_owner"; then
        FM_LOCK_OWNER_DIR=$ownerdir
        return 0
      fi
      if fm_lock_points_to_owner "$lockdir" "$ownerdir"; then
        rm -f "$lockdir" 2>/dev/null || true
      fi
    fi
    fm_lock_remove_stray_owner_link "$lockdir" "$ownerdir"
  else
    fm_lock_remove_stray_owner_link "$lockdir" "$ownerdir"
  fi
  if [ -d "$lockdir" ] && [ ! -L "$lockdir" ] && [ ! -e "$lockdir/pid" ]; then
    fm_lock_clean_known_files "$lockdir"
    rmdir "$lockdir" 2>/dev/null || true
  fi
  if mkdir "$lockdir" 2>/dev/null; then
    if fm_lock_prepare_owner "$lockdir"; then
      FM_LOCK_OWNER_DIR=$lockdir
      fm_lock_discard_owner "$ownerdir"
      return 0
    fi
    fm_lock_discard_owner "$lockdir"
  fi
  fm_lock_discard_owner "$ownerdir"
  return 1
}

fm_lock_remove_path() {
  local lockdir=$1 ownerdir trash
  if [ -L "$lockdir" ]; then
    ownerdir=$(fm_lock_link_owner "$lockdir" 2>/dev/null || true)
    rm -f "$lockdir" 2>/dev/null || return 1
    [ -n "$ownerdir" ] && fm_lock_discard_owner "$ownerdir"
    return 0
  fi
  trash="$lockdir.remove.$(fm_current_pid).$RANDOM"
  if mv "$lockdir" "$trash" 2>/dev/null; then
    fm_lock_clean_known_files "$trash"
    rmdir "$trash" 2>/dev/null || rm -rf -- "$trash" 2>/dev/null || true
    return 0
  fi
  fm_lock_clean_known_files "$lockdir"
  rmdir "$lockdir" 2>/dev/null || rm -rf -- "$lockdir" 2>/dev/null || true
}

fm_lock_mid_acquire_is_fresh() {
  local lockdir=$1 pid=$2 mid_acquire_stale
  case "$pid" in
    ''|*[!0-9]*)
      mid_acquire_stale=$(fm_lock_stale_after_seconds)
      [ "$(fm_path_age "$lockdir")" -lt "$mid_acquire_stale" ]
      return
      ;;
  esac
  return 1
}

fm_lock_recheck_stale_owner() {
  local lockdir=$1 expected_owner=$2 expected_pid=$3 actual_pid
  if [ -n "$expected_owner" ]; then
    fm_lock_points_to_owner "$lockdir" "$expected_owner" || return 1
  elif [ -e "$lockdir" ] || [ -L "$lockdir" ]; then
    [ -d "$lockdir" ] && [ ! -L "$lockdir" ] || return 1
  fi
  actual_pid=$(fm_read_file_line "$lockdir/pid")
  [ "$actual_pid" = "$expected_pid" ] || return 1
  if fm_pid_alive "$actual_pid"; then
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$actual_pid"; then
    return 1
  fi
  return 0
}

fm_lock_try_acquire_directory_mutex() {
  local lockdir=$1 pid
  FM_LOCK_HELD_PID=
  FM_LOCK_OWNER_DIR=
  fm_lock_debug "mutex enter lockdir=$lockdir"

  if fm_lock_try_create_directory_lock "$lockdir"; then
    fm_lock_debug "mutex created lockdir=$lockdir owner=$FM_LOCK_OWNER_DIR"
    return 0
  fi

  pid=$(fm_read_file_line "$lockdir/pid")
  if fm_pid_alive "$pid"; then
    fm_lock_debug "mutex live-holder lockdir=$lockdir pid=$pid"
    FM_LOCK_HELD_PID=$pid
    return 1
  fi
  if fm_lock_recent_holder_is_fresh "$lockdir" "$pid"; then
    fm_lock_debug "mutex recent-dead-holder lockdir=$lockdir pid=$pid"
    FM_LOCK_HELD_PID=$pid
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$pid"; then
    fm_lock_debug "mutex fresh-mid-acquire lockdir=$lockdir pid=${pid:-none}"
    FM_LOCK_HELD_PID=$pid
    return 1
  fi

  fm_lock_debug "mutex reclaim-remove lockdir=$lockdir pid=${pid:-none}"
  fm_lock_remove_path "$lockdir" || true
  if fm_lock_try_create_directory_lock "$lockdir"; then
    fm_lock_debug "mutex reclaimed lockdir=$lockdir owner=$FM_LOCK_OWNER_DIR"
    return 0
  fi

  FM_LOCK_HELD_PID=$(fm_read_file_line "$lockdir/pid")
  fm_lock_debug "mutex lost-race lockdir=$lockdir held=${FM_LOCK_HELD_PID:-none}"
  FM_LOCK_OWNER_DIR=
  return 1
}

fm_lock_try_acquire_directory_only() {
  local lockdir=$1 pid steal cur rc steal_owner
  FM_LOCK_HELD_PID=
  FM_LOCK_OWNER_DIR=
  fm_lock_debug "primary enter lockdir=$lockdir"

  if fm_lock_try_create_directory_lock "$lockdir"; then
    fm_lock_debug "primary created lockdir=$lockdir owner=$FM_LOCK_OWNER_DIR"
    return 0
  fi

  pid=$(fm_read_file_line "$lockdir/pid")
  if fm_pid_alive "$pid"; then
    fm_lock_debug "primary live-holder lockdir=$lockdir pid=$pid"
    FM_LOCK_HELD_PID=$pid
    return 1
  fi
  if fm_lock_recent_holder_is_fresh "$lockdir" "$pid"; then
    fm_lock_debug "primary recent-dead-holder lockdir=$lockdir pid=$pid"
    FM_LOCK_HELD_PID=$pid
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$pid"; then
    fm_lock_debug "primary fresh-mid-acquire lockdir=$lockdir pid=${pid:-none}"
    FM_LOCK_HELD_PID=$pid
    return 1
  fi

  steal="$lockdir.steal"
  if ! fm_lock_try_acquire_directory_mutex "$steal"; then
    fm_lock_debug "primary steal-busy lockdir=$lockdir steal=$steal held=${FM_LOCK_HELD_PID:-none}"
    FM_LOCK_HELD_PID=$(fm_read_file_line "$lockdir/pid")
    FM_LOCK_OWNER_DIR=
    return 1
  fi
  steal_owner=${FM_LOCK_OWNER_DIR:-}
  fm_lock_debug "primary steal-acquired lockdir=$lockdir steal=$steal owner=$steal_owner"

  cur=$(fm_read_file_line "$lockdir/pid")
  if fm_pid_alive "$cur"; then
    fm_lock_debug "primary recheck-live lockdir=$lockdir pid=$cur"
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$cur
    FM_LOCK_OWNER_DIR=
    return 1
  fi
  if fm_lock_recent_holder_is_fresh "$lockdir" "$cur"; then
    fm_lock_debug "primary recheck-recent-dead lockdir=$lockdir pid=$cur"
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$cur
    FM_LOCK_OWNER_DIR=
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$cur"; then
    fm_lock_debug "primary recheck-fresh lockdir=$lockdir pid=${cur:-none}"
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$cur
    FM_LOCK_OWNER_DIR=
    return 1
  fi

  fm_lock_debug "primary reclaim-remove lockdir=$lockdir pid=${cur:-none}"
  fm_lock_remove_path "$lockdir" || true
  rc=1
  if fm_lock_try_create_directory_lock "$lockdir" "$steal_owner"; then
    rc=0
    fm_lock_debug "primary reclaimed lockdir=$lockdir owner=$FM_LOCK_OWNER_DIR"
  fi
  if [ "$rc" -ne 0 ]; then
    FM_LOCK_HELD_PID=$(fm_read_file_line "$lockdir/pid")
    fm_lock_debug "primary lost-race lockdir=$lockdir held=${FM_LOCK_HELD_PID:-none}"
    FM_LOCK_OWNER_DIR=
  fi
  fm_lock_release "$steal"
  fm_lock_debug "primary exit lockdir=$lockdir rc=$rc"
  return "$rc"
}

fm_lock_try_acquire() {
  local lockdir=$1 pid steal cur rc steal_owner primary_owner
  FM_LOCK_HELD_PID=
  FM_LOCK_OWNER_DIR=

  if fm_lock_directory_only_platform; then
    case "$lockdir" in
      *.steal) fm_lock_try_acquire_directory_mutex "$lockdir" ;;
      *) fm_lock_try_acquire_directory_only "$lockdir" ;;
    esac
    return "$?"
  fi

  if fm_lock_try_create "$lockdir"; then
    return 0
  fi

  pid=$(cat "$lockdir/pid" 2>/dev/null || true)
  if fm_pid_alive "$pid"; then
    FM_LOCK_HELD_PID=$pid
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$pid"; then
    FM_LOCK_HELD_PID=$pid
    return 1
  fi

  steal="$lockdir.steal"
  if ! fm_lock_try_acquire "$steal"; then
    FM_LOCK_HELD_PID=$(cat "$lockdir/pid" 2>/dev/null || true)
    FM_LOCK_OWNER_DIR=
    return 1
  fi
  steal_owner=${FM_LOCK_OWNER_DIR:-}

  cur=$(cat "$lockdir/pid" 2>/dev/null || true)
  if fm_pid_alive "$cur"; then
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$cur
    FM_LOCK_OWNER_DIR=
    return 1
  fi
  if fm_lock_mid_acquire_is_fresh "$lockdir" "$cur"; then
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$cur
    FM_LOCK_OWNER_DIR=
    return 1
  fi
  if ! fm_lock_points_to_owner "$steal" "$steal_owner"; then
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$(cat "$lockdir/pid" 2>/dev/null || true)
    FM_LOCK_OWNER_DIR=
    return 1
  fi

  primary_owner=
  if [ -L "$lockdir" ]; then
    primary_owner=$(fm_lock_link_owner "$lockdir" 2>/dev/null || true)
  fi
  cur=$(cat "$lockdir/pid" 2>/dev/null || true)
  if ! fm_lock_recheck_stale_owner "$lockdir" "$primary_owner" "$cur"; then
    fm_lock_release "$steal"
    FM_LOCK_HELD_PID=$(cat "$lockdir/pid" 2>/dev/null || true)
    FM_LOCK_OWNER_DIR=
    return 1
  fi

  fm_lock_remove_path "$lockdir" || true
  rc=1
  if fm_lock_try_create "$lockdir" "$steal_owner"; then
    rc=0
  fi
  if [ "$rc" -ne 0 ]; then
    # shellcheck disable=SC2034 # Read by callers after fm_lock_try_acquire returns.
    FM_LOCK_HELD_PID=$(cat "$lockdir/pid" 2>/dev/null || true)
    FM_LOCK_OWNER_DIR=
  fi
  fm_lock_release "$steal"
  return "$rc"
}

fm_lock_acquire_wait() {
  local lockdir=$1 wait_sleep
  wait_sleep=$(fm_lock_wait_sleep_seconds)
  while ! fm_lock_try_acquire "$lockdir"; do
    sleep "$wait_sleep"
  done
}

fm_lock_release() {
  local lockdir=$1 token ownerdir trash
  if [ -L "$lockdir" ]; then
    ownerdir=$(fm_lock_link_owner "$lockdir" 2>/dev/null || true)
    [ -n "$ownerdir" ] || return 0
    token=$(fm_read_file_line "$ownerdir/token")
    [ -n "$token" ] || return 0
    [ "$token" = "$(fm_lock_local_token "$ownerdir")" ] || return 0
    fm_lock_points_to_owner "$lockdir" "$ownerdir" || return 0
    rm -f "$lockdir" 2>/dev/null || return 0
    fm_lock_discard_owner "$ownerdir"
    return 0
  fi
  token=$(fm_read_file_line "$lockdir/token")
  [ -n "$token" ] || return 0
  [ "$token" = "$(fm_lock_local_token "$lockdir")" ] || return 0
  fm_lock_debug "release lockdir=$lockdir"
  fm_lock_clear_local_token "$lockdir"
  trash="$lockdir.release.$(fm_current_pid).$RANDOM"
  if mv "$lockdir" "$trash" 2>/dev/null; then
    fm_lock_clean_known_files "$trash"
    rmdir "$trash" 2>/dev/null || rm -rf -- "$trash" 2>/dev/null || true
    return 0
  fi
  fm_lock_clean_known_files "$lockdir"
  rmdir "$lockdir" 2>/dev/null || rm -rf -- "$lockdir" 2>/dev/null || true
}

fm_wake_clean_field() {
  LC_ALL=C tr '\t\r\n' '   '
}

fm_wake_use_spool_backend() {
  fm_lock_directory_only_platform
}

fm_wake_seq() {
  local seq
  seq=$(fm_now_stamp)
  case "$seq" in
    ''|*[!0-9]*) seq="$(fm_epoch_seconds)$(printf '%05d%05d' "${RANDOM:-0}" "${RANDOM:-0}")" ;;
  esac
  printf '%s\n' "$seq"
}

fm_wake_mark_pending() {
  printf '1\n' > "$FM_WAKE_QUEUE" 2>/dev/null || true
}

fm_wake_clear_pending() {
  : > "$FM_WAKE_QUEUE" 2>/dev/null || true
}

fm_wake_spool_has_entries() {
  local dir=${1:-$FM_WAKE_QUEUE_DIR}
  [ -d "$dir" ] || return 1
  (
    shopt -s nullglob
    local files=( "$dir"/*.wake )
    [ "${#files[@]}" -gt 0 ]
  )
}

fm_wake_append_spooled() {
  local kind=$1 key=$2 payload=$3 clean_key clean_payload epoch seq entry status pid
  clean_key=$(printf '%s' "$key" | fm_wake_clean_field)
  clean_payload=$(printf '%s' "$payload" | fm_wake_clean_field)
  epoch=$(fm_epoch_seconds)
  status=0
  pid=${BASHPID:-$$}
  [ -d "$FM_WAKE_QUEUE_DIR" ] || mkdir -p "$FM_WAKE_QUEUE_DIR" || return 1

  while :; do
    seq=$(fm_wake_seq)
    entry="$FM_WAKE_QUEUE_DIR/$seq.$pid.${RANDOM:-0}.wake"
    if ( set -C; : > "$entry" ) 2>/dev/null; then
      break
    fi
    [ -d "$FM_WAKE_QUEUE_DIR" ] || mkdir -p "$FM_WAKE_QUEUE_DIR" || return 1
  done

  if ! printf '%s\t%s\t%s\t%s\t%s\n' "$epoch" "$seq" "$kind" "$clean_key" "$clean_payload" > "$entry"; then
    rm -f "$entry" 2>/dev/null || true
    return 1
  fi
  fm_wake_mark_pending
  return 0
}

fm_wake_append() {
  local kind=$1 key=$2 payload=$3 clean_key clean_payload epoch seq seq_file status
  case "$kind" in
    signal|stale|check|heartbeat) ;;
    *) printf 'fm_wake_append: invalid wake kind: %s\n' "$kind" >&2; return 2 ;;
  esac

  if fm_wake_use_spool_backend; then
    fm_lock_debug "append spooled kind=$kind key=$key"
    fm_wake_append_spooled "$kind" "$key" "$payload"
    return "$?"
  fi

  clean_key=$(printf '%s' "$key" | fm_wake_clean_field)
  clean_payload=$(printf '%s' "$payload" | fm_wake_clean_field)
  epoch=$(date +%s)
  seq_file="$STATE/.wake-queue.seq"
  status=0

  fm_lock_debug "append waiting kind=$kind key=$clean_key"
  fm_lock_acquire_wait "$FM_WAKE_QUEUE_LOCK"
  fm_lock_debug "append acquired kind=$kind key=$clean_key"
  seq=$(fm_read_file_line "$seq_file")
  [ -n "$seq" ] || seq=0
  case "$seq" in
    ''|*[!0-9]*) seq=0 ;;
  esac
  seq=$((seq + 1))
  printf '%s\n' "$seq" > "$seq_file" || status=$?
  if [ "$status" -eq 0 ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$epoch" "$seq" "$kind" "$clean_key" "$clean_payload" >> "$FM_WAKE_QUEUE" || status=$?
  fi
  fm_lock_release "$FM_WAKE_QUEUE_LOCK"
  fm_lock_debug "append released kind=$kind key=$clean_key status=$status"
  return "$status"
}

fm_wake_restore_queue() {
  local drained=$1 restore
  if fm_wake_use_spool_backend && [ -d "$drained" ]; then
    mkdir -p "$FM_WAKE_QUEUE_DIR" || return 1
    (
      shopt -s nullglob
      local files=( "$drained"/*.wake )
      [ "${#files[@]}" -eq 0 ] || mv "${files[@]}" "$FM_WAKE_QUEUE_DIR"/
    ) || return 1
    rmdir "$drained" 2>/dev/null || rm -rf -- "$drained" 2>/dev/null || true
    if fm_wake_spool_has_entries; then
      fm_wake_mark_pending
    else
      fm_wake_clear_pending
    fi
    return 0
  fi
  restore="$STATE/.wake-queue.restore.$(fm_current_pid)"
  if [ -e "$FM_WAKE_QUEUE" ]; then
    cat "$drained" "$FM_WAKE_QUEUE" > "$restore" && mv "$restore" "$FM_WAKE_QUEUE"
  else
    mv "$drained" "$FM_WAKE_QUEUE"
  fi
}

fm_wake_print_deduped() {
  local file=$1
  awk -F '\t' '
    NF >= 5 {
      dedupe = $3 SUBSEP $4
      if ($3 == "heartbeat") {
        dedupe = "heartbeat"
      }
      if (!(dedupe in seen)) {
        order[++count] = dedupe
        seen[dedupe] = 1
      }
      line[dedupe] = $0
    }
    END {
      for (i = 1; i <= count; i++) {
        print line[order[i]]
      }
    }
  ' "$file"
}

fm_wake_print_deduped_spool() {
  local dir=$1 merged
  merged="$STATE/.wake-queue.print.$(fm_current_pid).${RANDOM:-0}"
  (
    shopt -s nullglob
    local files=( "$dir"/*.wake )
    if [ "${#files[@]}" -eq 0 ]; then
      : > "$merged"
    else
      cat "${files[@]}" > "$merged"
    fi
  ) || return 1
  fm_wake_print_deduped "$merged"
  rm -f "$merged" 2>/dev/null || true
}
