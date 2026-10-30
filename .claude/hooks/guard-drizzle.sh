#!/usr/bin/env bash
# PreToolUse guard: nothing writes in drizzle/ except `npm run db:generate`.
# drizzle/ holds the generated migrations and their snapshots (meta/). A
# hand-edited migration drifts from the snapshot, and the next generate is
# wrong. Covers the file tools (Write, Edit, MultiEdit, NotebookEdit), shell
# commands that touch the folder, and the drizzle-kit commands that rewrite it.
# Exit 2 = block, stderr = reason (the agent reads it).
block() {
  echo "Blocked by guard-drizzle: $1" >&2
  echo "drizzle/ is generated, never edited by hand. Instead: change the schema in src/db/schema.ts, then run npm run db:generate." >&2
  exit 2
}

# Without jq the guard reads an empty input and lets everything through: fail closed.
command -v jq >/dev/null || block "jq is missing: install it (see the setup guide)"
input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
project=${CLAUDE_PROJECT_DIR:-$cwd}
lower() { tr '[:upper:]' '[:lower:]'; }

# Absolute, symlink-resolved path, also for files that do not exist yet:
# resolve the deepest existing directory, then append the rest.
resolve() {
  local p=$1 rest=""
  [[ $p = /* ]] || p="${cwd:-$PWD}/$p"
  while [ ! -d "$p" ]; do
    rest="/$(basename "$p")$rest"
    p=$(dirname "$p")
  done
  p=$(cd "$p" && pwd -P)$rest
  # Collapse any ".." / "." left in the non-existing tail.
  local out=() part
  IFS=/ read -ra parts <<<"$p"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  local IFS=/; echo "/${out[*]}"
}

# 1. File tools. Compared case-insensitively: macOS file systems are, by default.
case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
    [ -n "$path" ] || exit 0
    target=$(resolve "$path" | lower)
    folder=$(resolve "$project/drizzle" | lower)
    if [ "$target" = "$folder" ] || [[ $target = "$folder"/* ]]; then
      block "$tool on $path"
    fi
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac

# 2. Shell. Split the command into simple commands (on ; & | newlines, $( ( ` { ).
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
# Redirects to /dev/null or another file descriptor (2>&1, &>/dev/null) are dropped
# first: they write nowhere, and their & is not a separator.
plain=$(sed -E 's#(&|[0-9]*)>>?[[:space:]]*(/dev/null|&[0-9-])##g' <<<"$cmd")
segments=$(awk '{ gsub(/\|\||&&|[;&|`({]|\$\(/, "\n"); print }' <<<"$plain")

# drizzle-kit commands that rewrite drizzle/: drop deletes a migration, up rewrites
# the snapshots, pull/introspect write into it, and generate goes through npm.
if grep -Eiq '(^|[^[:alnum:]_-])drizzle-kit[^[:space:]]*[[:space:]]+([^[:space:]]+[[:space:]]+)*(drop|up|pull|introspect|generate)([[:space:]]|$)' <<<"$segments"; then
  block "drizzle-kit drop / up / pull / introspect / generate are not allowed (generate only as npm run db:generate)"
fi

# Does the command name the drizzle/ folder? drizzle-kit, drizzle-orm and
# drizzle.config.ts are not the folder.
names_folder() {
  lower <<<"$1" | sed -E 's/drizzle[-.][[:alnum:]]//g' | grep -Eq '(^|[^[:alnum:]_-])drizzle([^[:alnum:]_-]|$)'
}
names_folder "$cmd" || exit 0

# It does: then every simple command in it must be read-only, so that
# `cd drizzle && rm x` is caught too. Anything not on this list is blocked.
while IFS= read -r seg; do
  seg=$(sed -E 's/^[[:space:]!]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' <<<"$seg")
  [ -n "$seg" ] || continue
  word=$(basename -- "${seg%%[[:space:]]*}")
  case "$word" in
    cat|head|tail|less|more|ls|tree|grep|egrep|fgrep|rg|wc|diff|cmp|sort|uniq|cut|tr|\
    jq|file|stat|du|realpath|readlink|basename|dirname|echo|printf|test|\[|true|false|\
    cd|pwd|nl|od|xxd|hexdump|md5sum|sha256sum|shasum|column|awk) ;;
    sed) grep -Eq '[[:space:]](-[[:alnum:]]*i|--in-place)' <<<"$seg" && block "sed -i on drizzle/" ;;
    find) grep -Eq '[[:space:]]-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)([[:space:]]|$)' <<<"$seg" \
            && block "find -delete / -exec on drizzle/" ;;
    git) grep -Eq '^git[[:space:]]+(add|commit|diff|log|show|status|blame|ls-files|grep)([[:space:]]|$)' <<<"$seg" \
           || block "only read-only git (and add / commit) may name drizzle/: $seg" ;;
    npm) grep -Eq '^npm[[:space:]]+run[[:space:]]+db:generate([[:space:]]|$)' <<<"$seg" \
           || block "only npm run db:generate may write drizzle/: $seg" ;;
    *) block "\`$word\` in a command that names drizzle/ (only read-only commands may)" ;;
  esac
done <<<"$segments"

# Read-only commands can still write through a redirect (echo x > drizzle/y.sql).
# Only redirects to /dev/null or another file descriptor are fine.
if grep -q '>' <<<"$plain"; then
  block "redirect (> or >>) in a command that names drizzle/"
fi

exit 0
