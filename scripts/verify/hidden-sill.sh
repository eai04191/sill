#!/bin/bash
# Usage: hidden-sill.sh build | start | pid | capture <directory> | stop
#
# Builds this checkout's Sill and runs it as a hidden instance (Sill/Utils/HiddenInstance.swift): its bar and popups
# are below the desktop picture, so the maintainer's screen, pointer and keyboard focus are left alone, and its windows
# can still be captured one at a time. Each checkout, such as a worktree, has its own instance, so several can run at
# once next to the maintainer's Sill.
#
# build    Builds into build/ and signs it with the certificate of the maintainer's Sill, so the calendar access already
#          granted to it applies and no permission prompt shows. That Sill is the running one outside this checkout, or
#          SILL_INSTALLED_APP when it is set.
# start    Starts the instance with its config in build/hidden-sill/config/sill/config.toml and prints its pid.
# pid      Prints the instance's pid, for SILL_PID with axpress and axscroll.
# capture  Captures each of the instance's windows on screen into <directory>/<window number>.png.
# stop     Quits the instance.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
app="$root/build/Build/Products/Release/Sill.app"
state="$root/build/hidden-sill"
tools="$root/build/verify-tools"

running_pid() {
    pgrep -f "^$app/Contents/MacOS/Sill" || true
}

require_pid() {
    local pid
    pid=$(running_pid)
    if [ -z "$pid" ]; then
        echo "The hidden instance is not running; start it with: $0 start" >&2
        exit 1
    fi
    echo "$pid"
}

# The maintainer's Sill: SILL_INSTALLED_APP, or the app of the running Sill that is not a build of a checkout, such as
# another worktree's hidden instance.
installed_app() {
    if [ -n "${SILL_INSTALLED_APP:-}" ]; then
        echo "$SILL_INSTALLED_APP"
        return
    fi
    local app
    app=$(ps -axo command= | sed -n 's|^\(/.*\.app\)/Contents/MacOS/Sill$|\1|p' | grep -v '/build/Build/Products/' | head -1)
    if [ -z "$app" ]; then
        echo "The maintainer's Sill is not running; set SILL_INSTALLED_APP to its app" >&2
        exit 1
    fi
    echo "$app"
}

# The SHA-1 of the maintainer's Sill's signing certificate, from its designated requirement. Signing with a different
# certificate would make the calendar access a new request.
installed_certificate() {
    local installed
    installed=$(installed_app)
    local requirement
    requirement=$(codesign -dr - "$installed" 2>&1) || {
        echo "Cannot read the signature of $installed; set SILL_INSTALLED_APP to the installed Sill" >&2
        exit 1
    }
    local hash
    hash=$(sed -n 's/.*certificate leaf = H"\([0-9a-f]*\)".*/\1/p' <<<"$requirement")
    if [ -z "$hash" ]; then
        echo "$installed is not signed with a certificate leaf requirement: $requirement" >&2
        exit 1
    fi
    echo "$hash"
}

case "${1:-}" in
build)
    identity=$(installed_certificate)
    xcodebuild -project "$root/Sill.xcodeproj" -scheme Sill -configuration Release -derivedDataPath "$root/build" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
        ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build -quiet
    mkdir -p "$tools"
    for tool in axpress axscroll windows; do
        swiftc -o "$tools/$tool" "$root/scripts/verify/$tool.swift"
    done
    echo "Built $app and the tools in $tools"
    ;;
start)
    if [ -n "$(running_pid)" ]; then
        echo "The hidden instance is already running: pid $(running_pid)" >&2
        exit 1
    fi
    mkdir -p "$state/config"
    # open, rather than running the executable from this shell, so that Sill itself is responsible for its calendar
    # access instead of the app the shell runs in. -g keeps it from coming to the front.
    open -g -n --env SILL_HIDDEN_INSTANCE=1 --env XDG_CONFIG_HOME="$state/config" "$app"
    for _ in $(seq 50); do
        pid=$(running_pid)
        if [ -n "$pid" ]; then
            echo "$pid"
            exit 0
        fi
        sleep 0.1
    done
    echo "The hidden instance did not start" >&2
    exit 1
    ;;
pid)
    require_pid
    ;;
capture)
    directory="${2:?Usage: $0 capture <directory>}"
    pid=$(require_pid)
    mkdir -p "$directory"
    "$tools/windows" "$pid" | while read -r number _ _ _ _ _ onscreen; do
        if [ "$onscreen" = on ]; then
            screencapture -x -o -l "$number" "$directory/$number.png"
            echo "$directory/$number.png"
        fi
    done
    ;;
stop)
    pid=$(require_pid)
    kill "$pid"
    for _ in $(seq 50); do
        [ -z "$(running_pid)" ] && exit 0
        sleep 0.1
    done
    echo "The hidden instance did not quit: pid $pid" >&2
    exit 1
    ;;
*)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
