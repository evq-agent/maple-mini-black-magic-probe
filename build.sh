#!/usr/bin/env bash
#
# build.sh - Build the Black Magic firmware + DFU bootloader for the Maple Mini
#
# Must be run inside the dev shell:
#   nix develop .
#   ./build.sh
#
# The Black Magic source is provided by the flake as a PATCHED tree (in the Nix
# store, read-only): pristine upstream v2.1.0 + the Maple-Mini patches from
# patches/ (PB9 USB D+ pull-up enable + 0x08005000 app load address). We copy it
# to ./src so meson can git-clone its subprojects into deps/.
#
# Outputs (in ./build/):
#   blackmagic_swlink_firmware.bin    - main firmware  (flash to 0x08005000)
#   blackmagic_swlink_bootloader.bin  - DFU bootloader (flash to 0x08000000)
#
set -euo pipefail

SRC=${BLACKMAGIC_SRC:?Run inside the dev shell:  nix develop .}
WORK=./src
BUILD=./build

# --- 1. Writable copy of the source -----------------------------------------
if [ ! -d "$WORK" ]; then
    echo ">> Copying Black Magic source to $WORK/"
    # --no-preserve=mode: the Nix store is read-only; we want a fully writable
    # copy so meson can git-clone subprojects into deps/.
    cp -r --no-preserve=mode,ownership "$SRC" "$WORK"
    chmod -R u+w "$WORK"
fi
# (To force a fresh copy after changing the flake's blackmagic input or
#  patches/:  rm -rf src build)

# --- 2. Pre-fetch subprojects (meson needs to write into deps/) -------------
# Parse each deps/*.wrap for its [wrap-git] url / revision / depth and clone it
# into deps/<name>/ so meson finds it locally (no network during setup).
echo ">> Ensuring subprojects are present"
pushd "$WORK/deps" > /dev/null
for wrap in *.wrap; do
    name="${wrap%.wrap}"
    if [ -d "$name" ]; then
        continue
    fi
    # tr -d '\r': some .wrap files use CRLF line endings.
    url=$(grep -m1 '^url *=' "$wrap" | tr -d '\r' | sed 's/^url *= *//' || true)
    rev=$(grep -m1 '^revision *=' "$wrap" | tr -d '\r' | sed 's/^revision *= *//' || true)
    depth=$(grep -m1 '^depth *=' "$wrap" | tr -d '\r' | sed 's/^depth *= *//' || true)
    echo "   cloning $name  ($url @ ${rev:-head})"
    if [ -n "${depth:-}" ]; then
        git clone --depth "$depth" "$url" "$name"
    else
        git clone "$url" "$name"
    fi
    if [ -n "${rev:-}" ] && [ "$rev" != "head" ]; then
        git -C "$name" checkout "$rev"
    fi
done
popd > /dev/null

# --- 3. Configure (meson setup) ---------------------------------------------
if [ ! -d "$BUILD" ]; then
    echo ">> Configuring (meson setup)"
    meson setup "$BUILD" "$WORK" \
        --cross-file "$WORK/cross-file/swlink.ini" \
        -Dbmd_bootloader=true \
        -Dtargets=stm,cortexm
    # Note: the Maple Mini has 128KB flash, so only ~120KB is available for the
    # firmware (after the 8KB bootloader). stm+cortexm keeps it at ~90KB and
    # covers all STM32 boards (Blue Pill, Black Pill, etc.). If you have a
    # 256KB board, add more targets here for wider chip support, e.g.:
    #   -Dtargets=stm,cortexm,lpc,nrf,nxp,rp,sam,ti
fi

# --- 4. Compile --------------------------------------------------------------
echo ">> Compiling"
meson compile -C "$BUILD" bin boot-bin

echo
echo ">> Build complete:"
ls -lh "$BUILD"/blackmagic_swlink_firmware.bin \
       "$BUILD"/blackmagic_swlink_bootloader.bin
