#!/bin/bash
# Runs Main.qml under quickshell outside omarchy-shell, with a throwaway state
# dir, logging devices and join/leave events. Ctrl+C to stop.
# Usage: tests/harness.sh [seconds]   (quickshell refuses relative imports
# outside its config dir, so the shell.qml is generated with a file:// URL.)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state"
cat > "$tmp/shell.qml" <<QML
import QtQuick
import Quickshell
import "file://$repo" as WM

ShellRoot {
  WM.Main {
    id: m
    settings: ({ scanIntervalSec: 15, absenceGraceSec: 60 })
    onPresenceEvents: function(events) { console.log("EVENTS", JSON.stringify(events)) }
    onPresentCountChanged: console.log("PRESENT", m.presentCount, "/", m.devices.length)
    onLastErrorChanged: if (m.lastError) console.log("ERROR", m.lastError)
  }
}
QML
XDG_STATE_HOME="$tmp/state" ${1:+timeout -s INT "$1"} qs -p "$tmp/shell.qml" --no-color 2>&1 |
  grep --line-buffered -E 'qml:|ERROR|WARN quickshell' || true
