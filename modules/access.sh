set -euo pipefail
. "$(dirname "$0")/../lib.sh"
load_conf
KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

install -m 755 "$KIT_ROOT/bin/kit-access" /usr/local/bin/kit-access

# 1. Постоянное лечение частой поломки: после перезагрузки нет папки /run/sshd и SSH не стартует
mkdir -p /etc/tmpfiles.d
echo 'd /run/sshd 0755 root root -' > /etc/tmpfiles.d/sshd.conf
systemd-tmpfiles --create /etc/tmpfiles.d/sshd.conf 2>/dev/null || true
# ... и SSH сам поднимается, если упал
if systemctl list-unit-files ssh.service 2>/dev/null | grep -q ssh.service; then
  mkdir -p /etc/systemd/system/ssh.service.d
  printf '[Service]\nRestart=always\nRestartSec=5\n' > /etc/systemd/system/ssh.service.d/kit-restart.conf
  systemctl daemon-reload
fi

# 2. Копия рабочего конфига SSH + копия настроек доступа
mkdir -p /run/sshd
/usr/local/bin/kit-access backup | tail -1

# 3. Запасной ключ
echo "  Запасной ключ: второй твой публичный SSH-ключ (с другого компьютера или телефона)."
echo "  Если основной потеряется, зайдёшь по запасному. Публичный ключ — строка 'ssh-ed25519 AAAA...'."
ask SPARE_KEY "Вставь запасной публичный ключ (Enter — пропустить)" ""
if [ -n "${SPARE_KEY:-}" ]; then /usr/local/bin/kit-access add-key "$SPARE_KEY" || warn "Ключ не добавлен"; fi

log "Страховка доступа готова. Команда: kit-access help"
warn "Главная страховка — консоль и режим Rescue в панели хостера. Убедись, что у тебя есть доступ к панели."
