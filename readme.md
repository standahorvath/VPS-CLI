# 🐧 Scripts for VPS CLI

Tento repozitář obsahuje sadu bash skriptů a nástrojů, které ti pomohou s inicializací a správou projektového prostředí na serveru s Ubuntu — například na vlastním VPS u DigitalOcean. Hlavním cílem je zjednodušit opakované úlohy jako start projektů, nastavení serveru nebo spouštění kontejnerů.

K dispozici je také Docker Compose konfigurace pro ty, kteří si chtějí celé prostředí nejdříve otestovat nebo vyvíjet lokálně.

---

## 📁 Struktura

```
.
├── Dockerfile              # Ubuntu 22.04 + základní nástroje
├── docker-compose.yml      # Definice služby a volume mount
├── start.sh                # Hlavní spouštěcí skript s výběrem dalších skriptů
├── server-init.sh          # Ukázkový skript
└── run-container.sh        # Ukázkový skript
```

---

## 🛠️ Požadavky

- V produkci: Ubuntu VPS (např. DigitalOcean droplet)
- Pro testování: [Docker](https://www.docker.com/), [Docker Compose](https://docs.docker.com/compose/)

---

## 🚀 Nasazení na VPS (např. DigitalOcean)

1. Přihlas se na svůj VPS:

```bash
ssh root@moje-server-ip
```

2. Naklonuj repozitář:

```bash
git clone https://github.com/tvoje-username/ubuntu-dev-docker.git
cd ubuntu-dev-docker
```

3. Spusť úvodní skript:

```bash
bash start.sh
```

Ten ti umožní zvolit další akce nebo skripty jako `server-init.sh`, `run-container.sh` apod.

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

