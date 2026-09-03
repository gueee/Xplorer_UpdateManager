#!/bin/bash
#############################################################################
# Xplorer Pi 5 Bootstrap — installs the full Klipper host stack on a fresh
# Raspberry Pi OS (Bookworm) after the CM4 -> Pi 5 swap.
#
# Run ON the Pi as the normal user (gueee):
#   bash pi5_bootstrap.sh
#
# Installs: Klipper, Moonraker, Mainsail (+nginx), mainsail-config,
# Crowsnest, Sonar, moonraker-timelapse, print_area_bed_mesh,
# Cartographer plugin (pip into klippy-env).
# KlipperScreen and Obico are intentionally NOT installed here.
#############################################################################
set -e

USER_NAME="$(whoami)"
HOME_DIR="$HOME"
PD="$HOME_DIR/printer_data"

log() { echo -e "\n=== $* ==="; }

log "APT dependencies"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git python3-virtualenv python3-dev libffi-dev build-essential \
  libncurses-dev libusb-dev libusb-1.0-0-dev pkg-config \
  avrdude gcc-avr binutils-avr avr-libc \
  stm32flash dfu-util libnewlib-arm-none-eabi \
  gcc-arm-none-eabi binutils-arm-none-eabi \
  nginx wget unzip policykit-1 rsync mpg123

mkdir -p "$PD"/{config,logs,gcodes,systemd,comms,database}

# ---------------------------------------------------------------- Klipper
if [ ! -d "$HOME_DIR/klipper" ]; then
  log "Klipper"
  git clone https://github.com/Klipper3d/klipper "$HOME_DIR/klipper"
fi
if [ ! -d "$HOME_DIR/klippy-env" ]; then
  virtualenv -p python3 "$HOME_DIR/klippy-env"
  "$HOME_DIR/klippy-env/bin/pip" install -r "$HOME_DIR/klipper/scripts/klippy-requirements.txt"
fi

cat > "$PD/systemd/klipper.env" <<EOF
KLIPPER_ARGS="$HOME_DIR/klipper/klippy/klippy.py $PD/config/printer.cfg -l $PD/logs/klippy.log -I $PD/comms/klippy.serial -a $PD/comms/klippy.sock"
EOF

sudo tee /etc/systemd/system/klipper.service > /dev/null <<EOF
[Unit]
Description=Klipper 3D Printer Firmware SV1
Documentation=https://www.klipper3d.org/
After=network-online.target
Wants=udev.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
User=$USER_NAME
RemainAfterExit=yes
WorkingDirectory=$HOME_DIR/klipper
EnvironmentFile=$PD/systemd/klipper.env
ExecStart=$HOME_DIR/klippy-env/bin/python \$KLIPPER_ARGS
Restart=always
RestartSec=10
EOF
sudo systemctl daemon-reload
sudo systemctl enable klipper.service

# --------------------------------------------------------------- Moonraker
if [ ! -d "$HOME_DIR/moonraker" ]; then
  log "Moonraker"
  git clone https://github.com/Arksine/moonraker "$HOME_DIR/moonraker"
  "$HOME_DIR/moonraker/scripts/install-moonraker.sh" -d "$PD"
fi

# ---------------------------------------------------------------- Mainsail
if [ ! -d "$HOME_DIR/mainsail" ]; then
  log "Mainsail"
  mkdir -p "$HOME_DIR/mainsail"
  wget -q -O /tmp/mainsail.zip https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip
  unzip -o /tmp/mainsail.zip -d "$HOME_DIR/mainsail"
fi
if [ ! -d "$HOME_DIR/mainsail-config" ]; then
  git clone https://github.com/mainsail-crew/mainsail-config.git "$HOME_DIR/mainsail-config"
  ln -sf "$HOME_DIR/mainsail-config/client.cfg" "$PD/config/mainsail.cfg" 2>/dev/null || true
fi

log "nginx site for Mainsail"
sudo tee /etc/nginx/conf.d/upstreams.conf > /dev/null <<'EOF'
upstream apiserver { ip_hash; server 127.0.0.1:7125; }
upstream mjpgstreamer1 { ip_hash; server 127.0.0.1:8080; }
upstream mjpgstreamer2 { ip_hash; server 127.0.0.1:8081; }
upstream mjpgstreamer3 { ip_hash; server 127.0.0.1:8082; }
upstream mjpgstreamer4 { ip_hash; server 127.0.0.1:8083; }
EOF
sudo tee /etc/nginx/sites-available/mainsail > /dev/null <<EOF
map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }
server {
    listen 80 default_server;
    access_log /var/log/nginx/mainsail-access.log;
    error_log /var/log/nginx/mainsail-error.log;
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
    root $HOME_DIR/mainsail;
    index index.html;
    server_name _;
    client_max_body_size 0;
    proxy_request_buffering off;
    location / { try_files \$uri \$uri/ /index.html; }
    location = /index.html { add_header Cache-Control "no-store, no-cache, must-revalidate"; }
    location /websocket {
        proxy_pass http://apiserver/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }
    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://apiserver\$request_uri;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Scheme \$scheme;
    }
    location /webcam/ { postpone_output 0; proxy_buffering off; proxy_ignore_headers X-Accel-Buffering; access_log off; error_log off; proxy_pass http://mjpgstreamer1/; }
    location /webcam2/ { postpone_output 0; proxy_buffering off; proxy_ignore_headers X-Accel-Buffering; access_log off; error_log off; proxy_pass http://mjpgstreamer2/; }
}
EOF
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
sudo systemctl restart nginx

# --------------------------------------------------------------- Crowsnest
if [ ! -d "$HOME_DIR/crowsnest" ]; then
  log "Crowsnest"
  git clone https://github.com/mainsail-crew/crowsnest.git "$HOME_DIR/crowsnest"
  cd "$HOME_DIR/crowsnest"
  sudo CROWSNEST_UNATTENDED=1 CROWSNEST_USER="$USER_NAME" make install
  cd "$HOME_DIR"
fi

# ------------------------------------------------------------------- Sonar
if [ ! -d "$HOME_DIR/sonar" ]; then
  log "Sonar"
  git clone https://github.com/mainsail-crew/sonar.git "$HOME_DIR/sonar"
  cd "$HOME_DIR/sonar"
  sudo SONAR_UNATTENDED=1 make install || echo "Sonar install returned nonzero, continuing"
  cd "$HOME_DIR"
fi

# --------------------------------------------------------------- Timelapse
if [ ! -d "$HOME_DIR/moonraker-timelapse" ]; then
  log "moonraker-timelapse"
  git clone https://github.com/mainsail-crew/moonraker-timelapse.git "$HOME_DIR/moonraker-timelapse"
  cd "$HOME_DIR/moonraker-timelapse"
  make install || bash install.sh || true
  cd "$HOME_DIR"
fi

# ---------------------------------------------------- print_area_bed_mesh
if [ ! -d "$HOME_DIR/print_area_bed_mesh" ]; then
  log "print_area_bed_mesh"
  git clone https://github.com/Turge08/print_area_bed_mesh.git "$HOME_DIR/print_area_bed_mesh"
fi
ln -sf "$HOME_DIR/print_area_bed_mesh/print_area_bed_mesh.py" "$HOME_DIR/klipper/klippy/extras/print_area_bed_mesh.py"

# ------------------------------------------------------------ Cartographer
log "Cartographer plugin"
"$HOME_DIR/klippy-env/bin/pip" install cartographer3d-plugin
echo 'from cartographer.extra import *' > "$HOME_DIR/klipper/klippy/extras/cartographer.py"

log "Bootstrap done. Next: restore configs, install Xplorer extras, start services."
