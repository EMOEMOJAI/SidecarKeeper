# Everyday use and configuration

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

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
