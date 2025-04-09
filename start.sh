#!/bin/bash

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
      bash server-init.sh
      break
      ;;
    2)
      echo "Spouštím run-container.sh..."
      bash run-container.sh
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
