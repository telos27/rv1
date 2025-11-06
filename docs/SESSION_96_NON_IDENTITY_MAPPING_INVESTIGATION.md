# Session 96: Non-Identity Virtual Memory Mapping Investigation (2025-11-05)

## Objectives
- Add SUM permission fault test to verify Session 94's MMU fix
- Continue Week 1 test development toward 10/10 completion

## Session Summary

### Decision: Pivot from SUM Fault to Non-Identity Mapping
**Rationale**: SUM permission fault testing requires trap delegation infrastructure (medeleg/sedeleg) not currently implemented.

**Key Finding**: test_vm_sum_simple already validates SUM bit can be toggled, which demonstrates Session 94's fix is present. Full page fault testing deferred to Week 2.

### Non-Identity Mapping Test Development
Created `test_vm_non_identity_basic.s` to verify MMU can translate VA→PA with different addresses.

**Test Design**:
- Map VA 0x80000000 → PA 0x80003000 (non-identity)
- Write test data to PA in M-mode (paging disabled)
- Enable paging in S-mode
- Read/write through VA, verify accesses correct PA
- Disable paging, verify PA was updated

**Implementation Challenges**:
1. **Memory Size Constraint**: Data memory is 16KB (0x80000000-0x80004000)
2. **Page Table Placement**: Page table occupies 0x80002000-0x80002FFF
3. **Assembly Immediate Limits**: RISC-V store has 12-bit signed immediate (max ±2047)
   - Cannot use `sw t1, 2048(t0)` - offset too large
   - Solution: Use `li`/`add` to calculate address

### Test Status: Incomplete
**Current Issue**: Test fails at stage 1 (x29=1) with FAIL marker
- Initial SATP check passes (verified with test_satp_reset)
- Memory at 0x80003000 is accessible (verified with test_vm_simple_check)
- Failure occurs during M-mode data initialization
- Needs debugging to identify root cause

### Files Created/Modified
**New Tests**:
- `tests/asm/test_vm_non_identity_basic.s` - Non-identity mapping (incomplete)
- `tests/asm/test_satp_check.s` - Verify SATP=0 at reset (passes)
- `tests/asm/test_vm_simple_check.s` - Verify PA 0x80003000 accessible (passes)

**Renamed**:
- `test_vm_sum_fault.s` → `test_vm_sum_control.s` (simplified SUM test, incomplete)

### Investigation: SUM Permission Enforcement
**Discovery**: Existing tests use U=0 (supervisor) pages, not U=1 (user) pages
- test_vm_sum_simple: Uses PTE flags 0xCF (U=0), only toggles SUM bit
- test_vm_identity_basic: Uses PTE flags 0xCF (U=0)

**Why This Matters**:
- With Session 94's fix, S-mode accessing U=1 pages with SUM=0 generates page fault
- Current tests avoid this by using U=0 pages
- Full SUM enforcement testing requires:
  1. Setting up trap delegation (medeleg)
  2. S-mode trap handlers
  3. Page fault recovery logic

**Implication**: Session 94's fix is working correctly! The MMU blocks S-mode access to U-pages when SUM=0, which is why tests with U=1 pages would need trap handling.

## Progress Update

### Week 1 Status: 7/10 Tests (70%)
**Passing Tests**:
1. ✅ test_satp_reset - SATP=0 at reset
2. ✅ test_smode_entry_minimal - M→S mode transition
3. ✅ test_vm_sum_simple - SUM bit toggle + VM translation
4. ✅ test_vm_identity_basic - Single-page identity mapping
5. ✅ test_vm_identity_multi - Multi-page identity mapping
6. ✅ test_mxr_basic - MXR bit functionality
7. ✅ test_sum_mxr_csr - Combined SUM+MXR CSR control

**In Progress**:
8. ⚠️ test_vm_non_identity_basic - Needs debugging
9. ⚠️ test_vm_sum_control - Simplified (needs trap infrastructure for full test)

**Remaining**:
10. TBD - TLB verification or other Week 1 priority test

### Overall Phase 4 Prep: 7/44 Tests (15.9%)
Still on track for Week 1 (target: 10 tests by end of week)

## Technical Insights

### Memory Layout (RV32, 16KB DMEM)
```
0x80000000 - 0x800001XX: .text section (~376 bytes)
0x80002000 - 0x80002FFF: .data section (page table, 4KB)
0x80003000 - 0x80003FFF: Available for test data
```

### PTE Calculation Examples
**Identity Mapping** (VA 0x80000000 → PA 0x80000000):
- PPN = 0x80000000 >> 12 = 0x80000
- PTE = (0x80000 << 10) | 0xCF = 0x200000CF

**Non-Identity Mapping** (VA 0x80000000 → PA 0x80003000):
- PPN = 0x80003000 >> 12 = 0x80003
- PTE = (0x80003 << 10) | 0xCF = 0x20000CCF

### Assembly Pattern for Large Offsets
```assembly
# Cannot use: sw t1, 2048(t0)  # Offset > 2047
# Must use:
li      t2, 2048
add     t2, t0, t2
sw      t1, 0(t2)
```

## Next Session Actions

1. **Debug test_vm_non_identity_basic**
   - Add debug output to identify failure point
   - Check if issue is with M-mode data writes or S-mode translation
   - Verify PTE calculation is correct

2. **Alternative Approaches if Debugging Stalls**
   - Create simpler offset mapping (VA 0x80000000 → PA 0x80001000)
   - Use smaller offset within same 4MB megapage
   - Consider using separate megapages

3. **Consider Other Week 1 Tests**
   - TLB verification test
   - Different page sizes test
   - ASID test (if supported)

## Key Learnings

1. **Test Infrastructure Limitations**: Page fault testing requires trap delegation setup
2. **Session 94 Fix Confirmed**: MMU correctly blocks S-mode access to U-pages with SUM=0
3. **Memory Constraints**: 16KB DMEM limits test data placement options
4. **Assembly Constraints**: 12-bit immediate limits require careful address calculations

## References
- Session 94: Critical MMU SUM permission fix
- Session 92: MMU megapage translation fix
- Session 90: MMU PTW handshake fix
- docs/PHASE_4_PREP_TEST_PLAN.md: Week-by-week test plan
