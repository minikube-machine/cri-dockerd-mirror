#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: missing-tags <downstream_repo> [upstream_repo]" >&2
  exit 1
fi

downstream_repo="$1"
upstream_repo="${2:-Mirantis/cri-dockerd}"

get_tags() {
  local repo="$1"
  # Fetch tags using gh api. --paginate to get all tags. -q '.[].name' for names.
  # Sort the output for comm/diff
  gh api "repos/$repo/tags" --paginate -q '.[].name' | sort
}

# Create temporary files for tag lists
upstream_tags_file=$(mktemp)
downstream_tags_file=$(mktemp)

# Cleanup on exit
trap 'rm -f "$upstream_tags_file" "$downstream_tags_file"' EXIT

echo "Fetching tags for upstream: $upstream_repo" >&2
get_tags "$upstream_repo" > "$upstream_tags_file"

echo "Fetching tags for downstream: $downstream_repo" >&2
get_tags "$downstream_repo" > "$downstream_tags_file"

# Find lines in upstream that are NOT in downstream
# comm -23 <(sort upstream) <(sort downstream)
# -2 suppresses lines only in file 2 (downstream)
# -3 suppresses lines in both
# So -23 gives lines unique to file 1 (upstream)
missing_tags=$(comm -23 "$upstream_tags_file" "$downstream_tags_file")

count=$(echo "$missing_tags" | grep -cve '^\s*$' || true)
echo "Found $count missing tags." >&2

# Convert newline-separated list to JSON array
if [ -z "$missing_tags" ]; then
  echo "[]"
else
  # Use jq if available, otherwise python/perl or manual construction
  if command -v jq >/dev/null 2>&1; then
    echo "$missing_tags" | jq -R . | jq -s -c .
  else
    # Fallback: manual JSON array construction
    # escape quotes just in case, though tags usually don't have them
    json="["
    first=true
    while IFS= read -r tag; do
      if [ "$first" = true ]; then
        first=false
      else
        json="$json,"
      fi
      json="$json\"$tag\""
    done <<< "$missing_tags"
    json="$json]"
    echo "$json"
  fi
fi
