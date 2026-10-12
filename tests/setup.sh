#!/bin/sh
set -eu

test_repo_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-setup-tests.XXXXXX")
trap 'rm -rf "$test_root"' 0
test_root=$(CDPATH='' cd -P "$test_root" && pwd -P)
test_count=0

fixture() {
  test_count=$((test_count + 1))
  test_case=$test_root/case\ $test_count
  test_repo=$test_case/repository
  test_home=$test_case/home
  test_setup_path=$test_case/bin
  mkdir -p "$test_repo/skills/example" "$test_home" "$test_case/external" "$test_setup_path"
  for test_utility in dirname mkdir ln sh; do
    ln -s "$(command -v "$test_utility")" "$test_setup_path/$test_utility"
  done
  printf '#!/bin/sh\nexit 99\n' > "$test_setup_path/claude"
  chmod +x "$test_setup_path/claude"
  cp "$test_repo_root/setup.sh" "$test_repo/setup.sh"
  printf 'Shared skill\n' > "$test_repo/skills/example/SKILL.md"
  printf 'Existing private data\n' > "$test_case/external/keep"
}

snapshot() {
  for snapshot_root in "$test_home" "$test_repo/skills" "$test_case/external"; do
    if [ -e "$snapshot_root" ] || [ -L "$snapshot_root" ]; then
      find "$snapshot_root" -print
    fi
  done | sort | while IFS= read -r snapshot_path; do
    if [ -L "$snapshot_path" ]; then
      printf 'link %s -> %s\n' "$snapshot_path" "$(readlink "$snapshot_path")"
    elif [ -f "$snapshot_path" ]; then
      cksum "$snapshot_path"
    else
      printf 'directory %s\n' "$snapshot_path"
    fi
  done
}

run_setup() {
  (cd "$test_root" && env PATH="$test_setup_path" "$test_repo/setup.sh" --home "$test_home")
}

assert_layout() {
  [ -L "$test_home/.agents/skills" ]
  [ "$(readlink "$test_home/.agents/skills")" = "$test_repo/skills" ]
  [ -d "$test_home/.claude/skills" ]
  [ ! -L "$test_home/.claude/skills" ]
  [ ! -e "$test_repo/skills/skills" ]
}

reject_unchanged() {
  snapshot > "$test_case/before"
  if env PATH="$test_setup_path" "$test_repo/setup.sh" "$@" > "$test_case/stdout" 2> "$test_case/stderr"; then
    printf 'Expected setup to reject case %s\n' "$test_count" >&2
    exit 1
  fi
  [ -s "$test_case/stderr" ]
  snapshot > "$test_case/after"
  diff -u "$test_case/before" "$test_case/after"
}

# Fresh setup works from another working directory, including paths with spaces.
fixture
run_setup > /dev/null
assert_layout
snapshot > "$test_case/before"
run_setup > /dev/null
run_setup > /dev/null
snapshot > "$test_case/after"
diff -u "$test_case/before" "$test_case/after"

# Without Claude, setup leaves its paths absent and supports later installation.
fixture
rm "$test_setup_path/claude"
run_setup > /dev/null
[ -L "$test_home/.agents/skills" ]
[ ! -e "$test_home/.claude" ]
snapshot > "$test_case/before"
run_setup > /dev/null
snapshot > "$test_case/after"
diff -u "$test_case/before" "$test_case/after"
printf '#!/bin/sh\nexit 99\n' > "$test_setup_path/claude"
chmod +x "$test_setup_path/claude"
run_setup > /dev/null
assert_layout

# Existing independent data and relative links remain unchanged.
fixture
mkdir -p "$test_home/.agents" "$test_home/.claude/skills/synced"
ln -s ../../repository/skills "$test_home/.agents/skills"
printf 'Claude download\n' > "$test_home/.claude/skills/synced/keep"
printf 'Agent settings\n' > "$test_home/.agents/keep"
snapshot > "$test_case/before"
run_setup > /dev/null
snapshot > "$test_case/after"
diff -u "$test_case/before" "$test_case/after"

# Every existing entry at the shared link location is preserved on conflict.
for entry_type in directory file link dangling; do
  fixture
  mkdir -p "$test_home/.agents"
  case $entry_type in
    directory)
      mkdir "$test_home/.agents/skills"
      printf 'Custom skills\n' > "$test_home/.agents/skills/keep"
      ;;
    file) printf 'Keep this file\n' > "$test_home/.agents/skills" ;;
    link) ln -s "$test_case/external" "$test_home/.agents/skills" ;;
    dangling) ln -s "$test_case/missing" "$test_home/.agents/skills" ;;
  esac
  reject_unchanged --home "$test_home"
done

# Provider directories must be physical directories, including their parents.
for directory_path in .agents .claude .claude/skills; do
  for entry_type in file link dangling; do
    fixture
    conflict_path=$test_home/$directory_path
    mkdir -p "$(dirname "$conflict_path")"
    case $entry_type in
      file) printf 'Keep this file\n' > "$conflict_path" ;;
      link) ln -s "$test_case/external" "$conflict_path" ;;
      dangling) ln -s "$test_case/missing" "$conflict_path" ;;
    esac
    reject_unchanged --home "$test_home"
    if [ "$directory_path" != .agents ]; then
      rm "$test_setup_path/claude"
      mkdir -p "$test_home/.agents"
      ln -s "$test_repo/skills" "$test_home/.agents/skills"
      snapshot > "$test_case/before"
      run_setup > /dev/null
      snapshot > "$test_case/after"
      diff -u "$test_case/before" "$test_case/after"
    fi
  done
done

# Claude downloads must not remain under the shared source directory.
for entry_type in directory file dangling; do
  fixture
  case $entry_type in
    directory)
      mkdir "$test_repo/skills/synced"
      printf 'Claude download\n' > "$test_repo/skills/synced/keep"
      ;;
    file) printf 'Keep this file\n' > "$test_repo/skills/synced" ;;
    dangling) ln -s "$test_case/missing" "$test_repo/skills/synced" ;;
  esac
  reject_unchanged --home "$test_home"
  rm "$test_setup_path/claude"
  reject_unchanged --home "$test_home"
done

# The legacy shared Claude layout is rejected with every conflict identified.
fixture
mkdir -p "$test_home/.agents" "$test_home/.claude" "$test_repo/skills/synced"
ln -s "$test_repo/skills" "$test_home/.agents/skills"
ln -s "$test_home/.agents/skills" "$test_home/.claude/skills"
printf 'Claude download\n' > "$test_repo/skills/synced/keep"
reject_unchanged --home "$test_home"
grep -F "$test_home/.claude/skills" "$test_case/stderr" > /dev/null
grep -F "$test_repo/skills/synced" "$test_case/stderr" > /dev/null

# A missing, invalid, or redirected source never changes the destination.
for entry_type in missing file link; do
  fixture
  rm -r "$test_repo/skills"
  case $entry_type in
    file) printf 'Keep this file\n' > "$test_repo/skills" ;;
    link) ln -s "$test_case/external" "$test_repo/skills" ;;
  esac
  reject_unchanged --home "$test_home"
done

# Invalid arguments and home paths fail without changing any files.
fixture
reject_unchanged --unknown
reject_unchanged --unknown "$test_home"
reject_unchanged --home
reject_unchanged --home "$test_home" extra
reject_unchanged --home ''
reject_unchanged --home relative/path
reject_unchanged --home "$test_case/missing"
reject_unchanged --home "$test_case/external/keep"
reject_unchanged --home "$test_repo/skills"
reject_unchanged --home "$test_repo/skills/example"
snapshot > "$test_case/before"
"$test_repo/setup.sh" --help > /dev/null
"$test_repo/setup.sh" -h > /dev/null
snapshot > "$test_case/after"
diff -u "$test_case/before" "$test_case/after"

# Filesystem operation failures preserve existing data and do not install a link.
for failing_command in mkdir ln; do
  fixture
  mkdir -p "$test_home/.agents" "$test_home/.claude/skills"
  printf 'Existing Claude skill\n' > "$test_home/.claude/skills/keep"
  snapshot > "$test_case/before"
  if SETUP_TEST_FAILURE=$failing_command PATH="$test_setup_path" sh -c '
    mkdir() {
      [ "$SETUP_TEST_FAILURE" != mkdir ] || return 1
      command mkdir "$@"
    }
    ln() {
      [ "$SETUP_TEST_FAILURE" != ln ] || return 1
      command ln "$@"
    }
    . "$0"
  ' "$test_repo/setup.sh" --home "$test_home" > "$test_case/stdout" 2> "$test_case/stderr"; then
    printf 'Expected setup to fail when %s fails\n' "$failing_command" >&2
    exit 1
  fi
  snapshot > "$test_case/after"
  diff -u "$test_case/before" "$test_case/after"
done

# Concurrent installers cannot replace a link or create a nested skills link.
fixture
test_pids=''
for attempt in 1 2 3 4 5 6; do
  run_setup > "$test_case/run-$attempt" 2>&1 &
  test_pids="$test_pids $!"
done
for test_pid in $test_pids; do
  wait "$test_pid"
done
assert_layout

printf 'Setup tests passed (%s isolated fixtures).\n' "$test_count"
