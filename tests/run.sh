#!/usr/bin/env bash

set -euo pipefail

harness_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
install_script="$harness_root/install.sh"
new_task_script="$harness_root/scripts/new-task.sh"

test_root=$(mktemp -d "${TMPDIR:-/tmp}/amao-harness-tests.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

init_repo() {
  git init -q "$1"
}

exclude_file() {
  local repo=$1
  local path
  path=$(git -C "$repo" rev-parse --git-path info/exclude)
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$repo" "$path"
  fi
}

# Test 1 — normal install, including repository-root discovery from a subdirectory.
normal_repo="$test_root/normal repo"
init_repo "$normal_repo"
mkdir -p "$normal_repo/nested"
normal_exclude=$(exclude_file "$normal_repo")
printf '/keep-local\n' >>"$normal_exclude"
"$install_script" "$normal_repo/nested" >/dev/null
[[ -f "$normal_repo/AGENTS.md" ]] || fail "normal install did not create AGENTS.md"
cmp -s "$harness_root/AGENTS.md" "$normal_repo/AGENTS.md" || fail "installed AGENTS.md differs"
[[ -d "$normal_repo/docs/agents" ]] || fail "normal install did not create docs/agents"
[[ ! -e "$normal_repo/.gitignore" ]] || fail "installer modified .gitignore"
normal_exclude=$(exclude_file "$normal_repo")
grep -Fqx -- '/keep-local' "$normal_exclude" || fail "existing exclude rule was changed"
grep -Fqx -- '# Amao Harness' "$normal_exclude" || fail "exclude marker is missing"
grep -Fqx -- '/AGENTS.md' "$normal_exclude" || fail "AGENTS.md exclude is missing"
grep -Fqx -- '/docs/agents/' "$normal_exclude" || fail "workspace exclude is missing"
[[ -z "$(git -C "$normal_repo" status --short)" ]] || fail "installed files are visible to Git"
pass "normal install"

# Test 2 — repeated install does not duplicate local excludes.
"$install_script" "$normal_repo" >/dev/null
[[ $(grep -Fxc -- '# Amao Harness' "$normal_exclude") -eq 1 ]] || fail "exclude marker was duplicated"
[[ $(grep -Fxc -- '/AGENTS.md' "$normal_exclude") -eq 1 ]] || fail "AGENTS.md exclude was duplicated"
[[ $(grep -Fxc -- '/docs/agents/' "$normal_exclude") -eq 1 ]] || fail "workspace exclude was duplicated"
pass "repeated install"

# Test 3 — a tracked AGENTS.md is never overwritten.
tracked_repo="$test_root/tracked"
init_repo "$tracked_repo"
git -C "$tracked_repo" config user.name "Amao Harness Tests"
git -C "$tracked_repo" config user.email "tests@example.invalid"
printf 'team rules\n' >"$tracked_repo/AGENTS.md"
git -C "$tracked_repo" add AGENTS.md
git -C "$tracked_repo" commit -qm "add team rules"
if tracked_output=$("$install_script" "$tracked_repo" 2>&1); then
  fail "tracked AGENTS.md was accepted"
fi
[[ "$tracked_output" == *"Refusing to overwrite tracked AGENTS.md"* ]] || fail "tracked-file error is unclear"
[[ $(<"$tracked_repo/AGENTS.md") == "team rules" ]] || fail "tracked AGENTS.md was changed"
[[ ! -e "$tracked_repo/docs/agents" ]] || fail "tracked-file refusal made workspace changes"
pass "tracked AGENTS.md refusal"

# Test 4 — a conflicting untracked AGENTS.md is never overwritten.
conflict_repo="$test_root/conflict"
init_repo "$conflict_repo"
printf 'local rules\n' >"$conflict_repo/AGENTS.md"
if conflict_output=$("$install_script" "$conflict_repo" 2>&1); then
  fail "conflicting untracked AGENTS.md was accepted"
fi
[[ "$conflict_output" == *"Refusing to overwrite conflicting untracked AGENTS.md"* ]] || fail "conflict error is unclear"
[[ $(<"$conflict_repo/AGENTS.md") == "local rules" ]] || fail "conflicting AGENTS.md was changed"
[[ ! -e "$conflict_repo/docs/agents" ]] || fail "conflict refusal made workspace changes"
pass "untracked AGENTS.md conflict refusal"

# Test 5 — task creation makes exactly the required directories.
"$new_task_script" "$normal_repo" example_task >/dev/null
for directory in persistent working scratch; do
  [[ -d "$normal_repo/docs/agents/example_task/$directory" ]] || fail "task directory $directory is missing"
done
pass "new task"

# Test 6 — repeated task creation preserves existing content.
printf 'keep me\n' >"$normal_repo/docs/agents/example_task/persistent/keep.txt"
"$new_task_script" "$normal_repo" example_task >/dev/null
[[ $(<"$normal_repo/docs/agents/example_task/persistent/keep.txt") == "keep me" ]] || fail "task recreation changed content"
pass "repeated task creation"

# Test 7 — unsafe task names are rejected without escaping the workspace.
for unsafe_name in '' '../abc' '../../tmp' '/absolute/path'; do
  if "$new_task_script" "$normal_repo" "$unsafe_name" >/dev/null 2>&1; then
    fail "unsafe task name was accepted: $unsafe_name"
  fi
done
[[ ! -e "$normal_repo/docs/abc" ]] || fail "unsafe task escaped docs/agents"
pass "unsafe task names"

# Test 8 — non-Git directories are rejected by both commands without changes.
non_git="$test_root/non-git"
mkdir -p "$non_git"
if "$install_script" "$non_git" >/dev/null 2>&1; then
  fail "install accepted a non-Git directory"
fi
if "$new_task_script" "$non_git" example_task >/dev/null 2>&1; then
  fail "new-task accepted a non-Git directory"
fi
[[ -z "$(find "$non_git" -mindepth 1 -print -quit)" ]] || fail "non-Git refusal made changes"
pass "non-Git directory refusal"

# Additional regression — Git linked worktrees use Git's resolved exclude path.
main_repo="$test_root/main-worktree"
linked_repo="$test_root/linked-worktree"
init_repo "$main_repo"
git -C "$main_repo" config user.name "Amao Harness Tests"
git -C "$main_repo" config user.email "tests@example.invalid"
printf 'base\n' >"$main_repo/README.md"
git -C "$main_repo" add README.md
git -C "$main_repo" commit -qm "initial commit"
git -C "$main_repo" worktree add -q -b harness-test "$linked_repo"
"$install_script" "$linked_repo" >/dev/null
linked_exclude=$(exclude_file "$linked_repo")
grep -Fqx -- '/AGENTS.md' "$linked_exclude" || fail "linked-worktree exclude is missing"
[[ -z "$(git -C "$linked_repo" status --short)" ]] || fail "linked-worktree files are visible to Git"
pass "linked worktree install"

printf 'All tests passed.\n'
