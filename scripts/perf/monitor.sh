#!/bin/sh
# monitor.sh <seconds> <app pid>: one line per second with live WindowServer
# CPU%, the app's CPU%, and GPU device utilization.
SECS=$1; APP=$2; WS=$(pgrep -x WindowServer | head -1)
i=0
while [ $i -lt "$SECS" ]; do
  OUT=$(top -l 2 -s 1 -pid "$WS" -pid "$APP" -stats pid,cpu 2>/dev/null | tail -2)
  WSC=$(echo "$OUT" | awk -v p="$WS" '$1==p{print $2}')
  APPC=$(echo "$OUT" | awk -v p="$APP" '$1==p{print $2}')
  GPU=$(ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -oE '"Device Utilization %"=[0-9]+' | head -1 | grep -oE '[0-9]+$')
  printf "t=%02d  WindowServer=%5s%%  app=%5s%%  GPU=%3s%%\n" "$i" "$WSC" "$APPC" "$GPU"
  i=$((i+1))
done
