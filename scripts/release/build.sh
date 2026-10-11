#!/bin/sh
# Usage: build.sh <version>
# Builds a signed Release of Sill with the given version and zips it as dist/Sill-<version>.zip. SIGNING_IDENTITY is
# the code signing identity (a name or SHA-1) in the keychain search list. The build job of the release workflow runs
# this.
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi
version=$1
: "${SIGNING_IDENTITY:?SIGNING_IDENTITY is required}"

# The same signing settings as make install-sill-dev in eai04191/dotfiles, so the hardened runtime is on and the build
# has no get-task-allow.
xcodebuild -project Sill.xcodeproj -scheme Sill -configuration Release \
  -derivedDataPath build \
  MARKETING_VERSION="$version" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build -quiet

app=build/Build/Products/Release/Sill.app
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dvv "$app" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)='
if ! codesign -dv "$app" 2>&1 | grep -q 'flags=.*runtime'; then
  echo "The hardened runtime is off" >&2
  exit 1
fi
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q get-task-allow; then
  echo "The build has get-task-allow" >&2
  exit 1
fi
# macOS keeps permissions such as calendar access while this stays the same.
codesign -d -r- "$app" 2>&1 | grep '^designated'
built_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [ "$built_version" != "$version" ]; then
  echo "The build has version $built_version, not $version" >&2
  exit 1
fi

mkdir -p dist
rm -f "dist/Sill-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Sill-$version.zip"
