#!/bin/bash

# =========================================================
# KOMPLEXNÍ SKRIPT PRO NASTAVENÍ UBUNTU SERVERU
# =========================================================

# ======== BEZPEČNOSTNÍ KONTROLY A NASTAVENÍ ============
if [[ $EUID -ne 0 ]]; then
   echo "Tento skript musi byt spusten jako root"
   exit 1
fi

set -euo pipefail

# =========================================================
# 0. KONFIGURAČNÍ PROMĚNNÉ
# =========================================================

DEFAULT_OWNER="docker-www"
DEFAULT_SSH_PORT=22
DEFAULT_TIMEZONE="Europe/Prague"
DEFAULT_SWAP_SIZE="2G"

read -p "Zadej SSH port [$DEFAULT_SSH_PORT]: " SSH_PORT
SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

read -p "Zadej hostname (napr. vps.example.com): " NEW_HOSTNAME

read -p "Zadej casovou zonu [$DEFAULT_TIMEZONE]: " TIMEZONE
TIMEZONE=${TIMEZONE:-$DEFAULT_TIMEZONE}

read -p "Zadej e-mail pro Let's Encrypt: " USER_EMAIL
if [[ -z "$USER_EMAIL" ]]; then
  echo "E-mail nesmi byt prazdny. Ukoncuji skript."
  exit 1
fi

read -p "Zadej domenu pro Portainer (napr. portainer.example.com): " PORTAINER_DOMAIN
if [[ -z "$PORTAINER_DOMAIN" ]]; then
  echo "Domena nesmi byt prazdna. Ukoncuji."
  exit 1
fi

read -p "Zadej velikost swap prostoru [$DEFAULT_SWAP_SIZE]: " INPUT_SWAP_SIZE
SWAP_SIZE=${INPUT_SWAP_SIZE:-$DEFAULT_SWAP_SIZE}

read -p "Povolit HTTP/HTTPS porty? (y/n) [y]: " ALLOW_HTTP
ALLOW_HTTP=${ALLOW_HTTP:-y}

read -p "Chces nastavit SSH klic pro uzivatele $DEFAULT_OWNER? (y/n) [n]: " SETUP_SSH_KEY
SETUP_SSH_KEY=${SETUP_SSH_KEY:-n}
if [[ "$SETUP_SSH_KEY" == "y" ]]; then
  read -p "Vloz verejny SSH klic: " SSH_KEY
fi

# =========================================================
# 1. CESTY KE KONFIGURAČNÍM SOUBORŮM
# =========================================================

TRAEFIK_CONFIG_PATH="/srv/docker/traefik/traefik.yml"
ACME_JSON_PATH="/srv/docker/traefik/acme.json"
TRAEFIK_LE_PATH="/srv/docker/traefik/letsencrypt"
PORTAINER_DATA_PATH="/srv/data/portainer"
PROJECTS_ROOT="/srv/projects"
DATA_ROOT="/srv/data"
BACKUP_ROOT="/srv/backups"
SCRIPTS_ROOT="/srv/scripts"
SHARED_DOCKER_PATH="/srv/docker/shared"

SSH_CONFIG="/etc/ssh/sshd_config"
FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"
UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
DOCKER_LOGROTATE="/etc/logrotate.d/docker"

# =========================================================
# 1. ZÁKLADNÍ NASTAVENÍ SERVERU
# =========================================================

hostnamectl set-hostname "$NEW_HOSTNAME"
echo "Hostname nastaven na: $NEW_HOSTNAME"

apt update && apt upgrade -y
apt install -y curl wget git vim nano htop ncdu zip unzip ufw fail2ban

if command -v timedatectl &> /dev/null; then
    timedatectl set-timezone "$TIMEZONE"
    CURRENT_TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
else
    echo "$TIMEZONE" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
    CURRENT_TIMEZONE=$(cat /etc/timezone)
fi

echo "Casova zona nastavena na: $CURRENT_TIMEZONE"

apt install -y locales
locale-gen en_US.UTF-8
locale-gen cs_CZ.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

apt install -y chrony
systemctl enable chrony
systemctl start chrony

# =========================================================
# 2. ZABEZPEČENÍ SERVERU
# =========================================================

ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp

if [[ "$ALLOW_HTTP" == "y" ]]; then
    ufw allow http
    ufw allow https
fi

ufw --force enable

cat > "$FAIL2BAN_CONFIG" << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban

apt install -y unattended-upgrades apt-listchanges
cat > "$UNATTENDED_UPGRADES" << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

# =========================================================
# 3. INSTALACE DOCKERU A KONFIGURACE
# =========================================================

apt install -y apt-transport-https ca-certificates gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose
systemctl enable docker
systemctl start docker

# =========================================================
# 4. VYTVORENI UZIVATELE PRO DOCKER
# =========================================================

if ! id "$DEFAULT_OWNER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEFAULT_OWNER"
    usermod -aG docker "$DEFAULT_OWNER"
fi

if [[ "$SETUP_SSH_KEY" == "y" ]]; then
    mkdir -p "/home/$DEFAULT_OWNER/.ssh"
    echo "$SSH_KEY" > "/home/$DEFAULT_OWNER/.ssh/authorized_keys"
    chmod 700 "/home/$DEFAULT_OWNER/.ssh"
    chmod 600 "/home/$DEFAULT_OWNER/.ssh/authorized_keys"
    chown -R "$DEFAULT_OWNER:$DEFAULT_OWNER" "/home/$DEFAULT_OWNER/.ssh"
fi

# =========================================================
# 5. STRUKTURA A TRAEFIK
# =========================================================

mkdir -p /srv/docker/{traefik,portainer,shared}
mkdir -p "$PROJECTS_ROOT" "$DATA_ROOT" "$BACKUP_ROOT" "$SCRIPTS_ROOT" "$TRAEFIK_LE_PATH"
touch "$ACME_JSON_PATH"

cat > "$TRAEFIK_CONFIG_PATH" <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

certificatesResolvers:
  myresolver:
    acme:
      email: $USER_EMAIL
      storage: /letsencrypt/acme.json
      tlsChallenge: true

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

api:
  dashboard: true
EOF

chown -R "$DEFAULT_OWNER:$DEFAULT_OWNER" /srv
find /srv -type d -exec chmod 755 {} \;
find /srv -type f -exec chmod 644 {} \;
chmod -R 775 "$DATA_ROOT"
chmod 600 "$ACME_JSON_PATH"

docker network create webproxy || true

docker run -d \
  --name traefik \
  --restart always \
  -p 80:80 \
  -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$TRAEFIK_LE_PATH":/letsencrypt \
  -v "$TRAEFIK_CONFIG_PATH":/traefik.yml \
  --network webproxy \
  traefik:v2.10

# =========================================================
# 6. PORTAINER
# =========================================================

mkdir -p "$PORTAINER_DATA_PATH"

docker run -d \
  --name portainer \
  --restart always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PORTAINER_DATA_PATH":/data \
  --network webproxy \
  -l "traefik.enable=true" \
  -l "traefik.http.routers.portainer.rule=Host(\`$PORTAINER_DOMAIN\`)" \
  -l "traefik.http.routers.portainer.entrypoints=websecure" \
  -l "traefik.http.routers.portainer.tls.certresolver=myresolver" \
  -l "traefik.http.services.portainer.loadbalancer.server.port=9000" \
  portainer/portainer-ce:latest

chown -R "$DEFAULT_OWNER:$DEFAULT_OWNER" "$PORTAINER_DATA_PATH"
chmod -R 755 "$PORTAINER_DATA_PATH"

# =========================================================
# 7. SWAP A LOGROTATE
# =========================================================

if ! swapon --show | grep -q "/swapfile"; then
    fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$(echo $SWAP_SIZE | sed 's/G/*1024/' | bc)
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

cat > "$DOCKER_LOGROTATE" << EOF
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
}
EOF

# =========================================================
# 8. DOKONČENÍ
# =========================================================

echo "=== Nastaveni serveru dokonceno ==="
echo "Hostname: $NEW_HOSTNAME"
echo "Casova zona: $CURRENT_TIMEZONE"
echo "SSH port: $SSH_PORT"
echo "Docker uzivatel: $DEFAULT_OWNER"
echo "Portainer: https://$PORTAINER_DOMAIN"
echo "IP adresa: $(hostname -I | awk '{print $1}')"
echo "Firewall status:"
ufw status verbose
