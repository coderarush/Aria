#!/bin/bash
# Aria headless smoke test — drives the REAL app through its debug hooks and
# asserts on /tmp/aria.log. Runs in ARIA_DEMO_MODE: deterministic scripted
# replies, zero network/quota dependence — the same engine, UI, voice and
# capture pipeline, only the model is scripted. Catches the failure classes
# unit tests can't: dead capture, hung turns, broken re-arm, startup hangs.
set -u
APP="${1:-.build/Aria.app}"
LOG=/tmp/aria.log
PASS=0; FAIL=0
OFFSET=0

mark() { OFFSET=$(wc -l < "$LOG" 2>/dev/null || echo 0); }
since() { tail -n +"$((OFFSET + 1))" "$LOG" 2>/dev/null; }

await_log() { # await_log <timeout-s> <regex>  — only matches lines after mark()
  local deadline=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if since | grep -qE "$2"; then return 0; fi
    sleep 2
  done
  return 1
}

post() { # post <name> [object]
  swift - "$@" <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(args[1]), object: args.count > 2 ? args[2] : nil,
    userInfo: nil, deliverImmediately: true)
SWIFT
}

check() {
  if [ "$2" -eq 0 ]; then echo "  PASS  $1"; PASS=$((PASS+1));
  else echo "  FAIL  $1"; FAIL=$((FAIL+1)); fi
}

echo "== Aria smoke (demo mode) =="
defaults write com.aria.agent app.debugHooks -bool true
pkill -x Aria 2>/dev/null; sleep 1
mark
ARIA_DEMO_MODE=1 "$APP/Contents/MacOS/Aria" >/dev/null 2>&1 &
APP_PID=$!

await_log 30 "debug hooks ON"; check "startup → hooks live (<30s)" $?
await_log 30 "audio bus \+ wake engine started OK"; check "audio + wake pipeline up" $?

mark
post aria.debug.summon
await_log 15 "summon — push-to-talk wake"; check "summon wakes" $?
await_log 20 "finishCommand"; check "capture cycle completes (silence grace)" $?
await_log 30 "island hidden → wake re-armed"; check "re-arms after empty capture" $?

mark
post aria.debug.say "tell me a joke"
await_log 15 "turn: streaming"; check "turn 1 reaches model" $?
await_log 60 "island hidden → wake re-armed"; check "turn 1 completes + re-arms" $?

mark
post aria.debug.say "what's on my calendar"
await_log 15 "turn: streaming"; check "turn 2 reaches model (no dead session)" $?
await_log 60 "island hidden → wake re-armed"; check "turn 2 completes + re-arms" $?

kill -0 "$APP_PID" 2>/dev/null; check "app still alive" $?

echo "== $PASS passed, $FAIL failed =="
kill "$APP_PID" 2>/dev/null
[ "$FAIL" -eq 0 ]
