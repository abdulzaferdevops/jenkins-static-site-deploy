#!/bin/bash
# rollback_release.sh - runs ON the app server (as deploy) via: ssh ... bash -s -- <site_root>
# Switches 'current' back to the release immediately before the active one.
set -euo pipefail

SITE_ROOT="$1"
cd "$SITE_ROOT"

active=$(basename "$(readlink current)")
target=$(ls -1 releases | sort | awk -v a="$active" '$0 == a { print prev; exit } { prev = $0 }')

if [ -z "$target" ]; then
  echo "no earlier release than $active - nothing to roll back to"
  exit 1
fi

ln -sfn "$SITE_ROOT/releases/$target" current.next
mv -T current.next current
echo "rolled back: $active -> $target"
