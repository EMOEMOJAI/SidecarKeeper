# Security

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/EMOEMOJAI/SidecarKeeper/security/advisories/new),
not in a public issue. You can expect a first reply within a week.

In scope: the watcher, `install.sh`, `uninstall.sh`, and the LaunchAgent they create. Things
worth reporting include the installer or uninstaller touching files outside the install
prefix, injection through device names, paths or environment variables, and anything that
runs with more privilege than a per-user LaunchAgent.

SidecarKeeper never uses `sudo`, makes no network requests at runtime, and collects no data.
The installer fetches one pinned commit of
[SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) from GitHub and builds it
locally. Issues in SidecarLauncher or in Apple's private `SidecarCore` framework belong
upstream.

Only the latest release is supported.
