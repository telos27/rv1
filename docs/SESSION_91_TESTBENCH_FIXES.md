# Session 91: Critical Testbench & Test Infrastructure Fixes

**Date**: November 5, 2025
**Focus**: Fix testbench and test bugs preventing VM test validation
**Status**: ✅ Infrastructure fixed, test debugging ongoing

---

## Overview

Attempted to create `test_vm_identity_multi.s` for multi-page VM testing but discovered critical infrastructure bugs that were causing all VM tests to fail. Fixed two major bugs in testbench and test page tables.

---

## Bugs Discovered and Fixed

### Bug 1: Testbench Reset Vector Mismatch

**File**: `tb/integration/tb_core_pipelined.v`

**Problem**:
- Reset vector was conditionally set to 0x00000000 for non-compliance tests
- All custom tests are linked at 0x80000000 (standard RISC-V reset vector)
- CPU started executing at PC=0x00000000 instead of 0x80000000
- All PC-relative address calculations were wrong by 0x80000000

**Symptoms**:
```verilog
// Before (WRONG):
`ifdef COMPLIANCE_TEST
  parameter [31:0] RESET_VEC = 32'h80000000;
`else
  parameter [31:0] RESET_VEC = 32'h00000000;  // BUG!
`endif
```

- `auipc t2, 0x2` at PC=0x00000014 produced 0x00002014 instead of 0x80002014
- `la` pseudoinstructions loaded wrong addresses
- Register t2 showed 0x00002000 instead of 0x80002000

**Fix**:
```verilog
// After (CORRECT):
// RISC-V tests start at 0x80000000 (standard reset vector)
// Custom tests also use 0x80000000 as they're linked with the same linker script
parameter [31:0] RESET_VEC = 32'h80000000;
```

Also added explicit XLEN parameter:
```verilog
rv_core_pipelined #(
  .XLEN(32),              // Force RV32 mode
  .RESET_VECTOR(RESET_VEC),
  ...
```

**Impact**: All addresses now correct, PC starts at 0x80000000

---

### Bug 2: Incorrect Page Table Entries (PTEs)

**File**: `tests/asm/test_vm_identity_basic.s`

**Problem**:
Page table entries had incorrect PPN values due to misunderstanding of Sv32 PTE format.

**Root Cause**:
For Sv32, PTEs are 32 bits:
- **PTE[31:10] = PPN (22 bits) = PA[33:12]**
- PTE[9:0] = Flags

For target physical address PA = 0x80000000:
- PPN = PA[33:12] = 0x80000000 >> 12 = 0x80000 (22 bits)
- PTE = (PPN << 10) | flags = (0x80000 << 10) | 0xCF = 0x200000CF

**Wrong PTEs** (before fix):
```assembly
page_table_l1:
    .word 0x000000CF   # Entry 0 - WRONG: maps to PA 0x00000000
    .fill 511, 4, 0
    .word 0x0800CF     # Entry 512 - WRONG: maps to PA 0x00200000
```

**Correct PTEs** (after fix):
```assembly
page_table_l1:
    .word 0x200000CF   # Entry 0 - maps to PA 0x80000000 ✓
    .fill 511, 4, 0
    .word 0x200000CF   # Entry 512 - maps to PA 0x80000000 ✓
```

**Verification**:
- Hex file at offset 0x1000: `cf 00 00 20` = 0x200000CF (little-endian) ✓
- Hex file at offset 0x1800: `cf 00 00 20` = 0x200000CF ✓
- MMU TLB update shows: `PPN=0xxxxxxX80000` (correct, was `0xxxxxxX00200` before)

**Impact**: MMU now translates to correct physical addresses

---

## Verification Tests

### Test Created: test_vm_debug.s

**Purpose**: Minimal test to verify basic SATP and memory functionality

**Code**:
```assembly
_start:
    li      t4, 1
    csrr    t0, satp           # Check SATP = 0
    mv      t5, t0
    bnez    t0, satp_fail

    li      t4, 2
    li      t1, 0x12345678     # Write test value
    li      t2, 0x80002000     # Direct address (not PC-relative)
    sw      t1, 0(t2)

    li      t4, 3
    lw      t3, 0(t2)          # Read back

    li      t4, 4
    bne     t1, t3, mem_fail   # Compare

    li      t4, 5
pass:
    li      t3, 0xDEADBEEF
    ebreak
```

**Result**: ✅ **TEST PASSED**
- Completes in 28 cycles
- x28 (t3) = 0xDEADBEEF (pass marker)
- Proves SATP=0 at boot ✓
- Proves M-mode memory read/write works ✓

---

## Analysis: Why test_vm_identity_basic Still Fails

Despite fixing both bugs, `test_vm_identity_basic` still fails with identical symptoms:
- Cycles: 73
- x28 = 0xDEADDEAD (fail marker)
- x29 (t4) = 0x00000001

**Investigation**:

1. **Test reaches Stage 5**: 73 cycles indicates test passes stages 1-4 and enters stage 5 (MMU enabled)

2. **Stage 5 code** (PC 0x800000A4):
   ```assembly
   li      t4, 5                    # Set stage marker
   li      t2, 0xABCD1234           # Value to write
   la      t3, test_data            # Load address 0x80002000
   sw      t2, 0(t3)                # Store through MMU
   lw      t4, 0(t3)                # Load through MMU
   bne     t2, t4, test_fail        # Compare - FAILS HERE
   ```

3. **Failure point**: The `lw t4, 0(t3)` returns wrong value
   - Expected: 0xABCD1234
   - Actual: 0x00000001 (inferred from final t4 value)

4. **MMU verification**:
   - TLB update occurs: `VPN=0x00080002, PPN=0xxxxxxX80000`
   - VPN=0x80002 corresponds to VA=0x80002000 ✓
   - PPN=0x80000 corresponds to PA base=0x80000000 ✓
   - Translation should work correctly

5. **Possible causes** (needs further investigation):
   - Memory bus timing issue with MMU-translated access
   - TLB lookup returning stale entry
   - Store not completing before load
   - MMU translation bug in physical address calculation

---

## Files Modified

### Core Infrastructure
- **tb/integration/tb_core_pipelined.v**
  - Fixed reset vector to 0x80000000
  - Added explicit `.XLEN(32)` parameter
  - Added explicit `.XLEN(32)` to dmem_bus_adapter

### Tests
- **tests/asm/test_vm_identity_basic.s**
  - Fixed entry 0: 0x000000CF → 0x200000CF
  - Fixed entry 512: 0x0800CF → 0x200000CF

### New Files
- **tests/asm/test_vm_debug.s** - Minimal passing test (28 cycles)
- **tests/asm/test_vm_identity_multi.s** - Multi-page VM test (needs PTE fixes)

---

## Key Learnings

### 1. Sv32 PTE Format
```
PTE (32 bits):
  [31:10] = PPN (22 bits) = Physical Address[33:12]
  [9:0]   = Flags (V, R, W, X, U, G, A, D)

For PA = 0x80000000:
  PPN = 0x80000000 >> 12 = 0x80000
  PTE = (0x80000 << 10) | 0xCF = 0x200000CF
```

### 2. Reset Vector Importance
- Custom tests linked at 0x80000000 must start execution there
- Wrong reset vector causes all PC-relative addressing to fail
- Always verify testbench parameters match test assumptions

### 3. Debugging Approach
- Created minimal passing test first to isolate variables
- Verified each component independently (SATP, memory, MMU)
- Used register dumps and debug output to trace execution

---

## Next Steps

1. **Immediate**: Debug why stage 5 fails despite correct MMU translation
   - Add detailed MMU access tracing
   - Check memory bus arbitration
   - Verify TLB hit/miss logic

2. **Apply PTE fixes**: Update test_vm_identity_multi.s with 0x200000CF

3. **Continue Phase 4 test development** once VM tests pass

---

## Statistics

- **Time**: ~4 hours debugging
- **Bugs found**: 2 critical
- **Bugs fixed**: 2 critical
- **Tests created**: 2 (test_vm_debug, test_vm_identity_multi)
- **Tests passing**: 1 (test_vm_debug)
- **Tests failing**: 2 (test_vm_identity_basic, test_vm_identity_multi)

---

## References

- RISC-V Privileged Spec v1.12: Section 4.3 (Sv32 Virtual Memory)
- `docs/SESSION_90_MMU_PTW_FIX.md` - Previous MMU debugging session
- `docs/PHASE_4_PREP_TEST_PLAN.md` - Overall test plan
