#!/usr/bin/env bash
# Атомарная выкладка собранного сайта на сервер.
#   deploy/publish.sh <папка-сборки> <user@host> <имя-релиза>
# Каждый релиз — отдельная папка в /var/www/site/releases, «current» — симлинк
# на активный. Переключение мгновенное, откат — rollback.sh на сервере.
set -euo pipefail

SRC=${1:?папка сборки}
DEST=${2:?user@host}
RELEASE=${3:-$(date +%Y%m%d%H%M%S)}
ROOT=/var/www/site
KEEP=5

RSH=${RSYNC_RSH:-ssh}

# Неизменённые файлы берутся жёсткими ссылками из текущего релиза — быстро и без лишнего места.
rsync -rlz --checksum --delete \
  --link-dest="$ROOT/current/" \
  "$SRC/" "$DEST:$ROOT/releases/$RELEASE/"

$RSH "$DEST" bash -s -- "$ROOT" "$RELEASE" "$KEEP" <<'REMOTE'
set -euo pipefail
ROOT=$1 RELEASE=$2 KEEP=$3
ln -sfn "releases/$RELEASE" "$ROOT/current.tmp"
mv -Tf "$ROOT/current.tmp" "$ROOT/current"
cd "$ROOT/releases"
ls -1t | tail -n +$((KEEP + 1)) | xargs -r rm -rf --
echo "Активный релиз: $RELEASE"
REMOTE
