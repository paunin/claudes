#!/bin/zsh
# Choose which binary an instance's icon launches.
#
#   set-binary-mode.sh                 show every instance's mode
#   set-binary-mode.sh <slug> on       launch the original Anthropic-signed binary
#   set-binary-mode.sh <slug> off      launch this clone's own binary (default)
#
# An ad-hoc signature carries no entitlements, so a clone cannot register the
# computer for remote session linking - the app reports that attached folders
# cannot be used. In 'on' mode the same tinted icon starts the original signed
# binary against this instance's profile, which can. The cost is that a running
# instance shows up as plain "Claude" with the untinted icon, because the
# process belongs to /Applications/Claude.app.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances

MARK=".use-signed-binary"
mode_of()    { [[ -f "$(config_dir "$1")/$MARK" ]] && print "signed" || print "clone"; }
supported()  { grep -q "$MARK" "$(app_path "$1")/Contents/MacOS/Claude" 2>/dev/null; }

if [[ $# -eq 0 ]]; then
  printf "%-6s %-8s %s\n" SLUG MODE "LAUNCHES"
  printf "%-6s %-8s %s\n" ------ -------- --------
  for slug in "${INSTANCE_SLUGS[@]}"; do
    m="$(mode_of "$slug")"
    if [[ "$m" == "signed" ]]; then t="$MAIN_APP/Contents/MacOS/Claude"; else t="$(app_path "$slug") (own binary)"; fi
    printf "%-6s %-8s %s\n" "$slug" "$m" "$t"
    supported "$slug" || print "       ^ app predates this switch - run: claude-rebuild $slug"
  done
  print
  print "usage: ${0:t} <slug> on|off"
  exit 0
fi

[[ $# -ge 2 ]] || die "usage: ${0:t} <slug> on|off   (slugs: ${INSTANCE_SLUGS[*]})"
ORG="$(require_instance "$1")"
CFG="$(config_dir "$ORG")"
mkdir -p "$CFG"

case "${2:l}" in
  on)  : > "$CFG/$MARK"; print "==> $ORG: signed mode - the icon now starts $MAIN_APP" ;;
  off) rm -f "$CFG/$MARK"; print "==> $ORG: clone mode - the icon starts $(app_path "$ORG")" ;;
  *)   die "expected 'on' or 'off', got '$2'" ;;
esac

if ! supported "$ORG"; then
  print
  print "WARNING: 'Claude ${INSTANCE_LABEL[$ORG]}' was built before this switch existed,"
  print "so its launcher ignores the setting. Rebuild it to pick this up:"
  print "    claude-rebuild $ORG"
elif pgrep -f "$(app_path "$ORG"):t/Contents/MacOS" >/dev/null 2>&1; then
  print "    (running - quit and reopen it for this to take effect)"
fi
