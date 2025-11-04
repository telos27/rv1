# Phase 4 Prep: Comprehensive Test Implementation Plan

**Date**: November 4, 2025
**Objective**: Implement all recommended tests before xv6-riscv integration
**Estimated Duration**: 3-4 weeks
**Total Tests to Add**: ~50 new tests

---

## Executive Summary

Before proceeding with Phase 4 (xv6-riscv), we will implement a comprehensive test suite covering all gaps identified in the OS readiness analysis. This ensures the hardware is fully validated and ready for complex OS workloads.

**Current Status**: 187/187 official tests passing, 231 custom tests
**Target Status**: 187/187 official + 280+ custom tests (all categories covered)

---

## Test Implementation Roadmap

### Week 1: Critical Tests (Priority 1A) - MUST HAVE

**Goal**: Address immediate blockers for xv6

#### 1.1 SUM/MXR Permission Bits (4 tests) 🚨 CRITICAL

**Why Critical**: xv6 kernel MUST access user stacks during syscalls

**Tests to Implement**:

1. **test_sum_disabled.s**
   - Set MSTATUS.SUM = 0
   - Enter S-mode
   - Try to read U-mode accessible memory
   - **Expected**: Load access fault (exception code 5)
   - **Lines**: ~80

2. **test_sum_enabled.s**
   - Set MSTATUS.SUM = 1
   - Enter S-mode
   - Read/write U-mode accessible memory
   - **Expected**: Success, data matches
   - **Lines**: ~90

3. **test_mxr_read_execute.s**
   - Set MSTATUS.MXR = 1
   - Page with X=1, R=0
   - Try load from executable page
   - **Expected**: Success when MXR=1, fault when MXR=0
   - **Lines**: ~100

4. **test_sum_mxr_combined.s**
   - Test all 4 combinations of SUM/MXR
   - Multiple page permission scenarios
   - S-mode and U-mode variations
   - **Expected**: Correct behavior for each combination
   - **Lines**: ~120

**Total**: ~390 lines, 3-4 days

#### 1.2 Non-Identity Page Table Walking (3 tests)

**Why Critical**: Current tests only use identity mapping (VA == PA)

**Tests to Implement**:

5. **test_vm_non_identity_simple.s**
   - Map VA 0x10000000 → PA 0x80010000
   - Write data through VA
   - Read back and verify
   - **Expected**: Correct translation
   - **Lines**: ~150

6. **test_vm_multi_level_walk.s**
   - Create 2-level page table for Sv32
   - Multiple VPN[1] entries (different megapages)
   - Multiple VPN[0] entries per megapage
   - Test loads from each region
   - **Expected**: All translations work correctly
   - **Lines**: ~200

7. **test_vm_sparse_mapping.s**
   - Map non-contiguous VA regions
   - VA: 0x1000 → PA: 0x80003000
   - VA: 0x5000 → PA: 0x80007000
   - Access both, verify unmapped causes fault
   - **Expected**: Mapped pages work, unmapped fault
   - **Lines**: ~180

**Total**: ~530 lines, 4-5 days

#### 1.3 TLB Verification (3 tests)

**Why Critical**: TLB bugs are subtle and hard to debug in OS context

**Tests to Implement**:

8. **test_tlb_basic_hit_miss.s**
   - Access page → TLB loads
   - Change PTE permissions
   - Access again (should use stale TLB → wrong behavior)
   - SFENCE.VMA
   - Access again (should work correctly)
   - **Expected**: Demonstrates TLB caching behavior
   - **Lines**: ~120

9. **test_tlb_replacement.s**
   - Fill all 16 TLB entries
   - Access 17th page (causes replacement)
   - Verify oldest entry evicted
   - **Expected**: LRU or random replacement works
   - **Lines**: ~200

10. **test_sfence_effectiveness.s**
    - Setup translation
    - Modify PTE (permissions, PPN)
    - Test WITHOUT sfence (should see stale)
    - Test WITH sfence (should see new)
    - **Expected**: SFENCE forces TLB update
    - **Lines**: ~140

**Total**: ~460 lines, 3-4 days

**Week 1 Total**: 11 tests, ~1380 lines, 10-13 days actual time

---

### Week 2: Critical Tests (Priority 1B) - MUST HAVE

#### 2.1 Page Fault Recovery (3 tests)

**Tests to Implement**:

11. **test_page_fault_invalid_recover.s**
    - Access invalid page (V=0)
    - Trap to handler
    - Fix PTE (set V=1)
    - SFENCE.VMA
    - Retry instruction (SEPC/MEPC)
    - **Expected**: Second attempt succeeds
    - **Lines**: ~150

12. **test_page_fault_load_store_fetch.s**
    - Three separate handlers for:
      - Load page fault (code 13)
      - Store page fault (code 15)
      - Instruction page fault (code 12)
    - Verify correct exception code
    - Verify STVAL contains faulting address
    - **Expected**: All three fault types distinguishable
    - **Lines**: ~180

13. **test_page_fault_delegation.s**
    - Set MEDELEG to delegate page faults to S-mode
    - Trigger page fault from U-mode
    - S-mode handler receives it (not M-mode)
    - Fix and return to U-mode
    - **Expected**: S-mode handles page fault
    - **Lines**: ~160

**Total**: ~490 lines, 3-4 days

#### 2.2 Complete Syscall Flow (3 tests)

**Tests to Implement**:

14. **test_syscall_args_passing.s**
    - U-mode prepares args in a0-a7
    - ECALL to S-mode
    - S-mode handler reads a0-a7
    - Handler writes result to a0
    - SRET back to U-mode
    - U-mode verifies a0 result
    - **Expected**: Arguments preserved, result returned
    - **Lines**: ~130

15. **test_syscall_user_memory_access.s**
    - U-mode passes pointer to buffer in a0
    - S-mode handler sets SUM=1
    - S-mode reads from user buffer
    - S-mode writes result back
    - Sets SUM=0 before SRET
    - **Expected**: Kernel can access user memory with SUM
    - **Lines**: ~170

16. **test_syscall_multi_call.s**
    - Multiple syscalls in sequence
    - Different syscall numbers (a7)
    - Nested calls (syscall from within handler? edge case)
    - **Expected**: All calls work independently
    - **Lines**: ~200

**Total**: ~500 lines, 3-4 days

#### 2.3 Context Switch Validation (3 tests)

**Tests to Implement**:

17. **test_context_switch_minimal.s**
    - Setup "Task A" state (all GPRs, PC, SP)
    - Save Task A context to memory
    - Load "Task B" context
    - Execute Task B
    - Switch back to Task A
    - Verify all Task A registers restored
    - **Expected**: Perfect register preservation
    - **Lines**: ~180

18. **test_context_switch_fp_state.s**
    - Same as above, but include FP registers
    - Save/restore F0-F31
    - Save/restore FCSR
    - Verify FP state isolation
    - **Expected**: FP state preserved across switches
    - **Lines**: ~200

19. **test_context_switch_csr_state.s**
    - Save/restore CSRs (SEPC, SSTATUS, SSCRATCH)
    - Multiple task contexts
    - Round-robin switching
    - **Expected**: CSR state isolated per task
    - **Lines**: ~190

**Total**: ~570 lines, 4-5 days

#### 2.4 Permission Violation Tests (2 tests)

**Tests to Implement**:

20. **test_pte_permission_rwx.s**
    - Create pages with different R/W/X bits
    - Test read from R=0 page (should fault)
    - Test write to W=0 page (should fault)
    - Test execute from X=0 page (should fault)
    - Verify exception codes
    - **Expected**: Permissions enforced correctly
    - **Lines**: ~150

21. **test_pte_permission_user_supervisor.s**
    - Create U=1 and U=0 pages
    - S-mode accesses U=1 with SUM=0 (should fault)
    - S-mode accesses U=1 with SUM=1 (should work)
    - U-mode accesses U=0 page (should fault)
    - **Expected**: User bit enforced
    - **Lines**: ~160

**Total**: ~310 lines, 2-3 days

**Week 2 Total**: 11 tests, ~1870 lines, 12-16 days actual time

---

### Week 3: Important Tests (Priority 2) - SHOULD HAVE

#### 3.1 SFENCE.VMA Variants (2 tests)

**Tests to Implement**:

22. **test_sfence_vma_rs1.s**
    - Flush specific VA (RS1 ≠ 0, RS2 = 0)
    - Verify only that VA invalidated
    - Other TLB entries remain
    - **Expected**: Selective invalidation works
    - **Lines**: ~140

23. **test_sfence_vma_asid.s**
    - Multiple ASIDs in SATP
    - Flush specific ASID (RS1 = 0, RS2 ≠ 0)
    - Verify only that ASID invalidated
    - **Expected**: ASID-selective flush works
    - **Lines**: ~160

**Total**: ~300 lines, 2-3 days

#### 3.2 ASID Management (2 tests)

**Tests to Implement**:

24. **test_asid_isolation.s**
    - Create two page tables (ASID 1, ASID 2)
    - Same VA in both, different PA
    - Switch ASID via SATP
    - Verify translation matches current ASID
    - **Expected**: ASIDs prevent TLB cross-talk
    - **Lines**: ~180

25. **test_asid_context_switch.s**
    - Simulate process switch
    - Save SATP (including ASID)
    - Load new SATP with different ASID
    - Verify TLB uses new ASID
    - **Expected**: ASID change effective
    - **Lines**: ~150

**Total**: ~330 lines, 2-3 days

#### 3.3 Advanced Trap Nesting (3 tests)

**Tests to Implement**:

26. **test_nested_trap_u_s_m.s**
    - Start in U-mode
    - Trigger exception → S-mode
    - S-mode triggers exception → M-mode
    - M-mode handles, returns to S-mode
    - S-mode handles, returns to U-mode
    - Verify EPC/STATUS stack correct
    - **Expected**: Clean nesting/unwinding
    - **Lines**: ~200

27. **test_interrupt_during_exception.s**
    - Start exception handling
    - Timer interrupt fires during handler
    - Verify interrupt preempts exception
    - Exception resumes after interrupt
    - **Expected**: Interrupt priority works
    - **Lines**: ~180

28. **test_trap_delegation_chain.s**
    - Configure MEDELEG/MIDELEG
    - U-mode → S-mode (delegated)
    - S-mode → M-mode (not delegated)
    - Verify correct delegation behavior
    - **Expected**: Delegation works as configured
    - **Lines**: ~170

**Total**: ~550 lines, 3-4 days

#### 3.4 Supervisor Mode Features (2 tests)

**Tests to Implement**:

29. **test_sstatus_vs_mstatus.s**
    - Write SSTATUS fields
    - Verify MSTATUS updated
    - Write SSTATUS-restricted MSTATUS fields
    - Verify SSTATUS can't access them
    - **Expected**: SSTATUS subset of MSTATUS
    - **Lines**: ~130

30. **test_smode_interrupt_masking.s**
    - Configure SEDELEG/SIDELEG
    - Test SIE/SPIE bits
    - Verify S-mode interrupt masking independent
    - **Expected**: S-mode interrupt control works
    - **Lines**: ~150

**Total**: ~280 lines, 2 days

#### 3.5 Address Translation Edge Cases (3 tests)

**Tests to Implement**:

31. **test_page_boundary_crossing.s**
    - Load/store crossing page boundary
    - First page valid, second invalid
    - Verify fault on second page
    - **Expected**: Correct fault address in STVAL
    - **Lines**: ~140

32. **test_misaligned_with_paging.s**
    - Misaligned access (e.g., LW at addr+1)
    - With paging enabled
    - Verify misaligned exception vs page fault priority
    - **Expected**: Correct exception priority
    - **Lines**: ~150

33. **test_large_address_ranges.s**
    - Map high VAs (near 2GB for RV32)
    - Map sparse regions
    - Verify no overflow in address calculation
    - **Expected**: Large addresses work correctly
    - **Lines**: ~130

**Total**: ~420 lines, 3 days

#### 3.6 Load/Store with Paging (2 tests)

**Tests to Implement**:

34. **test_byte_access_paging.s**
    - LB/LH/LW/LD with address translation
    - Verify sign-extension works
    - Test all byte alignments
    - **Expected**: Load behavior correct with MMU
    - **Lines**: ~120

35. **test_store_byte_paging.s**
    - SB/SH/SW/SD with address translation
    - Verify partial writes
    - Read back with different sizes
    - **Expected**: Store behavior correct with MMU
    - **Lines**: ~130

**Total**: ~250 lines, 2 days

#### 3.7 CSR Consistency (2 tests)

**Tests to Implement**:

36. **test_csr_nested_traps.s**
    - U→S trap: SEPC, SCAUSE, STVAL set
    - S→M trap: MEPC, MCAUSE, MTVAL set
    - Verify S-mode CSRs preserved
    - Return path preserves all
    - **Expected**: No CSR corruption
    - **Lines**: ~160

37. **test_csr_shadow_updates.s**
    - Write SSTATUS.SIE
    - Verify MSTATUS.SIE updated
    - Write MSTATUS.SIE
    - Verify SSTATUS.SIE reflects it
    - **Expected**: Shadow CSRs stay coherent
    - **Lines**: ~120

**Total**: ~280 lines, 2 days

**Week 3 Total**: 16 tests, ~2410 lines, 16-19 days actual time

---

### Week 4: Advanced Tests (Priority 3) - NICE TO HAVE

#### 4.1 Superpage Support (2 tests)

**Tests to Implement**:

38. **test_superpage_megapage.s**
    - Create megapage (PTE at level 1, leaf=1)
    - Access addresses across megapage range
    - Verify single TLB entry covers 4MB (Sv32)
    - **Expected**: Superpage works correctly
    - **Lines**: ~150

39. **test_superpage_mixed.s**
    - Mix superpages and regular pages
    - Verify correct translation for each
    - **Expected**: Can coexist properly
    - **Lines**: ~140

**Total**: ~290 lines, 2 days

#### 4.2 Exception Priority (2 tests)

**Tests to Implement**:

40. **test_exception_priority_order.s**
    - Trigger multiple exceptions simultaneously
    - Instruction access fault + illegal instruction
    - Verify correct priority per spec
    - **Expected**: Matches RISC-V priority table
    - **Lines**: ~160

41. **test_fault_during_fault.s**
    - Page fault handler itself faults
    - Verify double-fault behavior
    - **Expected**: No infinite loop, M-mode catches
    - **Lines**: ~150

**Total**: ~310 lines, 2-3 days

#### 4.3 RV64-Specific VM Tests (3 tests)

**Tests to Implement**:

42. **test_sv39_three_level.s**
    - Create 3-level page table (Sv39)
    - Test all VPN[2], VPN[1], VPN[0] combinations
    - Verify 39-bit VA support
    - **Expected**: RV64 Sv39 works correctly
    - **Lines**: ~220

43. **test_rv64_gigapage.s**
    - Create gigapage (PTE at level 2, leaf=1)
    - Access across 1GB range
    - **Expected**: Gigapage translation works
    - **Lines**: ~160

44. **test_rv64_canonical_addresses.s**
    - Test VA bits [63:39] must match bit 38
    - Verify non-canonical causes fault
    - **Expected**: Canonical address check works
    - **Lines**: ~130

**Total**: ~510 lines, 3-4 days

#### 4.4 Multi-Hart Tests (if applicable) (2 tests)

**Status**: Skip for now (single-hart design)

**Total**: 0 tests for now

**Week 4 Total**: 7 tests, ~1110 lines, 7-9 days actual time

---

## Summary Statistics

### Total Test Count

| Priority | Category | Tests | Est. Lines | Est. Days |
|----------|----------|-------|------------|-----------|
| **P1A** | SUM/MXR, VM, TLB | 10 | 1,380 | 10-13 |
| **P1B** | Faults, Syscall, Context | 11 | 1,870 | 12-16 |
| **P2** | Advanced VM, Traps, Edge Cases | 16 | 2,410 | 16-19 |
| **P3** | Superpages, RV64, Priority | 7 | 1,110 | 7-9 |
| **TOTAL** | | **44** | **~6,770** | **45-57** |

**Realistic Timeline**: 3-4 weeks with focused effort

### Breakdown by Feature Area

| Feature | Tests | Critical? |
|---------|-------|-----------|
| Virtual Memory | 10 | ✅ Yes |
| Permission Bits (SUM/MXR) | 4 | ✅ Yes |
| Page Faults | 5 | ✅ Yes |
| TLB Management | 5 | ✅ Yes |
| System Calls | 3 | ✅ Yes |
| Context Switching | 3 | ✅ Yes |
| Trap Nesting | 4 | ⚠️ Important |
| ASID | 2 | ⚠️ Important |
| CSR Consistency | 2 | ⚠️ Important |
| Superpages | 2 | ℹ️ Nice-to-have |
| Exception Priority | 2 | ℹ️ Nice-to-have |
| RV64 Specific | 3 | ℹ️ Nice-to-have |

---

## Implementation Strategy

### Phase A: Foundation (Week 1) - Priority 1A Tests
**Focus**: Absolute blockers for OS functionality
- Start with SUM/MXR (most critical)
- Then non-identity VM (required for real OS)
- Then TLB verification (subtle bugs)

### Phase B: Integration (Week 2) - Priority 1B Tests
**Focus**: Complete OS paths
- Page fault recovery (OS needs this)
- Full syscall flow (core OS interface)
- Context switching (multitasking)
- Permission enforcement (security)

### Phase C: Robustness (Week 3) - Priority 2 Tests
**Focus**: Edge cases and advanced features
- SFENCE variants (efficiency)
- ASID management (performance)
- Complex trap scenarios (correctness)
- Edge cases in translation

### Phase D: Polish (Week 4) - Priority 3 Tests
**Focus**: Nice-to-have features
- Superpages (performance)
- Exception priority (spec compliance)
- RV64-specific features

---

## Testing Workflow

### For Each Test

1. **Design** (30 min - 1 hour)
   - Write test plan
   - Identify expected behavior
   - Plan data structures (page tables, etc.)

2. **Implement** (1-3 hours)
   - Write assembly (.s file)
   - Setup page tables / CSRs
   - Implement verification logic

3. **Debug** (30 min - 2 hours)
   - Run simulation
   - Check waveforms
   - Fix issues

4. **Document** (15 min)
   - Add comments
   - Update TEST_CATALOG.md
   - Note any findings

**Average**: 2-4 hours per test (simpler tests faster, complex tests slower)

### Daily Workflow

**Target**: 2-3 tests per day (on average)

**Morning**:
- Pick next test from plan
- Implement first test

**Afternoon**:
- Debug/finish first test
- Start second test

**Evening** (if energy):
- Finish second test, or start third

**Reality Check**: Some days you'll finish 4 tests, some days 0. Average 2-3.

---

## Success Criteria

### Per Test
- ✅ Test assembles without errors
- ✅ Test runs to completion
- ✅ Pass/fail detected correctly (x28 register)
- ✅ Test documented in catalog

### Per Week
- ✅ All priority tests for that week pass
- ✅ No regressions in existing tests
- ✅ Code reviewed for clarity

### Overall (End of 4 Weeks)
- ✅ All 44 tests implemented and passing
- ✅ Full regression passes (231 + 44 = 275 custom tests)
- ✅ Official tests still 100% (187/187)
- ✅ Documentation updated
- ✅ Ready to start xv6 integration

---

## Risk Mitigation

### Risk: Tests reveal hardware bugs
**Mitigation**: Fix bugs immediately, update design docs

### Risk: Test implementation takes longer than estimated
**Mitigation**:
- Focus on P1A and P1B first (3 weeks minimum)
- P2 and P3 can slip or be deferred
- Reassess after Week 2

### Risk: Test complexity spirals
**Mitigation**:
- Keep tests focused and simple
- Split complex tests into multiple simpler ones
- Don't over-engineer

### Risk: Debugging time explodes
**Mitigation**:
- Add debug output early
- Use waveforms effectively
- Ask for help if stuck > 1 day

---

## Deliverables

### End of Week 1
- [ ] 10 tests implemented (SUM/MXR, VM, TLB)
- [ ] Session document: PHASE_4_PREP_WEEK_1.md
- [ ] Updated TEST_CATALOG.md

### End of Week 2
- [ ] 11 more tests (Faults, Syscalls, Context)
- [ ] Session document: PHASE_4_PREP_WEEK_2.md
- [ ] Regression report (all tests passing)

### End of Week 3
- [ ] 16 more tests (Advanced features)
- [ ] Session document: PHASE_4_PREP_WEEK_3.md
- [ ] Test coverage report

### End of Week 4
- [ ] 7 final tests (P3)
- [ ] Final session document: PHASE_4_PREP_COMPLETE.md
- [ ] Git tag: v1.1-xv6-ready
- [ ] Ready to start Phase 4!

---

## Next Steps

1. **Review this plan** - Any adjustments needed?
2. **Start Week 1, Test 1** - test_sum_disabled.s
3. **Set up tracking** - Create todo list for Week 1
4. **Begin implementation** - Let's write the first test!

Ready to start? 🚀
