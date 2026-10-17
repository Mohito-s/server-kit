#!/usr/bin/env bash
# server-kit: установка модуля резервного копирования (kit-backup & kit-restore)
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log "Установка утилит резервного копирования (kit-backup и kit-restore)..."

cp "$SELF_DIR/bin/kit-backup" /usr/local/bin/kit-backup
cp "$SELF_DIR/bin/kit-restore" /usr/local/bin/kit-restore
chmod 755 /usr/local/bin/kit-backup /usr/local/bin/kit-restore

# Настройка еженедельного cron-задания (каждое воскресенье в 03:00)
cat > /etc/cron.d/kit-backup <<'CRON'
# Регулярный еженедельный бэкап в Telegram от server-kit
0 3 * * 0 root /usr/local/bin/kit-backup > /var/log/kit-backup.log 2>&1
CRON
chmod 644 /etc/cron.d/kit-backup

log "Модуль бэкапа установлен. Автозапуск: каждое воскресенье в 03:00."
log "Команды: kit-backup (создать и отправить) | kit-restore <архив> (восстановить)"
