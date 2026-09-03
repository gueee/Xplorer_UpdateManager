#!/usr/bin/env bash
# Run on the Pi: installs the vc4 modesetting X config and restarts KlipperScreen.
set -e
SRC="$HOME/printer_data/config/0_Xplorer/_deploy/99-vc4.conf"
[ -f "$SRC" ] || SRC="$HOME/99-vc4.conf"
sudo install -D -m 644 "$SRC" /etc/X11/xorg.conf.d/99-vc4.conf
sudo systemctl restart KlipperScreen
sleep 6
systemctl status KlipperScreen --no-pager | head -5
tail -5 "$HOME/printer_data/logs/KlipperScreen.log" 2>/dev/null || true
