#!/usr/bin/env bash
#
# flash.sh - Flash the Black Magic Probe app onto the Maple Mini.
#
# The Maple Mini ships with the LeafLabs Maple Bootloader in the first 20 KB of
# flash. It is a USB-DFU device (1eaf:0003) with two alternate interfaces:
#   -a 0  -> "DFU Program RAM   0x20000C00"  (RAM -- NOT what we want)
#   -a 1  -> "DFU Program FLASH 0x08005000"  (FLASH -- this is the one)
# So we flash the BMD app through interface 1, which writes to 0x08005000 --
# exactly where the BMD app is linked. No external debugger, no BOOT0 jumper.
#
#   blackmagic_swlink_firmware.bin -> 0x08005000  (via LeafLabs DFU 1eaf:0003, -a 1)
#
# The LeafLabs bootloader stays at 0x08000000 and jumps to the BMD app on each
# boot. The probe works fully; only BMD's *self-update* (which expects BMD's own
# bootloader at 0x08000000) is unavailable -- to update, just re-run this script.
#
# Run from inside the dev shell:   nix develop . && ./build.sh && ./flash.sh
#
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build}"
APP="${BUILD_DIR}/blackmagic_swlink_firmware.bin"

if [[ ! -f "$APP" ]]; then
  echo "error: ${APP} not found. Run ./build.sh first." >&2
  exit 1
fi

MAPLE_DFU_PID="1eaf:0003"   # LeafLabs Maple Bootloader DFU interface

# Use sudo only if we can't talk to the USB device directly.
DFU=(dfu-util)
if ! dfu-util -l >/dev/null 2>&1; then
  echo ">> No permission to access USB DFU; retrying with sudo."
  DFU=(sudo dfu-util)
fi

pause() { read -rp "  >>> $1 " _; }

echo "============================================================"
echo " Step 1/2 - Enter the LeafLabs Maple bootloader (DFU)"
echo "============================================================"
echo "  On power-up the Maple Mini runs the LeafLabs bootloader, which blinks"
echo "  the on-board LED. While it is blinking FAST (the bootloader's waiting"
echo "  window), press the USER button to put it into USB-DFU mode (1eaf:0003)."
echo "  Miss the window and it jumps to the app -- unplug and try again."
echo
echo "  1. Plug in the Maple Mini's USB cable."
echo "  2. Watch the on-board LED. When it blinks FAST, press the USER button."
echo "  3. The board now enumerates as the LeafLabs Maple DFU device:"
echo "         lsusb | grep -iE '1eaf|leaflabs|maple'"
pause "Press ENTER when the 1eaf:0003 device is connected ..."

echo
echo "============================================================"
echo " Step 2/2 - Flash the Black Magic app -> 0x08005000"
echo "============================================================"
echo "  (Interface -a 1 is the FLASH target; the LeafLabs bootloader writes"
echo "   to 0x08005000 automatically.)"
echo
echo "  Tip: if the download times out, use a USB port directly on the"
echo "  computer (not a hub), a USB 2.0 port, and a known-good cable."
echo

# The LeafLabs DFU download can occasionally time out mid-transfer. Retry a
# few times before giving up.
attempt=1
max_attempts=3
while :; do
  if "${DFU[@]}" -d "$MAPLE_DFU_PID" -a 1 -D "$APP" -R; then
    break
  fi
  if (( attempt >= max_attempts )); then
    echo "error: DFU download failed after $max_attempts attempts." >&2
    echo "       Try a different USB port (directly on the computer, USB 2.0)," >&2
    echo "       a different cable, and re-enter DFU (fast-blink + user button)." >&2
    exit 1
  fi
  echo ">> Download failed (attempt $attempt/$max_attempts)."
  echo "   Re-enter DFU: unplug, re-plug, press the USER button when the LED"
echo "   blinks FAST, then press ENTER to retry."
  pause "Press ENTER to retry ..."
  attempt=$((attempt+1))
done

echo
echo "============================================================"
echo " Done!"
echo "============================================================"
echo " The board has reset. The LeafLabs bootloader now jumps to the"
echo " Black Magic app at 0x08005000. Verify with:"
echo
echo "     lsusb | grep -i black        # Black Magic Probe (1d50:6018)"
echo "     ls /dev/ttyACM*              # ttyACM0 (debugger), ttyACM1 (console)"
echo
echo " Next: wire a target board to the probe (see README.md) and run ./use.sh"
