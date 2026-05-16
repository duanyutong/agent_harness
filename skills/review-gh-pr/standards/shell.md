# Shell Scripts

**Reference**: [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) | [Ubuntu DashAsBinSh](https://wiki.ubuntu.com/DashAsBinSh)

## When to Use Shell

Use shell scripts for:

- **Small utilities** (<100 lines)
- **Build/deployment automation** (orchestrating other tools)
- **System administration tasks** (file operations, environment setup)
- **Simple wrappers** around complex command-line tools

**Avoid shell for**:

- Complex logic (>100 lines) → **Prefer Python**
- Data transformation → **Use Python or dedicated tools**
- Business logic → **Use Python**
- Workflows requiring sophisticated error handling → **Use Python**

---

## Choosing POSIX sh or Bash

| Use POSIX sh (`#!/bin/sh`)                             | Use bash (`#!/bin/bash`)                  |
| ------------------------------------------------------ | ----------------------------------------- |
| Maximum portability (Alpine, BSD, embedded systems)    | Arrays are needed                         |
| System init scripts, package scripts                   | Pattern matching in conditionals          |
| Simple wrappers, build scripts                         | `$RANDOM`, `$PIPESTATUS`, `$LINENO`       |
| When `/bin/sh` might be dash, ash, or other minimal sh | Process substitution `<()` `>()`          |
| CI environments with unknown shell                     | When you control the environment (Docker) |

**Important**: On many systems (Ubuntu, Debian, Alpine), `/bin/sh` is **not bash**; it is often dash or ash. Scripts that declare `#!/bin/sh` while using bash-specific features may fail silently or produce incorrect results.

**Recommendation**: Use `#!/bin/sh` for simple portable scripts. Use `#!/bin/bash` explicitly when bash-specific features are required, and document the reason.

---

## POSIX-Portable Shell (sh)

These practices work in any POSIX-compliant shell: bash, dash, ash, zsh, ksh.

### Shebang & Setup

```sh
#!/bin/sh
set -eu
```

**The setup has the following semantics**:

- `#!/bin/sh` — Use the system's POSIX shell (portable)
- `set -e` — Exit immediately if any command fails
- `set -u` — Treat undefined variables as errors

**Note**: `set -o pipefail` is a bashism. For POSIX sh, handle pipeline errors explicitly.

### Quoting (Critical)

Always quote variables. Unquoted variables split on whitespace and expand globs.

```sh
# Preferred
cp "${source_file}" "${dest_dir}/"
rm "${old_config}"

# Avoid: breaks on spaces and expands globs
cp $source_file $dest_dir/
```

### Command Substitution

Use `$(command)` instead of backticks. It nests cleanly and is easier to read.

```sh
# Preferred
version=$(grep 'version' pyproject.toml)
current_dir=$(pwd)

# Avoid: difficult to nest and read
version=`grep 'version' pyproject.toml`
```

### Tests and Conditionals

Use `[ ]` (single brackets) for POSIX portability:

```sh
# String comparison: use single =
if [ "$var" = "value" ]; then
  printf "match\n"
fi

# Check whether a value is empty or non-empty
if [ -z "$var" ]; then
  printf "var is empty\n"
fi

if [ -n "$var" ]; then
  printf "var is set\n"
fi

# File tests
if [ -f "$file" ]; then
  printf "file exists\n"
fi

# Numeric comparison: use -eq, -ne, -lt, -gt, -le, -ge
if [ "$count" -gt 10 ]; then
  printf "too many\n"
fi
```

**Important**: Use `=` not `==` in `[ ]`. The `==` operator is a bashism.

### Arithmetic

Use `$(( ))` for arithmetic; it is POSIX compliant:

```sh
# Preferred: POSIX arithmetic
total=$((total + 1))
result=$((num % 10))

# Avoid: bashisms
let total="total + 1"      # not POSIX
((total++))                # not POSIX
total=$((total++))         # increment operators not POSIX
```

### Output

Use `printf` instead of `echo` for portability. `echo` behaviour varies between shells.

```sh
# Preferred: portable and predictable
printf "Building version %s\n" "$version"
printf "Error: %s\n" "$message" >&2

# Avoid: echo -n and echo -e are not portable
echo -n "no newline"       # not POSIX
echo -e "tab\there"        # not POSIX
```

### Functions

Use the portable function syntax (no `function` keyword):

```sh
# Preferred: POSIX syntax
my_function() {
  local_var="$1"  # Note: 'local' is widely supported but not strictly POSIX
  printf "Processing %s\n" "$local_var"
}

# Avoid: bashism
function my_function {
  ...
}
```

### Source Files

Use `.` instead of `source`:

```sh
# Preferred: POSIX
. ./config.sh

# Avoid: bashism
source ./config.sh
```

### Here Documents

Here documents are POSIX-compliant:

```sh
cat <<EOF
This is a multi-line
string with $variable expansion
EOF

# For literal content (no expansion)
cat <<'EOF'
This $variable is NOT expanded
EOF
```

### Error Handling

```sh
# Check return values explicitly
if ! docker build -t "$image" .; then
  printf "Docker build failed\n" >&2
  exit 1
fi

# Or use || for inline handling
command_that_might_fail || exit 1
```

---

## Bash-Specific Features

When you need these features, use `#!/bin/bash` explicitly.

### Bash Shebang & Setup

```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Additional options**:

- `set -o pipefail` — Pipeline fails if _any_ command fails (bash-specific)
- Using `env bash` finds bash in PATH (more portable than `/bin/bash`)

### Extended Tests with `[[ ]]`

`[[ ]]` provides safer semantics and pattern matching:

```bash
# Pattern matching (bash-specific)
if [[ "$filename" == *.txt ]]; then
  printf "Text file\n"
fi

# Regex matching (bash-specific)
if [[ "$email" =~ ^[a-z]+@[a-z]+\.[a-z]+$ ]]; then
  printf "Valid email format\n"
fi

# No word splitting occurs inside [[ ]]
if [[ -f $file_with_spaces ]]; then
  printf "File exists\n"
fi
```

### Arrays

Arrays are essential for safely handling lists of arguments:

```bash
# Declare and populate
declare -a docker_args=(
  "--rm"
  "--interactive"
  "--tty"
  "--env" "LOG_LEVEL=$LOG_LEVEL"
)

# Expand safely
docker run "${docker_args[@]}" "$image"

# Iterate
for arg in "${docker_args[@]}"; do
  printf "Arg: %s\n" "$arg"
done
```

### Arithmetic with `(( ))`

```bash
# Clear numeric comparisons
if (( count > 10 )); then
  printf "Too many\n"
fi

# Increment/decrement while avoiding set -e pitfalls
(( i += 1 ))
```

**Warning**: `(( i++ ))` returns 1 (failure) when i starts at 0, which triggers `set -e`. Use `(( i += 1 ))` or `(( ++i ))` instead.

### Process Substitution

```bash
# Compare two command outputs
diff <(sort file1) <(sort file2)

# Feed command output as a file
while read -r line; do
  process "$line"
done < <(generate_lines)
```

### Special Variables

```bash
# Random number (bash-specific)
random_num=$RANDOM

# Pipeline exit statuses (bash-specific)
cmd1 | cmd2 | cmd3
if (( PIPESTATUS[0] != 0 )); then
  printf "cmd1 failed\n" >&2
fi

# Current line number (bash-specific, useful for debugging)
printf "Debug at line %d\n" "$LINENO"
```

### Here Strings

```bash
# Feed a string as stdin (bash-specific)
grep "pattern" <<< "$string_variable"
```

---

## Common Practices (All Shells)

### Use `local` for Function Variables

`local` is widely supported (bash, dash, zsh, ksh) though not strictly POSIX:

```sh
build_app() {
  local app_name="$1"
  local build_dir="build"

  printf "Building %s in %s\n" "$app_name" "$build_dir"
}
```

### Constants with `readonly`

```sh
readonly LOG_LEVEL="INFO"
readonly MAX_RETRIES=3
readonly CONFIG_DIR="${HOME}/.config/myapp"
```

### Main Function Pattern

For scripts >10 lines, use a `main()` function:

```sh
#!/bin/sh
set -eu

build_app() {
  local app="$1"
  printf "Building %s\n" "$app"
}

main() {
  build_app "switchboard"
}

main "$@"
```

### Trap for Clean-Up

```sh
cleanup() {
  rm -rf "$temp_dir"
}

main() {
  temp_dir=$(mktemp -d)
  trap cleanup EXIT

  # Work with temp_dir
  printf "Using %s\n" "$temp_dir"
}
```

### Script Directory

Determine the directory containing the script; this form is compatible with most shells:

```sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
config_file="${script_dir}/config.sh"
```

---

## ShellCheck

**ShellCheck is required** for all shell scripts.

```bash
# Check a script
shellcheck script.sh

# Check all scripts
shellcheck scripts/*.sh
```

ShellCheck catches:

- Unquoted variables (SC2086)
- Bashisms in sh scripts (SC2039, SC3000+)
- Undefined variables
- Common errors

### Disabling Checks, Rarely

```sh
# shellcheck disable=SC2086
# Intentionally unquoted for glob expansion
rm $backup_files
```

---

## Practices to Avoid

### Avoid `eval`

```sh
# Unsafe
eval "$command_string"

# Preferred: use arrays in bash, or explicit commands
"$cmd" "$arg1" "$arg2"
```

### Avoid Aliases in Scripts

Aliases only work in interactive shells:

```sh
# Ineffective in scripts
alias ll='ls -la'
ll /tmp

# Preferred: use functions
ll() { ls -la "$@"; }
```

### Avoid SUID/SGID

Shell scripts cannot securely use SUID. Use `sudo` instead.

### Avoid Ambiguous Relative Paths

```sh
# Avoid: breaks if called from a different directory
config_file="./config.sh"

# Preferred: absolute path
script_dir="$(cd "$(dirname "$0")" && pwd)"
config_file="${script_dir}/config.sh"
```

---

## Quick Reference: Bashisms to Avoid in sh

| Bashism             | POSIX Alternative              |
| ------------------- | ------------------------------ |
| `[[ ]]`             | `[ ]` with proper quoting      |
| `==` in test        | `=`                            |
| `(( ))`             | `$(( ))` or `[ -gt ]` forms    |
| `function f { }`    | `f() { }`                      |
| `source`            | `.`                            |
| `echo -e` / `-n`    | `printf`                       |
| `${var/pat/repl}`   | Use sed                        |
| `${var:0:3}`        | Use expr or awk                |
| Arrays              | Positional parameters or IFS   |
| `<<<`               | `echo ... \|` or here-doc      |
| `&>`                | `> file 2>&1`                  |
| `$RANDOM`           | `/dev/urandom`                 |
| `$PIPESTATUS`       | Named pipes or explicit checks |
| `read -p "prompt"`  | `printf "prompt"; read var`    |
| `select`            | Manual menu implementation     |
| `{a,b,c}` expansion | Write out explicitly           |

---

## Further Reading

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [ShellCheck](https://www.shellcheck.net/)
- [Ubuntu DashAsBinSh](https://wiki.ubuntu.com/DashAsBinSh) — Common bashisms and fixes
- [Wooledge Bashism List](https://mywiki.wooledge.org/Bashism) — Comprehensive reference
- [POSIX Shell Specification](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)
