# Contributing

Bug reports, fixes and reports of behaviour on other macOS versions or hardware are welcome.

**Reporting a bug.** Include your macOS version, Mac model family, whether the iPad is on
USB or Wi-Fi, the output of `sidecar-keeper status`, and the relevant lines of
`~/Library/Logs/sidecar-keeper.log`. The log records every decision the watcher makes, so it
usually shows the cause. Check the log for device names you would rather not share.

**Changing code.** Run `make check` before opening a pull request. It builds with warnings
as errors, runs the behaviour tests, and lints the scripts. CI runs the same on macOS 14, 15
and 26. A behaviour change needs a test in `tests/run.sh` that fails without your change.
[AGENTS.md](AGENTS.md) lists the project's rules and the platform facts behind the design,
and is worth reading whether or not you are an AI.

**The one rule.** A failed connect attempt shows the user a notification, so the watcher
must never attempt a connect that cannot succeed. Changes that loosen a gate need a very
good reason.
