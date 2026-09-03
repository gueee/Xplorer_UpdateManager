#!/usr/bin/env bash
#
# stm32f446-recover.sh
# Recover a BTT Octopus V1 (STM32F446ZET6) via ST-Link / SWD using OpenOCD.
#
# Wiring (ST-Link clone -> Octopus SWD header):
#   SWDIO -> SWDIO, SWCLK -> SWCLK, GND -> GND, 3V3 -> 3V3 (reference).
#   Board may be self-powered; do not back-feed the rail from the ST-Link.
#
# Usage:
#   ./stm32f446-recover.sh check
#   ./stm32f446-recover.sh erase
#   ./stm32f446-recover.sh flash <firmware.bin> [address]
#   ./stm32f446-recover.sh full  <firmware.bin> [address]
#
set -euo pipefail

# --- config -----------------------------------------------------------------
IFACE="${IFACE:-interface/stlink.cfg}"     # ST-Link v2 / clone
TARGET="${TARGET:-target/stm32f4x.cfg}"    # STM32F4 family
FLASH_BASE="0x08000000"

# Official BTT Octopus V1 F446 32 KiB bootloader (Intel HEX, self-addresses to
# 0x08000000). SHA256 below is the version verified at time of writing.
BOOTLOADER_HEX="${BOOTLOADER_HEX:-OctoPus-F446-bootloader-32KB.hex}"
BOOTLOADER_URL="https://raw.githubusercontent.com/bigtreetech/BIGTREETECH-OCTOPUS-V1.0/master/Firmware/DFU%20Update%20bootloader/bootloader/OctoPus-F446-bootloader-32KB.hex"
BOOTLOADER_SHA256="c54bf32fe7ad2abed946cafadefa2f827b97b19d3335992072bc5bd72237b085"

# Set CONNECT_UNDER_RESET=1 if OpenOCD can't attach (e.g. firmware reconfigured
# the SWD pins, or the chip is wedged). This asserts NRST while connecting.
CONNECT_UNDER_RESET="${CONNECT_UNDER_RESET:-0}"

# ----------------------------------------------------------------------------
ocd() {
    # Run OpenOCD with the given list of -c commands.
    local pre=()
    if [[ "$CONNECT_UNDER_RESET" == "1" ]]; then
        pre=(-c "reset_config srst_only connect_assert_srst")
    fi
    openocd -f "$IFACE" -f "$TARGET" "${pre[@]}" "$@"
}

cmd_check() {
    echo ">> Connecting and reading device ID (expect F446 DEV_ID = 0x421)..."
    ocd -c "init" \
        -c "reset halt" \
        -c "echo {--- DBGMCU_IDCODE (low 12 bits = DEV_ID) ---}" \
        -c "mdw 0xE0042000" \
        -c "flash probe 0" \
        -c "flash info 0" \
        -c "shutdown"
}

cmd_hsetest() {
    # Probe whether the 12 MHz HSE crystal actually oscillates.
    # SDIO (SD-card flashing) and USB (app CDC + ROM DFU) both rely on the
    # HSE-derived PLL; SWD does NOT. So if SWD works but SD + USB are all dead,
    # a non-oscillating crystal is the unifying suspect.
    #   RCC_CR = 0x40023800 : HSEON = bit16 (0x00010000), HSERDY = bit17 (0x00020000)
    echo ">> Probing 12 MHz HSE crystal via RCC_CR (enable HSE, watch HSERDY)..."
    ocd -c "init" \
        -c "reset halt" \
        -c "echo {RCC_CR (reset state):}" \
        -c "mdw 0x40023800" \
        -c "mww 0x40023800 0x00010001" \
        -c "sleep 100" \
        -c "echo {RCC_CR after enabling HSE -- want bit17 (0x00020000) SET:}" \
        -c "mdw 0x40023800" \
        -c "shutdown"
    echo ""
    echo "   Read the SECOND value:"
    echo "     bit17 SET   (e.g. 0x000300x1) -> crystal OSCILLATES; clock OK, look elsewhere"
    echo "     bit17 CLEAR (e.g. 0x000100x1) -> HSE will not start; crystal / solder joint is the fault"
}

cmd_erase() {
    echo ">> Mass-erasing flash..."
    ocd -c "init" \
        -c "reset halt" \
        -c "stm32f4x mass_erase 0" \
        -c "reset" \
        -c "shutdown"
    echo ">> Erase complete."
}

cmd_flash() {
    local bin="$1"
    local addr="${2:-$FLASH_BASE}"
    [[ -f "$bin" ]] || { echo "!! File not found: $bin" >&2; exit 1; }
    echo ">> Programming '$bin' at $addr (verify + reset)..."
    ocd -c "program \"$bin\" verify reset exit $addr"
    echo ">> Done."
}

cmd_bootloader() {
    # Restore the BTT 32 KiB bootloader so SD-card / USB-DFU flashing works again.
    if [[ ! -f "$BOOTLOADER_HEX" ]]; then
        echo ">> '$BOOTLOADER_HEX' not found; downloading from BTT..."
        curl -fsSL "$BOOTLOADER_URL" -o "$BOOTLOADER_HEX"
    fi
    if command -v sha256sum >/dev/null; then
        local got
        got="$(sha256sum "$BOOTLOADER_HEX" | cut -d' ' -f1)"
        if [[ "$got" != "$BOOTLOADER_SHA256" ]]; then
            echo "!! SHA256 mismatch on $BOOTLOADER_HEX" >&2
            echo "   expected $BOOTLOADER_SHA256" >&2
            echo "   got      $got" >&2
            echo "   (BTT may have updated the file; verify before proceeding.)" >&2
        else
            echo ">> SHA256 OK."
        fi
    fi
    cmd_erase
    echo ">> Flashing bootloader '$BOOTLOADER_HEX' (address from hex, verify + reset)..."
    ocd -c "program \"$BOOTLOADER_HEX\" verify reset exit"
    echo ">> Bootloader restored. Flash Klipper via SD card from here on."
}

cmd_full() {
    local bin="$1"
    local addr="${2:-$FLASH_BASE}"
    [[ -f "$bin" ]] || { echo "!! File not found: $bin" >&2; exit 1; }
    cmd_erase
    cmd_flash "$bin" "$addr"
}

case "${1:-}" in
    check)  cmd_check ;;
    hsetest) cmd_hsetest ;;
    erase)  cmd_erase ;;
    bootloader) cmd_bootloader ;;
    flash)  shift; [[ $# -ge 1 ]] || { echo "usage: $0 flash <firmware.bin> [address]" >&2; exit 1; }; cmd_flash "$@" ;;
    full)   shift; [[ $# -ge 1 ]] || { echo "usage: $0 full <firmware.bin> [address]" >&2; exit 1; }; cmd_full "$@" ;;
    *)
        cat >&2 <<EOF
STM32F446 (BTT Octopus V1) recovery via ST-Link + OpenOCD

Usage:
  $0 check                          Connect, read device ID + flash info
  $0 hsetest                        Probe the 12 MHz HSE crystal (SD/USB dead but SWD works?)
  $0 erase                          Mass-erase the whole flash
  $0 bootloader                     Restore BTT 32 KiB bootloader (SD/DFU flashing)
  $0 flash <firmware.bin> [addr]    Program + verify + reset (default $FLASH_BASE)
  $0 full  <firmware.bin> [addr]    Mass-erase, then program + verify + reset

Address guide:
  $FLASH_BASE   bootloader, or Klipper built with NO bootloader
  0x08008000   Klipper built with 32 KiB bootloader offset

Env overrides:
  IFACE=$IFACE
  TARGET=$TARGET
  CONNECT_UNDER_RESET=0|1   set to 1 if OpenOCD cannot attach
EOF
        exit 1
        ;;
esac
