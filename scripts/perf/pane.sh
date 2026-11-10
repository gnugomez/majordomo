#!/bin/sh
# pane.sh <tag>: launches the Reviews demo with the preview placed under
# the board, selects a card with the arrows, opens the preview with Space,
# and screenshots the window several times through the pane's slide.
TAG=$1
S=$(cd "$(dirname "$0")" && pwd)
cd "$S" || exit 1
defaults write Majordomo sidebarBoard starter-reviews
defaults write Majordomo boardPreviewPlacement bottom
MAJORDOMO_DEMO=1 MAJORDOMO_OPEN_MAIN=1 MAJORDOMO_DEMO_SCALE=30 "$S/../../.build/release/Majordomo" >"demo-$TAG.log" 2>&1 &
PID=$!
WID=""
for i in $(seq 1 40); do sleep 0.5; WID=$(./winfo "$PID" 2>/dev/null | awk '/id=/{for(i=1;i<=NF;i++) if($i ~ /^id=/){sub("id=","",$i); print $i; exit}}'); [ -n "$WID" ] && break; done
[ -z "$WID" ] && { echo "no window"; kill "$PID"; exit 1; }
sleep 3; ./axwin "$PID" 2215 60 790 1550; sleep 1.5
WID=$(./winfo "$PID" | awk '/id=/{for(i=1;i<=NF;i++) if($i ~ /^id=/){sub("id=","",$i); print $i; exit}}')
./hidkeys "$PID" 125 1 120
sleep 1
screencapture -x -l"$WID" "$TAG-before.png"
# Space opens the preview; the shots follow at once, through the slide.
./hidkeys "$PID" 49 1 0 & KEYPID=$!
for i in 1 2 3 4 5 6 7 8; do
  screencapture -x -l"$WID" "$TAG-s$i.png"
done
wait $KEYPID
sleep 1
screencapture -x -l"$WID" "$TAG-after.png"
for f in before s1 s2 s3 s4 s5 s6 s7 s8 after; do sips -Z 700 "$TAG-$f.png" --out "$TAG-$f-small.png" >/dev/null; done
kill "$PID"
echo done
