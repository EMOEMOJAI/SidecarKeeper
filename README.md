<p align="center"><img src="assets/icon-256.png" width="112" height="112" alt="SidecarKeeper icon"></p>

<h1 align="center">SidecarKeeper</h1>

<p align="center"><b>Auto-reconnect Apple Sidecar on macOS.</b><br>
Reconnect your iPad after waking or unlocking your Mac.</p>

<p align="center">
  <a href="https://github.com/EMOEMOJAI/SidecarKeeper/actions/workflows/ci.yml"><img src="https://github.com/EMOEMOJAI/SidecarKeeper/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest"><img src="https://img.shields.io/github/v/release/EMOEMOJAI/SidecarKeeper?color=14B8A6" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14.2%2B-black.svg" alt="macOS 14.2 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center"><img src="assets/demo.svg" width="760" alt="SidecarKeeper's log over one day: it notes a lock, stays idle, reconnects the iPad nine seconds after unlock, idles all night with the lid closed, and reconnects in the morning."></p>

SidecarKeeper runs in the background and checks screen, lock, lid and device state before
trying to reconnect. Failed attempts back off to reduce repeated notifications.

## Install

Requires macOS 14.2 or newer and an iPad that already works with Sidecar. Unlock your iPad,
then paste this into Terminal:

```sh
/bin/bash -c "$(curl -fsSL https://github.com/EMOEMOJAI/SidecarKeeper/releases/latest/download/install.sh)"
```

The release install needs no Xcode, git, admin rights or special permissions. It starts
at login. Binaries support Apple silicon and Intel; they are not notarized, and the
installer removes their quarantine flag. See [Security](SECURITY.md) for verification details.

Or use Homebrew:

```sh
brew install emoemojai/tap/sidecarkeeper
brew services start sidecarkeeper
```

Choose one installation method. See the [user guide](docs/guide.md) for updates,
other install options and configuration.

## Use

```sh
sidecar-keeper status   # show service state and recent log entries
sidecar-keeper pause    # stop reconnecting when you disconnect on purpose
sidecar-keeper pause --for 1h  # resume automatically after an hour
sidecar-keeper resume   # start reconnecting again
```

Logs are at `~/Library/Logs/sidecar-keeper.log`. To choose an iPad or enable experimental
USB-only mode, follow [configuration](docs/guide.md#configuration).

Uninstall a standard installation with `~/.sidecarkeeper/uninstall.sh`. For Homebrew, run
`brew services stop sidecarkeeper` followed by `brew uninstall sidecarkeeper`.

## Limitations

- macOS drops Sidecar when the built-in display turns off. Reconnection waits until the
  screen is awake, the Mac is unlocked and the lid is open.
- The iPad must be reachable and unlocked. Failed connections can still show a macOS
  notification.
- It uses Apple's private SidecarCore framework through
  [SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher), so macOS updates may break it.
- Actual Sidecar sessions have been tested on Apple silicon. CI also builds and tests on Intel.

[User guide](docs/guide.md) · [Website](https://emoemojai.github.io/SidecarKeeper/) ·
[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

Built on SidecarLauncher by Jovany Ocasio. MIT licensed. Not affiliated with Apple.
