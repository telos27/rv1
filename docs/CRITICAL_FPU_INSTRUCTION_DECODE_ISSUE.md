# 🚨 CRITICAL: FPU Instruction Decode Issue - UNRESOLVED

**Status**: 🔴 **BLOCKING** - Workaround applied, root cause unknown
**Severity**: High - Prevents FPU context switching in FreeRTOS
**Date Discovered**: 2025-10-28 (Session 56)
**Workaround Applied**: 2025-10-29

---

## Executive Summary

FreeRTOS crashes when attempting to restore FPU context during task switching. The CPU raises an illegal instruction exception, but investigation reveals the instruction never reaches the control unit properly. Despite implementing full MSTATUS.FS support, the issue persists, suggesting a deeper instruction decode or pipeline corruption problem.

**Workaround**: FPU context save/restore disabled (`portasmADDITIONAL_CONTEXT_SIZE = 0`)
**Impact**: Tasks cannot use FPU across context switches (FPU use limited to single task)

---

## Problem Description

### Symptoms
1. FreeRTOS crashes during `portcontextRESTORE_CONTEXT` macro execution
2. Exception occurs at PC=0x130 when executing `fld ft0, 0(sp)` (C.FLDSP compressed)
3. CPU raises illegal instruction exception (mcause indicates unimplemented instruction)
4. Exception is **repeatable** - occurs at exact same point every time

### Expected Behavior
- Instruction at PC=0x130: `c.fldsp ft0, 0(sp)` (compressed encoding: 0x2002)
- Should expand to: `fld ft0, 0(sp)` (OP_LOAD_FP opcode)
- Control unit should see OP_LOAD_FP and execute load
- MSTATUS.FS=11 (Dirty), so FPU should be enabled

### Actual Behavior
- mtval register shows: **0x00000013** (NOP instruction!)
- Control unit **never sees OP_LOAD_FP** opcode
- Exception handler triggered instead of normal execution
- MSTATUS.FS correctly set to 11 (Dirty) - not the issue!

---

## Investigation History

### Session 56: MSTATUS.FS Implementation
**Goal**: Implement missing MSTATUS.FS field (suspected root cause)
**Result**: ✅ Hardware complete, ❌ Issue persists

**Changes Made** (7 modifications across 4 files):
1. Added `MSTATUS_FS_LSB`/`MSTATUS_FS_MSB` constants (bits [14:13])
2. Initialize FS=11 (Dirty) on reset
3. Extract FS field and add `mstatus_fs` output port
4. **Critical**: Preserve FS in MSTATUS write handler
5. Wire `mstatus_fs` through core pipeline stages
6. Add FS validation in control unit for all FP opcodes
7. Enhanced CSR debug output with operation tracking

**Discovery**: FreeRTOS DOES initialize MSTATUS.FS!
- Uses `CSRRS mstatus, 0x2000` to set FS=11 (Dirty)
- Official docs claim no FPU support, but code includes it
- FS field remains at 11 throughout execution
- **Conclusion**: MSTATUS.FS is NOT the root cause

### The Real Mystery: Instruction Corruption?

**Evidence**:
- Expected instruction: 0x2002 (C.FLDSP)
- Actual mtval: 0x00000013 (NOP/ADDI x0, x0, 0)
- Control unit never sees OP_LOAD_FP opcode
- Instruction appears corrupted between fetch and decode

**Possible Causes**:
1. **RVC decoder bug**: C.FLDSP (0x2002) not expanding correctly
2. **Pipeline corruption**: Instruction modified between IF→ID→EX stages
3. **Memory corruption**: Instruction memory returning wrong value
4. **PC/fetch mismatch**: Fetching from wrong address
5. **Stack pointer issue**: SP pointing to invalid memory region

---

## Hardware Context

### RVC Decoder (rtl/core/rv32_rvc_decoder.v)
- Handles compressed instruction expansion (C.FLDSP → FLD)
- C.FLDSP encoding: `010_?_?????_?????_10` (bits [15:13]=010, [1:0]=10)
- Should expand to: `fld rd, offset(x2)` where x2=sp
- **Status**: Implemented, but may have bugs

### MSTATUS.FS Implementation (rtl/core/csr_file.v)
- **Hardware complete** (Session 56)
- FS field: bits [14:13] of MSTATUS
- Values: 00=Off, 01=Initial, 10=Clean, 11=Dirty
- Initialized to 11 (Dirty) on reset
- Validated in control unit for FP instructions
- **Status**: ✅ Working correctly

### FPU Control Flow (rtl/core/rv_control_unit.v)
- Checks `mstatus_fs != 2'b00` for FP instructions
- Generates illegal instruction exception if FS=Off
- OP_LOAD_FP: loads from memory to FP registers
- **Status**: Should work, but never reached

---

## Debugging Traces (Session 56)

### Last Known Good State (Cycle 57098)
```
PC=0x12E, instruction executed successfully
MSTATUS.FS=11 (Dirty), FPU enabled
SP pointing to task stack (exact value TBD)
```

### Exception Point (Cycle 57099)
```
PC=0x130
Expected: c.fldsp ft0, 0(sp) [0x2002]
Actual mtval: 0x00000013 (NOP)
mcause: Illegal instruction exception
MSTATUS.FS: Still 11 (Dirty) - correct!
```

### Key Questions
1. Why does mtval show 0x13 instead of 0x2002?
2. Where does instruction corruption occur?
3. Is RVC decoder receiving correct input?
4. Does SP point to valid memory?
5. Are other FLD instructions working in isolation?

---

## Workaround (Applied 2025-10-29)

### File Modified
`software/freertos/port/chip_specific_extensions/freertos_risc_v_chip_specific_extensions.h`

### Change
```c
// Before:
#define portasmADDITIONAL_CONTEXT_SIZE 66  /* 66 words = 264 bytes for FPU state */

// After:
#define portasmADDITIONAL_CONTEXT_SIZE 0  /* DISABLED: Was 66 words = 264 bytes */
```

### Effect
- `portasmSAVE_ADDITIONAL_REGISTERS` macro expands to empty (no FLD/FSD instructions)
- `portasmRESTORE_ADDITIONAL_REGISTERS` macro expands to empty
- FreeRTOS no longer executes FPU instructions during context switch
- Tasks cannot use FPU across context switches

### Limitations
- **FPU unavailable in multitasking**: Tasks lose FPU state on switch
- **Single-task FPU only**: Only one task can use FPU at a time
- **No FPU in interrupts**: Interrupt handlers cannot use FPU
- Timer interrupts and task switching should work normally

---

## Future Investigation Plan

### Priority 1: Isolate the Bug
1. **Test FPU instructions in isolation**
   - Create minimal test: single FLD/FSD sequence
   - Test C.FLDSP expansion specifically
   - Verify RVC decoder output for 0x2002

2. **Check instruction pipeline**
   - Add debug tracing from IF→ID→EX stages
   - Track instruction value through pipeline
   - Verify no corruption in pipeline registers

3. **Verify memory/stack**
   - Check SP value at exception point
   - Verify SP points to valid task stack region
   - Test if memory read from PC=0x130 returns 0x2002

### Priority 2: RVC Decoder Deep Dive
1. Review C.FLDSP decoding logic
2. Check if FP loads have special case issues
3. Test other compressed FP instructions (C.FSDSP)
4. Verify expanded instruction format matches spec

### Priority 3: Hardware Validation
1. Run official RV32DC compliance tests (all passed previously)
2. Create FreeRTOS-specific FPU test
3. Test FPU context save/restore in isolation

---

## Testing Strategy

### Test 1: Minimal FLD/FSD Test
```assembly
.global _start
_start:
    li sp, 0x80040000      # Set SP to known good address
    fld ft0, 0(sp)         # Should work with FS=11
    fsd ft0, 8(sp)
    li a0, 0               # Success
    j .                    # Loop
```

### Test 2: C.FLDSP Specific
```assembly
.global _start
_start:
    li sp, 0x80040000
    c.fldsp ft0, 0         # Compressed version - does it expand correctly?
    c.fsdsp ft0, 8
    li a0, 0
    j .
```

### Test 3: Stack Context Simulation
```assembly
# Simulate FreeRTOS context restore
.global _start
_start:
    li sp, 0x80040000
    # Allocate space like FreeRTOS
    addi sp, sp, -264      # FPU context size
    # Try restore
    fld ft0, 0(sp)
    fld ft1, 8(sp)
    # ... etc
```

---

## Related Files

### Hardware (Verilog)
- `rtl/core/rv32_rvc_decoder.v` - RVC expansion (C.FLDSP → FLD)
- `rtl/core/csr_file.v` - MSTATUS.FS implementation
- `rtl/core/rv_control_unit.v` - FP instruction validation
- `rtl/core/rv32i_core_pipelined.v` - Pipeline control

### Software (FreeRTOS)
- `software/freertos/port/portASM.S` - Context switch macros
- `software/freertos/port/portContext.h` - Context save/restore
- `software/freertos/port/chip_specific_extensions/freertos_risc_v_chip_specific_extensions.h` - FPU macros

### Documentation
- `docs/SESSION_56_FPU_EXCEPTION_ROOT_CAUSE.md` - Full investigation
- `docs/MSTATUS_FS_IMPLEMENTATION.md` - Hardware implementation details

---

## Success Criteria (Future)

Issue will be considered **RESOLVED** when:
1. ✅ Root cause identified and documented
2. ✅ Hardware fix implemented (if needed)
3. ✅ FreeRTOS can save/restore FPU context without crash
4. ✅ All regression tests still pass (14/14)
5. ✅ FreeRTOS task switching with FPU works correctly
6. ✅ Timer interrupts work with FPU context save

---

## Notes for Future Sessions

**IMPORTANT**: This is a **critical hardware bug** that must be resolved before claiming full RV32IMAFDC compliance in a multitasking environment.

**When resuming investigation**:
1. Read this document first
2. Review Session 56 notes: `docs/SESSION_56_FPU_EXCEPTION_ROOT_CAUSE.md`
3. Start with Test 1 (minimal FLD/FSD test)
4. Add extensive debug tracing to RVC decoder and pipeline
5. Focus on **why mtval=0x13** instead of 0x2002

**Priority**: Medium-High
- Not blocking RV64 upgrade (Phase 3)
- Blocks full FreeRTOS FPU support
- May indicate subtle pipeline bug affecting other instructions

---

**Last Updated**: 2025-10-29
**Status**: Workaround applied, investigation deferred
**Next Action**: Run Test 1 when investigation resumes
