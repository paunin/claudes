#!/bin/zsh
# Build a small launcher app for the PERSONAL profile.
#
#   usage: personal-launcher.sh [label]      (default: ME)
#
# Why this exists: a signed-mode instance registers itself with LaunchServices
# as /Applications/Claude.app, so opening the real Claude.app by its own icon
# collides with it and ends both processes. Launching through a bundle of its
# own does not collide - two such launchers run side by side happily.
#
# This is a launcher, not a clone: a few KB, no copy of the app, no re-signing
# of anything large. It runs the original signed binary with the stock profile,
# so it opens the same personal account, history and logins as Claude.app does -
# ~/.claude and ~/Library/Application Support/Claude, untouched.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances --optional
preflight

LABEL="${1:-ME}"
[[ "$LABEL" =~ '^[A-Za-z0-9]{1,4}$' ]] || die "label must be 1-4 letters or digits, got '$LABEL'"
DST="${CLAUDE_APPS_DIR:-/Applications}/Claude $LABEL.app"
ID="com.anthropic.claude.personal"

print "==> building '\''$(basename "$DST")'\'' -> $MAIN_APP with the stock profile"
make_launcher "$DST" "$ID" "$LABEL" "${CLAUDE_APPS_PERSONAL_HUE:-100}" "" ""
killall Dock 2>/dev/null || true
print "done -> $DST"
print
print "Use this instead of Claude.app when a signed-mode instance is running."
print "Drag it into the Dock and remove the original from the Dock to avoid mixing them up."
