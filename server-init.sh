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

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# =========================================================
# 0. KONFIGURAČNÍ PROMĚNNÉ
# =========================================================

DEFAULT_OWNER="docker-www"
DEFAULT_SSH_PORT=22
DEFAULT_TIMEZONE="Europe/Prague"
DEFAULT_SWAP_SIZE="2G"

while true; do
  read -p "Zadej SSH port [$DEFAULT_SSH_PORT]: " SSH_PORT
  SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}
  if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )); then
    break
  fi
  echo "Neplatny port (1-65535)."
done

while true; do
  read -p "Zadej hostname (napr. vps.example.com): " NEW_HOSTNAME
  if [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    break
  fi
  echo "Neplatny hostname."
done

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

while true; do
  read -p "Zadej velikost swap prostoru (napr. 2G, 512M) [$DEFAULT_SWAP_SIZE]: " INPUT_SWAP_SIZE
  SWAP_SIZE=${INPUT_SWAP_SIZE:-$DEFAULT_SWAP_SIZE}
  if [[ "$SWAP_SIZE" =~ ^[0-9]+[GM]$ ]]; then
    break
  fi
  echo "Neplatna velikost, pouzij format napr. 2G nebo 512M."
done

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
TRAEFIK_LE_PATH="/srv/docker/traefik/letsencrypt"
ACME_JSON_PATH="$TRAEFIK_LE_PATH/acme.json"
PORTAINER_DATA_PATH="/srv/data/portainer"
PROJECTS_ROOT="/srv/projects"
DATA_ROOT="/srv/data"
BACKUP_ROOT="/srv/backups"
SCRIPTS_ROOT="/srv/scripts"
SHARED_DOCKER_PATH="/srv/docker/shared"

SSH_PORT_CONFIG="/etc/ssh/sshd_config.d/00-vps-cli-port.conf"
FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"
UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
DOCKER_LOGROTATE="/etc/logrotate.d/docker"

# =========================================================
# 1. ZÁKLADNÍ NASTAVENÍ SERVERU
# =========================================================

hostnamectl set-hostname "$NEW_HOSTNAME"
if ! grep -qE "^127\.0\.1\.1[[:space:]]+$NEW_HOSTNAME([[:space:]]|$)" /etc/hosts; then
    echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
fi
echo "Hostname nastaven na: $NEW_HOSTNAME"

apt-get update && apt-get upgrade "${APT_OPTS[@]}"
apt-get install "${APT_OPTS[@]}" curl wget git vim nano htop ncdu zip unzip ufw fail2ban

if command -v timedatectl &> /dev/null; then
    timedatectl set-timezone "$TIMEZONE"
    CURRENT_TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
else
    echo "$TIMEZONE" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
    CURRENT_TIMEZONE=$(cat /etc/timezone)
fi

echo "Casova zona nastavena na: $CURRENT_TIMEZONE"

apt-get install "${APT_OPTS[@]}" locales
locale-gen en_US.UTF-8
locale-gen cs_CZ.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

apt-get install "${APT_OPTS[@]}" chrony
systemctl enable chrony
systemctl start chrony

# =========================================================
# 2. ZABEZPEČENÍ SERVERU
# =========================================================

# Nastaveni SSH portu (drop-in ma prednost pred hlavnim sshd_config).
# Musi probehnout pred zapnutim firewallu, jinak hrozi zamceni mimo server.
mkdir -p /etc/ssh/sshd_config.d /run/sshd
echo "Port $SSH_PORT" > "$SSH_PORT_CONFIG"
if ! sshd -t; then
    rm -f "$SSH_PORT_CONFIG"
    echo "Neplatna SSH konfigurace, port nebyl zmenen. Ukoncuji."
    exit 1
fi
if systemctl is-enabled ssh.socket &>/dev/null; then
    # Ubuntu 22.10+ pouziva socket activation, port se bere ze sshd_config pres generator
    systemctl daemon-reload
    systemctl restart ssh.socket
else
    systemctl restart ssh
fi
echo "SSH nasloucha na portu: $SSH_PORT"

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp

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

apt-get install "${APT_OPTS[@]}" unattended-upgrades apt-listchanges
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

apt-get install "${APT_OPTS[@]}" apt-transport-https ca-certificates gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install "${APT_OPTS[@]}" docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# =========================================================
# 4. VYTVORENI UZIVATELE PRO DOCKER
# =========================================================

if ! id "$DEFAULT_OWNER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEFAULT_OWNER"
fi
usermod -aG docker "$DEFAULT_OWNER"

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

mkdir -p /srv/docker/{traefik,portainer} "$SHARED_DOCKER_PATH"
mkdir -p "$PROJECTS_ROOT" "$DATA_ROOT" "$BACKUP_ROOT" "$SCRIPTS_ROOT" "$TRAEFIK_LE_PATH" "$PORTAINER_DATA_PATH"
touch "$ACME_JSON_PATH"

cat > "$TRAEFIK_CONFIG_PATH" <<EOF
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
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
EOF

# Prava nastavujeme jen na adresare vytvorene skriptem, ne rekurzivne
# do dat aplikaci (napr. postgres vyzaduje sva vlastni prava).
for dir in /srv /srv/docker /srv/docker/traefik /srv/docker/portainer "$SHARED_DOCKER_PATH" \
           "$PROJECTS_ROOT" "$BACKUP_ROOT" "$SCRIPTS_ROOT"; do
    chown "$DEFAULT_OWNER:$DEFAULT_OWNER" "$dir"
    chmod 755 "$dir"
done
chown "$DEFAULT_OWNER:$DEFAULT_OWNER" "$DATA_ROOT"
chmod 775 "$DATA_ROOT"
chmod 644 "$TRAEFIK_CONFIG_PATH"
chmod 700 "$TRAEFIK_LE_PATH"
chmod 600 "$ACME_JSON_PATH"

docker network inspect webproxy &>/dev/null || docker network create webproxy

# Pri opakovanem spusteni kontejner znovu vytvorime s aktualni konfiguraci
docker rm -f traefik &>/dev/null || true
docker run -d \
  --name traefik \
  --restart always \
  -p 80:80 \
  -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$TRAEFIK_LE_PATH":/letsencrypt \
  -v "$TRAEFIK_CONFIG_PATH":/etc/traefik/traefik.yml:ro \
  --network webproxy \
  traefik:v3.6

# =========================================================
# 6. PORTAINER
# =========================================================

docker rm -f portainer &>/dev/null || true
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

# =========================================================
# 7. SWAP A LOGROTATE
# =========================================================

if ! swapon --show | grep -q "/swapfile"; then
    if [[ ! -f /swapfile ]]; then
        SWAP_NUM=${SWAP_SIZE%[GM]}
        if [[ "$SWAP_SIZE" == *G ]]; then SWAP_MB=$((SWAP_NUM * 1024)); else SWAP_MB=$SWAP_NUM; fi
        fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB"
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile
fi
grep -q "^/swapfile " /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab

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
if [[ "$SSH_PORT" != "22" ]]; then
    echo ""
    echo "POZOR: SSH nyni bezi na portu $SSH_PORT. Pred odhlasenim over pripojeni v novem okne:"
    echo "  ssh -p $SSH_PORT root@$(hostname -I | awk '{print $1}')"
fi
