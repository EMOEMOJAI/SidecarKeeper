# Frequently asked questions

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

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
[Wired mode](wired-mode.md).

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
macOS 14.2 or newer, on Apple silicon or Intel. CI builds, tests and installs it on both,
including a real Intel Mac. An actual Sidecar session has only been exercised on Apple
silicon, because CI machines have no iPad. Any iPad that already works with
Sidecar on your Mac.
