#!/bin/bash
#############################################################################
# Xplorer Printer Full Setup Script
# Recreates the Formbot Xplorer image setup from a stock Klipper/Mainsail OS
#
# Usage: scp this entire extracted_from_image folder to the printer, then:
#   chmod +x install_xplorer.sh
#   ./install_xplorer.sh
#
# Run from: /home/biqu/printer_data/config/  (or adjust paths)
#############################################################################

set -e

CONFIG_DIR="$HOME/printer_data/config"
KLIPPER_EXTRAS="$HOME/klipper/klippy/extras"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  Xplorer Printer Setup"
echo "=========================================="
echo ""
echo "Config dir: $CONFIG_DIR"
echo "Source dir:  $SCRIPT_DIR"
echo ""

# -------------------------------------------------------------------
# 1. Clone the Xplorer Update Manager repo
# -------------------------------------------------------------------
if [ ! -d "$CONFIG_DIR/0_Xplorer" ]; then
    echo "[1/8] Cloning Xplorer Update Manager repo..."
    git clone https://github.com/FORMBOT/Xplorer_UpdateManager.git "$CONFIG_DIR/0_Xplorer"
else
    echo "[1/8] 0_Xplorer already exists, pulling latest..."
    cd "$CONFIG_DIR/0_Xplorer" && git pull && cd "$CONFIG_DIR"
fi

# -------------------------------------------------------------------
# 2. Install custom Klipper extras
# -------------------------------------------------------------------
echo "[2/8] Installing custom Klipper extras..."
cp "$SCRIPT_DIR/xplorer.py" "$KLIPPER_EXTRAS/xplorer.py"
cp "$SCRIPT_DIR/gcode_shell_command.py" "$KLIPPER_EXTRAS/gcode_shell_command.py"
echo "  -> xplorer.py installed"
echo "  -> gcode_shell_command.py installed"

# -------------------------------------------------------------------
# 3. Create directory structure
# -------------------------------------------------------------------
echo "[3/8] Creating directory structure..."
mkdir -p "$CONFIG_DIR/02__Boards_Serials"
mkdir -p "$CONFIG_DIR/01__User_Custom__CFG"
mkdir -p "$CONFIG_DIR/03_Resonances_Measurments"
mkdir -p "$CONFIG_DIR/.10__Audio"

# -------------------------------------------------------------------
# 4. Create board serial template files (user must fill in serials)
# -------------------------------------------------------------------
echo "[4/8] Creating board serial templates..."

create_serial_if_missing() {
    local file="$1"
    local mcu_name="$2"
    local mcu_section="$3"
    if [ ! -f "$CONFIG_DIR/02__Boards_Serials/$file" ]; then
        cat > "$CONFIG_DIR/02__Boards_Serials/$file" << SERIALEOF
[$mcu_section]

# Replace the serial below with your actual board serial from: ls /dev/serial/by-id/

serial: /dev/serial/by-id/usb-Klipper_stm32xxxxx_REPLACE_WITH_YOUR_SERIAL
SERIALEOF
        echo "  -> Created $file (NEEDS YOUR SERIAL!)"
    else
        echo "  -> $file already exists, skipping"
    fi
}

create_serial_if_missing "Mainboard_serial.cfg" "mainboard" "mcu"
create_serial_if_missing "Tool0_serial.cfg" "Tool0" "mcu Tool0"
create_serial_if_missing "Tool1_serial.cfg" "Tool1" "mcu Tool1"
create_serial_if_missing "Tool2_serial.cfg" "Tool2" "mcu Tool2"
create_serial_if_missing "Tool3_serial.cfg" "Tool3" "mcu Tool3"
create_serial_if_missing "Extension_serial.cfg" "ext" "mcu ext"

# -------------------------------------------------------------------
# 5. Copy audio files
# -------------------------------------------------------------------
echo "[5/8] Copying audio files..."
if [ -d "$SCRIPT_DIR/.10__Audio" ]; then
    cp "$SCRIPT_DIR/.10__Audio/"*.mp3 "$CONFIG_DIR/.10__Audio/" 2>/dev/null && echo "  -> Audio files copied" || echo "  -> No audio files found"
else
    echo "  -> No .10__Audio source folder, skipping"
fi

# -------------------------------------------------------------------
# 6. Create variables.cfg with defaults
# -------------------------------------------------------------------
echo "[6/8] Creating variables.cfg..."
if [ ! -f "$CONFIG_DIR/variables.cfg" ]; then
    cat > "$CONFIG_DIR/variables.cfg" << 'VARSEOF'
[Variables]
bp_zoff = 0.85
h_brush = 0.0
mesh_tmp = 85
pmode = 0
shaper_freq_xidexcp = 50.8
shaper_freq_xidexmr = 61.6
shaper_freq_xt0 = 98.8
shaper_freq_xt1 = 55.0
shaper_freq_xt2 = 56.6
shaper_freq_xt3 = 56.6
shaper_freq_yidexcp = 45.4
shaper_freq_yidexmr = 45.6
shaper_freq_yt0 = 44.2
shaper_freq_yt1 = 69.2
shaper_freq_yt2 = 43.2
shaper_freq_yt3 = 43.2
shaper_type_xidexcp = 'mzv'
shaper_type_xidexmr = 'mzv'
shaper_type_xt0 = '3hump_ei'
shaper_type_xt1 = 'mzv'
shaper_type_xt2 = 'mzv'
shaper_type_xt3 = 'mzv'
shaper_type_yidexcp = 'mzv'
shaper_type_yidexmr = 'mzv'
shaper_type_yt0 = 'mzv'
shaper_type_yt1 = '2hump_ei'
shaper_type_yt2 = 'mzv'
shaper_type_yt3 = 'mzv'
tprobe = 170
ttovr = 0
x1offset = 0.0
x2offset = 0.0
x3offset = 0.0
xy_resume = 1
y1offset = 0.0
y2offset = 0.0
y3offset = 0.0
z1offset = 0.0
z2offset = 0.0
z3offset = 0.0
VARSEOF
    echo "  -> variables.cfg created with defaults"
else
    echo "  -> variables.cfg already exists, skipping"
fi

# -------------------------------------------------------------------
# 7. Create system password file
# -------------------------------------------------------------------
echo "[7/8] Creating system password file..."
if [ ! -f "$CONFIG_DIR/.system_pass.txt" ]; then
    echo -n "biqu" > "$CONFIG_DIR/.system_pass.txt"
    echo "  -> .system_pass.txt created"
else
    echo "  -> .system_pass.txt already exists, skipping"
fi

# -------------------------------------------------------------------
# 8. Setup moonraker.conf with Update Manager
# -------------------------------------------------------------------
echo "[8/8] Checking moonraker.conf..."
if ! grep -q "update_manager Xplorer" "$CONFIG_DIR/moonraker.conf" 2>/dev/null; then
    cat >> "$CONFIG_DIR/moonraker.conf" << 'MOONEOF'

[update_manager Xplorer]
type: git_repo
primary_branch: main
path: /home/biqu/printer_data/config/0_Xplorer/
origin: https://github.com/FORMBOT/Xplorer_UpdateManager.git
managed_services: klipper
MOONEOF
    echo "  -> Added [update_manager Xplorer] to moonraker.conf"
else
    echo "  -> moonraker.conf already has Xplorer update manager entry"
fi

# -------------------------------------------------------------------
# Install print_area_bed_mesh if not present
# -------------------------------------------------------------------
if [ ! -d "$HOME/print_area_bed_mesh" ]; then
    echo ""
    echo "[Extra] Installing print_area_bed_mesh..."
    git clone https://github.com/Turge08/print_area_bed_mesh.git "$HOME/print_area_bed_mesh"
    ln -sf "$HOME/print_area_bed_mesh/print_area_bed_mesh.cfg" "$CONFIG_DIR/print_area_bed_mesh.cfg"
fi

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT - You still need to:"
echo ""
echo "  1. Copy the right printer.cfg for your variant:"
echo "     cp $CONFIG_DIR/0_Xplorer/02_Printer_cfg/XP1.1__IDEX_printer.cfg $CONFIG_DIR/printer.cfg"
echo "     (or SINGLE, 2xGantry, IQEX variant)"
echo ""
echo "  2. Fill in your board serials in $CONFIG_DIR/02__Boards_Serials/"
echo "     Run: ls /dev/serial/by-id/ to find your serials"
echo ""
echo "  3. Import Mainsail settings from the UI:"
echo "     File is at: 0_Xplorer/07_Mainsail_Settings/backup-mainsail_*.json"
echo ""
echo "  4. Restart Klipper and Moonraker:"
echo "     sudo systemctl restart klipper moonraker"
echo ""
echo "  5. Run resonance calibration after first boot"
echo "     (the default shaper values are from the image, not your printer)"
echo ""
