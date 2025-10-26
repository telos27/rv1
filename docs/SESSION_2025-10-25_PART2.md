# Development Session Summary - 2025-10-25 Part 2

## Session Goal
Debug and fix the failing `test_fp_compare_simple` regression that appeared after exception latching fixes.

## Issues Investigated

### Issue #1: test_fp_compare_simple Timeout/Infinite Loop ✅ FIXED

**Symptoms:**
- Test timing out after 49,999 cycles
- Quick regression showing 13/14 tests passing (test_fp_compare_simple failing)
- Infinite loop detected - program restarting from PC=0 repeatedly
- x28 register showing 0 (no test completion marker)

**Root Cause Analysis:**

1. **Configuration Mismatch (Critical)**
   - **Problem**: Tests compiled with `-march=rv32imafc` (includes C extension)
   - **Problem**: Testbench compiled with `-DCONFIG_RV32I` which sets `ENABLE_C_EXT=0`
   - **Impact**: CPU treated 2-byte aligned PCs (0x16, 0x1a, etc.) as misaligned
   - **Result**: Exception code 0 (instruction address misaligned) at PC=0x16
   - **Loop**: Exception → jump to mtvec (0x00000000) → program restarts → repeat

2. **EBREAK Detection Broken (Critical)**
   - **Problem**: Recent exception latching fix made EBREAK properly trap
   - **Problem**: Testbench checked for EBREAK in IF stage AFTER trap occurred
   - **Impact**: After trap, IF stage fetched from trap vector (NOPs at address 0)
   - **Result**: Testbench never detected EBREAK, ran to MAX_CYCLES timeout

**Investigation Process:**

1. **Initial Trace**: Discovered PC incrementing normally, then jumping to 0
2. **Memory Check**: Verified hex file was valid and loaded correctly
3. **PC Analysis**: Found PC starting at 0x00000000 instead of 0x80000000
4. **Address Mismatch**: Realized testbench uses RESET_VEC=0x00000000 for non-compliance tests
5. **Recompilation**: Rebuilt test with `-addr=0x00000000` - still failed
6. **Instruction Trace**: Found all instructions were NOPs (0x00000013)
7. **Loading Issue**: Discovered MEM_FILE parameter wasn't being passed correctly
8. **Exception Discovery**: Found exception code 0 at PC=0x00000016
9. **Alignment Check**: Verified 0x16 is 2-byte aligned (bit[0]=0)
10. **Configuration Root Cause**: Discovered `ENABLE_C_EXT=0` in CONFIG_RV32I
11. **EBREAK Detection**: Realized compressed EBREAK (0x9002) vs uncompressed (0x00100073)
12. **Testbench Fix**: Updated to check ID stage instead of IF stage

**Fixes Applied:**

1. **Configuration Fix** (`tools/test_pipelined.sh`)
   ```bash
   # Old (incorrect):
   CONFIG_FLAG="-DCONFIG_RV32I"

   # New (correct):
   CONFIG_FLAG="-DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1"
   ```
   - Enables all extensions to match test compilation
   - Allows proper execution of compressed instructions
   - Prevents spurious misalignment exceptions

2. **EBREAK Detection Fix** (`tb/integration/tb_core_pipelined.v`)
   ```verilog
   // Old (incorrect):
   if (instruction == 32'h00100073) begin  // IF stage, uncompressed only

   // New (correct):
   if (DUT.ifid_instruction == 32'h00100073 || DUT.ifid_instruction == 32'h9002 ||
       DUT.if_instruction == 32'h00100073 || DUT.if_instruction == 32'h9002) begin
   ```
   - Checks ID stage instead of IF (before trap occurs)
   - Supports both compressed (0x9002) and uncompressed (0x00100073) EBREAK
   - Works correctly with trapping exceptions

**Results:**
- ✅ test_fp_compare_simple now passes
- ✅ Quick regression: 14/14 tests passing (100%)
- ✅ No regressions introduced
- ✅ All tests complete in ~3 seconds

## Files Modified

### 1. `tools/test_pipelined.sh`
**Lines Modified**: 33-48
**Changes**:
- Removed `-DCONFIG_RV32I` flag that disabled C extension
- Added explicit extension enables: `-DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1`
- Added comment explaining the need for all extensions
- Updated both RV32 and RV64 configurations

**Before:**
```bash
CONFIG_FLAG="-DCONFIG_RV32I"
```

**After:**
```bash
# Enable all extensions to match test compilation (rv32imafc)
CONFIG_FLAG="-DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1"
```

### 2. `tb/integration/tb_core_pipelined.v`
**Lines Modified**: 185-194
**Changes**:
- Changed EBREAK detection from IF stage to ID stage
- Added support for compressed EBREAK encoding (0x9002)
- Added debug output showing both instruction formats
- Added detailed comments explaining the change

**Before:**
```verilog
// Check for EBREAK (0x00100073) in IF stage
if (instruction == 32'h00100073) begin
```

**After:**
```verilog
// Check for EBREAK in ID stage (before trap)
// EBREAK can be either:
//   - Compressed: 0x9002 (C.EBREAK) - 16-bit encoding
//   - Uncompressed: 0x00100073 - 32-bit encoding
// We check ID stage instead of IF because EBREAK causes a trap,
// and the IF stage will immediately fetch from mtvec (trap vector)
if (DUT.ifid_instruction == 32'h00100073 || DUT.ifid_instruction == 32'h9002 ||
    DUT.if_instruction == 32'h00100073 || DUT.if_instruction == 32'h9002) begin
  $display("[%0d] EBREAK DETECTED! ifid_instr=%08h if_instr=%08h PC=%08h",
           cycle_count, DUT.ifid_instruction, DUT.if_instruction, pc);
```

### 3. `CLAUDE.md`
**Changes**:
- Added new session summary (2025-10-25 Part 2)
- Updated Known Issues section with U-mode test failures
- Moved SRET/CSR hazard to lower priority (documented, not blocking)
- Updated progress status

## Test Results

### Quick Regression (make test-quick)
```
Total:   14 tests
Passed:  14 ✅
Failed:  0
Time:    3s
```

**All Tests Passing:**
- ✅ rv32ui-p-add (I extension)
- ✅ rv32ui-p-jal (I extension)
- ✅ rv32um-p-mul (M extension)
- ✅ rv32um-p-div (M extension)
- ✅ rv32ua-p-amoswap_w (A extension)
- ✅ rv32ua-p-lrsc (A extension)
- ✅ rv32uf-p-fadd (F extension)
- ✅ rv32uf-p-fcvt (F extension)
- ✅ rv32ud-p-fadd (D extension)
- ✅ rv32ud-p-fcvt (D extension)
- ✅ rv32uc-p-rvc (C extension)
- ✅ test_fp_compare_simple (custom FP test)
- ✅ test_priv_minimal (privilege test)
- ✅ test_fp_add_simple (custom FP test)

### Privilege Mode Tests Status

**Phase 1: U-Mode Fundamentals (3/5 passing)**
- ❌ `test_umode_entry_from_mmode.s` - M→U transition (x28=0xDEADDEAD)
- ❌ `test_umode_entry_from_smode.s` - S→U transition (x28=0xDEADDEAD)
- ✅ `test_umode_ecall.s` - ECALL from U-mode (needs hex rebuild)
- ✅ `test_umode_csr_violation.s` - CSR privilege checking
- ✅ `test_umode_illegal_instr.s` - WFI privilege with TW bit

**Note**: Tests need to be recompiled with `-addr=0x00000000` to match testbench configuration.

## Key Learnings

1. **Configuration Consistency Critical**
   - Test compilation and CPU simulation MUST use matching configurations
   - `-march=rv32imafc` tests require `ENABLE_C_EXT=1` in simulation
   - Mismatched configs cause spurious exceptions and infinite loops

2. **Exception Handling Changes Have Ripple Effects**
   - Making exceptions work correctly (latching fix) changed behavior
   - Testbench assumptions about instruction visibility need updating
   - EBREAK now properly traps instead of being a passive marker

3. **Compressed Instruction Support**
   - C extension changes instruction encoding (16-bit vs 32-bit)
   - Affects PC alignment checks (2-byte vs 4-byte)
   - Affects EBREAK encoding (0x9002 vs 0x00100073)
   - Decompression happens early in pipeline (before ID stage)

4. **Testbench Design**
   - Check for control flow changes BEFORE they happen (ID stage)
   - Support both compressed and uncompressed instruction formats
   - Don't rely on instruction visibility after traps

## Next Session Tasks

1. **Debug U-Mode Entry Failures**
   - Investigate `test_umode_entry_from_mmode.s` (M→U via MRET)
   - Investigate `test_umode_entry_from_smode.s` (S→U via SRET)
   - Check mstatus.MPP and mstatus.SPP updates
   - Verify privilege mode transition logic

2. **Complete Phase 1 Testing**
   - Get all 5 Phase 1 tests passing
   - Rebuild privilege tests with correct address (0x00000000)

3. **Phase 2 Implementation**
   - Continue with mstatus state machine tests
   - Implement remaining trap/MRET/SRET tests

## Statistics

- **Time to Fix**: ~2 hours of investigation
- **Files Modified**: 3 (2 source files, 1 documentation)
- **Lines Changed**: ~30 lines
- **Tests Fixed**: 1 (test_fp_compare_simple)
- **Regression Status**: 100% passing (14/14)
- **Bug Severity**: Critical (blocked all further development)
- **Bug Complexity**: High (required deep understanding of config system, exception handling, and testbench)
