#!/bin/bash

# ===============================
# Flash Tool 2 (BTT EBB36)
# ===============================

# Define the paths
PASSWORD_FILE="/home/biqu/printer_data/config/.system_pass.txt"
SERIAL_FILE="/home/biqu/printer_data/config/02__Boards_Serials/Tool2_serial.cfg"
CONFIG_FILE="/home/biqu/printer_data/config/0_Xplorer/.9_MCU_Flash/MCU_config/BTT_EBB36/.config"
KLIPPER_DIR="/home/biqu/klipper"

echo "=== MCU Flash Script (Tool 2 / BTT EBB36) ==="

# Check if the password file exists
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "ERROR: Password file $PASSWORD_FILE does not exist!"
    exit 1
fi
PASSWORD=$(cat "$PASSWORD_FILE")

# Check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file $CONFIG_FILE does not exist!"
    exit 1
fi

# -------------------------------
# Extract SERIAL_ID (Robust method)
# -------------------------------
if [ ! -f "$SERIAL_FILE" ]; then
    echo "ERROR: Serial file $SERIAL_FILE does not exist!"
    exit 1
fi

SERIAL_LINE=$(grep -E '^[[:space:]]*serial\s*:' "$SERIAL_FILE" | head -n 1)
if [ -z "$SERIAL_LINE" ]; then
    echo "ERROR: Could not find a 'serial:' line in $SERIAL_FILE!"
    exit 1
fi

SERIAL_ID=$(echo "$SERIAL_LINE" | cut -d':' -f2- | xargs)
if [ -z "$SERIAL_ID" ]; then
    echo "ERROR: Could not extract SERIAL_ID!"
    exit 1
fi

echo "Using SERIAL_ID: $SERIAL_ID"

# -------------------------------
# Prepare Klipper build
# -------------------------------
# Take the config suited for this toolboard
cp -f "$CONFIG_FILE" "$KLIPPER_DIR/.config"

cd "$KLIPPER_DIR" || exit 1

echo "Cleaning and building firmware..."
make olddefconfig || exit 1
make clean || exit 1
make || exit 1

# -------------------------------
# Flash firmware
# -------------------------------
echo "Flashing the firmware to $SERIAL_ID..."

# Flash the firmware with sudo
echo "$PASSWORD" | sudo -S make flash FLASH_DEVICE="$SERIAL_ID"
FLASH_RESULT=$?

if [ $FLASH_RESULT -ne 0 ]; then
    echo "ERROR: make flash failed with exit code $FLASH_RESULT"
    exit $FLASH_RESULT
fi

echo "Waiting for the EBB36 board to initialize..."
sleep 3

# Restart doar la serviciul Klipper, NU tot sistemul
echo "Restarting Klipper service..."
echo "$PASSWORD" | sudo -S systemctl restart klipper

echo "Firmware flashing complete."
