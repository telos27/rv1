# Phase 15.2: Atomic Forwarding Stall Logic Implementation

**Date**: 2025-10-12
**Status**: In Progress - Logic implemented but not yet working
**Objective**: Prevent forwarding from in-progress atomic operations to dependent instructions

---

## Problem Recap

From Phase 15.1, we identified that the LR/SC test fails because:
- LR instruction in EX stage hasn't completed yet
- Dependent ADD instruction in ID stage tries to forward from EX
- Forwarded value (`ex_atomic_result`) isn't ready yet
- ADD reads stale/incorrect data

**Test Sequence**:
```assembly
800001f0:  lr.w   a4, (a0)      # Load reserved from mem[a0] into a4
800001f4:  add    a4, a4, a2    # a4 = a4 + a2 (should be loaded_value + 1)
800001f8:  sc.w   a4, a4, (a0)  # Store conditional a4 to mem[a0]
800001fc:  bnez   a4, 800001f0  # Loop if SC failed
```

**Expected**: ADD computes `loaded_value + 1`
**Actual**: ADD computes `address + 1` (0x80002008 + 1 = 0x80002109)

---

## Solution Approach

### Strategy: Stall on Atomic Forward Hazard

When the ID stage would forward from an in-progress atomic operation in EX:
1. Stall the PC (don't fetch new instruction)
2. Stall IF/ID register (keep current instruction in ID)
3. Insert bubble into ID/EX (prevent dependent instruction from advancing)
4. Wait until atomic completes (atomic_done = 1)
5. Then allow dependent instruction to proceed with correct forwarded value

---

## Implementation

### Changes to `hazard_detection_unit.v`

**1. Added forwarding signal inputs** (lines 29-31):
```verilog
// ID stage forwarding signals (to detect forwarding from in-progress atomics)
input  wire [2:0]  id_forward_a,     // ID forward select for rs1
input  wire [2:0]  id_forward_b,     // ID forward select for rs2
```

**2. Added atomic forward hazard detection** (lines 108-117):
```verilog
// A extension forwarding hazard: stall when ID stage would forward from in-progress atomic in EX
// This prevents forwarding atomic results before they're ready.
// Forward from EX is indicated by id_forward_a/b == 3'b100
// Stall if: forwarding from EX AND atomic in EX AND not done
// This catches all cases including the first cycle when atomic enters EX
wire atomic_forward_hazard;
assign atomic_forward_hazard =
  ((id_forward_a == 3'b100) || (id_forward_b == 3'b100)) &&  // Forwarding from EX stage
  idex_is_atomic &&                                            // EX has atomic instruction
  !atomic_done;                                                // Not yet complete
```

**3. Updated stall control signals** (lines 135-136):
```verilog
assign stall_pc    = ... || atomic_forward_hazard || ...;
assign stall_ifid  = ... || atomic_forward_hazard || ...;
```

**4. Updated bubble control** (line 140):
```verilog
assign bubble_idex = load_use_hazard || fp_load_use_hazard || atomic_forward_hazard;
```

### Changes to `rv32i_core_pipelined.v`

**Updated hazard detection unit instantiation** (lines 763-765):
```verilog
// ID stage forwarding signals (for atomic forwarding hazard detection)
.id_forward_a(id_forward_a),
.id_forward_b(id_forward_b),
```

---

## Testing Results

### Test: rv32ua-p-lrsc
**Result**: Still TIMEOUT/ERROR

**Observations**:
- Instruction count changed: 17913 → 10787 (more stalling occurring)
- CPI increased: 2.791 → 4.635 (pipeline more stalled)
- Flush cycles increased: 49.9% → 64.1%
- Still stuck in infinite loop with a4 = 0x80002109

### Test: All A Extension Tests
**Result**: 9/10 PASS (no regressions)
- All 9 AMO tests still pass
- Only LR/SC still fails

---

## Analysis: Why It's Not Working Yet

### Theory 1: Timing Issue
The stall condition checks:
```verilog
atomic_forward_hazard = (id_forward_a == 3'b100) && idex_is_atomic && !atomic_done
```

**Potential problem**: When does `idex_is_atomic` become true?
- LR enters ID on cycle N
- LR latched into IDEX on cycle N+1 (idex_is_atomic becomes 1)
- ADD enters ID on cycle N+1, reads operands

If ADD reads operands **before** the clock edge that latches idex_is_atomic, the stall won't trigger!

### Theory 2: Forwarding Decision Timing
The forwarding unit makes its decision combinationally:
```verilog
id_forward_a = (idex_reg_write && idex_rd == id_rs1) ? 3'b100 : ...
```

If this evaluates before `idex_is_atomic` is valid, we might detect forwarding but not the atomic nature.

### Theory 3: Result Not Ready
Even with stalling, `ex_atomic_result` might not contain valid data:
```verilog
// In atomic_unit.v, result is only updated when:
if (state == STATE_WAIT_READ && mem_ready) begin
    result <= mem_rdata;  // LR result
end
```

If we're stalling but the result register hasn't been updated yet, forwarding will still get stale data.

### Theory 4: Wrong Forwarding Source
Maybe the issue is that we're still forwarding from `ex_alu_result` instead of `ex_atomic_result`. The forwarding mux should use:
```verilog
assign ex_forward_data = idex_is_atomic ? ex_atomic_result : ex_alu_result;
```

But if `ex_atomic_result` is 0 or uninitialized, this won't help.

---

## Next Steps for Debugging

### 1. Add Debug Output (PRIORITY)
Add targeted debug to see:
- When `idex_is_atomic` becomes true
- When `id_forward_a` becomes 3'b100
- When `atomic_forward_hazard` triggers
- Value of `ex_atomic_result` at forwarding time
- Whether stall actually happens

### 2. Check Atomic Result Initialization
Verify that `ex_atomic_result` starts with a known value (0x00000000, not garbage).

### 3. Verify Forwarding Mux Selection
Confirm that when forwarding from EX atomic, we're actually selecting `ex_atomic_result` not `ex_alu_result`.

### 4. Consider Alternative: Load-Use Style Stall
Instead of checking forwarding signals, treat atomics like loads:
```verilog
wire atomic_use_hazard;
assign atomic_use_hazard = idex_is_atomic &&
                            ((idex_rd == ifid_rs1 && idex_rd != 0) ||
                             (idex_rd == ifid_rs2 && idex_rd != 0));
```

This would stall **all** dependent instructions, not just those that forward.

### 5. Check if Problem is Earlier in Pipeline
Maybe the issue is that LR's `idex_rd` isn't being set correctly, so forwarding unit doesn't detect the hazard at all.

---

## Files Modified

### rtl/core/hazard_detection_unit.v
- Added `id_forward_a` and `id_forward_b` inputs
- Added `atomic_forward_hazard` wire and logic
- Updated `stall_pc`, `stall_ifid`, and `bubble_idex` assignments

### rtl/core/rv32i_core_pipelined.v
- Connected `id_forward_a` and `id_forward_b` to hazard detection unit

---

## Architecture Notes

### Hazard Types in RV1 Core

1. **Load-Use Hazard**: Load in EX, dependent instruction in ID
   - Solution: 1-cycle stall + bubble

2. **Multi-Cycle Operation Hazard**: M/A/F extension ops in EX
   - Solution: Hold IDEX and EXMEM, stall IF/ID

3. **Atomic Forward Hazard** (NEW): Atomic in EX, dependent tries to forward
   - Attempted solution: Stall + bubble (like load-use)
   - Status: Not working yet

### Key Differences from Load-Use

Load-use hazard:
- Load completes in 1 extra cycle
- Forwarding from MEM stage works fine
- Stall for 1 cycle is sufficient

Atomic forward hazard:
- Atomic takes multiple cycles (3-5 cycles for LR)
- Result available in EX stage, but timing is complex
- May need to stall for multiple cycles OR wait until MEM/WB stage

---

## Lessons Learned

1. **Multi-cycle operations are hard**: Even with correct forwarding paths, timing of when results become available is critical

2. **Stall logic requires precise timing**: Checking at the right pipeline stage with the right signals is essential

3. **Load-use analogy may not apply**: Atomics might need different treatment than loads

4. **Debug output is essential**: Without visibility into signal timing, debugging pipeline hazards is nearly impossible

---

## Open Questions

1. **Why does the test show a4 = 0x80002109 (address+1) instead of loaded_value+1?**
   - Is forwarding selecting the wrong source?
   - Is the atomic result register not being updated?
   - Is there an off-by-one error in the address calculation?

2. **When exactly does `ex_atomic_result` become valid?**
   - On what cycle after the atomic starts?
   - Does it persist across cycles or change?

3. **Should we disable EX→ID forwarding for atomics entirely?**
   - Force wait until atomic reaches MEM or WB stage?
   - Would be less efficient but more reliable?

4. **Is the stall actually triggering?**
   - How can we verify this without adding clock-dependent debug?

---

## Recommendation for Next Session

**Approach 1: Detailed Debug Session**
1. Compile with extensive debug output
2. Run LR/SC test for just first 100 cycles
3. Trace exact pipeline state when LR→ADD transition occurs
4. Identify exact cycle where wrong value is forwarded

**Approach 2: Alternative Design**
1. Disable EX→ID forwarding for atomics
2. Force atomics to only forward from MEM or WB stages
3. Accept the performance penalty for correctness
4. Test if this resolves the issue

**Approach 3: Load-Use Style Detection**
1. Treat atomics exactly like loads in hazard detection
2. Use register number matching instead of forwarding signal checking
3. Simpler logic, might be more reliable

**Recommended**: Try Approach 3 first (simplest), then Approach 1 (most thorough).
