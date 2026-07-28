#!/usr/bin/env bash
# Capture everything about the aideck streamer while joined to the deck's AP.
# Run this on the AP, then switch back to your normal network and read /tmp/cfdiag/.
set -u

OUT=/tmp/cfdiag
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$(dirname "$0")/.."

echo "== network ==" | tee "$OUT/summary.txt"
ifconfig en0 | grep "inet " | tee -a "$OUT/summary.txt"

# Deliberately NOT probing the port first: the GAP8 serves a single client, and an
# open-then-close from nc can leave it unwilling to serve the next connection. The
# streamer must be the first thing to touch the socket.

echo "== starting streamer ==" | tee -a "$OUT/summary.txt"
pixi run camera > "$OUT/node.log" 2>&1 &
NODE=$!
sleep 12

echo "== node alive? ==" | tee -a "$OUT/summary.txt"
if kill -0 $NODE 2>/dev/null; then
  echo "yes (pid $NODE)" | tee -a "$OUT/summary.txt"
else
  echo "NO - it exited" | tee -a "$OUT/summary.txt"
fi

echo "== topics ==" | tee -a "$OUT/summary.txt"
pixi run ros2 topic list > "$OUT/topics.txt" 2>&1
cat "$OUT/topics.txt" | tee -a "$OUT/summary.txt"

echo "== publisher count on /camera/image ==" | tee -a "$OUT/summary.txt"
pixi run ros2 topic info /camera/image > "$OUT/topic_info.txt" 2>&1
cat "$OUT/topic_info.txt" | tee -a "$OUT/summary.txt"

echo "== node output so far ==" | tee -a "$OUT/summary.txt"
cat "$OUT/node.log" | tee -a "$OUT/summary.txt"

echo "== encoding ==" | tee -a "$OUT/summary.txt"
# background + kill: `echo --once` blocks forever if nothing is published, and macOS
# has no timeout(1)
pixi run ros2 topic echo /camera/image --once --field encoding > "$OUT/encoding.txt" 2>&1 &
ECHO=$!
sleep 8
kill $ECHO 2>/dev/null; pkill -f "topic echo" 2>/dev/null
cat "$OUT/encoding.txt" | tee -a "$OUT/summary.txt"

echo "== rate (10s) ==" | tee -a "$OUT/summary.txt"
pixi run ros2 topic hz /camera/image > "$OUT/hz.txt" 2>&1 &
HZ=$!
sleep 10
kill $HZ 2>/dev/null; pkill -f "topic hz" 2>/dev/null
tail -3 "$OUT/hz.txt" | tee -a "$OUT/summary.txt"

echo "== tf cf1 -> cf1/camera ==" | tee -a "$OUT/summary.txt"
pixi run ros2 run tf2_ros tf2_echo cf1 cf1/camera > "$OUT/tf.txt" 2>&1 &
TF=$!
sleep 6
kill $TF 2>/dev/null; pkill -f tf2_echo 2>/dev/null
tail -8 "$OUT/tf.txt" | tee -a "$OUT/summary.txt"

echo "== node output ==" | tee -a "$OUT/summary.txt"
cat "$OUT/node.log" | tee -a "$OUT/summary.txt"

kill $NODE 2>/dev/null; pkill -f aideck_streamer 2>/dev/null

echo
echo "Done. Everything is in $OUT/ - summary.txt has it all."
