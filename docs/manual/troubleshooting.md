# Troubleshooting and limitations

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

## Troubleshooting

Start with `sidecar-keeper status`. What the log lines mean:

| Log line | Meaning | What to do |
| --- | --- | --- |
| `ok` | Sidecar is connected | Nothing |
| `reconnected <name>` | A dropped session was restored | Nothing |
| `<name> not reachable, idle` | The iPad is not in `devices` | Unlock it, bring it closer or plug in USB, check the name with `~/.sidecarkeeper/bin/SidecarLauncher devices` |
| `locked, idle` / `screen off, idle` / `lid closed, idle` | macOS cannot host Sidecar right now | Nothing, it resumes by itself |
| `paused, idle` | You ran `pause` | `sidecar-keeper resume` |
| `settings file error (line N: ...)` | A mistake in the settings file | Run `sidecar-keeper config`, fix the line it names, restart the watcher |
| `wired mode: no iPad on USB, idle` | `--wired` is on and no cable is detected | Plug the iPad in, or see [Wired mode](wired-mode.md) |
| `cable is back, restarting the wired session` | A dead wired session was replaced | Nothing |
| `fail: ... WiFiNotEnabled` (-203) | The iPad is locked or asleep | Unlock the iPad |
| `fail: ... VirtualDisplay` (-500/-501) | Display stack is busy, or the lid is closed | Wait, it retries in 5 min or on the next wake/unlock |
| `fail: timeout after 30s` | SidecarLauncher hung | Usually clears by itself; otherwise toggle Sidecar once in Control Centre |
| `cannot run launcher ...` | SidecarLauncher binary is missing | Run the installer again |

If a macOS update breaks things, run the installer again, and check for a newer release.

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
