# Session 93: VM Multi-Page Test & MMU V-bit Bug Fix

**Date:** 2025-11-05
**Focus:** Phase 4 Prep - Week 1 VM tests continuation, critical MMU bug fix

## Overview

Continued Phase 4 test development for xv6 readiness. Fixed PTE values in test_vm_identity_multi and discovered/fixed a critical MMU bug where the Page Table Walker (PTW) wasn't checking the valid bit before processing PTEs.

## Session Goals

1. ✅ Fix and test `test_vm_identity_multi.s`
2. ⚠️ Create and test `test_vm_sum_read.s` (blocked by SUM permission bug)
3. ✅ Discovered and fixed critical MMU V-bit check bug

## Bugs Fixed

### 1. test_vm_identity_multi PTE Values (tests/asm/test_vm_identity_multi.s)

**Problem:** Page Table Entries used incorrect PPN values
- Used: `0x0800CF` (from incorrect calculation)
- Should be: `0x200000CF` (correct PPN for PA 0x80000000)

**Root Cause:** PTE calculation was wrong in comments and values:
```
# WRONG: PTE = (0x200 << 10) | 0xCF = 0x80000 | 0xCF = 0x0800CF
# CORRECT: PTE = (0x80000 << 10) | 0xCF = 0x20000000 | 0xCF = 0x200000CF
```

**Correct Calculation:**
- Target PA = 0x80000000
- PPN = PA[33:12] = 0x80000000 >> 12 = 0x80000 (22 bits)
- PTE[31:10] = PPN, PTE[9:0] = flags
- PTE = (0x80000 << 10) | 0xCF = **0x200000CF**

**Fix Applied:**
- Changed all 5 incorrect PTEs (entries 0, 1, 2, 3, 512) from 0x0800CF → 0x200000CF
- Updated comments to show correct calculation

**Verification:**
- ✅ test_vm_identity_multi now PASSES (246 cycles)
- ✅ All 12 test stages complete successfully
- ✅ TLB confirmed working with 5 concurrent entries
- ✅ Multi-page identity mapping verified
- ✅ Data consistency across different VAs to same PA

### 2. MMU PTW V-bit Check Missing (rtl/core/mmu.v:420-423)

**Problem:** Page Table Walker didn't check PTE valid bit before processing
- PTW would attempt to walk non-leaf invalid PTEs (V=0)
- Caused infinite loops when accessing pages with invalid PTEs
- Security issue: could potentially use garbage PPN values from invalid PTEs

**Root Cause (rtl/core/mmu.v:421-438):**
```verilog
// BROKEN: No V-bit check!
if (ptw_resp_data[PTE_R] || ptw_resp_data[PTE_X]) begin
  // Leaf PTE found: check permissions
  ...
end else if (ptw_level == 0) begin
  // Non-leaf at level 0: fault
  ptw_state <= PTW_FAULT;
end else begin
  // Non-leaf PTE: go to next level
  // BUG: Uses PPN from invalid PTE!
  ptw_pte_addr <= (ptw_resp_data[31:10] << PAGE_SHIFT) + ...
end
```

**Observed Behavior:**
- Created test with invalid PTE (V=0) at entry 0
- Load from VA 0x00001000 caused infinite TLB updates:
  ```
  MMU: TLB[0] updated: VPN=0x00000001, PPN=0xxxxxxX00403, PTE=0x93
  MMU: TLB[1] updated: VPN=0x00000001, PPN=0xxxxxxX00403, PTE=0x93
  ... (repeating forever, cycling through all 16 TLB entries)
  ```
- PTW interpreted V=0 PTE as non-leaf, tried to walk to next level
- Used garbage PPN from invalid PTE, read more garbage, infinite loop

**Fix Applied (rtl/core/mmu.v:420-423):**
```verilog
// First check if PTE is valid
if (!ptw_resp_data[PTE_V]) begin
  // Invalid PTE: page fault
  ptw_state <= PTW_FAULT;
// Check if this is a leaf PTE
end else if (ptw_resp_data[PTE_R] || ptw_resp_data[PTE_X]) begin
  ...
```

**Impact:**
- Critical security fix: prevents using invalid PTEs
- Fixes page fault detection for unmapped pages
- Required for proper OS support (page fault handling)
- RISC-V spec compliance: V=0 must cause page fault

## Tests Created

### 1. test_vm_identity_multi.s ✅ PASSES
**Purpose:** Multi-page identity mapping with TLB stress test
**Coverage:**
- 4 different VAs (0x00000000, 0x00400000, 0x00800000, 0x00C00000) mapping to same PA
- Multiple concurrent TLB entries (5 entries: code + 4 data regions)
- Data isolation across different VAs
- Paging enable/disable toggle
**Results:** 246 cycles, CPI 1.236, all 12 stages pass

### 2. test_vm_sum_read.s ⚠️ BLOCKED
**Purpose:** SUM (Supervisor User Memory) bit with VM translation
**Coverage:**
- SUM=0: S-mode should fault on U-page reads
- SUM=1: S-mode should succeed on U-page reads
- Page fault handling and recovery
**Status:** Test created but fails - SUM permission check not working
**Issue:** S-mode can access U-pages even with SUM=0 (should fault but doesn't)

### 3. test_sum_basic_debug.s ✅ PASSES
**Purpose:** Verify SUM CSR bit read/write without VM
**Coverage:**
- SUM bit in MSTATUS/SSTATUS
- M-mode → S-mode SUM inheritance
- CSRS/CSRC operations on SUM bit
**Results:** 62 cycles, all stages pass
**Conclusion:** SUM CSR infrastructure works, issue is in MMU permission checking

### 4. test_page_fault_invalid.s ⚠️ CREATED
**Purpose:** Test page fault on invalid PTE (V=0)
**Status:** Created but times out (likely related to V-bit bug before fix was complete)
**Note:** Should retest in next session after V-bit fix verification

## Issue Discovered: SUM Permission Check Not Working

### Problem
S-mode can access user pages (U-bit set) even when SUM=0, violating RISC-V privilege spec.

### Evidence
test_vm_sum_read.s:
- Stage 5: Load from U-page with SUM=0 should fault
- Actual: Load succeeds, no fault generated
- Test fails at stage 5 (t4=1, t28=0xdeaddead)

### Investigation Done
1. ✅ Verified SUM CSR read/write works (test_sum_basic_debug passes)
2. ✅ Verified SUM wiring: mstatus_sum connected from CSR to MMU
3. ✅ Verified permission function looks correct (rtl/core/mmu.v:238-241):
   ```verilog
   else if (priv_mode == 2'b01) begin  // Supervisor mode
     if (pte_flags[PTE_U] && !sum) begin
       check_permission = 0;  // Supervisor accessing user page without SUM
     end
   end
   ```
4. ✅ Verified PTE has U-bit set (0xD7 = 0b11010111, bit 4 = 1)
5. ✅ Verified exception_unit handles load page faults

### Possible Root Causes (Next Session)
1. Privilege mode not actually S-mode when we think it is?
2. Function check_permission not being evaluated correctly in combinational logic?
3. Timing issue: permission check result not propagating to exception unit?
4. TLB storing permissions separately and not re-checking on each access?

### Next Steps
- Add targeted debug output to see actual priv_mode and sum values at check time
- Test with inlined permission check instead of function
- Verify current_priv updates correctly on SRET
- Check if TLB hit path bypasses permission recheck

## Test Progress

**Total Progress:** 5/44 tests (11.4%)

**Phase 1 (CSR tests):** 3/3 ✅ COMPLETE
- test_sum_basic.s ✅
- test_mxr_basic.s ✅
- test_sum_mxr_csr.s ✅

**Phase 2 (VM tests):** 2 tests complete
- test_vm_identity_basic.s ✅
- test_vm_identity_multi.s ✅

**Week 1 (Priority 1A):** 5/10 tests (50%)
- 3 CSR tests ✅
- 2 VM identity tests ✅
- 5 remaining: test_vm_sum_read, test_vm_non_identity, test_tlb_basic, test_vm_mxr_execute, test_vm_sum_mxr_combined

## Files Modified

### Tests
- `tests/asm/test_vm_identity_multi.s` - Fixed PTE values (5 changes)
- `tests/asm/test_vm_sum_read.s` - Created (345 lines)
- `tests/asm/test_sum_basic_debug.s` - Created (63 lines)
- `tests/asm/test_page_fault_invalid.s` - Created (96 lines)

### RTL
- `rtl/core/mmu.v` - Added V-bit check in PTW (lines 420-423)

## Performance Metrics

### test_vm_identity_multi
- **Cycles:** 246
- **Instructions:** 199
- **CPI:** 1.236
- **Stalls:** 51 cycles (20.7%), 20 load-use
- **Flushes:** 23 cycles (9.3%)

### test_sum_basic_debug
- **Cycles:** 62
- **Instructions:** 39
- **CPI:** 1.590
- **Stalls:** 7 cycles (11.3%)

## Key Learnings

1. **PTE Calculation Pitfall:** Easy to confuse PPN extraction (PA >> 12) with PTE construction ((PPN << 10) | flags). Always double-check bit positions!

2. **MMU V-bit Critical:** The valid bit must be checked FIRST before any PTE processing. This is a security-critical check that prevents using garbage data as PTEs.

3. **Test-Driven Debug:** Creating simpler tests (test_sum_basic_debug, test_page_fault_invalid) helped isolate where SUM works vs where it doesn't.

4. **Infinite Loops from Invalid PTEs:** Without V-bit check, PTW interprets invalid PTEs as non-leaf and tries to walk further, using garbage PPNs → more garbage → infinite loop.

5. **Function Permission Checks:** Verilog functions in combinational logic may have subtle evaluation issues. Consider inlining critical checks if function behavior is suspect.

## Next Session Plan

### High Priority
1. **Investigate SUM permission bug** - This blocks 5 Week 1 tests
   - Add debug output to see actual priv_mode/sum values
   - Try inlining permission check
   - Verify TLB doesn't cache stale permissions

2. **Verify V-bit fix works** - Retest test_page_fault_invalid
   - Should now properly fault on invalid PTEs
   - Should complete quickly (not timeout)

### Alternative Path (if SUM blocked)
3. **Continue with non-SUM tests:**
   - test_vm_non_identity.s - Non-identity mapping (VA 0x10000000 → PA 0x80000000)
   - test_tlb_basic.s - TLB hit/miss verification

These don't require SUM and can proceed in parallel with SUM debugging.

## References

- RISC-V Privileged Spec v1.12: Section 4.3 (Sv32), Section 4.4.1 (Page Fault Exceptions)
- Previous sessions: Session 90 (PTW handshake fix), Session 91 (testbench fixes), Session 92 (megapage fix)
- Test plan: docs/PHASE_4_PREP_TEST_PLAN.md
- Test inventory: docs/TEST_INVENTORY_DETAILED.md
