#!/bin/zsh
# Choose which Claude gets links the browser opens (`claude://...`).
#
#   set-default-handler.sh                 show the current handler
#   set-default-handler.sh <slug>          send claude:// links to that instance
#   set-default-handler.sh personal        send them back to /Applications/Claude.app
#
# Every clone inherits the `claude` URL scheme from the original bundle, and
# macOS allows exactly one default handler per scheme - there is no per-browser
# or per-profile routing. So sign-in callbacks land in whichever app is the
# current default, regardless of which one started the sign-in. Point this at an
# instance before logging into it.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances

SCHEME="claude"
current() { swift "$HERE/url-handler.swift" show "$SCHEME"; }

if [[ $# -eq 0 ]]; then
  print "claude:// currently opens:"
  print "    $(current)"
  print
  print "candidates:"
  swift "$HERE/url-handler.swift" list "$SCHEME" | sed 's/^/    /'
  print
  print "switch with: ${0:t} <slug>   (slugs: ${INSTANCE_SLUGS[*]}, or 'personal')"
  exit 0
fi

if [[ "${1:l}" == "personal" ]]; then
  TARGET="$MAIN_APP"; NAME="personal"
else
  ORG="$(require_instance "$1")"
  TARGET="$(app_path "$ORG")"
  NAME="Claude ${INSTANCE_LABEL[$ORG]}"
  [[ -d "$TARGET" ]] || die "missing $TARGET - run: claude-rebuild $ORG"
fi

print "==> claude:// -> $NAME"
now="$(swift "$HERE/url-handler.swift" set "$SCHEME" "$TARGET")"
print "    now: $now"
if [[ "$now" != "$TARGET" ]]; then
  die "LaunchServices kept $now - macOS may have refused the change"
fi
