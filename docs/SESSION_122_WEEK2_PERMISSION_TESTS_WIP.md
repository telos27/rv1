# Session 122: Phase 4 Week 2 - Permission Violation Tests (Work in Progress)

**Date**: 2025-11-07
**Status**: 🔄 Work in Progress - Test implementation started but not complete
**Focus**: Permission violation tests for OS security validation

## Session Overview

Started implementing Phase 4 Week 2 permission violation tests to validate privilege isolation. These tests verify that U-mode cannot access kernel pages (U=0) and S-mode cannot access user pages without SUM=1.

**Target Tests**:
1. `test_user_mode_kernel_access.s` - U-mode accessing kernel memory (should fault)
2. `test_kernel_mode_user_write.s` - S-mode writing user pages without SUM (should fault)

## Work Completed

### Test Files Created
1. **`test_user_mode_kernel_access.s`** (304 lines)
   - Tests U-mode load/store page faults on kernel pages (U=0)
   - Includes M→S→U mode transitions
   - Page table setup for kernel and user pages
   - Fault recovery and verification

2. **`test_user_mode_kernel_access_simple.s`** (217 lines)
   - Simplified version for debugging
   - Single load fault test case
   - Uses separate U=1 page for user code execution

### Key Learnings

#### 1. Mode Transition Complexity
Tests require careful handling of privilege mode transitions:
- Start in M-mode
- Enter S-mode via MRET (to enable paging with satp)
- Enter U-mode via SRET (to test permission violations)
- Return to S-mode via trap handler

#### 2. Page Table Setup Challenges
Mixed U/S-mode execution requires complex page table setup:
```
VA 0x80000000 (Code/Data): U=0 (S-mode accessible, kernel megapage)
VA 0x10000000 (Kernel page): U=0 (S-mode only - test target)
VA 0x30000000 (User code): U=1 (U-mode executable page)
```

**Issue**: After enabling paging in S-mode, if code region is marked U=1, S-mode with SUM=0 cannot execute. If marked U=0, U-mode cannot execute. Solution requires separate code pages for S-mode and U-mode.

#### 3. Test Infrastructure Pattern
Discovered existing test macro library that simplifies these tests:
- **`tests/asm/include/priv_test_macros.s`** - Comprehensive privilege test macros
- Provides `ENTER_UMODE_M`, `ENTER_SMODE_M`, `ENTER_UMODE_S` macros
- Used successfully by passing tests like `test_sum_disabled`
- Handles mstatus/sstatus bit manipulation correctly

#### 4. Permission Checking Verification
Reviewed MMU permission checking logic (`rtl/core/mmu.v:214-260`):
```verilog
// User mode check (lines 237-240)
else if (priv_mode == 2'b00) begin  // User mode
    if (!pte_flags[PTE_U]) begin
        check_permission = 0;  // User accessing supervisor page
    end
end
```
✅ Logic is correct - U-mode cannot access U=0 pages

## Issues Encountered

### Test Execution Failure
Both test versions fail at same point (415 cycles, 209 instructions):
- Likely failing during page table setup or mode transition
- Not reaching the actual permission violation test code
- Suggests trap/exception during initialization

**Debug Output**:
```
[PC_UPDATE] MRET: pc_current=0x80000032 -> pc_next=0x8000002a (mepc)
[415] TEST MARKER WRITE DETECTED at address 0x80002100
Value written: 0x00000000 (gp register)  // FAIL
```

### Root Cause Analysis
1. **Page table access after enabling paging**: S-mode code tries to execute from mapped region, but permission mismatch
2. **User code execution**: Need separate U=1 executable page for user code
3. **Trap handler complexity**: Must manage SPP correctly to return to right mode

## Test Architecture (Planned)

### Test Strategy
```
1. M-mode: Setup and enter S-mode
2. S-mode: Setup page tables (before enabling paging)
   - Map code region (U=0 for S-mode execution)
   - Map kernel data page (U=0, target for test)
   - Map user code page (U=1, executable)
   - Map user data page (U=1, for valid access test)
3. S-mode: Enable paging (csrw satp)
4. S-mode: Copy user code to U=1 page
5. S-mode: Enter U-mode
6. U-mode: Attempt kernel page access → expect page fault
7. Trap handler: Verify fault, return to S-mode
8. S-mode: Verify fault occurred, test pass
```

### Page Table Layout
```
L0 Entry 512: VA 0x80000000 → PA 0x80000000 (megapage, U=0, RWX)
L0 Entry  64: VA 0x10000000 → L1 kernel PT
  L1 Entry 0: → kernel_data page (U=0, RW)
L0 Entry 192: VA 0x30000000 → L1 user PT
  L1 Entry 0: → user_code_page (U=1, RWX)
  L1 Entry 1: → user_data_page (U=1, RW)
```

## Next Session Tasks

### High Priority
1. **Rewrite test using `priv_test_macros.s`**
   - Use `ENTER_SMODE_M` and `ENTER_UMODE_S` macros
   - Follow pattern from `test_sum_disabled.s`
   - Simplify mode transitions

2. **Debug page table setup**
   - Add debug output for MMU operations
   - Verify page table entries are correct
   - Check if paging enablement causes immediate fault

3. **Simplify initial test**
   - Start with absolute minimal test case
   - Just U-mode trying to read one kernel page
   - Add complexity incrementally

### Alternative Approach
Consider using RISC-V official privilege test patterns if available, or create a minimal reproducer that:
- Stays in S-mode for most of test
- Only briefly enters U-mode for single instruction
- Uses identity mapping where possible

## References

### Related Files
- `rtl/core/mmu.v:214-260` - Permission checking function
- `tests/asm/include/priv_test_macros.s` - Test macro library
- `tests/asm/test_sum_disabled.s` - Working example of U-mode VM test
- `tests/asm/test_syscall_args_passing.s` - Working U-mode syscall test

### Documentation
- RISC-V Privileged Spec Section 3.1.6.3 - Page-Based Virtual Memory
- RISC-V Privileged Spec Section 4.3 - Supervisor Memory-Management

## Statistics

**Files Created**: 2 test files (521 lines total)
**Test Status**: 0/2 passing (both WIP)
**Lines of Test Code**: 521 lines
**Session Duration**: ~2 hours
**Blocker**: Page table/mode transition complexity

## Notes for Next Session

1. The macro library exists and is battle-tested - use it!
2. Start even simpler - maybe just S-mode accessing U=1 page without SUM
3. Consider generating waveforms for detailed debugging
4. May need to add debug output to MMU to trace page table walks
5. Verify that working tests (test_sum_*) use similar page table patterns

**Key Insight**: Permission violation tests are more complex than context switch tests because they require:
- Multi-level page tables with mixed U-bit settings
- Careful mode transition orchestration
- Separate executable pages for different privilege levels
- Precise trap handler SPP management

This is expected complexity for OS security testing!
