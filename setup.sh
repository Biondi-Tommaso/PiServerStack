#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BASE_DIR="/srv/raspi-stack"
TZ="Europe/London"
PUID=1000
PGID=1000
DOMAIN=""
WG_PORT=51820
SSH_PORT=22

ensure_root(){ if [ "$(id -u)" -ne 0 ]; then echo "Run as root"; exit 1; fi; }

install_docker(){
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  if [ -n "${SUDO_USER-}" ]; then usermod -aG docker "$SUDO_USER" || true; fi
}

create_dirs(){ mkdir -p "$BASE_DIR"; chown -R $PUID:$PGID "$BASE_DIR" || true; }

write_env(){
cat > "$BASE_DIR/.env" <<EOF
PUID=$PUID
PGID=$PGID
TZ=$TZ
DOMAIN=$DOMAIN
WG_PORT=$WG_PORT
EOF
}

write_compose(){
cat > "$BASE_DIR/docker-compose.yml" <<'YAML'
version: "3.8"
services:
  traefik:
    image: traefik:latest
    restart: unless-stopped
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./traefik/letsencrypt:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - web

  wireguard:
    image: lscr.io/linuxserver/wireguard:latest
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - SERVERURL=${DOMAIN}
      - SERVERPORT=${WG_PORT}
      - PEERS=1
      - PEERDNS=1.1.1.1
    ports:
      - "${WG_PORT}:${WG_PORT}/udp"
    volumes:
      - ./wireguard/config:/config
      - /lib/modules:/lib/modules
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
    networks:
      - web

  pihole:
    image: pihole/pihole:latest
    environment:
      - TZ=${TZ}
      - WEBPASSWORD=changeme
      - DNSMASQ_LISTENING=all
    volumes:
      - ./pihole/etc-pihole:/etc/pihole
      - ./pihole/etc-dnsmasq.d:/etc/dnsmasq.d
    cap_add:
      - NET_ADMIN
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8081:80"
    restart: unless-stopped
    networks:
      - web

  unbound:
    image: mvance/unbound:latest
    restart: unless-stopped
    ports:
      - "5335:5335/tcp"
      - "5335:5335/udp"
    volumes:
      - ./unbound:/opt/unbound
    networks:
      - web

  jellyfin:
    image: jellyfin/jellyfin:latest
    volumes:
      - ./jellyfin/config:/config
      - ./jellyfin/cache:/cache
      - ./media:/media
    ports:
      - "8096:8096"
    restart: unless-stopped
    networks:
      - web

  navidrome:
    image: deluan/navidrome:latest
    volumes:
      - ./navidrome/data:/data
      - ./media/music:/music
    ports:
      - "4533:4533"
    restart: unless-stopped
    networks:
      - web

  mariadb:
    image: mariadb:10.6
    environment:
      - MYSQL_ROOT_PASSWORD=changeme
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=nextcloudpass
    volumes:
      - ./mariadb:/var/lib/mysql
    restart: unless-stopped
    networks:
      - web

  nextcloud:
    image: nextcloud:latest
    environment:
      - MYSQL_PASSWORD=nextcloudpass
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=mariadb
    volumes:
      - ./nextcloud/data:/var/www/html
    ports:
      - "8080:80"
    depends_on:
      - mariadb
    restart: unless-stopped
    networks:
      - web

  immich:
    image: ghcr.io/immich-app/immich-server:latest
    volumes:
      - ./immich/data:/usr/src/app/upload
    ports:
      - "2283:3001"
    restart: unless-stopped
    networks:
      - web

  raid:
    image: linuxserver/mdadm
    container_name: raid
    privileged: true
    volumes:
      - /dev:/dev
      - ./raid/config:/config
    restart: unless-stopped
    networks:
      - web

  portainer:
    image: portainer/portainer-ce:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer/data:/data
    ports:
      - "9000:9000"
    restart: unless-stopped
    networks:
      - web

networks:
  web:
    driver: bridge
YAML
}

firewall(){
  if ! command -v ufw >/dev/null 2>&1; then apt-get install -y ufw; fi
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow $SSH_PORT/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 53
  ufw allow $WG_PORT/udp
  ufw --force enable
}

menu(){
  echo "Select services (space separated):"
  echo "1) Traefik 2) WireGuard 3) Pi-hole 4) Unbound 5) Jellyfin 6) Navidrome 7) Nextcloud 8) Immich 9) Raid 10) Portainer"
  read -rp "Enter numbers: " choices
  sed -i '/services:/,$d' "$BASE_DIR/docker-compose.yml"
  echo "services:" >> "$BASE_DIR/docker-compose.yml"
  for c in $choices; do
    case $c in
      1) grep -A20 "traefik:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      2) grep -A30 "wireguard:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      3) grep -A20 "pihole:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      4) grep -A10 "unbound:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      5) grep -A15 "jellyfin:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      6) grep -A15 "navidrome:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      7) grep -A20 "nextcloud:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      8) grep -A10 "immich:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      9) grep -A10 "raid:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
      10) grep -A10 "portainer:" "$BASE_DIR/docker-compose.yml.bak" >> "$BASE_DIR/docker-compose.yml";;
    esac
done
}

ensure_root
install_docker
create_dirs
write_env
write_compose
cp "$BASE_DIR/docker-compose.yml" "$BASE_DIR/docker-compose.yml.bak"
menu
firewall
echo "Setup complete. Run: cd $BASE_DIR && docker compose up -d"
