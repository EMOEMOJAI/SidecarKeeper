#!/bin/bash
# Stand-in for SidecarLauncher. Behaviour comes from the file "mode" next to this script;
# every connect call is appended to "calls", and every full command line to "argv".
dir="$(cd "$(dirname "$0")" && pwd)"
mode="$(cat "$dir/mode")"
[ "$1" = devices ] || echo "$*" >> "$dir/argv"
case "$1" in
  devices)
    echo probe >> "$dir/probes"
    if [ "$mode" = hangdevices ]; then sleep 60; fi
    if [ "$mode" = leaky ]; then
      ( trap '' TERM; exec sleep 20 ) & # a child that keeps the pipe open
      echo "$!" > "$dir/leaky-child"
      wait
    fi
    if [ "$mode" = none ]; then echo "No sidecar capable devices detected"; exit 2; fi
    printf 'Other iPad\nJoe\xe2\x80\x99s iPad\n' ;;
  connect)
    echo "$2" >> "$dir/calls"
    case "$mode" in
      new)  echo "connected" ;;
      ok)   echo 'Error Domain=SidecarErrorDomain Code=-402 "SidecarErrorServiceAlreadyInUse"'; exit 4 ;;
      fail) echo 'Error Domain=SidecarErrorDomain Code=-203 "SidecarErrorDeviceWiFiNotEnabled"'; exit 4 ;;
      vd)   echo 'Error Domain=SidecarErrorDomain Code=-501 "SidecarErrorVirtualDisplayFailed"'; exit 4 ;;
      trap) echo 'Error: device is not connected to power'; exit 4 ;;
      hang) sleep 60 ;;
      stale) # a dead wired session: "in use" until someone disconnects it
        if [ -f "$dir/disconnected" ]; then echo "connected"
        else echo 'Error Domain=SidecarErrorDomain Code=-100 "SidecarErrorServiceAlreadyInUse"'; exit 4; fi ;;
    esac ;;
  disconnect) touch "$dir/disconnected"; echo "disconnected" ;;
esac
