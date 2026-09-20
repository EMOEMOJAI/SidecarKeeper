#!/bin/bash
# Behaviour tests for sidecar-keeper using a fake SidecarLauncher. No iPad is touched.
#   tests/run.sh [path-to-sidecar-keeper]
# The watcher's real gates still apply, so run with the screen unlocked and the lid open.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/build/sidecar-keeper}"
TMP="${TMPDIR:-/tmp}"; WORK="$(mktemp -d "${TMP%/}/sk-tests.XXXXXX")"
cleanup_leaky_child() {
  if [ -f "$WORK/leaky-child" ]; then
    kill -KILL "$(cat "$WORK/leaky-child")" 2>/dev/null || true
    rm -f "$WORK/leaky-child"
  fi
}
trap 'cleanup_leaky_child; rm -rf "$WORK"' EXIT
cp "$ROOT/tests/fake-launcher.sh" "$WORK/SidecarLauncher"; chmod +x "$WORK/SidecarLauncher"
export SIDECARKEEPER_STATE_DIR="$WORK/state"
# Fake USB bus: the watcher reads this script's output instead of calling ioreg.
printf '#!/bin/bash\ncat "%s/usb" 2>/dev/null\n' "$WORK" > "$WORK/usb-probe"; chmod +x "$WORK/usb-probe"
export SIDECARKEEPER_USB_PROBE="$WORK/usb-probe"
plug()   { echo '    "USB Product Name" = "iPad"' > "$WORK/usb"; }
unplug() { echo '    "USB Product Name" = "Some Keyboard"' > "$WORK/usb"; }
PASS=0; FAIL=0
status() { SIDECARKEEPER_AGENT_LABELS="com.example.definitely-not-loaded" "$BIN" status --log "$WORK/log"; }

# watch MODE SECONDS [watcher args...] -> captures status while alive, then stops the watcher.
watch() {
  local mode="$1" secs="$2"; shift 2
  echo "$mode" > "$WORK/mode"; rm -f "$WORK/calls" "$WORK/argv" "$WORK/probes" "$WORK/disconnected" "$WORK/log"
  "$BIN" --launcher "$WORK/SidecarLauncher" --log "$WORK/log" --interval 1 "$@" &
  local pid=$! attempt; sleep "$secs"
  # A poll may be in flight at the sampling instant; allow its bounded fake probe to finish.
  for ((attempt=0; attempt<20; attempt++)); do
    STATUS="$(status)"
    if ! grep -qE '^watcher: (checking device availability|connecting |disconnecting )' <<<"$STATUS"; then break; fi
    sleep 0.1
  done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  LOG="$(cat "$WORK/log" 2>/dev/null)"; CALLS="$(cat "$WORK/calls" 2>/dev/null)"; ARGV="$(cat "$WORK/argv" 2>/dev/null)"
}
# The launcher's first commands must be exactly $2 (later ticks may repeat the connect).
argv_is() { local n; n=$(grep -c . <<<"$2"); if [ "$(head -n "$n" <<<"$ARGV")" = "$2" ]; then ok "$1"; else bad "$1 (launcher commands were: ${ARGV//$'\n'/ ; })"; fi; }
ok()   { PASS=$((PASS+1)); echo "  pass: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "    log:   ${LOG//$'\n'/$'\n'           }"; echo "    calls: $CALLS"; }
has()  { if grep -qF -- "$2" <<<"$LOG"; then ok "$1"; else bad "$1 (log lacks: $2)"; fi; }
hasnt(){ if grep -qF -- "$2" <<<"$LOG"; then bad "$1 (log has: $2)"; else ok "$1"; fi; }
ncalls(){ local n; n=$(grep -c . <<<"$CALLS"); if [ "$n" -eq "$2" ]; then ok "$1"; else bad "$1 (expected $2 connect calls, got $n)"; fi; }
status_has() { if grep -qF -- "$2" <<<"$STATUS"; then ok "$1"; else bad "$1 (status lacks: $2; got: $STATUS)"; fi; }

# These checks remain useful with a locked screen: none requires a connect to succeed.
echo "timed pause and live status"
LOG=""; CALLS=""; STATUS="$(status)"
status_has "missing snapshot is unavailable" "watcher: unavailable"
"$BIN" pause --for 1h >/dev/null
watch new 1
status_has "timed pause has an expiry" "paused: yes (until "
status_has "watcher reports paused" "watcher: paused"
ncalls "timed pause prevents connect" 0
STATUS="$(status)"; status_has "stopped watcher is stale" "watcher: stale"
watch new 1
status_has "timed pause survives watcher restart" "watcher: paused"
ncalls "restart does not bypass timed pause" 0
saved_pause="$(cat "$SIDECARKEEPER_STATE_DIR/paused")"
for duration in 0s -1h nanh infs 1e300d 366d 10 1w; do
  "$BIN" pause --for "$duration" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ] && [ "$(cat "$SIDECARKEEPER_STATE_DIR/paused")" = "$saved_pause" ]; then
    ok "invalid duration leaves pause intact: $duration"
  else bad "invalid duration leaves pause intact: $duration"; fi
done
for args in '--for' '--bogus' '--for 1h extra'; do
  # shellcheck disable=SC2086
  "$BIN" pause $args >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then ok "rejects pause arguments: $args"; else bad "rejects pause arguments: $args"; fi
done
for duration in 30s 15m 1.5h 1d; do
  if "$BIN" pause --for "$duration" >/dev/null; then ok "accepts duration: $duration"; else bad "accepts duration: $duration"; fi
done
"$BIN" resume >/dev/null
STATUS="$(status)"; status_has "resume ends a timed pause early" "paused: no"
"$BIN" pause --for 1h >/dev/null; "$BIN" pause >/dev/null
STATUS="$(status)"; status_has "plain pause replaces a timer" "paused: yes (until resumed)"
printf 'broken expiry\n' > "$SIDECARKEEPER_STATE_DIR/paused"
watch new 1
status_has "damaged pause remains paused" "watcher: paused"
ncalls "damaged pause never connects" 0
rm -f "$SIDECARKEEPER_STATE_DIR/paused"
ln -s "$WORK/missing-pause" "$SIDECARKEEPER_STATE_DIR/paused"
watch new 1
status_has "broken pause symlink remains paused" "watcher: paused"
ncalls "broken pause symlink never connects" 0
"$BIN" resume >/dev/null; "$BIN" pause >/dev/null

# A fresh PID alone is insufficient: reject expired snapshots and a mismatched process start.
echo new > "$WORK/mode"
"$BIN" --launcher "$WORK/SidecarLauncher" --log "$WORK/log" --interval 60 & pid=$!
sleep 1
cp "$SIDECARKEEPER_STATE_DIR/status.json" "$WORK/snapshot"
python3 - "$SIDECARKEEPER_STATE_DIR/status.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); data = json.loads(p.read_text())
data['retryAt'] = 1e300
p.write_text(json.dumps(data))
PY
STATUS="$(status)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "out-of-range status date does not crash"; else bad "out-of-range status date does not crash"; fi
status_has "out-of-range status date is unavailable" "watcher: unavailable"
cp "$WORK/snapshot" "$SIDECARKEEPER_STATE_DIR/status.json"
python3 - "$SIDECARKEEPER_STATE_DIR/status.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); data = json.loads(p.read_text())
data['freshUntil'] = 0
p.write_text(json.dumps(data))
PY
STATUS="$(status)"; status_has "expired snapshot is stale even with a live PID" "watcher: stale"
cp "$WORK/snapshot" "$SIDECARKEEPER_STATE_DIR/status.json"
python3 - "$SIDECARKEEPER_STATE_DIR/status.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); data = json.loads(p.read_text())
data['processStart'] = 'a different process'
p.write_text(json.dumps(data))
PY
STATUS="$(status)"; status_has "reused PID cannot make an old snapshot live" "watcher: stale"
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
printf 'invalid json\n' > "$SIDECARKEEPER_STATE_DIR/status.json"
STATUS="$(status)"; status_has "damaged snapshot is unavailable" "watcher: unavailable"
rm -f "$SIDECARKEEPER_STATE_DIR/status.json"

unplug; "$BIN" pause --for 2s >/dev/null
watch new 3 --wired
status_has "timed pause expires automatically" "paused: no"
ncalls "expiry cannot bypass connection gates" 0
printf 'unknown = value\n' > "$SIDECARKEEPER_STATE_DIR/config"
watch new 1
status_has "settings error is visible in live status" "watcher: settings file error"
ncalls "expired pause cannot bypass invalid settings" 0
rm -f "$SIDECARKEEPER_STATE_DIR/config"
"$BIN" resume >/dev/null

echo "broken settings symlink"
mkdir -p "$SIDECARKEEPER_STATE_DIR"
ln -s "$WORK/missing-settings" "$SIDECARKEEPER_STATE_DIR/config"
watch new 2
has "broken settings symlink is reported" "cannot read settings:"
ncalls "broken settings symlink never connects" 0
"$BIN" config > "$WORK/config-output"; rc=$?
if [ "$rc" -eq 1 ]; then ok "config rejects broken settings symlink"; else bad "config rejects broken settings symlink (exit $rc)"; fi
rm -f "$SIDECARKEEPER_STATE_DIR/config"

watch ok 2
if grep -qE "lid closed|locked, idle" <<<"$LOG"; then
  if grep -q 'locked, idle' <<<"$LOG"; then status_has "live status reports the locked gate" "watcher: locked"
  else status_has "live status reports the lid gate" "watcher: lid closed"; fi
  # CI sets SK_TESTS_NO_SKIP so that a skipped run can never look like a pass.
  if [ -n "${SK_TESTS_NO_SKIP:-}" ]; then echo "FAIL: watcher is idle (lid closed or locked) and SK_TESTS_NO_SKIP is set"; exit 1; fi
  echo "$PASS passed, $FAIL failed; remaining tests SKIP: lid closed or session locked."
  [ "$FAIL" -eq 0 ]; exit $?
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
status_has "live status reports successful connection" "watcher: connected to Other iPad"
if grep -qE '^last reconnect: [0-9].*\(Other iPad\)$' <<<"$STATUS"; then ok "records last reconnection and iPad"; else bad "records last reconnection and iPad"; fi
last_reconnect="$(grep '^last reconnect:' <<<"$STATUS")"
watch ok 2
if [ "$(grep '^last reconnect:' <<<"$STATUS")" = "$last_reconnect" ]; then ok "already-connected checks and restart preserve last reconnection"; else bad "already-connected checks and restart preserve last reconnection"; fi

"$BIN" pause --for 2s >/dev/null; watch new 4
has "expired pause reconnects automatically when eligible" "reconnected Other iPad"

echo "no devices at all"
watch none 2
has    "idle when nothing reachable"      "device not reachable, idle"
ncalls "no connect attempted"             0
status_has "live status explains device absence" "watcher: device not reachable"

echo "failure backoff (each failed connect is a user-visible notification)"
watch fail 4
has    "first failure waits 30s"          "(retry in 30s)"
has    "hints at a locked iPad"           "[is the iPad unlocked?]"
ncalls "only one attempt in 4s"           1
if grep -qE '^watcher: waiting to retry connection \(eligible in [0-9]+s\)' <<<"$STATUS"; then ok "live status shows retry countdown"; else bad "live status shows retry countdown"; fi
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
# Once the call times out, pause polling so an in-flight ioreg probe cannot look like a leak.
# The child still holds stdout open, but the watcher must have closed its end of that pipe.
count() { wc -l | tr -d ' '; }
pipe_count() { lsof -a -p "$pid" -d '^0,1,2' -F t 2>/dev/null | grep -c '^tPIPE$'; }
sleep 3; "$BIN" pause >/dev/null; sleep 2
t1=$(ps -M "$pid" | count); f1=$(pipe_count)
sleep 4; t2=$(ps -M "$pid" | count); f2=$(pipe_count)
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; cleanup_leaky_child
"$BIN" resume >/dev/null
LOG="$(cat "$WORK/log")"; CALLS=""
# Ignore inherited stdin/stdout/stderr. The thread pool may add or drop one worker.
if [ "$f1" -eq 0 ] && [ "$f2" -eq 0 ] && [ "$t2" -le $((t1 + 1)) ]; then ok "threads $t1->$t2, child pipes $f1->$f2"; else bad "threads $t1->$t2, child pipes $f1->$f2 leaked"; fi

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
status_has "live status explains missing cable" "watcher: waiting for USB cable"
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

echo "settings file"
CFG="$SIDECARKEEPER_STATE_DIR/config"; mkdir -p "$SIDECARKEEPER_STATE_DIR"
printf '# a comment\n\ndevice = Nope\n' > "$CFG"; watch new 2
has    "device comes from the file"        "Nope not reachable, idle"
ncalls "and nothing else is connected"     0
watch new 2 --device "other ipad"
has    "a command-line flag wins over the file" "reconnected Other iPad"
printf 'wired = true\ninterval = 1\n' > "$CFG"; plug; watch new 2
argv_is "wired = true in the file connects with -wired" "connect Other iPad -wired"
printf 'device = "Joe\x27s iPad"\n' > "$CFG"; watch ok 2
if [ "$(head -1 <<<"$CALLS")" = $'Joe\xe2\x80\x99s iPad' ]; then ok "quoted value with an apostrophe"; else bad "quoted value with an apostrophe"; fi
printf 'device = Other iPad\nspeed = fast\n' > "$CFG"; watch new 3
has    "a mistake in the file is reported with its line" "settings file error (line 2: unknown setting"
ncalls "and the watcher stays idle instead of guessing" 0
printf 'interval = soon\n' > "$CFG"; watch new 2
has    "a bad number is reported, not fatal"  "settings file error (line 1: interval must be"
printf 'device = \xff\n' > "$CFG"; watch new 2
has    "invalid UTF-8 is reported"         "cannot read settings:"
ncalls "invalid UTF-8 never connects"      0
"$BIN" config > "$WORK/config-output"; rc=$?
if [ "$rc" -eq 1 ]; then ok "config rejects unreadable settings"; else bad "config rejects unreadable settings (exit $rc)"; fi
printf 'device = Nope\n' > "$CFG"; chmod 000 "$CFG"; watch new 2
chmod 600 "$CFG"
has    "unreadable permissions are reported" "cannot read settings:"
ncalls "unreadable settings never connect" 0
out="$("$BIN" config)"
if grep -q '^file settings: --device Nope$' <<<"$out" && grep -q 'Command-line flags override' <<<"$out"; then
  ok "config describes file settings and flag precedence"
else bad "config describes file settings and flag precedence"; fi
rm -f "$CFG"; LOG=""; CALLS=""
if "$BIN" config --init >/dev/null && [ -s "$CFG" ]; then ok "config --init writes a template"; else bad "config --init writes a template"; fi
if grep -qvE '^(#.*)?$' "$CFG"; then bad "the template sets nothing by itself"; else ok "the template sets nothing by itself"; fi
"$BIN" config --init >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "config --init never overwrites"; else bad "config --init never overwrites (exit $rc)"; fi
rm -f "$CFG"

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
