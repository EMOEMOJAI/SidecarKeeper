<p align="center"><img src="assets/icon-256.png" width="128" height="128" alt="SidecarKeeper icon"></p>

# SidecarKeeper

**Auto-reconnect Apple Sidecar on macOS.** Keep your iPad working as a second display: when
Sidecar disconnects after sleep, lock or a lid close, SidecarKeeper brings it back by itself.

<p align="center">
  <a href="https://github.com/EMOEMOJAI/SidecarKeeper/actions/workflows/ci.yml"><img src="https://github.com/EMOEMOJAI/SidecarKeeper/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14.2%2B-black.svg" alt="macOS 14.2 or newer">
</p>

Keeps [Sidecar](https://support.apple.com/en-us/102597) connected from your Mac to your iPad,
automatically and quietly. When the session drops (display sleep, lock, lid close, iPad
walked out of range) it reconnects as soon as macOS is able to, without the stream of
"Unable to connect to iPad" notifications that naive retry loops produce.

Built on [Ocasio-J/SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) (MIT), a
tiny CLI that drives Apple's private `SidecarCore` framework. SidecarKeeper adds a
LaunchAgent that decides *when* it is safe to call it.

Tested on macOS 27.0 on Apple silicon with an iPad over USB. CI builds and tests it on
macOS 14, 15 and 26.

## Quick start

Unlock your iPad, then paste this into Terminal:

```sh
/bin/bash -c "$(curl -fsSL https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest/download/install.sh)"
```

That is the whole install. It needs nothing but macOS: no Xcode, no git, no `sudo`. It
starts at login and needs no further attention. Other ways to install, and what the command
does, are under [Install](#install).

## Why this exists

Sidecar is great until the display sleeps. macOS drops the session whenever the built-in
display turns off, and it never reconnects by itself. The obvious fix, a script that calls
"connect" in a loop, makes things worse: while the screen is locked or the lid is closed the
connect cannot succeed, and **every failed attempt raises an "Unable to connect to iPad"
notification**. Leave that running overnight and you wake up to a hundred of them.

SidecarKeeper only tries when a connect can actually work, and backs off when it does not.

## How it works

`sidecar-keeper` is a small Swift daemon that ticks every 15 s and only calls
`SidecarLauncher connect` when all of these are true:

| Gate | Signal |
| --- | --- |
| Not paused by you | `sidecar-keeper pause` / `resume` |
| Built-in screens are awake | `NSWorkspace` screensDidSleep / screensDidWake / didWake |
| Login session is unlocked | `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` |
| Lid is open (laptops) | `ioreg` `AppleClamshellState` |
| iPad is reachable | it appears in `SidecarLauncher devices` (8 ms call) |
| Cable attached (only with `--wired`) | an iPad on the USB bus, via `ioreg` (3 ms call) |

Wake and unlock events trigger a reconnect after an 8 s settle delay. Failures back off
from 30 s up to 5 min (straight to 5 min on `VirtualDisplay` errors, which mean the display
stack is still changing). A hung `SidecarLauncher` call is killed after 30 s so the
watcher can never wedge. A repeated state is logged only once, so the log stays readable:

```
2026-09-18 11:53:54 ok
2026-09-18 12:45:44 session locked
2026-09-18 12:45:53 locked, idle
2026-09-18 12:53:13 session unlocked
2026-09-18 12:53:24 ok
```

Observed on the test machine: reconnect 5-9 s after a drop, no connect attempts while
locked or with the lid closed, no attempts when the iPad is out of range.

## Prerequisites

- macOS 14.2 or newer. Tested on Apple silicon; Intel is expected to work but untested. Sidecar itself must already work
  between the two devices (same Apple ID, Wi-Fi and Bluetooth on, or a USB cable).
- Nothing else for the release install. Building from source needs the Xcode Command Line
  Tools and git.
- The iPad must be unlocked for a connect to succeed. A locked or sleeping iPad still
  shows up in `devices` but returns `SidecarErrorDeviceWiFiNotEnabled` (-203); the
  watcher backs off and retries.
- USB is recommended: a wired iPad stays reachable and reconnects faster.

## Install

Unlock the iPad first so it shows up. There are three ways, and all end in the same place.

**1. One line (recommended).** Downloads the latest release, verifies its SHA-256, and
installs the prebuilt binaries. Nothing else is required.

```sh
/bin/bash -c "$(curl -fsSL https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest/download/install.sh)"
```

Pass options after a placeholder name, for example `... install.sh)" sk --device "My iPad"`.
If you would rather read a script before running it, download `install.sh` from the
[latest release](https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest) first. It is
short.

**2. Download the release.** Get `SidecarKeeper.tar.gz` from the
[latest release](https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest), unpack it,
open Terminal, drag `install.sh` into the window and press Return. The installer clears the
quarantine flag that macOS puts on browser downloads, which is why it has to be started from
Terminal and not by double-clicking.

**3. Build from source.** Needs the Xcode Command Line Tools (`xcode-select --install`) and
git.

```sh
git clone https://github.com/EMOEMOJAI/SidecarKeeper.git
cd SidecarKeeper
./install.sh                      # one iPad reachable: uses it. Several: asks you.
./install.sh --device "My iPad"   # or name it explicitly
./install.sh --wired              # cable only, see "Wired mode" below
```

Every route installs two small binaries to `~/.sidecarkeeper/bin`, writes
`~/Library/LaunchAgents/com.sidecarkeeper.agent.plist` and starts it. If a user-writable
directory such as `/opt/homebrew/bin` is on your `PATH`, the `sidecar-keeper` command is
linked there (`--no-link` to skip). Nothing needs `sudo`, and running the installer again
is the way to update or change the device.

Release binaries are universal (Apple silicon and Intel), built by GitHub Actions from the
tagged source, and not notarized, because that requires a paid Apple developer account.
You can check where they came from with
`gh attestation verify SidecarKeeper.tar.gz --repo EMOEMOJAI/SidecarKeeper`. When building
from source, [SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) is fetched at a
pinned commit and compiled locally.

Then optionally keep the Mac awake with the lid closed while on AC power:

```sh
sudo pmset -c disablesleep 1   # undo with: sudo pmset -c disablesleep 0
```

This is a system-wide power setting, not part of SidecarKeeper, and `uninstall.sh` does not
change it back.

## Everyday use

```sh
sidecar-keeper status   # agent state, paused or not, last log lines
sidecar-keeper pause    # you disconnected Sidecar on purpose: stop reconnecting
sidecar-keeper resume   # start reconnecting again
tail -f ~/Library/Logs/sidecar-keeper.log
```

Without `pause`, a manual disconnect is indistinguishable from a drop, so the watcher
reconnects within about 15 s. If the command is not on your `PATH`, use
`~/.sidecarkeeper/bin/sidecar-keeper`.

## Uninstall

```sh
~/.sidecarkeeper/uninstall.sh              # stops the agent, removes plist and ~/.sidecarkeeper
~/.sidecarkeeper/uninstall.sh --purge-logs # also removes the log files
```

Both scripts accept `--prefix DIR` (or `SIDECARKEEPER_PREFIX`) to use a different install
directory. It must be a dedicated directory, because uninstalling deletes it. The
uninstaller only removes a directory that the installer marked as its own, so pass the
same `--prefix` to both.

## Configuration

Everything is a command-line flag on `sidecar-keeper`, so edit the LaunchAgent plist (or
re-run `install.sh`) to change it:

```
--device NAME       iPad name as printed by `SidecarLauncher devices`; case and
                    straight/curly apostrophes are ignored
                    (default: the first reachable device)
--launcher PATH     path to SidecarLauncher (default: next to sidecar-keeper)
--log PATH          log file (default: ~/Library/Logs/sidecar-keeper.log)
--interval SECONDS  poll interval (default: 15)
--settle SECONDS    delay after wake/unlock before reconnecting (default: 8)
--timeout SECONDS   give up on a hung SidecarLauncher call (default: 30)
--wired             experimental: connect over the USB cable only
--usb-match TEXT    USB product name that means "the iPad is cabled" (default: iPad)
```

After editing the plist: `launchctl kickstart -k gui/$(id -u)/com.sidecarkeeper.agent`.

## Wired mode (experimental)

`./install.sh --wired` makes the watcher use SidecarLauncher's `-wired` option, which
forces the session over the USB cable for lower latency and no Wi-Fi dependence. Upstream
marks the option experimental, and a wired session has two sharp edges that the watcher
handles for you:

- **A wired connect fails when no cable is attached**, and every failure is a
  notification. So in wired mode the watcher checks the USB bus first and stays idle,
  logging `wired mode: no iPad on USB, idle`, until an iPad is plugged in.
- **A wired session does not survive an unplug and never recovers by itself.** macOS keeps
  reporting the dead session as in use. When the watcher has seen the cable go away and
  come back, it ends the stale session and starts a fresh wired one, logging
  `cable is back, restarting the wired session`. A session that was never unplugged is
  left alone.

Connecting over the cable and the USB detection have been tested on real hardware. The
replug recovery follows upstream's description of the failure and is covered by simulated
tests only, so treat it as the least proven part.

There is no fallback to wireless in this mode: no cable means no Sidecar. Re-run
`./install.sh` without `--wired` to go back to the default, which uses whichever transport
macOS picks.

`sidecar-keeper status` shows whether an iPad is currently seen on USB. If yours is
plugged in but not detected, find its product name with
`ioreg -r -c IOUSBHostDevice -d1 | grep "USB Product Name"` and add
`--usb-match "<that name>"` to the LaunchAgent arguments. An unplug and replug that both
happen within one 15 s poll can be missed; `launchctl kickstart -k
gui/$(id -u)/com.sidecarkeeper.agent` after toggling Sidecar off clears that case.

## Troubleshooting

Start with `sidecar-keeper status`. What the log lines mean:

| Log line | Meaning | What to do |
| --- | --- | --- |
| `ok` | Sidecar is connected | Nothing |
| `reconnected <name>` | A dropped session was restored | Nothing |
| `<name> not reachable, idle` | The iPad is not in `devices` | Unlock it, bring it closer or plug in USB, check the name with `~/.sidecarkeeper/bin/SidecarLauncher devices` |
| `locked, idle` / `screen off, idle` / `lid closed, idle` | macOS cannot host Sidecar right now | Nothing, it resumes by itself |
| `paused, idle` | You ran `pause` | `sidecar-keeper resume` |
| `wired mode: no iPad on USB, idle` | `--wired` is on and no cable is detected | Plug the iPad in, or see "Wired mode" |
| `cable is back, restarting the wired session` | A dead wired session was replaced | Nothing |
| `fail: ... WiFiNotEnabled` (-203) | The iPad is locked or asleep | Unlock the iPad |
| `fail: ... VirtualDisplay` (-500/-501) | Display stack is busy, or the lid is closed | Wait, it retries in 5 min or on the next wake/unlock |
| `fail: timeout after 30s` | SidecarLauncher hung | Usually clears by itself; otherwise toggle Sidecar once in Control Centre |
| `cannot run launcher ...` | SidecarLauncher binary is missing | Run the installer again |

If a macOS update breaks things, run the installer again, and check for a newer release.

## FAQ

**Sidecar keeps disconnecting when my Mac sleeps or locks. Does this fix it?**
It fixes the part that can be fixed. macOS always drops Sidecar when the built-in display
turns off, and nothing can prevent that. SidecarKeeper reconnects automatically within a
few seconds of the display coming back, so you never reconnect by hand.

**How do I automatically connect my iPad as a second display at login?**
Install SidecarKeeper. Its LaunchAgent starts at login and connects as soon as the iPad is
reachable and unlocked.

**Can I use Sidecar with the MacBook lid closed (clamshell mode)?**
No. macOS cannot create the Sidecar virtual display while the built-in display is off
(error -501). This is an Apple limitation that no tool can work around. SidecarKeeper
waits quietly and reconnects when you open the lid.

**How do I stop the "Unable to connect to iPad" notifications?**
Those come from connect attempts that were never going to succeed. SidecarKeeper checks
screen, lock, lid and device state first, and backs off from 30 seconds to 5 minutes after
a real failure, so the notifications stop.

**How is this different from SidecarLauncher, a Shortcut, or an AppleScript?**
[SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) connects once when you run
it, and SidecarKeeper uses it for exactly that. Shortcuts and AppleScript click through
Control Centre and break with macOS updates. None of them watch the session or know when
a connect is safe to try. SidecarKeeper is the always-on layer that decides when to call
connect.

**Does it work over USB, or Wi-Fi only?**
Both. By default macOS picks the transport. `./install.sh --wired` forces the cable, see
[Wired mode](#wired-mode-experimental).

**I disconnected on purpose and it reconnected. How do I stop that?**
Run `sidecar-keeper pause`, and `sidecar-keeper resume` when you want it back.

**Do I need Xcode or any developer tools?**
No. The release install needs only macOS. Developer tools are needed only if you choose to
build from source.

**Does it need admin rights, a kernel extension, or accessibility permission?**
No. It is a per-user LaunchAgent and two small binaries in `~/.sidecarkeeper`. It never
asks for `sudo` and needs no privacy permissions.

**Is it safe? It uses a private Apple framework.**
It calls the same `SidecarCore` framework that Control Centre uses, through
SidecarLauncher, built from source at a pinned commit on your own machine. Apple may change
that framework in any update. If that happens, connects fail and get logged, and nothing
else on your Mac is affected.

**Which macOS and iPad versions are supported?**
macOS 14.2 or newer. It is tested on Apple silicon. Intel Macs should work, since nothing
in it is architecture-specific, but that is untested. Any iPad that already works with
Sidecar on your Mac.

## Limitations

- **Lid closed = no Sidecar.** macOS cannot create the Sidecar virtual display while the
  built-in display is off (error -501), even with `disablesleep`. Sidecar drops when the
  lid closes and comes back within seconds of opening it. This is a Sidecar limitation.
- **Any built-in-display-off state drops the session** (idle display sleep, lock screen,
  lid). The watcher waits for the display to return rather than fighting it.
- **Failed attempts still notify.** Every failed `connect` raises a macOS notification,
  which is exactly why attempts are gated and backed off. If you see notifications, check
  the log for the error being returned.
- **Private API.** SidecarLauncher uses `SidecarCore`, which Apple can change in any macOS
  update. If `SidecarLauncher devices` stops working after an update, check upstream.
- **One iPad per watcher.** It keeps a single named device connected.

## Development

```sh
make build   # build/sidecar-keeper
make test    # 43 behaviour tests against a fake SidecarLauncher, no iPad needed (~40 s)
make check   # build + test + bash -n + shellcheck + plist lint; run before pushing
make package # release bundle with universal binaries, in dist/
```

CI runs on GitHub-hosted runners for every push and pull request: the same build and
tests on macOS 14, 15 and 26, a real install and uninstall on each (from source and from a
release bundle with the compiler disabled), and shellcheck on Linux. Pushing a `v*` tag
runs the release workflow, which builds the bundle, installs it on all three macOS
versions, and only then publishes it. The tests run the real watcher binary, so its real gates apply: locally, run them
with the screen unlocked and the lid open.
`SIDECARLAUNCHER_REF=<full 40-character sha> ./install.sh` builds a different upstream commit.

The icon, favicon and social preview are hand-written SVG in `assets/`. After editing
one, run `assets/render.sh` to regenerate the PNG and ICO files (needs Google Chrome,
`python3` and `sips`). The `favicon.svg` in the repo root is a copy of
`assets/favicon.svg`, kept there because some editors and tools look for a project icon
at that path.

Run it in the foreground against your existing install to experiment:

```sh
build/sidecar-keeper --launcher ~/.sidecarkeeper/bin/SidecarLauncher --log /tmp/sk.log --interval 5
```

## Credits

- [Ocasio-J/SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) by Jovany Ocasio,
  MIT. SidecarKeeper builds it unmodified, at a pinned commit, at install time.

## License

MIT, see [LICENSE](LICENSE).
