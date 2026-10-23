# Maple Mini → Black Magic Probe

Turn a **Maple Mini** (STM32F103) into a **Black Magic Probe** — a cheap SWD/JTAG
debugger you can use to program and debug a **Blue Pill** and other STM32 boards
(via GDB, OpenOCD, `st-flash`, etc.).

The Maple Mini runs the [Black Magic Debug](https://codeberg.org/blackmagic-debug/blackmagic)
firmware, built for the **`swlink`** probe host (the F103 "minimum system" pinout,
which matches the Maple Mini's header).

---

## How it works

The F103's flash is split into two regions:

| Address      | Size   | Contents                                          |
|--------------|--------|---------------------------------------------------|
| `0x08000000` | 20 KB  | **LeafLabs Maple Bootloader** (already on the board) |
| `0x08005000` | 108 KB | Black Magic **probe app** (what we flash)           |

The Maple Mini ships with the LeafLabs bootloader in the first 8 KB. It boots into
USB-DFU mode (`1eaf:0003`) while the BOOT button is held, and otherwise jumps to
the app at `0x08005000`. We flash the Black Magic app into that app region through
the LeafLabs bootloader — no external debugger, no BOOT0 jumper.

> The Maple Mini is an **STM32F103CBT6** with **128 KB** of flash, leaving 108 KB
> for the app. `build.sh` therefore defaults to the `stm`+`cortexm` target set
> (~90 KB app), which fits. If your board is a 64 KB clone (C8T6) the app will not
> fit — see [Troubleshooting](#troubleshooting).

---

## What you need

- A Maple Mini (STM32F103, **128 KB** flash)
- A USB cable (data, not just charge)
- Nix with flakes enabled (`experimental-features = [nix-command flakes]`)
- A target board to program (e.g. a Blue Pill) + a few jumper wires

---

## Pin mapping

### Probe side — Maple Mini pins that connect to the target's SWD header

| SWD signal | Target header pin | Maple Mini pin | GPIO  |
|------------|-------------------|----------------|-------|
| **SWDIO**  | SWDIO / TMS       | **D22**        | PA13  |
| **SWCLK**  | SWCLK / TCK       | **D21**        | PA14  |
| **NRST**   | NRST / RESET      | **D18**        | PB4   |
| **GND**    | GND               | **GND**        | —     |
| TDO / SWO  | TDO (optional)    | D19            | PB3   |
| TDI        | TDI (optional)    | D20            | PA15  |

**Minimum wiring for SWD (4 wires):**

```
  Maple Mini          Blue Pill (SWD header)
  ----------          --------------------
  D22 (PA13)  ------> SWDIO
  D21 (PA14)  ------> SWCLK
  D18 (PB4)   ------> NRST
  GND         ------> GND
```

> Do **not** connect the two boards' 3.3 V together unless you are sure the
> target is already powered; the probe does not power the target over these pins.
> Power the target from its own USB/Vin.

The Maple Mini's USB (PA11/PA12) is already wired to its USB connector — nothing
to do there. The probe shows up as `/dev/ttyACM0` (debugger) and `/dev/ttyACM1`
(target UART pass-through).

> **Key hardware detail — the USB D+ pull-up is external and on PB9.**
> Unlike a bare F103 (which has an internal D+ pull-up), the Maple Mini gates a
> 1.5 kΩ D+ pull-up through a transistor on **PB9 (`USB_DISC`)**:
> **PB9 low → pull-up ON (host sees the device)**; PB9 high/floating → OFF
> (board invisible on the bus). The stock BMD `swlink` platform never drives PB9,
> so `platform_init()` here configures it as a low output early in boot. Without
> this the probe builds fine but never enumerates.

### Reference — full Maple Mini digital pin map

| D | GPIO | D | GPIO | D | GPIO | D | GPIO |
|---|------|---|------|---|------|---|------|
| D0  | PB11 | D10 | PA1  | D20 | PA15 | D30 | PB13 |
| D1  | PB10 | D11 | PA0  | D21 | PA14 | D31 | PB12 |
| D2  | PB2  | D12 | PC15 | D22 | PA13 | D32 | PB8  |
| D3  | PB0  | D13 | PC14 | D23 | PA12 | D33 | PB1  |
| D4  | PA7  | D14 | PC13 | D24 | PA11 |     |      |
| D5  | PA6  | D15 | PB7  | D25 | PA10 |     |      |
| D6  | PA5  | D16 | PB6  | D26 | PA9  |     |      |
| D7  | PA4  | D17 | PB5  | D27 | PA8  |     |      |
| D8  | PA3  | D18 | PB4  | D28 | PB15 |     |      |
| D9  | PA2  | D19 | PB3  | D29 | PB14 |     |      |

---

## 1. Enter the dev shell

```sh
nix develop .
```

This gives you `arm-none-eabi-gcc`, `meson`, `ninja`, `dfu-util`, an ARM GDB and
OpenOCD, and sets `BLACKMAGIC_SRC` to the pinned Black Magic source tree.

## 2. Build

```sh
./build.sh
```

The flake takes the pinned upstream Black Magic source and applies the two
Maple-Mini patches from `patches/` to produce a read-only patched tree in the Nix
store (that's `BLACKMAGIC_SRC`). `build.sh` copies that tree into `./src/` and
git-clones the Black Magic subprojects (`libopencm3`, `hidapi`, `libusb`, …) into
`./src/deps/`, so the first run needs network access. Re-runs are fast and offline.
To force a fresh copy after changing the flake's `blackmagic` input or a patch:
`rm -rf src build`.

The two patches (in `patches/`) are the only changes from upstream:

- `0001-maple-pb9-usb-pullup.patch` — drive PB9 low to enable the external USB
  D+ pull-up (see [How it works](#how-it-works)); without it the board never
  enumerates.
- `0002-maple-app-address.patch` — link the app at `0x08005000` (the LeafLabs
  bootloader's app region) instead of upstream's `0x08002000`.

Produces (in `build/`):

- `blackmagic_swlink_bootloader.bin` — DFU bootloader (`0x08000000`)
- `blackmagic_swlink_firmware.bin`   — probe app (`0x08005000`)

## 3. Flash the Maple Mini

```sh
./flash.sh
```

The script walks you through the physical steps. In short:

1. Plug in USB; when the on-board LED blinks **fast** (the bootloader's waiting
   window), press the **user button** → the **LeafLabs bootloader** appears as a
   DFU device (`1eaf:0003`).
2. Flash the **Black Magic app** to `0x08005000` (the LeafLabs bootloader handles
   the address for you).
3. The board resets; the LeafLabs bootloader jumps into the probe
   (`1d50:6018`). Done.

Verify:

```sh
lsusb | grep -i black      # Black Magic Probe (1d50:6018)
ls /dev/ttyACM*            # ttyACM0 (debugger), ttyACM1 (console)
```

If you get a permission error on the USB DFU or the `ttyACM*` devices:

```sh
sudo usermod -aG dialout "$USER"   # then log out and back in
```

## 4. Use the probe

Wire a target (e.g. Blue Pill) to the probe per the [pin mapping](#pin-mapping),
power the target, then:

```sh
./use.sh                     # starts GDB attached to /dev/ttyACM0
```

Inside GDB:

```
(gdb) monitor scan            # find the target on the SWD bus
(gdb) monitor reset
(gdb) file my_target.elf      # load symbols
(gdb) break main
(gdb) continue
```

To raw-flash a binary to the target from GDB:

```
(gdb) flash write image.bin 0x08000000
(gdb) monitor reset
```

You can also drive the probe with OpenOCD (`interface blackmagicpi`) or any tool
that speaks the GDB Remote Serial Protocol on `/dev/ttyACM0`.

To attach GDB manually (outside `use.sh`), note the probe needs the
**extended-remote** transport, not plain `remote`:

```
arm-none-eabi-gdb -ex 'target extended-remote /dev/ttyACM0'
```

---

## Updating the probe firmware later

Re-run `./build.sh` then `./flash.sh`. The LeafLabs bootloader re-flashes the app
to `0x08005000` the same way.

---

## Troubleshooting

- **`dfu-util` can't find `1eaf:0003`** — you're not in the LeafLabs bootloader.
  Make sure you **held the BOOT button the whole time** while plugging in USB, and
  that the cable carries data. Try a different USB port/cable.
- **Board enumerates as `1eaf:0003` but not `1d50:6018` after flashing** — the app
  image didn't flash, or the app is too big. Re-run step 2 of `./flash.sh`.
- **App too big / link error about `rom` overflow** — the app is larger than the
  120 KB app region. The default build (`stm`+`cortexm`, ~90 KB) fits a 128 KB chip.
  If you are on a 64 KB (C8T6) board it still won't fit — use a 128 KB (CBT6) board.
  If you added extra targets and it overflows, trim the `-Dtargets=` list in `build.sh`.
- **`No permission` on the USB DFU or `/dev/ttyACM*`** — add your user to the
  `dialout` group and re-login.
- **Probe works but can't see the target** — check the 4 SWD wires (SWDIO, SWCLK,
  NRST, GND), make sure the target is powered, and try `monitor scan`.

---

## Files

| File         | Purpose                                    |
|--------------|--------------------------------------------|
| `flake.nix`  | Nix dev shell + pinned Black Magic source  |
| `build.sh`   | Build firmware + DFU bootloader            |
| `flash.sh`   | Flash the Maple Mini over USB DFU          |
| `use.sh`     | Start GDB against the probe                |
| `README.md`  | This file                                  |
