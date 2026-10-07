#!/bin/bash

# ===============================
# Interaktivní spuštění Docker kontejneru s podporou Traefik
# ===============================

set -euo pipefail

DATA_ROOT="/srv/data"

if ! command -v docker &>/dev/null; then
  echo "❌ Docker není nainstalovaný. Nejdřív spusť server-init.sh."
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "❌ Nemáš přístup k Dockeru. Spusť skript jako root nebo jako uživatel ve skupině docker."
  exit 1
fi

# === Uživatelské vstupy ===

while true; do
  read -p "Zadej jméno kontejneru: " CONTAINER_NAME
  # Jméno se používá i v názvu Traefik routeru, proto bez teček
  if [[ "$CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    if docker container inspect "$CONTAINER_NAME" &>/dev/null; then
      echo "❌ Kontejner '$CONTAINER_NAME' už existuje."
    else
      break
    fi
  else
    echo "❌ Jméno smí obsahovat jen písmena, číslice, '-' a '_'."
  fi
done

while true; do
  read -p "Zadej název Docker image (např. nginx:latest): " IMAGE_NAME
  if [[ -n "$IMAGE_NAME" && "$IMAGE_NAME" != *[[:space:]]* ]]; then
    break
  fi
  echo "❌ Image nesmí být prázdný ani obsahovat mezery."
done

# === Doména pro Traefik ===
while true; do
  read -p "Zadej doménu, na které má kontejner běžet (např. app.example.com): " DOMAIN
  if [[ -n "$DOMAIN" ]]; then
    break
  else
    echo "❌ Doména nesmí být prázdná."
  fi
done

# === Interní port (na kterém běží služba v kontejneru) ===
while true; do
  read -p "Zadej interní port (např. 80, 9000): " INTERNAL_PORT
  if [[ "$INTERNAL_PORT" =~ ^[0-9]+$ ]] && (( INTERNAL_PORT >= 1 && INTERNAL_PORT <= 65535 )); then
    break
  else
    echo "❌ Zadej validní číslo portu."
  fi
done

# === Docker síť ===
while true; do
  read -p "Chceš použít síť (např. webproxy)? [webproxy]: " NETWORK
  NETWORK=${NETWORK:-webproxy}
  if docker network inspect "$NETWORK" &>/dev/null; then
    break
  fi
  echo "❌ Síť '$NETWORK' neexistuje."
done

# === Restart politika ===
read -p "Restart policy? (např. always, unless-stopped) [always]: " RESTART_POLICY
RESTART_POLICY=${RESTART_POLICY:-always}

# === Mounty z /srv/data ===
VOLUMES=()
while true; do
  read -p "Chceš připojit adresář ze $DATA_ROOT? (y/n) [n]: " ADD_MOUNT
  ADD_MOUNT=${ADD_MOUNT:-n}
  if [[ "$ADD_MOUNT" != "y" ]]; then
    break
  fi

  read -p "Zadej název podadresáře (např. app1, postgres, portainer): " DATA_SUBDIR
  read -p "Zadej cílovou cestu v kontejneru (např. /data): " CONTAINER_PATH
  if [[ -z "$DATA_SUBDIR" || "$DATA_SUBDIR" == *..* || "$CONTAINER_PATH" != /* ]]; then
    echo "❌ Neplatný podadresář nebo cesta (cesta v kontejneru musí začínat '/')."
    continue
  fi
  HOST_PATH="$DATA_ROOT/$DATA_SUBDIR"
  mkdir -p "$HOST_PATH"
  VOLUMES+=("$HOST_PATH:$CONTAINER_PATH")
done

# === Environment proměnné ===
read -p "Chceš přidat ENV proměnné? (např. VAR=hodnota), čárkami oddělené: " ENVS_INPUT
ENVS=()
if [[ -n "$ENVS_INPUT" ]]; then
  IFS=',' read -ra ENVS <<< "$ENVS_INPUT"
fi

# ===============================
# Sestavení docker run příkazu
# ===============================

DOCKER_CMD=(docker run -d
  --name "$CONTAINER_NAME"
  --restart "$RESTART_POLICY"
  --network "$NETWORK")

# Přidání volume mountů
for vol in "${VOLUMES[@]+"${VOLUMES[@]}"}"; do
  DOCKER_CMD+=(-v "$vol")
done

# Přidání environment proměnných
for env in "${ENVS[@]+"${ENVS[@]}"}"; do
  [[ -n "$env" ]] && DOCKER_CMD+=(-e "$env")
done

# Traefik labely
DOCKER_CMD+=(
  -l "traefik.enable=true"
  -l "traefik.docker.network=$NETWORK"
  -l "traefik.http.routers.${CONTAINER_NAME}.rule=Host(\`$DOMAIN\`)"
  -l "traefik.http.routers.${CONTAINER_NAME}.entrypoints=websecure"
  -l "traefik.http.routers.${CONTAINER_NAME}.tls.certresolver=myresolver"
  -l "traefik.http.services.${CONTAINER_NAME}.loadbalancer.server.port=$INTERNAL_PORT"
)

# Přidání Docker image
DOCKER_CMD+=("$IMAGE_NAME")

# ===============================
# Spuštění
# ===============================

echo ""
echo "📦 Spouštím kontejner s příkazem:"
printf '%q ' "${DOCKER_CMD[@]}"
echo ""
echo ""

if ! "${DOCKER_CMD[@]}"; then
  echo ""
  echo "❌ Spuštění kontejneru '$CONTAINER_NAME' selhalo."
  exit 1
fi

echo ""
echo "✅ Kontejner '$CONTAINER_NAME' běží na https://$DOMAIN"
