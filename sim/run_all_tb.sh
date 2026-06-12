#!/bin/bash
set -e

RTL_CPU=../rtl/cpu
RTL_ACCEL=../rtl/accel
RTL_TOP=../rtl/top

cd "$(dirname "$0")"

echo "========================================"
echo "Test 1: Identity weights, activations 1..8"
echo "========================================"
iverilog -g2012 -o accel_wrapper_tb.out \
    ../tb/accel_wrapper_tb.sv \
    ${RTL_ACCEL}/accel_wrapper.sv \
    ${RTL_ACCEL}/accel_top.sv \
    ${RTL_ACCEL}/systolic_array_wrap.sv \
    ${RTL_ACCEL}/scratchpad.sv \
    ${RTL_ACCEL}/systolic_array.sv \
    ${RTL_ACCEL}/pe.sv \
    && vvp accel_wrapper_tb.out | grep -E "PASS|FAIL|Results|ALL"

echo ""
echo "========================================"
echo "Test 2: All-ones weights, activations 1..8"
echo "========================================"
iverilog -g2012 -o accel_wrapper_tb2.out \
    ../tb/accel_wrapper_tb.sv \
    ${RTL_ACCEL}/accel_wrapper.sv \
    ${RTL_ACCEL}/accel_top.sv \
    ${RTL_ACCEL}/systolic_array_wrap.sv \
    ${RTL_ACCEL}/scratchpad.sv \
    ${RTL_ACCEL}/systolic_array.sv \
    ${RTL_ACCEL}/pe.sv \
    -s accel_wrapper_tb2 \
    && vvp accel_wrapper_tb2.out | grep -E "PASS|FAIL|Results|ALL"

echo ""
echo "========================================"
echo "Test 3: CPU pipeline MLOAD/MMUL/MSTORE"
echo "========================================"
iverilog -g2012 -o tb_cpu_accel.out \
    ../tb/tb_cpu_accel.sv \
    ${RTL_TOP}/cpu_top.sv \
    ${RTL_CPU}/fetch.sv \
    ${RTL_CPU}/decode.sv \
    ${RTL_CPU}/execute.sv \
    ${RTL_CPU}/hazard.sv \
    ${RTL_CPU}/regfile.sv \
    ${RTL_CPU}/memory_stage.sv \
    ${RTL_CPU}/writeback.sv \
    ${RTL_CPU}/bht.sv \
    ${RTL_ACCEL}/accel_wrapper.sv \
    ${RTL_ACCEL}/accel_top.sv \
    ${RTL_ACCEL}/systolic_array_wrap.sv \
    ${RTL_ACCEL}/scratchpad.sv \
    ${RTL_ACCEL}/systolic_array.sv \
    ${RTL_ACCEL}/pe.sv \
    && vvp tb_cpu_accel.out | grep -E "PASS|FAIL|Total|accel_done"
