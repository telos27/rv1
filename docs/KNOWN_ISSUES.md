# Known Issues

This document tracks known bugs and limitations in the RV32IMAFDC implementation.

## Active Issues

### 1. Register Preservation During Traps - test_delegation_disable

**Status**: Identified 2025-10-26 Session 5, Under Investigation
**Priority**: LOW - Single privilege test affected, compliance tests pass
**Affected**: `test_delegation_disable` (M-mode handler receives incorrect register values)

#### Description

The `test_delegation_disable` test fails because the M-mode trap handler receives an incorrect value in register `s0`. The S-mode handler sets `s0=5` before executing ECALL, but when the M-mode handler runs, `s0` appears to have a different value, causing the handler to take the wrong branch and fail.

**Symptoms:**
- S-mode handler sets `s0=5` before ECALL
- M-mode handler checks `s0` value and expects 5
- BEQ branch at M-handler+0x04 doesn't take (s0 != 5)
- Handler falls through to TEST_FAIL path
- Final `s0` value is 7, suggesting partial test progression

**Failing Tests:**
- `test_delegation_disable` - M-mode handler stage check fails

**Passing Tests:**
- 14/14 quick regression tests ✅
- 81/81 official RISC-V compliance tests ✅
- `test_delegation_to_current_mode` ✅
- `test_umode_entry_from_mmode` ✅
- `test_umode_entry_from_smode` ✅
- 22/34 privilege mode tests ✅

#### Root Causes Under Investigation

1. **Register Corruption During Trap**: Register `s0` may be corrupted during trap entry/exit
2. **Trap Timing Issue**: ECALL trap may occur before `s0=5` write commits
3. **Pipeline State Management**: Pipeline flush or stall may affect register writeback timing

#### Fixes Applied (2025-10-26 Session 5)

**CSR Write Exception Gating** (`rv32i_core_pipelined.v:1563`):
- Added `&& !exception` to CSR write enable
- Prevents CSR writes from committing when instruction causes exception
- **Impact**: ECALL detection now works correctly ✅
- This fixed the PRIMARY issue (CSR writes committing despite illegal instruction exceptions)

**Previous Fixes (Session 4):**

**Exception Propagation Fix** (`rv32i_core_pipelined.v:452`):
- Added `exception_gated = exception && !exception_r && !exception_taken_r`
- Prevents exception signal from propagating to subsequent instructions
- Eliminates spurious duplicate exceptions ✅

**Trap Target Computation Fix** (`rv32i_core_pipelined.v:454-489`):
- Added `compute_trap_target()` function in core to calculate delegation
- Uses **un-latched** `exception_code` and `current_priv` for accurate delegation
- Prevents race condition where `trap_target_priv` used stale `exception_code_r`
- Fixed trap delegation decisions ✅

**CSR Delegation Register Export** (`csr_file.v:51, 621`):
- Added `medeleg_out` port to expose `medeleg_r` to core
- Allows core to compute trap target without CSR file latency
- Core now has direct access to delegation configuration ✅

#### Impact Assessment

- **Compliance**: No impact - 81/81 official tests still pass ✅
- **Regression**: No impact - 14/14 quick tests pass ✅
- **Privilege Tests**: Minor impact - 1 test fails due to register timing issue
- **Functionality**: CSR write exception handling significantly improved

#### Progress Summary

**Session 4** (2025-10-26):
- Fixed exception propagation (exception_gated logic)
- Fixed trap delegation timing (core-side compute_trap_target)
- Added medeleg_out export from CSR file

**Session 5** (2025-10-26):
- Fixed CSR write exception gating ✅
- ECALL detection now working correctly ✅
- Identified new issue: register `s0` timing in trap handler

#### Next Steps
- Investigate register writeback timing during trap entry
- Check if ECALL trap occurs before `li s0, 5` commits to register file
- Analyze pipeline state during trap sequence with register file debug
- Consider waveform analysis for precise timing verification

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
