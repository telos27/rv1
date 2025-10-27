# Known Issues

This document tracks known bugs and limitations in the RV32IMAFDC implementation.

## Active Issues

### 1. Trap Latency and Exception Propagation Issues

**Status**: Identified 2025-10-26, Under Investigation
**Priority**: MEDIUM - Some privilege tests affected
**Affected**: Tests with trap-then-ecall patterns

#### Description

The privilege mode forwarding fix introduced a one-cycle delay in trap handling (using `exception_r` instead of `exception` for `trap_flush`). This breaks the combinational feedback loop but changes trap latency from 0 to 1 cycle. Additionally, exception signals may propagate to subsequent instructions during the trap flush cycle.

**Symptoms:**
- Exception signal fires for instruction following a trap-causing instruction
- ECALL exception shows duplicate PC values (original + next instruction)
- Privilege mode updates may not be visible to immediately following instructions in trap handler

**Failing Tests:**
- `test_delegation_disable` - ECALL in S-mode trap handler shows as ECALL from M-mode (cause=11 instead of cause=9)
- `test_mstatus_state_trap` - Needs investigation

**Passing Tests:**
- 14/14 quick regression tests ✅
- 81/81 official RISC-V compliance tests ✅
- `test_delegation_to_current_mode` ✅ (fixed by actual_priv delegation fix)
- `test_umode_entry_from_mmode` ✅
- `test_umode_entry_from_smode` ✅
- 19+/34 privilege mode tests ✅

#### Root Causes Identified

1. **Exception Propagation**: When `exception` signal fires and `exception_r` is latched, the next instruction in the pipeline may also see `exception=1` before `exception_taken_r` gates it off.

2. **Privilege Mode Visibility**: After `trap_flush` updates `current_priv`, the first instruction in the trap handler may execute with stale privilege information due to pipeline timing.

3. **CSR Access After Trap**: S-mode trap handler executing in M-mode context (wrong privilege) - `current_priv` update timing issue.

#### Fixes Applied

**2025-10-26 Session**: Fixed delegation logic by separating `actual_priv` from `effective_priv`
- Changed `csr_file.v` `.actual_priv` connection from `effective_priv` to `current_priv`
- This fixed `test_delegation_to_current_mode` ✅
- Delegation now works correctly (trap goes to S-mode when medeleg bit set)
- **File**: `rtl/core/rv32i_core_pipelined.v:1543`

#### Next Steps
- Investigate `exception_taken_r` timing to prevent exception propagation
- Consider adding pipeline bubble after trap to ensure privilege mode is stable
- May need to add explicit gating of exception signal when `exception_r` is active
- Alternative: Accept 1-cycle trap latency and update affected tests

---

## Resolved Issues

### 1. Privilege Mode Forwarding Bug (RESOLVED 2025-10-26)

**Status**: FIXED ✅
**Priority**: HIGH - Was blocking Phase 6 privilege mode tests
**Affected**: Pipelined core privilege mode transitions

#### Description

When `MRET` or `SRET` executes and changes the privilege mode, the next instruction may evaluate CSR access permissions using the OLD privilege mode instead of the NEW one, causing incorrect exception delegation behavior.

#### Root Cause

Pipeline hazard in privilege mode updates:

1. `MRET`/`SRET` reaches MEM stage and updates `current_priv` register
2. Next instruction already in IF/ID/EX stages uses OLD `current_priv` for CSR checks
3. CSR illegal instruction exceptions use wrong privilege mode for delegation decisions

**Example Timeline:**
```
Cycle 34: MRET in MEM stage → current_priv = 11→01 (M→S)
          Next instruction at EX stage checks CSR access with curr_priv=11 (stale!)
          Exception delegation fails: medeleg[2]=1 but curr_priv=11 → trap to M-mode
```

#### Evidence

From `test_delegation_to_current_mode` debug output:
```
[PRIV] MRET: priv 11 -> 01 (from MPP) mepc=0x00000070
[CSR_DELEG] get_trap_target_priv: cause=2 curr_priv=11 medeleg=00000004 medeleg[cause]=1
[CSR_DELEG] -> M-mode (curr_priv==M)
```

Even with delegation enabled (`medeleg[2]=1`), the check sees `curr_priv=11` (M-mode), so per RISC-V spec "M-mode traps never delegate," the exception goes to M-mode instead of delegating to S-mode.

#### Impact

**Failing Tests:**
- `test_delegation_to_current_mode` - Phase 6
- `test_delegation_disable` - Phase 6
- Any test with immediate CSR access after MRET/SRET

**Passing Tests:**
- `test_umode_entry_from_mmode` - Works because next instruction is NOT a privileged CSR access
- Basic privilege transitions without CSR access work correctly

**Compliance:**
- 81/81 official RISC-V tests still PASS (they don't test this edge case)
- 19/34 privilege mode tests PASS (those not affected by this bug)

#### Solution Implemented

**1. Privilege Mode Forwarding** (`rv32i_core_pipelined.v:1839-1885`):
```verilog
// Compute new privilege mode from MRET/SRET in MEM stage
wire [1:0] mret_new_priv = mpp;
wire [1:0] sret_new_priv = {1'b0, spp};

// Forward privilege mode when MRET/SRET is in MEM stage
wire forward_priv_mode = (exmem_is_mret || exmem_is_sret) && exmem_valid && !exception;

// Effective privilege mode for EX stage
wire [1:0] effective_priv = forward_priv_mode ?
                            (exmem_is_mret ? mret_new_priv : sret_new_priv) :
                            current_priv;
```

**2. Exception Latching** (`rv32i_core_pipelined.v:447-481`):
- Latch `exception_target_priv_r` when exception first occurs
- Prevents combinational feedback loop (exception → trap_flush → current_priv → trap_target_priv)

**3. Delayed Trap Flush** (`rv32i_core_pipelined.v:522`):
```verilog
// Use registered exception to break feedback loop
assign trap_flush = exception_r && !exception_r_hold;
```

**4. CSR File Updates** (`csr_file.v:46-47, 602`):
- Added `actual_priv` input for trap delegation
- Separated CSR privilege checks (uses `effective_priv`) from trap delegation (uses `actual_priv`)

**Files Modified:**
- `rtl/core/rv32i_core_pipelined.v` - Privilege forwarding, exception latching
- `rtl/core/csr_file.v` - Dual privilege inputs

#### References

- RISC-V Privileged Spec v1.12 Section 3.1.6.1 (Privilege and Global Interrupt-Enable Stack)
- Issue discovered during Phase 6 implementation (Delegation Edge Cases)
- Debug trace: `docs/debug/privilege_forwarding_trace_2025-10-26.log` (if saved)

---

## Resolved Issues

(None yet - first issue tracking)

---

## Future Enhancements

1. **Trap Latency Optimization**: Current implementation has 1-cycle trap latency. Consider optimizing to 0-cycle while maintaining correctness.
2. **Coverage**: Need more edge case tests for privilege transitions
3. **Documentation**: Better waveform examples for privilege mode state machine
