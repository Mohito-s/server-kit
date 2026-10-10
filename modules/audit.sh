set -euo pipefail
. "$(dirname "$0")/../lib.sh"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y lynis

mkdir -p /var/lib/server-kit

cat > /usr/local/bin/kit-audit <<'INNER'
#!/usr/bin/env bash
# Аудит безопасности (Lynis) + краткий отчёт в Telegram
lynis audit system --cronjob >/dev/null 2>&1 || true
R=/var/log/lynis-report.dat
idx=$(grep -m1 '^hardening_index=' $R | cut -d= -f2)
warns=$(grep -c '^warning\[\]=' $R || true)
sugg=$(grep -c '^suggestion\[\]=' $R || true)
top=$(grep '^warning\[\]=' $R | head -5 | cut -d'|' -f2)
msg="🛡 Lynis: индекс безопасности ${idx:-?}/100, предупреждений: $warns, советов: $sugg"
[ -n "$top" ] && msg="$msg"$'\n'"$top"
echo "$msg"
/usr/local/bin/kit-notify "$msg"
INNER
chmod 755 /usr/local/bin/kit-audit

cat > /usr/local/bin/kit-check <<'INNER'
#!/usr/bin/env bash
# Самопроверка: сервисы, файрвол, защита, диск, память
. /etc/server-kit/config.env
problems=()
svc=(crowdsec crowdsec-firewall-bouncer kit-bot)
[ "${WITH_DOCKER:-0}"  = "1" ] && svc+=(docker)
[ "${WITH_NETDATA:-0}" = "1" ] && svc+=(netdata)
svc+=(${EXTRA_SERVICES:-})
for s in "${svc[@]}"; do
  systemctl list-unit-files "$s.service" 2>/dev/null | grep -q "$s.service" || continue
  systemctl is-active --quiet "$s" || problems+=("сервис $s не работает")
done
systemctl is-active --quiet ssh || systemctl is-active --quiet sshd || problems+=("SSH не работает")
ufw status | grep -q "Status: active" || problems+=("UFW выключен")
disk=$(df / --output=pcent | tail -1 | tr -dc 0-9)
[ "${disk:-0}" -lt 90 ] || problems+=("диск заполнен на ${disk}%")
mem=$(free | awk '/Mem:/ {printf "%d", $3/$2*100}')
[ "${mem:-0}" -lt 92 ] || problems+=("память ${mem}%")
if command -v docker >/dev/null; then
  bad=$(docker ps --filter status=restarting --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')
  [ -z "$bad" ] || problems+=("контейнеры перезапускаются: $bad")
fi
if [ ${#problems[@]} -eq 0 ]; then echo "OK: всё в порядке"; rm -f /var/lib/server-kit/last; exit 0; fi
msg="⚠️ $(IFS='; '; echo "${problems[*]}")"
echo "$msg"
# не спамим: то же сообщение повторяем не чаще раза в 6 часов
f=/var/lib/server-kit/last
if [ ! -f $f ] || [ "$(cat $f)" != "$msg" ] || [ -n "$(find $f -mmin +360)" ]; then
  echo "$msg" > $f
  /usr/local/bin/kit-notify "$msg"
fi
exit 1
INNER
chmod 755 /usr/local/bin/kit-check

cat > /etc/cron.d/server-kit <<'CRON'
*/10 * * * * root /usr/local/bin/kit-check >/dev/null 2>&1
0 6 * * 1 root /usr/local/bin/kit-audit >/dev/null 2>&1
CRON
log "Самопроверка каждые 10 минут, аудит Lynis по понедельникам в 06:00"
