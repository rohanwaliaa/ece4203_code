# ECE4203 Lab 1 — Makefile
#
# Targets
#   make sim              RTL simulation (iverilog, pre-synthesis)
#   make synth            Synthesise all bit widths with Yosys
#   make sta              Static timing analysis + SDF generation (OpenSTA)
#   make sim_gl WIDTH=N   Gate-level simulation with SDF back-annotation
#   make summary          Print area and WNS tables
#   make clean            Remove all generated files
#
# Typical workflow:
#   make sim              ← confirm RTL is correct first
#   make synth            ← map to sky130hd cells
#   make sta              ← timing analysis, produces .sdf files
#   make sim_gl WIDTH=8   ← gate-level sim with gate delays visible
#   make summary          ← tabulate area and slack

SHELL := /bin/bash

# ---------------------------------------------------------------
# Tool paths (all on PATH inside the Codespace / Docker image)
# ---------------------------------------------------------------
YOSYS    := yosys
STA      := sta        # OpenSTA, shipped with ORFS as 'sta'
IVERILOG := source /opt/oss-cad-suite/environment && iverilog
VVP      := source /opt/oss-cad-suite/environment && vvp
PYTHON   := python3

# ---------------------------------------------------------------
# sky130hd paths
# ---------------------------------------------------------------
# Liberty file — typical corner, 25 °C, 1.8 V
#LIBERTY := /OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
LIBERTY := ../pdk/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
# sky130 gate-level Verilog models (needed for gate-level simulation).
# These ship with the PDK inside OSS CAD Suite.
# Adjust if your container mounts the PDK elsewhere.
#SKY130_CELLS := /workspaces/ece4203_code/pdk/sky130_fd_sc_hd/verilog
SKY130_CELLS := ../pdk/sky130_fd_sc_hd/verilog
# ---------------------------------------------------------------
# Sweep parameters
# ---------------------------------------------------------------
WIDTHS  := 8 16 32 64

# Clock periods (ns) for STA.
# sky130hd typical adder carry-chain delays (no interconnect):
#   W=4 ~1ns  W=8 ~2ns  W=16 ~3.5ns  W=32 ~6ns  W=64 ~11ns
# These periods give a spread of PASS / MARGINAL / FAIL:
PERIODS := 1 4 16

# sky130hd FF setup time subtracted from the period to give ABC
# the combinational-only budget (ABC -D flag is in picoseconds).
ABC_SETUP_PS := 160

#NETLISTS := $(foreach W,$(WIDTHS),results/netlist_$(W).v)
#STA_LOGS := $(foreach W,$(WIDTHS),$(foreach P,$(PERIODS),results/sta_w$(W)p$(P).log))

# ---------------------------------------------------------------
# Default
# ---------------------------------------------------------------
.PHONY: all
all: sim synth sta summary

# ---------------------------------------------------------------
# 1. RTL simulation (pre-synthesis)
# ---------------------------------------------------------------
.PHONY: sim
sim: results/sim_rtl.log

results/sim_rtl.log: rtl/registered_adder.v sim/tb_rtl.v | results/
	@echo "=== RTL Simulation (WIDTH=8) ==="
	$(IVERILOG) -g2012 -D WIDTH=8 \
	    -o results/sim_rtl_exe \
	    sim/tb_rtl.v rtl/registered_adder.v
	$(VVP) results/sim_rtl_exe | tee $@
	@grep -q "9/9 tests passed" $@ && \
	    echo ">>> RTL sim PASSED <<<" || \
	    { echo ">>> RTL sim FAILED — fix RTL before synthesising <<<"; exit 1; }

# ---------------------------------------------------------------
# 2. Synthesis — one rule per WIDTH
# ---------------------------------------------------------------

# Convert period in ns to ps and subtract setup time
# $(1) = period as float string e.g. "4.0"
ns_to_ps = $(shell $(PYTHON) -c "print(int(float('$(1)') * 1000 - $(ABC_SETUP_PS)))")

.PHONY: synth
synth: $(foreach W,$(WIDTHS),$(foreach P,$(PERIODS),results/netlist_$(W)_$(P).v))

define SYNTH_RULE
results/netlist_$(1)_$(2).v: rtl/registered_adder.v synth/synth.tcl | results/
	@echo "=== Synthesis WIDTH=$(1) PERIOD=$(2)ns ABC budget=$(call ns_to_ps,$(2))ps ==="
	WIDTH=$(1) PERIOD=$(2) LIBERTY=$(LIBERTY) \
	    ABC_PERIOD_PS=$(call ns_to_ps,$(2)) \
	    $(YOSYS) -l results/yosys_$(1)_$(2).log -p "tcl synth/synth.tcl"
endef
$(foreach W,$(WIDTHS),$(foreach P,$(PERIODS),$(eval $(call SYNTH_RULE,$(W),$(P)))))

# ---------------------------------------------------------------
# 3. STA — generate SDC and OpenSTA script, run sta
# ---------------------------------------------------------------
.PHONY: sta
sta: $(foreach W,$(WIDTHS),$(foreach P,$(PERIODS),results/sta_w$(W)p$(P).log))

# Substitute __WIDTH__ and __PERIOD__ tokens into the SDC template.
# Pattern: constraints_w<WIDTH>p<PERIOD>.sdc

results/constraints_w%.sdc: synth/constraints.sdc.template | results/
	$(eval _W := $(word 1,$(subst p, ,$*)))
	$(eval _P := $(word 2,$(subst p, ,$*)))
	sed -e 's/__WIDTH__/$(_W)/g' -e 's/__PERIOD__/$(_P)/g' $< > $@

# Substitute tokens into the OpenSTA script template.
results/sta_w%.tcl: synth/sta.tcl.template | results/
	$(eval _W := $(word 1,$(subst p, ,$*)))
	$(eval _P := $(word 2,$(subst p, ,$*)))
	sed \
	    -e 's|__LIBERTY__|$(LIBERTY)|g' \
	    -e 's/__WIDTH__/$(_W)/g' \
	    -e 's/__PERIOD__/$(_P)/g' \
	    $< > $@

define STA_RULE
results/sta_w$(1)p$(2).log: \
        results/netlist_$(1)_$(2).v \
        results/constraints_w$(1)p$(2).sdc \
        results/sta_w$(1)p$(2).tcl | results/
	@echo "=== STA WIDTH=$(1) PERIOD=$(2)ns ==="
	$(STA) -exit results/sta_w$(1)p$(2).tcl | tee $$@
endef
$(foreach W,$(WIDTHS),$(foreach P,$(PERIODS),$(eval $(call STA_RULE,$(W),$(P)))))

# ---------------------------------------------------------------
# 4. Gate-level simulation with SDF back-annotation
#
# Usage:  make sim_gl WIDTH=8
#   (defaults to WIDTH=8 if not specified)
#
# Requires:
#   - results/netlist_<WIDTH>.v   (from make synth)
#   - results/netlist_<WIDTH>.sdf (from make sta)
#   - sky130 Verilog cell models at $(SKY130_CELLS)
# ---------------------------------------------------------------
WIDTH ?= 8
PERIOD ?= 4

#.PHONY: sim_gl
#sim_gl: results/netlist_$(WIDTH).v results/netlist_$(WIDTH).sdf
#	@echo "=== Gate-Level Simulation WIDTH=$(WIDTH) with SDF ==="
#	@if [ ! -f $(SKY130_CELLS)/sky130_fd_sc_hd.v ]; then \
#	    echo "ERROR: sky130 cell models not found at $(SKY130_CELLS)"; \
#	    echo "       Check SKY130_CELLS in Makefile and adjust path."; \
#	    exit 1; \
#	fi
#	$(IVERILOG) -g2012 -gspecify -ginterconnect \
#	    -D WIDTH=$(WIDTH) \
#	    -D SDF_FILE=\"results/netlist_$(WIDTH).sdf\" \
#	    -D VCD_FILE=\"results/gl_$(WIDTH).vcd\" \
#	    -o results/sim_gl_$(WIDTH)_exe \
#	    sim/tb_gl.v \
#	    results/netlist_$(WIDTH).v \
#	    $(SKY130_CELLS)/sky130_fd_sc_hd.v \
#	    $(SKY130_CELLS)/primitives.v
#	$(VVP) -M. results/sim_gl_$(WIDTH)_exe +sdfmax+tb_gl.dut | tee results/sim_gl_$(WIDTH).log
#	@echo ""
#	@echo "Open with:  gtkwave results/gl_$(WIDTH).vcd &"

# SDF is written by OpenSTA as a side effect of the STA run.
# Declare it so downstream targets can depend on it directly.
results/netlist_%_$(PERIOD).sdf: results/sta_w%p$(PERIOD).log ;

results/netlist_$(WIDTH)_$(PERIOD)_timed.v: \
        results/netlist_$(WIDTH)_$(PERIOD).v \
        results/sta_w$(WIDTH)p$(PERIOD).log | results/
	@echo "=== Injecting SDF delays WIDTH=$(WIDTH) PERIOD=$(PERIOD)ns ==="
	$(PYTHON) scripts/sdf_inject.py \
	    --sdf      results/netlist_$(WIDTH)_$(PERIOD).sdf \
	    --netlist  results/netlist_$(WIDTH)_$(PERIOD).v \
	    --cells    $(SKY130_CELLS)/sky130_fd_sc_hd.v \
	    --out      results/netlist_$(WIDTH)_$(PERIOD)_timed.v \
	    --wrappers results/netlist_$(WIDTH)_$(PERIOD)_wrappers.v

.PHONY: sim_timed
sim_timed: results/netlist_$(WIDTH)_$(PERIOD)_timed.v
	@echo "=== Gate-Level Sim WIDTH=$(WIDTH) PERIOD=$(PERIOD)ns ==="
		$(IVERILOG) -g2012 -g specify \
			-D WIDTH=$(WIDTH) \
			-D PERIOD=$(PERIOD) \
			-D VCD_FILE=\"results/timed_$(WIDTH)_$(PERIOD).vcd\" \
			-D FUNCTIONAL \
			-o results/sim_timed_$(WIDTH)_$(PERIOD)_exe \
			sim/tb_gl.v \
			results/netlist_$(WIDTH)_$(PERIOD)_wrappers.v \
			results/netlist_$(WIDTH)_$(PERIOD)_timed.v \
	    		$(SKY130_CELLS)/primitives.v \
	    		$(SKY130_CELLS)/sky130_fd_sc_hd.v 
		$(VVP) results/sim_timed_$(WIDTH)_$(PERIOD)_exe | tee results/sim_timed_$(WIDTH)_$(PERIOD).log
		@echo ""
		@echo "Waveform: results/timed_$(WIDTH)_$(PERIOD).vcd"
		@echo "Open with: gtkwave results/timed_$(WIDTH)_$(PERIOD).vcd &"

# ---------------------------------------------------------------
# 5. Summary tables
#
# Area table shows how ABC chooses differently at each period.
# WNS table shows timing result for each (WIDTH, PERIOD) pair.
# ---------------------------------------------------------------
.PHONY: summary
summary:
	@echo ""
	@echo "================================================================"
	@echo " ECE4203 Lab 1 — Area Summary (cells and area per WIDTH x PERIOD)"
	@echo "================================================================"
	@printf "  %-6s  %-7s  %-8s  %-12s\n" "WIDTH" "PERIOD" "Cells" "Area(um^2)"
	@printf "  %-6s  %-7s  %-8s  %-12s\n" "-----" "------" "-----" "----------"
	@for w in $(WIDTHS); do \
	    for p in $(PERIODS); do \
	        cells=$$(grep "Number of cells" results/yosys_$${w}_$${p}.log 2>/dev/null \
	                 | awk '{print $$NF}' | tail -1); \
	        area=$$(grep "Chip area" results/yosys_$${w}_$${p}.log 2>/dev/null \
	                | awk '{print $$NF}' | tail -1); \
	        printf "  %-6s  %-7s  %-8s  %-12s\n" \
	            "$$w" "$${p}ns" "$${cells:--}" "$${area:--}"; \
	    done; \
	done
	@echo ""
	@echo "================================================================"
	@echo " Timing — WNS / ns  (positive = pass, negative = fail)"
	@echo "================================================================"
	@printf "  %-6s" "WIDTH"
	@for p in $(PERIODS); do printf "  %9s" "$${p}ns"; done
	@echo ""
	@printf "  %-6s" "-----"
	@for p in $(PERIODS); do printf "  %9s" "---------"; done
	@echo ""
	@for w in $(WIDTHS); do \
	    printf "  %-6s" "$$w"; \
	    for p in $(PERIODS); do \
	        wns=$$(grep "^worst slack " results/sta_w$${w}p$${p}.log 2>/dev/null \
	               | awk '{print $$4}' | head -1); \
	        printf "  %9s" "$${wns:--}"; \
	    done; \
	    echo ""; \
	done
	@echo ""

# ---------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------
results/:
	mkdir -p $@

.PRECIOUS: results/constraints_w%.sdc results/sta_w%.tcl

.PHONY: clean
clean:
	rm -rf results/
