#!/usr/bin/env bash
# server-kit: подготовка чистого Ubuntu/Debian сервера одной командой.
# Справка:  bash install.sh --help
set -euo pipefail

# >>> ЗАМЕНИ YOUR_USER на свой ник на GitHub <<<
REPO_URL="${REPO_URL:-https://github.com/Mohito-s/server-kit.git}"
INSTALL_DIR=/opt/server-kit

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

# Запуск через "curl | bash": скачиваем весь репозиторий и перезапускаемся из него
if [ ! -f "$SELF_DIR/lib.sh" ]; then
  [ "$(id -u)" -eq 0 ] || { echo "Запусти от root (или добавь sudo перед bash)"; exit 1; }
  apt-get update -y && apt-get install -y git curl ca-certificates
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  exec bash "$INSTALL_DIR/install.sh" "$@"
fi

. "$SELF_DIR/lib.sh"

case "${1:-}" in
  -h|--help|help) describe_modules; echo; describe_requirements; exit 0 ;;
esac

need_root
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
  *debian*|*ubuntu*) ;;
  *) die "Поддерживаются только Debian/Ubuntu" ;;
esac

echo; describe_modules; echo; describe_requirements; echo
preflight
load_conf

log "Настройка (Enter — значение по умолчанию)"
echo "  Telegram-бот нужен для уведомлений. Создай его у @BotFather, свой id узнай у @userinfobot."
echo "  Лучше создать ОТДЕЛЬНОГО бота только для сервера (не того, что уже работает в твоём проекте)."
ask TG_TOKEN "Токен Telegram-бота (Enter — без уведомлений)" ""
[ -n "${TG_TOKEN:-}" ] && ask TG_CHAT_ID "Твой chat id в Telegram" ""
if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
  echo "  bot: команды /status, /unban, /repair прямо из Telegram. Отвечает только тебе."
  ask_yn WITH_BOT "Включить управление из Telegram?" y
else
  WITH_BOT=0
fi
echo "  docker: нужен, если будешь ставить Remnawave и другие сервисы в контейнерах."
ask_yn WITH_DOCKER  "Установить Docker + Compose?" n
echo "  netdata: графики нагрузки (процессор, память, сеть). Съедает 150–300 МБ памяти."
ask_yn WITH_NETDATA "Установить Netdata?" n
save_conf
check_choices

echo
ask_yn CONFIRM "Всё готово. Начать установку?" y
[ "${YES:-0}" = "1" ] && CONFIRM=1
[ "$CONFIRM" = "1" ] || { echo "Отменено. Ничего не изменено."; exit 0; }

run() { log "=== $1: $(module_desc "$1") ==="; bash "$SELF_DIR/modules/$1.sh"; }

run base
run alerts
run firewall
run crowdsec
run access
[ "${WITH_BOT:-0}"     = "1" ] && run bot
[ "${WITH_DOCKER:-0}"  = "1" ] && run docker
[ "${WITH_NETDATA:-0}" = "1" ] && run netdata
run audit

tg "✅ server-kit установлен"
log "Готово! Проверка: kit-check | Доступ: kit-access help | Аудит: kit-audit | Баны: cscli decisions list"
