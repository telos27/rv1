# Known Issues

This document tracks known bugs and limitations in the RV32IMAFDC implementation.

## Active Issues

### 1. Privilege Mode Forwarding Bug (CRITICAL)

**Status**: Identified 2025-10-26, Fix Pending
**Priority**: HIGH - Blocks Phase 6 privilege mode tests
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

#### Required Fix

Implement **privilege mode forwarding** similar to data forwarding:

1. When MRET/SRET detected in MEM stage:
   - Compute new_priv from MPP/SPP
   - Forward new_priv to earlier pipeline stages

2. Modify CSR access check in EX stage:
   ```verilog
   wire [1:0] effective_priv = (mret_in_mem || sret_in_mem) ?
                                forwarded_priv : current_priv;
   ```

3. Use `effective_priv` for:
   - CSR privilege checks (`csr_priv_ok`)
   - Exception delegation decisions (`get_trap_target_priv`)

**Files to modify:**
- `rtl/core/rv32i_core_pipelined.v` - Add privilege forwarding logic
- `rtl/core/csr_file.v` - Accept forwarded privilege mode input

**Complexity**: Moderate (~2-3 hours)

#### Workaround

Tests can avoid this bug by:
1. Adding NOP instruction after MRET/SRET before CSR access
2. Avoiding immediate CSR operations after privilege transitions
3. Testing delegation separately from privilege transitions

#### References

- RISC-V Privileged Spec v1.12 Section 3.1.6.1 (Privilege and Global Interrupt-Enable Stack)
- Issue discovered during Phase 6 implementation (Delegation Edge Cases)
- Debug trace: `docs/debug/privilege_forwarding_trace_2025-10-26.log` (if saved)

---

## Resolved Issues

(None yet - first issue tracking)

---

## Future Enhancements

1. **Performance**: Privilege mode changes have 1-cycle latency due to lack of forwarding
2. **Coverage**: Need more edge case tests for privilege transitions
3. **Documentation**: Better waveform examples for privilege mode state machine
