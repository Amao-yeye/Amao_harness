#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  die "Usage: $0 <target_project>"
fi

target_project=$1
[[ -d "$target_project" ]] || die "Target directory does not exist: $target_project"

repo_root=$(git -C "$target_project" rev-parse --show-toplevel 2>/dev/null) ||
  die "Target is not inside a Git repository: $target_project"
repo_root=$(cd -- "$repo_root" && pwd -P)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_agents="$script_dir/AGENTS.md"
target_agents="$repo_root/AGENTS.md"

[[ -f "$source_agents" ]] || die "Harness AGENTS.md is missing: $source_agents"

if git -C "$repo_root" ls-files --error-unmatch -- AGENTS.md >/dev/null 2>&1; then
  die "Refusing to overwrite tracked AGENTS.md"
fi

if [[ -e "$target_agents" || -L "$target_agents" ]]; then
  if ! cmp -s -- "$source_agents" "$target_agents"; then
    die "Refusing to overwrite conflicting untracked AGENTS.md"
  fi
fi

[[ ! -L "$repo_root/docs" ]] || die "Refusing to use symlinked docs directory"
[[ ! -L "$repo_root/docs/agents" ]] || die "Refusing to use symlinked docs/agents directory"

exclude_path=$(git -C "$repo_root" rev-parse --git-path info/exclude)
if [[ "$exclude_path" != /* ]]; then
  exclude_path="$repo_root/$exclude_path"
fi
mkdir -p -- "$(dirname -- "$exclude_path")"
touch -- "$exclude_path"

exclude_lines=()
if ! grep -Fqx -- '/AGENTS.md' "$exclude_path"; then
  exclude_lines+=('/AGENTS.md')
fi
if ! grep -Fqx -- '/docs/agents/' "$exclude_path"; then
  exclude_lines+=('/docs/agents/')
fi

if (( ${#exclude_lines[@]} > 0 )); then
  if [[ -s "$exclude_path" ]]; then
    printf '\n' >>"$exclude_path"
  fi
  if ! grep -Fqx -- '# Amao Harness' "$exclude_path"; then
    printf '%s\n' '# Amao Harness' >>"$exclude_path"
  fi
  printf '%s\n' "${exclude_lines[@]}" >>"$exclude_path"
fi

if [[ ! -e "$target_agents" ]]; then
  cp -- "$source_agents" "$target_agents"
fi
mkdir -p -- "$repo_root/docs/agents"

printf 'Amao Harness installed in %s\n' "$repo_root"
