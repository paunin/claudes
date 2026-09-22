<p align="center">
  <img src="docs/banner.png" alt="Claudes — several Claude accounts on one Mac, a separate desktop app and CLI profile for each" width="100%">
</p>

# Claudes

Run several Claude accounts side by side on one Mac — a separate desktop app and
CLI profile per organisation, all usable at the same time.

Instances are defined **only** in `instances.conf`. No script here names a
specific organisation, and nothing depends on where this directory lives, so it
can be moved, copied to another machine, or committed to git.

`instances.conf` is gitignored — slugs and organisation names are private to a
machine. On a fresh clone, start from the tracked example:

```bash
cp instances.conf.example instances.conf   # then edit
claude-sync
```

The scripts point you at this if the file is missing.

The default `/Applications/Claude.app` and `~/.claude` are the personal profile.
This tooling never modifies them.

## Requirements

macOS, the Claude desktop app, and the Xcode command line tools
(`xcode-select --install`) for `swift`. Nothing else — icon rendering uses
CoreImage and AppKit, so there is no ImageMagick or other third-party
dependency. The scripts check this up front and fail with a clear message.

Paths can be overridden if your setup differs:

| Variable | Default |
|---|---|
| `CLAUDE_APPS_MAIN_APP` | `/Applications/Claude.app` |
| `CLAUDE_APPS_DIR` | `/Applications` (where clones are created) |
| `CLAUDE_APPS_BIN` | `~/.local/bin` (where commands are installed) |

`claude-sync` warns if the command directory is not on your `PATH`.

## How isolation works

Each instance gets two separate things, both set by a wrapper installed at
`Contents/MacOS/Claude` inside its app bundle:

- `CLAUDE_CONFIG_DIR=~/.claude-<slug>` — credentials, settings, skills, plugins
  and session history for the Code side.
- `--user-data-dir=~/Library/Application Support/Claude-<label>` — the Electron
  app's own login, cookies and window state.

Because the wrapper lives inside the bundle, the desktop apps need no shell
configuration at all. The `~/.local/bin` commands exist only for terminal use.

## Commands

Generated into `~/.local/bin` by `claude-sync`.

| Command | Does |
|---|---|
| `claude-instances` | list every instance and its current state |
| `claude-<slug>` | run the CLI under that instance's config dir |
| `claude-<slug>-app` | open that instance's desktop app |
| `claude-update-all` | update the CLI, rebuild stale apps (`--check`, `--force`) |
| `claude-rebuild <slug> [hue]` | rebuild one app from the current `Claude.app` |
| `claude-icon <slug> [hue]` | re-skin an app without a full rebuild |
| `claude-remove <slug>` | remove an instance: app, commands, config row (`--purge`) |
| `claude-sync` | regenerate the commands after editing `instances.conf` |

## Adding or changing an instance

Edit `instances.conf`, then:

```bash
claude-sync              # refresh ~/.local/bin commands
claude-rebuild <slug>    # build the app, for a new instance
```

## Removing an instance

```bash
claude-remove <slug>            # app + commands + instances.conf row; profile kept
claude-remove <slug> --purge    # also delete the profile — not recoverable
```

It prints exactly what it will delete, with sizes, and asks you to type the slug
back before touching anything (`--yes` skips the prompt for scripts). There is no
need to edit `instances.conf` first — it removes the row for you.

Without `--purge` the two profile directories survive, so re-adding the row and
running `claude-rebuild <slug>` picks up the same logins and history. `--purge`
deletes `~/.claude-<slug>` and the Electron user-data dir: chat history, settings
and login state, gone for good.

`--purge` works as a later, separate step too. Each build leaves a
`.claude-apps-instance` stamp in the config dir recording the slug's label, which
is how a purge still finds `Claude-<label>` in *Application Support* after the app
and the config row are already gone.

An **orphan** — an app on disk that `instances.conf` no longer mentions, typically
left by editing the file by hand — is removed the same way: `claude-remove` reads
the bundle identifier rather than the config, so the slug is enough.
`claude-update-all` reports orphans it finds.

Removal is safe to repeat: a second run finds nothing to do and exits 0. The
command only ever deletes `~/.local/bin` files carrying this tooling's
generated-by marker, so hand-written scripts there are left alone, and every
deletion goes through a guard that refuses `/`, `$HOME`, `/Applications/Claude.app`
and `~/.claude`.

## Files

| File | Purpose |
|---|---|
| `instances.conf` | the only place instances are defined (**gitignored**) |
| `instances.conf.example` | tracked template to copy from |
| `lib.sh` | config parsing and shared helpers |
| `rebuild-claude-org.sh` | clone, rebrand, re-sign and re-skin one app |
| `set-claude-icon.sh` | icon only; much faster than a full rebuild |
| `render-icon.swift` | tints and badges an `.iconset` (CoreImage + AppKit) |
| `update-all.sh` | the three update tracks, in order |
| `list-instances.sh` | status table |
| `sync-commands.sh` | generate `~/.local/bin` commands |
| `remove-instance.sh` | remove one instance (or an orphan), optionally its data |
| `render-banner.swift` | regenerates `docs/banner.png` (`swift render-banner.swift docs/banner.png`) |

## Idempotency

Every command is safe to run repeatedly; none of them needs a clean starting
state.

- `claude-rebuild` deletes the old clone and re-clones from the pristine
  `Claude.app` every time, so a rebuild is a fresh build, never a patch on top of
  a patch. The profile directories are created if missing and never overwritten.
- `claude-icon` and the icon step of a rebuild always render from the untouched
  `Claude.app` icon, so re-running never compounds a tint or a badge.
- `claude-sync` regenerates all of its commands from `instances.conf` and prunes
  the ones it previously generated for instances that are gone. Two consecutive
  runs leave `~/.local/bin` byte-identical.
- `claude-update-all` rebuilds only apps whose version has drifted from
  `Claude.app`; when everything matches it changes nothing. `--check` is a pure
  dry run, `--force` rebuilds regardless.
- `claude-remove` exits 0 with "nothing - already removed" when run again.

## Updating

`Claude.app` auto-updates itself; clones cannot, because they are ad-hoc signed
copies. Let the original update first, then:

```bash
claude-update-all
```

It compares each app's `CFBundleShortVersionString` against the original's and
rebuilds only what has drifted.

Three things update on independent schedules:

1. **Terminal CLI** — one install shared by every profile. Only the config dir
   differs between `claude` and `claude-<slug>`; the binary is the same, so it is
   updated once. If Homebrew owns it, `claude-update-all` upgrades it; otherwise
   it tells you the command for your install method rather than guessing.
2. **Desktop app bundles** — the original auto-updates, clones are rebuilt.
3. **claude-code inside each desktop app** — lives in that app's user-data-dir and
   self-updates. A rebuild replaces only the `.app` bundle, so these survive it.
   They often run *ahead* of the CLI install.

## Gotchas this tooling works around

Each of these cost real debugging time. Do not remove the workarounds.

- **`CFBundleIconName`.** macOS prefers the icon named by this key inside
  `Assets.car` over `CFBundleIconFile`, silently ignoring a replaced
  `electron.icns`. The scripts delete the key to force the fallback. Verify what
  the system actually resolves with `NSWorkspace.icon(forFile:)` — the file on
  disk can be correct while the Dock still shows the old icon.
- **Electron helper apps.** Electron resolves its helper processes at
  `Frameworks/<CFBundleName> Helper.app`. Renaming the bundle without renaming
  the helpers makes the app die at launch with
  `FATAL: Unable to find helper app`.
- **Inside-out signing.** Sign frameworks and helpers first, the outer bundle
  last, and never use `codesign --deep`. Restricted entitlements
  (`keychain-access-groups`, `application-identifier`) cannot be carried by an
  ad-hoc signature and are dropped; they only affect WebAuthn and Microsoft SSO.
- **`ditto`, not `cp -R`**, for copying a bundle — it preserves bundle metadata.
- **Icon rendering is Swift, not ImageMagick.** Some ImageMagick builds ship
  without FreeType and silently cannot draw text at all, so tint and badge are
  both done with CoreImage/AppKit. That also keeps the repo dependency-free.
- **zsh `set -e` and `(( n++ ))`.** Post-increment evaluates to the *old* value,
  so the first iteration returns 0 and aborts the script. Use `n=$((n+1))`.
- **zsh `[[ x == [a-z]## ]]`** silently never matches unless `EXTENDED_GLOB` is
  set. `lib.sh` uses `=~` regex instead.
- **zsh `print` eats leading dashes.** `print "--purge ..."` parses `-p` as an
  option and fails with `no coprocess`, which under `set -e` kills the script.
  Any `print` whose text starts with a variable or a `-` uses `print -r --`.
- **Never `local path=...` in zsh.** `$path` is tied to `$PATH`, so a scalar
  assignment wipes the command search path for the rest of the function and every
  later command fails with `command not found`. `safe_rm` uses `target`.
- **Unmatched globs abort a zsh script.** `for f in dir/*` is fatal when nothing
  matches — the fresh-machine case. The loops here use the `(N)` qualifier.
- **PlistBuddy talks on stdout.** A missing file or key produces
  `File Doesn't Exist, Will Create...` on *stdout*, which silently becomes your
  captured value. `bundle_version` checks the file first and discards the output.

## Do not run Claude from `$HOME`

Claude Code reads `<cwd>/.claude/settings.json` as *project* settings. In your
home directory that resolves to `~/.claude/settings.json` — the personal
profile's own config — so any instance launched from `~` picks up personal's
permissions as project settings. `cd` into a real project first.

## Verifying

The commands must not depend on shell configuration. `zsh -f` skips every rc
file, so this proves it:

```bash
zsh -f -c 'claude-instances'
```
