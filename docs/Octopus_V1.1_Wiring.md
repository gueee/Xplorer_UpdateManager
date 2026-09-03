# Xplorer V1.1 IDEX — BTT Octopus V1.1 wiring guide

Replaces the BTT Manta M8P V2.0 + CB2 with a **BTT Octopus V1.1 (STM32F446)** driven over
USB by a **Raspberry Pi 5**. All seven mainboard motors run **TMC2240 in SPI mode**. The two
EBB toolboards keep their onboard TMC2209 extruder drivers and are not touched.

Everything below is derived from the config in `_deploy/` — if you change the wiring, the
config has to change with it.

---

## 1. What moves and what does not

| Subsystem | Before | After |
|---|---|---|
| Mainboard | Manta M8P V2.0 | Octopus V1.1 |
| Host | CB2 (on the Manta) | Raspberry Pi 5 |
| Host ↔ mainboard link | UART `/dev/ttyAMA0` | USB-C |
| X, X1, Y, Y1, Z, Z1, Z2 drivers | TMC2209 UART | **TMC2240 SPI** |
| T0/T1 extruder drivers | TMC2209 on the EBB | unchanged |
| Hotends, part fans, X endstops, smart sensors | on the EBB toolboards | unchanged |
| Cartographer V4 | USB | USB, now to the Pi |
| Nozzle alignment camera | USB | USB, now to the Pi |

Only 25 mainboard signals exist in this build. Everything on the toolhead is on the
toolboards and needs no rework.

---

## 2. Parts and consumables

- 7 × TMC2240 stepper driver modules (SPI-capable, e.g. BTT TMC2240 V1.0 — `rref` 12 kΩ)
- Driver heatsinks, plus airflow over the driver bank
- A pile of 2.54 mm jumper caps: SPI jumpers for 7 driver slots, plus 6 fan voltage selectors
- USB-C cable, Pi → Octopus
- Powered USB 2.0 hub (you already have a VIA Labs hub in the machine)
- Official Raspberry Pi 5 27 W USB-C PSU

---

## 3. Power terminals

The Octopus has **four** screw terminals. Feeding all inputs from one 24 V PSU with a common
ground is fine.

| Terminal | Connect | Notes |
|---|---|---|
| `PWR IN` | 24 V from PSU | Logic, fans, hotend FETs. Must be **> 14.1 V** — do not feed 12 V here |
| `MOTOR PWR` | 24 V from PSU | Supplies all eight driver slots. TMC2240 is happy at 24 V |
| `BED IN` | 24 V from PSU | Bed heater supply, up to 300 W |
| `BED OUT` | to the bed heater pads | Switched by `PA1` |

Polarity is silkscreened on the **underside** of the board. Getting it wrong kills the board.

> **MCU power jumper:** there is a jumper that lets the board run off USB-C alone, for DFU
> flashing. Leave it **off** in normal operation and never fit it while the PSU is connected.

---

## 4. Driver slots and jumpers

### 4.1 Jumpers — do this before inserting any driver

1. **Remove every jumper under all eight driver slots.** Boards ship with UART or microstep
   jumpers fitted, and leftovers will short the SPI bus.
2. Fit the **SPI mode** jumper pattern under slots **0 through 6**. This is section 3.3 of the
   BTT Octopus user guide ("3.3 SPI MODE") — the pattern is only given as an image, so follow
   the manual picture rather than any text description. It bridges each driver's
   `SW_MOSI` / `SW_MISO` / `SW_SCK` pins onto the shared SPI1 bus (`PA7` / `PA6` / `PA5`).
3. Leave **slot 7** empty with no jumpers.
4. **Remove all DIAG jumpers** (section 4.2 of the manual). Those tie a driver's stallguard
   output onto the very same `PG9`–`PG15` inputs we use for physical endstops. A single
   forgotten DIAG jumper will make an endstop read permanently triggered.

You cannot mix these SPI drivers with a step/dir driver at anything other than 16 microsteps —
the microstep pins are the SPI pins. Not an issue here since every slot is SPI or empty.

### 4.2 Slot → axis → motor connector

Drivers all face the same way; line the module's `EN` pin up with the `EN` marking on the
socket silkscreen.

| Slot | Klipper stepper | Physical axis | Motor connector | CS pin |
|---|---|---|---|---|
| DRIVER0 | `stepper_x` | X, T0 carriage | `MOTOR0` | `PC4` |
| DRIVER1 | `dual_carriage` | X1, T1 carriage | `MOTOR1` | `PD11` |
| DRIVER2 | `stepper_y` | Y, right side | **`MOTOR2_1`** | `PC6` |
| DRIVER3 | `stepper_y1` | Y1, left side | `MOTOR3` | `PC7` |
| DRIVER4 | `stepper_z` | Z, front-left | `MOTOR4` | `PF2` |
| DRIVER5 | `stepper_z1` | Z1, back | `MOTOR5` | `PE4` |
| DRIVER6 | `stepper_z2` | Z2, front-right | `MOTOR6` | `PE1` |
| DRIVER7 | — | spare | `MOTOR7` | `PD3` |

> **The `MOTOR2_1` / `MOTOR2_2` trap.** The Octopus has nine motor connectors but only eight
> drivers: `MOTOR2_1` and `MOTOR2_2` are wired **in parallel off DRIVER2**. Plug Y into
> `MOTOR2_1` and leave `MOTOR2_2` **empty**. Anything plugged into `MOTOR2_2` moves in lockstep
> with Y.

### 4.3 Motor cable pinout

Each header is a 4-pin JST-XH with the coil pairs silkscreened next to it. If you are reusing
the Manta harnesses, verify before plugging in: with the motor unplugged, buzz the four wires
for continuity — the two that read a few ohms to each other are one coil, and each coil must
land on one silkscreened pair.

If a motor stutters and grinds, the coils are split across the pairs. If a motor simply runs
the wrong way, **do not rewire it** — flip the `!` on that stepper's `dir_pin` in the config.

---

## 5. Endstops and switch inputs

All eight of these are simple switch-to-GND connections: **signal + GND**. Where a header has a
third pin it is a supply rail for powered sensors, which none of these need.

| Header | Pin | Connect | Config |
|---|---|---|---|
| `X-STOP` | `PG6` | *nothing* | X and X1 home against switches on the EBB toolboards |
| `Y-STOP` | `PG9` | Y endstop switch | `endstop_pin: ~PG9` |
| `Z-STOP` | `PG10` | Z endstop, front-left | `endstop_pin: PG10` |
| `Z2-STOP` | `PG11` | Z1 endstop, back | `endstop_pin: PG11` |
| `E0DET` | `PG12` | Z2 endstop, front-right | `endstop_pin: PG12` |
| `E1DET` | `PG13` | tool offset contact probe | `pin: ^PG13` |
| `E2DET` | `PG14` | T0 (left) buffer runout switch | `switch_pin: ^PG14` |
| `E3DET` | `PG15` | T1 (right) buffer runout switch | `switch_pin: ^PG15` |

The three Z switches are physically identical, so label the cables — swapping two of them will
make `Z_TILT_ADJUST` drive the gantry into a corner.

The dedicated `PROBE` port (`PB7`) stays empty; probing is done by the Cartographer over USB.

---

## 6. Thermistors

Non-polarised, either way round.

| Header | Pin | Connect | Sensor type in config |
|---|---|---|---|
| `TB` | `PF3` | bed thermistor | `Generic 3950` |
| `T0` / `TH0` | `PF4` | *nothing* | hotend thermistors are on the toolboards |
| `T1` / `TH1` | `PF5` | chamber thermistor | `EPCOS 100K B57560G104F` |
| `T2` / `TH2` | `PF6` | *nothing* | |
| `T3` / `TH3` | `PF7` | *nothing* | |

---

## 7. Heater outputs

| Terminal | Pin | Connect |
|---|---|---|
| `BED OUT` / `HB` | `PA1` | bed heater pads |
| `HE0` | `PA2` | **case light LED strip** — `[output_pin caselight]` |
| `HE1` | `PA3` | *nothing* |
| `HE2` | `PB10` | *nothing* |
| `HE3` | `PB11` | *nothing* |

Both hotends are driven by their own EBB toolboards, so no hotend uses these outputs.

The case light lives on `HE0` because that mirrors the Manta, where it sat on `HE1` (`PA1`).
Heater outputs have **no voltage selector** — they are fed straight from `PWR IN`, so the strip
sees 24 V here exactly as it did before. Nothing to set, nothing to get wrong.

---

## 8. Fan headers and switched outputs

**Set the voltage selector jumper on each header before you plug anything in.** Every fan
header has its own 5 V / 12 V / 24 V selector, and the wrong setting will destroy whatever is
attached. Copy the setting each device had on the Manta.

| Header | Pin | Connect | Voltage jumper |
|---|---|---|---|
| `FAN0` | `PA8` | *free* — case light is on `HE0`, see section 7 | — |
| `FAN1` | `PE5` | *free* | — |
| `FAN2` | `PD12` | chamber fan | match the fan |
| `FAN3` | `PD13` | electronics bay fan | match the fan |
| `FAN4` | `PD14` | T0 (left) LLL buffer supply | match the buffer |
| `FAN5` | `PD15` | T1 (right) LLL buffer supply | match the buffer |
| always-on ×2 | — | *free* | — |

Polarity matters, and BTT swapped the fan polarity silkscreen on some early boards — check
against PINS.pdf rather than trusting the underside marking.

Aim the electronics bay fan across the driver bank. Y and Y1 are set to 1.5 A RMS and Z to
1.4 A; TMC2240 at those currents needs both its heatsink and moving air.

### PS-ON

| Header | Pin | Connect |
|---|---|---|
| `PS-ON` | `PE11` | PSU relay / SSR control line — `[output_pin Power]` |

This is the board's dedicated PS-ON port, the same function `PD14` served on the Manta M8P
V2.0, so `[output_pin Power]` carries over unchanged — `value: 1` still means "PSU on" and the
relay wiring is identical. Move the relay control lead across as-is.

The one board-specific piece is in the firmware build, not the config: the Octopus `.config`
sets `CONFIG_INITIAL_PINS="PE11"`, mirroring `"PD14"` on the Manta. That drives PS-ON high the
moment the MCU boots, so the PSU stays up through a `FIRMWARE_RESTART` instead of cutting out
before Klipper loads its config.

---

## 9. USB and the Raspberry Pi 5

Six USB devices, and the Pi 5 has four ports. Known identities from the live system:

| Device | USB ID | Where to plug it |
|---|---|---|
| Octopus V1.1 | `stm32f446xx`, new serial after flashing | Pi, direct, **USB 2.0 (black) port** |
| Cartographer V4 | `usb-Cartographer_stm32g431xx_350035000550315551333620-if00` | Pi, direct |
| Tool0 EBB | `usb-Klipper_stm32g0b1xx_420019000F504D4D35313220-if00` | Pi direct, or hub |
| Tool1 EBB | `usb-Klipper_stm32g0b1xx_590031000D504D4D35313220-if00` | Pi direct, or hub |
| Nozzle alignment camera | Alcor Micro `058f:5608` | Pi, direct — it wants the bandwidth |
| BTT-HDMI5 touchscreen | Holtek `04d9:8030` | powered hub |

Put the four MCUs and the camera on the Pi's own ports and hang the touchscreen off the
powered hub. USB 2.0 ports are preferable for the MCUs — USB 3.0 buys nothing here and its
2.4 GHz noise is a known source of trouble.

> **Do not power the Pi 5 from the Octopus.** The board's Raspberry Pi 5 V header cannot supply
> what a Pi 5 draws. Use the official 27 W USB-C supply.

The `[mcu]` serial path changes from `/dev/ttyAMA0` to the Octopus's
`/dev/serial/by-id/usb-Klipper_stm32f446xx_*-if00`. `scripts/octopus_cutover.sh` reads the real
path off the Pi and writes it into `02__Boards_Serials/Mainboard_serial.cfg` for you.

---

## 10. Nothing to do on the toolhead

For completeness, these stay exactly as they are and connect to the EBB toolboards, not the
Octopus: both extruder motors and their TMC2209 drivers, both hotend heaters and thermistors,
part cooling and hotend fans, the X and X1 endstops, the smart filament sensors, and the
Cartographer probe body.

---

## 11. Before first power-on

- [ ] PSU unplugged from mains, board unpowered.
- [ ] Every driver slot: old jumpers removed, SPI pattern fitted on slots 0–6, slot 7 bare.
- [ ] **All DIAG jumpers removed.**
- [ ] MCU USB-power jumper removed.
- [ ] Each fan header's voltage selector set for the device on it.
- [ ] Polarity checked on `PWR IN`, `MOTOR PWR`, `BED IN`.
- [ ] Drivers fully seated, correct orientation, heatsinks fitted.

### First power-on sequence

1. Flash Klipper via SD card: `.9_MCU_Flash/scripts/flash_M1_BTTOctopusV11.sh --build`.
2. Confirm the board enumerates: `ls /dev/serial/by-id/` should show `stm32f446xx`.
3. Bring up on `_deploy/octopus_bringup_minimal.cfg` first — mainboard only, no toolboards.
4. `scripts/octopus_bringup_check.sh` for the automated checks.
5. `DUMP_TMC STEPPER=stepper_x` (then `dual_carriage`, `stepper_y`, `stepper_y1`,
   `stepper_z`, `stepper_z1`, `stepper_z2`). Real register values prove the SPI jumpers are
   right; all-zero or all-`ffffffff` means that slot's jumpers are wrong.
6. `QUERY_ENDSTOPS` — trip each switch by hand and confirm the right one changes state.
7. `FORCE_MOVE` each axis a few millimetres to check direction **before** homing anything.
8. Swap to the full `Xplorer_V1.1_IDEX_custom.cfg` and reconnect the toolboards.

### Things worth re-checking once it runs

- `rref: 12000` matches BTT TMC2240 modules. A different vendor may use a different reference
  resistor, and a wrong value silently scales every motor current.
- Run currents were carried over unchanged from the TMC2209 setup. Watch driver temperatures on
  the first long print — TMC2240 reports its own temperature in `DUMP_TMC`.

---

## Appendix — complete mainboard pin map

| Pin | Silkscreen | Function |
|---|---|---|
| `PF13` `PF12` `PF14` `PC4` | DRIVER0 | `stepper_x` step / dir / enable / CS |
| `PG0` `PG1` `PF15` `PD11` | DRIVER1 | `dual_carriage` step / dir / enable / CS |
| `PF11` `PG3` `PG5` `PC6` | DRIVER2 | `stepper_y` step / dir / enable / CS |
| `PG4` `PC1` `PA0` `PC7` | DRIVER3 | `stepper_y1` step / dir / enable / CS |
| `PF9` `PF10` `PG2` `PF2` | DRIVER4 | `stepper_z` step / dir / enable / CS |
| `PC13` `PF0` `PF1` `PE4` | DRIVER5 | `stepper_z1` step / dir / enable / CS |
| `PE2` `PE3` `PD4` `PE1` | DRIVER6 | `stepper_z2` step / dir / enable / CS |
| `PA5` `PA6` `PA7` | SPI1 | shared TMC2240 SCK / MISO / MOSI |
| `PG6` | X-STOP | unused |
| `PG9` | Y-STOP | Y endstop |
| `PG10` | Z-STOP | Z endstop |
| `PG11` | Z2-STOP | Z1 endstop |
| `PG12` | E0DET | Z2 endstop |
| `PG13` | E1DET | tool offset contact probe |
| `PG14` | E2DET | T0 buffer runout |
| `PG15` | E3DET | T1 buffer runout |
| `PA1` | BED OUT | bed heater |
| `PA2` | HE0 | case light |
| `PF3` | TB | bed thermistor |
| `PF5` | T1 | chamber thermistor |
| `PD12` | FAN2 | chamber fan |
| `PD13` | FAN3 | electronics fan |
| `PD14` | FAN4 | T0 buffer supply |
| `PD15` | FAN5 | T1 buffer supply |
| `PE11` | PS-ON | PSU control |
