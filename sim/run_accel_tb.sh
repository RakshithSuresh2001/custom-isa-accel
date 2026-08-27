#!/bin/bash
set -e
RTL_ACCEL=../rtl/accel
cd "$(dirname "$0")"

echo "=== Test 1: Identity weights, activations 1..8 ==="
iverilog -g2012 -o accel_wrapper_tb.out \
    ../tb/accel_wrapper_tb1.sv \
    ${RTL_ACCEL}/accel_wrapper.sv \
    ${RTL_ACCEL}/accel_top.sv \
    ${RTL_ACCEL}/systolic_array_wrap.sv \
    ${RTL_ACCEL}/scratchpad.sv \
    ${RTL_ACCEL}/systolic_array.sv \
    ${RTL_ACCEL}/pe.sv \
    -s accel_wrapper_tb \
    && echo "Compile OK" \
    && vvp accel_wrapper_tb.out

echo ""
echo "=== Test 2: All-ones weights, activations 1..8 ==="
iverilog -g2012 -o accel_wrapper_tb2.out \
    ../tb/accel_wrapper_tb2.sv \
    ${RTL_ACCEL}/accel_wrapper.sv \
    ${RTL_ACCEL}/accel_top.sv \
    ${RTL_ACCEL}/systolic_array_wrap.sv \
    ${RTL_ACCEL}/scratchpad.sv \
    ${RTL_ACCEL}/systolic_array.sv \
    ${RTL_ACCEL}/pe.sv \
    -s accel_wrapper_tb2 \
    && echo "Compile OK" \
    && vvp accel_wrapper_tb2.out

echo ""
echo "=== Test 3: PyTorch-generated random weights/activations ==="
iverilog -g2012 -o accel_wrapper_tb3.out \
    ../tb/accel_wrapper_tb3_only.sv \
    ${RTL_ACCEL}/accel_wrapper.sv \
    ${RTL_ACCEL}/accel_top.sv \
    ${RTL_ACCEL}/systolic_array_wrap.sv \
    ${RTL_ACCEL}/scratchpad.sv \
    ${RTL_ACCEL}/systolic_array.sv \
    ${RTL_ACCEL}/pe.sv \
    -s accel_wrapper_tb3 \
    && echo "Compile OK" \
    && vvp accel_wrapper_tb3.out
