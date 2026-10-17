#!/usr/bin/env bash
# server-kit: настройка системы защиты CrowdSec и Firewall Bouncer
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf
export DEBIAN_FRONTEND=noninteractive

log "Установка и настройка CrowdSec..."

# 1. Добавление официального репозитория CrowdSec (если еще не добавлен)
if ! command -v cscli >/dev/null 2>&1; then
  log "Подключение официального репозитория CrowdSec..."
  curl -fsSL https://install.crowdsec.net | sh
  apt-get update -y
  apt-get install -y crowdsec
fi

# 2. Установка Firewall Bouncer (блокировка атак на уровне ядра/фаервола)
if ! dpkg -l | grep -qE "crowdsec-firewall-bouncer-(nftables|iptables)"; then
  log "Установка Firewall Bouncer..."
  apt-get install -y crowdsec-firewall-bouncer-nftables 2>/dev/null || \
    apt-get install -y crowdsec-firewall-bouncer-iptables
fi

# 3. Базовые коллекции правил
log "Обновление коллекций правил CrowdSec..."
cscli hub update >/dev/null 2>&1 || true
cscli collections install crowdsecurity/sshd crowdsecurity/linux crowdsecurity/whitelist-good-actors >/dev/null 2>&1 || true

# 4. Железобетонный Whitelist от самоблокировки
mkdir -p /etc/crowdsec/parsers/s02-enrich

SSH_CLIENT="${SSH_CLIENT:-}"
ADMIN_IP="${SSH_CLIENT%% *}"

cat > /etc/crowdsec/parsers/s02-enrich/kit-whitelist.yaml <<'WL'
name: kit/whitelist
description: "Защита от бана: приватные сети, VPN и доверенный IP администратора"
whitelist:
  reason: "Admin access and private subnets"
  ip:
    - "127.0.0.1"
    - "::1"
  cidr:
    - "10.0.0.0/8"        # Подсети WireGuard / AmneziaWG
    - "172.16.0.0/12"      # Docker мосты и внутренние сети AWS/VPS
    - "192.168.0.0/16"     # Локальные домашние сети
WL

if [ -n "$ADMIN_IP" ] && [[ "$ADMIN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "    - \"$ADMIN_IP\"" >> /etc/crowdsec/parsers/s02-enrich/kit-whitelist.yaml
  log "Текущий IP администратора ($ADMIN_IP) добавлен в whitelist CrowdSec"
fi

# 5. Мониторинг логов фаервола UFW (сканирование портов)
if [ -f /var/log/ufw.log ]; then
  cscli collections install crowdsecurity/iptables >/dev/null 2>&1 || true
  mkdir -p /etc/crowdsec/acquis.d
  cat > /etc/crowdsec/acquis.d/ufw.yaml <<'ACQ'
filenames:
  - /var/log/ufw.log
labels:
  type: syslog
ACQ
fi

# 6. Автоопределение установленных веб-серверов
if command -v nginx >/dev/null 2>&1; then
  log "Обнаружен Nginx — подключаю коллекцию правил CrowdSec для веб-сервера..."
  cscli collections install crowdsecurity/nginx >/dev/null 2>&1 || true
fi

# 7. Настройка уведомлений о банах в Telegram
if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
  mkdir -p /etc/crowdsec/notifications
  cp -n /etc/crowdsec/notifications/http.yaml /etc/crowdsec/notifications/http.yaml.bak 2>/dev/null || true
  cp -n /etc/crowdsec/profiles.yaml /etc/crowdsec/profiles.yaml.bak 2>/dev/null || true

  cat > /etc/crowdsec/notifications/http.yaml <<NOTIF
type: http
name: http_default
log_level: info
format: |
  {"chat_id": "${TG_CHAT_ID}", "text": "🚫 [CrowdSec Alert]\nЗаблокирован IP: {{range . -}}{{range .Decisions -}}{{.Value}} (правило: {{.Scenario}}){{end}}{{end}}"}
url: https://api.telegram.org/bot${TG_TOKEN}/sendMessage
method: POST
headers:
  Content-Type: "application/json"
NOTIF
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

# 8. Проверка конфигурации и запуск служб
if crowdsec -t >/dev/null 2>&1; then
  systemctl enable crowdsec >/dev/null 2>&1 || true
  systemctl restart crowdsec

  # Перезапуск bouncer'а
  if systemctl list-unit-files | grep -q "crowdsec-firewall-bouncer"; then
    systemctl enable crowdsec-firewall-bouncer >/dev/null 2>&1 || true
    systemctl restart crowdsec-firewall-bouncer >/dev/null 2>&1 || true
  fi
  log "CrowdSec успешно настроен и защищает сервер."
else
  warn "Внимание: проверка конфигурации crowdsec -t выдала ошибку. Сервер оставлен в текущем состоянии."
fi

log "Справка по CrowdSec: cscli decisions list (баны) | cscli metrics (метрики)"
