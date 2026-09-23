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
machine. On a fresh clone, one command does the whole setup:

```bash
./install.sh
```

The first run copies `instances.conf.example` to `instances.conf` and stops, so
you can put your own organisations in it. Run it again and it generates the
`~/.local/bin` commands and builds every app the config defines. It never builds
from the example — those rows are placeholders.

After that first run the command is on your PATH as `claude-install`, and
re-running it is safe: apps that already exist are skipped unless you pass
`--force`. `--check` reports what it would do and changes nothing.

The default `/Applications/Claude.app` and `~/.claude` are the personal profile.
This tooling never modifies them.

Each instance runs in one of two modes — a ~1 MB **launcher** over the original
signed app, or a full ~877 MB **clone**. The launcher keeps Anthropic's
entitlements, so features like linking a remote session to this computer keep
working; the clone gets you a tinted icon in the Dock while it runs. See
[Two ways to run an instance](#two-ways-to-run-an-instance).

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
| `CLAUDE_APPS_DEFAULT_MODE` | `clone` — set to `signed` to build new instances in signed mode |

`claude-sync` warns if the command directory is not on your `PATH`.

## How isolation works

Each instance gets two separate things, both set by the launcher installed at
`Contents/MacOS/` inside its app bundle:

- `CLAUDE_CONFIG_DIR=~/.claude-<slug>` — credentials, settings, skills, plugins
  and session history for the Code side.
- `--user-data-dir=~/Library/Application Support/Claude-<label>` — the Electron
  app's own login, cookies and window state.

Because the launcher lives inside the bundle, the desktop apps need no shell
configuration at all. The `~/.local/bin` commands exist only for terminal use.

## Two ways to run an instance

The profile is the same either way. What differs is **which binary** the icon
starts, and that turns out to decide which features work.

| | **launcher** (signed) | **clone** |
|---|---|---|
| Runs | the original `/Applications/Claude.app` binary | its own copy, re-signed ad hoc |
| Size on disk | ~1 MB | ~877 MB |
| Entitlements | intact | **none** |
| Remote session ↔ computer linking | works | fails |
| Microsoft SSO, WebAuthn | work | fail |
| Goes stale when Claude updates | never | needs `claude-rebuild` |
| Icon while running | plain "Claude" | tinted and badged |
| Personal `Claude.app` can be open too | only via `claude-personal` | yes |

```bash
claude-signed                  # show every instance's mode
claude-signed xpt on           # switch to the signed binary
claude-rebuild xpt             # rebuild as a ~1 MB launcher
claude-signed xpt off && claude-rebuild xpt    # back to a clone
```

Mode is a marker file in the instance's config dir, which rebuilds preserve, so
an instance keeps its mode across updates. `CLAUDE_APPS_DEFAULT_MODE=signed`
makes new instances launchers; it only applies to an instance that has no mode
yet, so a rebuild never silently changes which binary you launch.

**Why a clone cannot do those things.** An ad-hoc signature carries no
entitlements at all. The original is signed by Anthropic with
`keychain-access-groups`, `application-identifier` and a team identifier only
they can claim, and Apple's provisioning is what makes those valid — so
re-signing here cannot reproduce them, and no macOS setting grants them. It is a
property of the binary's signature, not a permission you approve. A clone that
tries logs `remote_cowork.device_register_miss {"reason":"unavailable_entitlement"}`
and the session reports *"Couldn't link this session to a computer, so attached
folders can't be used."* Sessions started locally in the app are unaffected.

**What launcher mode costs.** Launching still uses the tinted icon, but the
running process belongs to `Claude.app`: LaunchServices registers it as plain
"Claude", so the Dock and app switcher show the untinted icon and two launcher
instances look alike while running.

Launcher instances **do** run side by side with each other, each on its own
profile. The one collision is the personal `/Applications/Claude.app` itself —
launching it by its own icon while an instance holds that bundle's registration
ends *both* processes. Hence the next section.

## The personal profile

The stock profile — `~/.claude` and `~/Library/Application Support/Claude` — is
never touched by this tooling. But once any instance runs in launcher mode, the
original `Claude.app` icon is the one thing you must stop clicking. Give the
personal profile a launcher of its own instead:

```bash
claude-personal          # builds "Claude ME.app"; claude-personal XYZ to name it
```

About 1 MB, no clone, nothing large to re-sign. It runs the original binary with
**no** profile flags, so it opens the same personal account, history and logins as
`Claude.app` always did. Being its own bundle, it does not collide — verified
running alongside two launcher instances at once.

Put it in the Dock and take the original `Claude.app` out, so nothing is left to
click that collides. Remove it with `rm -rf "/Applications/Claude ME.app"`; it is
not an instance, so `claude-remove` does not manage it and `claude-update-all`
does not count it as an orphan.

## Which Claude opens a link

Isolation stops at the bundle. Every clone inherits the `claude` URL scheme from
the original app, and macOS allows exactly **one** default handler per scheme for
the whole login session — there is no per-browser, per-profile or per-window
routing to configure. So a `claude://` link from the browser, including a sign-in
callback, goes to whichever app is currently the default, no matter which
instance started the flow.

```bash
claude-default           # show the current handler and all the candidates
claude-default <slug>    # send claude:// links to that instance
claude-default personal  # send them back to /Applications/Claude.app
```

Point it at an instance *before* signing into that instance, then put it back if
you like. The switch is immediate and needs no restart.

A rebuild re-registers the bundle with LaunchServices, so check with
`claude-default` afterwards if links start landing in the wrong app.

The same collision applies to `msauth.com.anthropic.claudefordesktop`, the
Microsoft SSO callback scheme. It is moot for a clone, which cannot do Microsoft
SSO at all, but it is real for launcher instances — point `claude-default` at the
instance you are signing into.

## Commands

Generated into `~/.local/bin` by `claude-sync`.

| Command | Does |
|---|---|
| `claude-install` | set up everything the config defines (`--check`, `--force`) |
| `claude-instances` | list every instance and its current state |
| `claude-<slug>` | run the CLI under that instance's config dir |
| `claude-<slug>-app` | open that instance's desktop app |
| `claude-<slug>-signed` | open that profile with the original signed `Claude.app` |
| `claude-update-all` | update the CLI, rebuild stale apps (`--check`, `--force`) |
| `claude-rebuild <slug> [hue]` | rebuild one app: launcher or clone, per its mode |
| `claude-icon <slug> [hue]` | re-skin an app without a full rebuild |
| `claude-default [slug]` | choose which Claude opens `claude://` links |
| `claude-signed [slug on\|off]` | switch an instance between launcher and clone mode |
| `claude-personal [label]` | build a Dock launcher for the personal profile |
| `claude-remove <slug>` | remove an instance: app, commands, config row (`--purge`) |
| `claude-sync` | regenerate the commands after editing `instances.conf` |

## Adding or changing an instance

Edit `instances.conf`, then:

```bash
claude-install           # refresh commands, build whatever is missing
```

Or do the two halves separately, which is what `claude-install` calls:

```bash
claude-sync              # refresh ~/.local/bin commands
claude-rebuild <slug>    # build one app
```

## Removing an instance

```bash
claude-remove <slug>            # app + commands + instances.conf row; profile kept
claude-remove <slug> --purge    # also delete the profile — not recoverable
```

It prints exactly what it will delete, with sizes, and asks you to type the slug
back before touching anything (`--yes` skips the prompt for scripts). There is no
need to edit `instances.conf` first — it removes the row for you.

`--purge` also takes the per-bundle-id state macOS keeps outside both: the
preferences plist, the two `Caches` directories and `HTTPStorages` (cookies).
Deleting only the app leaves those behind under a bundle id nothing will ever
claim again. `defaults delete` runs first, because `cfprefsd` caches preferences
in memory and would otherwise rewrite the plist after it is deleted.

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
| `install.sh` | first-run setup: config, commands, then every missing app |
| `lib.sh` | config parsing and shared helpers |
| `rebuild-claude-org.sh` | build one instance: a launcher, or a re-skinned clone |
| `set-claude-icon.sh` | icon only; much faster than a full rebuild |
| `set-default-handler.sh` | pick the app that opens `claude://` links |
| `set-binary-mode.sh` | launcher vs. clone mode, per instance |
| `personal-launcher.sh` | ~1 MB launcher app for the stock personal profile |
| `url-handler.swift` | reads and sets a scheme's default app via LaunchServices |
| `render-icon.swift` | tints and badges an `.iconset` (CoreImage + AppKit) |
| `update-all.sh` | the three update tracks, in order |
| `list-instances.sh` | status table |
| `sync-commands.sh` | generate `~/.local/bin` commands |
| `remove-instance.sh` | remove one instance (or an orphan), optionally its data |
| `render-banner.swift` | regenerates `docs/banner.png` (`swift render-banner.swift docs/banner.png`) |
| `LICENSE` | MIT |

## Idempotency

Every command is safe to run repeatedly; none of them needs a clean starting
state.

- `claude-rebuild` deletes the old app and builds again from scratch every time —
  re-cloning from the pristine `Claude.app` in clone mode, or writing a fresh
  launcher in launcher mode — so a rebuild is never a patch on top of a patch. The
  profile directories are created if missing and never overwritten, which is why
  an instance keeps its login, history and mode across rebuilds.
- `claude-icon` and the icon step of a rebuild always render from the untouched
  `Claude.app` icon, so re-running never compounds a tint or a badge.
- `claude-sync` regenerates all of its commands from `instances.conf` and prunes
  the ones it previously generated for instances that are gone. Two consecutive
  runs leave `~/.local/bin` byte-identical.
- `claude-update-all` rebuilds only apps whose version has drifted from
  `Claude.app`, and skips signed-mode launchers entirely, since they have no copy
  of the app to go stale; when everything matches it changes nothing. `--check` is a pure
  dry run, `--force` rebuilds regardless.
- `claude-remove` exits 0 with "nothing - already removed" when run again.
- `claude-install` skips apps that already exist, so re-running it after adding a
  row to `instances.conf` builds only the new one. It never overwrites an
  existing `instances.conf`.

## Updating

`Claude.app` auto-updates itself. Launcher instances inherit that for free —
they run the original binary, so they are current the moment it is. Clones cannot,
being ad-hoc signed copies, so they are rebuilt when their version drifts.

```bash
claude-update-all
```

It compares each clone's `CFBundleShortVersionString` against the original's and
rebuilds only what has drifted, reporting launchers as *nothing to rebuild*. If
every instance is a launcher, this only has the CLI left to do.

Three things update on independent schedules:

1. **Terminal CLI** — one install shared by every profile. Only the config dir
   differs between `claude` and `claude-<slug>`; the binary is the same, so it is
   updated once. If Homebrew owns it, `claude-update-all` upgrades it; otherwise
   it tells you the command for your install method rather than guessing.
2. **Desktop app bundles** — the original auto-updates, launchers follow it
   automatically, clones are rebuilt.
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
- **A launcher-mode process does not carry its own bundle path.** It runs as
  `/Applications/Claude.app/Contents/MacOS/Claude`, so `pkill -f "<the instance
  bundle>"` never matches it — a rebuild left the old process alive and the next
  launch put two processes on one profile. Match `--user-data-dir=` instead.
- **PlistBuddy talks on stdout.** A missing file or key produces
  `File Doesn't Exist, Will Create...` on *stdout*, which silently becomes your
  captured value. `bundle_version` checks the file first and discards the output.

## What is not isolated

The launcher isolates the config dir and the Electron user-data dir. Two things
it does not reach:

- **`~/Library/Logs/Claude`** is shared by every instance. Electron derives the
  log path from the application name it was built with, not from the bundle or
  the user-data dir, so all instances interleave into one `main.log`. Useful to
  know when reading logs; harmless otherwise.
- **The `claude://` URL scheme**, which has one system-wide handler — see
  [Which Claude opens a link](#which-claude-opens-a-link).

Per-bundle-id state (preferences, caches, cookies) *is* separate, because each
instance gets its own `CFBundleIdentifier` in either mode. `claude-remove --purge`
cleans it up.

## Do not run Claude from `$HOME`

Claude Code reads `<cwd>/.claude/settings.json` as *project* settings. In your
home directory that resolves to `~/.claude/settings.json` — the personal
profile's own config — so any instance launched from `~` picks up personal's
permissions as project settings. `cd` into a real project first.

## License

MIT — see [LICENSE](LICENSE).

## Verifying

The commands must not depend on shell configuration. `zsh -f` skips every rc
file, so this proves it:

```bash
zsh -f -c 'claude-instances'
```
