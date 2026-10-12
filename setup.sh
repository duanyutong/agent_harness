#!/bin/sh
set -eu

usage() {
  printf 'Usage: %s [--home DIRECTORY]\n' "$0"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

conflict() {
  printf 'Conflict: %s\n' "$*" >&2
  setup_conflicts=1
}

points_to() {
  [ -L "$1" ] && [ "$(CDPATH='' cd -P "$1" 2>/dev/null && pwd -P)" = "$2" ]
}

main() {
  setup_home=${HOME-}
  case $# in
    0) ;;
    1)
      case $1 in
        -h | --help) usage; return ;;
        *) usage >&2; exit 1 ;;
      esac
      ;;
    2)
      [ "$1" = --home ] || fail 'Expected --home DIRECTORY.'
      setup_home=$2
      ;;
    *) usage >&2; exit 1 ;;
  esac
  case $setup_home in
    /*) ;;
    *) fail 'The home directory must be an existing absolute path.' ;;
  esac
  [ -d "$setup_home" ] || fail "Home directory does not exist: $setup_home"
  setup_home=$(CDPATH='' cd -P "$setup_home" && pwd -P)
  setup_root=$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P)
  setup_shared=$setup_root/skills
  case $setup_home/ in
    "$setup_shared/"*) fail 'The home directory must be outside the shared skills directory.' ;;
  esac
  setup_agents=$setup_home/.agents/skills
  setup_claude=$setup_home/.claude/skills
  setup_claude_available=0
  set -- "$setup_home/.agents"
  if command -v claude > /dev/null 2>&1; then
    setup_claude_available=1
    set -- "$@" "$setup_home/.claude" "$setup_claude"
  fi
  setup_conflicts=0

  # Check every supported path before creating directories or links.
  if [ -L "$setup_shared" ] || [ ! -d "$setup_shared" ]; then
    conflict "Expected a physical skills directory at $setup_shared."
  fi
  if [ -e "$setup_shared/synced" ] || [ -L "$setup_shared/synced" ]; then
    conflict "Move $setup_shared/synced outside the shared skills directory before retrying."
  fi
  for setup_directory in "$@"; do
    if [ -L "$setup_directory" ] || { [ -e "$setup_directory" ] && [ ! -d "$setup_directory" ]; }; then
      conflict "$setup_directory must be absent or a physical directory; resolve it manually."
    fi
  done
  if [ -e "$setup_agents" ] || [ -L "$setup_agents" ]; then
    if ! points_to "$setup_agents" "$setup_shared"; then
      conflict "$setup_agents already exists and does not link to $setup_shared; preserve it and resolve it manually."
    fi
  fi
  [ "$setup_conflicts" -eq 0 ] || fail 'No changes made. Resolve the conflicts and rerun setup.'

  mkdir -p "$@"
  if ! points_to "$setup_agents" "$setup_shared"; then
    # Target the parent directory so an existing skills link is never followed.
    # No force flag: a competing installer cannot overwrite an existing entry.
    if ! ln -s "$setup_shared" "$setup_home/.agents/"; then
      points_to "$setup_agents" "$setup_shared" || fail "Could not create $setup_agents."
    fi
  fi
  printf 'Shared skills: %s -> %s\n' "$setup_agents" "$setup_shared"
  if [ "$setup_claude_available" -eq 1 ]; then
    printf 'Claude skills: %s (independent directory)\n' "$setup_claude"
  else
    printf 'Claude setup skipped: claude is not available on PATH.\n'
  fi
}

main "$@"
