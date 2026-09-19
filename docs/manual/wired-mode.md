# Wired mode (experimental)

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

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
