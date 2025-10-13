# Phase 13 Complete: MMU Bare Mode Fix - 100% RV32I Compliance

**Date**: 2025-10-12
**Session**: 31
**Status**: ✅ **COMPLETE**
**Achievement**: **100% RV32I Compliance (42/42 tests passing)** 🎉

## Summary

Successfully debugged and fixed the last failing RV32I compliance test (`rv32ui-p-ma_data`) by resolving a stale address bug in the MMU bare mode path. This achievement restores 100% RV32I compliance that was temporarily lost when the MMU was integrated.

## Problem Statement

### Symptom
- **Test**: `rv32ui-p-ma_data`
- **Failure Point**: Test #92 (gp=0xb9=185, test_num = (185-1)/2 = 92)
- **Expected**: Load byte from address 0x80002002 should return 0xffffff9b (-101)
- **Actual**: Returned 0xffffff9a (-102)
- **Error**: Off by -1 address (loaded from 0x80002001 instead of 0x80002002)

### Test #92 Details
From `riscv-tests/isa/rv64ui/ma_data.S:178`:
```assembly
MISMATCHED_STORE_TEST(92, sh, lb, s0, 1, 2, 0x9b9a, SEXT(0x9b, 8))
```

This expands to:
```assembly
li t1, 0x9b9a           # t1 = 0x9b9a
li t2, 0xffffff9b       # t2 = expected result
sh t1, 1(s0)            # Store halfword at s0+1 (misaligned)
                        #   mem[s0+1] = 0x9a
                        #   mem[s0+2] = 0x9b
lb t3, 2(s0)            # Load signed byte from s0+2
                        #   Should load 0x9b, sign-extend to 0xffffff9b
bne t2, t3, fail        # Compare expected vs actual
```

### Observed Behavior
- Store halfword 0x9b9a at s0+1: ✅ Worked correctly
  - Byte at s0+1 = 0x9a
  - Byte at s0+2 = 0x9b
- Load byte from s0+2: ❌ Returned wrong byte
  - Expected: 0x9b from address 0x80002002
  - Actual: 0x9a from address 0x80002001 (off by -1)

## Root Cause Analysis

### Timeline of Changes
1. **Commit 3def08c**: Achieved 100% RV32I compliance (42/42 tests)
   - Fixed FENCE.I and misaligned access
   - No MMU integrated yet
2. **Commit a595d33**: Added MMU support
   - Integrated MMU for virtual memory translation
   - Introduced address arbiter for PTW (Page Table Walk) support
3. **Current**: Regression to 41/42 tests
   - MMU integration broke bare mode addressing

### The Bug

In `rtl/core/rv32i_core_pipelined.v:1438-1439` (before fix):

```verilog
wire use_mmu_translation = mmu_req_ready && !mmu_req_page_fault;
wire [XLEN-1:0] translated_addr = use_mmu_translation ? mmu_req_paddr : dmem_addr;
```

**Problem**: The condition `use_mmu_translation` didn't check if translation was actually enabled (bare mode vs virtual memory mode).

### Timing Issue

In bare mode (satp.MODE = 0), the MMU still responds with registered outputs:

```verilog
// Inside mmu.v, bare mode path:
if (!translation_enabled) begin
  req_paddr <= req_vaddr;  // Registered, takes effect NEXT cycle
  req_ready <= 1;          // Registered, takes effect NEXT cycle
end
```

**Cycle-by-cycle breakdown:**

| Cycle | Operation | mmu_req_vaddr | mmu_req_ready | mmu_req_paddr | use_mmu_translation | translated_addr | Issue |
|-------|-----------|---------------|---------------|---------------|---------------------|-----------------|-------|
| N-1   | Store to 0x80002001 | 0x80002001 | 0 → 1 | X → 0x80002001 | false → true | 0x80002001 | ✅ OK |
| N     | Load from 0x80002002 | 0x80002002 | 1 (from N-1) | 0x80002001 (from N-1) | **true** | **0x80002001** | ❌ **STALE!** |

The pipeline uses `mmu_req_ready` and `mmu_req_paddr` from the **previous cycle**, causing it to use the stale address 0x80002001 when it should use 0x80002002.

### Why This Wasn't Caught Earlier

The original 100% compliance was achieved **before** MMU integration. The MMU was added later for supervisor mode support, and this edge case in bare mode wasn't tested thoroughly with the misaligned access test.

## Solution

### The Fix

Add a check for whether translation is actually enabled before using the MMU's output:

```verilog
// Check if translation is enabled: satp.MODE != 0
// RV32: satp[31] (1-bit mode), RV64: satp[63:60] (4-bit mode)
wire translation_enabled = (XLEN == 32) ? csr_satp[31] : (csr_satp[63:60] != 4'b0000);
wire use_mmu_translation = translation_enabled && mmu_req_ready && !mmu_req_page_fault;
wire [XLEN-1:0] translated_addr = use_mmu_translation ? mmu_req_paddr : dmem_addr;
```

### How It Works

**Bare Mode (satp.MODE = 0):**
- `translation_enabled` = 0
- `use_mmu_translation` = 0 (regardless of `mmu_req_ready`)
- `translated_addr` = `dmem_addr` (direct from pipeline, no MMU)
- **Result**: Addresses flow directly from EX stage to memory, no timing issues

**Virtual Memory Mode (satp.MODE != 0):**
- `translation_enabled` = 1
- `use_mmu_translation` = 1 (when `mmu_req_ready` and no page fault)
- `translated_addr` = `mmu_req_paddr` (MMU-translated address)
- **Result**: Full MMU functionality preserved

## Implementation

### Files Modified

**rtl/core/rv32i_core_pipelined.v** (lines 1436-1442):

```diff
   // When PTW is active, it gets priority
   // When PTW is not active, use translated address from MMU (or bypass if no MMU)
+  // Check if translation is enabled: satp.MODE != 0
+  // RV32: satp[31] (1-bit mode), RV64: satp[63:60] (4-bit mode)
+  wire translation_enabled = (XLEN == 32) ? csr_satp[31] : (csr_satp[63:60] != 4'b0000);
-  wire use_mmu_translation = mmu_req_ready && !mmu_req_page_fault;
+  wire use_mmu_translation = translation_enabled && mmu_req_ready && !mmu_req_page_fault;
   wire [XLEN-1:0] translated_addr = use_mmu_translation ? mmu_req_paddr : dmem_addr;
```

**Changes**: 3 lines added

### Verification

**Before Fix:**
```
Total:  42
Passed: 41
Failed: 1
Pass rate: 97.6%

Failed tests:
  - rv32ui-p-ma_data (test #92)
```

**After Fix:**
```
Total:  42
Passed: 42
Failed: 0
Pass rate: 100% ✅
```

**Test Execution:**
```bash
./tools/run_official_tests.sh i ma_data
# Result: PASSED in 538 cycles
```

## Technical Details

### SATP (Supervisor Address Translation and Protection) Register

| XLEN | Bits | Field | Description |
|------|------|-------|-------------|
| RV32 | [31] | MODE | 0=Bare, 1=Sv32 |
| RV32 | [30:22] | ASID | Address Space ID |
| RV32 | [21:0] | PPN | Physical Page Number |
| RV64 | [63:60] | MODE | 0=Bare, 8=Sv39, 9=Sv48, 10=Sv57 |
| RV64 | [59:44] | ASID | Address Space ID |
| RV64 | [43:0] | PPN | Physical Page Number |

**Bare Mode**: MODE = 0, no address translation, physical addresses only

### Memory Address Path (After Fix)

```
EX Stage ALU Result (exmem_alu_result)
  ↓
dmem_addr (muxed with atomic unit)
  ↓
translation_enabled? ──No──→ translated_addr = dmem_addr
  ↓ Yes                            ↓
MMU Translation                    ↓
  ↓                                ↓
mmu_req_paddr ─────────────→ translated_addr = mmu_req_paddr
                                   ↓
                            arb_mem_addr (muxed with PTW)
                                   ↓
                            Data Memory
```

## Impact

### Positive Outcomes
- ✅ **100% RV32I Compliance** restored (42/42 tests passing)
- ✅ **MMU functionality preserved** for virtual memory mode
- ✅ **Minimal code change** (3 lines, clear and maintainable)
- ✅ **No performance impact** (combinational logic only)
- ✅ **Correct separation** between bare mode and virtual memory mode

### Testing Coverage
- All 42 RV32I tests passing, including:
  - `rv32ui-p-ma_data` (misaligned access) ✅
  - `rv32ui-p-fence_i` (self-modifying code) ✅
  - All arithmetic, logical, branch, load/store tests ✅

## Lessons Learned

1. **Regression Testing**: Major architectural changes (like MMU integration) need comprehensive regression testing
2. **Timing Analysis**: Be careful with registered outputs in control paths - check if outputs from previous cycles are being used incorrectly
3. **Mode Separation**: Clearly separate bare mode (passthrough) from translated mode in address paths
4. **Edge Cases**: Misaligned access tests are great for catching subtle address calculation bugs

## Next Steps

### Completed
- ✅ Fix identified and implemented
- ✅ All RV32I compliance tests passing
- ✅ Documentation updated

### Future Work
1. **Phase 8.5**: FPU (F/D Extension) thorough testing and verification
2. **Extension Testing**: Run M, A, F, D extension compliance tests
3. **Performance**: Consider optimizing MMU TLB hit rate
4. **Formal Verification**: Consider formal methods for critical address translation paths

## Files Changed

| File | Lines Changed | Description |
|------|---------------|-------------|
| rtl/core/rv32i_core_pipelined.v | +3 | Added translation_enabled check |
| docs/PHASE13_COMPLETE.md | +300 | This documentation |
| PHASES.md | +15 | Updated status and progress |

## Conclusion

Phase 13 successfully debugged and fixed a subtle timing bug in the MMU bare mode path, restoring 100% RV32I compliance. The fix is minimal, correct, and preserves all MMU functionality for virtual memory mode while properly bypassing the MMU in bare mode.

**Status**: ✅ **COMPLETE** - Ready to move to Phase 8.5 (FPU Testing) or further extensions!
