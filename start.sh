#!/bin/bash

# Skripty spouštíme vždy z adresáře, kde leží start.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Seznam dostupných skriptů
scripts=(
  "Inicializace serveru (server-init.sh)"
  "Spustit kontejner (run-container.sh)"
  "Konec"
)

# Menu
echo "Vyberte skript, který chcete spustit:"
select opt in "${scripts[@]}"; do
  case $REPLY in
    1)
      echo "Spouštím server-init.sh..."
      bash "$SCRIPT_DIR/server-init.sh"
      break
      ;;
    2)
      echo "Spouštím run-container.sh..."
      bash "$SCRIPT_DIR/run-container.sh"
      break
      ;;
    3)
      echo "Ukončuji..."
      break
      ;;
    *)
      echo "Neplatná volba, zkuste to znovu."
      ;;
  esac
done
