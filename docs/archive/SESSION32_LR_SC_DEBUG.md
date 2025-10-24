# Session 32: LR/SC Debugging - Partial Fix

**Date**: 2025-10-13
**Status**: In Progress - 1 of 2 bugs fixed
**Files Modified**: `rtl/core/rv32i_core_pipelined.v`

## Executive Summary

Systematic debugging of LR/SC (Load-Reserved/Store-Conditional) test failures revealed **TWO critical bugs**:
1. ✅ **FIXED**: Spurious reservation invalidation bug
2. ⚠️ **UNFIXED**: Atomic instruction forwarding hazard bug

## Bug #1: Spurious Reservation Invalidation (FIXED ✅)

### The Problem
The reservation set by LR instructions was being immediately invalidated by store instructions that had already completed but whose signals persisted in the EXMEM pipeline register.

### Root Cause Analysis

**Timeline of the bug:**
1. SW (store word) instruction executes and enters MEM stage
2. LR instruction executes and sets reservation at address 0x01000000
3. **BUG**: SW instruction's `exmem_mem_write` signal still asserted
4. Reservation invalidation logic fires: `reservation_invalidate = exmem_mem_write && !exmem_is_atomic`
5. Reservation cleared immediately after being set
6. SC instruction fails because reservation is gone

**Debug trace showing the bug:**
```
[RESERVATION] LR at 0x01000000 (masked: 0x01000000)
[RESERVATION] Invalidated by write to 0x01000000          ← Bug!
[CORE] Reservation invalidate: PC=0x00000008, mem_wr=1, is_atomic=0, hold=0, valid=1, addr=0x01000000
[RESERVATION] SC at 0x01000000, reserved=0, match=1 -> FAIL
```

The invalidating instruction was at PC=0x08 (the SW that happened BEFORE the LR).

### The Fix

**File**: `rtl/core/rv32i_core_pipelined.v:1178-1192`

Added state tracking to only invalidate reservations when NEW store instructions enter MEM stage:

```verilog
// Track when EXMEM was held last cycle
reg hold_exmem_prev;
always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    hold_exmem_prev <= 1'b0;
  else
    hold_exmem_prev <= hold_exmem;
end

// Only invalidate on the FIRST cycle an instruction is in MEM stage
assign reservation_invalidate = exmem_mem_write && !exmem_is_atomic &&
                                !hold_exmem_prev && exmem_valid;
```

**Key insight**: By checking `!hold_exmem_prev`, we ensure invalidation only happens when:
- A NEW instruction just entered MEM (normal flow: `hold_exmem_prev=0`)
- OR an instruction was just released from hold (transition from `hold_exmem_prev=1` to `hold_exmem=0`)

This prevents stale pipeline values from triggering spurious invalidations.

### Verification

After the fix:
```
[RESERVATION] LR at 0x01000000 (masked: 0x01000000)
[RESERVATION] SC at 0x01000000, reserved=1, match=1 -> SUCCESS  ← Fixed!
[ATOMIC] SC @ 0x01000000 SUCCESS (wdata=0x0000002b)
```

The SC now succeeds and writes the correct value.

---

## Bug #2: Atomic Forwarding Hazard (UNFIXED ⚠️)

### The Problem
Despite SC succeeding, the test still fails because the BNEZ instruction reads stale data (0) instead of the SC result (also 0, but for different reasons - the branch shouldn't be evaluating against stale register file data).

### Symptoms

**Test program flow:**
```assembly
0x1c: sc.w    t3, t1, (a0)      # t3 = 0 on success, 1 on failure
0x20: bnez    t3, fail          # Branch to fail if t3 != 0
```

**Debug trace:**
```
[CORE] Atomic in EXMEM: PC=0x0000001c, is_atomic=1, result=0x00000000
[CORE] BNEZ in IDEX: PC=0x00000020, rs1(t3)=x28, rs1_data=0x00000000, id_forward_a=000
      exmem: rd=x28, reg_wr=1, valid=1, is_atomic=1
```

**Analysis:**
- SC in EXMEM has `rd=x28`, `reg_wr=1`, `result=0x00000000`
- BNEZ reads `rs1=x28` with `rs1_data=0x00000000`
- Forwarding signal: `id_forward_a=000` ← **NO FORWARDING!**
- All conditions for MEM→ID forwarding are met, but forwarding doesn't happen

### Root Cause (Preliminary Analysis)

The issue is a **timing problem** in the hazard detection:

**Execution timeline:**
```
Cycle 17: SC in EX (stalled), BNEZ in ID
          - Hazard check: Should stall BNEZ?
          - atomic_done=1 (SC just completed)
          - !atomic_done=0 → First hazard condition FALSE

Cycle 18: SC moves to MEM, BNEZ moves to EX (NO STALL!)
          - SC result now in EXMEM
          - But BNEZ already read stale value in ID stage

Cycle 19: Branch taken to FAIL (using stale data)
```

**The hazard detection has two conditions:**
```verilog
assign atomic_forward_hazard =
    (idex_is_atomic && !atomic_done && (atomic_rs1_hazard_ex || atomic_rs2_hazard_ex)) ||  // Condition 1
    (atomic_done && !exmem_is_atomic && (atomic_rs1_hazard_mem || atomic_rs2_hazard_mem));  // Condition 2
```

**Why it fails:**
- **Condition 1**: When `atomic_done=1`, this becomes FALSE (doesn't stall)
- **Condition 2**: When atomic moves to MEM, `exmem_is_atomic=1`, so this is also FALSE

There's a **one-cycle gap** where the atomic completes (`atomic_done=1`) but hasn't propagated to EXMEM yet. During this cycle, dependent instructions can slip through without stalling.

### Proposed Fix (Not Yet Implemented)

The hazard detection needs to account for the transition cycle. Possible approaches:

**Option 1**: Hold stall for one extra cycle after atomic completion
```verilog
reg atomic_done_prev;
always @(posedge clk) atomic_done_prev <= atomic_done && idex_is_atomic;

assign atomic_forward_hazard =
    (idex_is_atomic && !atomic_done && hazard) ||
    (atomic_done && !exmem_is_atomic && hazard) ||
    (atomic_done_prev && hazard);  // Extra cycle stall
```

**Option 2**: Check for atomic in EX that just finished
```verilog
wire atomic_just_finished = idex_is_atomic && atomic_done;
assign atomic_forward_hazard =
    (idex_is_atomic && hazard) ||  // Stall for all atomics in EX, even when done
    (atomic_done && !exmem_is_atomic && hazard);
```

**Option 3**: Forward from EX stage when atomic is done
- Currently, EX→ID forwarding is disabled for atomics (`!idex_is_atomic` check)
- Could enable forwarding when `atomic_done=1`
- Requires checking if `ex_atomic_result` is valid

---

## Test Results

**Before fixes:**
- LR sets reservation ✗
- Reservation immediately invalidated ✗
- SC fails ✗
- Test result: FAIL (infinite loop)

**After Bug #1 fix:**
- LR sets reservation ✓
- Reservation persists ✓
- SC succeeds ✓
- **But** BNEZ reads stale data ✗
- Test result: FAIL (branches to fail path)

**Target (after Bug #2 fix):**
- LR sets reservation ✓
- SC succeeds ✓
- BNEZ reads SC result via forwarding ✓
- Test result: PASS ✓

---

## Files Modified

### rtl/core/rv32i_core_pipelined.v
**Lines 1178-1192**: Added reservation invalidation state tracking
- New register: `hold_exmem_prev`
- Modified: `reservation_invalidate` assignment
- Effect: Prevents spurious invalidation from stale pipeline values

**Lines 1195-1214**: Added debug output (ifdef DEBUG_ATOMIC)
- Prints atomic instructions in IDEX and EXMEM
- Prints BNEZ forwarding signals
- Helps trace forwarding and hazard detection

---

## Next Steps for Bug #2

1. **Analyze hazard detection timing** more carefully
   - Add debug to print `atomic_done`, `exmem_is_atomic` each cycle
   - Trace exactly when stall signal is computed vs when instruction advances

2. **Test proposed fixes**:
   - Try Option 1: Extra cycle stall after atomic completion
   - Try Option 2: Keep stalling while `idex_is_atomic=1` regardless of done
   - Try Option 3: Enable EX→ID forwarding when atomic is done

3. **Verify fix doesn't break existing tests**
   - Run RV32I compliance suite
   - Run AMO (other atomic) tests

4. **Consider broader implications**:
   - Does similar issue affect M extension (MUL/DIV)?
   - Does similar issue affect FP extension?
   - Are there other multi-cycle operations with forwarding issues?

---

## Debugging Methodology (For Future Reference)

This systematic approach successfully identified both bugs:

1. ✅ **Run test with minimal debug** - Identify failure mode
2. ✅ **Check high-level behavior** - LR/SC succeed or fail?
3. ✅ **Add targeted debug output** - Reservation station traces
4. ✅ **Identify exact failure cycle** - When does reservation get cleared?
5. ✅ **Trace signal values** - What instruction is causing the issue?
6. ✅ **Find root cause** - Why is that signal asserted?
7. ✅ **Implement fix** - Add state tracking to prevent spurious triggers
8. ✅ **Verify fix** - Re-run with debug, confirm bug is gone
9. ⚠️ **Check for secondary issues** - Found second bug (forwarding)
10. 🔄 **Repeat for new bug** - Currently in progress

**Key insight**: When debugging fails but simulation shows operations working (like SC succeeding), look for DATA FLOW issues (forwarding, hazards) not just CONTROL FLOW issues.

---

## Conclusion

**Bug #1 (Reservation Invalidation)**: Fully fixed and verified. The reservation logic now correctly distinguishes between new stores entering MEM stage and stale pipeline values.

**Bug #2 (Forwarding Hazard)**: Root cause identified but not yet fixed. The hazard detection logic has a one-cycle gap during atomic completion that allows dependent instructions to read stale data. Fix is straightforward but requires careful implementation and testing.

**Overall Progress**: 50% complete (1 of 2 bugs fixed). The harder architectural bug (reservation invalidation) is solved. The remaining bug is a timing/scheduling issue in the hazard detection unit.
