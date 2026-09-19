# Install and uninstall

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

## Prerequisites

- macOS 14.2 or newer. Used daily on Apple silicon; CI builds, tests and installs it on Apple silicon and on a real Intel Mac, though Sidecar itself has only been exercised on Apple silicon. Sidecar itself must already work
  between the two devices (same Apple ID, Wi-Fi and Bluetooth on, or a USB cable).
- Nothing else for the release install. Building from source needs the Xcode Command Line
  Tools and git.
- The iPad must be unlocked for a connect to succeed. A locked or sleeping iPad still
  shows up in `devices` but returns `SidecarErrorDeviceWiFiNotEnabled` (-203); the
  watcher backs off and retries.
- USB is recommended: a wired iPad stays reachable and reconnects faster.

## Install

Unlock the iPad first so it shows up. There are four ways, and all end in the same place.

**1. One line (recommended).** Downloads the latest release, checks the archive against the
SHA-256 stamped into that release's installer, and installs the prebuilt binaries. Nothing
else is required.

```sh
/bin/bash -c "$(curl -fsSL https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest/download/install.sh)"
```

Pass options after a placeholder name, for example `... install.sh)" sk --device "My iPad"`.
If you would rather read a script before running it, download `install.sh` from the
[latest release](https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest) first. It is
short.

**2. Homebrew.** Builds from source with the compiler Homebrew already requires.

```sh
brew install emoemojai/tap/sidecarkeeper
brew services start sidecarkeeper
```

The Homebrew service keeps the first reachable iPad connected. To pick a specific iPad or
use wired mode, put it in the [settings file](configuration.md#settings-file). Do not run both, or two watchers will compete;
`sidecar-keeper status` warns you if that happens.

**3. Download the release.** Get `SidecarKeeper.tar.gz` from the
[latest release](https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest), unpack it,
open Terminal, drag `install.sh` into the window and press Return. This route checks
nothing by itself, so verify the download first if you want that: `shasum -a 256 -c
SidecarKeeper.tar.gz.sha256`, or the attestation command below.

**4. Build from source.** Needs the Xcode Command Line Tools (`xcode-select --install`) and
git.

```sh
git clone https://github.com/EMOEMOJAI/SidecarKeeper.git
cd SidecarKeeper
./install.sh                      # one iPad reachable: uses it. Several: asks you.
./install.sh --device "My iPad"   # or name it explicitly
./install.sh --wired              # cable only, see [Wired mode](wired-mode.md)
```

Apart from Homebrew, which uses its own directories and `brew services`, every route
installs two small binaries to `~/.sidecarkeeper/bin`, writes
`~/Library/LaunchAgents/com.sidecarkeeper.agent.plist` and starts it. If a user-writable
directory such as `/opt/homebrew/bin` is on your `PATH`, the `sidecar-keeper` command is
linked there (`--no-link` to skip). Nothing needs `sudo`, and running the installer again
is the way to update or change the device.

Release binaries are universal (Apple silicon and Intel), built by GitHub Actions from the
tagged source, and not notarized, because that requires a paid Apple developer account.
macOS quarantines browser downloads and will not run un-notarized binaries while that flag
is set, so the installer removes it from the two binaries it installs. Be aware that this
also means macOS will not ask you before they run.
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

## Uninstall

```sh
~/.sidecarkeeper/uninstall.sh              # stops the agent, removes plist and ~/.sidecarkeeper
~/.sidecarkeeper/uninstall.sh --purge-logs # also removes the log files
~/.sidecarkeeper/uninstall.sh --purge      # logs and your settings file too
```

Both scripts accept `--prefix DIR` (or `SIDECARKEEPER_PREFIX`) to use a different install
directory. It must be a dedicated directory, because uninstalling deletes it. The
uninstaller only removes a directory that the installer marked as its own, so pass the
same `--prefix` to both.
