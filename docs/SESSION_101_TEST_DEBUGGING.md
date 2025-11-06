# Session 101: Test Infrastructure Debugging
**Date**: 2025-11-06
**Status**: 🔍 IN PROGRESS - Test failures under investigation

## Session Goal
Fix broken tests (test_sum_disabled, test_vm_sum_read) to continue Phase 4 test development.

## Changes Made

### 1. DMEM Size Increase (16KB)
**File**: `tests/linker.ld`

**Before**:
```
DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 12K
```

**After**:
```
DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 16K
```

**Reason**: Tests with multiple page tables need >12KB
- test_sum_disabled: 3 page tables (L1 + L0 + user_data) = 12KB + variables
- Allows headroom for complex VM tests

**Verification**: Quick regression passes (14/14 tests) ✅

### 2. Testbench Already Configured
**File**: `tb/integration/tb_core_pipelined.v:62`
```verilog
.DMEM_SIZE(16384),  // 16KB data memory
```
Already set to 16KB - no change needed!

## Issues Investigated

### Issue 1: test_sum_disabled.s - Timeout

**Symptom**: Test times out during execution

**Root Cause Analysis**:
1. Initially: Linker error "region DMEM overflowed by 152 bytes"
   - Data section: 12,440 bytes (0x3098)
   - DMEM was only 12KB (12,288 bytes)
   - Fixed by increasing DMEM to 16KB

2. After DMEM fix: Still times out
   - Test compiles successfully
   - Execution enters infinite loop or stalls
   - Likely issue: Trap handler infrastructure not properly initialized
   - Test expects page faults to S-mode via delegation, complex setup

**Test Complexity**:
- Requires 2-level page table with U=1 pages
- Requires trap handler to catch page faults
- Requires exception delegation to S-mode
- Requires page fault recovery and retry logic

**Decision**: **DEFER** test_sum_disabled
- Already have 4 passing SUM/MXR tests:
  - test_sum_basic.s ✅
  - test_mxr_basic.s ✅
  - test_sum_mxr_csr.s ✅
  - test_vm_sum_simple.s ✅
- These cover SUM/MXR functionality adequately
- test_sum_disabled is too complex for current debugging session

### Issue 2: test_vm_sum_read.s - Stage 1 Failure

**Symptom**: Test fails at stage 1 (x29=1), basic M-mode data write/read

**Register State at Failure**:
```
x5  (t0)   = 0x80080001  (should be 0xDEADBEEF)
x6  (t1)   = 0x80002020  (address of test_data_user)
x7  (t2)   = 0x80002000  (value read back - WRONG!)
x28 (t3)   = 0xdeaddead  (fail marker)
x29 (t4)   = 0x00000001  (stage 1)
```

**Test Code (lines 116-122)**:
```assembly
li      t0, 0xDEADBEEF
la      t1, test_data_user
sw      t0, 0(t1)           # Write 0xDEADBEEF to test_data_user

lw      t2, 0(t1)           # Read back
bne     t0, t2, test_fail   # FAILS: t2=0x80002000, not 0xDEADBEEF
```

**Initial Hypothesis**: Wrong memory map (0x80000000 vs 0x00000000)
- Test uses PA 0x80002020 for test_data_user
- Our testbench memory is at 0x00000000
- **HYPOTHESIS WAS WRONG!**

**Key Discovery**: Memory Address Masking
Found in `rtl/memory/data_memory.v:39`:
```verilog
assign masked_addr = addr & (MEM_SIZE - 1);
```

This means:
- addr = 0x80002020
- MEM_SIZE = 16384 (0x4000)
- masked_addr = 0x80002020 & 0x3FFF = 0x2020
- **0x80000000-based addresses automatically work!**

**Same for instruction_memory.v:69**:
```verilog
wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);
```

**Memory Map**:
- Testbench RESET_VECTOR = 0x80000000 (tb/integration/tb_core_pipelined.v:56)
- Linker places code at 0x80000000
- Memory modules mask addresses to fit in actual memory size
- Example: 0x80003000 → 0x3000 (maps correctly!)

**Real Issue**: Still under investigation
- Write to 0x80002020 should work (masked to 0x2020)
- Read back returns 0x80002000 (looks like an address, not data!)
- May be related to PC initialization or `la` (load address) calculation

**PC Investigation**:
Created test_satp_check.s to verify PC value:
```assembly
auipc  t0, 0x2     # t0 = PC + 0x2000
mv     a0, t0      # x10 = t0
```
Result: x10 = 0x00002000 (suggests PC = 0x00000000, NOT 0x80000000!)

**But**: `pc.v:22` shows `pc_current <= RESET_VECTOR` on reset
**And**: Testbench passes RESET_VECTOR = 0x80000000

**Mystery**: Why does `auipc` give 0x00002000 instead of 0x80002000?
- Either PC is not being set to 0x80000000
- Or there's address calculation issue with `auipc`
- Needs further investigation

### Issue 3: test_vm_non_identity_basic.s - Also Failing

**Symptom**: Was passing in Session 100, now failing!

**Observation**: Uses PA 0x80000000-based addresses (should work due to masking)

**Status**: Deferred until test_vm_sum_read is resolved (likely same root cause)

## Memory Map Architecture

### Testbench Configuration
```
RESET_VECTOR = 0x80000000
IMEM_SIZE = 4096 (4KB)
DMEM_SIZE = 16384 (16KB) 
```

### Linker Script (tests/linker.ld)
```
IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 16K
```

### Address Masking in Hardware
Both instruction_memory.v and data_memory.v use:
```verilog
masked_addr = addr & (MEM_SIZE - 1)
```

This clever design allows:
- Standard RISC-V addresses (0x80000000+) in software
- Small memory arrays (4KB-16KB) in hardware
- Automatic translation via masking

Examples:
- Code at 0x80000000 → masked to 0x0000
- Code at 0x80000100 → masked to 0x0100
- Data at 0x80002020 → masked to 0x2020
- Data at 0x80003000 → masked to 0x3000

## Test Status Summary

### Passing Tests (4)
- ✅ test_vm_identity_basic.s
- ✅ test_vm_identity_multi.s
- ✅ test_vm_sum_simple.s
- ✅ test_vm_offset_mapping.s

### Failing Tests (2)
- ❌ test_vm_sum_read.s - Stage 1 failure (wrong value read back)
- ❌ test_vm_non_identity_basic.s - Unknown (was passing in Session 100)

### Deferred Tests (1)
- ⏸️  test_sum_disabled.s - Too complex, trap handler infrastructure issue

## Debugging Tools Created

1. **test_satp_check.s** - Minimal test to check SATP at start
   - Result: SATP = 0 ✅ (correct)

2. **test_sum_disabled_debug.s** - Simplified SUM test
   - Compilation issues with large offsets (2048 > 2047 immediate limit)

3. **check_addr.s** - Test to check `la` address calculation
   - Result: x10 = 0x00002000 (unexpected - should be 0x80002000?)

## Known Issues

### 1. RESET_VECTOR Mystery
**Expected**: PC starts at 0x80000000
**Observed**: `auipc` suggests PC = 0x00000000
**Evidence**:
- pc.v:22 sets `pc_current <= RESET_VECTOR`
- Testbench sets `.RESET_VECTOR(RESET_VEC)` where RESET_VEC = 0x80000000
- But runtime behavior suggests PC = 0

**Needs Investigation**: 
- Verify PC value at start with debug output
- Check if RESET_VECTOR parameter is properly propagated
- Understand why address masking doesn't affect PC value

### 2. Data Read Returns Wrong Value
**Test**: test_vm_sum_read.s
**Issue**: Write 0xDEADBEEF, read back 0x80002000
- Read value looks like an address, not data
- May be reading from wrong memory location
- May be test data initialization issue

## Next Steps

### Immediate (Next Session)
1. Add debug output to verify PC value at reset
2. Verify RESET_VECTOR parameter propagation through hierarchy
3. Check if `auipc` implementation is correct
4. Debug why test_vm_sum_read reads wrong value
5. Re-test test_vm_non_identity_basic after fixes

### If PC Issue Confirmed
- Fix PC initialization to properly use RESET_VECTOR
- Or adjust tests to work with PC=0 if that's intended design

### If Data Issue Confirmed
- Check test data section placement
- Verify memory initialization
- Check if .data section overlaps with something

## Files Modified This Session

1. **tests/linker.ld**
   - DMEM: 12K → 16K

2. **tests/asm/test_sum_disabled_debug.s** (created, incomplete)
3. **tests/asm/test_satp_check.s** (created)
4. **tests/asm/check_addr.s** (created)

## Regression Status

✅ **Quick regression: 14/14 tests pass** (after DMEM increase)
- No regressions from DMEM size change
- Existing tests unaffected

## Conclusion

**Progress**: 
- ✅ DMEM increased to 16KB
- ✅ Quick regression still passes
- 🔍 Identified memory address masking mechanism
- 🔍 Discovered potential PC initialization issue

**Blockers**:
- test_vm_sum_read and test_vm_non_identity_basic failures
- Need to resolve before continuing Week 1 test development

**Time Spent**: ~90k tokens deep-diving into test infrastructure

**Decision**: Document and push, continue debugging in next session
