#!/bin/bash
set -e

RTL_CPU=../rtl/cpu
RTL_ACCEL=../rtl/accel
RTL_TOP=../rtl/top

cd "$(dirname "$0")"

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
    && echo "Compile OK" \
    && vvp tb_cpu_accel.out
