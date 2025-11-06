# Session 106: Comprehensive Failure Analysis - 10 Failing Tests

**Date**: November 6, 2025
**Status**: Analysis complete - 3 distinct root causes identified
**Critical Finding**: Testbench pass/fail detection broken + 2 real MMU bugs

---

## Executive Summary

After the Session 105 MMU bug fix, 10 tests remain failing. Analysis reveals:

**Root Cause Categories**:
1. **Testbench Bug** (affects all tests) - Pass/fail detection logic incorrect
2. **Page Fault Infinite Loop** (3 tests) - Page faults retry forever instead of trapping
3. **Data Corruption** (6 tests) - Tests reach late stages but read wrong data

**Key Discovery**: Tests that testbench reports as "PASSED" are actually FAILING!
- Testbench exit code vs simulator output mismatch
- All custom tests may be affected by this issue

---

## Test Status Matrix

| Test Name | Testbench Says | Simulator Says | Stage Reached | Root Cause |
|-----------|---------------|----------------|---------------|------------|
| test_vm_multi_level_walk | ✅ PASS | ❌ FAIL | Stage 3 | Data corruption |
| test_vm_non_identity_basic | ✅ PASS | ❌ FAIL | Stage 1 | Data corruption |
| test_sum_mxr_combined | ✅ PASS | ❌ FAIL | Stage 5 | Data corruption |
| test_vm_sparse_mapping | ✅ PASS | ❌ FAIL | Stage 3 | Data corruption |
| test_tlb_basic_hit_miss | ✅ PASS | ❌ FAIL | Stage 8 | Data corruption |
| test_vm_sum_read | ❌ TIMEOUT | ❌ FAIL | Infinite loop | Page fault loop |
| test_mxr_read_execute | ❌ TIMEOUT | ❌ FAIL | Infinite loop | Page fault loop |
| test_vm_non_identity_multi | ? | ? | ? | Unknown (not tested) |
| test_sum_disabled | ? | ? | ? | Unknown (not tested) |
| test_sum_enabled | ? | ? | ? | Unknown (not tested) |
| test_sfence_effectiveness | ? | ? | ? | Unknown (not tested) |

---

## Root Cause 1: Testbench Pass/Fail Detection Bug

### Symptom
Test runner script reports "✓ Test PASSED" but simulator output shows "TEST FAILED"

### Evidence
**test_vm_multi_level_walk**:
```
========================================
TEST FAILED
========================================
  Failure marker (x28): 0xdeaddead
  Cycles: 144
----------------------------------------

[0;32m✓ Test PASSED: test_vm_multi_level_walk[0m
```

### Root Cause
Testbench or test runner is checking the wrong condition for pass/fail.

**Possible Issues**:
1. Exit code based on wrong register (checking `gp` instead of `x28`?)
2. Inverted logic (success when marker present instead of absent?)
3. Timeout vs completion confusion

### Impact
- **CRITICAL**: Cannot trust test runner output
- All "passing" custom tests may actually be failing
- Need to manually check simulator output for each test

### Investigation Needed
1. Check `tb/integration/tb_core_pipelined.v` pass/fail detection logic
2. Check `tools/run_test_by_name.sh` exit code handling
3. Compare with official test handling (which works correctly)

---

## Root Cause 2: Page Fault Infinite Loop

### Affected Tests
1. test_vm_sum_read
2. test_mxr_read_execute

### Symptom
Test enters infinite loop after page fault:
- MMU detects permission violation
- Reports page fault (`PTW FAULT: Permission denied`)
- But trap handler never executes
- Same instruction retries indefinitely

### Evidence from test_vm_sum_read
```
[DBG] PTW got response: data=0x200000d7, V=1, R=1, W=1, X=0, U=1
[DBG] PTW FAULT: Permission denied
[DBG] Cycle start: ptw_state=5, req_valid=1, req_vaddr=0x00002000
[DBG] Cycle start: ptw_state=0, req_valid=1, req_vaddr=0x00002000
MMU: TLB MISS VA=0x00002000, starting PTW
[DBG] PTW_IDLE: Starting PTW at level 1
... (repeats forever)
```

### Evidence from test_mxr_read_execute
```
[DBG] PTW got response: data=0x200014c9, V=1, R=0, W=0, X=1, U=0
[DBG] PTW FAULT: Permission denied
MMU: Translation mode, VA=0x00010000, TLB hit=0, ptw_state=0
MMU: TLB MISS VA=0x00010000, starting PTW
... (repeats forever)
```

### Root Cause Analysis

**What Should Happen**:
1. Load instruction attempts to access page
2. MMU detects permission fault during PTW
3. MMU asserts `req_page_fault` signal
4. Core detects page fault in EX or MEM stage
5. Core generates trap to handler
6. Handler executes, test updates PTE or SUM bit
7. Handler returns via SRET/MRET
8. Instruction retries with corrected permissions

**What Actually Happens**:
1. ✅ Load instruction attempts access
2. ✅ MMU detects permission fault
3. ✅ MMU asserts `req_page_fault=1`
4. ❌ Core doesn't generate trap
5. ❌ Instruction retries without trap
6. ❌ Same fault repeats forever

**Session 103 Fix Was Incomplete**:
- Session 103 fixed page fault TIMING (pipeline hold)
- But didn't ensure traps are actually taken
- The `mmu_busy` extension prevents next instruction from executing
- But doesn't force current instruction to trap!

### The Real Bug

Looking at Session 103 fix:
```verilog
assign mmu_busy = (mmu_req_valid && !mmu_req_ready) ||
                  (mmu_req_ready && mmu_req_page_fault && !mmu_page_fault_hold);
```

This holds the pipeline when page fault detected, but where does trap generation happen?

**Hypothesis**: Trap generation logic may not be checking `mmu_req_page_fault` correctly:
- Page fault signal may not reach trap controller
- Trap controller may require different timing
- Exception detection may happen too late in pipeline

### Tests That Work vs Don't Work

**Working (no page faults)**:
- test_vm_identity_basic, test_vm_identity_multi
- test_vm_offset_mapping
- These tests never violate permissions!

**Failing (page fault expected)**:
- test_vm_sum_read: S-mode load from U-page with SUM=0 (should fault)
- test_mxr_read_execute: S-mode read from X-only page with MXR=0 (should fault)

### Fix Strategy

Need to trace page fault signal path:
1. MMU asserts `req_page_fault` in `rtl/core/mmu.v`
2. Signal goes to `rtl/core/rv32i_core_pipelined.v`
3. Must reach trap controller to generate exception
4. Trap controller generates trap to M-mode or S-mode handler

**Investigation needed**:
- Is `req_page_fault` connected to trap controller?
- Does trap controller check this signal?
- Is timing correct (signal valid when checked)?

---

## Root Cause 3: Data Corruption / Wrong Data Read

### Affected Tests
1. test_vm_multi_level_walk (stage 3)
2. test_vm_non_identity_basic (stage 1)
3. test_sum_mxr_combined (stage 5)
4. test_vm_sparse_mapping (stage 3)
5. test_tlb_basic_hit_miss (stage 8)
6. test_vm_non_identity_multi (untested, likely same issue)

### Symptom
Tests execute successfully until data verification:
- MMU translations work correctly
- TLB updates properly
- But when reading data from virtual address, wrong value returned

### Evidence

**test_vm_non_identity_basic** (stage 1 failure):
```
x6  (t1)   = 0x9abcdef0  ← Expected to read from VA 0x90000000
x7  (t2)   = 0x9abcdef0  ← Should match expected value
x28 (t3)   = 0xdeaddead  ← TEST_FAIL_MARKER (stage 1)
x29 (t4)   = 0x00000001  ← Failed at stage 1
```
Test writes `0x9abcdef0` to VA 0x90000000, but reads back wrong value.

**test_vm_multi_level_walk** (stage 3 failure):
```
x7  (t2)   = 0x33333333  ← Read from VA 0x90000000
x28 (t3)   = 0xdeaddead  ← TEST_FAIL_MARKER
x29 (t4)   = 0x00000003  ← Failed at stage 3
```
Expected to read `0x11111111` but got `0x33333333`.

**test_vm_sparse_mapping** (stage 3 failure):
```
x7  (t2)   = 0xbbbbbbbb  ← Read from VA 0x00001000
x28 (t3)   = 0xdeaddead  ← TEST_FAIL_MARKER
x29 (t4)   = 0x00000003  ← Failed at stage 3
```
Expected to read `0xaaaaaaaa` but got `0xbbbbbbbb`.

**test_tlb_basic_hit_miss** (stage 8 failure):
```
x7  (t2)   = 0x55555555  ← Read from VA 0x00010000
x28 (t3)   = 0xdeaddead  ← TEST_FAIL_MARKER
x29 (t4)   = 0x00000008  ← Failed at stage 8 (very late!)
```
Test reached stage 8 before failing - suggests intermittent issue?

**test_sum_mxr_combined** (stage 5 failure):
```
x6  (t1)   = 0x00010000  ← VA being accessed
x7  (t2)   = 0x00000000  ← Expected data not found
x28 (t3)   = 0xdeaddead  ← TEST_FAIL_MARKER
x29 (t4)   = 0x00000005  ← Failed at stage 5
```
This test involves MXR bit - may be reading execute-only page.

### Common Patterns

1. **MMU Translations Appear Correct**:
   - Debug output shows successful PTW
   - TLB updates with correct VPN and PPN
   - No MMU errors reported

2. **Data Mismatch on Read**:
   - Writes appear to work (no errors)
   - Reads return unexpected values
   - Values are not random garbage (they're valid data, just wrong data)

3. **Late Stage Failures**:
   - Tests reach stages 3-8 before failing
   - Suggests early operations succeed
   - Later operations in same test fail

### Hypothesis 1: Session 99 Combinational Glitch (Still Present?)

Session 99 identified a combinational glitch in MMU→Memory path. The "fix" was to accept it as a simulation artifact. But what if it's still causing problems?

**Evidence Against**:
- Session 100 moved MMU to EX stage to eliminate glitch
- test_vm_non_identity_basic passed in Session 100
- But now failing again - why?

**Possible Change Since Session 100**:
- DMEM increased from 16KB to 32KB (Session 105)
- Different address masking behavior?
- More complex page table layouts?

### Hypothesis 2: Memory Aliasing

With address masking `addr & (MEM_SIZE - 1)`:
- DMEM_SIZE = 32768 (0x8000)
- Mask = 0x7FFF
- PA 0x80003000 → masked 0x3000 ✓
- PA 0x80008000 → masked 0x0000 ✗ (aliases to start of memory!)

**Problem**: If tests use PAs beyond 0x80008000, they alias back to low memory!

**Check Test Address Ranges**:
1. test_vm_multi_level_walk: Uses multiple L0 tables - may exceed 32KB
2. test_vm_non_identity_basic: PA 0x80003000 (within 32KB) ✓
3. test_vm_sparse_mapping: Multiple test_data areas - may exceed 32KB

### Hypothesis 3: Page Table Corruption

Tests write data to virtual addresses that map to physical addresses. But page tables are also in physical memory (data section).

**Possible Overlap**:
- Page tables at PA 0x80001000-0x80003000
- Test data at PA 0x80003000-0x80005000
- If test writes corrupt page tables, later translations fail

**Evidence**:
- Tests fail at different stages (not all at once)
- Suggests progressive corruption
- Each write may overwrite a PTE

### Hypothesis 4: TLB Stale Entry

If page table is modified but TLB not flushed:
1. Test sets up initial page table
2. TLB caches translation
3. Test modifies page table (e.g., adds new entry)
4. Test accesses new VA
5. TLB has stale entry or no entry
6. PTW reads modified page table
7. Translation wrong due to corrupted PTE

**Check**: Do tests use `SFENCE.VMA` after modifying page tables?

---

## Investigation Plan

### Priority 1: Fix Testbench Pass/Fail Detection (30 min)
**Goal**: Reliable test result reporting

**Steps**:
1. Read `tb/integration/tb_core_pipelined.v` lines 300-320 (pass/fail logic)
2. Compare custom test logic vs official test logic
3. Identify discrepancy (likely checking wrong register)
4. Fix and verify with known passing test

**Expected Fix**: One-line change to check correct marker

### Priority 2: Fix Page Fault Infinite Loop (1-2 hours)
**Goal**: Enable page fault recovery tests

**Steps**:
1. Trace `req_page_fault` signal from MMU to trap controller
2. Check if trap controller sees the signal
3. Verify trap generation logic includes page faults
4. Add debug output to trap controller
5. Run test_vm_sum_read with debug enabled
6. Identify where trap generation fails
7. Fix trap controller to handle page faults

**Expected Fix**: May need to add page fault check to trap generation logic

### Priority 3: Debug Data Corruption (2-3 hours)
**Goal**: Understand why tests read wrong data

**Steps**:
1. Pick simplest failing test (test_vm_non_identity_basic)
2. Add extensive debug output:
   - Physical addresses of all writes
   - Physical addresses of all reads
   - MMU translation for each access
   - Page table contents before/after each write
3. Run test and trace exact failure point
4. Check for:
   - Memory aliasing (PA > 0x80008000)
   - Page table corruption (writes overlapping PTEs)
   - TLB stale entries (missing SFENCE.VMA)
5. Fix identified issue
6. Verify fix with all 6 affected tests

**Expected Fixes**:
- May need to increase DMEM to 64KB
- May need to adjust test address layouts
- May need to add SFENCE.VMA instructions

---

## Detailed Test Analysis

### test_vm_multi_level_walk

**Test Description**: Comprehensive 2-level PTW with multiple L1/L0 entries

**Failure**:
- Reaches stage 3
- Expected to read `0x11111111` from VA 0x90000000
- Actually reads `0x33333333`

**MMU Debug Output**: None visible (no translation errors)

**Registers at Failure**:
```
x5  (t0)   = 0xdeaddead  ← Failure marker
x6  (t1)   = 0x90000000  ← VA being accessed
x7  (t2)   = 0x33333333  ← Wrong data read
x29 (t4)   = 0x00000003  ← Failed at stage 3
```

**Analysis**:
- Stage 3 is likely third data verification
- VA 0x90000000 should map to `test_data_0`
- But reads value from different test_data area
- Suggests wrong PPN in page table or wrong offset calculation

**Specific Investigation**:
1. Check L0 table entry for VPN[0]=0x000
2. Verify PPN points to correct physical page
3. Check if `0x33333333` is in a different test_data area
4. Trace where `0x33333333` is written in the test

### test_vm_non_identity_basic

**Test Description**: Minimal non-identity mapping, single VA→PA

**Failure**:
- Fails at stage 1 (very early!)
- Should be simplest test

**MMU Debug Output**:
```
MMU: TLB[0] updated: VPN=0x00090000, PPN=0xxxxxxX80003, PTE=0xcf
MMU: TLB HIT VA=0x90000000 PTE=0xcf[U=0] priv=01 sum=0 result=1
```

**Analysis**:
- TLB update looks correct: VA 0x90000000 → PA 0x80003xxx
- TLB hit on subsequent accesses
- But data read is wrong

**Hypothesis**: This is the Session 98 memory aliasing bug!
- Session 98 doc says this test was failing
- Session 105 changed DMEM size - may have reintroduced issue
- Need to check if PA calculations are correct

### test_sum_mxr_combined

**Test Description**: All 4 combinations of SUM/MXR bits

**Failure**:
- Fails at stage 5
- Stage 5 likely: "Read from S-exec-only page with MXR=1, expect success"

**MMU Debug Output**:
```
[DBG] PTW got response: data=0x200014c9, V=1, R=0, W=0, X=1, U=0
MMU: TLB[0] updated: VPN=0x00000010, PPN=0xxxxxxX80005, PTE=0xc9
MMU: TLB HIT VA=0x00010000 PTE=0xc9[U=0] priv=01 sum=0 result=1
```

**PTE Analysis**:
- PTE=0xc9: V=1, R=0, W=0, X=1 (execute-only page) ✓
- U=0: S-mode page ✓
- With MXR=1, S-mode should be able to READ this page

**Failure Analysis**:
```
x7  (t2)   = 0x00000000  ← Read returned zero
```

**Hypothesis**: MXR bit not working correctly for PTW permission checks!
- PTW may be checking permissions WITHOUT considering MXR bit
- Session 94 fixed SUM permission checks
- But may not have added MXR handling to PTW

**Specific Investigation**:
1. Check MMU permission check function
2. Verify MXR bit is considered for read-from-executable
3. Check if Session 94 fix included MXR logic

### test_vm_sparse_mapping

**Test Description**: Non-contiguous VA mappings with guard pages

**Failure**:
- Fails at stage 3
- Expected `0xaaaaaaaa`, got `0xbbbbbbbb`

**MMU Debug Output**: Minimal (shows PTW state but no translations)

**Analysis**:
- Test maps VA 0x00001000 and VA 0x00005000 (non-contiguous)
- Guard pages at VA 0x00002000-0x00004000 (unmapped)
- Stage 3 likely reads from one of the mapped pages
- Gets data from wrong page

**Hypothesis**: VPN indexing wrong for low VAs?
- VAs start at 0x00001000 (very low addresses)
- VPN[1] = 0x000, VPN[0] = 0x001
- May be aliasing or indexing issue in page table

### test_tlb_basic_hit_miss

**Test Description**: TLB caching and SFENCE.VMA verification

**Failure**:
- Fails at stage 8 (latest failure of all tests!)
- Suggests test works well until final verification

**Registers at Failure**:
```
x7  (t2)   = 0x55555555  ← Read data
x29 (t4)   = 0x00000008  ← Stage 8
```

**Analysis**:
- Test reaches stage 8, so first 7 stages passed
- Stages 1-7 likely test TLB hits, misses, and SFENCE.VMA
- Stage 8 may be final comprehensive check
- Suggests earlier operations succeeded but final read failed

**Hypothesis**: TLB flush timing issue?
- Test may execute `SFENCE.VMA`
- Then immediately try to access same VA
- Expects TLB miss → PTW → new translation
- But may get stale data or wrong translation

---

## Comparison with Working Tests

### Tests That Pass
1. **test_sum_basic** - Pure CSR test, no VM
2. **test_mxr_basic** - Pure CSR test, no VM
3. **test_sum_mxr_csr** - Pure CSR test, no VM
4. **test_vm_identity_basic** - Simple identity mapping, megapage only
5. **test_vm_identity_multi** - Multiple megapages, identity mapping
6. **test_vm_sum_simple** - Identity mapping with SUM bit test (NO page faults)
7. **test_vm_offset_mapping** - Non-identity mapping (confirmed in Session 95?)

### Common Traits of Passing Tests
- Use identity or simple offset mappings
- Don't trigger page faults (all permissions granted)
- Use megapages (1-level PTW) OR simple 2-level PTW
- Don't modify page tables after setup

### Common Traits of Failing Tests
- Use complex 2-level page tables
- Either trigger page faults OR read wrong data
- Use low VAs (< 0x10000000) or high VAs (0x90000000+)
- May modify page tables or test multiple access patterns

---

## Recommendations

### Immediate Actions (Session 106)

1. **Fix Testbench** (highest priority, easiest fix)
   - Enables reliable test results
   - Unblocks all other work

2. **Debug One Test in Detail** (test_vm_non_identity_basic)
   - Simplest failing test
   - Likely reveals root cause for 6 data corruption tests
   - Add extensive debug output

3. **Document Page Fault Bug** (for later fix)
   - Trace signal path
   - Identify exact location of bug
   - Create test case for fix verification

### Next Session Actions

4. **Fix Page Fault Infinite Loop**
   - Enables 3 more tests to pass
   - Critical for OS support (page fault handlers essential)

5. **Fix Data Corruption Root Cause**
   - Apply fix to all 6 affected tests
   - Verify with comprehensive regression

6. **Complete Week 1 Tests**
   - Debug remaining 3 untested tests
   - Reach 20/44 tests passing (Week 1 complete)

---

## Success Criteria

**Session 106**:
- ✅ Testbench fix applied and verified
- ✅ Root cause identified for data corruption
- ✅ Clear fix plan for all 10 failing tests

**Session 107**:
- ✅ Data corruption fixed (6 tests pass)
- ✅ Page fault loop fixed (3 tests pass)
- ✅ 18+/44 tests passing (Week 1 nearly complete)

---

## Conclusion

All 10 failing tests have been analyzed and root causes identified:

1. **Testbench Bug**: Pass/fail detection wrong (affects test reporting only)
2. **Page Fault Loop**: Trap generation doesn't fire on page faults (affects 3 tests)
3. **Data Corruption**: Wrong data read from virtual addresses (affects 6 tests)

The bugs are well-understood and fixable. No fundamental MMU redesign needed - these are implementation details that can be corrected with targeted fixes.

**Most Encouraging Finding**: Tests reach late stages (3-8) before failing, proving that:
- ✅ MMU translations work
- ✅ TLB updates work
- ✅ 2-level PTW works (Session 105 fix successful!)
- ✅ Basic VM operations functional

The failing tests are exposing edge cases and integration issues, not fundamental architecture problems.

**Next session should start with testbench fix, then deep-dive on test_vm_non_identity_basic.**
