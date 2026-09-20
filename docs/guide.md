# User guide

[Back to README](../README.md) · [Install](#install-and-update) ·
[Configuration](#configuration) · [Wired mode](#wired-mode) ·
[Troubleshooting](#troubleshooting) · [Uninstall](#uninstall)

## Install and update

Sidecar must already work between your Mac and iPad. Keep the iPad unlocked during setup.
The [README](../README.md#install) has the release and Homebrew commands; use only one
method to avoid competing watchers.

- **Release installer:** run the same command again to update. It installs into
  `~/.sidecarkeeper`, creates a per-user LaunchAgent and links `sidecar-keeper` into a
  writable directory on your `PATH` when available.
- **Homebrew:** run `brew upgrade sidecarkeeper`, then
  `brew services restart sidecarkeeper` to use the new binary.
- **Manual download:** download `SidecarKeeper.tar.gz` and its `.sha256` file from the
  [latest release](https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest). In the
  download directory, run `shasum -a 256 -c SidecarKeeper.tar.gz.sha256`, extract the
  archive, then run its `install.sh`.
- **Source:** see [Contributing](../CONTRIBUTING.md#build-and-test). A source checkout's
  `./install.sh` builds and installs both binaries, fetching SidecarLauncher at a pinned commit.

The release installer checks the archive against an embedded SHA-256. Downloaded bundles
require the manual check above. Release binaries are not notarized; the installer removes
their quarantine flag so macOS will allow them to run. See [Security](../SECURITY.md) for
trust and provenance details.

The standard installer accepts `--device "My iPad"`, `--wired`, `--prefix DIR` and
`--no-link`. To pass options through the one-line installer:

```sh
/bin/bash -c "$(curl -fsSL https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest/download/install.sh)" sk --device "My iPad"
```

## Configuration

```sh
sidecar-keeper config --init   # create a template without overwriting an existing file
open -e "$HOME/Library/Application Support/SidecarKeeper/config"
sidecar-keeper config          # inspect the settings file and report errors
```

Example settings:

```text
device = My iPad
interval = 15
wired = false
```

Use one `name = value` per line; values may be quoted. Lines beginning with `#`
(after optional whitespace) are comments. Inline comments are not supported.

| Setting | Default | Purpose |
| --- | --- | --- |
| `device` | First reachable iPad | Device name; case and apostrophe style are ignored |
| `interval` | `15` | Seconds between checks |
| `settle` | `8` | Seconds to wait after wake or unlock |
| `timeout` | `30` | Seconds before stopping a hung launcher call |
| `wired` | `false` | Require a USB cable; experimental |
| `usb-match` | `iPad` | USB product name to detect |
| `launcher` | Next to `sidecar-keeper` | Path to SidecarLauncher |
| `log` | `~/Library/Logs/sidecar-keeper.log` | Log location |

Settings also have command-line flags, listed by `sidecar-keeper --help`. Flags take
precedence over the file. The standard installer writes the selected device and any
`--wired` flag into `~/Library/LaunchAgents/com.sidecarkeeper.agent.plist`; re-run the
installer to change those, or edit the plist. Homebrew uses the settings file.

Restart after changing settings:

```sh
# Homebrew
brew services restart sidecarkeeper

# Standard installer
launchctl kickstart -k gui/$(id -u)/com.sidecarkeeper.agent
```

Invalid settings keep the watcher idle. Fix the reported line and restart.

## Wired mode

By default, macOS chooses USB or Wi-Fi. Set `wired = true` in the settings file, or use
`install.sh --wired`, to require the cable. Without a detected cable, the watcher stays
idle; it does not fall back to wireless.

A wired session can remain stuck after unplugging. When the watcher observes the cable
leave and return, it replaces the stale session. Cable detection and connection have been
tested on hardware; replug recovery is covered by simulated tests only.

`sidecar-keeper status` shows USB detection. If a connected iPad is missing, find its
product name with `ioreg -r -c IOUSBHostDevice -d1` and set `usb-match` accordingly.
An unplug and replug within one polling interval can be missed; toggle Sidecar off and
restart the watcher if it remains stuck.

To return to automatic transport, set `wired = false` and restart. If installed with
`--wired`, also re-run the installer without that flag.

## Troubleshooting

Start with `sidecar-keeper status` and `~/Library/Logs/sidecar-keeper.log`. If the command
is not on your `PATH` after a standard install, use `~/.sidecarkeeper/bin/sidecar-keeper`.

Status shows the watcher's latest observed state, such as paused, locked, waiting for a
USB cable, or device not reachable. During backoff it shows how long until a retry is
eligible; the next attempt still waits for a poll and all connection gates. It also shows
the last successful reconnection recorded by the watcher, including its date and iPad name.
An already-connected session does not change that timestamp. The record survives watcher
restarts and is removed by the standard uninstaller.

These observations update on watcher checks, not continuously. Stopped watchers and
expired observations are marked stale; a missing or unreadable record is marked unavailable.
An older watcher must be restarted after upgrading to produce live status.

| Status or log message | What to do |
| --- | --- |
| `ok` / `reconnected` | Nothing; Sidecar is connected |
| `locked, idle` / `screen off, idle` / `lid closed, idle` | Wake and unlock the Mac, and open the lid |
| `not reachable, idle` | Unlock the iPad, check its configured name, and bring it nearby or attach USB |
| `paused, idle` | Run `sidecar-keeper resume` |
| `settings file error` | Run `sidecar-keeper config`, fix the error and restart |
| `wired mode: no iPad on USB, idle` | Check the cable and [USB detection](#wired-mode) |
| `cable is back, restarting the wired session` | Nothing; recovery is in progress |
| `WiFiNotEnabled` (-203) | Unlock the iPad |
| `VirtualDisplay` (-500/-501) | Open the lid; retries wait up to five minutes or until wake/unlock |
| `timeout after 30s` | If it persists, toggle Sidecar in Control Centre |
| `cannot run launcher` | Run the installer again |

Use `pause` before disconnecting Sidecar intentionally; otherwise the watcher reconnects.
To pause temporarily, use `sidecar-keeper pause --for 1h`. Durations accept `s`, `m`, `h`
or `d` (for example, `30s`, `15m`, `1.5h` or `1d`), from one second to 365 days.
The expiry survives watcher restarts and is shown by `status`. After expiry, reconnection
waits for the next eligible check, including any existing failure backoff. A locked Mac,
closed lid, missing device or missing cable in wired mode still prevents reconnection.
Run plain `pause` to replace a timed pause with an indefinite one, or `resume` to end
either kind early. These commands do not interrupt a launcher call already in progress.

Failed attempts can still notify, but retries back off from 30 seconds to five minutes.
The watcher manages one iPad, and cannot keep Sidecar running with the built-in display off.
If a macOS update breaks connectivity, check for a newer release.

## Uninstall

For the standard installer:

```sh
~/.sidecarkeeper/uninstall.sh              # keep logs and settings
~/.sidecarkeeper/uninstall.sh --purge-logs # also remove logs
~/.sidecarkeeper/uninstall.sh --purge      # remove logs and settings too
```

For Homebrew:

```sh
brew services stop sidecarkeeper
brew uninstall sidecarkeeper
```

If you installed with `--prefix DIR` (or `SIDECARKEEPER_PREFIX`), use that same prefix
when uninstalling. It must be a dedicated directory: uninstall deletes it after checking
that the installer marked it as its own.
