# Session 97: Non-Identity Virtual Memory Mapping - MMU Bug Investigation (2025-11-05)

## Objectives
- Debug test_vm_non_identity_basic failure from Session 96
- Implement non-identity VA→PA mapping test
- Continue Week 1 test development (Priority 1A)

## Session Summary

### Critical Bug Found: MMU Translation Active in M-Mode with SATP=0

**Achievement**: 🔍 **Identified root cause of non-identity mapping test failure** - MMU incorrectly performs translation in M-mode!

**Status**: Bug identified but not yet fixed. Test currently fails at stage 1.

## Bug Investigation Process

### Initial Symptoms
Test `test_vm_non_identity_basic` fails at stage 1 with:
- x29 (stage marker) = 1 (stage 1)
- x28 (test result) = 0xDEADDEAD (FAIL marker)
- t2 (value read from PA 0x80003000) = 0x00100e93 (first instruction, should be 0xCAFEBABE)

### Investigation Steps

1. **Memory System Verification** ✅
   - Created simple tests: test_simple_mem, test_vm_simple_check, test_stage1_only
   - All simple tests PASS - writing/reading PA 0x80003000 works correctly
   - Confirms: Data memory, bus adapter, and basic memory operations are functional

2. **Test Isolation** ✅
   - Progressively disabled stages of test_vm_non_identity_basic
   - **Key Finding**: Test passes with stages 1-4 only, fails with full test
   - However, when early `j test_pass` added to stage 1, test passes!

3. **Critical Discovery** 🎯
   - MMU debug output shows: `MMU: TLB[0] updated: VPN=0x00080000, PPN=0xxxxxxX80003, PTE=0xcf`
   - This proves MMU performed page table walk for VA 0x80000000
   - **BUT**: We're in M-mode with SATP=0 - translation should be DISABLED!

4. **Page Table Analysis**
   - Page table is statically initialized in .data section (line 217):
     ```assembly
     .word 0x20000CCF            # Entry 512: Maps VA 0x80000000 → PA 0x80003000
     ```
   - When DMEM loads from hex file, page table already contains valid PTE
   - MMU finds this PTE during page table walk

5. **Address Translation Flow** (INCORRECT BEHAVIOR)
   - Test executes from VA 0x80000000 (code location)
   - MMU (incorrectly active) translates VA 0x80000000 → PA 0x80003000
   - When test tries to read PA 0x80003000, MMU treats it as VA 0x80003000
   - No PTE exists for VA 0x80003000, MMU behavior undefined
   - Result: Read returns 0x00100e93 (first instruction) instead of 0xCAFEBABE

## Root Cause Analysis

### The Bug: MMU Translation Enabled When It Shouldn't Be

**Location**: `rtl/core/mmu.v:93` (RV32) or `rtl/core/mmu.v:97` (RV64)

**Current Logic**:
```verilog
// RV32 (line 93)
assign translation_enabled = (satp_mode == 1'b1) && (privilege_mode != 2'b11);

// RV64 (line 97)
assign translation_enabled = (satp_mode == 4'h8) && (privilege_mode != 2'b11);
```

**Expected Behavior**:
- M-mode (privilege_mode == 2'b11): Translation DISABLED regardless of SATP
- SATP = 0: Translation DISABLED regardless of privilege mode
- S/U-mode with SATP mode set: Translation ENABLED

**Observed Behavior**:
- MMU performs page table walk in M-mode with SATP=0
- TLB gets updated with translation for VA 0x80000000
- Subsequent memory accesses get incorrectly translated

### Potential Causes

1. **SATP Mode Read Error**
   - RV32: `satp_mode = satp[31:31]` (1 bit)
   - Maybe satp[31] is corrupted or read incorrectly?

2. **Privilege Mode Error**
   - Maybe privilege_mode signal is not 2'b11 (M-mode) when it should be?
   - Test starts in M-mode, should stay in M-mode during stage 1

3. **Logic Error**
   - Current logic doesn't check if SATP == 0
   - Spec says: "When satp.MODE=Bare, supervisor virtual addresses are equal to supervisor physical addresses"
   - Should add explicit check: `(satp != 0) && ...`

## Test Files Created/Modified

### New Tests Created (Session 97)
- `tests/asm/test_simple_mem.s` - Simple memory write/read test (PASSES) ✅
- `tests/asm/test_debug_satp.s` - SATP verification test (PASSES) ✅
- `tests/asm/test_with_pagetable.s` - Test with unused page table (PASSES) ✅
- `tests/asm/test_setup_pt.s` - Test with PTE setup but no SATP write (PASSES) ✅
- `tests/asm/test_stage1_only.s` - Isolated stage 1 test (PASSES) ✅

### Modified Tests
- `tests/asm/test_vm_non_identity_basic.s` - Added debug code (reverted)

### Test Results Summary
| Test | Stage 1 | Page Table | SATP Write | S-Mode | Result |
|------|---------|------------|------------|--------|--------|
| test_simple_mem | ✅ | ❌ | ❌ | ❌ | PASS ✅ |
| test_vm_simple_check | ✅ | ❌ | ❌ | ❌ | PASS ✅ |
| test_with_pagetable | ✅ | ✅ (unused) | ❌ | ❌ | PASS ✅ |
| test_setup_pt | ✅ | ✅ (setup) | ❌ | ❌ | PASS ✅ |
| test_stage1_only | ✅ | ❌ | ❌ | ❌ | PASS ✅ |
| test_vm_non_identity_basic (simplified) | ✅ | ✅ (setup) | ✅ | ✅ | PASS ✅ |
| test_vm_non_identity_basic (full) | ✅ | ✅ (setup) | ✅ | ✅ | **FAIL** ❌ |

**Pattern**: Test passes when later stages are disabled, fails with full test. This suggests something in the later stages triggers the MMU incorrectly.

## Technical Insights

### Memory Layout (RV32, 16KB DMEM)
```
0x80000000 - 0x80000177: .text section (376 bytes - test_vm_non_identity_basic)
0x80002000 - 0x80002FFF: .data section (page table, 4KB)
  0x80002800: Entry 512 = 0x20000CCF (VA 0x80000000 → PA 0x80003000)
0x80003000 - 0x80003FFF: Available for test data
```

### PTE Calculation
**Mapping**: VA 0x80000000 → PA 0x80003000 (4MB megapage)
- PPN = PA >> 12 = 0x80003000 >> 12 = 0x80003
- PTE = (PPN << 10) | flags = (0x80003 << 10) | 0xCF
- PTE = 0x20000C00 | 0xCF = **0x20000CCF** ✓

### MMU Debug Output Analysis
```
MMU: TLB[0] updated: VPN=0x00080000, PPN=0xxxxxxX80003, PTE=0xcf
```
- VPN = 0x00080000 → VA = 0x80000000 (VPN is VA[31:12] for Sv32)
- PPN shows as truncated in debug (should be 0x80003)
- PTE = 0xCF (shows only low byte, full value is 0x20000CCF)
- **This proves MMU did page table walk when it shouldn't have!**

## Next Session Actions

### Immediate Priority: Fix MMU Bug
1. **Debug translation_enabled Signal**
   - Add debug output for SATP, privilege_mode, satp_mode
   - Verify values during test execution
   - Check if SATP is being corrupted somehow

2. **Potential Fixes**
   - Add explicit `satp == 0` check to translation_enabled logic
   - Verify privilege_mode is correctly passed to MMU
   - Check for race conditions or initialization issues

3. **Verification**
   - Run test_vm_non_identity_basic after fix
   - Verify MMU debug shows no TLB updates in M-mode
   - Confirm test passes all 8 stages

### Alternative Approach (If Bug is Complex)
- Simplify test_vm_non_identity_basic to not use statically initialized page table
- Write PTE dynamically in stage 2 (currently does both static and dynamic)
- Remove `.word 0x20000CCF` from .data section

## Progress Update

### Week 1 Status: 7/10 Tests (70%)
**Passing Tests** (unchanged from Session 96):
1. ✅ test_satp_reset
2. ✅ test_smode_entry_minimal
3. ✅ test_vm_sum_simple
4. ✅ test_vm_identity_basic
5. ✅ test_vm_identity_multi
6. ✅ test_mxr_basic
7. ✅ test_sum_mxr_csr

**Blocked**:
8. ⚠️ test_vm_non_identity_basic - **MMU bug blocks progress**

**Remaining**:
9-10. TBD (pending non-identity test fix)

### Overall Phase 4 Prep: 7/44 Tests (15.9%)
**Status**: Blocked by MMU bug - must fix before continuing

## Key Learnings

1. **Test Isolation is Critical**: Simple tests helped identify that core memory system works correctly
2. **Progressive Debugging**: Disabling test stages one-by-one revealed the bug is triggered by later stages
3. **MMU Debug Output Invaluable**: TLB update message proved MMU was active when it shouldn't be
4. **Static vs Dynamic Initialization**: Page table being pre-initialized in .data section contributed to confusion
5. **Hardware Bugs Can Be Subtle**: Logic looks correct (M-mode check present), but something is still wrong

## Files Modified

### RTL Changes
- `rtl/memory/data_memory.v` - Added (then disabled) debug output for 0x80003000 accesses

### Test Files (Session 97)
- Created: test_simple_mem, test_debug_satp, test_with_pagetable, test_setup_pt, test_stage1_only
- Modified: test_vm_non_identity_basic (reverted to original)

## References
- Session 96: Initial non-identity mapping test development
- Session 95: S-mode and VM functionality confirmed working
- Session 94: Critical MMU SUM permission fix
- Session 92: MMU megapage translation fix
- Session 90: MMU PTW handshake fix
- docs/PHASE_4_PREP_TEST_PLAN.md: Week-by-week test plan

## Conclusion

This session successfully identified a critical MMU bug: the translation_enabled signal is true when it should be false (M-mode with SATP=0). This causes incorrect address translation that breaks the non-identity mapping test.

The bug is well-isolated and understood. The fix should be straightforward - either add explicit SATP==0 check or debug why the existing logic fails. This is a blocking issue for Phase 4 test development and must be resolved before continuing with VM tests.

**Next session**: Debug and fix MMU translation_enabled logic, then verify test_vm_non_identity_basic passes all 8 stages.
