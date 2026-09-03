#!/bin/bash

# ===============================
# Flash Mainboard (BTT Octopus V1.1 / STM32F446)
# ===============================
#
# Usage:
#   flash_M1_BTTOctopusV11.sh                 build + flash, auto-detecting the board
#   flash_M1_BTTOctopusV11.sh --build         build only, no flash
#   flash_M1_BTTOctopusV11.sh --device DEV    flash a specific device
#                                             (a /dev path, or 0483:df11 for raw DFU)
#
# Device detection order:
#   1. --device argument
#   2. /dev/serial/by-id/*stm32f446xx*   Klipper already on the board
#   3. /dev/serial/by-id/*OCTOPUS*       stock Marlin, i.e. the very first flash
#   4. 0483:df11                         board already sitting in DFU mode
#   5. the serial: line in Mainboard_serial.cfg
#
# Reflashing a board that ALREADY runs Klipper needs no jumpers: Klipper's
# bootloader_request() on this chip ends in dfu_reboot(), which jumps to the
# STM32 ROM DFU bootloader (src/stm32/stm32f4.c), so plain
# --device /dev/serial/by-id/...stm32f446xx... just works.
#
# The FIRST flash is different. Stock Marlin resets into the BTT bootloader,
# which boots Marlin again, so DFU has to be entered by hardware:
#   1. Power off the board
#   2. Fit a jumper between BOOT0 and 3.3V (pin pair next to the MCU)
#   3. Power on -- it appears as 0483:df11
#   4. Run this script with --device 0483:df11
#   5. Power off, REMOVE the BOOT0 jumper, power on
#
# The build targets 0x08008000, so dfu-util writes above the factory bootloader
# and preserves it. BTT's manual warns that DFU "will overwrite the bootloader",
# which is true only when flashing a no-bootloader build at 0x08000000.
#
# sudo: dfu-util needs root and this system has no DFU udev rules. The password
# is taken from .system_pass.txt if present, else $SUDO_PASS, else sudo is called
# normally (works if sudo is passwordless).

CONFIG_DIR_NAME="BTT_Octopus_V1.1"

PRINTER_CONFIG="${HOME}/printer_data/config"
PASSWORD_FILE="${PRINTER_CONFIG}/.system_pass.txt"
SERIAL_FILE="${PRINTER_CONFIG}/02__Boards_Serials/Mainboard_serial.cfg"
CONFIG_FILE="${PRINTER_CONFIG}/0_Xplorer/.9_MCU_Flash/MCU_config/${CONFIG_DIR_NAME}/.config"
KLIPPER_DIR="${HOME}/klipper"

BUILD_ONLY=0
DEVICE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --build)  BUILD_ONLY=1 ;;
        --device) shift; DEVICE="$1" ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

echo "=== MCU Flash Script (Mainboard / BTT Octopus V1.1) ==="

# -------------------------------
# sudo helper
# -------------------------------
run_sudo() {
    if sudo -n true 2>/dev/null; then
        sudo "$@"
    elif [ -n "${SUDO_PASS:-}" ]; then
        printf '%s\n' "$SUDO_PASS" | sudo -S "$@"
    elif [ -f "$PASSWORD_FILE" ]; then
        sudo -S "$@" < "$PASSWORD_FILE"
    else
        echo "ERROR: sudo needs a password, but no .system_pass.txt and no \$SUDO_PASS."
        return 1
    fi
}

# -------------------------------
# Prepare Klipper build
# -------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file $CONFIG_FILE does not exist!"
    exit 1
fi

cp -f "$CONFIG_FILE" "$KLIPPER_DIR/.config"

cd "$KLIPPER_DIR" || exit 1

echo "Cleaning and building firmware..."
make olddefconfig || exit 1
make clean || exit 1
make || exit 1

echo "Build complete: $KLIPPER_DIR/out/klipper.bin"

if [ "$BUILD_ONLY" -eq 1 ]; then
    echo
    echo "Build only - nothing flashed."
    echo "SD card alternative: copy out/klipper.bin to a FAT32 card as 'firmware.bin',"
    echo "insert it into the Octopus, then power-cycle. It becomes FIRMWARE.CUR on success."
    exit 0
fi

# -------------------------------
# Resolve the target device
# -------------------------------
if [ -z "$DEVICE" ]; then
    for pattern in '*stm32f446xx*' '*OCTOPUS*'; do
        for candidate in /dev/serial/by-id/$pattern; do
            [ -e "$candidate" ] && DEVICE="$candidate" && break 2
        done
    done
fi

if [ -z "$DEVICE" ] && lsusb 2>/dev/null | grep -q '0483:df11'; then
    echo "Board is already in DFU mode."
    DEVICE="0483:df11"
fi

if [ -z "$DEVICE" ] && [ -f "$SERIAL_FILE" ]; then
    SERIAL_LINE=$(grep -E '^[[:space:]]*serial[[:space:]]*:' "$SERIAL_FILE" | head -n 1)
    DEVICE=$(echo "$SERIAL_LINE" | cut -d':' -f2- | xargs)
fi

if [ -z "$DEVICE" ]; then
    echo "ERROR: Could not find the Octopus."
    echo "Plug it in, or enter DFU by hardware: power off, fit a jumper between"
    echo "BOOT0 and 3.3V, power on, then re-run with: --device 0483:df11"
    exit 1
fi

case "$DEVICE" in
    /dev/ttyAMA*|/dev/serial0)
        echo "ERROR: resolved to the UART ($DEVICE) - that was the Manta's link."
        echo "The Octopus talks over USB. Pass --device explicitly."
        exit 1
        ;;
esac

echo "Flashing to: $DEVICE"

# -------------------------------
# Flash firmware
# -------------------------------
echo "Stopping Klipper so it cannot grab the port mid-flash..."
run_sudo systemctl stop klipper || exit 1

run_sudo make flash FLASH_DEVICE="$DEVICE"
FLASH_RESULT=$?

if [ $FLASH_RESULT -ne 0 ]; then
    echo
    echo "ERROR: make flash failed with exit code $FLASH_RESULT"
    echo "If the 1200-baud bootloader request was ignored (normal for stock Marlin),"
    echo "enter DFU by hardware: power off, fit a jumper between BOOT0 and 3.3V,"
    echo "power on, then re-run with:"
    echo "  $0 --device 0483:df11"
    run_sudo systemctl start klipper
    exit $FLASH_RESULT
fi

if [ "$DEVICE" = "0483:df11" ]; then
    echo
    echo "*** Now power off the board and REMOVE the BOOT0 jumper, then power on. ***"
    echo "*** Leaving it fitted makes the board come back up in DFU, not Klipper. ***"
fi

echo "Waiting for the Octopus to re-enumerate..."
sleep 5

echo "Klipper serial paths now present:"
ls -l /dev/serial/by-id/ 2>/dev/null || echo "  (none found - check USB)"

echo "Restarting Klipper service..."
run_sudo systemctl start klipper

echo "Firmware flashing complete."
