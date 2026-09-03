# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the Xplorer 3D Printer Update Manager repository that integrates with the Mainsail interface to provide centralized configuration management for Formbot's Xplorer 3D printers. The repository contains Klipper configuration files, calibration scripts, slicer profiles, and printer documentation that can be automatically synchronized to printer systems.

## Repository Structure

- **01_Default_CFG/**: Main Klipper configuration files for different printer variants (SINGLE, IDEX, 2xGANTRY)
- **02_Printer_cfg/**: Complete printer configuration files that include the default configs
- **03_MODs/**: Formbot official modifications and tweaks
- **04_Slicer_Profiles/**: Pre-configured slicer profiles (OrcaSlicer)
- **05_STEP_FILES/**: 3D model files for printer parts
- **06_Manual/**: Printer manuals and documentation PDFs
- **07_Mainsail_Settings/**: Mainsail interface configuration backups
- **.7_XP_modules/**: Python modules for printer calibration (tools_calibrate.py, trsync_patch.py)
- **.8_Scripts/**: Shell scripts for resonance calibration and input shaping

## Key Configuration Architecture

The printer configurations use a modular include system:
- Main configs (Xplorer_SINGLE.cfg, Xplorer_IDEX.cfg, Xplorer_2xGANTRY.cfg) include multiple specialized cfg files
- Configuration is split by function: basic settings, tool configurations, axis configurations, macros, calibration
- Each printer variant has specific Z-tilt configurations and bed mesh settings
- Tool offset calibration is handled through dedicated configuration files

## Calibration System

The repository includes an automated calibration system:
- **Resonance calibration scripts** in `.8_Scripts/` that process CSV data and update shaper settings
- **Tools calibration module** (`tools_calibrate.py`) for multi-axis probe calibration
- Scripts automatically backup configuration files before making changes
- Calibration results are saved to `/home/biqu/printer_data/config/` on target systems

## Common Commands

Since this is a configuration repository without build processes, common operations include:

```bash
# View configuration structure
find . -name "*.cfg" | sort

# Check calibration scripts
ls .8_Scripts/

# View printer variants
ls 01_Default_CFG/Xplorer_*.cfg
```

## Development Notes

- All configuration files use Klipper syntax
- Shell scripts are designed to run on the printer's Raspberry Pi system
- Python modules extend Klipper functionality for advanced calibration
- The repository is designed for direct integration with Mainsail's Update Manager
- License is CC BY-NC 4.0 - commercial use requires permission from Formbot

## File Naming Conventions

- Configuration files use underscore separation (Xp_Tool0.cfg)
- Scripts use descriptive names indicating their function (resonances_X_t0.sh)
- Backup files are prefixed with dots (.variables.cfg.bak)
- Time-stamped output files include date/time in filename

## This Machine: Octopus V1.1 Migration (Sep 2026)

This particular printer has been migrated from a BTT Manta M8P v2 to a **BTT Octopus
V1.1 (STM32F446, 12 MHz crystal)**. Klipper reports `ready`; all 4 MCUs connect, all
7 TMC2240s answer on SPI, all temperatures read correctly. The printer has **not been
homed** on the new board yet.

### Hardware changes from stock

- Host is a Raspberry Pi 5 / MainsailOS, talking to the mainboard over **USB-C** (the
  Manta used UART `/dev/ttyAMA0`)
- All 7 mainboard motors (X, X1, Y, Y1, Z, Z1, Z2) are **TMC2240 in SPI mode**
- Extruders remain TMC2209 on the EBB toolboards; Cartographer V4 and the alignment
  camera are on Pi USB
- Case light is on `HE0` / `PA2`

### Deployment: `0_Xplorer` is a clone of the fork, `01__User_Custom__CFG` is not

Since 2026-09-03, `~/printer_data/config/0_Xplorer/` on the Pi is a git clone of the
fork (`gueee/Xplorer_UpdateManager`, branch main) managed by Moonraker's
`[update_manager Xplorer]`. Push to origin, then update "Xplorer" in Mainsail.
Never `chmod` inside it on the Pi: a dirty tree disables updates.

`01__User_Custom__CFG/` and `printer.cfg` are still **not** in git. Files under
`_deploy/` only reach the printer when copied there by hand:
`cp ~/printer_data/config/0_Xplorer/_deploy/<file> ~/printer_data/config/01__User_Custom__CFG/`.

Overlooking this cost an hour of misdiagnosis: the bed thermistor read a steady
166 °C and the chamber ~950 °C, which looks exactly like two shorted ADC inputs. The
actual cause was that no Octopus file had ever been deployed, so Klipper still used
the Manta pin map and read `PB1`/`PB0` — not thermistor inputs on an Octopus. Board,
sensors and wiring were all fine. **Verify what is actually on the printer before
diagnosing hardware.**

Currently deployed: `X_Axis_IDEX_octopus.cfg`, `Y_Axis_1xGantry_octopus.cfg`,
`Z_Axis_octopus.cfg`, `octopus_v11_pins.cfg`, `Xplorer_V1.1_IDEX_custom.cfg`.
Backups kept as `Xplorer_V1.1_IDEX_custom.cfg.manta.bak` and
`Mainboard_serial.cfg.uartbak`.

`[include octopus_v11_pins.cfg]` **must stay last** — it overrides mainboard pins
from the upstream Formbot fragments.

### Firmware: SD card only, DFU does not work

Build config lives at `.9_MCU_Flash/MCU_config/BTT_Octopus_V1.1/.config`
(`MACH_STM32F446`, `CLOCK_REF_12M`, `USBSERIAL`, `FLASH_START_8000` → `0x08008000`).

Flash by copying `out/klipper.bin` to a FAT32 microSD as `firmware.bin` and
power-cycling. The card renaming it to `FIRMWARE.CUR` is the success signal.

Both USB routes were tested and fail on this board:

- BOOT0 jumper fitted produces **no USB enumeration at all**, not even `0483:df11`
- `make flash FLASH_DEVICE=<by-id>` completes the 1200-baud touch and sees the device
  reconnect, but it returns as a Virtual COM Port rather than DFU, so `dfu-util`
  reports "No DFU capable USB device available". Klipper's `make flash` only works on
  a board *already running Klipper*, whose `dfu_reboot()` jumps to ROM DFU.

### Pin map (matches Klipper's `generic-bigtreetech-octopus-v1.1.cfg`)

| Function | Pin |
| --- | --- |
| MCU serial | `/dev/serial/by-id/usb-Klipper_stm32f446xx_360025000451343437373238-if00` |
| TMC2240 SPI bus / `rref` | `spi1_PA6_PA7_PA5` / `12000` |
| CS: X, X1, Y, Y1, Z, Z1, Z2 | `PC4`, `PD11`, `PC6`, `PC7`, `PF2`, `PE4`, `PE1` |
| Bed heater / bed thermistor | `PA1` / `PF3` (TB) |
| Chamber thermistor | `PF5` (T1) |
| Case light | `PA2` (HE0) |
| PS-ON | `PE11` |
| Endstops Y / Z / Z1 / Z2 | `~PG9` / `PG10` / `PG11` / `PG12` |
| Tool probe / T0 + T1 buffers | `^PG13` / `PG14`, `PG15` |
| Fans: chamber, electronics, buffers | `PD12`–`PD15` |

Thermistor pins are identical across all non-Max Octopus variants. Octopus **Pro**
V1.1 moves HE0 to `PA0`. Octopus **Max EZ** differs entirely (`PB1`/`PB0`).

### Outstanding, requires physical access — do before homing

1. Motor direction on all 7 TMC2240 slots
2. Which physical corner each Z endstop belongs to — `Z_TILT_ADJUST` will drive the
   gantry into a corner if two are swapped
3. `QUERY_ENDSTOPS` shows `stepper_y:TRIGGERED`, most likely because the gantry is
   parked on the switch. Push it clear by hand and re-query to confirm `open`; if it
   stays triggered, suspect a DIAG jumper on driver slot 2 tying `PG9` to the
   driver's DIAG output
4. Case light on `HE0`

### Notes for future sessions

- The USB serial path exists only on the printer, not mirrored into `_deploy/`
- `.9_MCU_Flash/firmware.bin` is an untracked build artifact
- `sudo` on the Pi requires a password and there is no `.system_pass.txt`; the flash
  script reads `$SUDO_PASS` or that file, otherwise falls back to plain `sudo`
