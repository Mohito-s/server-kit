set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf

SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)
SSH_PORT=${SSH_PORT:-22}

if ufw status | grep -q "Status: inactive"; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${SSH_PORT}/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
  for p in ${EXTRA_PORTS:-}; do ufw allow "$p"; done
  ufw logging low
  ufw --force enable
  log "UFW включён: открыты SSH (${SSH_PORT}), 80, 443 ${EXTRA_PORTS:-}"
else
  # На сервере, где файрвол уже настроен, ничего не ломаем
  ufw allow "${SSH_PORT}/tcp" >/dev/null
  ufw logging low >/dev/null
  warn "UFW уже активен — правила не менял, только убедился что SSH (${SSH_PORT}) открыт"
fi
