#!/bin/bash
# Behaviour tests for sidecar-keeper using a fake SidecarLauncher. No iPad is touched.
#   tests/run.sh [path-to-sidecar-keeper]
# The watcher's real gates still apply, so run with the screen unlocked and the lid open.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/sidecar-keeper}"
TMP="${TMPDIR:-/tmp}"; WORK="$(mktemp -d "${TMP%/}/sk-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/fake-launcher.sh" "$WORK/SidecarLauncher"; chmod +x "$WORK/SidecarLauncher"
export SIDECARKEEPER_STATE_DIR="$WORK/state"
# Fake USB bus: the watcher reads this script's output instead of calling ioreg.
printf '#!/bin/bash\ncat "%s/usb" 2>/dev/null\n' "$WORK" > "$WORK/usb-probe"; chmod +x "$WORK/usb-probe"
export SIDECARKEEPER_USB_PROBE="$WORK/usb-probe"
plug()   { echo '    "USB Product Name" = "iPad"' > "$WORK/usb"; }
unplug() { echo '    "USB Product Name" = "Some Keyboard"' > "$WORK/usb"; }
PASS=0; FAIL=0

# watch MODE SECONDS [watcher args...]  -> fills $LOG and $CALLS
watch() {
  local mode="$1" secs="$2"; shift 2
  echo "$mode" > "$WORK/mode"; rm -f "$WORK/calls" "$WORK/argv" "$WORK/probes" "$WORK/disconnected" "$WORK/log"
  "$BIN" --launcher "$WORK/SidecarLauncher" --log "$WORK/log" --interval 1 "$@" &
  local pid=$!; sleep "$secs"; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  LOG="$(cat "$WORK/log" 2>/dev/null)"; CALLS="$(cat "$WORK/calls" 2>/dev/null)"; ARGV="$(cat "$WORK/argv" 2>/dev/null)"
}
# The launcher's first commands must be exactly $2 (later ticks may repeat the connect).
argv_is() { local n; n=$(grep -c . <<<"$2"); if [ "$(head -n "$n" <<<"$ARGV")" = "$2" ]; then ok "$1"; else bad "$1 (launcher commands were: ${ARGV//$'\n'/ ; })"; fi; }
ok()   { PASS=$((PASS+1)); echo "  pass: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "    log:   ${LOG//$'\n'/$'\n'           }"; echo "    calls: $CALLS"; }
has()  { if grep -qF -- "$2" <<<"$LOG"; then ok "$1"; else bad "$1 (log lacks: $2)"; fi; }
hasnt(){ if grep -qF -- "$2" <<<"$LOG"; then bad "$1 (log has: $2)"; else ok "$1"; fi; }
ncalls(){ local n; n=$(grep -c . <<<"$CALLS"); if [ "$n" -eq "$2" ]; then ok "$1"; else bad "$1 (expected $2 connect calls, got $n)"; fi; }

watch ok 2
if grep -qE "lid closed|locked, idle" <<<"$LOG"; then
  # CI sets SK_TESTS_NO_SKIP so that a skipped run can never look like a pass.
  if [ -n "${SK_TESTS_NO_SKIP:-}" ]; then echo "FAIL: watcher is idle (lid closed or locked) and SK_TESTS_NO_SKIP is set"; exit 1; fi
  echo "SKIP: the lid is closed or the session is locked, the watcher is correctly idle."; exit 0
fi

echo "already connected"
has    "logs ok"                         " ok"
echo "auto device picks the first listed"
if [ "$(head -1 <<<"$CALLS")" = "Other iPad" ]; then ok "connects to first device"; else bad "connects to first device"; fi

echo "device name matching"
watch ok 2 --device "joe's ipad"
if [ "$(head -1 <<<"$CALLS")" = $'Joe\xe2\x80\x99s iPad' ]; then ok "case and apostrophe insensitive, real name passed on"; else bad "case and apostrophe insensitive"; fi
watch ok 2 --device "Nope"
has    "unknown device stays idle"        "Nope not reachable, idle"
ncalls "unknown device never connects"    0

echo "reconnect"
watch new 2
has    "logs reconnect"                   "reconnected Other iPad"

echo "no devices at all"
watch none 2
has    "idle when nothing reachable"      "device not reachable, idle"
ncalls "no connect attempted"             0

echo "failure backoff (each failed connect is a user-visible notification)"
watch fail 4
has    "first failure waits 30s"          "(retry in 30s)"
has    "hints at a locked iPad"           "[is the iPad unlocked?]"
ncalls "only one attempt in 4s"           1
watch vd 4
has    "display errors wait 5 min"        "(retry in 300s)"
ncalls "only one attempt in 4s"           1
watch trap 3
hasnt  "'not connected' is not success"   "reconnected"

echo "hung launcher"
watch hang 4 --timeout 1
has    "times out instead of wedging"     "fail: timeout after 1s"

watch hangdevices 6 --timeout 1
n=$(grep -c . "$WORK/probes" 2>/dev/null || true)
if [ "$n" -eq 1 ]; then ok "a hung devices call backs off instead of blocking every tick"; else bad "a hung devices call backs off (devices was called $n times in 6s)"; fi

echo "no leak when a launcher child keeps the pipe open"
echo leaky > "$WORK/mode"; rm -f "$WORK/log"
"$BIN" --launcher "$WORK/SidecarLauncher" --log "$WORK/log" --interval 1 --timeout 1 --settle 0 & pid=$!
# Thread and fd counts before and after the timed-out call is abandoned: the output reader
# must not strand a thread or a descriptor waiting for an EOF that never comes.
count() { wc -l | tr -d ' '; }
sleep 3; t1=$(ps -M "$pid" | count); f1=$(lsof -p "$pid" 2>/dev/null | count)
sleep 4; t2=$(ps -M "$pid" | count); f2=$(lsof -p "$pid" 2>/dev/null | count)
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pkill -f "sleep 20" 2>/dev/null
LOG="$(cat "$WORK/log")"; CALLS=""
if [ "$t2" -le "$t1" ] && [ "$f2" -le "$f1" ]; then ok "threads $t1->$t2, fds $f1->$f2"; else bad "threads $t1->$t2, fds $f1->$f2 grew"; fi

echo "missing launcher"
echo ok > "$WORK/mode"; rm -f "$WORK/log"
"$BIN" --launcher "$WORK/nope" --log "$WORK/log" --interval 1 & pid=$!; sleep 3; kill $pid; wait $pid 2>/dev/null
LOG="$(cat "$WORK/log")"; CALLS=""
has    "reports the bad path"             "cannot run launcher $WORK/nope"
if [ "$(grep -c "cannot run" <<<"$LOG")" -eq 1 ]; then ok "logged once, not every tick"; else bad "logged once, not every tick"; fi

echo "pause / resume"
"$BIN" pause >/dev/null
watch new 2
has    "paused watcher is idle"           "paused, idle"
ncalls "paused watcher never connects"    0
if "$BIN" status --log "$WORK/log" | grep -q "paused: yes"; then ok "status shows paused"; else bad "status shows paused"; fi
"$BIN" resume >/dev/null
watch new 2
has    "resumed watcher reconnects"       "reconnected"

echo "wired mode"
plug; watch new 2
if grep -q -- "-wired" <<<"$ARGV"; then bad "normal mode never passes -wired"; else ok "normal mode never passes -wired"; fi
unplug; watch new 3 --wired
has    "no cable: idle"                   "wired mode: no iPad on USB, idle"
ncalls "no cable: never connects (a wired connect without a cable fails and notifies)" 0
plug; watch new 2 --wired
argv_is "cable present: connects with -wired" "connect Other iPad -wired"
has    "logs a wired reconnect"           "reconnected Other iPad (wired)"
plug; watch ok 3 --wired
if grep -q "^disconnect" <<<"$ARGV"; then bad "healthy session is left alone"; else ok "healthy session is left alone"; fi
unplug; ( sleep 2; plug ) & watch stale 5 --wired
wait
argv_is "replug: dead session is ended and restarted" $'connect Other iPad -wired\ndisconnect Other iPad\nconnect Other iPad -wired'
has    "replug is logged"                 "cable is back, restarting the wired session"
has    "replug ends connected"            "reconnected Other iPad (wired)"
unplug; watch new 2 --wired --usb-match "keyboard"
argv_is "--usb-match picks the product name, ignoring case" "connect Other iPad -wired"
plug

echo "status finds whichever agent is loaded"
LOG=""; CALLS=""
out="$(SIDECARKEEPER_AGENT_LABELS="com.example.definitely-not-loaded" "$BIN" status --log "$WORK/log")"
if grep -q "^agent:  not loaded$" <<<"$out"; then ok "no agent: not loaded"; else bad "no agent: not loaded (got: $(head -1 <<<"$out"))"; fi
# Any agent that is really loaded in this session stands in for ours.
some="$(launchctl list 2>/dev/null | awk 'NR>1 && $3 ~ /^com\.apple\.[A-Za-z0-9.]+$/ {print $3; exit}')"
if [ -n "$some" ] && launchctl print "gui/$(id -u)/$some" 2>/dev/null | grep -q "state ="; then
  out="$(SIDECARKEEPER_AGENT_LABELS="com.example.nope,$some" "$BIN" status --log "$WORK/log")"
  if grep -qF "($some)" <<<"$(head -1 <<<"$out")"; then ok "finds an agent under a later label, and names it"; else bad "finds an agent under a later label (got: $(head -1 <<<"$out"))"; fi
else
  echo "  note: no loaded agent to stand in, skipped one status check"
fi

echo "argument errors"
LOG=""; CALLS=""
for args in "--bogus" "--interval 0" "--interval inf" "--timeout 1e30" "--settle nan" "--device" "frobnicate"; do
  # shellcheck disable=SC2086
  "$BIN" $args >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then ok "rejects: $args"; else bad "rejects: $args (exit $rc)"; fi
done

echo "log file handling"
echo ok > "$WORK/mode"
"$BIN" --launcher "$WORK/SidecarLauncher" --log "$WORK/new/sub/dir/w.log" --interval 1 & pid=$!; sleep 2; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
LOG="$(cat "$WORK/new/sub/dir/w.log" 2>/dev/null)"
has    "creates missing log directories"  "started"
mkdir -p "$WORK/ro"; chmod 555 "$WORK/ro"
"$BIN" --launcher "$WORK/SidecarLauncher" --log "$WORK/ro/w.log" --interval 1 >/dev/null 2>"$WORK/err" & pid=$!
sleep 2; if kill -0 "$pid" 2>/dev/null; then kill "$pid"; wait "$pid" 2>/dev/null; rc=running; else wait "$pid"; rc=$?; fi
LOG="$(cat "$WORK/err")"; chmod 755 "$WORK/ro"
if [ "$rc" = 1 ]; then ok "unwritable log exits 1 instead of running blind"; else bad "unwritable log exits 1 (got: $rc)"; fi
has    "and says why on stderr"           "cannot write log file"

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
