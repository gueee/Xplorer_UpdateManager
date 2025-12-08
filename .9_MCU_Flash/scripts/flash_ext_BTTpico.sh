
#!/bin/bash

# ===============================
# Flash Extension Board (BTT Pico)
# ===============================

# Path to the password file (for sudo)
PASSWORD_FILE="/home/biqu/printer_data/config/.system_pass.txt"

# Path to the serial file and klipper config template
SERIAL_FILE="/home/biqu/printer_data/config/02__Boards_Serials/Extension_serial.cfg"
CONFIG_FILE="/home/biqu/printer_data/config/0_Xplorer/.9_MCU_Flash/MCU_config/BTT_Pico/.config"
KLIPPER_DIR="/home/biqu/klipper"

echo "=== MCU Flash Script (Extension / BTT Pico) ==="

# -------------------------------
# Check password file
# -------------------------------
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "ERROR: Password file $PASSWORD_FILE does not exist!"
    exit 1
fi

PASSWORD=$(cat "$PASSWORD_FILE")

# -------------------------------
# Check config file
# -------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file $CONFIG_FILE does not exist!"
    exit 1
fi

# -------------------------------
# Extract SERIAL_ID
# Supports both:
#   serial:/dev/serial/by-id/...
#   serial: /dev/serial/by-id/...
# -------------------------------
if [ ! -f "$SERIAL_FILE" ]; then
    echo "ERROR: Serial file $SERIAL_FILE does not exist!"
    exit 1
fi

# Get the line that contains "serial:" (ignoring comments)
SERIAL_LINE=$(grep -E '^[[:space:]]*serial\s*:' "$SERIAL_FILE" | head -n 1)

if [ -z "$SERIAL_LINE" ]; then
    echo "ERROR: Could not find a 'serial:' line in $SERIAL_FILE!"
    exit 1
fi

# Take everything after the first ':' and trim whitespace
SERIAL_ID=$(echo "$SERIAL_LINE" | cut -d':' -f2- | xargs)

if [ -z "$SERIAL_ID" ]; then
    echo "ERROR: Could not extract SERIAL_ID from line:"
    echo "       $SERIAL_LINE"
    exit 1
fi

echo "Using SERIAL_ID: $SERIAL_ID"

# -------------------------------
# Prepare Klipper build
# -------------------------------
if [ ! -d "$KLIPPER_DIR" ]; then
    echo "ERROR: Klipper directory $KLIPPER_DIR does not exist!"
    exit 1
fi

# Copy the prepared .config for the BTT Pico to Klipper
cp -f "$CONFIG_FILE" "$KLIPPER_DIR/.config"

cd "$KLIPPER_DIR" || {
    echo "ERROR: Failed to cd into $KLIPPER_DIR"
    exit 1
}

echo "Running: make olddefconfig"
make olddefconfig || {
    echo "ERROR: make olddefconfig failed!"
    exit 1
}

echo "Running: make clean"
make clean || {
    echo "ERROR: make clean failed!"
    exit 1
}

echo "Running: make"
make || {
    echo "ERROR: make failed!"
    exit 1
}

# -------------------------------
# Flash firmware
# -------------------------------
echo "Flashing the firmware to $SERIAL_ID ..."

# If you want to stop Klipper via sudo, uncomment this:
# echo "$PASSWORD" | sudo -S service klipper stop

# Flash using sudo and the extracted SERIAL_ID
echo "$PASSWORD" | sudo -S make flash FLASH_DEVICE="$SERIAL_ID"
FLASH_RESULT=$?

if [ $FLASH_RESULT -ne 0 ]; then
    echo "ERROR: make flash failed with exit code $FLASH_RESULT"
    exit $FLASH_RESULT
fi

sleep 5

# Restart Klipper (adjust to your system if sudo is needed)
service klipper restart || {
    echo "WARNING: Failed to restart klipper service via 'service klipper restart'"
    # Not exiting hard here, flashing already succeeded
}

echo "Firmware flashing complete."
