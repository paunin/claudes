#!/bin/zsh
# Update every Claude install on this machine.
#   update-all.sh           update CLI, then rebuild any stale instance
#   update-all.sh --check   report only, change nothing
#   update-all.sh --force   rebuild every instance even if versions match
#
# Three independent tracks:
#   1. terminal CLI  - one install, shared by every profile (config dirs differ,
#                      the binary does not).
#   2. desktop apps  - the main app auto-updates itself; clones cannot, so they
#                      are rebuilt from it whenever their version has drifted.
#   3. claude-code inside each desktop app - lives per user-data-dir and
#                      self-updates. A rebuild replaces only the .app bundle.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"
load_instances
preflight

MODE="${1:-}"
CHECK=0; FORCE=0
[[ "$MODE" == "--check" ]] && CHECK=1
[[ "$MODE" == "--force" ]] && FORCE=1

print "=== 1. terminal CLI (shared by every profile) ==="
if ! command -v claude >/dev/null 2>&1; then
  print "    not installed / not on PATH - skipping"
else
  print "    installed: $(claude --version 2>/dev/null)"
  # Do not assume a package manager: only drive the one that actually owns it.
  if command -v brew >/dev/null 2>&1 && brew list --cask claude-code >/dev/null 2>&1; then
    if (( CHECK )); then
      out="$(brew outdated --cask claude-code 2>/dev/null || true)"
      [[ -n "$out" ]] && print "    homebrew: update available - $out" || print "    homebrew: up to date"
    else
      brew upgrade --cask claude-code || print "    (nothing to upgrade)"
      print "    now: $(claude --version 2>/dev/null)"
    fi
  else
    print "    not managed by homebrew - update it the way you installed it, e.g."
    print "      claude install stable      # native build"
    print "      npm update -g @anthropic-ai/claude-code"
  fi
fi

print
print "=== 2. desktop apps ==="
MAIN="$(bundle_version "$MAIN_APP")"
print "    ${MAIN_APP:t} (auto-updating): $MAIN"

for slug in "${INSTANCE_SLUGS[@]}"; do
  APP="$(app_path "$slug")"
  LABEL="${INSTANCE_LABEL[$slug]}"
  if [[ ! -d "$APP" ]]; then
    if (( CHECK )); then
      print "    Claude $LABEL: MISSING - run: claude-rebuild $slug"
    else
      print "    Claude $LABEL: missing - building"
      "$HERE/rebuild-claude-org.sh" "$slug"
    fi
    continue
  fi
  V="$(bundle_version "$APP")"
  if [[ "$V" == "$MAIN" ]] && (( ! FORCE )); then
    print "    Claude $LABEL: $V  - current"
  elif (( CHECK )); then
    print "    Claude $LABEL: $V  - STALE, needs rebuild -> $MAIN"
  else
    print "    Claude $LABEL: $V  - rebuilding to $MAIN"
    "$HERE/rebuild-claude-org.sh" "$slug"
  fi
done

# Clones on disk that instances.conf no longer mentions.
for APP in "${CLAUDE_APPS_DIR:-/Applications}"/Claude\ *.app(N); do
  [[ -f "$APP/Contents/MacOS/Claude.real" ]] || continue
  L="${${APP:t:r}#Claude }"
  known=0
  for slug in "${INSTANCE_SLUGS[@]}"; do [[ "${INSTANCE_LABEL[$slug]}" == "$L" ]] && known=1; done
  (( known )) || {
    print "    Claude $L: on disk but NOT in instances.conf - orphan"
    print "      remove it with: claude-remove <slug>   (slug from its bundle id)"
  }
done

print
print "=== 3. claude-code inside each desktop app (self-updating, no action) ==="
for D in "$HOME/Library/Application Support/"Claude*(N); do
  [[ -d "$D/claude-code" ]] || continue
  print "    ${D:t}: $(ls "$D/claude-code" | tr '\n' ' ')"
done
