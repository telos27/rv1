# Session 102: Exception Timing Debug - test_vm_sum_read Investigation

**Date**: 2025-11-06
**Focus**: Debugging test_vm_sum_read failure - discovered pipeline exception timing issue

## Problem Statement

Test `test_vm_sum_read.s` fails at stage 5, appearing to show that S-mode can access U-pages without SUM=1. Initial investigation suggested a data memory initialization issue, but root cause is actually a pipeline exception timing bug.

## Investigation Timeline

### Initial Hypothesis (INCORRECT)
- Suspected Stage 1 failure (M-mode memory access)
- Thought test_data_user wasn't initialized in memory
- Investigated hex file format and memory loading

### Key Discovery 1: Test Actually Fails at Stage 5
- Register dump shows x29 (stage marker) = 1, but this is misleading
- Test actually progresses to stage 5 (S-mode accessing U-page)
- Stage 1 passes correctly - memory write/read works fine

### Key Discovery 2: MMU Works Correctly!
The MMU permission checking is functioning as designed:

**PTW Response for VA 0x00002000**:
```
data=0x200000d7, V=1, R=1, W=1, X=0, U=1
Permission check FAILS (S-mode accessing U-page with SUM=0)
PTW reports: req_ready=1, req_page_fault=1
```

The MMU correctly:
- Performs page table walk
- Finds PTE with U=1 (user page)
- Checks permissions (S-mode, SUM=0, U-page)
- Denies access and reports page fault

### Key Discovery 3: Pipeline Timing Bug

**The Problem**: When MMU reports page fault, pipeline continues executing before exception is taken.

**Expected Behavior**:
1. Load at PC 0x800000f4 causes page fault
2. Exception handler invoked immediately
3. No subsequent instructions execute

**Actual Behavior**:
1. Load at PC 0x800000f4 causes page fault
2. Jump at PC 0x800000f8 executes
3. PC advances to test_fail (0x80000244)
4. Exception detected too late

**Debug Trace**:
```
[DBG] PTW FAULT: Permission denied
[CORE] MMU reported page fault: vaddr=0x00002000
[CORE] EXMEM stage has page fault: vaddr=0x00002000, PC=0x80000248
```

PC=0x80000248 is INSIDE test_fail, several instructions after the faulting load!

## Root Cause Analysis

### The Bug: Exception Detection Latency

The pipeline has a 1-2 cycle latency between:
1. Instruction causes fault (EX stage)
2. Fault registered in pipeline (MEM stage)
3. Exception detected and trap taken

During this latency, subsequent instructions continue to execute:

**Cycle N**: Load enters EX, MMU starts PTW
- `mmu_busy=1` holds EXMEM register
- IF/ID continues fetching next instructions

**Cycles N+1 to N+3**: PTW in progress
- EX stage held
- Jump instruction waiting in ID stage

**Cycle N+4**: MMU completes with fault
- Sets `req_ready=1, req_page_fault=1`
- `mmu_busy` becomes 0 (mmu_req_ready=1)
- EXMEM hold released
- **Load advances to MEM, Jump enters EX**

**Cycle N+5**: Jump executes
- Page fault now in EXMEM stage
- But PC already changed to test_fail
- Exception detected too late

### Why This Happens

Current `mmu_busy` logic:
```verilog
assign mmu_busy = mmu_req_valid && !mmu_req_ready;
```

When MMU completes (ready=1), mmu_busy becomes 0, even if page_fault=1. This releases the pipeline hold immediately, allowing subsequent instructions to execute.

## The Real Test Status

**test_vm_sum_read is NOT broken** - it's correctly validating SUM permission checks!

The test expects:
1. S-mode load from U-page with SUM=0
2. Immediate page fault exception
3. Trap to S-mode handler at smode_after_first_fault

What happens:
1. S-mode load from U-page with SUM=0 ✓
2. MMU correctly reports page fault ✓
3. But jump to test_fail executes before trap ✗

## Potential Fixes

### Option 1: Extend mmu_busy for Faults
```verilog
// Keep EX stage held for one more cycle when page fault occurs
assign mmu_busy = (mmu_req_valid && !mmu_req_ready) ||
                  (mmu_req_ready && mmu_req_page_fault && !page_fault_handled);
```

### Option 2: Immediate Exception Detection
Detect page fault in EX stage instead of MEM stage:
- Check `mmu_req_page_fault` in EX stage
- Set exception flag immediately
- Flush IF/ID before next instruction enters

### Option 3: Exception Flush Timing
Ensure `trap_flush` prevents subsequent instructions from committing:
- When exception detected in MEM, flush all younger instructions
- Requires tracking instruction age or sequence numbers

## Files Modified (Debug Only)

### rtl/core/mmu.v
Added extensive debug output:
- PTW state transitions
- Permission check results
- Page fault causes

**These debug statements should be removed or made conditional before production.**

### rtl/core/rv32i_core_pipelined.v
Added page fault tracking:
```verilog
// Debug: Track page faults
always @(posedge clk) begin
  if (mmu_req_page_fault && mmu_req_ready)
    $display("[CORE] MMU reported page fault: vaddr=0x%h", mmu_req_fault_vaddr);
  if (exmem_page_fault && exmem_valid)
    $display("[CORE] EXMEM stage has page fault: vaddr=0x%h, PC=0x%h",
             exmem_fault_vaddr, exmem_pc);
end
```

**This debug block should be removed before production.**

## Test Progress Update

**Phase 4 Prep Status**: 7/44 tests (15.9%)
- **Week 1**: 7/10 tests (70%)
  - ✅ test_satp_reset (Session 95)
  - ✅ test_smode_entry_minimal (Session 95)
  - ✅ test_vm_sum_simple (Session 95)
  - ✅ test_sum_basic (Session 88)
  - ✅ test_mxr_basic (Session 89)
  - ✅ test_sum_mxr_csr (Session 89)
  - ✅ test_vm_identity_basic (Session 92)
  - ❌ test_vm_sum_read (THIS SESSION - pipeline timing issue, NOT MMU bug)
  - 📝 test_vm_identity_multi (pending)
  - 📝 test_vm_offset_mapping (pending)

## Next Session Tasks

1. **Choose and implement exception timing fix** (Option 1, 2, or 3 above)
2. **Verify test_vm_sum_read passes** after fix
3. **Test other VM tests** (test_vm_identity_multi, test_vm_non_identity_basic)
4. **Clean up debug output** from mmu.v and rv32i_core_pipelined.v

## Key Insights

### The Good News
- ✅ MMU permission checking works correctly
- ✅ SUM bit enforcement is functional
- ✅ Page table walks complete successfully
- ✅ Session 94 fix was correct and effective

### The Challenge
- Pipeline exception timing needs refinement
- Memory operations with faults don't prevent subsequent instruction execution
- This is a general issue affecting all memory exceptions, not just page faults

### Impact
This bug affects ANY memory instruction that can cause exceptions:
- Load/Store page faults
- Load/Store access faults
- Load/Store misalignment (though handled earlier)

The fix will benefit the entire exception handling pipeline, making the core more robust for OS workloads.

## References
- Session 94: MMU SUM permission bug fix
- Session 92: MMU megapage translation fix
- Session 90: MMU PTW handshake fix
- RISC-V Privileged Spec Section 3.1.15: Exception Handling
