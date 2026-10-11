#!/bin/sh
# Usage: update-tap.sh <version> <tap directory>
# Writes the cask for dist/Sill-<version>.zip into a checkout of the tap, commits and pushes it. The release workflow
# runs this after the zip is on GitHub Releases.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <version> <tap directory>" >&2
  exit 1
fi
version=$1
tap=$2
script_dir=$(cd "$(dirname "$0")" && pwd)

# Not piped, so a missing zip stops the script instead of writing an empty sha256.
checksum=$(shasum -a 256 "dist/Sill-$version.zip")
sha256=${checksum%% *}
mkdir -p "$tap/Casks"
"$script_dir/sill-cask.sh" "$version" "$sha256" > "$tap/Casks/sill.rb"

cd "$tap"
git add Casks/sill.rb
if git diff --cached --quiet; then
  echo "Casks/sill.rb already describes $version" >&2
  exit 1
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "sill $version"
git push
