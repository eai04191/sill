#!/bin/sh
# Usage: prepend-changelog.sh <version> <notes file>
# Adds the release notes as a "## <version>" section at the top of CHANGELOG.md, under its "# Changelog" title. The
# release job of the release workflow runs this after the GitHub release is created.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <version> <notes file>" >&2
  exit 1
fi
version=$1
notes=$2
changelog=CHANGELOG.md

if [ "$(head -n 1 "$changelog")" != "# Changelog" ]; then
  echo "$changelog does not start with # Changelog" >&2
  exit 1
fi
if grep -qx "## $version" "$changelog"; then
  echo "$changelog already has $version" >&2
  exit 1
fi

{
  echo "# Changelog"
  echo
  echo "## $version"
  echo
  # git-cliff starts the notes with an empty line.
  sed '/./,$!d' "$notes"
  echo
  tail -n +2 "$changelog" | sed '1{/^$/d;}'
} > "$changelog.new"
mv "$changelog.new" "$changelog"
