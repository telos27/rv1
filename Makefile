# RV1 RISC-V Processor Makefile
# Supports multiple configurations: RV32I, RV32IM, RV64I, etc.

# Tools
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave
RISCV_PREFIX = riscv64-unknown-elf-
AS = $(RISCV_PREFIX)as
LD = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump

# Directories
RTL_DIR = rtl
TB_DIR = tb
SIM_DIR = sim
TEST_DIR = tests
WAVE_DIR = $(SIM_DIR)/waves
SCRIPT_DIR = tools

# RTL Sources
RTL_CORE = $(wildcard $(RTL_DIR)/core/*.v)
RTL_MEM = $(wildcard $(RTL_DIR)/memory/*.v)
RTL_CONFIG = $(RTL_DIR)/config/rv_config.vh
RTL_ALL = $(RTL_CORE) $(RTL_MEM)

# Testbenches
TB_UNIT = $(wildcard $(TB_DIR)/unit/*.v)
TB_INTEGRATION = $(wildcard $(TB_DIR)/integration/*.v)

# Assembly tests
ASM_TESTS = $(wildcard $(TEST_DIR)/asm/*.s)
HEX_TESTS = $(ASM_TESTS:$(TEST_DIR)/asm/%.s=$(TEST_DIR)/vectors/%.hex)

# Simulation parameters
CLK_PERIOD ?= 10
TIMEOUT ?= 10000

# Iverilog flags
IVERILOG_FLAGS = -g2012 -I $(RTL_DIR)

# Configuration presets
CONFIG_RV32I = -DCONFIG_RV32I
CONFIG_RV32IM = -DCONFIG_RV32IM
CONFIG_RV32IMC = -DCONFIG_RV32IMC
CONFIG_RV64I = -DCONFIG_RV64I
CONFIG_RV64GC = -DCONFIG_RV64GC

# Default target
.PHONY: all
all: help

.PHONY: help
help:
	@echo "RV1 RISC-V Processor Build System"
	@echo ""
	@echo "Configuration Targets:"
	@echo "  make rv32i          - Build RV32I configuration (default)"
	@echo "  make rv32im         - Build RV32IM configuration (with M extension)"
	@echo "  make rv32imc        - Build RV32IMC configuration (with M+C)"
	@echo "  make rv64i          - Build RV64I configuration (64-bit)"
	@echo "  make rv64gc         - Build RV64GC configuration (full-featured)"
	@echo ""
	@echo "Simulation Targets:"
	@echo "  make run-rv32i      - Run RV32I pipelined core"
	@echo "  make run-rv64i      - Run RV64I pipelined core"
	@echo "  make compliance     - Run RISC-V compliance tests (RV32I)"
	@echo ""
	@echo "Testing Targets:"
	@echo "  make test-unit      - Run all unit tests"
	@echo "  make test-core      - Run core integration test"
	@echo "  make test-alu       - Run ALU unit test"
	@echo "  make asm-tests      - Assemble all test programs"
	@echo ""
	@echo "Utility Targets:"
	@echo "  make clean          - Clean all generated files"
	@echo "  make waves          - Open waveform viewer"
	@echo "  make lint           - Run Verilator lint"
	@echo "  make info           - Show configuration info"
	@echo ""
	@echo "Variables:"
	@echo "  CLK_PERIOD=$(CLK_PERIOD)  - Clock period in ns"
	@echo "  TIMEOUT=$(TIMEOUT)        - Simulation timeout cycles"

# Create necessary directories
$(SIM_DIR) $(WAVE_DIR):
	@mkdir -p $@

#==============================================================================
# Configuration Build Targets
#==============================================================================

.PHONY: rv32i
rv32i: | $(SIM_DIR)
	@echo "Building RV32I configuration..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32I) \
		-o $(SIM_DIR)/rv32i_core.vvp $(RTL_ALL)
	@echo "✓ RV32I build complete: $(SIM_DIR)/rv32i_core.vvp"

.PHONY: rv32im
rv32im: | $(SIM_DIR)
	@echo "Building RV32IM configuration..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32IM) \
		-o $(SIM_DIR)/rv32im_core.vvp $(RTL_ALL)
	@echo "✓ RV32IM build complete: $(SIM_DIR)/rv32im_core.vvp"

.PHONY: rv32imc
rv32imc: | $(SIM_DIR)
	@echo "Building RV32IMC configuration..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32IMC) \
		-o $(SIM_DIR)/rv32imc_core.vvp $(RTL_ALL)
	@echo "✓ RV32IMC build complete: $(SIM_DIR)/rv32imc_core.vvp"

.PHONY: rv64i
rv64i: | $(SIM_DIR)
	@echo "Building RV64I configuration..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV64I) \
		-o $(SIM_DIR)/rv64i_core.vvp $(RTL_ALL)
	@echo "✓ RV64I build complete: $(SIM_DIR)/rv64i_core.vvp"

.PHONY: rv64gc
rv64gc: | $(SIM_DIR)
	@echo "Building RV64GC configuration..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV64GC) \
		-o $(SIM_DIR)/rv64gc_core.vvp $(RTL_ALL)
	@echo "✓ RV64GC build complete: $(SIM_DIR)/rv64gc_core.vvp"

#==============================================================================
# Pipelined Core Build Targets
#==============================================================================

.PHONY: pipelined-rv32i
pipelined-rv32i: | $(SIM_DIR)
	@echo "Building RV32I pipelined core..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32I) \
		-o $(SIM_DIR)/rv32i_pipelined.vvp \
		$(RTL_ALL) $(TB_DIR)/integration/tb_core_pipelined.v
	@echo "✓ RV32I pipelined build complete"

.PHONY: pipelined-rv64i
pipelined-rv64i: | $(SIM_DIR)
	@echo "Building RV64I pipelined core..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV64I) \
		-o $(SIM_DIR)/rv64i_pipelined.vvp \
		$(RTL_ALL) $(TB_DIR)/integration/tb_core_pipelined.v
	@echo "✓ RV64I pipelined build complete"

#==============================================================================
# Simulation Run Targets
#==============================================================================

.PHONY: run-rv32i
run-rv32i: pipelined-rv32i
	@echo "Running RV32I pipelined core simulation..."
	@$(VVP) $(SIM_DIR)/rv32i_pipelined.vvp | tee $(SIM_DIR)/rv32i_run.log
	@echo "Log saved to: $(SIM_DIR)/rv32i_run.log"

.PHONY: run-rv64i
run-rv64i: pipelined-rv64i
	@echo "Running RV64I pipelined core simulation..."
	@$(VVP) $(SIM_DIR)/rv64i_pipelined.vvp | tee $(SIM_DIR)/rv64i_run.log
	@echo "Log saved to: $(SIM_DIR)/rv64i_run.log"

#==============================================================================
# RISC-V Compliance Tests
#==============================================================================

.PHONY: compliance
compliance: pipelined-rv32i
	@echo "Running RISC-V compliance tests..."
	@if [ -x $(SCRIPT_DIR)/run_compliance_pipelined.sh ]; then \
		$(SCRIPT_DIR)/run_compliance_pipelined.sh; \
	else \
		echo "Warning: Compliance test script not found"; \
		echo "Expected: $(SCRIPT_DIR)/run_compliance_pipelined.sh"; \
	fi

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(SIM_DIR)/*.vvp $(SIM_DIR)/*.log
	@rm -rf $(WAVE_DIR)/*.vcd $(WAVE_DIR)/*.fst
	@rm -rf $(TEST_DIR)/vectors/*.hex $(TEST_DIR)/vectors/*.elf $(TEST_DIR)/vectors/*.o
	@rm -rf obj_dir
	@echo "Clean complete"

# Assemble test programs
.PHONY: asm-tests
asm-tests: $(HEX_TESTS)
	@echo "All assembly tests built"

$(TEST_DIR)/vectors/%.hex: $(TEST_DIR)/asm/%.s | $(SIM_DIR)
	@echo "Assembling $<..."
	@$(AS) -march=rv32i -mabi=ilp32 -o $(TEST_DIR)/vectors/$*.o $<
	@$(LD) -m elf32lriscv -T $(TEST_DIR)/linker.ld -o $(TEST_DIR)/vectors/$*.elf $(TEST_DIR)/vectors/$*.o
	@$(OBJCOPY) -O verilog $(TEST_DIR)/vectors/$*.elf $@
	@$(OBJDUMP) -D $(TEST_DIR)/vectors/$*.elf > $(TEST_DIR)/vectors/$*.dump
	@echo "Created $@"

# Unit tests
.PHONY: test-unit
test-unit: test-alu test-regfile test-decoder
	@echo "All unit tests complete"

.PHONY: test-alu
test-alu: | $(SIM_DIR) $(WAVE_DIR)
	@echo "Running ALU test..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32I) -o $(SIM_DIR)/tb_alu.vvp \
		$(RTL_DIR)/core/alu.v $(TB_DIR)/unit/tb_alu.v
	@$(VVP) $(SIM_DIR)/tb_alu.vvp | tee $(SIM_DIR)/alu.log
	@grep -q "PASS\|All tests passed" $(SIM_DIR)/alu.log && echo "✓ ALU test PASSED" || echo "✗ ALU test FAILED"

.PHONY: test-regfile
test-regfile: | $(SIM_DIR) $(WAVE_DIR)
	@echo "Running Register File test..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32I) -o $(SIM_DIR)/tb_regfile.vvp \
		$(RTL_DIR)/core/register_file.v $(TB_DIR)/unit/tb_register_file.v
	@$(VVP) $(SIM_DIR)/tb_regfile.vvp | tee $(SIM_DIR)/regfile.log
	@grep -q "PASS\|All tests passed" $(SIM_DIR)/regfile.log && echo "✓ Register File test PASSED" || echo "✗ Register File test FAILED"

.PHONY: test-decoder
test-decoder: | $(SIM_DIR) $(WAVE_DIR)
	@echo "Running Decoder test..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32I) -o $(SIM_DIR)/tb_decoder.vvp \
		$(RTL_DIR)/core/decoder.v $(TB_DIR)/unit/tb_decoder.v
	@$(VVP) $(SIM_DIR)/tb_decoder.vvp | tee $(SIM_DIR)/decoder.log
	@grep -q "PASS\|All tests passed" $(SIM_DIR)/decoder.log && echo "✓ Decoder test PASSED" || echo "✗ Decoder test FAILED"

# Integration tests
.PHONY: test-core
test-core: | $(SIM_DIR) $(WAVE_DIR)
	@echo "Running core integration test..."
	@$(IVERILOG) $(IVERILOG_FLAGS) $(CONFIG_RV32I) -o $(SIM_DIR)/tb_core.vvp \
		$(RTL_ALL) $(TB_DIR)/integration/tb_core.v
	@$(VVP) $(SIM_DIR)/tb_core.vvp | tee $(SIM_DIR)/core.log
	@grep -q "PASS\|Test PASSED" $(SIM_DIR)/core.log && echo "✓ Core test PASSED" || echo "✗ Core test FAILED"

# Run specific test program
.PHONY: run-test
run-test: | $(SIM_DIR) $(WAVE_DIR)
ifndef TEST
	@echo "Error: Please specify TEST=<name>"
	@echo "Example: make run-test TEST=fibonacci"
	@exit 1
endif
	@echo "Running test: $(TEST)"
	@$(IVERILOG) -g2012 -DMEM_FILE=\"$(TEST_DIR)/vectors/$(TEST).hex\" \
		-o $(SIM_DIR)/test_$(TEST).vvp $(RTL_ALL) $(TB_DIR)/integration/tb_core.v
	@$(VVP) $(SIM_DIR)/test_$(TEST).vvp | tee $(SIM_DIR)/$(TEST).log

# Waveform viewer
.PHONY: waves
waves:
ifndef WAVE
	@echo "Available waveforms:"
	@ls -1 $(WAVE_DIR)/*.vcd 2>/dev/null | xargs -n1 basename || echo "No waveforms found"
	@echo ""
	@echo "Usage: make waves WAVE=<name>"
else
	@$(GTKWAVE) $(WAVE_DIR)/$(WAVE).vcd &
endif

# Verilator lint
.PHONY: lint
lint:
	@echo "Running Verilator lint..."
	@verilator --lint-only -Wall --top-module rv32i_core $(RTL_ALL)

# Synthesis (using Yosys)
.PHONY: synth
synth:
	@echo "Running synthesis..."
	@yosys -p "read_verilog $(RTL_ALL); synth -top rv32i_core; stat"

# Documentation
.PHONY: docs
docs:
	@echo "Generating documentation..."
	@$(SCRIPT_DIR)/gen_docs.sh

# Check for required tools
.PHONY: check-tools
check-tools:
	@echo "Checking for required tools..."
	@command -v $(IVERILOG) >/dev/null 2>&1 || echo "Warning: iverilog not found"
	@command -v $(RISCV_PREFIX)gcc >/dev/null 2>&1 || echo "Warning: RISC-V toolchain not found"
	@command -v verilator >/dev/null 2>&1 || echo "Info: verilator not found (optional)"
	@command -v yosys >/dev/null 2>&1 || echo "Info: yosys not found (optional)"
	@echo "Tool check complete"

# Print configuration
.PHONY: info
info:
	@echo "RV1 RISC-V Processor Configuration"
	@echo "===================================="
	@echo ""
	@echo "RTL Configuration:"
	@echo "  Core modules:        $(words $(RTL_CORE))"
	@echo "  Memory modules:      $(words $(RTL_MEM))"
	@echo "  Total RTL files:     $(words $(RTL_ALL))"
	@echo "  Config file:         $(RTL_CONFIG)"
	@echo ""
	@echo "Available Configurations:"
	@echo "  RV32I   - 32-bit base ISA"
	@echo "  RV32IM  - 32-bit with multiply/divide"
	@echo "  RV32IMC - 32-bit with M+C extensions"
	@echo "  RV64I   - 64-bit base ISA"
	@echo "  RV64GC  - 64-bit full-featured"
	@echo ""
	@echo "Testing:"
	@echo "  Unit testbenches:    $(words $(TB_UNIT))"
	@echo "  Integration tests:   $(words $(TB_INTEGRATION))"
	@echo "  Assembly tests:      $(words $(ASM_TESTS))"
	@echo ""
	@echo "Build with: make <config>    (e.g., make rv32i)"
	@echo "Run with:   make run-<config> (e.g., make run-rv32i)"

.PHONY: .FORCE
.FORCE:
