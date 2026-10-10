set -euo pipefail
. "$(dirname "$0")/../lib.sh"
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl git jq ufw unattended-upgrades chrony htop ncdu rsync \
  ca-certificates gnupg lsb-release cron

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT
systemctl enable --now chrony cron >/dev/null 2>&1 || true
log "База готова: пакеты, автообновления безопасности, синхронизация времени"
