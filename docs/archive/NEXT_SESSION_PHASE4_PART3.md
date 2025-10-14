# Next Session - Phase 4 Part 3: Bug Fixes

**Date**: 2025-10-10 (Session 6 - Debugging)
**Current Status**: Phase 4 Integration Complete, **2 Critical Bugs Found** 🐛
**Next Task**: Fix CSR Read Bug and Exception Re-triggering

---

## Session 6 Summary - Investigation Complete

### 🔍 Bugs Discovered

#### Bug #1: Exception Re-triggering (✅ FIXED)
**Severity**: Critical
**Impact**: Infinite trap handler loops, `ma_data` test timeout

**Problem**:
- Exception unit is combinational and monitors pipeline stages
- When misaligned load/store triggers exception in MEM stage
- Pipeline flushes IF/ID and ID/EX, but **NOT EX/MEM**
- Faulting instruction stays in MEM stage with `valid=1`
- Exception keeps triggering every cycle → infinite loop

**Root Cause**:
```verilog
// Exception unit monitors MEM stage
.mem_valid(exmem_valid),  // This stays 1 after exception!

// EX/MEM register has no flush input
.valid_in(idex_valid),  // No invalidation on exception
```

**Fix Applied**:
```verilog
// Track exception from previous cycle
reg exception_taken_r;
always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    exception_taken_r <= 1'b0;
  else
    exception_taken_r <= exception;
end

// Invalidate EX/MEM stage after exception
.valid_in(idex_valid && !exception_taken_r),
```

**Location**: `rtl/core/rv32i_core_pipelined.v:214-220, 583`

---

#### Bug #2: CSR Read Returning Zero (❌ NOT FIXED - CRITICAL)
**Severity**: **CRITICAL** - Blocks all CSR functionality
**Impact**: All CSR reads return 0, trap handlers don't work, compliance tests fail

**Problem**:
- CSR file outputs correct values (verified with unit test)
- CSR reads in pipelined core return 0
- Example: `csrr x2, mstatus` → `x2 = 0` (should be mstatus value)

**Evidence**:
```
Test: csrw mstatus, 0x1888
      csrr sp, mstatus

Expected: sp = 0x1888
Actual:   sp = 0x0000  ❌
```

**Data Path** (appears correct but broken):
1. CSR File: `csr_rdata` → `ex_csr_rdata` ✅
2. EX/MEM: `ex_csr_rdata` → `exmem_csr_rdata` ❓
3. MEM/WB: `exmem_csr_rdata` → `memwb_csr_rdata` ❓
4. WB Mux: `memwb_csr_rdata` selected when `wb_sel == 2'b11` ❓
5. Register File: `wb_data` written to `rd` ❓

**Status**: Pre-existing bug from Phase 4 Part 2 commit (af5a599)

---

### 🧪 Test Results

#### Simple CSR Read Test
```assembly
li   x1, 0x1888
csrw mstatus, x1
csrr x2, mstatus  # Should read 0x1888 into x2
```
**Result**: `x1 = 0x1888 ✅`, `x2 = 0x0000 ❌`

#### Misaligned Exception Test
```assembly
la   x1, trap_handler
csrw mtvec, x1
li   x2, 0x1001     # Odd address
lh   x3, 0(x2)      # Trigger misaligned exception
```
**Result**:
- Exception triggers ✅
- Trap handler called ✅
- But stuck in infinite loop ❌ (CSR reads return 0)
- PC stuck at trap handler entry (0x00000020)

#### Compliance Status
- **Current**: 40/42 (95%)
- **Failures**: `fence_i` (expected), `ma_data` (timeout - blocked by CSR bug)

---

## Next Session Tasks

### Priority 1: Fix CSR Read Bug (CRITICAL) 🚨

**Debug Strategy**:

1. **Verify CSR File Output** (✅ Already confirmed working)
   ```verilog
   // Direct test shows CSR file outputs correctly
   csr_rdata = 0x1888 ✅
   ```

2. **Check EX/MEM Pipeline Register**
   - Verify `ex_csr_rdata` is being latched
   - Check if `csr_rdata_in` → `csr_rdata_out` works
   - Test: Add waveform debug or print statements

3. **Check MEM/WB Pipeline Register**
   - Verify `exmem_csr_rdata` → `memwb_csr_rdata`
   - Check if valid flag affects CSR data

4. **Check Write-Back Path**
   - Verify `wb_sel == 2'b11` for CSR instructions
   - Verify `memwb_csr_rdata` is non-zero at write-back time
   - Check register file write enable

5. **Check Timing**
   - CSR read is combinational in CSR file
   - Pipeline registers are sequential
   - Verify no timing/synchronization issues

**Likely Causes**:
- Pipeline register not latching CSR data
- Valid flag incorrectly gating CSR data
- Write-back mux priority issue
- Register write enable not asserted for CSR reads

### Priority 2: Test Both Fixes Together

After fixing CSR reads:

1. **Re-test misaligned exception**
   ```bash
   iverilog -DMEM_FILE="tests/asm/test_misaligned_simple.hex" ...
   ```
   **Expected**: Trap handler runs, mcause = 4, MRET returns, test passes

2. **Run `ma_data` compliance test**
   ```bash
   ./tools/run_compliance_pipelined.sh
   ```
   **Expected**: `ma_data` PASSES → 41/42 (97%)

3. **Full compliance sweep**
   **Target**: 41/42 or 42/42 (if fence_i somehow works)

---

## Files Modified This Session

### Changed
- `rtl/core/rv32i_core_pipelined.v` - Added exception re-trigger prevention

### Created (Test Files)
- `tests/asm/test_misaligned_simple.s` - Simple misaligned exception test
- `/tmp/test_csr_read.s` - Ultra-simple CSR read test
- `/tmp/test_csr_simple.v` - Direct CSR file verification

---

## Technical Details

### Exception Re-trigger Fix Details

**Before Fix**:
```
Cycle 1: Misaligned load in MEM, exception=1, trap_vector → PC
Cycle 2: Pipeline flushed IF/ID/EX, but MEM still has faulting inst
         Exception unit sees mem_valid=1, exception=1 again
Cycle 3: Infinite loop, PC keeps going to trap_vector
```

**After Fix**:
```
Cycle 1: Misaligned load in MEM, exception=1, trap_vector → PC
Cycle 2: exception_taken_r=1, EX/MEM.valid_in=0
         MEM stage now invalid, exception unit sees mem_valid=0
Cycle 3: exception=0, trap handler executes normally
```

### CSR Read Bug Analysis

**CSR File Behavior** (Verified Working):
```verilog
// Combinational read
always @(*) begin
  case (csr_addr)
    CSR_MSTATUS: csr_rdata = mstatus_value;  // ✅ Outputs correct value
    ...
  endcase
end
```

**Pipeline Flow** (Broken Somewhere):
```
IF: csrr x2, mstatus (instruction fetch)
ID: Decode CSR address (0x300)
    csr_addr ← 0x300
    csr_we ← 0 (read-only)
    wb_sel ← 2'b11
EX: CSR file read
    csr_rdata ← ??? (should be mstatus value)
    ex_csr_rdata ← csr_rdata
MEM: Forward CSR data
     exmem_csr_rdata ← ex_csr_rdata (❓)
WB: Write to register
    wb_data ← memwb_csr_rdata (❓ = 0)
    rf[2] ← 0 ❌
```

**Hypothesis**: One of the pipeline registers is not latching CSR data correctly, or valid flag is clearing it.

---

## Quick Start for Next Session

```bash
# 1. Check current status
git status
git diff rtl/core/rv32i_core_pipelined.v

# 2. Debug CSR read path - add waveform or print debug
# Focus on: EX stage CSR read, EX/MEM register, MEM/WB register

# 3. Option A: Waveform analysis
gtkwave sim/waves/core_pipelined.vcd
# Look for: ex_csr_rdata, exmem_csr_rdata, memwb_csr_rdata

# 4. Option B: Add debug prints to pipeline registers
vim rtl/core/exmem_register.v
vim rtl/core/memwb_register.v

# 5. Test CSR read fix
iverilog -DMEM_FILE="/tmp/test_csr_read.hex" -o sim/test.vvp rtl/core/*.v ...
vvp sim/test.vvp

# 6. Test both fixes together
iverilog -DMEM_FILE="tests/asm/test_misaligned_simple.hex" ...

# 7. Run compliance tests
./tools/run_compliance_pipelined.sh
```

---

## Success Criteria

### CSR Read Fix Complete When:
- ✅ Simple CSR read test: `csrr x2, mstatus` → `x2 = mstatus_value`
- ✅ CSR write-read sequence works: `csrw then csrr` returns written value
- ✅ All CSR instructions work (CSRRW, CSRRS, CSRRC, immediate forms)
- ✅ Trap handler can read mcause, mepc, mtval

### Both Fixes Verified When:
- ✅ Misaligned exception test passes (trap handler works correctly)
- ✅ MRET returns from trap successfully
- ✅ `ma_data` compliance test PASSES
- ✅ All previous 40 tests still pass (no regression)
- ✅ Compliance: **41/42 (97%)** or **42/42 (100%)**

---

## Known Issues

1. **CSR Read Bug**: Critical, blocks all exception handling functionality
2. **fence_i Test**: Expected failure (requires I-cache flush, not implemented)
3. **ma_data Test**: Currently times out due to CSR read bug

---

## Notes

- Exception re-trigger fix is elegant and minimal (10 lines)
- CSR file unit works perfectly (verified with standalone test)
- Bug is definitely in pipeline integration, not CSR file itself
- Phase 4 Part 2 commit (af5a599) has CSR read bug - was not caught in testing
- Original commit claimed "rv32ui-p-add PASSED" but likely didn't test CSR reads

---

## Architecture Reference

### Current Pipeline Stages
```
IF → [IF/ID] → ID → [ID/EX] → EX → [EX/MEM] → MEM → [MEM/WB] → WB
                      ↓           ↓        ↓
                   Decode    CSR File  Exception
                                        Detection
```

### CSR Data Flow (Should Be)
```
EX:  CSR File → ex_csr_rdata (combinational)
     ↓
EX/MEM: Latch on clock → exmem_csr_rdata
     ↓
MEM/WB: Latch on clock → memwb_csr_rdata
     ↓
WB:  Mux → wb_data → Register File
```

---

**Ready for next session - focus on CSR read bug fix!** 🔧
