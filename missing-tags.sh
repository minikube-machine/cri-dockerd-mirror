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
  local limit="${2:-}"
  
  # Fetch tags using gh api. 
  # -q '.[].name' returns names.
  # The API returns tags in reverse chronological order (newest first).
  if [ -n "$limit" ]; then
    # For upstream, we only want the recent ones.
    # We don't use --paginate here because we only want the first page/top N
    gh api "repos/$repo/tags" --per-page "$limit" -q '.[].name'
  else
    # For downstream, we need all existing tags to check against
    gh api "repos/$repo/tags" --paginate -q '.[].name'
  fi
}

# Create temporary files for tag lists
upstream_tags_file=$(mktemp)
downstream_tags_file=$(mktemp)

# Cleanup on exit
trap 'rm -f "$upstream_tags_file" "$downstream_tags_file"' EXIT

echo "Fetching recent 5 tags for upstream: $upstream_repo" >&2
# Get top 5 tags, then sort them for 'comm'
get_tags "$upstream_repo" 5 | sort > "$upstream_tags_file"

echo "Fetching all tags for downstream: $downstream_repo" >&2
get_tags "$downstream_repo" | sort > "$downstream_tags_file"

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
