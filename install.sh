#!/bin/bash

# =========================================================
# Jednořádková instalace a spuštění VPS CLI:
#   curl -fsSL https://raw.githubusercontent.com/standahorvath/VPS-CLI/main/install.sh | sudo bash
# =========================================================

set -euo pipefail

REPO_URL="https://github.com/standahorvath/VPS-CLI.git"
BRANCH="${VPS_CLI_BRANCH:-main}"
INSTALL_DIR="${VPS_CLI_DIR:-/opt/vps-cli}"

if [[ $EUID -ne 0 ]]; then
  echo "Spusť instalaci jako root (např. přes sudo)."
  exit 1
fi

# Při 'curl ... | bash' je stdin roura se skriptem, interaktivní dotazy
# proto musí číst z terminálu.
if [[ ! -t 0 ]]; then
  if [[ -r /dev/tty ]]; then
    exec < /dev/tty
  else
    echo "Není dostupný terminál pro interaktivní dotazy."
    exit 1
  fi
fi

if ! command -v git &>/dev/null; then
  echo "Instaluji git..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y git
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Aktualizuji $INSTALL_DIR..."
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout -B "$BRANCH" FETCH_HEAD
else
  echo "Stahuji VPS CLI do $INSTALL_DIR..."
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

exec bash "$INSTALL_DIR/start.sh"
