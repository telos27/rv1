# Session 124: MMU Arbiter Livelock Discovery

**Date**: 2025-11-08
**Focus**: Debug test_syscall_user_memory_access build hang
**Status**: ⚠️ **CRITICAL ARCHITECTURAL ISSUE DISCOVERED** - Unified TLB arbiter livelock
**Impact**: Blocks Phase 4 Week 2 SUM test, requires I-TLB/D-TLB separation

---

## Executive Summary

### Initial Goal
Debug build hang for `test_syscall_user_memory_access` (Phase 4 Week 2 SUM bit test)

### Issues Fixed
1. ✅ **Build hang** - Missing trap handler definitions
2. ✅ **Page table bug** - L2 table misalignment (not page-aligned)

### Critical Discovery
⚠️ **Unified TLB arbiter causes livelock** when IF and EX stages simultaneously need MMU
- Affects tests with 2-level page tables and non-identity mapping
- Existing tests pass because they use identity mapping or megapages
- **Requires separate I-TLB and D-TLB** (industry standard architecture)

### Results
- ✅ Zero regressions (14/14 quick tests pass)
- ✅ Test infrastructure ready
- ⚠️ test_syscall_user_memory_access blocked pending I-TLB/D-TLB implementation
- Current: **5/11 Phase 4 Week 2 tests complete**

---

## Problem Analysis

### Initial Symptom: Build Hang

**Command**:
```bash
make test-one TEST=test_syscall_user_memory_access
```

**Behavior**: Build process hung indefinitely

**Investigation**:
```bash
timeout 10 bash -x tools/run_test_by_name.sh test_syscall_user_memory_access --timeout 5
```

**Discovery**: Build hung in `asm_to_hex.sh` during linking phase

---

## Fix #1: Missing Trap Handlers

### Root Cause
Test used `ENTER_SMODE_M` macro which references `m_trap_handler` and `s_trap_handler`, but these symbols were undefined.

**Linker Error**:
```
riscv64-unknown-elf-ld: (.text+0x0): undefined reference to `m_trap_handler'
riscv64-unknown-elf-ld: (.text+0xc): undefined reference to `s_trap_handler'
```

### Solution
Added trap handler definitions at end of test (lines 259-269):

```assembly
###############################################################################
# Trap handlers
###############################################################################

m_trap_handler:
    # M-mode trap is unexpected (we delegated exceptions to S-mode)
    TEST_FAIL

s_trap_handler:
    # S-mode trap is unexpected for this test
    # (We're not testing fault cases, only successful SUM accesses)
    csrr    a0, scause
    csrr    a1, sepc
    csrr    a2, stval
    TEST_FAIL
```

**Result**: ✅ Test now builds successfully

---

## Fix #2: Page Table Alignment Bug

### Root Cause
L2 page table base address was `0x80002400` (not page-aligned).

**The Problem**:
```assembly
li      t4, 0x80002400          # L2 page table base
li      t1, 0x80002400
srli    t1, t1, 12              # PPN = 0x80002
slli    t1, t1, 10              # Shift to PPN field
```

**PPN Calculation**:
- `0x80002400 >> 12 = 0x80002` (bits [31:12])
- MMU reconstructs: `0x80002 << 12 = 0x80002000` (NOT 0x80002400!)
- **Lost lower 12 bits!**

**Why PTW Failed**:
```
MMU: PTW level 1 - issuing memory request addr=0x80002200  # L1 PTE
[DBG] PTW got response: data=0x20000801, V=1, R=0, W=0, X=0  # Points to L2 at PPN=0x80002
MMU: PTW level 0 - issuing memory request addr=0x80002000   # L2 base (not 0x80002400!)
[DBG] PTW got response: data=0x00000000, V=0, R=0, W=0, X=0  # EMPTY!
[DBG] PTW FAULT: Invalid PTE (V=0)
```

### Solution
Changed L2 base to page-aligned address:

```assembly
# Before (WRONG):
li      t4, 0x80002400          # Not page-aligned!

# After (CORRECT):
li      t4, 0x80003000          # Page-aligned (lower 12 bits = 0)
```

**Result**: ✅ Page table walk succeeds, TLB populated correctly

---

## Critical Discovery: MMU Arbiter Livelock

### Symptom After Fixes
Test built and ran, but **hung at runtime** with 99.9% pipeline stalls:

```
WARNING: Timeout reached (50000 cycles)
Final PC: 0x800000e8
Last instruction: 0x12c00313  (li t1,300)

Total cycles:        49999
Stall cycles:        49939 (99.9%)  ← PIPELINE BLOCKED!
x29 (t4)   = 0x00000004          ← Stage 4
```

**Stage 4 Code** (line 106):
```assembly
sw      t1, 0(t0)  # Store to VA 0x20000000 (U=1 page)
```

### MMU Debug Output (Infinite Loop)
```
MMU: Translation mode, VA=0x800000e8 (fetch=1 store=0), TLB hit=1
MMU: Translation mode, VA=0x20000000 (fetch=0 store=1), TLB hit=1
MMU: Translation mode, VA=0x800000e8 (fetch=1 store=0), TLB hit=1
MMU: Translation mode, VA=0x20000000 (fetch=0 store=1), TLB hit=1
[...repeats forever...]
```

**Pattern**: Alternating IF/EX MMU requests, but store never completes!

---

## Root Cause Analysis: Session 119 Round-Robin Arbiter

### Current Arbiter Logic
From `rv32i_core_pipelined.v:2629-2639`:

```verilog
always @(posedge clk) begin
  if (!reset_n) begin
    mmu_grant_to_ex_r <= 1'b0;
  end else if (if_needs_translation && ex_needs_translation) begin
    // Both need MMU - toggle grant
    mmu_grant_to_ex_r <= !mmu_grant_to_ex_r;  ← TOGGLES EVERY CYCLE!
  end else begin
    mmu_grant_to_ex_r <= ex_needs_translation;
  end
end
```

### The Livelock Scenario

**Cycle 1**: EX has MMU grant
- EX translates VA `0x20000000` → PA `0x80010000`
- MMU asserts `ex_mmu_req_ready` (translation complete)
- Store needs to propagate through memory bus...

**Cycle 2**: Arbiter toggles to IF
- IF gets MMU grant, EX loses it
- Store **hasn't completed yet** (bus takes cycles)
- EX stage stalls because store incomplete

**Cycle 3**: Arbiter toggles to EX
- EX retries store, gets MMU translation again...
- But needs multiple cycles to complete

**Cycle 4+**: **LIVELOCK!**
- Arbiter keeps toggling
- EX never holds MMU long enough for store to complete
- Pipeline stuck at 99.9% stalls

### Why Existing Tests Pass

**test_vm_identity_basic**: Uses identity mapping (VA=PA)
- Even if translation fails occasionally, physical address is correct
- Memory operations complete

**test_sum_enabled**: Uses megapages (1-level translation)
- Faster translation, less contention
- Store completes before toggle

**test_syscall_user_memory_access**: Uses 2-level page tables + non-identity mapping
- Requires TWO memory reads for PTW
- Higher latency = more IF/EX contention
- **First test to trigger the livelock!**

---

## Attempted Fixes (All Failed)

### Attempt 1: Hold EX Grant for N Cycles
```verilog
reg [1:0] ex_grant_hold_cycles;

// Hold EX grant for 4 cycles
if (mmu_grant_to_ex_r) begin
  if (ex_grant_hold_cycles > 0) begin
    ex_grant_hold_cycles <= ex_grant_hold_cycles - 1;
  end else begin
    mmu_grant_to_ex_r <= 1'b0;  // Toggle to IF
  end
end
```

**Problem**: Broke `test_vm_identity_basic` (caused timeouts)
- Fixed cycle count doesn't account for variable memory latency
- IF starved for too long, instruction fetch stalls

### Attempt 2: Track Memory Operation Completion
```verilog
reg ex_mem_op_in_progress;

// Set when EX gets translation
if (mmu_grant_to_ex_r && ex_mmu_req_ready) begin
  ex_mem_op_in_progress <= 1'b1;
end

// Clear when IDEX stage advances
else if (!ex_needs_translation || !idex_valid) begin
  ex_mem_op_in_progress <= 1'b0;
end
```

**Problem**: Cleared too early!
- `!idex_valid` asserts when IDEX advances to next instruction
- But memory operation still in MEM stage (EXMEM register)
- Arbiter toggles before bus operation completes

### Attempt 3: Simple Priority (IF Always Wins)
```verilog
mmu_grant_to_ex_r <= ex_needs_translation && !if_needs_translation;
```

**Problem**: Deadlock!
- IF always needs translation (constant instruction fetching)
- EX **never** gets MMU grant
- All stores/loads fail

---

## The Fundamental Issue: Unified TLB Architecture

### Current Design (Session 117/119)
```
        ┌─────────────────┐
  IF ──→│                 │
        │  Unified TLB    │──→ Translated Address
  EX ──→│  (16 entries)   │
        │                 │
        └─────────────────┘
             ↑
        Round-robin
        Arbiter
```

**Problems**:
1. **Structural Hazard**: IF and EX compete for same resource
2. **No Fair Scheduling**: Toggle-based arbiter doesn't account for operation completion
3. **Single Point of Contention**: One TLB bottleneck for all memory access

### Industry Standard: Dual TLB Architecture
```
  IF ──→ ┌─────────────┐
         │   I-TLB     │──→ Instruction PA
         └─────────────┘

  EX ──→ ┌─────────────┐
         │   D-TLB     │──→ Data PA
         └─────────────┘
```

**Benefits**:
1. ✅ **No Contention**: IF and EX access independent TLBs
2. ✅ **Parallel Operation**: Both can translate simultaneously
3. ✅ **Simpler Logic**: No arbiter needed
4. ✅ **Better Performance**: No pipeline stalls from TLB conflicts

---

## Proper Solution: Separate I-TLB and D-TLB

### Implementation Plan (Next Session)

**Changes Required**:
1. Split `mmu.v` into `itlb.v` (I-TLB) and `dtlb.v` (D-TLB)
2. Each TLB: 8-16 entries (configurable)
3. Shared PTW unit (page table walker)
4. PTW arbiter for when both I-TLB and D-TLB miss

**Estimated Effort**: 4-8 hours (1-2 sessions)

**Files to Modify**:
- `rtl/core/mmu/itlb.v` (new)
- `rtl/core/mmu/dtlb.v` (new)
- `rtl/core/mmu/ptw.v` (extract from existing mmu.v)
- `rtl/core/rv32i_core_pipelined.v` (connect dual TLBs)

**Testing Strategy**:
1. Verify zero regressions (14 quick tests)
2. Run Phase 4 Week 1 tests (9 tests)
3. Run test_syscall_user_memory_access (should now pass!)

---

## Files Modified (Session 124)

### Test File
- `tests/asm/test_syscall_user_memory_access.s` (+19 lines)
  - Line 53: Changed L2 base `0x80002400` → `0x80003000` (page-aligned)
  - Lines 259-269: Added trap handlers

### Core (No RTL changes - reverted arbiter experiments)
- `rtl/core/rv32i_core_pipelined.v` (no net changes)
  - Attempted arbiter fixes all reverted
  - Session 119 arbiter restored

---

## Validation Results

### Quick Regression
```bash
make test-quick
```

**Result**: ✅ **14/14 tests PASSED** (zero regressions)

### Phase 4 Week 2 Status
- ✅ test_syscall_args_passing
- ✅ test_context_switch_minimal
- ✅ test_syscall_multi_call
- ✅ test_context_switch_fp_state
- ✅ test_context_switch_csr_state
- ⚠️ test_syscall_user_memory_access (BLOCKED - needs I-TLB/D-TLB)
- ⏳ 5 more tests pending

**Current Progress**: **5/11 tests complete (45%)**

---

## Key Insights

### Why This Wasn't Caught Earlier
1. All Phase 4 tests use identity mapping or megapages
2. Session 122 data MMU fix only tested with identity VA=PA
3. First test with **2-level page tables + non-identity mapping**

### Architectural Lessons
1. **Unified TLB = Structural Hazard**: Industry uses separate I-TLB/D-TLB for good reason
2. **Round-Robin Inadequate**: Need completion-aware arbitration for shared resources
3. **Test Coverage**: Need tests with diverse addressing patterns (identity, megapage, 2-level, 3-level)

### Why Arbiter Fixes Failed
All attempted fixes tried to work around the fundamental structural hazard. The only proper solution is eliminating the hazard by providing separate resources.

**Analogy**: Trying to fix traffic jams on a 1-lane bridge by adjusting traffic light timing. Real solution: Build a 2-lane bridge!

---

## Next Session Plan

### Priority 1: Implement Dual TLB Architecture
1. Create separate I-TLB and D-TLB modules
2. Extract shared PTW logic
3. Update core pipeline connections
4. Validate with full test suite

### Priority 2: Complete Phase 4 Week 2 Tests
Once I-TLB/D-TLB implemented:
1. ✅ test_syscall_user_memory_access (should pass!)
2. Remaining 5 tests (page faults, permissions, etc.)

### Success Criteria
- Zero regressions (14/14 quick tests)
- Phase 4 Week 1: 9/9 passing
- Phase 4 Week 2: 11/11 passing (target)

---

## References

### Related Sessions
- **Session 117**: Instruction fetch MMU implementation (created unified TLB)
- **Session 119**: Round-robin arbiter (identified as interim solution)
- **Session 122**: Data MMU translation bug fix
- **Session 124**: Discovered unified TLB limitation (this session)

### Industry Standards
- RISC-V privileged spec (separate I-TLB/D-TLB common practice)
- ARM Cortex-A series: Separate L1 I-TLB/D-TLB, shared L2 TLB
- Intel x86: Separate instruction and data TLBs at all cache levels

### Test Files
- `tests/asm/test_syscall_user_memory_access.s` (270 lines, Phase 4 Week 2)
- `tests/asm/test_vm_identity_basic.s` (megapage, passes)
- `tests/asm/test_sum_enabled.s` (megapage, passes)

---

## Conclusion

Session 124 successfully resolved the immediate build infrastructure issues (trap handlers, page alignment) but uncovered a **critical architectural limitation** in the unified TLB design. This discovery is actually valuable - it identifies exactly why industry CPUs use separate I-TLB and D-TLB.

The path forward is clear: implement dual TLB architecture (standard practice) to eliminate the structural hazard. This will unblock not just test_syscall_user_memory_access, but any future tests with complex virtual memory usage.

**Status**: Ready for Session 125 - Dual TLB implementation
