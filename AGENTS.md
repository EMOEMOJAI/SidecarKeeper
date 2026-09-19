# AGENTS.md

Guidance for AI coding agents and automated tools working in this repository.

## What this project is

SidecarKeeper keeps Apple Sidecar (a Mac using an iPad as a second display) connected. It is
one Swift file compiled with `swiftc`, two bash scripts, and a launchd plist template. There
is no Swift package, no Xcode project and no third-party dependency.

| Path | Role |
| --- | --- |
| `Sources/SidecarKeeper/main.swift` | The watcher daemon and its `pause` / `resume` / `status` subcommands |
| `install.sh`, `uninstall.sh` | Build, install to `~/.sidecarkeeper`, load or remove the LaunchAgent |
| `launchd/com.sidecarkeeper.plist.template` | LaunchAgent template, filled in by `install.sh` |
| `tests/run.sh`, `tests/fake-launcher.sh` | Behaviour tests driven by a fake SidecarLauncher |
| `scripts/package.sh`, `.github/workflows/release.yml` | Release bundle with prebuilt universal binaries; a `v*` tag builds, verifies and publishes it |
| `docs/manual/` | The full documentation. The README is deliberately short and links here |
| `assets/`, `docs/` | Icons and the project website. `assets/render.sh` regenerates the PNGs |

## Commands

```sh
make build   # swiftc -O -warnings-as-errors, output in build/
make test    # behaviour tests, about 60 s, no iPad required
make check   # build + test + bash -n + shellcheck + plist lint. Run before every commit.
```

## Rules that matter

1. **Never run a real `SidecarLauncher connect` or `disconnect` in tests or while exploring.**
   It changes the user's live display layout, and a failed connect raises a macOS
   notification. Use `tests/fake-launcher.sh`, the way `tests/run.sh` does.
2. **Do not run `install.sh` or `uninstall.sh` casually.** They load and remove a real
   LaunchAgent. To exercise them, pass a throwaway `--prefix` and `--no-link`, and uninstall
   afterwards. CI does this on every push.
3. **Always pass `--log` when running the watcher by hand**, plus
   `SIDECARKEEPER_STATE_DIR` (it holds the settings file and the pause flag) and `SIDECARKEEPER_USB_PROBE` pointing at temp paths, so the
   user's real log and pause state are untouched.
4. **The central invariant: never attempt a connect that cannot succeed.** Every gate in
   `tick()` exists because a failed attempt is user-visible. A change that adds a connect
   path must keep all gates in front of it and needs a test proving no attempt is made.
5. **Warnings are errors** in both `make build` and CI. Scripts must pass
   `shellcheck -S style`.
6. **Behaviour changes need a test** in `tests/run.sh`, and a new test should fail against
   the old code. Add a mode to `tests/fake-launcher.sh` when you need new launcher behaviour.
7. **Keep it dependency-free** and a single Swift file unless there is a strong reason.
8. **Releasing:** bump `version` in `main.swift`, add a matching `## x.y.z` section to
   `CHANGELOG.md`, push, then push the tag `vx.y.z`. The workflow refuses a tag that does
   not match both. Never attach binaries built on a personal machine.
9. The upstream SidecarLauncher commit is pinned by full SHA in `install.sh`. Bump it
   deliberately, after reading the upstream diff.

## Platform facts worth knowing before changing behaviour

- macOS drops Sidecar whenever the built-in display turns off. This cannot be prevented.
- Sidecar cannot start while a laptop lid is closed (error -501).
- A locked or sleeping iPad still appears in `devices` but connect fails with -203.
- `CGDisplayIsAsleep` was found unreliable as a display-off signal, so the watcher relies on
  `NSWorkspace` sleep and wake notifications instead.
- A wired (`-wired`) session does not recover after an unplug; see `docs/manual/wired-mode.md`.

## Style

Match the surrounding code: compact Swift, comments that explain why rather than what.
README and manual prose is plain and factual, and every claim should be something that was
tested. The README stays short, for a first-time visitor; detail belongs in `docs/manual/`.
