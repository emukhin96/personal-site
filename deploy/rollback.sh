#!/usr/bin/env bash
# Откат на предыдущий релиз (или на указанный): site-rollback [имя-релиза]
set -euo pipefail
ROOT=/var/www/site
cd "$ROOT/releases"
CURRENT=$(basename "$(readlink "$ROOT/current")")
TARGET=${1:-$(ls -1t | grep -vxF "$CURRENT" | head -n 1)}
[ -d "$TARGET" ] || { echo "Нет релиза $TARGET. Есть: $(ls -1t | tr '\n' ' ')"; exit 1; }
ln -sfn "releases/$TARGET" "$ROOT/current.tmp"
mv -Tf "$ROOT/current.tmp" "$ROOT/current"
echo "Было: $CURRENT → стало: $TARGET"
