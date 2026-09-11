#!/usr/bin/env bash

set -euo pipefail

managed_marker='<!-- Managed by Amao Harness -->'
metadata_name='amao-harness/AGENTS.md.hash'

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
[[ "$(head -n 1 -- "$source_agents")" == "$managed_marker" ]] ||
  die "Harness AGENTS.md is missing its managed marker"

if git -C "$repo_root" ls-files --error-unmatch -- AGENTS.md >/dev/null 2>&1; then
  die "Refusing to overwrite tracked AGENTS.md"
fi

[[ -e "$target_agents" || -L "$target_agents" ]] ||
  die "Amao Harness does not appear to be installed. Run install.sh first."

[[ ! -L "$target_agents" ]] || die "Refusing to overwrite symlinked AGENTS.md"
[[ "$(head -n 1 -- "$target_agents")" == "$managed_marker" ]] ||
  die "Refusing to overwrite unmanaged AGENTS.md"

metadata_path=$(git -C "$repo_root" rev-parse --git-path "$metadata_name")
if [[ "$metadata_path" != /* ]]; then
  metadata_path="$repo_root/$metadata_path"
fi
metadata_dir=$(dirname -- "$metadata_path")
[[ ! -L "$metadata_dir" ]] || die "Refusing to use symlinked Amao Harness metadata directory"
if [[ -e "$metadata_path" || -L "$metadata_path" ]]; then
  [[ -f "$metadata_path" && ! -L "$metadata_path" ]] ||
    die "Refusing to use invalid Amao Harness metadata"
fi

current_hash=$(git -C "$repo_root" hash-object --no-filters -- "$target_agents")
source_hash=$(git -C "$repo_root" hash-object --no-filters -- "$source_agents")

if [[ -f "$metadata_path" ]]; then
  installed_hash=$(<"$metadata_path")
  if [[ "$current_hash" != "$installed_hash" ]]; then
    die "Local AGENTS.md has been modified since the last Amao Harness install/update. Refusing to overwrite."
  fi
elif [[ "$current_hash" != "$source_hash" ]]; then
  die "Amao Harness update metadata is missing. Refusing to overwrite. Run install.sh first."
fi

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

if ! cmp -s -- "$source_agents" "$target_agents"; then
  cp -- "$source_agents" "$target_agents"
fi

mkdir -p -- "$metadata_dir"
printf '%s\n' "$source_hash" >"$metadata_path"

printf 'Amao Harness updated in %s\n' "$repo_root"
