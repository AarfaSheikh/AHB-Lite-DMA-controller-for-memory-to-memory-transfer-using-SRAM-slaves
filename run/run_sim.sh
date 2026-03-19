#!/bin/bash

echo "Loading Questa..."
module load questa

echo "Creating library..."
vlib work
vmap work work

echo "Compiling RTL..."
vlog ../rtl/dma_defs_pkg.sv
vlog ../rtl/dma_controller.sv
vlog ../rtl/sram_ahb_subsystem.sv
vlog ../rtl/top_level_system.sv

echo "Compiling Testbench..."
vlog ../tb/tb_top_level_system.sv

echo "Running simulation..."
vsim -c tb_top_level_system -do "run -all; quit"

echo "Done."