#!/bin/bash
# FINISH the CM4->Pi5 migration. Run from the WORKSTATION once SSH key access
# to `xpi` (gueee@192.168.1.90) works. The Pi already runs MainsailOS 3.0.0
# (Klipper/Moonraker/Mainsail/Crowsnest/Sonar installed); configs were already
# pushed over the Moonraker HTTP API. This installs the remaining klippy extras,
# reconciles the Cartographer plugin, installs kTAMV, and restarts.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-xpi}"
EXTRACT="$REPO/Assets/cb2_backup/config/extracted_from_image"

echo "==> 1/5 Push klippy extras (tools_calibrate, trsync_patch, xplorer, gcode_shell_command)"
scp "$REPO/.7_XP_modules/tools_calibrate.py" \
    "$REPO/.7_XP_modules/trsync_patch.py" \
    "$EXTRACT/xplorer.py" \
    "$EXTRACT/gcode_shell_command.py" \
    "$HOST:klipper/klippy/extras/"

echo "==> 2/5 Reconcile Cartographer plugin (saved config = Cartographer HT 5.1.0 / survey)"
ssh "$HOST" '
set -e
echo "--- installed cartographer extra head ---"; head -3 ~/klipper/klippy/extras/cartographer.py 2>/dev/null || echo "no cartographer.py extra"
echo "--- klippy-env cartographer package ---"; ~/klippy-env/bin/pip show cartographer3d-plugin 2>/dev/null | head -2 || echo "cartographer3d-plugin NOT installed via pip"
# Install/upgrade the survey plugin that matches the saved touch_model/scan_model (HT 5.1.0)
~/klippy-env/bin/pip install --upgrade cartographer3d-plugin
# Ensure the extras shim points at the pip package
echo "from cartographer.extra import *" > ~/klipper/klippy/extras/cartographer.py
'

echo "==> 3/5 Install kTAMV (nozzle alignment camera)"
ssh "$HOST" '
set -e
[ -d ~/kTAMV ] || git clone https://github.com/TypQxQ/kTAMV.git ~/kTAMV
cd ~/kTAMV && bash install.sh || echo "kTAMV install.sh returned nonzero — check output"
'

echo "==> 4/5 Ensure fork clone + run config sync (0_Xplorer default cfgs, _deploy overlays)"
ssh "$HOST" '
set -e
[ -d ~/Xplorer_UpdateManager/.git ] || git clone --depth 1 -b main https://github.com/gueee/Xplorer_UpdateManager.git ~/Xplorer_UpdateManager
cd ~/Xplorer_UpdateManager && git pull --ff-only || true
bash ~/Xplorer_UpdateManager/scripts/sync_fork_to_printer_config.sh ~/Xplorer_UpdateManager ~/printer_data/config
'

echo "==> 5/5 Verify MCU serials on the new powered USB hub, then restart"
ssh "$HOST" '
echo "--- /dev/serial/by-id/ ---"; ls -1 /dev/serial/by-id/ 2>/dev/null || echo "none"
echo "--- expected (02__Boards_Serials) ---"; grep -h "serial:" ~/printer_data/config/02__Boards_Serials/*.cfg 2>/dev/null
sudo systemctl restart klipper moonraker crowsnest || true
'
sleep 6
echo "==> Klipper state:"
curl -s -m5 http://192.168.1.90:7125/printer/info | python3 -c "import sys,json;d=json.load(sys.stdin)['result'];print(d['state']);print(d['state_message'][:400])" 2>/dev/null || true

echo
echo "If serials differ from the expected list above, update ~/printer_data/config/02__Boards_Serials/*.cfg and RESTART."
echo "Then run tool-offset calibration AT THE PRINTER: NOZZLE_CAM_CALIBRATE_OFFSETS (camera XY) or AUTO_CALIBRATE_tool_offsets (contact probe)."
