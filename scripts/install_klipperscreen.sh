#!/usr/bin/env bash
# One-shot KlipperScreen install for the Pi 5 / BTT HDMI5. Needs your sudo password.
# X11 backend, systemd service, no NetworkManager reinstall (already running), start when done.
set -e
cd "$HOME/KlipperScreen"
export SERVICE=Y BACKEND=X NETWORK=n START=1
sudo -v
bash scripts/KlipperScreen-install.sh
sudo systemctl disable --now getty@tty1 || true
echo; systemctl status KlipperScreen --no-pager | head -5
