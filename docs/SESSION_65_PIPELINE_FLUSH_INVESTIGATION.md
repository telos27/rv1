# Session 65: Pipeline Flush Investigation (2025-10-29)

## Summary
Investigated pipeline flush logic after Session 64 findings. Determined that **original pipeline code is CORRECT** and my attempted "fix" was wrong.

## Investigation

### Initial Hypothesis (INCORRECT)
- Believed that JAL/JALR instructions were being flushed before completing
- Thought removing `ex_take_branch` from `flush_idex` would fix register write issues
- Appeared to help FreeRTOS run longer (39K → 282K cycles)

### Testing Results
- **Original code**: All regression tests PASS (14/14) ✅
- **With my "fix"**: 2 tests FAIL (rv32ua-p-lrsc, rv32uc-p-rvc) ❌
- **FreeRTOS**: Exhibits issues with BOTH versions

### Root Cause Analysis

#### Pipeline Flush Timing (Correct Behavior)
When a branch/jump executes in EX stage:

**Cycle N+2** (branch in EX):
- ID/EX register contains branch instruction (latched at N+1→N+2)
- EX stage evaluates branch, sets `ex_take_branch=1`
- `flush_ifid=1` (flush IF/ID register)
- `flush_idex=1` (flush ID/EX register - **CORRECT!**)

**Clock edge N+2→N+3**:
- EX/MEM latches branch from ID/EX outputs (happens BEFORE flush)
- ID/EX updates to NOP (due to flush)
- IF/ID updates to NOP (due to flush)
- Branch continues to MEM stage → WB stage → writes register ✅

#### Why Original Code Works
The flush happens at the clock edge, but EX/MEM latches the branch instruction BEFORE ID/EX updates its outputs. This is standard Verilog behavior - all registers sample their inputs before updating outputs.

#### Why My "Fix" Was Wrong
Removing `ex_take_branch` from `flush_idex` allows the wrong-path instruction (after the branch) to enter the pipeline and execute. This breaks:
- **Atomic tests**: LR/SC sequences require precise control flow
- **RVC tests**: Compressed instruction sequences sensitive to wrong-path execution

### FreeRTOS Investigation

#### What We Know
1. Init_array code executes correctly at cycles 1809-1817
2. FreeRTOS boots and runs for thousands of cycles
3. Eventually exhibits issues (infinite loops, crashes)
4. The issue is NOT related to pipeline flush logic

#### What Needs Investigation
- t0 register corruption (if still occurring)
- Task context switching behavior
- Interrupt handling
- Stack initialization (Session 64 found it correct, but more testing needed)

## Conclusion

**The pipeline flush logic is WORKING CORRECTLY.**

The original code:
```verilog
assign flush_ifid = trap_flush | mret_flush | sret_flush | ex_take_branch;
assign flush_idex = trap_flush | mret_flush | sret_flush | flush_idex_hazard | ex_take_branch;
```

This is the correct implementation. Branch/jump instructions:
1. Set `ex_take_branch=1` in EX stage
2. Flush IF/ID and ID/EX to remove wrong-path instructions
3. Continue through MEM → WB to complete (write return address for JAL/JALR)
4. Pipeline refills from branch target

## Recommendations

1. **Keep original pipeline code** - It is correct
2. **FreeRTOS debugging** should focus on:
   - Actual crash symptoms (register corruption, unexpected jumps)
   - Software-level issues (stack, interrupts, context switching)
   - NOT hardware pipeline issues

## Files
- `rtl/core/rv32i_core_pipelined.v` - Pipeline flush logic (KEEP ORIGINAL)
- `docs/SESSION_64_STACK_INITIALIZATION_INVESTIGATION.md` - Previous investigation
- `docs/SESSION_63_FREERTOS_CONTEXT_SWITCH_BUG.md` - Context switch analysis

## Status
✅ Pipeline logic validated
❌ FreeRTOS issues remain (separate root cause)
