#!/bin/bash

# ===============================
# Interaktivní spuštění Docker kontejneru s podporou Traefik
# ===============================

DATA_ROOT="/srv/data"

# === Uživatelské vstupy ===

read -p "Zadej jméno kontejneru: " CONTAINER_NAME
read -p "Zadej název Docker image (např. nginx:latest): " IMAGE_NAME

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
  if [[ "$INTERNAL_PORT" =~ ^[0-9]+$ ]]; then
    break
  else
    echo "❌ Zadej validní číslo portu."
  fi
done

# === Docker síť ===
read -p "Chceš použít síť (např. webproxy)? [webproxy]: " NETWORK
NETWORK=${NETWORK:-webproxy}

# === Restart politika ===
read -p "Restart policy? (např. always, unless-stopped) [always]: " RESTART_POLICY
RESTART_POLICY=${RESTART_POLICY:-always}

# === Mounty z /srv/data ===
VOLUMES=()
while true; do
  read -p "Chceš připojit adresář ze $DATA_ROOT? (y/n): " ADD_MOUNT
  ADD_MOUNT=${ADD_MOUNT:-n}
  if [[ "$ADD_MOUNT" != "y" ]]; then
    break
  fi

  read -p "Zadej název podadresáře (např. app1, postgres, portainer): " DATA_SUBDIR
  read -p "Zadej cílovou cestu v kontejneru (např. /data): " CONTAINER_PATH
  HOST_PATH="$DATA_ROOT/$DATA_SUBDIR"
  mkdir -p "$HOST_PATH"
  VOLUMES+=("$HOST_PATH:$CONTAINER_PATH")
done

# === Environment proměnné ===
read -p "Chceš přidat ENV proměnné? (např. VAR=hodnota), čárkami oddělené: " ENVS_INPUT
IFS=',' read -ra ENVS <<< "$ENVS_INPUT"

# ===============================
# Sestavení docker run příkazu
# ===============================

DOCKER_CMD="docker run -d \
  --name $CONTAINER_NAME \
  --restart $RESTART_POLICY \
  --network $NETWORK"

# Přidání volume mountů
for vol in "${VOLUMES[@]}"; do
  DOCKER_CMD+=" -v $vol"
done

# Přidání environment proměnných
for env in "${ENVS[@]}"; do
  [[ -n "$env" ]] && DOCKER_CMD+=" -e \"$env\""
done

# Traefik labely – escapované správně
DOCKER_CMD+=" \
  -l \"traefik.enable=true\" \
  -l \"traefik.http.routers.${CONTAINER_NAME}.rule=Host(\\\`$DOMAIN\\\`)\" \
  -l \"traefik.http.routers.${CONTAINER_NAME}.entrypoints=websecure\" \
  -l \"traefik.http.routers.${CONTAINER_NAME}.tls.certresolver=myresolver\" \
  -l \"traefik.http.services.${CONTAINER_NAME}.loadbalancer.server.port=$INTERNAL_PORT\""

# Přidání Docker image
DOCKER_CMD+=" $IMAGE_NAME"

# ===============================
# Spuštění
# ===============================

echo ""
echo "📦 Spouštím kontejner s příkazem:"
echo "$DOCKER_CMD"
echo ""

# Provede příkaz
eval "$DOCKER_CMD"

echo ""
echo "✅ Kontejner '$CONTAINER_NAME' běží na https://$DOMAIN"
