{
  description = "Maple Mini as a Black Magic Probe (STM32 SWD/JTAG debugger)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    # Black Magic Debug firmware source (pinned to a stable release).
    # Codeberg is the canonical upstream; github:blackmagic-debug/blackmagic
    # is a mirror. The Maple Mini is an STM32F103, so we build the "swlink"
    # probe host (SWD on PA13/PA14/PA15/PB3/PB4).
    blackmagic = {
      url = "https://codeberg.org/blackmagic-debug/blackmagic/archive/v2.1.0.tar.gz";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    blackmagic,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # ---------------------------------------------------------------------
    # Maple-Mini-specific patches, applied on top of the pristine upstream
    # source. Keeping them as patches (rather than editing a local copy of
    # the tree) means `src/` stays a clean checkout of upstream and the two
    # hardware/board adaptations are explicit, reviewable, and reproducible:
    #
    #   0001  PB9 USB D+ pull-up enable  (the Maple Mini gates its external
    #           1.5k D+ pull-up through a transistor on PB9; stock BMD never
    #           drives it, so the board is invisible on the bus without this)
    #   0002  app load address 0x08005000 (the LeafLabs bootloader reserves
    #           20KB and places apps at 0x08005000; upstream links at 0x08002000)
    # ---------------------------------------------------------------------
    blackmagicPatched =
      pkgs.runCommand "blackmagic-maple-patched"
      {
        nativeBuildInputs = [pkgs.patch];
      }
      ''
        cp -r ${blackmagic}/. $out
        chmod -R u+w $out
        cd $out
        patch -p1 < ${self}/patches/0001-maple-pb9-usb-pullup.patch
        patch -p1 < ${self}/patches/0002-maple-app-address.patch
      '';
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "maple-mini-bmp";

      packages = [
        # ---- Cross toolchain (arm-none-eabi-*) ----
        # includes gcc, binutils and gdb
        pkgs.gcc-arm-embedded

        # ---- Build system ----
        pkgs.meson
        pkgs.ninja
        pkgs.gnumake

        # ---- Flashing the Maple Mini ----
        pkgs.dfu-util

        # ---- Useful utilities ----
        pkgs.file
        pkgs.gnutar

        # ---- Optional: for testing the probe once it works ----
        pkgs.openocd
      ];

      shellHook = ''
        echo "=================================================="
        echo "  Maple Mini  ->  Black Magic Probe  dev shell"
        echo "=================================================="
        # Patched upstream source (PB9 pull-up + 0x08005000 app address).
        export BLACKMAGIC_SRC="${blackmagicPatched}"
        echo "Black Magic source : \$BLACKMAGIC_SRC"
        echo
        echo "Quick start:"
        echo "  ./build.sh     build firmware + DFU bootloader"
        echo "  ./flash.sh     flash the Maple Mini"
        echo "  ./use.sh       point GDB at the probe"
        echo
        echo "See README.md for the pin mapping and full instructions."
      '';
    };
  };
}
