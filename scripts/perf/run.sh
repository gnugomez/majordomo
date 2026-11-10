#!/bin/sh
# run.sh <tag> <board-id>: launches the scaled demo on a board, parks its
# window on the 6K display, wheel-scrolls it for 7 s while counting the
# window's updates, CPU, and the main thread, then quits it.
set -u
TAG=$1; BOARD=$2
S=$(cd "$(dirname "$0")" && pwd)
cd "$S" || exit 1
defaults write Majordomo sidebarBoard "$BOARD"
MAJORDOMO_DEMO=1 MAJORDOMO_OPEN_MAIN=1 MAJORDOMO_DEMO_SCALE=30 \
  "$S/../../.build/release/Majordomo" >"demo-$TAG.log" 2>&1 &
PID=$!
echo "pid $PID"
WID=""
for i in $(seq 1 40); do
  sleep 0.5
  WID=$(./winfo "$PID" 2>/dev/null | awk '/id=/{for(i=1;i<=NF;i++) if($i ~ /^id=/){sub("id=","",$i); print $i; exit}}')
  [ -n "$WID" ] && break
done
if [ -z "$WID" ]; then echo "no window"; kill "$PID"; exit 1; fi
sleep 2
./axwin "$PID" 2215 60 790 1550
sleep 1.5
WID=$(./winfo "$PID" | awk '/id=/{for(i=1;i<=NF;i++) if($i ~ /^id=/){sub("id=","",$i); print $i; exit}}')
echo "window $WID"; ./winfo "$PID"; ./front 2600 900 | head -3
screencapture -x -l"$WID" "$TAG-0.png"
./fpscount "$WID" 11 >"fps-$TAG.txt" 2>&1 & FPSPID=$!
./monitor.sh 11 "$PID" >"mon-$TAG.txt" 2>&1 & MONPID=$!
sleep 1
( sleep 1; sample "$PID" 5 -mayDie -file "s-$TAG.txt" >/dev/null 2>&1 ) & SAMPID=$!
./hidscroll 2600 900 v 7 8 165 >"hid-$TAG.log" 2>&1
wait $FPSPID $MONPID $SAMPID
screencapture -x -l"$WID" "$TAG-1.png"
echo "== fps"; cat "fps-$TAG.txt" | tr '\n' ' '; echo
echo "== mon"; cat "mon-$TAG.txt"
awk '/DispatchQueue_1: com.apple.main-thread/{f=1} f&&/NSEventThread/{exit} f' "s-$TAG.txt" >"s-$TAG.main.txt"
echo "== main thread: $(sed 's/^[ +!:|]*//' "s-$TAG.main.txt" | awk 'NR==1{t=$1} /__CFRunLoopServiceMachPort/{i+=$1} END{print "samples", t, "idle", i}')"
kill "$PID"
