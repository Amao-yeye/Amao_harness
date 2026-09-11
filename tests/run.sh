#!/usr/bin/env bash

set -euo pipefail

harness_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
install_script="$harness_root/install.sh"
update_script="$harness_root/update.sh"
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

metadata_file() {
  local repo=$1
  local path
  path=$(git -C "$repo" rev-parse --git-path amao-harness/AGENTS.md.hash)
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
[[ $(head -n 1 -- "$normal_repo/AGENTS.md") == '<!-- Managed by Amao Harness -->' ]] || fail "managed marker is missing"
[[ -d "$normal_repo/docs/agents" ]] || fail "normal install did not create docs/agents"
[[ ! -e "$normal_repo/.gitignore" ]] || fail "installer modified .gitignore"
normal_exclude=$(exclude_file "$normal_repo")
grep -Fqx -- '/keep-local' "$normal_exclude" || fail "existing exclude rule was changed"
grep -Fqx -- '# Amao Harness' "$normal_exclude" || fail "exclude marker is missing"
grep -Fqx -- '/AGENTS.md' "$normal_exclude" || fail "AGENTS.md exclude is missing"
grep -Fqx -- '/docs/agents/' "$normal_exclude" || fail "workspace exclude is missing"
normal_metadata=$(metadata_file "$normal_repo")
[[ -f "$normal_metadata" ]] || fail "install metadata is missing"
normal_hash=$(git -C "$normal_repo" hash-object --no-filters -- "$normal_repo/AGENTS.md")
[[ $(<"$normal_metadata") == "$normal_hash" ]] || fail "install metadata hash is incorrect"
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

# Test 8 — non-Git directories are rejected by all commands without changes.
non_git="$test_root/non-git"
mkdir -p "$non_git"
if "$install_script" "$non_git" >/dev/null 2>&1; then
  fail "install accepted a non-Git directory"
fi
if "$new_task_script" "$non_git" example_task >/dev/null 2>&1; then
  fail "new-task accepted a non-Git directory"
fi
if non_git_update_output=$("$update_script" "$non_git" 2>&1); then
  fail "update accepted a non-Git directory"
fi
[[ "$non_git_update_output" == *"Target is not inside a Git repository"* ]] || fail "non-Git update error is unclear"
[[ -z "$(find "$non_git" -mindepth 1 -print -quit)" ]] || fail "non-Git refusal made changes"
pass "non-Git directory refusal"

# Update Test 1 — normal update from a repository subdirectory preserves project state.
mkdir -p "$normal_repo/src" "$normal_repo/tests" "$normal_repo/debug"
printf 'src sentinel\n' >"$normal_repo/src/keep.txt"
printf 'tests sentinel\n' >"$normal_repo/tests/keep.txt"
printf 'debug sentinel\n' >"$normal_repo/debug/keep.txt"
"$update_script" "$normal_repo/nested" >/dev/null
cmp -s "$harness_root/AGENTS.md" "$normal_repo/AGENTS.md" || fail "normal update did not synchronize AGENTS.md"
[[ $(<"$normal_repo/docs/agents/example_task/persistent/keep.txt") == "keep me" ]] || fail "update changed task history"
[[ $(<"$normal_repo/src/keep.txt") == "src sentinel" ]] || fail "update changed src"
[[ $(<"$normal_repo/tests/keep.txt") == "tests sentinel" ]] || fail "update changed tests"
[[ $(<"$normal_repo/debug/keep.txt") == "debug sentinel" ]] || fail "update changed debug"
pass "normal update"

# Update Test 2 — repeated updates are idempotent.
"$update_script" "$normal_repo" >/dev/null
"$update_script" "$normal_repo" >/dev/null
[[ $(grep -Fxc -- '# Amao Harness' "$normal_exclude") -eq 1 ]] || fail "update duplicated exclude marker"
[[ $(grep -Fxc -- '/AGENTS.md' "$normal_exclude") -eq 1 ]] || fail "update duplicated AGENTS.md exclude"
[[ $(grep -Fxc -- '/docs/agents/' "$normal_exclude") -eq 1 ]] || fail "update duplicated workspace exclude"
[[ $(<"$normal_metadata") == "$normal_hash" ]] || fail "repeated update changed metadata hash"
pass "repeated update"

# Update Test 3 — a newer Harness AGENTS.md replaces the recorded managed version.
rules_repo="$test_root/rules-change"
init_repo "$rules_repo"
"$install_script" "$rules_repo" >/dev/null
updated_harness="$test_root/updated-harness"
mkdir -p "$updated_harness"
cp -- "$update_script" "$updated_harness/update.sh"
cp -- "$harness_root/AGENTS.md" "$updated_harness/AGENTS.md"
printf '\nTest-only Harness rule revision.\n' >>"$updated_harness/AGENTS.md"
"$updated_harness/update.sh" "$rules_repo" >/dev/null
cmp -s "$updated_harness/AGENTS.md" "$rules_repo/AGENTS.md" || fail "changed Harness rules were not installed"
rules_metadata=$(metadata_file "$rules_repo")
rules_hash=$(git -C "$rules_repo" hash-object --no-filters -- "$rules_repo/AGENTS.md")
[[ $(<"$rules_metadata") == "$rules_hash" ]] || fail "changed Harness metadata hash is incorrect"
pass "Harness rule update"

# Update Test 4 — local edits conflict with the last recorded install.
modified_repo="$test_root/locally-modified"
init_repo "$modified_repo"
"$install_script" "$modified_repo" >/dev/null
printf '\nlocal project rule\n' >>"$modified_repo/AGENTS.md"
modified_hash=$(git -C "$modified_repo" hash-object --no-filters -- "$modified_repo/AGENTS.md")
if modified_output=$("$update_script" "$modified_repo" 2>&1); then
  fail "locally modified AGENTS.md was overwritten"
fi
[[ "$modified_output" == *"Local AGENTS.md has been modified since the last Amao Harness install/update"* ]] || fail "local-modification error is unclear"
[[ $(git -C "$modified_repo" hash-object --no-filters -- "$modified_repo/AGENTS.md") == "$modified_hash" ]] || fail "local AGENTS.md modification was changed"
pass "local AGENTS.md conflict"

# Update Test 5 — tracked AGENTS.md is always refused.
tracked_update_repo="$test_root/tracked-update"
init_repo "$tracked_update_repo"
git -C "$tracked_update_repo" config user.name "Amao Harness Tests"
git -C "$tracked_update_repo" config user.email "tests@example.invalid"
"$install_script" "$tracked_update_repo" >/dev/null
git -C "$tracked_update_repo" add -f AGENTS.md
git -C "$tracked_update_repo" commit -qm "track managed rules"
tracked_update_hash=$(git -C "$tracked_update_repo" hash-object --no-filters -- "$tracked_update_repo/AGENTS.md")
if tracked_update_output=$("$update_script" "$tracked_update_repo" 2>&1); then
  fail "tracked AGENTS.md was updated"
fi
[[ "$tracked_update_output" == *"Refusing to overwrite tracked AGENTS.md"* ]] || fail "tracked update error is unclear"
[[ $(git -C "$tracked_update_repo" hash-object --no-filters -- "$tracked_update_repo/AGENTS.md") == "$tracked_update_hash" ]] || fail "tracked AGENTS.md was changed by update"
pass "tracked AGENTS.md update refusal"

# Update Test 6 — an untracked file without the managed marker is refused.
unmanaged_repo="$test_root/unmanaged-update"
init_repo "$unmanaged_repo"
printf 'project-owned local rules\n' >"$unmanaged_repo/AGENTS.md"
if unmanaged_output=$("$update_script" "$unmanaged_repo" 2>&1); then
  fail "unmanaged AGENTS.md was updated"
fi
[[ "$unmanaged_output" == *"Refusing to overwrite unmanaged AGENTS.md"* ]] || fail "unmanaged update error is unclear"
[[ $(<"$unmanaged_repo/AGENTS.md") == "project-owned local rules" ]] || fail "unmanaged AGENTS.md was changed"
[[ ! -e "$(metadata_file "$unmanaged_repo")" ]] || fail "unmanaged refusal created metadata"
pass "unmanaged AGENTS.md update refusal"

# Update Test 7 — update does not act as install when AGENTS.md is absent.
missing_agents_repo="$test_root/missing-agents"
init_repo "$missing_agents_repo"
if missing_agents_output=$("$update_script" "$missing_agents_repo" 2>&1); then
  fail "update installed a missing AGENTS.md"
fi
[[ "$missing_agents_output" == *"Amao Harness does not appear to be installed. Run install.sh first."* ]] || fail "missing-install error is unclear"
[[ ! -e "$missing_agents_repo/AGENTS.md" ]] || fail "update created a missing AGENTS.md"
[[ ! -e "$(metadata_file "$missing_agents_repo")" ]] || fail "missing-install refusal created metadata"
pass "missing AGENTS.md update refusal"

# Update Test 8 — missing Harness excludes are restored without changing other rules.
exclude_repo="$test_root/missing-excludes"
init_repo "$exclude_repo"
"$install_script" "$exclude_repo" >/dev/null
exclude_repo_file=$(exclude_file "$exclude_repo")
printf '/keep-update-local\n' >"$exclude_repo_file"
"$update_script" "$exclude_repo" >/dev/null
grep -Fqx -- '/keep-update-local' "$exclude_repo_file" || fail "update changed an existing exclude"
[[ $(grep -Fxc -- '# Amao Harness' "$exclude_repo_file") -eq 1 ]] || fail "update did not restore the exclude marker"
[[ $(grep -Fxc -- '/AGENTS.md' "$exclude_repo_file") -eq 1 ]] || fail "update did not restore AGENTS.md exclude"
[[ $(grep -Fxc -- '/docs/agents/' "$exclude_repo_file") -eq 1 ]] || fail "update did not restore workspace exclude"
[[ ! -e "$exclude_repo/.gitignore" ]] || fail "update modified .gitignore"
pass "exclude restoration"

# Update Test 9 — missing arguments and directories fail before making changes.
if usage_output=$("$update_script" 2>&1); then
  fail "update accepted a missing argument"
fi
[[ "$usage_output" == *"Usage:"* ]] || fail "update usage error is unclear"
missing_target="$test_root/does-not-exist"
if missing_target_output=$("$update_script" "$missing_target" 2>&1); then
  fail "update accepted a missing target directory"
fi
[[ "$missing_target_output" == *"Target directory does not exist"* ]] || fail "missing-directory error is unclear"
[[ ! -e "$missing_target" ]] || fail "missing-directory refusal created the target"
pass "update argument validation"

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
"$update_script" "$linked_repo" >/dev/null
linked_exclude=$(exclude_file "$linked_repo")
grep -Fqx -- '/AGENTS.md' "$linked_exclude" || fail "linked-worktree exclude is missing"
[[ -f "$(metadata_file "$linked_repo")" ]] || fail "linked-worktree metadata is missing"
[[ -z "$(git -C "$linked_repo" status --short)" ]] || fail "linked-worktree files are visible to Git"
pass "linked worktree install and update"

printf 'All tests passed.\n'
