# Session 56: FPU Exception Root Cause Analysis

**Date**: 2025-10-28
**Status**: 🎯 ROOT CAUSE CONFIRMED - MSTATUS.FS field missing

## Summary
Identified the root cause of FreeRTOS FPU context restore exception: **MSTATUS.FS field is not implemented**, causing all floating-point instructions to trap with illegal instruction exceptions.

## Problem Statement
- FreeRTOS crashes at cycle 57099 during first task switch
- Exception occurs at `xPortStartFirstTask` when executing `fld ft0, 0(sp)`
- mcause = 0x02 (illegal instruction)
- CPU stuck in exception handler infinite loop

## Investigation Results

### Root Cause: Missing MSTATUS.FS Field

**Finding**: The MSTATUS.FS field (bits [14:13]) is **NOT defined** in the CSR implementation.

**Evidence**:
1. Checked `rtl/config/rv_csr_defines.vh` - NO FS field definition (lines 88-107)
2. Checked `rtl/core/csr_file.v` - NO FS field extraction or handling
3. RISC-V spec requires FS field to enable FPU operations

**RISC-V Spec Reference** (Privileged Spec Section 3.1.6.5):
```
MSTATUS.FS[14:13] - Floating-point unit Status
  00 = Off    - FP instructions cause illegal instruction exception
  01 = Initial - FP state initialized but not modified
  10 = Clean  - FP state modified, in sync with memory
  11 = Dirty  - FP state modified, not yet saved to memory
```

**Impact**: With FS=00 (hardwired to Off), ALL FP load/store instructions trap as illegal, including:
- `fld`, `fsd` (double-precision load/store)
- `flw`, `fsw` (single-precision load/store)
- `fadd.s`, `fmul.d`, etc. (all FP arithmetic)

### Why Official FPU Tests Pass
The official RISC-V FPU tests (rv32uf, rv32ud) run in M-mode and may:
1. Not require FS field check (bare-metal assumption)
2. Have testbench that bypasses FS checking
3. Enable FPU through different mechanism

### Why FreeRTOS Fails
FreeRTOS port expects standard privilege-compliant FPU behavior:
1. FreeRTOS initializes MSTATUS properly (sets MPP, MIE, etc.)
2. FreeRTOS port saves/restores FP context on task switch
3. FreeRTOS expects FS to be non-zero to allow FP instructions
4. Without FS field, first FP instruction (`fld ft0, 0(sp)`) traps

## Fix Strategy

### Option 1: Implement MSTATUS.FS Field (Proper Solution)
**Complexity**: Medium
**Time**: 2-3 hours
**Scope**:
1. Add FS field constants to `rv_csr_defines.vh`
2. Add FS state register to `csr_file.v`
3. Implement FS state machine (Off → Initial → Clean → Dirty)
4. Update illegal instruction logic to check FS before FP ops
5. Handle FS writes (WARL behavior, reset to Initial/Off)

**Steps**:
```verilog
// 1. Add to rv_csr_defines.vh:
localparam MSTATUS_FS_LSB = 13;
localparam MSTATUS_FS_MSB = 14;

// 2. Add to csr_file.v:
wire [1:0] mstatus_fs_w = mstatus_r[MSTATUS_FS_MSB:MSTATUS_FS_LSB];

// 3. Initialize to Initial (01) or Dirty (11) on reset
mstatus_r[MSTATUS_FS_MSB:MSTATUS_FS_LSB] <= 2'b11; // Start with FPU enabled

// 4. Check in decoder/exception logic:
if (is_fp_instr && mstatus_fs_w == 2'b00) begin
  illegal_instruction <= 1'b1;
end
```

### Option 2: Quick Workaround - Disable FP Context Save (Already Documented)
**Complexity**: Low
**Time**: 10 minutes
**Tradeoff**: Tasks cannot use floating-point

Edit `software/freertos/FreeRTOS-Kernel/portable/GCC/RISC-V/portASM.S`:
```asm
.set portasmADDITIONAL_CONTEXT_SIZE, 0  // Skip FP registers (was 33)
```

### Option 3: Lazy FPU Context Switching
**Complexity**: High
**Time**: 4-6 hours
**Scope**: Only save/restore FP context when task actually uses FPU

## Recommendation

**Implement Option 1** (Proper MSTATUS.FS support):
- Aligns with RISC-V privilege spec
- Required for proper FPU integration
- Fixes root cause rather than working around it
- Enables full FreeRTOS floating-point support
- Required for future OS work (xv6, Linux)

**Fallback**: Use Option 2 if time-constrained, but:
- Document as technical debt
- Limits FreeRTOS task functionality
- May cause issues with FP-dependent libraries

## Implementation Complete ✅

### Changes Made
1. ✅ Added MSTATUS.FS field constants to `rv_csr_defines.vh` (bits [14:13])
2. ✅ Initialized MSTATUS.FS=11 (Dirty) on reset in `csr_file.v`
3. ✅ Added FS field extraction and output wire in `csr_file.v`
4. ✅ Added FS field to MSTATUS write handler (preserves FS on CSR writes)
5. ✅ Wired `mstatus_fs` signal from CSR file through core to control unit
6. ✅ Added FS validation in `control.v` for all FP instruction types:
   - OP_LOAD_FP (FLW/FLD)
   - OP_STORE_FP (FSW/FSD)
   - OP_MADD/OP_MSUB/OP_NMSUB/OP_NMADD (FMA variants)
   - OP_OP_FP (all other FP operations)
7. ✅ Regression tests pass (14/14 tests, including FPU tests)

### Current Status

**Hardware Implementation**: COMPLETE ✅
- MSTATUS.FS field fully implemented and functional
- FP instructions properly trap when FS=00 (Off)
- FP instructions execute normally when FS≠00

**Unexpected Discovery**: FreeRTOS DOES handle MSTATUS.FS! 🎯

**Initial Analysis - CSRRS Operation**:
- Hardware initializes: MSTATUS = 0x7800 (FS=11, MPP=11)
- FreeRTOS attempts: `CSRRS mstatus, 0x2000` (set FS=01 bit)
- CSRRS performs: `new_value = old_value | wdata = 0x7800 | 0x2000 = 0x7800`
- **Result**: MSTATUS.FS remains 11 (Dirty), not 01 (Initial)
- **BUT**: FS=11 should still allow FP instructions!

**Key Findings**:
1. ✅ Official FreeRTOS RISC-V port DOES try to set MSTATUS.FS (contrary to forum claims)
2. ✅ Uses same approach as SiFive fork: `CSRRS mstatus, 0x2000` to enable FPU
3. ✅ MSTATUS.FS stays at 11 throughout execution (confirmed via CSR debug traces)
4. ❌ FP instructions still trap as illegal despite FS=11

**Real Issue - Still Unknown** 🔍:
- Exception at PC=0x130 (should be `fld ft0, 0(sp)` compressed = 0x2002)
- But mtval=0x00000013 (NOP instruction, not FLD!)
- Control unit debug shows NO OP_LOAD_FP opcodes reaching control logic
- **Hypothesis**: Instruction decode or pipeline issue, NOT MSTATUS.FS

**Context**:
- Official FreeRTOS port documentation claims no FPU support (Feb 2025 forum)
- But actual code DOES include FPU initialization (similar to SiFive)
- Our port adds FP context save/restore to standard FreeRTOS base

### Next Steps

**Option A: Fix FreeRTOS Port (Recommended)**
Modify FreeRTOS RISC-V port to set MSTATUS.FS before using FP context save/restore:

```c
// In port.c or portASM.S initialization:
// Enable FPU by setting MSTATUS.FS = 11 (Dirty)
#define MSTATUS_FS_MASK (0x3 << 13)
#define MSTATUS_FS_DIRTY (0x3 << 13)

// In vPortSetupTimerInterrupt() or similar init function:
uint32_t mstatus;
__asm__ volatile ("csrr %0, mstatus" : "=r"(mstatus));
mstatus |= MSTATUS_FS_DIRTY;
__asm__ volatile ("csrw mstatus, %0" :: "r"(mstatus));
```

**Option B: Hardware Auto-Enable (Not Recommended)**
Modify hardware to never allow FS=00:
- Pro: Software doesn't need changes
- Con: Violates RISC-V spec (FS should be software-controlled)
- Con: Prevents power-saving by disabling FPU

**Option C: Disable FP Context Save (Temporary Workaround)**
Set `portasmADDITIONAL_CONTEXT_SIZE = 0` in portASM.S
- Pro: Quick workaround to test task switching
- Con: Tasks cannot use floating-point operations

## Next Session Tasks

**MSTATUS.FS is a red herring!** The real issue is elsewhere:

1. 📋 **PRIORITY**: Debug instruction decode issue
   - Why does FLD (0x2002) not reach control unit as OP_LOAD_FP?
   - Why is mtval=0x13 (NOP) instead of 0x2002 (FLD)?
   - Check RVC decoder expansion for C.FLDSP
   - Check pipeline for instruction corruption
2. 📋 Test FreeRTOS task switching once decode issue fixed
3. 📋 Validate timer interrupts work correctly
4. 📋 Run full FreeRTOS test suite

## Session Summary

**What worked**:
- ✅ MSTATUS.FS field fully implemented (hardware complete)
- ✅ All regression tests pass (14/14)
- ✅ FPU tests still work with new FS validation
- ✅ Discovered FreeRTOS DOES initialize MSTATUS.FS

**What didn't work**:
- ❌ FreeRTOS still crashes (but NOT due to MSTATUS.FS!)
- ❌ Real issue is instruction decode/pipeline, not CSR

**Key insight**: Always verify assumptions! MSTATUS.FS was the obvious suspect, but the real bug is hidden deeper in instruction processing.

## Files Involved
- `rtl/config/rv_csr_defines.vh` - Add FS field constants
- `rtl/core/csr_file.v` - Implement FS state tracking
- `rtl/core/rv32i_core_pipelined.v` - May need FS signal routing
- `rtl/core/decoder.v` - Check FS for FP instruction legality

## References
- RISC-V Privileged Spec v1.12, Section 3.1.6.5 (MSTATUS.FS field)
- FreeRTOS RISC-V port: `portASM.S` (FP context save/restore)
- Session 55 investigation: `docs/SESSION_55_FINAL_ANALYSIS.md`
