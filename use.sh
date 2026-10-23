#!/usr/bin/env bash
#
# use.sh - Use the Maple Mini Black Magic Probe to debug/flash a target.
#
# The probe exposes two USB CDC serial ports once running:
#   /dev/ttyACM0  - GDB Remote Serial Protocol (the debugger)
#   /dev/ttyACM1  - the target's UART console (pass-through)
#
# Run from inside the dev shell:   nix develop .
#
set -euo pipefail

PROBE="${PROBE:-/dev/ttyACM0}"

if [[ ! -e "$PROBE" ]]; then
  echo "error: probe not found at ${PROBE}" >&2
  echo "       Check 'ls /dev/ttyACM*' and 'lsusb | grep -i black'." >&2
  echo "       If the group is wrong:  sudo usermod -aG dialout \$USER  (re-login)" >&2
  exit 1
fi

ELF="${1:-}"

echo ">> Using probe at ${PROBE}"
echo ">> Starting GDB (use 'help' for commands, 'quit' to exit)."
echo
echo "   Common commands once connected:"
echo "     monitor scan          # list SWD targets on the bus"
echo "     monitor reset         # reset the target"
echo "     file <target.elf>     # load a symbol file"
echo "     flash write <file.bin>  # raw-flash a binary to the target"
echo "     break main / continue / step"
echo

if [[ -n "$ELF" ]]; then
  exec arm-none-eabi-gdb "$ELF" -ex "target extended-remote ${PROBE}"
else
  exec arm-none-eabi-gdb -ex "target extended-remote ${PROBE}"
fi
