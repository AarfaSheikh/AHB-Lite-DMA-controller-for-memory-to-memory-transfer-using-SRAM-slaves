#!/bin/bash

echo "Loading Questa..."
module load questa

echo "Creating library..."
vlib work
vmap work work

echo "Compiling files..."
vlog dma_defs_pkg.sv
vlog dma_controller.sv
vlog sram_ahb_subsystem.sv
vlog top_level_system.sv
vlog tb_top_level_system.sv

echo "Running simulation..."
vsim -c tb_top_level_system -do "run -all; quit"

echo "Done."