#!/bin/zsh
# Re-skin an instance's Claude clone: hue-tinted icon + label badge.
#   usage: set-claude-icon.sh <slug> [hue]
# Idempotent - always renders from the pristine /Applications/Claude.app icon,
# so re-running never double-tints or double-badges.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances
preflight

[[ $# -ge 1 ]] || die "usage: ${0:t} <slug> [hue]   (slugs: ${INSTANCE_SLUGS[*]})"
ORG="$(require_instance "$1")"
LABEL="${INSTANCE_LABEL[$ORG]}"
HUE="${2:-${INSTANCE_HUE[$ORG]}}"
DST="$(app_path "$ORG")"
[[ -d "$DST" ]] || die "missing $DST - run rebuild-claude-org.sh $ORG first"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
make_icns "$ORG" "$TMP/org.icns" "$HUE"
cp "$TMP/org.icns" "$DST/Contents/Resources/electron.icns"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$DST/Contents/Info.plist" 2>/dev/null || true
touch "$DST"

codesign --force --sign - "$DST"
codesign --verify --deep --strict "$DST"
lsregister -f "$DST"
print "icon set: Claude ${LABEL} (hue=$HUE, badge=${LABEL})"
