#!/bin/bash
# activate_release.sh - runs ON the app server (as deploy) via: ssh ... bash -s -- <site_root> <release> [keep]
# Atomically switches the 'current' symlink to the new release, then prunes old releases.
set -euo pipefail

SITE_ROOT="$1"
RELEASE="$2"
KEEP="${3:-5}"

cd "$SITE_ROOT"
[ -s "releases/$RELEASE/index.html" ] || { echo "release $RELEASE is incomplete (no index.html)"; exit 1; }

previous=$(basename "$(readlink current 2>/dev/null || echo none)")

# Atomic switch: build the new link beside 'current', then rename over it.
ln -sfn "$SITE_ROOT/releases/$RELEASE" current.next
mv -T current.next current

echo "previous release: $previous"
echo "active release:   $(basename "$(readlink current)")"

# Keep the newest $KEEP releases; never delete the active one.
active=$(basename "$(readlink current)")
ls -1 releases | sort | head -n -"$KEEP" | while read -r old; do
  [ "$old" = "$active" ] && continue
  rm -rf "releases/$old"
  echo "pruned:           $old"
done
