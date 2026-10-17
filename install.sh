#!/usr/bin/env bash
# server-kit: автоматическая подготовка и защита чистого Ubuntu/Debian сервера.
# Справка: bash install.sh --help
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Mohito-s/server-kit.git}"
INSTALL_DIR=/opt/server-kit
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

# Запуск через "curl | bash": клонируем репозиторий и перезапускаемся из него
if [ ! -f "$SELF_DIR/lib.sh" ]; then
  [ "$(id -u)" -eq 0 ] || { echo "Запустите от root (или добавьте sudo перед bash)"; exit 1; }
  apt-get update -y && apt-get install -y git curl ca-certificates
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  exec bash "$INSTALL_DIR/install.sh" "$@"
fi

. "$SELF_DIR/lib.sh"

NON_INTERACTIVE=0
AUTO_YES=0
CUSTOM_CONF=""

# Разбор аргументов командной строки
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help)
      echo "Использование: bash install.sh [ОПЦИИ]"
      echo
      describe_modules
      echo
      describe_requirements
      echo
      echo "Опции:"
      echo "  -y, --yes              Автоматически подтверждать запуск установки"
      echo "  --non-interactive      Запуск без интерактивных вопросов (из config.env)"
      echo "  -c, --config FILE      Использовать указанный конфигурационный файл"
      echo "  -h, --help             Показать эту справку"
      exit 0
      ;;
    -y|--yes)
      AUTO_YES=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      AUTO_YES=1
      shift
      ;;
    -c|--config)
      CUSTOM_CONF="$2"
      shift 2
      ;;
    *)
      warn "Неизвестный параметр: $1"
      shift
      ;;
  esac
done

need_root
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
  *debian*|*ubuntu*) ;;
  *) die "Поддерживаются только дистрибутивы Debian и Ubuntu" ;;
esac

echo -e "\033[1;36m"
cat <<'BANNER'
 ╔══════════════════════════════════════════════════════════════╗
 ║                     SERVER-KIT  v1.2                         ║
 ║        Модульная система настройки и защиты серверов         ║
 ╚══════════════════════════════════════════════════════════════╝
BANNER
echo -e "\033[0m"

preflight

if [ -n "$CUSTOM_CONF" ] && [ -f "$CUSTOM_CONF" ]; then
  log "Загрузка конфигурации из $CUSTOM_CONF"
  . "$CUSTOM_CONF"
else
  load_conf
fi

if [ "$NON_INTERACTIVE" -eq 0 ]; then
  echo
  describe_modules
  echo
  log "Настройка параметров (Enter — сохранить значение по умолчанию):"
  echo "  Telegram-бот нужен для моментальных алертов о входе по SSH и банах CrowdSec."
  ask TG_TOKEN "Токен Telegram-бота (Enter — без уведомлений)" ""

  if [ -n "${TG_TOKEN:-}" ]; then
    test_tg_token "$TG_TOKEN" || warn "Проверьте правильность токена бота!"
    ask TG_CHAT_ID "Ваш chat id в Telegram (узнать в @userinfobot)" ""
  fi

  if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
    echo "  bot: интерактивные кнопки меню /status, /bans, /unban, /repair прямо из Telegram."
    ask_yn WITH_BOT "Включить управление из Telegram?" y
  else
    WITH_BOT=0
  fi

  echo "  docker: контейнеризация приложений, обязательна для Remnawave/Xray/Amnezia."
  ask_yn WITH_DOCKER  "Установить Docker + Docker Compose?" y

  echo "  netdata: веб-панель мониторинга нагрузки (CPU, RAM, сеть) в реальном времени."
  ask_yn WITH_NETDATA "Установить Netdata?" n

  save_conf
  check_choices

  echo
  ask_yn CONFIRM "Все настройки сохранены. Начать установку?" y
  [ "$AUTO_YES" = "1" ] && CONFIRM=1
  [ "$CONFIRM" = "1" ] || { log "Установка отменена. Изменения не внесены."; exit 0; }
else
  log "Режим non-interactive: используются параметры из конфигурации"
  save_conf
fi

TOTAL_STEPS=7
[ "${WITH_BOT:-0}"     = "1" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[ "${WITH_DOCKER:-0}"  = "1" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[ "${WITH_NETDATA:-0}" = "1" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

CURRENT_STEP=1

run() {
  log "[$CURRENT_STEP/$TOTAL_STEPS] Модуль $1: $(module_desc "$1")"
  bash "$SELF_DIR/modules/$1.sh"
  CURRENT_STEP=$((CURRENT_STEP + 1))
}

run base
run alerts
run firewall
run crowdsec
run access
run backup
[ "${WITH_BOT:-0}"     = "1" ] && run bot
[ "${WITH_DOCKER:-0}"  = "1" ] && run docker
[ "${WITH_NETDATA:-0}" = "1" ] && run netdata
run audit

tg "✅ Server-Kit v1.2 успешно установлен на $(hostname)"

echo -e "\033[1;32m"
cat <<'DONE'
 ╔══════════════════════════════════════════════════════════════╗
 ║                УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                  ║
 ╚══════════════════════════════════════════════════════════════╝
DONE
echo -e "\033[0m"

log "Полезные команды для работы:"
echo "  • kit-check          — быстрая проверка статуса всех служб сервера"
echo "  • kit-backup         — создать бэкап и мгновенно отправить в Telegram"
echo "  • kit-restore <файл> — в 1 клик восстановить сервер из бэкапа"
echo "  • kit-access help    — управление SSH-ключами и аварийным доступом"
echo "  • kit-audit          — запуск аудита безопасности Lynis"
echo "  • cscli decisions list — просмотр заблокированных IP в CrowdSec"
echo "  • cscli decisions delete --all — снять все баны CrowdSec"
if [ "${WITH_BOT:-0}" = "1" ]; then
  echo "  • Telegram Bot       — отправьте /menu в чат с ботом для управления"
fi
echo
