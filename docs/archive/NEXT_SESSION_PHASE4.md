# Next Session - Phase 4 Integration

**Date**: 2025-10-10 (Session 5 Complete)
**Current Status**: Phase 4 Infrastructure Complete ✅
**Next Task**: Pipeline Integration 🚧

---

## Session 5 Summary

### ✅ Completed
1. **CSR Register File** - 254 lines, 30/30 tests ✅
2. **Decoder CSR Support** - 105 lines, 63/63 tests ✅
3. **Control Unit CSR Support** - 225 lines, 63/63 tests ✅
4. **Exception Detection Unit** - 139 lines, 46/46 tests ✅
5. **Documentation** - Phase 4 plan complete
6. **Total Tests**: 139/139 PASSING (100%) 🎉

### 📊 Progress
- **Phase 4 Completion**: ~60%
- **Next Major Task**: Pipeline integration (largest component)
- **Estimated Remaining**: 2-3 hours integration + 1-2 hours testing

---

## Next Session: Pipeline Integration

### 🎯 Primary Goal
Integrate CSR file and exception unit into the pipelined core (`rv32i_core_pipelined.v`)

### 📋 Task Breakdown

#### 1. Update Pipeline Registers (30 min)
**Files**: `rtl/core/idex_register.v`, `rtl/core/exmem_register.v`, `rtl/core/memwb_register.v`

Add signals to pipeline registers:
- **ID/EX**:
  - `csr_addr[11:0]`
  - `csr_we`
  - `csr_src`
  - `csr_wdata[31:0]` (rs1 data or uimm)
  - `is_ecall`, `is_ebreak`, `is_mret`
  - `illegal_inst`

- **EX/MEM**:
  - `csr_addr[11:0]`
  - `csr_we`
  - `csr_rdata[31:0]` (from CSR file)

- **MEM/WB**:
  - `csr_rdata[31:0]`

#### 2. Instantiate New Modules (15 min)
**File**: `rtl/core/rv32i_core_pipelined.v`

Add module instances:
```verilog
// CSR File
csr_file csr_file_inst (
    .clk(clk),
    .reset_n(reset_n),
    .csr_addr(ex_csr_addr),
    .csr_wdata(ex_csr_wdata),
    .csr_op(ex_funct3),  // funct3 encodes operation
    .csr_we(ex_csr_we),
    .csr_rdata(csr_rdata),
    .trap_entry(trap_entry),
    .trap_pc(exception_pc),
    .trap_cause(exception_code),
    .trap_val(exception_val),
    .trap_vector(trap_vector),
    .mret(ex_mret),
    .mepc_out(mepc),
    .mstatus_mie(mstatus_mie),
    .illegal_csr(illegal_csr)
);

// Exception Unit
exception_unit exception_unit_inst (
    .if_pc(if_pc),
    .if_valid(if_valid),
    .id_illegal_inst(id_illegal_inst | illegal_csr),
    .id_ecall(id_ecall),
    .id_ebreak(id_ebreak),
    .id_pc(id_pc),
    .id_instruction(id_instruction),
    .id_valid(id_valid),
    .mem_addr(mem_alu_result),
    .mem_read(mem_mem_read),
    .mem_write(mem_mem_write),
    .mem_funct3(mem_funct3),
    .mem_pc(mem_pc),
    .mem_instruction(mem_instruction),
    .mem_valid(mem_valid),
    .exception(exception),
    .exception_code(exception_code),
    .exception_pc(exception_pc),
    .exception_val(exception_val)
);
```

#### 3. Wire CSR Data Path (30 min)
**File**: `rtl/core/rv32i_core_pipelined.v`

- Wire CSR signals through pipeline:
  - ID stage: extract CSR address, prepare write data
  - EX stage: CSR read/write occurs here
  - MEM stage: forward CSR read data
  - WB stage: write CSR data to register file

- Update write-back mux:
```verilog
assign wb_data = (memwb_wb_sel == 2'b00) ? memwb_alu_result :
                 (memwb_wb_sel == 2'b01) ? memwb_mem_data :
                 (memwb_wb_sel == 2'b10) ? memwb_pc_plus_4 :
                 (memwb_wb_sel == 2'b11) ? memwb_csr_rdata :  // NEW
                                           32'h0;
```

#### 4. Implement Trap Handling (45 min)
**File**: `rtl/core/rv32i_core_pipelined.v`

**Trap Entry**:
```verilog
wire trap_entry = exception;
wire trap_flush = trap_entry;

// PC update on trap
wire [31:0] trap_pc = trap_entry ? trap_vector : pc_next;

// Flush pipeline on trap
wire if_flush = trap_flush || branch_taken || jump;
wire id_flush = trap_flush || branch_taken || jump;
wire ex_flush = trap_flush || branch_taken;
```

**MRET Handling**:
```verilog
// MRET in EX stage
wire ex_mret = ex_is_mret && ex_valid;

// PC update on MRET
wire [31:0] mret_pc = mepc;
wire mret_flush = ex_mret;

// Combine with trap flush
wire total_flush = trap_flush || mret_flush || branch_taken || jump;
```

#### 5. Update Forwarding Logic (30 min)
**File**: `rtl/core/rv32i_core_pipelined.v`

CSR data needs forwarding like ALU results:
```verilog
// Forward CSR data if CSR instruction in EX/MEM or MEM/WB
// Similar to existing forwarding, but for CSR reads
```

#### 6. Add Exception Prevention (15 min)
**File**: `rtl/core/rv32i_core_pipelined.v`

Prevent faulting instructions from committing:
```verilog
// If exception in MEM stage, don't write register or memory
wire mem_reg_write_gated = mem_reg_write && !exception;
wire mem_mem_write_gated = mem_mem_write && !exception;
```

---

### 🧪 Testing Plan

#### Unit Tests (30 min)
1. Test CSR instructions individually:
   - CSRRW, CSRRS, CSRRC
   - CSRRWI, CSRRSI, CSRRCI

2. Create `tests/asm/test_csr_basic.s`:
```assembly
# Test CSR read/write
li   x1, 0x1800        # mstatus value (MPP=11, MIE=1)
csrrw x2, mstatus, x1  # Write x1 to mstatus, read old to x2
csrrs x3, mstatus, x0  # Read mstatus to x3 (no write)
csrrc x4, mie, x0      # Read mie to x4
```

#### Exception Tests (30 min)
1. Create `tests/asm/test_exceptions.s`:
```assembly
# Test ECALL
ecall                  # Should trap to handler

# Trap handler
csrr x1, mepc          # Read exception PC
csrr x2, mcause        # Read cause (should be 11)
mret                   # Return from trap
```

2. Create `tests/asm/test_misaligned.s`:
```assembly
# Test misaligned load
li   x1, 0x1001        # Odd address
lh   x2, 0(x1)         # Should trap (misaligned halfword)
```

#### Integration Tests (30 min)
1. Run all Phase 1-3 tests to ensure no regression
2. Run compliance tests: target **41/42** (ma_data should now pass!)

---

### 📁 Files to Modify

#### Core Pipeline
- `rtl/core/rv32i_core_pipelined.v` - Main integration (MAJOR CHANGES)

#### Pipeline Registers (Minor updates)
- `rtl/core/idex_register.v` - Add CSR signals
- `rtl/core/exmem_register.v` - Add CSR signals
- `rtl/core/memwb_register.v` - Add CSR signals

#### Testbenches (New)
- `tb/integration/tb_core_pipelined_csr.v` - CSR integration test
- `tests/asm/test_csr_basic.s` - CSR instruction test
- `tests/asm/test_exceptions.s` - Exception test
- `tests/asm/test_misaligned.s` - Misaligned access test

---

### ⚠️ Critical Integration Points

1. **CSR Write Timing**: CSR operations happen in EX stage
2. **Exception Timing**: Exceptions detected across multiple stages, handled at commit
3. **Pipeline Flush**: Must flush IF/ID/EX on trap, ensure no instructions commit
4. **PC Update**: Multiple sources (PC+4, branch, jump, trap_vector, mepc)
5. **Forwarding**: CSR read data must be forwarded to dependent instructions

---

### 🎯 Success Criteria

#### Integration Complete When:
- ✅ All CSR instructions execute correctly
- ✅ ECALL/EBREAK trigger exceptions
- ✅ Exception handler invoked (PC → mtvec)
- ✅ MRET returns correctly (PC ← mepc)
- ✅ Misaligned access detected and trapped
- ✅ Pipeline flush works correctly
- ✅ No instruction commits after exception

#### Testing Complete When:
- ✅ All Phase 1-3 tests still pass (no regression)
- ✅ CSR instruction tests pass
- ✅ Exception tests pass
- ✅ Compliance tests: **41/42 or 42/42** (ma_data + fence_i)
- ✅ Pipeline timing verified in waveforms

---

### 📊 Expected Results

**Compliance Test Prediction**:
- Current: 40/42 (95%)
- After Phase 4: **41/42 (97%)** or **42/42 (100%)**
  - `ma_data` ✅ (misaligned access trap - will pass)
  - `fence_i` ❓ (cache coherency - may still fail without cache)

---

### 🐛 Potential Issues to Watch

1. **Pipeline Flush Timing**:
   - Ensure exception detected in MEM doesn't allow instruction to commit
   - Flush earlier stages when exception occurs

2. **CSR Forwarding**:
   - CSR read in EX, used by next instruction
   - Need forwarding path from EX/MEM

3. **Multiple Exceptions**:
   - Priority encoder ensures only one reported
   - Earlier stages have priority

4. **MRET Timing**:
   - Jump to mepc must flush IF/ID stages
   - Restore mstatus correctly

5. **Valid Flags**:
   - Ensure valid flags propagate correctly
   - Flushed instructions marked invalid

---

### 🚀 Quick Start for Next Session

```bash
# 1. Check current status
git status
git log --oneline -5

# 2. Start with pipeline register updates
vim rtl/core/idex_register.v

# 3. Then modify main core
vim rtl/core/rv32i_core_pipelined.v

# 4. Compile and test incrementally
iverilog -g2012 -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp

# 5. Run compliance tests when integration complete
./tools/run_compliance_pipelined.sh
```

---

## 📈 Phase 4 Roadmap

```
Phase 4.1: CSR Register File          ✅ DONE (Session 5)
Phase 4.2: Decoder & Control Updates  ✅ DONE (Session 5)
Phase 4.3: Exception Detection Unit   ✅ DONE (Session 5)
Phase 4.4: Pipeline Integration       🚧 NEXT (Session 6) ← YOU ARE HERE
Phase 4.5: Testing & Compliance       ⏳ PENDING (Session 6)
```

**Estimated Time Remaining**: 3-5 hours total (2-3 hrs integration, 1-2 hrs testing)

---

**Ready to complete Phase 4! 🚀**
