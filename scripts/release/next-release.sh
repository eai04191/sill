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

# Without a release tag, git-cliff starts over at 0.1.0, which barik already released. Releases continue from barik's
# tags, so a checkout without them is a mistake, not a first release.
if [ -z "$(git tag --list --merged HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)" ]; then
  echo "No release tag (such as 0.5.1) is reachable from HEAD; fetch the tags first" >&2
  exit 1
fi

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
# Stop before building a version that was released already, rather than after the GitHub release.
if git rev-parse --quiet --verify "refs/tags/$version" > /dev/null; then
  echo "The tag $version exists already" >&2
  exit 1
fi
if grep -qx "## $version" CHANGELOG.md; then
  echo "CHANGELOG.md has $version already" >&2
  exit 1
fi
"$git_cliff" --unreleased --tag "$version" --output "$notes"
echo "$version"
