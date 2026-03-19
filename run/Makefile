# ============================================================
# QuestaSim Makefile (run/ directory)
# ============================================================

TOP = tb_top_level_system

RTL_DIR = ../rtl
TB_DIR  = ../tb

SRCS = \
    $(RTL_DIR)/dma_defs_pkg.sv \
    $(RTL_DIR)/dma_controller.sv \
    $(RTL_DIR)/sram_ahb_subsystem.sv \
    $(RTL_DIR)/top_level_system.sv \
    $(TB_DIR)/tb_top_level_system.sv

# ============================================================
# Targets
# ============================================================

all: compile run

compile:
	module load questa &&\
	vlib work &&\
	vlog $(SRCS)

run:
	module load questa &&\
	vsim -c $(TOP) -do "run -all; quit"

gui:
	module load questa &&\
	vsim $(TOP)

clean:
	rm -rf work transcript vsim.wlf