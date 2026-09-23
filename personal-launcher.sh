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
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

print "==> building '$(basename "$DST")' -> $MAIN_APP with the stock profile"
rm -rf "$DST"
mkdir -p "$DST/Contents/MacOS" "$DST/Contents/Resources"

plist="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Claude $LABEL" \
  -c "Add :CFBundleDisplayName string Claude $LABEL" \
  -c "Add :CFBundleIdentifier string $ID" \
  -c "Add :CFBundleExecutable string launcher" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleIconFile string electron" \
  -c "Add :LSMinimumSystemVersion string 11.0" "$plist" >/dev/null

# No --user-data-dir and no CLAUDE_CONFIG_DIR: the stock defaults are the point.
cat > "$DST/Contents/MacOS/launcher" <<INNER
#!/bin/zsh
exec "$MAIN_APP/Contents/MacOS/Claude" "\$@"
INNER
chmod +x "$DST/Contents/MacOS/launcher"

print "==> tinted + badged icon"
INSTANCE_LABEL[personal]="$LABEL"
make_icns personal "$TMP/p.icns" "${CLAUDE_APPS_PERSONAL_HUE:-100}"
cp "$TMP/p.icns" "$DST/Contents/Resources/electron.icns"

codesign --force --sign - "$DST"
touch "$DST"; lsregister -f "$DST"
killall Dock 2>/dev/null || true
print "done -> $DST"
print
print "Use this instead of Claude.app when a signed-mode instance is running."
print "Drag it into the Dock and remove the original from the Dock to avoid mixing them up."
