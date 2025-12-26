# Raspberry Pi Server Setup
 
This repository provides an **all-in-one automated installer** for turning a Raspberry Pi into a self-hosted server with VPN, DNS, media servers, cloud storage, and more.

## Features

The script allows you to choose which services to install:

- **Traefik** – Reverse proxy with automatic SSL (Let's Encrypt)
- **WireGuard** – VPN access to your home network
- **Pi-hole + Unbound** – Local ad-blocking DNS with privacy-focused upstream resolver
- **Jellyfin** – Media server for movies and TV shows
- **Navidrome** – Music streaming server
- **Nextcloud** – Self-hosted cloud storage
- **MariaDB** – Database for Nextcloud
- **Immich** – Self-hosted photo and video backup
- **RAID (mdadm)** – Software RAID management
- **Portainer** – Web UI for managing Docker

All services run inside Docker containers.

## Requirements

- Raspberry Pi 3/4/5 (arm64 or armv7 supported)
- Raspberry Pi OS (Debian-based)
- Static IP or port forwarding set up on your router if you want external access
- Root privileges

## Installation

Clone the repository and run the script:

```bash
sudo apt update && sudo apt install -y wget git
git clone https://github.com/Biondi-Tommaso/PiServerStack.git
cd raspi-server-setup
sudo ./raspiserver-setup.sh
```

Or run directly with wget:

```
wget https://github.com/Biondi-Tommaso/PiServerStack/blob/main/setup.sh -O setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

Usage

1. The script installs Docker and generates a default docker-compose.yml file.
2. You will be prompted to select which services to enable.
3. A .env file will be created with default environment values (PUID, PGID, TZ, etc.).

After setup:
```
cd /srv/raspi-stack
docker compose up -d
```

### Firewall

- The script configures UFW automatically:
- SSH (22 or your custom port)
- HTTP (80), HTTPS (443)
- WireGuard (UDP 51820 by default)
- DNS (53)

### Notes

- Change all default passwords before exposing services to the internet.
- For external access with SSL, set your domain name in .env and configure DNS records.
- Backup your volumes (nextcloud, mariadb, pihole, etc.) regularly.

### Disclaimer

This project is provided as is. Use at your own risk. Always secure your Raspberry Pi and network before exposing services publicly.

Happy self-hosting!
