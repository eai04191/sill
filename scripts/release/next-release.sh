#!/bin/sh
# Usage: next-release.sh <notes file>
# Prints the next version with git-cliff (cliff.toml) and writes its release notes to the notes file. Prints nothing
# and writes no notes when no commit since the last tag needs a release. GIT_CLIFF is the git-cliff to run.
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <notes file>" >&2
  exit 1
fi
notes=$1
git_cliff=${GIT_CLIFF:-git-cliff}

# Not piped, so a git-cliff failure stops the script instead of reading as nothing to release.
context=$("$git_cliff" --unreleased --context)
count=$(printf '%s' "$context" | jq '[.[].commits[]] | length')
if [ "$count" -eq 0 ]; then
  exit 0
fi

version=$("$git_cliff" --bumped-version)
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "git-cliff printed an unexpected version: $version" >&2
    exit 1
    ;;
esac
"$git_cliff" --unreleased --tag "$version" --output "$notes"
echo "$version"
