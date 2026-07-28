#!/usr/bin/env bash
# Clone crazyswarm2 + motion_capture_tracking and apply the patches in patches/.
# Idempotent: re-running resets both checkouts to the pinned commit and reapplies.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

CRAZYSWARM2_SHA=f6154e2d51791a41e6f320c1ee166f782be02a20
MCT_SHA=64d3af2456e534cd5e587b98ef2f15dd8ad35e8c

mkdir -p src

clone_or_reset() {
  local dir="$1" url="$2" sha="$3" recursive="$4"
  if [ -d "$dir/.git" ]; then
    echo "resetting $dir to $sha"
    git -C "$dir" fetch --quiet origin
    git -C "$dir" checkout --quiet --force "$sha"
    git -C "$dir" clean -qfd
    [ "$recursive" = "yes" ] && git -C "$dir" submodule update --quiet --init --recursive
  else
    echo "cloning $url"
    if [ "$recursive" = "yes" ]; then
      git clone --quiet --recursive "$url" "$dir"
    else
      git clone --quiet "$url" "$dir"
    fi
    git -C "$dir" checkout --quiet "$sha"
    [ "$recursive" = "yes" ] && git -C "$dir" submodule update --quiet --init --recursive
  fi
  return 0
}

clone_or_reset src/crazyswarm2 https://github.com/IMRCLab/crazyswarm2.git "$CRAZYSWARM2_SHA" yes
clone_or_reset src/motion_capture_tracking https://github.com/IMRCLab/motion_capture_tracking.git "$MCT_SHA" no

echo
echo "applying patches"
for p in "$ROOT"/patches/000[1-4]-*.patch; do
  echo "  $(basename "$p")"
  git -C src/crazyswarm2 apply "$p"
done
for p in "$ROOT"/patches/0005-*.patch; do
  echo "  $(basename "$p")"
  git -C src/motion_capture_tracking apply "$p"
done

echo
echo "Done. Next: pixi install"
