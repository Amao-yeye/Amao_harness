#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  die "Usage: $0 <target_project> <sub_task_name>"
fi

target_project=$1
task_name=$2

[[ -d "$target_project" ]] || die "Target directory does not exist: $target_project"

repo_root=$(git -C "$target_project" rev-parse --show-toplevel 2>/dev/null) ||
  die "Target is not inside a Git repository: $target_project"
repo_root=$(cd -- "$repo_root" && pwd -P)

if [[ ! "$task_name" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] ||
   [[ "$task_name" == "." || "$task_name" == ".." ]]; then
  die "Unsafe task name: $task_name"
fi

workspace="$repo_root/docs/agents"
[[ ! -L "$repo_root/docs" ]] || die "Refusing to use symlinked docs directory"
[[ -d "$workspace" && ! -L "$workspace" ]] ||
  die "Amao Harness is not installed; run install.sh first"

task_dir="$workspace/$task_name"
task_paths=(
  "$task_dir"
  "$task_dir/persistent"
  "$task_dir/working"
  "$task_dir/scratch"
)

for path in "${task_paths[@]}"; do
  [[ ! -L "$path" ]] || die "Refusing to use symlinked task path: $path"
  if [[ -e "$path" && ! -d "$path" ]]; then
    die "Task path exists and is not a directory: $path"
  fi
done

mkdir -p -- \
  "$task_dir/persistent" \
  "$task_dir/working" \
  "$task_dir/scratch"

printf 'Task workspace ready: %s\n' "$task_dir"
