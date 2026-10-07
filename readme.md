# 🐧 Scripts for VPS CLI

Tento repozitář obsahuje sadu bash skriptů a nástrojů, které ti pomohou s inicializací a správou projektového prostředí na serveru s Ubuntu — například na vlastním VPS u DigitalOcean. Hlavním cílem je zjednodušit opakované úlohy jako start projektů, nastavení serveru nebo spouštění kontejnerů.

K dispozici je také Docker Compose konfigurace pro ty, kteří si chtějí celé prostředí nejdříve otestovat nebo vyvíjet lokálně.

---

## 📁 Struktura

```
.
├── Dockerfile              # Ubuntu 22.04 + základní nástroje
├── docker-compose.yml      # Definice služby a volume mount
├── install.sh              # Jednořádková instalace (stáhne repozitář a spustí start.sh)
├── start.sh                # Hlavní spouštěcí skript s výběrem dalších skriptů
├── server-init.sh          # Inicializace serveru (firewall, SSH port, Docker, Traefik, Portainer, swap)
└── run-container.sh        # Spuštění kontejneru za Traefikem s HTTPS
```

---

## 🛠️ Požadavky

- V produkci: Ubuntu VPS (např. DigitalOcean droplet)
- Pro testování: [Docker](https://www.docker.com/), [Docker Compose](https://docs.docker.com/compose/)

---

## ⚡ Rychlý start (jeden příkaz)

Na čerstvém Ubuntu serveru stačí spustit:

```bash
curl -fsSL https://raw.githubusercontent.com/standahorvath/VPS-CLI/main/install.sh | sudo bash
```

Skript stáhne (nebo aktualizuje) repozitář do `/opt/vps-cli` a spustí `start.sh`. Při dalším spuštění stejného příkazu se repozitář jen aktualizuje.

Volitelně lze změnit větev nebo cílový adresář:

```bash
curl -fsSL https://raw.githubusercontent.com/standahorvath/VPS-CLI/main/install.sh | sudo VPS_CLI_BRANCH=main VPS_CLI_DIR=/opt/vps-cli bash
```

---

## 🚀 Nasazení na VPS ručně (např. DigitalOcean)

1. Přihlas se na svůj VPS:

```bash
ssh root@moje-server-ip
```

2. Naklonuj repozitář:

```bash
git clone https://github.com/standahorvath/VPS-CLI.git
cd VPS-CLI
```

3. Spusť úvodní skript:

```bash
bash start.sh
```

Ten ti umožní zvolit další akce nebo skripty jako `server-init.sh`, `run-container.sh` apod.

> ⚠️ Pokud v `server-init.sh` zvolíš jiný SSH port než 22, skript ho nastaví v SSH i ve firewallu. Před odhlášením si v novém okně ověř, že se připojíš: `ssh -p <port> root@moje-server-ip`.

> ℹ️ Pro HTTPS musí DNS záznamy domén (Portainer i aplikací) mířit na IP serveru — certifikáty vydává Let's Encrypt přes Traefik automaticky. HTTP se automaticky přesměrovává na HTTPS.

---

## 🐳 Lokální testování přes Docker Compose

1. Postav Docker image:

```bash
docker-compose build
```

2. Spusť kontejner interaktivně:

```bash
docker-compose run ubuntu-env
```

3. V kontejneru pak spustíš:

```bash
bash start.sh
```

> ℹ️ V kontejneru nefunguje `systemd` (`systemctl`, `hostnamectl`), takže `server-init.sh` tam celý neproběhne. Docker prostředí je vhodné hlavně pro úpravy menu a skriptů; `server-init.sh` testuj na čistém VPS.

Nebo uprav `docker-compose.yml` a spusť automaticky `start.sh`:

```yaml
command: ["bash", "start.sh"]
```

---

## 📂 Vazba na lokální složku

Lokální složka s tvými skripty se při použití Docker Compose automaticky připojí jako volume do `/root` v kontejneru. To znamená, že změny v projektu se okamžitě projeví i v Docker prostředí.

---

## ✨ Tipy

- `start.sh` můžeš rozšířit o další menu volby nebo automatizační logiku.
- Na serveru můžeš tento repozitář používat jako nástroj pro rychlý setup nových projektů nebo serverových prostředí.

