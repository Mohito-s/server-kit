set -euo pipefail
. "$(dirname "$0")/../lib.sh"

if command -v docker >/dev/null; then
  log "Docker уже установлен"
else
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
log "Docker + Compose готовы: docker compose version"
warn "ВАЖНО: порты, опубликованные Docker-контейнерами, обходят UFW. Публикуй только нужное (лучше 127.0.0.1:порт:порт + Nginx)."
