#!/bin/zsh
# Shared helpers. Sourced by the other scripts, which set HERE to this directory.
#
#   HERE="${0:A:h}"; source "$HERE/lib.sh"
#
# Nothing here knows about any particular instance - everything comes from
# instances.conf, so the directory can be moved or copied to another machine.

typeset -gA INSTANCE_LABEL INSTANCE_HUE INSTANCE_NOTE
typeset -ga INSTANCE_SLUGS

CONF="$HERE/instances.conf"
MAIN_APP="${CLAUDE_APPS_MAIN_APP:-/Applications/Claude.app}"
# Which binary a newly built instance launches: 'clone' (its own, ad-hoc signed)
# or 'signed' (the original, entitlements intact). Only ever applied when an
# instance has no mode of its own yet - claude-signed stays authoritative after
# that, and the marker it writes lives in the config dir, which a rebuild keeps.
DEFAULT_MODE="${CLAUDE_APPS_DEFAULT_MODE:-clone}"

die() { print -u2 "error: $*"; exit 1; }

# Fail early and clearly rather than halfway through rewriting a bundle.
preflight() {
  [[ -d "$MAIN_APP" ]] || die "no Claude desktop app at $MAIN_APP
    install it from https://claude.ai/download, or set CLAUDE_APPS_MAIN_APP"
  local c
  for c in iconutil codesign ditto; do
    command -v "$c" >/dev/null 2>&1 || die "missing '$c' (ships with macOS)"
  done
  command -v swift >/dev/null 2>&1 || die "missing 'swift' - install the Xcode command line tools:
    xcode-select --install"
}

# load_instances [--optional]
#   --optional tolerates a missing or empty instances.conf. Only the remove
#   command needs it - it must still work while taking out the last row.
load_instances() {
  local optional=0
  [[ "${1:-}" == "--optional" ]] && optional=1
  if [[ ! -f "$CONF" ]]; then
    (( optional )) && { INSTANCE_SLUGS=(); return 0 }
    [[ -f "$CONF.example" ]] && die "no $CONF yet - start from the example:\n    cp ${CONF}.example $CONF"
    die "no instances file at $CONF"
  fi
  INSTANCE_SLUGS=(); INSTANCE_LABEL=(); INSTANCE_HUE=(); INSTANCE_NOTE=()
  local line slug label hue; local -a f; local n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n+1))
    line="${line%%\#*}"                 # strip comments
    [[ -z "${line//[[:space:]]/}" ]] && continue
    f=(${=line})                        # split on whitespace
    (( ${#f} >= 3 )) || die "$CONF:$n: need at least 'slug label hue'"
    slug="${f[1]:l}"; label="${f[2]}"; hue="${f[3]}"
    [[ "$slug" =~ '^[a-z0-9-]+$' ]] || die "$CONF:$n: bad slug '$slug' (use a-z 0-9 -)"
    [[ "$hue"  =~ '^[0-9]+$' ]]     || die "$CONF:$n: hue must be a number, got '$hue'"
    [[ -n "${INSTANCE_LABEL[$slug]:-}" ]] && die "$CONF:$n: duplicate slug '$slug'"
    INSTANCE_SLUGS+=("$slug")
    INSTANCE_LABEL[$slug]="$label"
    INSTANCE_HUE[$slug]="$hue"
    INSTANCE_NOTE[$slug]="${f[4,-1]}"
  done < "$CONF"
  (( ${#INSTANCE_SLUGS} )) || { (( optional )) && return 0; die "$CONF defines no instances" }
}

# Resolve a slug, or fail with the list of valid ones.
require_instance() {
  local want="${1:l}"
  [[ -n "${INSTANCE_LABEL[$want]:-}" ]] && { print -r -- "$want"; return 0; }
  die "unknown instance '$1' - $CONF defines: ${INSTANCE_SLUGS[*]}"
}

# The personal profile is just another row in instances.conf. The one thing that
# makes it different is where its profile lives: the stock locations, so it opens
# the same account, history and logins Claude.app always did. Hence the reserved
# slug - everything else about it goes through the same code as any instance.
PERSONAL_SLUG="personal"
is_personal() { [[ "$1" == "$PERSONAL_SLUG" ]] }

app_path()    { print -r -- "${CLAUDE_APPS_DIR:-/Applications}/Claude ${INSTANCE_LABEL[$1]}.app"; }
bundle_id()   { print -r -- "com.anthropic.claude.$1"; }
config_dir()  {
  if is_personal "$1"; then print -r -- "$HOME/.claude"
  else print -r -- "$HOME/.claude-$1"; fi
}
data_dir()    {
  if is_personal "$1"; then print -r -- "$HOME/Library/Application Support/Claude"
  else print -r -- "$HOME/Library/Application Support/Claude-${INSTANCE_LABEL[$1]}"; fi
}

bundle_version() {
  local plist="$1/Contents/Info.plist" v
  [[ -f "$plist" ]] || { print "unknown"; return 0 }
  # PlistBuddy chats on stdout when it cannot read a key, so drop its output
  # rather than letting it become the version string.
  v="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null)" || v=""
  print -- "${v:-unknown}"
}

# Render a tinted, badged .icns for an arbitrary label into $2.
make_icns_label() {
  local label="$1" out="$2" hue="$3"
  local work; work="$(mktemp -d)"
  iconutil -c iconset "$MAIN_APP/Contents/Resources/electron.icns" -o "$work/icon.iconset"
  swift "$HERE/render-icon.swift" "$work/icon.iconset" "$label" "$hue"
  iconutil -c icns "$work/icon.iconset" -o "$out"
  rm -rf "$work"
}

# Build a launcher .app: a few KB that runs the ORIGINAL signed binary against a
# given profile, instead of an 877 MB clone that must be re-signed and rebuilt
# after every Claude update. Used for signed-mode instances and for the personal
# profile. Pass empty cfg/data to get the stock profile.
# $7 is the instance's own URL scheme, e.g. claude-rsg. Every launcher also
# claims plain `claude`, so it can be picked as the system-wide default handler
# the way a clone could - a launcher with no CFBundleURLTypes is not even a
# candidate, and every claude:// link falls back to the personal profile.
make_launcher() {
  local dst="$1" id="$2" label="$3" hue="$4" cfg="${5:-}" data="${6:-}" scheme="${7:-}"
  rm -rf "$dst"
  mkdir -p "$dst/Contents/MacOS" "$dst/Contents/Resources"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string Claude $label" \
    -c "Add :CFBundleDisplayName string Claude $label" \
    -c "Add :CFBundleIdentifier string $id" \
    -c "Add :CFBundleExecutable string launcher" \
    -c "Add :CFBundlePackageType string APPL" \
    -c "Add :CFBundleIconFile string electron" \
    -c "Add :LSMinimumSystemVersion string 11.0" "$dst/Contents/Info.plist" >/dev/null
  local plist="$dst/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" \
    -c "Add :CFBundleURLTypes:0 dict" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLName string Claude" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string claude" "$plist" >/dev/null
  if [[ -n "$scheme" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1 dict" \
      -c "Add :CFBundleURLTypes:1:CFBundleURLName string $id" \
      -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes array" \
      -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string $scheme" "$plist" >/dev/null
  fi
  {
    print "#!/bin/zsh"
    print "# generated by claude-apps - a launcher, not a clone"
    [[ -n "$cfg" ]] && print "export CLAUDE_CONFIG_DIR=\"$cfg\""
    if [[ -n "$data" ]]; then
      print "exec \"$MAIN_APP/Contents/MacOS/Claude\" --user-data-dir=\"$data\" \"\$@\""
    else
      print "exec \"$MAIN_APP/Contents/MacOS/Claude\" \"\$@\""
    fi
  } > "$dst/Contents/MacOS/launcher"
  chmod +x "$dst/Contents/MacOS/launcher"
  local tmp; tmp="$(mktemp -d)"
  make_icns_label "$label" "$tmp/l.icns" "$hue"
  cp "$tmp/l.icns" "$dst/Contents/Resources/electron.icns"
  rm -rf "$tmp"
  codesign --force --sign - "$dst"
  touch "$dst"; lsregister -f "$dst"
}

# True when an app is one of our launchers rather than a full clone.
is_launcher() { [[ -x "$1/Contents/MacOS/launcher" ]] }

# Render a tinted, badged .icns for an instance into $2.
# Always rendered from the pristine Claude.app icon, so it never compounds.
# Uses only macOS built-ins (iconutil + swift) - no third-party tools required.
make_icns() {
  local slug="$1" out="$2" hue="${3:-${INSTANCE_HUE[$1]}}"
  make_icns_label "${INSTANCE_LABEL[$slug]}" "$out" "$hue"
}

lsregister() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister "$@"
}

# --- removal helpers -------------------------------------------------------
# A slug being removed may already be gone from instances.conf, so these work
# from what is on disk rather than from the config.

# Slug -> label has to survive the app being deleted, otherwise a later
# --purge cannot name the Electron data dir. So every build leaves a stamp in
# the config dir, which outlives the bundle.
stamp_path()  { print -- "$(config_dir "$1")/.claude-apps-instance" }
write_stamp() {
  local cfg; cfg="$(config_dir "$1")"
  [[ -d "$cfg" ]] || return 0
  print -r -- "label=$2" > "$(stamp_path "$1")"
}
read_stamp_label() {
  local f; f="$(stamp_path "$1")"
  [[ -f "$f" ]] || return 1
  local v; v="$(sed -n 's/^label=//p' "$f" | head -1)"
  [[ -n "$v" ]] || return 1
  print -- "$v"
}

# Label of an existing clone, read back from its bundle name: "Claude ACME" -> ACME.
label_from_app() { local n="${1:t:r}"; print -- "${n#Claude }"; }

# Find the clone belonging to a slug by its bundle id, wherever it was named.
find_app_by_slug() {
  local slug="$1" app id
  for app in "${CLAUDE_APPS_DIR:-/Applications}"/Claude\ *.app(N); do
    id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$id" == "$(bundle_id "$slug")" ]] && { print -- "$app"; return 0 }
  done
  return 1
}

# Drop a slug's row from instances.conf, keeping comments and the other rows.
conf_remove_slug() {
  local slug="$1" tmp; tmp="$(mktemp)"
  awk -v slug="$slug" '
    { line = $0; sub(/#.*/, "", line) }
    line ~ /^[[:space:]]*$/ { print; next }          # blank or comment-only
    { n = split(line, f, /[[:space:]]+/)
      i = (f[1] == "" ? 2 : 1)
      if (tolower(f[i]) == slug) next                # the row being removed
      print }
  ' "$CONF" > "$tmp" && mv "$tmp" "$CONF"
}

# macOS scatters per-bundle-id state well outside the app and the data dir.
# Deleting a clone without these leaves preference, cache and cookie stores
# behind under a bundle id nothing will ever claim again.
system_state_paths() {
  local id; id="$(bundle_id "$1")"
  print -r -- "$HOME/Library/Preferences/$id.plist"
  print -r -- "$HOME/Library/Caches/$id"
  print -r -- "$HOME/Library/Caches/$id.ShipIt"
  print -r -- "$HOME/Library/HTTPStorages/$id"
  print -r -- "$HOME/Library/WebKit/$id"
  print -r -- "$HOME/Library/Saved Application State/$id.savedState"
}

# rm -rf that refuses the obvious catastrophes: empty, /, $HOME, the personal
# profile. Everything this tooling deletes goes through here.
safe_rm() {
  local target="$1"                    # not 'path': zsh ties $path to $PATH
  [[ -n "$target" ]]                     || die "safe_rm: empty path"
  [[ "$target" != "/" ]]                 || die "safe_rm: refusing /"
  [[ "$target" != "$HOME" ]]             || die "safe_rm: refusing \$HOME"
  [[ "$target" != "$MAIN_APP" ]]         || die "safe_rm: refusing the personal $MAIN_APP"
  [[ "$target" != "$HOME/.claude" ]]     || die "safe_rm: refusing the personal ~/.claude"
  [[ "$target" != "$HOME/Library/Application Support/Claude" ]] \
    || die "safe_rm: refusing the personal Electron profile"
  [[ "$target" == "$HOME"/* || "$target" == "${CLAUDE_APPS_DIR:-/Applications}"/* ]] \
    || die "safe_rm: refusing '$target' (outside \$HOME and the apps directory)"
  rm -rf -- "$target"
}
