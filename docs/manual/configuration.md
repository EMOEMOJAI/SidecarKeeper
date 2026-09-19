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

## Settings file

The easiest way to change an option, and the only way under `brew services`, is the settings
file:

```sh
sidecar-keeper config --init   # creates a commented template, never overwrites
open -e "$HOME/Library/Application Support/SidecarKeeper/config"
sidecar-keeper config          # shows what is in effect, or what is wrong
```

```
device = My iPad
wired = true
interval = 15
```

One `name = value` per line. Names are the option names below without the dashes, `wired`
takes `true` or `false`, values may be quoted, and `#` starts a comment. Restart the watcher to
apply a change: `brew services restart sidecarkeeper`, or
`launchctl kickstart -k gui/$(id -u)/com.sidecarkeeper.agent` for the standard installer.

Flags on the command line win over the file. The standard installer writes `--device` and
friends into its LaunchAgent, so for that route either re-run the installer or edit the plist.

If the file contains a mistake, the watcher logs `settings file error (line N: ...)` and stays
idle until you fix it. It will not fall back to the defaults, because "the first reachable
iPad" could be the wrong one.

## Command-line options

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
