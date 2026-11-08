#!/usr/bin/env bash
# Разовая настройка чистого VPS (Debian/Ubuntu) под сайт. Запускать от root:
#   bash setup-server.sh example.com "ssh-ed25519 AAAA… github-deploy"
# Ставит Caddy, создаёт пользователя deploy с доступом только к /var/www/site.
set -euo pipefail

DOMAIN=${1:?домен, например example.com}
DEPLOY_KEY=${2:?публичный SSH-ключ для GitHub Actions}

apt-get update
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg rsync
if ! command -v caddy >/dev/null; then
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

id deploy >/dev/null 2>&1 || useradd --create-home --shell /bin/bash deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
grep -qxF "$DEPLOY_KEY" /home/deploy/.ssh/authorized_keys 2>/dev/null \
  || echo "$DEPLOY_KEY" >> /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

install -d -o deploy -g deploy /var/www/site /var/www/site/releases
if [ ! -e /var/www/site/current ]; then
  install -d -o deploy -g deploy /var/www/site/releases/initial
  echo '<!doctype html><meta charset="utf-8"><title>Скоро</title><p>Сайт скоро появится.' \
    > /var/www/site/releases/initial/index.html
  chown deploy:deploy /var/www/site/releases/initial/index.html
  ln -sfn releases/initial /var/www/site/current
  chown -h deploy:deploy /var/www/site/current
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
sed "s/example\.com/$DOMAIN/g" "$SCRIPT_DIR/Caddyfile" > /etc/caddy/Caddyfile
install -m 755 "$SCRIPT_DIR/rollback.sh" /usr/local/bin/site-rollback
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy

echo
echo "Готово. Для секрета DEPLOY_KNOWN_HOSTS выполните на своём компьютере:"
echo "  ssh-keyscan -t ed25519 $(hostname -I | awk '{print $1}')"
