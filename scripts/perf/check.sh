#!/bin/sh
# check.sh <tag>: launches the scaled demo on Reviews (lanes off), parks
# it, wheel-scrolls a column to its foot and screenshots it, scrolls back,
# then walks the arrows down the column and screenshots where the
# selection ends up.
TAG=$1
S=$(cd "$(dirname "$0")" && pwd)
cd "$S" || exit 1
defaults write Majordomo sidebarBoard starter-reviews
MAJORDOMO_DEMO=1 MAJORDOMO_OPEN_MAIN=1 MAJORDOMO_DEMO_SCALE=30 "$S/../../.build/release/Majordomo" >"demo-$TAG.log" 2>&1 &
PID=$!
WID=""
for i in $(seq 1 40); do sleep 0.5; WID=$(./winfo "$PID" 2>/dev/null | awk '/id=/{for(i=1;i<=NF;i++) if($i ~ /^id=/){sub("id=","",$i); print $i; exit}}'); [ -n "$WID" ] && break; done
[ -z "$WID" ] && { echo "no window"; kill "$PID"; exit 1; }
sleep 3; ./axwin "$PID" 2215 60 790 1550; sleep 1.5
WID=$(./winfo "$PID" | awk '/id=/{for(i=1;i<=NF;i++) if($i ~ /^id=/){sub("id=","",$i); print $i; exit}}')
./front 2600 900 | head -1
shot() { screencapture -x -l"$WID" "$TAG-$1.png"; sips -Z 900 "$TAG-$1.png" --out "$TAG-$1-small.png" >/dev/null; }
# Down, five short runs: the first second of a run goes up, so a negative step goes down.
for i in 1 2 3 4 5; do ./hidscroll 2600 900 v 0.9 -8 165 >/dev/null 2>&1; done
sleep 1; shot foot
for i in 1 2 3 4 5; do ./hidscroll 2600 900 v 0.9 8 165 >/dev/null 2>&1; done
sleep 1; shot top
./hidkeys "$PID" 125 1 120; ./hidkeys "$PID" 124 1 120; ./hidkeys "$PID" 125 14 120
sleep 1; shot keys14
./hidkeys "$PID" 125 12 120
sleep 1; shot keys26
./hidkeys "$PID" 126 20 120
sleep 1; shot keysup
kill "$PID"
echo done
