#!/bin/sh
# Usage: write-cask.sh <version>
# Writes Casks/sill.rb for dist/Sill-<version>.zip. This repository is the Homebrew tap, so the release job commits the
# cask to main after the zip is on GitHub Releases.
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi
version=$1
script_dir=$(cd "$(dirname "$0")" && pwd)

# Not piped, so a missing zip stops the script instead of writing an empty sha256.
checksum=$(shasum -a 256 "dist/Sill-$version.zip")
sha256=${checksum%% *}
mkdir -p Casks
"$script_dir/sill-cask.sh" "$version" "$sha256" > Casks/sill.rb
