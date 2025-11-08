# Session 121: Phase 4 Week 2 - Context Switch Tests (FP and CSR)

**Date**: November 7, 2025
**Session Goal**: Implement FP and CSR context switch tests
**Starting Point**: 3/11 Phase 4 Week 2 tests complete (Session 120)
**Result**: ✅ **SUCCESS** - 5/11 Week 2 tests complete (45% → 45% progress)

---

## Summary

Successfully implemented **2 new context switch tests** to verify FP and CSR state preservation across task switches. Both tests follow the same pattern as the GPR context switch test from Session 120.

### Tests Implemented (2 new tests)

1. ✅ **test_context_switch_fp_state.s** (718 lines)
   - Tests preservation of all 32 FP registers (f0-f31) and FCSR
   - Pattern: Task A uses values 1.0-32.0, Task B uses 100.0-131.0
   - Verifies perfect isolation between tasks
   - 866 cycles, 531 instructions

2. ✅ **test_context_switch_csr_state.s** (308 lines)
   - Tests preservation of supervisor CSRs across context switches
   - CSRs tested: SEPC, SSTATUS, SSCRATCH, SCAUSE, STVAL
   - Includes round-robin switching test (A→B→A→B→A)
   - 227 cycles, 139 instructions

---

## Test Results

### New Tests (2/2 passing, 100%)

| Test | Status | Cycles | Description |
|------|--------|--------|-------------|
| test_context_switch_fp_state | ✅ PASS | 866 | FP register preservation |
| test_context_switch_csr_state | ✅ PASS | 227 | CSR state preservation |

### Regression Tests (14/14 passing, 100%)

Quick regression suite: ✅ **14/14 tests passing**
- Zero regressions
- Core remains stable

### Week 2 Progress (5/11 tests, 45%)

**Completed (5/11)**:
1. ✅ test_syscall_args_passing (Session 120)
2. ✅ test_context_switch_minimal (Session 120)
3. ✅ test_syscall_multi_call (Session 120)
4. ✅ test_context_switch_fp_state (Session 121) ← NEW
5. ✅ test_context_switch_csr_state (Session 121) ← NEW

**Remaining (6/11)**:
- test_page_fault_invalid_recover (exists, needs validation)
- test_page_fault_load_store_fetch
- test_page_fault_delegation
- test_syscall_user_memory_access
- test_pte_permission_rwx
- test_pte_permission_user_supervisor

---

## Implementation Details

### Test 1: test_context_switch_fp_state.s

**Purpose**: Verify floating-point state isolation between tasks

**Test Flow**:
1. Enable FPU (MSTATUS.FS = 1)
2. Load Task A FP values (1.0, 2.0, 3.0, ..., 32.0) into f0-f31
3. Set FCSR to 0xAA
4. Save Task A FP context to memory (32 FP regs + FCSR)
5. Load Task B FP values (100.0, 101.0, ..., 131.0) into f0-f31
6. Set FCSR to 0x55
7. Save Task B FP context to memory
8. Restore Task A FP context from memory
9. Verify all 32 FP registers match original values
10. Verify FCSR matches original value (0xAA)
11. Restore Task B FP context from memory
12. Verify all 32 FP registers match Task B values
13. Verify FCSR matches Task B value (0x55)

**Key Features**:
- Uses IEEE 754 single-precision values for simplicity
- Verification by FSW→LW comparison (bit-exact matching)
- Tests all 32 FP registers (complete FP context)
- Tests FCSR preservation (rounding mode, exception flags)

**Files Created**:
- `tests/asm/test_context_switch_fp_state.s` (718 lines)

### Test 2: test_context_switch_csr_state.s

**Purpose**: Verify supervisor CSR state isolation between tasks

**Test Flow**:
1. Setup Task A CSR values:
   - SEPC = 0x80001000
   - SSTATUS = 0x122 (SPP=1, SPIE=1, SIE=0)
   - SSCRATCH = 0xAAAAAAAA
   - SCAUSE = 0x8 (ECALL from U-mode)
   - STVAL = 0x12345678
2. Save Task A CSR context to memory
3. Setup Task B CSR values (different patterns)
4. Save Task B CSR context to memory
5. Restore Task A CSR context and verify
6. Restore Task B CSR context and verify
7. Round-robin switching test (A→B→A→B→A)

**Key Features**:
- Tests 5 critical supervisor CSRs
- Round-robin test ensures no cross-contamination
- Uses distinctive bit patterns for easy verification
- Simulates real OS context switching

**Files Created**:
- `tests/asm/test_context_switch_csr_state.s` (308 lines)

---

## Performance Analysis

### test_context_switch_fp_state.s Performance

```
Total cycles:        866
Total instructions:  531
CPI:                 1.631
Stall cycles:        344 (39.7%)
  Load-use stalls:   148 (FP loads from memory)
Flush cycles:        167 (19.3%)
  Branch flushes:    3
```

**Analysis**:
- Higher stall rate (39.7%) due to FP load-use dependencies
- FLW instructions have 1-cycle latency, causing frequent stalls
- 148 load-use stalls from 64 FLW instructions (2.3 stalls per load)
- This is expected and matches hardware behavior

### test_context_switch_csr_state.s Performance

```
Total cycles:        227
Total instructions:  139
CPI:                 1.633
Stall cycles:        48 (21.1%)
  Load-use stalls:   16 (CSR restore from memory)
Flush cycles:        35 (15.4%)
  Branch flushes:    3
```

**Analysis**:
- More efficient than FP test (fewer CSRs to save/restore)
- Load-use stalls from LW→CSRW sequences
- Similar CPI to FP test despite different workloads
- Round-robin test adds minimal overhead

---

## Testing Pattern Analysis

All three context switch tests (GPR, FP, CSR) follow the same pattern:

1. **Setup Task A state** - Load distinctive values
2. **Save Task A context** - Store to memory
3. **Setup Task B state** - Load different values
4. **Save Task B context** - Store to memory
5. **Restore Task A** - Load from memory
6. **Verify Task A** - Compare against expected values
7. **Restore Task B** - Load from memory
8. **Verify Task B** - Compare against expected values

This pattern:
- ✅ Tests save/restore mechanisms
- ✅ Tests isolation between tasks
- ✅ Tests round-trip correctness
- ✅ Detects cross-contamination bugs

---

## Code Quality

### test_context_switch_fp_state.s
- **Lines**: 718
- **Comments**: Extensive (test flow, stage descriptions)
- **Structure**: Clear sections for each test stage
- **Data**: IEEE 754 single-precision constants
- **Verification**: Bit-exact comparison for all 32 FP registers

### test_context_switch_csr_state.s
- **Lines**: 308
- **Comments**: Comprehensive CSR descriptions
- **Structure**: Follows GPR test pattern
- **Data**: Distinctive bit patterns for CSRs
- **Verification**: Exact value matching for all CSRs
- **Bonus**: Round-robin switching test

---

## Lessons Learned

1. **FP Context Size**: 132 bytes (32 regs × 4 bytes + FCSR)
   - Significant memory overhead per task
   - OS must save/restore on every context switch

2. **CSR Context Size**: 20 bytes (5 CSRs × 4 bytes)
   - Much smaller than FP context
   - Critical for trap handling and privilege management

3. **Load-Use Stalls**: FP loads cause more stalls
   - Software can mitigate by interleaving save/restore
   - Hardware could add FP load bypassing

4. **Test Pattern Reusability**: Same pattern works for:
   - GPRs (Session 120)
   - FPRs (Session 121)
   - CSRs (Session 121)
   - Could extend to: vector registers, custom CSRs, etc.

---

## Files Created/Modified

### New Files (2)
```
tests/asm/test_context_switch_fp_state.s   (718 lines)
tests/asm/test_context_switch_csr_state.s  (308 lines)
docs/SESSION_121_WEEK2_CONTEXT_SWITCH_TESTS.md
```

**Total New Code**: 1,026 lines

### Modified Files
- None (no RTL changes required)

---

## Next Steps

### Immediate (Session 122)
Continue Phase 4 Week 2 tests - remaining 6 tests:

**Option 1: Page Fault Tests (3 tests, complex)**
- test_page_fault_invalid_recover (verify existing)
- test_page_fault_load_store_fetch
- test_page_fault_delegation

**Option 2: Permission Tests (2 tests, medium)**
- test_pte_permission_rwx
- test_pte_permission_user_supervisor

**Option 3: Syscall Test (1 test, medium)**
- test_syscall_user_memory_access (requires SUM bit)

**Recommendation**: Start with Option 2 (permission tests) since:
- Builds on existing SUM/MXR knowledge (Week 1)
- Medium complexity (achievable in 1 session)
- Unblocks other tests

### Long-term (Phase 4)
- Complete Week 2 (6 more tests)
- Week 3: Advanced features (16 tests)
- Week 4: Nice-to-have features (7 tests)
- Target: v1.1-xv6-ready milestone

---

## Statistics

### Session Metrics
- **Duration**: ~2 hours
- **Tests Implemented**: 2
- **Lines Written**: 1,026
- **Tests Passing**: 2/2 (100%)
- **Regressions**: 0

### Cumulative Progress
- **Phase 4 Week 1**: 9/9 complete (100%) ✅
- **Phase 4 Week 2**: 5/11 complete (45%) 🔄
- **Total Phase 4**: 14/20 complete (70%)

### Test Breakdown
| Category | Week 2 Status |
|----------|---------------|
| Syscalls | 2/3 complete (67%) |
| Context Switching | 3/3 complete (100%) ✅ |
| Page Faults | 0/3 complete (0%) |
| Permissions | 0/2 complete (0%) |

---

## Conclusion

✅ **Session 121 SUCCESSFUL**

Both FP and CSR context switch tests implemented and passing. The context switch test suite is now complete (GPR, FP, CSR), validating that RV1 can correctly preserve task state across switches - a fundamental requirement for multitasking operating systems.

**Week 2 Progress**: 45% complete (5/11 tests)
**Next Target**: Permission violation tests (2 tests) or page fault tests (3 tests)

The core is stable and ready for the next batch of Week 2 tests!
