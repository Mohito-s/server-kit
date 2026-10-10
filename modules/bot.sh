set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf
KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${TG_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
  warn "Нет токена бота — управление из Telegram пропущено"; exit 0
fi
install -m 755 "$KIT_ROOT/bin/kit-bot" /usr/local/bin/kit-bot
cat > /etc/systemd/system/kit-bot.service <<'UNIT'
[Unit]
Description=server-kit Telegram bot
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/kit-bot
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now kit-bot
log "Бот слушает команды: /status /unban /unbanall /repair (только от твоего chat id)"
warn "Если бот уже используется другой программой, будет ошибка 409. Для сервера заведи отдельного бота."
