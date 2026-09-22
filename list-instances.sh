#!/bin/zsh
# Show every configured instance and its current state.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances

printf "%-6s %-6s %-5s %-9s %-9s %-7s %s\n" SLUG LABEL HUE APP CONFIG CMD NOTE
printf "%-6s %-6s %-5s %-9s %-9s %-7s %s\n" ------ ------ ----- --------- --------- ------- ----
for slug in "${INSTANCE_SLUGS[@]}"; do
  app="$(app_path "$slug")"; cfg="$(config_dir "$slug")"
  a=$([[ -d "$app" ]] && print "ok" || print "MISSING")
  c=$([[ -d "$cfg" ]] && print "ok" || print "MISSING")
  m=$(command -v "claude-$slug" >/dev/null 2>&1 && print "ok" || print "MISSING")
  printf "%-6s %-6s %-5s %-9s %-9s %-7s %s\n" \
    "$slug" "${INSTANCE_LABEL[$slug]}" "${INSTANCE_HUE[$slug]}" "$a" "$c" "$m" "${INSTANCE_NOTE[$slug]}"
done
print
print "config:   $CONF"
print "personal: /Applications/Claude.app + ~/.claude (not managed here)"
