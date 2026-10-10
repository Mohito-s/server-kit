set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf

if ! command -v netdata >/dev/null; then
  curl -fsSL https://get.netdata.cloud/kickstart.sh -o /tmp/netdata-kickstart.sh
  sh /tmp/netdata-kickstart.sh --non-interactive --stable-channel --disable-telemetry
fi

mkdir -p /etc/netdata
# Панель только локально. Доступ с компьютера: ssh -L 19999:localhost:19999 root@СЕРВЕР
printf '\n[web]\n\tbind to = 127.0.0.1\n' >> /etc/netdata/netdata.conf

if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
  cat >> /etc/netdata/health_alarm_notify.conf <<NCONF
SEND_TELEGRAM="YES"
TELEGRAM_BOT_TOKEN="${TG_TOKEN}"
DEFAULT_RECIPIENT_TELEGRAM="${TG_CHAT_ID}"
NCONF
fi
systemctl restart netdata
log "Netdata готов (только localhost:19999, доступ через SSH-туннель)"
