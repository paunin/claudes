#!/bin/zsh
# Build/rebuild an isolated Claude desktop app, cloned from /Applications/Claude.app.
#
#   usage: rebuild-claude-org.sh <slug> [hue]
#
# Instances come from instances.conf; this script hardcodes none of them.
# Re-run after every Claude desktop update - auto-update only touches the
# original app. The default Claude.app and ~/.claude are never modified.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances
preflight

[[ $# -ge 1 ]] || die "usage: ${0:t} <slug> [hue]   (slugs: ${INSTANCE_SLUGS[*]})"
ORG="$(require_instance "$1")"
LABEL="${INSTANCE_LABEL[$ORG]}"
HUE="${2:-${INSTANCE_HUE[$ORG]}}"

SRC="$MAIN_APP"   # honours CLAUDE_APPS_MAIN_APP; preflight has checked it
DST="$(app_path "$ORG")"
DATA="$(data_dir "$ORG")"
CFG="$(config_dir "$ORG")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

print "==> building 'Claude ${LABEL}'  (config=$CFG  hue=$HUE)"

print "==> quitting + removing old clone"
pkill -f "${DST:t}/Contents/MacOS/Claude.real" 2>/dev/null || true
sleep 2
rm -rf "$DST"

print "==> cloning bundle"
ditto "$SRC" "$DST"
xattr -cr "$DST"

print "==> rebranding"
plist="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Claude ${LABEL}'"        "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Claude ${LABEL}'" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$(bundle_id "$ORG")'" "$plist"
rm -f "$DST/Contents/embedded.provisionprofile"

# macOS prefers the Assets.car icon named by CFBundleIconName over
# CFBundleIconFile, which silently ignores our custom electron.icns.
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$plist" 2>/dev/null || true

# Electron resolves Frameworks/<CFBundleName> Helper.app, so helpers must track
# the rename or the app dies at launch with "Unable to find helper app".
print "==> renaming Electron helpers"
F="$DST/Contents/Frameworks"
for suffix in "" " (GPU)" " (Plugin)" " (Renderer)"; do
  new="$F/Claude ${LABEL} Helper${suffix}.app"
  mv "$F/Claude Helper${suffix}.app" "$new"
  mv "$new/Contents/MacOS/Claude Helper${suffix}" "$new/Contents/MacOS/Claude ${LABEL} Helper${suffix}"
  p="$new/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable 'Claude ${LABEL} Helper${suffix}'" "$p"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName 'Claude ${LABEL} Helper${suffix}'" "$p"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$(bundle_id "$ORG").helper'" "$p"
done

print "==> launcher wrapper (isolates Electron data dir AND claude-code config dir)"
exe="$DST/Contents/MacOS/Claude"
real="$DST/Contents/MacOS/Claude.real"
mv "$exe" "$real"
cat > "$exe" <<EOF
#!/bin/zsh
APP_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
export CLAUDE_CONFIG_DIR="$CFG"
# Normally this clone's own binary. With the marker file present, run the
# original Anthropic-signed binary instead: same profile and same icon to click,
# but entitlements intact, so remote session linking works. An ad-hoc signature
# carries no entitlements, which is why the clone cannot do it.
#   toggle with:  claude-signed $ORG on|off
BIN="\$APP_DIR/Claude.real"
if [[ -f "$CFG/.use-signed-binary" && -x "$MAIN_APP/Contents/MacOS/Claude" ]]; then
  BIN="$MAIN_APP/Contents/MacOS/Claude"
fi
exec "\$BIN" --user-data-dir="$DATA" "\$@"
EOF
chmod +x "$exe"

print "==> tinted + badged icon"
make_icns "$ORG" "$TMP/org.icns" "$HUE"
cp "$TMP/org.icns" "$DST/Contents/Resources/electron.icns"

print "==> re-signing inside-out (ad-hoc; no --deep)"
find "$F" -maxdepth 1 -name "*.framework" -type d -exec codesign --force --sign - {} \;
find "$F" -maxdepth 1 -name "*.app"       -type d -exec codesign --force --sign - {} \;
for f in "$DST/Contents/Helpers/"*; do [[ -e "$f" ]] && codesign --force --sign - "$f"; done
codesign --force --sign - "$real"
codesign --force --sign - "$exe"
codesign --force --sign - "$DST"
codesign --verify --deep --strict "$DST" && print "signature OK"

mkdir -p "$CFG" "$DATA"
write_stamp "$ORG" "$LABEL"   # lets claude-remove find $DATA after the app is gone
touch "$DST"
lsregister -f "$DST"
killall Dock 2>/dev/null || true
print "done -> $DST"
