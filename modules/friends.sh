#!/usr/bin/env bash
# server-kit: установка модуля управления друзьями kit-friend (AmneziaWG)
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf
export DEBIAN_FRONTEND=noninteractive

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log "Установка модуля друзей (kit-friend)..."

# Установка утилиты генерации QR-кодов
if ! command -v qrencode >/dev/null 2>&1; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y qrencode >/dev/null 2>&1 || true
fi

cp "$SELF_DIR/bin/kit-friend" /usr/local/bin/kit-friend
chmod 755 /usr/local/bin/kit-friend
mkdir -p /var/lib/server-kit/friends

log "Модуль kit-friend установлен!"
log "Команды: kit-friend add <имя> [smart|full] | kit-friend list | kit-friend revoke <имя>"
