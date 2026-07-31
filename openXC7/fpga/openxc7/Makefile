# =============================================================================
# Makefile - openXC7 FPGA build flow for arty_top (CPU + systolic array accel)
# -----------------------------------------------------------------------------
# Fully open-source flow, no Vivado required:
#   Yosys synthesis -> nextpnr-xilinx PnR -> fasm2frames -> xc7frames2bit
#
# Usage:
#   make synth   - run Yosys synthesis, produce arty_top.json
#   make pnr     - run nextpnr-xilinx place-and-route, produce arty_top.fasm
#   make bit     - generate final arty_top.bit from the fasm file
#   make flash   - program the bitstream onto the Arty A7 over JTAG (OpenOCD)
#   make all     - synth + pnr + bit (does not flash)
#   make clean   - remove all generated build artifacts
#
# Requires: openXC7 toolchain installed (Yosys, nextpnr-xilinx, prjxray tools,
# OpenOCD), and PRJXRAY_DB pointing at the artix7 prjxray-db directory.
# =============================================================================

TOP        := arty_top
PART       := xc7a100tcsg324-1
CHIPDB     := xc7a100t.bin
XDC        := arty_top.xdc

# Point this at your local prjxray-db/artix7 checkout, e.g.:
#   /snap/openxc7/x1/opt/nextpnr-xilinx/external/prjxray-db/artix7
PRJXRAY_DB ?= /snap/openxc7/x1/opt/nextpnr-xilinx/external/prjxray-db/artix7

RTL_TOP    := ../../rtl/top/arty_top.sv ../../rtl/top/cpu_top.sv
RTL_CPU    := ../../rtl/cpu/decode.sv ../../rtl/cpu/memory_stage.sv \
              ../../rtl/cpu/execute.sv ../../rtl/cpu/writeback.sv \
              ../../rtl/cpu/bht.sv ../../rtl/cpu/hazard.sv \
              ../../rtl/cpu/fetch.sv ../../rtl/cpu/regfile.sv
RTL_ACCEL  := ../../rtl/accel/accel_wrapper.sv ../../rtl/accel/systolic_array_wrap.sv \
              ../../rtl/accel/systolic_array.sv ../../rtl/accel/accel_top.sv \
              ../../rtl/accel/scratchpad.sv ../../rtl/accel/pe.sv

RTL_SRCS   := $(RTL_TOP) $(RTL_CPU) $(RTL_ACCEL)

.PHONY: all synth pnr bit flash clean

all: bit

synth: $(TOP).json

$(TOP).json: $(RTL_SRCS) imem.hex
	yosys -p "synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); write_json $(TOP).json" $(RTL_SRCS)

pnr: $(TOP).fasm

$(TOP).fasm: $(TOP).json $(XDC)
	nextpnr-xilinx --chipdb $(CHIPDB) --xdc $(XDC) --json $(TOP).json --fasm $(TOP).fasm

bit: $(TOP).bit

$(TOP).frames: $(TOP).fasm
	fasm2frames --part $(PART) --db-root $(PRJXRAY_DB) $(TOP).fasm $(TOP).frames

$(TOP).bit: $(TOP).frames
	xc7frames2bit --part_file $(PRJXRAY_DB)/$(PART)/part.yaml \
	  --part_name $(PART) --frm_file $(TOP).frames --output_file $(TOP).bit

flash: $(TOP).bit
	./flash.sh $(TOP).bit

clean:
	rm -f $(TOP).json $(TOP).fasm $(TOP).frames $(TOP).bit
