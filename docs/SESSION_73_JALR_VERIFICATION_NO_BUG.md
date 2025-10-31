# Session 73: JALR Verification - No Bug Found! (2025-10-31)

## Session Goal
Investigate the suspected JALR instruction bug from Session 72 that appeared to prevent `ex_take_branch` from being set.

## Key Achievement
✅ **JALR instruction works correctly - NO BUG EXISTS!**

## Investigation Process

### 1. Initial Hypothesis (Session 72)
- Session 72 concluded JALR wasn't setting `ex_take_branch=1`
- Created `test_jalr_ret_simple` to test basic JALR/RET
- Test appeared to timeout, suggesting JALR failure

### 2. Deep Dive Analysis
Examined the entire JALR execution path:

**Branch Unit (branch_unit.v:29-31)**
```verilog
if (jump) begin
  // JAL and JALR always taken
  take_branch = 1'b1;
end
```
✓ Logic is correct

**Control Unit (control.v:217)**
```verilog
OP_JALR: begin
  reg_write = 1'b1;
  jump = 1'b1;  // ← Sets jump signal
  ...
end
```
✓ JALR sets `jump=1` correctly

**RVC Decoder (rvc_decoder.v:475)**
```verilog
// C.JR (ret instruction)
decompressed_instr = {12'b0, rs1, F3_ADD, x0, JALR};
```
✓ Compressed RET expands to JALR correctly

**Pipeline Register (idex_register.v)**
- `jump_in` → `jump_out` wiring verified correct
- Flush logic verified correct

### 3. Debug Instrumentation Added
Created `DEBUG_JALR_TRACE` flag to trace JALR through all pipeline stages:
- ID Stage: Decoding and control signal generation
- IDEX Latch: Signal propagation
- EX Stage: Branch execution

Location: `rtl/core/rv32i_core_pipelined.v:295-333`

### 4. Test Results

**Compilation:**
```bash
env XLEN=32 DEBUG_JALR_TRACE=1 iverilog -g2012 \
    -DXLEN=32 -DENABLE_C_EXT=1 -DDEBUG_JALR_TRACE \
    -DMEM_FILE="tests/asm/test_jalr_ret_simple.hex" \
    -o sim/test_jalr.vvp \
    rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
```

**Simulation Output:**
```
[CYCLE 8] JALR in ID stage:
  ifid_pc=0000001e ifid_instr=00008067 is_compressed=1
  id_jump=1 id_branch=0 stall_ifid=0 flush_ifid=0

[CYCLE 8] JALR latching into IDEX:
  jump_in=1 branch_in=0

[CYCLE 9] JALR in EX stage:
  idex_pc=0000001e idex_instr=00008067 idex_is_compressed=1
  idex_jump=1 idex_branch=0 ex_take_branch=1  ← WORKS!
  rs1_addr=x1 rs1_data=0000000e target=0000000e
```

**Final Register State:**
```
x1  (ra)   = 0x0000000e  ← Correct return address
x10 (a0)   = 0x00000001  ← Test PASSED!
x11 (a1)   = 0x00000001  ← Comparison value
```

### 5. Test Analysis
The test `test_jalr_ret_simple.s`:
1. Initializes ra to 0xDEADBEEF (known bad value)
2. Calls `test_func` via JAL (saves ra = 0x0e)
3. Function increments a0 (0→1)
4. Returns via RET (JALR x0, ra, 0)
5. Checks a0 == 1, jumps to pass
6. Sets a0=1 and infinite loops

**Result:** Test PASSES! (a0=1 in final state)

## Root Cause Analysis

### Session 72 Misdiagnosis
Session 72 incorrectly concluded JALR was broken because:
1. Test appeared to timeout → Actually, test PASSED but enters infinite loop (expected)
2. Didn't verify final register state → a0=1 indicates success
3. Assumed timeout = failure → Timeout is expected for tests with infinite end loops

### Why FreeRTOS Still Crashes
If JALR works correctly in simple tests, why does FreeRTOS crash at PC=0xa5a5a5a4?

**Answer:** The issue is NOT JALR execution, but **register corruption**:
- JALR instruction executes correctly
- But tries to jump to **corrupted address** 0xa5a5a5a5 in a register
- 0xa5a5a5 is FreeRTOS stack fill pattern (uninitialized memory)

**Possible causes:**
1. Context switch corrupting registers
2. Stack overflow/underflow
3. Incorrect stack frame setup
4. Interrupt handler corruption
5. Task return address not properly initialized

## Files Modified
- `rtl/core/rv32i_core_pipelined.v` - Added DEBUG_JALR_TRACE instrumentation
- `tests/asm/test_jalr_ret_simple.s` - Created (already existed from Session 72)

## Conclusions

1. ✅ **JALR instruction hardware is CORRECT**
   - Sets `idex_jump=1` correctly in ID stage
   - Sets `ex_take_branch=1` correctly in EX stage
   - Calculates branch target correctly
   - Writes return address correctly

2. ⚠️ **Session 72's "JALR bug" was a false diagnosis**
   - Test actually passes (a0=1)
   - Timeout is expected behavior (infinite loop at end)

3. 🔍 **FreeRTOS issue requires different investigation**
   - NOT a JALR instruction bug
   - Likely register/stack corruption
   - Jump target 0xa5a5a5a5 is uninitialized memory pattern
   - Need to trace where this value enters register file

## Debug Capability Added
New `DEBUG_JALR_TRACE` flag provides:
- ID stage decode visibility
- IDEX latch tracking
- EX stage execution details
- Branch unit input/output visibility

Usage:
```bash
env DEBUG_JALR_TRACE=1 make test
```

## Next Steps

1. **Re-examine FreeRTOS crash with correct understanding:**
   - JALR instruction works
   - Problem is corrupted jump target in register
   - Trace where 0xa5a5a5a5 value originates

2. **Investigate register/stack corruption:**
   - Context switch logic
   - Stack frame initialization
   - Task creation/deletion
   - Interrupt handler register save/restore

3. **Focus areas:**
   - Task control block initialization
   - Stack pointer setup
   - Return address setup in task creation
   - Context switch register preservation

## Lessons Learned

1. **Don't assume timeout = failure** - Check final register state
2. **Test isolation matters** - Simple tests revealed JALR works
3. **Debug instrumentation is valuable** - Visibility into pipeline stages crucial
4. **Symptoms can be misleading** - "JALR bug" was actually "corrupted register bug"
5. **Verify assumptions** - Session 72's conclusion needed verification

## Statistics
- Debug code added: ~40 lines
- Test result: PASS (a0=1)
- JALR execution: CORRECT
- False positives resolved: 1 (Session 72)

---
**Status:** JALR verified correct, FreeRTOS issue requires different investigation approach
**Date:** 2025-10-31
**Session:** 73
