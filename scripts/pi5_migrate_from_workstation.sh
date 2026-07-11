#!/bin/bash
# Run on the WORKSTATION after `pi5_bootstrap.sh` completed on the Pi.
# Pushes the staged (biqu->gueee rewritten) config, klippy extras, runs the
# fork sync, installs kTAMV, restarts services.
#
# Usage: bash scripts/pi5_migrate_from_workstation.sh [STAGE_DIR] [HOST]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${1:?pass the staged config dir (rewritten cb2_backup copy)}"
HOST="${2:-xpi}"

echo "==> Push printer_data/config"
rsync -a "$STAGE/config/" "$HOST:printer_data/config/"

echo "==> Push klippy extras"
scp "$REPO/Assets/cb2_backup/config/extracted_from_image/xplorer.py" \
    "$REPO/Assets/cb2_backup/config/extracted_from_image/gcode_shell_command.py" \
    "$REPO/.7_XP_modules/tools_calibrate.py" \
    "$REPO/.7_XP_modules/trsync_patch.py" \
    "$HOST:klipper/klippy/extras/"

echo "==> Push and run fork pull+sync on printer"
scp "$REPO/scripts/printer_pull_fork_and_sync.sh" "$REPO/scripts/sync_fork_to_printer_config.sh" "$HOST:"
ssh "$HOST" 'bash ~/printer_pull_fork_and_sync.sh || bash ~/sync_fork_to_printer_config.sh ~/Xplorer_UpdateManager ~/printer_data/config'

echo "==> Install kTAMV (klippy module + server service)"
ssh "$HOST" '
set -e
if [ ! -d ~/kTAMV ]; then git clone https://github.com/TypQxQ/kTAMV.git ~/kTAMV; fi
cd ~/kTAMV && bash install.sh || true
'

echo "==> Restart services"
ssh "$HOST" 'sudo systemctl restart klipper moonraker; sudo systemctl restart crowsnest || true'

echo "==> Status"
ssh "$HOST" 'systemctl --no-pager --plain status klipper moonraker crowsnest 2>/dev/null | grep -E "\.service|Active:"'
