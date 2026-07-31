#!/usr/bin/env bash
# =============================================================================
# flash.sh - Program a bitstream onto the Arty A7-100T over JTAG via OpenOCD
# -----------------------------------------------------------------------------
# Usage:
#   ./flash.sh <bitstream.bit>
#
# Requires OpenOCD with the digilent_jtag_smt2 interface config and the
# xilinx-xc7 CPLD config (both ship with standard OpenOCD scripts).
#
# On WSL2, the FTDI JTAG device must be attached first from Windows:
#   usbipd attach --wsl --busid <busid>
# =============================================================================
set -euo pipefail

BITSTREAM="${1:?Usage: ./flash.sh <bitstream.bit>}"

if [ ! -f "$BITSTREAM" ]; then
    echo "Error: bitstream file '$BITSTREAM' not found." >&2
    exit 1
fi

openocd \
  -f interface/ftdi/digilent_jtag_smt2.cfg \
  -c "ftdi vid_pid 0x0403 0x6010" \
  -c "ftdi channel 0" \
  -c "adapter speed 6000" \
  -f cpld/xilinx-xc7.cfg \
  -c "init; xc7_program xc7.tap; pld load 0 $BITSTREAM; exit"

echo "Flash complete: $BITSTREAM programmed to Arty A7-100T."
