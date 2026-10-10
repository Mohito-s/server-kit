# Общие функции для server-kit
KIT_CONF_DIR=/etc/server-kit
CONF=$KIT_CONF_DIR/config.env

log()  { echo -e "\033[1;32m[kit]\033[0m $*"; }
warn() { echo -e "\033[1;33m[kit]\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m[kit]\033[0m $*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "Запусти от root (или через sudo)"; }
have_tty()  { (exec </dev/tty) 2>/dev/null; }

load_conf() { if [ -f "$CONF" ]; then . "$CONF"; fi; }

# ask VAR "Вопрос" "значение по умолчанию"
ask() {
  local var=$1 q=$2 def=${3:-} ans=""
  if [ -n "${!var:-}" ]; then return 0; fi
  if have_tty; then read -r -p "$q ${def:+[$def]}: " ans </dev/tty || true; fi
  printf -v "$var" '%s' "${ans:-$def}"
}

# ask_yn VAR "Вопрос" y|n
ask_yn() {
  local var=$1 q=$2 def=${3:-n} ans=""
  if [ -n "${!var:-}" ]; then return 0; fi
  if have_tty; then read -r -p "$q [y/n, Enter=$def]: " ans </dev/tty || true; fi
  ans=${ans:-$def}
  case "$ans" in y|Y|yes|д|Д|да) printf -v "$var" '%s' 1 ;; *) printf -v "$var" '%s' 0 ;; esac
}

save_conf() {
  mkdir -p "$KIT_CONF_DIR"
  umask 077
  cat > "$CONF" <<CFG
TG_TOKEN="${TG_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"
WITH_DOCKER="${WITH_DOCKER:-0}"
WITH_NETDATA="${WITH_NETDATA:-0}"
WITH_BOT="${WITH_BOT:-0}"
EXTRA_PORTS="${EXTRA_PORTS:-}"
EXTRA_SERVICES="${EXTRA_SERVICES:-}"
CFG
  umask 022
}

tg() { [ -x /usr/local/bin/kit-notify ] && /usr/local/bin/kit-notify "$1" || true; }

# ---------- Описания для новичков ----------
MODULE_LIST="base alerts firewall crowdsec access bot docker netdata audit"

module_desc() {
  case "$1" in
    base)     echo "ставит нужные программы (curl, git, htop...) и включает автообновления безопасности" ;;
    alerts)   echo "присылает сообщение в Telegram, когда кто-то заходит на сервер по SSH" ;;
    firewall) echo "«забор» вокруг сервера: закрывает все порты, кроме SSH, 80 и 443 (готовый файрвол не ломает)" ;;
    crowdsec) echo "«охранник»: банит тех, кто подбирает пароли или сканирует порты, и сообщает вам" ;;
    access)   echo "страховка доступа: запасной ключ, защита SSH от частой поломки, команда kit-access для починки" ;;
    bot)      echo "команды из Telegram: /status, /unban, /repair — если вас забанили или SSH сломался" ;;
    docker)   echo "(по желанию) запуск программ в изолированных «коробках» (контейнерах), нужен для Remnawave" ;;
    netdata)  echo "(по желанию) красивые графики нагрузки сервера в браузере" ;;
    audit)    echo "проверка здоровья сервера каждые 10 минут и раз в неделю оценка безопасности (Lynis)" ;;
  esac
}

describe_modules() {
  echo "Что умеет этот скрипт (простыми словами):"
  for m in $MODULE_LIST; do printf "  • %-9s — %s\n" "$m" "$(module_desc "$m")"; done
}

describe_requirements() {
  cat <<'REQ'
Требования к серверу:
  • ОС: Ubuntu 22.04 / 24.04 или Debian 11 / 12 (лучше чистая, только что установленная)
  • Права: root (или sudo). Тип сервера: KVM. На OpenVZ/LXC файрвол может не работать
  • Базовый набор: от 1 ядра, 1 ГБ памяти, 10 ГБ диска
  • С Docker: от 2 ГБ памяти и 20 ГБ диска
  • С Docker + Netdata + твои сайты/боты/Remnawave: лучше 4 ГБ памяти
  • Интернет с доступом к GitHub, Telegram и репозиториям пакетов
  • Процессор x86_64 (обычный) или ARM64
  (цифры примерные, это ориентир, а не гарантия)
REQ
}

# ---------- Проверка сервера ----------
preflight() {
  MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  DISK_GB=$(df -BG / --output=avail | tail -1 | tr -dc 0-9)
  local cpus virt arch
  cpus=$(nproc)
  virt=$(systemd-detect-virt 2>/dev/null || echo unknown)
  arch=$(uname -m)
  log "Ваш сервер: ${cpus} CPU, ${MEM_MB} МБ памяти, ${DISK_GB} ГБ свободно, виртуализация: ${virt}, архитектура: ${arch}"

  case "$arch" in x86_64|aarch64) ;; *) die "Архитектура $arch не поддерживается (нужна x86_64 или ARM64)" ;; esac
  [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ] || die "Нужен systemd (на этом сервере его нет)"
  case "$virt" in openvz|lxc|lxc-libvirt) warn "Тип сервера $virt: файрвол и CrowdSec могут не заработать. Лучше KVM." ;; esac

  if [ "$MEM_MB" -lt 450 ] && [ "${FORCE:-0}" != "1" ]; then
    die "Слишком мало памяти (${MEM_MB} МБ), нужно хотя бы ~1 ГБ. Игнорировать: FORCE=1"
  fi
  if [ "${DISK_GB:-0}" -lt 3 ] && [ "${FORCE:-0}" != "1" ]; then
    die "Слишком мало места на диске (${DISK_GB} ГБ), нужно хотя бы 10 ГБ. Игнорировать: FORCE=1"
  fi
  [ "$MEM_MB" -ge 900 ] || warn "Памяти меньше 1 ГБ: сервер будет работать впритык, Docker и Netdata ставить не стоит"
  [ "${DISK_GB:-0}" -ge 10 ] || warn "Свободного места меньше 10 ГБ"
}

check_choices() {
  if [ "${WITH_DOCKER:-0}" = "1" ] && [ "$MEM_MB" -lt 1800 ]; then
    warn "Для Docker рекомендуется от 2 ГБ памяти, у вас ${MEM_MB} МБ"
  fi
  if [ "${WITH_NETDATA:-0}" = "1" ] && [ "$MEM_MB" -lt 1800 ]; then
    warn "Netdata занимает 150–300 МБ памяти, на вашем сервере это заметно (${MEM_MB} МБ)"
  fi
}
