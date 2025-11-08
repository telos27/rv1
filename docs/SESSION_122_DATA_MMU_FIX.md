# Session 122: Critical Data MMU Bug Fix - Translation Now Working!

**Date**: 2025-11-07
**Focus**: Fix critical bug where data memory accesses bypassed MMU translation
**Status**: ✅ **MAJOR BREAKTHROUGH** - Data MMU now functional!
**Impact**: Unblocks Phase 4 Week 2 permission tests

---

## Executive Summary

### Critical Discovery
**All Phase 4 tests were passing by accident** - they used identity mapping (VA=PA) which masked the fact that **data memory accesses were completely bypassing MMU translation!** Only instruction fetches were being translated.

### The Bug (Two-Part)
1. **EXMEM Register Using Wrong Signals**: Captured shared MMU outputs instead of EX-specific signals
2. **MMU Arbiter Starvation**: EX stage never got MMU access when IF also needed it

### The Fix
Two critical changes to `rtl/core/rv32i_core_pipelined.v`:
1. **Line 2428-2431**: Changed EXMEM inputs from `mmu_req_*` → `ex_mmu_req_*`
2. **Line 2722**: Added stall for EX waiting on MMU grant

### Results
- ✅ Data MMU translation **NOW WORKING** (first time ever!)
- ✅ Permission violations detected correctly
- ✅ Zero regressions (14/14 quick tests pass)
- ⚠️ Page fault trap delivery needs debugging (next session)

---

## Detailed Problem Analysis

### Initial Symptoms
When implementing `test_pte_permission_rwx.s` to test R/W/X permission bits:
- Test tried to write to read-only page (R=1, W=0, X=0)
- **Expected**: Store/AMO page fault (exception code 15)
- **Actual**: Store succeeded without fault!

### Investigation Process

#### Step 1: Check MMU Debug Output
```
MMU: Translation mode, VA=0x80000090 (fetch=1 store=0), TLB hit=0
MMU: Translation mode, VA=0x80000094 (fetch=1 store=0), TLB hit=1
MMU: Translation mode, VA=0x80000098 (fetch=1 store=0), TLB hit=1
```

**Discovery**: Only seeing `fetch=1 store=0` - NO data accesses!

#### Step 2: Check Existing Tests
Ran `test_sum_enabled` (known passing test):
```bash
timeout 10 tools/run_test_by_name.sh test_sum_enabled 2>&1 | grep "fetch=0"
# NO OUTPUT!
```

**Discovery**: Even passing Phase 4 tests show no data MMU activity!

#### Step 3: Verify Identity Mapping Hypothesis
Checked `test_sum_enabled.s`:
```assembly
# Create 1-level page table for Sv32 (identity mapping + U-page)
li t2, 0x200000CF           # PPN[21:10]=0x80000, flags=0xCF (V,R,W,X)
sw t2, 0(t4)                # page_table[512] = 0x200000CF
# This creates a 4MB megapage at VA 0x80000000 → PA 0x80000000 (identity)
```

**Confirmed**: All Phase 4 tests use identity mapping, so untranslated VAs equal PAs!

---

## Root Cause Analysis

### Bug #1: EXMEM Register Using Shared MMU Signals

**Location**: `rtl/core/rv32i_core_pipelined.v:2428-2431`

**Original Code**:
```verilog
exmem_register exmem (
    // ...
    // MMU translation results from EX stage
    .mmu_paddr_in(mmu_req_paddr),        // ❌ WRONG! Shared signal
    .mmu_ready_in(mmu_req_ready),        // ❌ WRONG! Could be IF result
    .mmu_page_fault_in(mmu_req_page_fault),
    .mmu_fault_vaddr_in(mmu_req_fault_vaddr),
    // ...
);
```

**Problem**:
- MMU is shared between IF (instruction fetch) and EX (data access)
- `mmu_req_ready` is TRUE when MMU completes ANY translation (IF or EX)
- EXMEM would capture IF translation results and think they were for data!
- Result: `exmem_translation_ready` was often FALSE or had wrong `exmem_paddr`

**Fix**:
```verilog
exmem_register exmem (
    // ...
    // MMU translation results from EX stage (use EX-specific signals!)
    .mmu_paddr_in(ex_mmu_req_paddr),           // ✅ EX-specific
    .mmu_ready_in(ex_mmu_req_ready),           // ✅ Only true for EX
    .mmu_page_fault_in(ex_mmu_req_page_fault),
    .mmu_fault_vaddr_in(ex_mmu_req_fault_vaddr),
    // ...
);
```

Where `ex_mmu_req_ready` is defined at line 2666:
```verilog
assign ex_mmu_req_ready = ex_mmu_req_valid && mmu_req_ready;
```

This ensures EXMEM only captures translation results that are actually for EX!

### Bug #2: MMU Arbiter Starvation

**Location**: `rtl/core/rv32i_core_pipelined.v:2646-2647, 2718-2722`

**The Arbiter**:
```verilog
// EX gets MMU only if IF doesn't need it OR EX has the grant
assign ex_mmu_req_valid = ex_needs_translation && idex_valid &&
                          (!if_needs_translation || mmu_grant_to_ex_r);

// Grant toggles every cycle when both need MMU
always @(posedge clk) begin
  if (if_needs_translation && ex_needs_translation)
    mmu_grant_to_ex_r <= !mmu_grant_to_ex_r;  // Toggle
end
```

**Problem**: With paging enabled, IF **always** needs translation (constant instruction fetching). So:
- Cycle N: IF needs, EX needs, grant=0 → `ex_mmu_req_valid = 1 && 1 && (0 || 0) = 0` ❌
- Cycle N+1: IF needs, EX needs, grant=1 → `ex_mmu_req_valid = 1 && 1 && (0 || 1) = 1` ✅
- BUT by cycle N+1, the memory operation might have moved on!

**Debug Output**:
```
[DEBUG] EX MEM ACCESS: VA=0x10000000 mem_w=1 needs_trans=1
        if_needs=1 grant=0 -> ex_valid=0
        ^^^^ EX needs MMU but can't get it!
```

**Original `mmu_busy` (line 2718)**:
```verilog
assign mmu_busy = (mmu_req_valid && !mmu_req_ready) ||  // PTW in progress
                  mmu_page_fault_pending ||
                  (if_needs_translation && ex_needs_translation && mmu_grant_to_ex_r);
                  // ^^^ Only stalls IF when EX has grant
```

This stalls IF when EX has the MMU, but **doesn't stall EX when IF has the MMU!**

**Fix** (line 2722):
```verilog
assign mmu_busy = (mmu_req_valid && !mmu_req_ready) ||  // PTW in progress
                  mmu_page_fault_pending ||
                  (if_needs_translation && ex_needs_translation && mmu_grant_to_ex_r) ||  // EX has MMU, stall IF
                  (if_needs_translation && ex_needs_translation && !mmu_grant_to_ex_r);   // IF has MMU, stall EX
```

Now EX **holds** (doesn't advance to MEM stage) when waiting for MMU grant!

---

## Testing & Validation

### Test 1: Data MMU Activity Detection

**Created**: `test_pte_permission_simple.s` - Simplified permission test

**Test**: Write to read-only page (R=1, W=0, X=0) at VA 0x10000000

**Before Fix**:
```
# No MMU activity for data access!
MMU: Translation mode, VA=0x80000090 (fetch=1 store=0)
MMU: Translation mode, VA=0x80000094 (fetch=1 store=0)
# Store succeeds without translation
```

**After Fix**:
```
[DEBUG] EX MMU REQ: VA=0x10000000 store=1 ready=1
MMU: Translation mode, VA=0x10000000 (fetch=0 store=1), TLB hit=1
MMU: TLB HIT VA=0x10000000 PTE=0x03[U=0] priv=01 sum=0 result=0
MMU: Permission DENIED - PAGE FAULT!
```

**Result**: ✅ **Data MMU now works!** First time seeing `fetch=0`!

### Test 2: Regression Testing

```bash
make test-quick
```

**Results**:
```
Total:   14 tests
Passed:  14
Failed:  0
Time:    3s

✓ All quick regression tests PASSED!
```

**Analysis**: Zero regressions! Tests still pass because they use identity mapping.

---

## Known Issues (For Next Session)

### Issue: Page Fault Trap Not Delivered

**Symptom**: Test times out in infinite loop
```
[DEBUG] EX MMU REQ: VA=0x10000000 store=1
MMU: Permission DENIED - PAGE FAULT!
[DEBUG] EX MMU REQ: VA=0x10000000 store=1  # Repeats forever!
MMU: Permission DENIED - PAGE FAULT!
# ... loops 50,000 times ...
```

**Expected**: Page fault should trigger trap to S-mode handler

**Actual**: Instruction retries indefinitely

**Hypothesis**: `mmu_page_fault_pending` logic may not be working for data accesses, or exception unit isn't propagating data page faults to trap logic.

**Next Session**: Debug page fault trap delivery for data accesses.

---

## Code Changes Summary

### File: `rtl/core/rv32i_core_pipelined.v`

#### Change 1: EXMEM Register MMU Inputs (Lines 2427-2431)
```diff
     .pc_in(idex_pc),
-    // MMU translation results from EX stage
-    .mmu_paddr_in(mmu_req_paddr),
-    .mmu_ready_in(mmu_req_ready),
-    .mmu_page_fault_in(mmu_req_page_fault),
-    .mmu_fault_vaddr_in(mmu_req_fault_vaddr),
+    // MMU translation results from EX stage (use EX-specific signals!)
+    .mmu_paddr_in(ex_mmu_req_paddr),
+    .mmu_ready_in(ex_mmu_req_ready),
+    .mmu_page_fault_in(ex_mmu_req_page_fault),
+    .mmu_fault_vaddr_in(ex_mmu_req_fault_vaddr),
     // Outputs
```

#### Change 2: MMU Busy Stall Logic (Lines 2717-2722)
```diff
   // Session 119: Stall when MMU busy OR when IF needs MMU but EX has it
+  // Session 122: Also stall when EX needs MMU but IF has it (waiting for grant)
   assign mmu_busy = (mmu_req_valid && !mmu_req_ready) ||      // PTW in progress
                     mmu_page_fault_pending ||                  // Page fault pending trap
-                    (if_needs_translation && ex_needs_translation && mmu_grant_to_ex_r);  // EX has MMU, stall IF
+                    (if_needs_translation && ex_needs_translation && mmu_grant_to_ex_r) ||  // EX has MMU, stall IF
+                    (if_needs_translation && ex_needs_translation && !mmu_grant_to_ex_r);   // IF has MMU, stall EX
```

**Total Lines Changed**: 6 lines
**Impact**: Fixes critical data MMU bug affecting all Phase 4 tests

---

## Test Files Created

### `tests/asm/test_pte_permission_simple.s` (103 lines)
Simplified permission test using priv_test_macros:
- Tests write to read-only page (R=1, W=0, X=0)
- Expects Store/AMO page fault (exception code 15)
- Based on working `test_sum_minimal.s` template
- Uses `.option norvc` to avoid compressed instruction issues

### `tests/asm/test_pte_permission_rwx.s` (378 lines)
Complex permission test (incomplete due to infrastructure issues):
- Attempted to test all permission combinations
- Discovered compressed instruction compatibility issues
- Led to discovery of data MMU bug
- **Status**: Incomplete, to be revisited after page fault trap fix

---

## Performance Impact

### Before Fix
- Data accesses: 0 cycles MMU overhead (bypassed entirely!)
- Invalid: Worked only due to identity mapping accident

### After Fix
With round-robin arbiter (both IF and EX need MMU):
- IF gets MMU: 1 cycle
- EX waits (stalled): 1 cycle
- EX gets MMU: 1 cycle for TLB hit, N cycles for PTW
- IF waits (stalled): 1 cycle
- Total: ~2-cycle penalty per data access (alternating with IF)

**Note**: This is a temporary arbiter. Future optimization (Session 117 note): Implement separate I-TLB and D-TLB for zero contention.

---

## Impact on Phase 4 Tests

### Why Tests Were Passing Before
All existing Phase 4 Week 1 tests (9/9) use **identity mapping**:
```assembly
# Megapage: VA 0x80000000 → PA 0x80000000
li t1, 0x200000CF  # PPN=0x20000, R=1, W=1, X=1, V=1
```

With identity mapping:
- Untranslated VA = 0x80000000
- Should-be-translated PA = 0x80000000
- Accidental match! Tests pass despite broken data MMU

### Impact on Week 2 Tests
Week 2 tests require **non-identity mapping** and **permission violations**:
- test_pte_permission_rwx: Needs R/W/X enforcement
- test_syscall_user_memory_access: Needs SUM bit + user page access
- test_page_fault_recovery: Needs page fault delivery

**All were blocked by this bug!** Now unblocked (pending trap delivery fix).

---

## Lessons Learned

### 1. Identity Mapping Masks Bugs
Using VA=PA in all tests accidentally hid critical MMU bugs. Future tests should include:
- Non-identity mappings
- Sparse VA space
- Different VA/PA ranges

### 2. Shared Resource Arbitration is Hard
Round-robin arbiter seemed simple but had subtle starvation issues:
- Must stall waiting stage, not just grant alternately
- Pipeline stage that doesn't get resource must HOLD

### 3. Pipeline Registers Must Use Qualified Signals
When multiple stages share a resource (MMU), pipeline registers must capture **stage-specific** qualified signals, not shared outputs.

### 4. Debug Output is Essential
MMU debug showing `fetch=0/1` and `store=0/1` was critical for discovering the bug.

---

## Next Session Tasks

### Priority 1: Fix Page Fault Trap Delivery
- Debug why data page faults aren't triggering traps
- Check `mmu_page_fault_pending` logic for data accesses
- Verify exception unit propagates `exmem_page_fault` correctly
- Test with `test_pte_permission_simple.s`

### Priority 2: Complete Permission Tests
- Finish `test_pte_permission_rwx.s`
- Add tests for all R/W/X combinations
- Test execute-only pages (X=1, R=0)

### Priority 3: Continue Phase 4 Week 2
Once page faults work:
- test_syscall_user_memory_access.s
- test_page_fault_invalid_recover.s
- Remaining 6/11 Week 2 tests

---

## References

- **Session 119**: MMU arbiter introduction (round-robin between IF/EX)
- **Session 117**: Instruction fetch MMU implementation
- **Session 115**: PTW req_ready protocol fix
- **Session 114**: Data memory bus adapter fix
- **RISC-V Spec Volume II**: Section 4.3 (Sv32 Page-Based Virtual Memory)

---

## Metrics

- **Time Spent**: ~4 hours debugging and fixing
- **Code Changed**: 2 critical sections, 6 lines
- **Tests Created**: 2 (481 lines total)
- **Regressions**: 0
- **Impact**: Unblocks Phase 4 Week 2 (6/11 tests pending)

---

**Session 122 Complete**: Data MMU now functional for the first time! 🎉
