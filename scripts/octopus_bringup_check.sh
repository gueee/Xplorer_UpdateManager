#!/bin/bash
# Verification helper for the Octopus V1.1 bring-up. Run ON THE PRINTER.
# Read-only: queries Moonraker, sends no motion commands.
#
# Usage: bash scripts/octopus_bringup_check.sh

API="http://localhost:7125"

jq_or_raw() { python3 -c "import sys,json;d=json.load(sys.stdin);print(json.dumps(d,indent=2))" 2>/dev/null || cat; }

echo "=============================================="
echo " Octopus V1.1 bring-up check"
echo "=============================================="

echo
echo "--- Klipper state ---"
curl -s -m5 "${API}/printer/info" | jq_or_raw

echo
echo "--- USB devices seen by the host ---"
ls -1 /dev/serial/by-id/ 2>/dev/null || echo "  (none)"

echo
echo "--- Configured MCU serials ---"
grep -rn -A2 '^\[mcu' "${HOME}/printer_data/config/02__Boards_Serials/" 2>/dev/null \
    | grep -E '\[mcu|serial:' || echo "  (none found)"

echo
echo "--- MCU versions reported by Klipper ---"
curl -s -m5 -G "${API}/printer/objects/query" --data-urlencode 'mcu' | jq_or_raw

echo
echo "--- Endstops (QUERY_ENDSTOPS) ---"
curl -s -m5 -X POST -G "${API}/printer/gcode/script" \
     --data-urlencode 'script=QUERY_ENDSTOPS' >/dev/null
curl -s -m5 -G "${API}/printer/objects/query" --data-urlencode 'query_endstops' | jq_or_raw

echo
echo "--- TMC driver status ---"
for s in stepper_x dual_carriage stepper_y stepper_y1 stepper_z stepper_z1 stepper_z2; do
    echo "  DUMP_TMC STEPPER=$s"
    curl -s -m5 -X POST -G "${API}/printer/gcode/script" \
         --data-urlencode "script=DUMP_TMC STEPPER=$s" >/dev/null
done
echo "  (results land in the Mainsail console / klippy.log)"

cat <<'EOF'

==============================================
 Manual checklist - do these in order
==============================================
 1. All DIAG jumpers removed from the Octopus
 2. QUERY_ENDSTOPS above shows y/z/z1/z2 as "open", and each
    flips to "TRIGGERED" when pressed by hand
 3. Direction check, ONE axis at a time, machine on blocks:
       FORCE_MOVE STEPPER=stepper_x DISTANCE=10 VELOCITY=20
    Add or remove the '!' on that stepper's dir_pin if it runs backwards
 4. G28 X, G28 Y, G28 Z
 5. Z_TILT_ADJUST
 6. Cartographer: touch calibration, then scan calibration
 7. BED_MESH_CALIBRATE
 8. NOZZLE_CAM_CALIBRATE_OFFSETS  (or AUTO_CALIBRATE_tool_offsets)
 9. Re-run input shaper for both carriages
EOF
