#!/bin/bash
# Cut the printer over from the Manta M8P v2 (UART) to the BTT Octopus V1.1 (USB).
# Run ON THE PRINTER, after the Octopus is wired in and flashed with Klipper.
#
# Usage:
#   bash scripts/octopus_cutover.sh              # apply
#   bash scripts/octopus_cutover.sh --dry-run    # show what would change
#
# Idempotent: safe to re-run.

set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

CONFIG="${HOME}/printer_data/config"
SERIAL_FILE="${CONFIG}/02__Boards_Serials/Mainboard_serial.cfg"
CROWSNEST="${CONFIG}/crowsnest.conf"
STAMP="$(date +%Y%m%d_%H%M%S)"

say() { echo "==> $*"; }

# -------------------------------------------------------------------
# 1. Backup
# -------------------------------------------------------------------
BACKUP="${HOME}/config_backup_pre_octopus_${STAMP}.tar.gz"
if [ "$DRY_RUN" -eq 0 ]; then
    tar czf "$BACKUP" -C "$(dirname "$CONFIG")" "$(basename "$CONFIG")"
    say "Backed up config to $BACKUP"
else
    say "[dry-run] would back up $CONFIG"
fi

# -------------------------------------------------------------------
# 2. Locate the Octopus
# -------------------------------------------------------------------
OCTO=""
for d in /dev/serial/by-id/usb-Klipper_stm32f446xx_*-if00; do
    [ -e "$d" ] && OCTO="$d" && break
done

if [ -z "$OCTO" ]; then
    echo "ERROR: no stm32f446xx Klipper device under /dev/serial/by-id/."
    echo "Present devices:"
    ls -1 /dev/serial/by-id/ 2>/dev/null || echo "  (none)"
    echo
    echo "Flash the Octopus first:"
    echo "  bash ~/printer_data/config/0_Xplorer/.9_MCU_Flash/scripts/flash_M1_BTTOctopusV11.sh --build"
    echo "  (copy out/klipper.bin to a FAT32 card as firmware.bin, power-cycle the board)"
    exit 1
fi
say "Found Octopus: $OCTO"

# -------------------------------------------------------------------
# 3. Point [mcu] at the Octopus over USB
# -------------------------------------------------------------------
NEW_SERIAL_CFG="[mcu]
# BTT Octopus V1.1 (stm32f446) over USB.
# The M8P v2 UART build is kept in Mainboard_serial.cfg.uartbak for reference.
serial: ${OCTO}
restart_method: command
"

if [ "$DRY_RUN" -eq 0 ]; then
    if [ -f "$SERIAL_FILE" ] && ! [ -f "${SERIAL_FILE}.uartbak" ]; then
        cp -a "$SERIAL_FILE" "${SERIAL_FILE}.uartbak"
        say "Saved previous mainboard serial to ${SERIAL_FILE}.uartbak"
    fi
    printf '%s' "$NEW_SERIAL_CFG" > "$SERIAL_FILE"
    say "Wrote $SERIAL_FILE"
else
    say "[dry-run] would write $SERIAL_FILE:"
    printf '%s' "$NEW_SERIAL_CFG" | sed 's/^/      /'
fi

# -------------------------------------------------------------------
# 4. Camera wiring in crowsnest
# -------------------------------------------------------------------
NOZZLE_CAM=""
for d in /dev/v4l/by-id/*-video-index0; do
    [ -e "$d" ] && NOZZLE_CAM="$d" && break
done

if [ -z "$NOZZLE_CAM" ]; then
    say "WARNING: no USB camera found under /dev/v4l/by-id/ - skipping crowsnest"
elif [ ! -f "$CROWSNEST" ]; then
    say "WARNING: $CROWSNEST not found - skipping"
else
    say "Nozzle camera: $NOZZLE_CAM"
    if [ "$DRY_RUN" -eq 0 ] && ! [ -f "${CROWSNEST}.pre_octopus" ]; then
        cp -a "$CROWSNEST" "${CROWSNEST}.pre_octopus"
    fi
    DRY_RUN="$DRY_RUN" NOZZLE_CAM="$NOZZLE_CAM" CROWSNEST="$CROWSNEST" python3 - <<'PYEOF'
import os, re

path = os.environ['CROWSNEST']
cam = os.environ['NOZZLE_CAM']
dry = os.environ['DRY_RUN'] == '1'

lines = open(path).read().split('\n')
changed = []

# Section spans: (name, start, end) where name is None for non-cam sections
heads = [i for i, l in enumerate(lines) if re.match(r'\s*#?\s*\[', l)]
spans = []
for n, start in enumerate(heads):
    end = heads[n + 1] if n + 1 < len(heads) else len(lines)
    spans.append((start, end))

for start, end in spans:
    head = lines[start]
    if head.lstrip().startswith('#'):
        continue                      # already disabled
    m = re.match(r'\s*\[cam\s+(\S+)\]', head)
    if not m:
        continue
    name = m.group(1)
    dev_idx = dev = None
    for i in range(start, end):
        dm = re.match(r'(\s*)device:(\s*)(\S+)(.*)', lines[i])
        if dm:
            dev_idx, dev = i, dm.group(3)
            break
    if dev is None:
        continue
    if name == 'nozzle':
        if dev != cam:
            lines[dev_idx] = re.sub(r'(device:\s*)\S+', lambda x: x.group(1) + cam,
                                    lines[dev_idx], count=1)
            changed.append('  [cam nozzle] device -> %s' % cam)
    elif dev.startswith('/dev/') and not os.path.exists(dev):
        for i in range(start, end):
            if lines[i].strip():
                lines[i] = '#' + lines[i]
        changed.append('  [cam %s] disabled (device %s does not exist)' % (name, dev))

if not changed:
    print('==> crowsnest already correct')
elif dry:
    print('==> [dry-run] crowsnest changes:')
    print('\n'.join(changed))
else:
    open(path, 'w').write('\n'.join(lines))
    print('==> crowsnest updated:')
    print('\n'.join(changed))
PYEOF
fi

# -------------------------------------------------------------------
# 5. Restart
# -------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
    say "Restarting klipper + crowsnest"
    sudo systemctl restart klipper crowsnest || true
    sleep 6
    say "Klipper state:"
    curl -s -m5 http://localhost:7125/printer/info || true
    echo
else
    say "[dry-run] would restart klipper + crowsnest"
fi

cat <<'EOF'

Next steps (see the bring-up checklist):
  QUERY_ENDSTOPS                 - verify y/z/z1/z2 before any motion
  FORCE_MOVE / direction check   - one axis at a time
  G28 then Z_TILT_ADJUST
  Cartographer touch + scan calibration, then BED_MESH_CALIBRATE
  NOZZLE_CAM_CALIBRATE_OFFSETS   - or AUTO_CALIBRATE_tool_offsets
EOF
