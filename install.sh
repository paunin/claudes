#!/bin/zsh
# One command to go from a fresh checkout to every instance built.
#
#   usage: install.sh [--check] [--force]
#
#     --check   report what would happen, change nothing
#     --force   rebuild instances whose app already exists
#
# Three steps: make sure instances.conf exists, generate the ~/.local/bin
# commands, then build any app that is missing. Safe to re-run - an instance
# that is already built is left alone unless you pass --force.
set -euo pipefail
HERE="${0:A:h}"; source "$HERE/lib.sh"

CHECK=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    *) die "unknown option '$arg'   (usage: ${0:t} [--check] [--force])" ;;
  esac
done

# --- 1. the config ----------------------------------------------------------
# Never build from the example: its rows are fictional placeholders, and
# building them would create apps nobody asked for.
if [[ ! -f "$CONF" ]]; then
  [[ -f "$CONF.example" ]] || die "no $CONF and no example to copy"
  if (( CHECK )); then
    print "instances.conf: missing - would be created from the example"
    exit 0
  fi
  cp "$CONF.example" "$CONF"
  print "==> created $CONF from the example"
  print
  print "It defines placeholder instances. Edit it - one row per organisation -"
  print "then run this again to build them:"
  print
  print "    \$EDITOR ${CONF}"
  print "    ${0:t}"
  exit 0
fi

load_instances
preflight

# --- 2. the commands --------------------------------------------------------
if (( CHECK )); then
  print "=== 1. commands ==="
  print "    would regenerate ${CLAUDE_APPS_BIN:-$HOME/.local/bin}/claude-* from ${CONF:t}"
else
  print "=== 1. commands ==="
  "$HERE/sync-commands.sh"
fi

# --- 3. the apps ------------------------------------------------------------
print
print "=== 2. apps ==="
built=0; skipped=0
for slug in "${INSTANCE_SLUGS[@]}"; do
  APP="$(app_path "$slug")"
  LABEL="${INSTANCE_LABEL[$slug]}"
  if [[ -d "$APP" ]] && (( ! FORCE )); then
    print "    Claude $LABEL: already built - skipping (--force to rebuild)"
    skipped=$((skipped+1))
    continue
  fi
  if (( CHECK )); then
    [[ -d "$APP" ]] && print "    Claude $LABEL: would rebuild (--force)" \
                    || print "    Claude $LABEL: would build"
    built=$((built+1))
    continue
  fi
  print "    Claude $LABEL: building"
  "$HERE/rebuild-claude-org.sh" "$slug"
  built=$((built+1))
done

print
if (( CHECK )); then
  print "=== check only - nothing was changed ==="
else
  print "=== 3. result ==="
  "$HERE/list-instances.sh"
  print "built: $built   already present: $skipped"
  print
  print "Next: 'claude-<slug>' for the CLI, 'claude-<slug>-app' for the desktop app."
  print "Keep them current with 'claude-update-all' after Claude.app updates itself."
fi
