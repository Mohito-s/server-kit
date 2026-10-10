set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf
export DEBIAN_FRONTEND=noninteractive

curl -fsSL https://install.crowdsec.net | sh
apt-get install -y crowdsec
apt-get install -y crowdsec-firewall-bouncer-nftables || \
  apt-get install -y crowdsec-firewall-bouncer-iptables

cscli collections install crowdsecurity/sshd crowdsecurity/linux >/dev/null 2>&1 || true

# Чтобы не забанить самого себя: whitelist для текущего IP администратора
SSH_CLIENT="${SSH_CLIENT:-}"; ADMIN_IP="${SSH_CLIENT%% *}"
if [ -n "$ADMIN_IP" ]; then
  mkdir -p /etc/crowdsec/parsers/s02-enrich
  cat > /etc/crowdsec/parsers/s02-enrich/kit-whitelist.yaml <<WL
name: kit/whitelist
description: "admin ip"
whitelist:
  reason: "admin"
  ip:
    - "$ADMIN_IP"
WL
  log "Твой IP $ADMIN_IP добавлен в whitelist"
fi

# Сканирование портов (по логам UFW) — по возможности
cscli collections install crowdsecurity/iptables >/dev/null 2>&1 || true
mkdir -p /etc/crowdsec/acquis.d
cat > /etc/crowdsec/acquis.d/ufw.yaml <<'ACQ'
filenames:
  - /var/log/ufw.log
labels:
  type: syslog
ACQ

# Уведомления о банах в Telegram
if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
  mkdir -p /etc/crowdsec/notifications
  cp -n /etc/crowdsec/notifications/http.yaml /etc/crowdsec/notifications/http.yaml.bak 2>/dev/null || true
  cp -n /etc/crowdsec/profiles.yaml /etc/crowdsec/profiles.yaml.bak 2>/dev/null || true
  cat > /etc/crowdsec/notifications/http.yaml <<'NOTIF'
type: http
name: http_default
log_level: info
format: |
  {"chat_id": "@CHAT@", "text": "🚫 CrowdSec: {{range . -}}{{range .Decisions -}}бан {{.Value}} ({{.Scenario}}) {{end}}{{end}}"}
url: https://api.telegram.org/bot@TOKEN@/sendMessage
method: POST
headers:
  Content-Type: "application/json"
NOTIF
  sed -i "s|@CHAT@|${TG_CHAT_ID}|; s|@TOKEN@|${TG_TOKEN}|" /etc/crowdsec/notifications/http.yaml
  chmod 600 /etc/crowdsec/notifications/http.yaml
  cat > /etc/crowdsec/profiles.yaml <<'PROF'
name: default_ip_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
 - type: ban
   duration: 4h
notifications:
 - http_default
on_success: break
---
name: default_range_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Range"
decisions:
 - type: ban
   duration: 4h
on_success: break
PROF
fi

systemctl enable crowdsec >/dev/null 2>&1 || true
systemctl restart crowdsec
log "CrowdSec установлен. Баны: cscli decisions list | Статистика: cscli metrics"
