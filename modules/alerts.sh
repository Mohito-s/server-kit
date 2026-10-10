set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf

cat > /usr/local/bin/kit-notify <<'INNER'
#!/usr/bin/env bash
. /etc/server-kit/config.env
[ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ] || exit 0
curl -s -m 10 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  --data-urlencode text="🖥 $(hostname): $1" >/dev/null 2>&1 || true
INNER
chmod 755 /usr/local/bin/kit-notify

if [ -z "${TG_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
  warn "Токен/chat id не указаны — Telegram-уведомления отключены"
  exit 0
fi

# Уведомление о каждом входе по SSH
cat > /usr/local/bin/kit-ssh-alert <<'INNER'
#!/usr/bin/env bash
[ "${PAM_TYPE:-}" = "open_session" ] || exit 0
/usr/local/bin/kit-notify "🔑 Вход по SSH: ${PAM_USER:-?} с ${PAM_RHOST:-локально}"
INNER
chmod 755 /usr/local/bin/kit-ssh-alert
grep -q kit-ssh-alert /etc/pam.d/sshd || \
  echo "session optional pam_exec.so quiet /usr/local/bin/kit-ssh-alert" >> /etc/pam.d/sshd

# Проверка, что бот реально отвечает
resp=$(curl -s -m 10 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -d chat_id="$TG_CHAT_ID" --data-urlencode text="🖥 $(hostname): уведомления подключены" || true)
if echo "$resp" | grep -q '"ok":true'; then
  log "Telegram работает, тестовое сообщение отправлено"
else
  warn "Telegram не ответил. Проверь токен и chat id (и что ты нажал Start у бота)"
fi
