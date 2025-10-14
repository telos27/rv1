# Next Session - RV1 Parameterization Continuation

**Date**: 2025-10-10
**Session**: Parameterization Phase - Session 2
**Current Status**: 70% Complete - Core Datapath and Pipeline Parameterized
**Priority**: Complete remaining modules and integrate

---

## 🎯 Session Goals

### Primary Objective
Complete the parameterization of the RV1 RISC-V processor to support multiple configurations (RV32/RV64, various extensions, multicore).

### Success Criteria
1. ✅ All core modules parameterized with XLEN
2. ✅ Top-level core integrated with parameterized modules
3. ✅ Build system (Makefile) with configuration targets
4. ✅ RV32I regression test passes (40/42 compliance tests)
5. 🎯 Documentation complete and up-to-date

---

## ✅ What's Been Completed (Session 1)

### Configuration System ✅
- **File**: `rtl/config/rv_config.vh`
- **Status**: Complete
- **Features**:
  - XLEN parameter (32 or 64)
  - Extension enables (M, A, C, Zicsr, Zifencei)
  - Cache configuration parameters
  - Multicore parameters (NUM_CORES, ENABLE_COHERENCY)
  - 5 configuration presets (RV32I, RV32IM, RV32IMC, RV64I, RV64GC)

### Core Datapath Modules ✅ (5/5)
1. **ALU** (`rtl/core/alu.v`)
   - XLEN-wide operations
   - Dynamic shift amount: `$clog2(XLEN)` (5 bits for RV32, 6 for RV64)
   - Width-agnostic comparisons

2. **Register File** (`rtl/core/register_file.v`)
   - XLEN-wide registers: 32 x XLEN
   - x0 hardwired to zero for any XLEN
   - Internal forwarding preserved

3. **Decoder** (`rtl/core/decoder.v`)
   - XLEN-wide immediate outputs
   - Proper sign-extension: `{{(XLEN-12){sign}}, ...}`
   - Instruction input remains 32-bit (RISC-V standard)

4. **Data Memory** (`rtl/memory/data_memory.v`)
   - XLEN-wide addresses and data
   - RV64 instructions added:
     - LD (load doubleword): funct3 = 3'b011
     - SD (store doubleword): funct3 = 3'b011
     - LWU (load word unsigned): funct3 = 3'b110
   - Sign-extension for LW in RV64 mode

5. **Instruction Memory** (`rtl/memory/instruction_memory.v`)
   - XLEN-wide address input
   - 32-bit instruction output (always)
   - Word-aligned addressing for any XLEN

### Pipeline Registers ✅ (4/4)
6. **IF/ID** (`rtl/core/ifid_register.v`)
   - XLEN-wide PC
   - 32-bit instruction
   - Stall/flush logic unchanged

7. **ID/EX** (`rtl/core/idex_register.v`)
   - XLEN-wide: pc, rs1_data, rs2_data, imm, csr_wdata
   - All control signals unchanged
   - Flush logic preserved

8. **EX/MEM** (`rtl/core/exmem_register.v`)
   - XLEN-wide: alu_result, mem_write_data, pc_plus_4, csr_rdata, pc
   - Control signals unchanged

9. **MEM/WB** (`rtl/core/memwb_register.v`)
   - XLEN-wide: alu_result, mem_read_data, pc_plus_4, csr_rdata
   - Control signals unchanged

### Support Units ✅ (2/2)
10. **PC** (`rtl/core/pc.v`)
    - XLEN-wide program counter
    - Parameterized reset vector
    - Stall logic unchanged

11. **Branch Unit** (`rtl/core/branch_unit.v`)
    - XLEN-wide comparisons (signed and unsigned)
    - All 6 branch types supported

### Documentation ✅
- `docs/PARAMETERIZATION_GUIDE.md` - Comprehensive usage guide (400+ lines)
- `PARAMETERIZATION_PROGRESS.md` - Progress report with statistics

---

## ⏳ Remaining Work (Session 2 Tasks)

### Task 1: CSR File Parameterization
**File**: `rtl/core/csr_file.v`
**Priority**: HIGH
**Estimated Time**: 1-2 hours

**Requirements**:
- CSRs must be XLEN-wide (per RISC-V spec)
- RV32: 32-bit CSRs (mstatus, mepc, mcause, etc.)
- RV64: 64-bit CSRs with proper bit definitions
- Special handling for:
  - `mstatus`: Different fields for RV32 vs RV64
  - `mtvec`, `mepc`, `mtval`: XLEN-wide addresses
  - `mcause`: XLEN-wide with exception code in lower bits

**Key Changes**:
```verilog
// Before:
reg [31:0] mepc;
reg [31:0] mtval;

// After:
reg [XLEN-1:0] mepc;
reg [XLEN-1:0] mtval;
```

**Notes**:
- Some CSRs like `mvendorid`, `marchid` remain 32-bit even in RV64
- XLEN parameter affects CSR read/write data widths
- CSR address (12 bits) unchanged

---

### Task 2: Exception Unit Parameterization
**File**: `rtl/core/exception_unit.v`
**Priority**: HIGH
**Estimated Time**: 30-60 minutes

**Requirements**:
- XLEN-wide address fields for exception handling
- Exception detection logic unchanged (instruction-based)
- Priority encoding unchanged

**Key Changes**:
```verilog
// Before:
input  wire [31:0] pc_if;
input  wire [31:0] pc_id;
input  wire [31:0] alu_result;

// After:
input  wire [XLEN-1:0] pc_if;
input  wire [XLEN-1:0] pc_id;
input  wire [XLEN-1:0] alu_result;
```

**Notes**:
- Exception codes remain the same for RV32/RV64
- `mcause` format: MSB = interrupt flag, lower bits = code

---

### Task 3: Control Unit Updates
**File**: `rtl/core/control.v`
**Priority**: MEDIUM
**Estimated Time**: 30 minutes

**Requirements**:
- Minimal changes (control signals are binary, not data)
- May need RV64-specific instruction detection
  - RV64I adds: LD, SD, LWU, ADDIW, etc.
  - These have different opcodes/funct3 values

**Key Changes**:
- Potentially add XLEN parameter for conditional logic
- Detect RV64-specific instructions if needed
- Most control generation logic unchanged

**Notes**:
- Control signals (branch, jump, mem_read, etc.) are XLEN-agnostic
- Only instruction decoding may need updates for RV64

---

### Task 4: Top-Level Core Integration
**File**: `rtl/core/rv32i_core_pipelined.v` → **`rtl/core/rv_core_pipelined.v`**
**Priority**: CRITICAL
**Estimated Time**: 2-3 hours

**Requirements**:
1. Rename file to `rv_core_pipelined.v` (remove "32i" specificity)
2. Add XLEN parameter to module
3. Instantiate all parameterized modules with XLEN
4. Add extension enable logic using `generate` blocks
5. Update all internal signals to XLEN width

**Template**:
```verilog
`include "config/rv_config.vh"

module rv_core_pipelined #(
  parameter XLEN = `XLEN,
  parameter ENABLE_M_EXT = `ENABLE_M_EXT,
  parameter ENABLE_A_EXT = `ENABLE_A_EXT
) (
  input  wire             clk,
  input  wire             rst_n,
  // ... other ports
);

  // XLEN-wide signals
  wire [XLEN-1:0] pc_if, pc_id, pc_ex;
  wire [XLEN-1:0] rs1_data, rs2_data;
  wire [XLEN-1:0] alu_result;
  // ... etc

  // Instantiate modules with XLEN
  alu #(.XLEN(XLEN)) alu_inst (...);
  register_file #(.XLEN(XLEN)) rf_inst (...);

  // Extension instantiation
  generate
    if (ENABLE_M_EXT) begin : gen_m_ext
      // Multiply/divide unit
    end
  endgenerate

endmodule
```

**Critical Areas**:
- PC calculation and updates
- Forwarding paths
- Branch target calculation
- Memory address generation
- Write-back data multiplexing

**Testing**:
- After integration, verify with simple RV32I tests first
- Check that all pipeline stages properly handle XLEN signals

---

### Task 5: Build System (Makefile)
**File**: `Makefile` (root directory)
**Priority**: HIGH
**Estimated Time**: 1 hour

**Requirements**:
Create build targets for different configurations:

```makefile
# Makefile for RV1 RISC-V Processor

# Configuration
INC_PATH = -I rtl/config
SIM = iverilog -g2012 $(INC_PATH)
RUN = vvp

# Source files
RTL_CORE = rtl/core/*.v
RTL_MEM  = rtl/memory/*.v
RTL_ALL  = $(RTL_CORE) $(RTL_MEM)

# Testbench
TB_PIPELINED = tb/integration/tb_core_pipelined.v

# Build targets
.PHONY: all rv32i rv32im rv64i clean

# Default: RV32I
all: rv32i

# RV32I - Base 32-bit ISA
rv32i:
	$(SIM) -DCONFIG_RV32I -o sim/rv32i.vvp $(RTL_ALL) $(TB_PIPELINED)
	@echo "Built RV32I configuration"

# RV32IM - 32-bit with multiply/divide
rv32im:
	$(SIM) -DCONFIG_RV32IM -o sim/rv32im.vvp $(RTL_ALL) $(TB_PIPELINED)
	@echo "Built RV32IM configuration"

# RV64I - 64-bit base ISA
rv64i:
	$(SIM) -DCONFIG_RV64I -o sim/rv64i.vvp $(RTL_ALL) $(TB_PIPELINED)
	@echo "Built RV64I configuration"

# Run simulation
run-%:
	$(RUN) sim/$*.vvp

# Clean
clean:
	rm -f sim/*.vvp sim/*.vcd

# Help
help:
	@echo "Available targets:"
	@echo "  make rv32i     - Build RV32I (default)"
	@echo "  make rv32im    - Build RV32IM (with M extension)"
	@echo "  make rv64i     - Build RV64I (64-bit)"
	@echo "  make run-rv32i - Run RV32I simulation"
	@echo "  make clean     - Clean build artifacts"
```

---

### Task 6: Regression Testing
**Priority**: CRITICAL
**Estimated Time**: 2-3 hours

**Requirements**:
1. Verify RV32I configuration still passes 40/42 compliance tests
2. Update testbenches if needed for XLEN parameters
3. Document any failures or changes

**Steps**:
```bash
# 1. Build RV32I configuration
make rv32i

# 2. Run compliance tests
./tools/run_compliance_pipelined.sh

# 3. Verify results
cat sim/compliance_results.txt
```

**Expected Results**:
- 40/42 tests passing (same as before)
- fence_i: Expected failure (no I-cache)
- ma_data: Expected failure (no trap handling yet)

**If failures occur**:
- Check module instantiation (XLEN parameters passed correctly?)
- Verify signal widths in top-level connections
- Check for `32` hardcoded values that should be `XLEN`

---

### Task 7: Update Documentation
**Priority**: MEDIUM
**Estimated Time**: 30 minutes

**Files to Update**:
1. **PHASES.md** - Add Phase 5: Parameterization
2. **README.md** - Add configuration options
3. **ARCHITECTURE.md** - Document parameterization approach
4. **IMPLEMENTATION.md** - List parameterized modules

**Phase 5 Entry for PHASES.md**:
```markdown
## Phase 5: Parameterization and Multi-Configuration Support

**Goal**: Enable multiple processor configurations (RV32/RV64, extensions, multicore)

**Status**: COMPLETED (2025-10-10)

### Achievements
- ✅ Central configuration system (rv_config.vh)
- ✅ 11 core modules parameterized for XLEN
- ✅ 5 configuration presets (RV32I, RV32IM, RV32IMC, RV64I, RV64GC)
- ✅ Build system with configuration targets
- ✅ RV32I regression test passed (40/42 - no regression)

### Deliverables
- Configuration system with presets
- Parameterized core datapath and pipeline
- Build system (Makefile)
- Comprehensive documentation
```

---

## 📋 Quick Start for Next Session

### 1. Verify Current State
```bash
cd /home/lei/rv1
git status
git log --oneline -5
```

### 2. List Parameterized Files
```bash
grep -l "parameter XLEN" rtl/core/*.v rtl/memory/*.v
```

### 3. Check Remaining Work
```bash
ls -la rtl/core/csr_file.v
ls -la rtl/core/exception_unit.v
ls -la rtl/core/control.v
ls -la rtl/core/rv32i_core_pipelined.v
```

### 4. Start with CSR File
```bash
# Open CSR file and start parameterizing
code rtl/core/csr_file.v
```

---

## 🔧 Key Commands Reference

### Build Commands
```bash
# RV32I (default)
iverilog -g2012 -DCONFIG_RV32I -I rtl/config -o sim/test.vvp rtl/**/*.v tb/**/*.v

# RV64I
iverilog -g2012 -DCONFIG_RV64I -I rtl/config -o sim/test.vvp rtl/**/*.v tb/**/*.v

# Custom configuration
iverilog -g2012 -DXLEN=64 -DENABLE_M_EXT=1 -I rtl/config -o sim/test.vvp rtl/**/*.v tb/**/*.v
```

### Testing Commands
```bash
# Run compliance tests
./tools/run_compliance_pipelined.sh

# Run specific test
make run-rv32i

# Check results
cat sim/compliance_results.txt
```

---

## 📊 Progress Tracking

| Task | Status | Est. Time | Priority |
|------|--------|-----------|----------|
| CSR File | ⏳ Pending | 1-2h | HIGH |
| Exception Unit | ⏳ Pending | 0.5-1h | HIGH |
| Control Unit | ⏳ Pending | 0.5h | MEDIUM |
| Top-Level Integration | ⏳ Pending | 2-3h | CRITICAL |
| Build System (Makefile) | ⏳ Pending | 1h | HIGH |
| Regression Testing | ⏳ Pending | 2-3h | CRITICAL |
| Documentation Update | ⏳ Pending | 0.5h | MEDIUM |
| **TOTAL** | **0/7** | **7-12h** | - |

---

## 🚨 Potential Issues to Watch

### 1. CSR Width Mismatches
- Some CSRs are XLEN-wide, others are fixed 32-bit
- `misa`, `mvendorid`, `marchid`, `mimpid` are always 32-bit in RV32, XLEN in RV64
- Check RISC-V privilege spec for exact definitions

### 2. Sign-Extension Edge Cases
- Immediate sign-extension must extend to XLEN bits
- Memory loads (LW in RV64) need sign-extension
- Upper immediate instructions (LUI) behavior in RV64

### 3. Module Instantiation
- Every module instantiation must pass XLEN parameter
- Missing parameters will use default (may cause width mismatches)
- Use linter or synthesis to catch mismatches

### 4. Testbench Updates
- Testbenches may need XLEN parameters
- Monitor widths in waveforms
- Expected values may change for RV64

---

## 📚 Reference Documents

**Created This Session**:
1. `rtl/config/rv_config.vh` - Configuration header
2. `docs/PARAMETERIZATION_GUIDE.md` - Usage guide
3. `PARAMETERIZATION_PROGRESS.md` - Progress report
4. `NEXT_SESSION_PARAMETERIZATION.md` - This file

**Existing Documentation**:
- `CLAUDE.md` - Project instructions
- `PHASES.md` - Development phases
- `ARCHITECTURE.md` - Design details
- `README.md` - Project overview

---

## 💡 Tips for Next Session

1. **Start with CSR file** - It's the most complex remaining module
2. **Test incrementally** - After each module, try to compile
3. **Use grep to find hardcoded widths** - Search for `[31:0]` patterns
4. **Check RISC-V spec** - CSR definitions differ between RV32 and RV64
5. **Save integration for last** - Top-level is complex, do it when all modules are ready

---

## 🎯 Success Criteria Checklist

- [ ] CSR file parameterized and compiles
- [ ] Exception unit parameterized and compiles
- [ ] Control unit updated (if needed)
- [ ] Top-level core integrated with all parameterized modules
- [ ] Makefile created with at least 3 targets (rv32i, rv32im, rv64i)
- [ ] RV32I regression test passes (40/42 tests)
- [ ] No compilation errors or warnings
- [ ] Documentation updated in PHASES.md
- [ ] Session summary created

---

## 📞 Quick Reference

**Current XLEN Parameter Locations**:
- `rtl/config/rv_config.vh` - Default definition
- All parameterized modules use `parameter XLEN = \`XLEN`
- Instantiations pass `.XLEN(XLEN)` or `.XLEN(32)` / `.XLEN(64)`

**Configuration Presets**:
- `-DCONFIG_RV32I` - 32-bit base
- `-DCONFIG_RV32IM` - 32-bit with multiply
- `-DCONFIG_RV32IMC` - 32-bit with M and compressed
- `-DCONFIG_RV64I` - 64-bit base
- `-DCONFIG_RV64GC` - 64-bit full-featured

**Files to Parameterize** (Remaining):
1. `rtl/core/csr_file.v`
2. `rtl/core/exception_unit.v`
3. `rtl/core/control.v` (minimal)
4. `rtl/core/rv32i_core_pipelined.v` (rename and integrate)

---

**Good luck with the next session! The foundation is solid - just need to finish CSR/exception handling and integrate everything together!**

---

**Last Updated**: 2025-10-10
**Session**: Parameterization Phase - Session 1 Complete
**Next Session**: Complete remaining modules and integration
