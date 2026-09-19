# How it works

[Manual](README.md) · [Install](install.md) · [Configuration](configuration.md) · [Wired mode](wired-mode.md) · [Troubleshooting](troubleshooting.md) · [FAQ](faq.md) · [How it works](how-it-works.md) · [Development](development.md)

## Why this exists

Sidecar is great until the display sleeps. macOS drops the session whenever the built-in
display turns off, and it never reconnects by itself. The obvious fix, a script that calls
"connect" in a loop, makes things worse: while the screen is locked or the lid is closed the
connect cannot succeed, and **every failed attempt raises an "Unable to connect to iPad"
notification**. Leave that running overnight and you wake up to a hundred of them.

SidecarKeeper only tries when a connect can actually work, and backs off when it does not.

## How it decides

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
