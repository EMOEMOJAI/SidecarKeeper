#!/bin/bash
# Removes the SidecarKeeper LaunchAgent, binaries and (optionally) logs.
#   ./uninstall.sh [--prefix DIR] [--purge-logs] [--purge]
# Your settings file is kept unless you pass --purge, so a reinstall picks it up again.
set -euo pipefail

# Everything runs inside main, called on the last line, so bash has read the whole file
# before this script deletes the directory it may be running from.
main() {
  LABEL="com.sidecarkeeper.agent"
  # When run from inside an install directory, that directory is the default prefix.
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if grep -q '^SidecarKeeper install directory' "$SELF_DIR/.sidecarkeeper" 2>/dev/null; then DEFAULT_PREFIX="$SELF_DIR"; else DEFAULT_PREFIX="$HOME/.sidecarkeeper"; fi
  PREFIX="${SIDECARKEEPER_PREFIX:-$DEFAULT_PREFIX}"
  PURGE=0
  PURGE_SETTINGS=0
  LEFTOVER=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
      --purge-logs) PURGE=1; shift ;;
      --purge) PURGE=1; PURGE_SETTINGS=1; shift ;;
      -h|--help) echo "usage: uninstall.sh [--prefix DIR] [--purge-logs] [--purge]   (--purge: logs and settings too)"; exit 0 ;;
      *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "==> Stopping $LABEL"; launchctl bootout "gui/$(id -u)/$LABEL" || true
  fi
  if [ -f "$PLIST" ]; then echo "==> Removing $PLIST"; rm -f "$PLIST"; fi
  # Remove the PATH symlink only if it is still ours.
  if [ -f "$PREFIX/symlink" ]; then
    LINK="$(cat "$PREFIX/symlink")"
    if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$PREFIX/bin/sidecar-keeper" ]; then
      echo "==> Removing $LINK"; rm -f "$LINK"
    fi
  fi
  # Only delete a directory that install.sh marked as ours. The marker must be a real file:
  # a symlinked or merely similar-looking directory is never removed.
  if [ -f "$PREFIX/.sidecarkeeper" ] && [ ! -L "$PREFIX/.sidecarkeeper" ] && [ ! -L "$PREFIX" ] \
     && grep -q '^SidecarKeeper install directory' "$PREFIX/.sidecarkeeper"; then
    case "${PREFIX%/}" in
      ""|"$HOME"|/usr|/usr/local|/opt|/opt/homebrew|/Applications|/Library|/System|/bin|/sbin|/etc|/var|/tmp)
        echo "error: refusing to delete $PREFIX" >&2; exit 1 ;;
    esac
    echo "==> Removing $PREFIX"; rm -rf "$PREFIX"
  elif [ -e "$PREFIX" ]; then
    echo "warning: $PREFIX has no SidecarKeeper marker, left untouched" >&2; LEFTOVER=1
  else
    echo "note: nothing at $PREFIX. If you installed with --prefix, pass the same --prefix here." >&2; LEFTOVER=1
  fi
  # The pause flag lives in the watcher's state directory, which is independent of --prefix.
  STATE="$HOME/Library/Application Support/SidecarKeeper"
  rm -f "$STATE/paused" "$HOME/.sidecarkeeper/paused" 2>/dev/null || true
  if [ "$PURGE_SETTINGS" -eq 1 ]; then
    echo "==> Removing settings"; rm -f "$STATE/config"; rmdir "$STATE" 2>/dev/null || true
  elif [ -f "$STATE/config" ]; then
    echo "note: kept your settings in $STATE/config (use --purge to remove them too)"
  fi
  if [ "$PURGE" -eq 1 ]; then
    echo "==> Removing logs"
    rm -f "$HOME/Library/Logs/sidecar-keeper.log" "$HOME/Library/Logs/sidecar-keeper.log.1" "$HOME/Library/Logs/sidecar-keeper.out"
  fi
  if [ "$LEFTOVER" -eq 1 ]; then
    echo "LaunchAgent removed; the install directory was not (see above)."
  else
    echo "SidecarKeeper removed."
  fi
}

main "$@"
