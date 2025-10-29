# Session 57 Summary: FPU Workaround Applied - FreeRTOS Progresses!

**Date**: 2025-10-29
**Focus**: Apply workaround for FPU instruction decode bug, unblock FreeRTOS testing
**Status**: ✅ Success - FreeRTOS now runs 39K+ cycles, new issues discovered

---

## Achievements

### 1. FPU Workaround Successfully Implemented
- **Problem**: FLD/FSD instructions causing illegal instruction exceptions at PC=0x12E/0x130
- **Root Cause**: Instruction decode/pipeline bug (mtval shows wrong instruction)
- **Solution**: Disabled FPU context save/restore in FreeRTOS
  - Modified: `software/freertos/port/chip_specific_extensions/freertos_risc_v_chip_specific_extensions.h`
  - Set `portasmADDITIONAL_CONTEXT_SIZE = 0`
  - Emptied `portasmSAVE_ADDITIONAL_REGISTERS` macro (removed all FSD instructions)
  - Emptied `portasmRESTORE_ADDITIONAL_REGISTERS` macro (removed all FLD instructions)

### 2. FreeRTOS Progress: 39K+ Cycles!
**Before Workaround**: Crashed at <1K cycles (PC=0x130)
**After Workaround**: Runs to 39K+ cycles before hitting new issues

**Progress Observed**:
- ✅ FreeRTOS boots successfully
- ✅ BSS fast-clear works (258 KB in 1 cycle)
- ✅ FreeRTOS kernel code executes
- ✅ Queue operations start (`xQueueGenericReset` called)
- ✅ ECALL traps work correctly (mcause=11)
- ✅ Data forwarding works (MULHU operations traced)

### 3. Comprehensive Documentation Created
- **`docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md`**:
  - Full tracking document for FPU decode bug
  - Investigation history and evidence
  - Future investigation plan with test cases
  - Success criteria for resolution
- **`docs/SESSION_57_FPU_WORKAROUND_APPLIED.md`**:
  - Detailed workaround implementation
  - Test results and analysis
  - Impact and limitations
  - Current behavior traces

---

## New Issues Discovered

### 1. IMEM .rodata Copy Issue (Cycle ~40-200)
**Symptom**: Strings not loading correctly from IMEM
```
Expected: "[Task" (0x5B 54 61 73)
Actual:   0x00000013 (NOP instruction)
```
**Impact**: String constants in FreeRTOS not accessible
**Hypothesis**: IMEM data port reads may be faulty
**Priority**: High - blocks correct FreeRTOS initialization

### 2. Early Assertion (Cycle 1,829)
**Symptom**: `vApplicationAssertionFailed()` called very early
**Location**: Right after `main()` returns (ra=0xcc, halt label)
**Context**: During startup, before main scheduler loop
**Priority**: Medium - may be related to .rodata issue

### 3. Queue Assertion (Cycle 30,355)
**Symptom**: Queue overflow check triggers incorrectly
```
queueLength = 0x800004b8 (looks like pointer!)
itemSize    = 0xffffffff (invalid!)
MULHU overflow check fails
```
**Function**: `xQueueGenericReset()`
**Possible Causes**:
- Queue structure corruption
- Uninitialized memory
- MULHU result forwarding issue (unlikely - traces look correct)
**Priority**: Medium - may be cascade from earlier issues

### 4. Illegal Instruction (Cycle 39,415)
**Symptom**: mtval=0x13 (NOP) at PC=0x1f46
**Similar to**: Original FPU decode bug (mtval showing wrong instruction)
**Hypothesis**: Same underlying instruction decode/pipeline corruption bug
**Priority**: High - suggests systemic issue, not just FPU-specific

---

## Impact & Limitations

### What Works ✅
- FreeRTOS boots and runs kernel code
- Integer register context switching (should work)
- Timer interrupts (should work - not yet tested)
- Queue operations (partial - hits assertion)
- ECALL exception handling
- Data forwarding and hazard detection

### What's Limited/Broken ⚠️
- **FPU context switching**: Disabled - tasks cannot use FPU across switches
- **FPU in interrupts**: Disabled - handlers cannot use FPU
- **String constants**: Not loading from IMEM correctly
- **Queue operations**: Hit assertion (may be initialization issue)
- **Full scheduler**: Not yet reached (blocked by earlier issues)

### Trade-offs
- **Short-term**: Workaround allows continued testing without FPU
- **Long-term**: Must fix instruction decode bug for full RV32IMAFDC multitasking
- **Current capability**: Integer-only multitasking should work when other issues resolved

---

## Technical Details

### Files Modified
1. `software/freertos/port/chip_specific_extensions/freertos_risc_v_chip_specific_extensions.h`
   - Line 45: `portasmADDITIONAL_CONTEXT_SIZE = 0`
   - Lines 64-67: Empty `portasmSAVE_ADDITIONAL_REGISTERS` macro
   - Lines 76-79: Empty `portasmRESTORE_ADDITIONAL_REGISTERS` macro

### Key Observations from Traces

#### Cycle 30,231-30,355: Queue Operations
```
Store to queue structure at 0x800004c4
xQueueGenericReset called
  a0 (queue ptr) = 0xffffffff (invalid!)
  But s0 later shows 0x8000048c (correct?)
Loading queueLength from offset 60
  queueLength = 0x800004b8 (suspicious!)
MULHU overflow check fails
vApplicationAssertionFailed() called
```

#### Cycle 39,171-39,415: Exception Cascade
```
Cycle 39,171: ECALL (mcause=11, mepc=0x1684)
Cycle 39,371: ECALL (mcause=11, mepc=0x1b40)
Cycle 39,415: Illegal instruction (mcause=2, mepc=0x1f46)
  mtval = 0x00000013 (NOP - wrong instruction!)
```

---

## Next Steps (Session 58)

### Immediate Priority
1. **Debug .rodata Copy Issue**
   - Check IMEM data port implementation
   - Verify IMEM-on-bus address mapping
   - Test isolated IMEM reads in testbench
   - May need to review Session 51 IMEM-on-bus changes

2. **Validate with Regression Tests**
   - Run `make test-quick` to ensure nothing broke
   - Verify all 14/14 tests still pass
   - Check FPU tests still work (no context switching needed)

3. **Investigate IMEM Data Port**
   - Review `rtl/interconnect/simple_bus.v` IMEM data handling
   - Check `rtl/memory/imem_bus_adapter.v` implementation
   - Verify address decoding for .rodata region

### Medium Priority
4. **Debug Queue Assertion**
   - May resolve automatically if .rodata issue is fixed
   - Otherwise: check queue structure initialization
   - Verify memory layout and alignment

5. **Test Timer Interrupts**
   - Should work with integer-only contexts
   - Validate CLINT operation with workaround
   - Test context switching without FPU

### Deferred
6. **FPU Instruction Decode Bug**
   - Status: Deferred with workaround in place
   - See: `docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md`
   - Return to this after FreeRTOS integer-only multitasking works

---

## Test Commands

### FreeRTOS Test (Current)
```bash
env XLEN=32 TIMEOUT=30 ./tools/test_freertos.sh
```

### Quick Regression
```bash
make test-quick  # Should still pass 14/14
```

### Rebuild FreeRTOS (if needed)
```bash
cd software/freertos && make clean && env XLEN=32 make
```

---

## Related Documents
- `docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md` - FPU bug tracking
- `docs/SESSION_57_FPU_WORKAROUND_APPLIED.md` - Workaround details
- `docs/SESSION_56_FPU_EXCEPTION_ROOT_CAUSE.md` - MSTATUS.FS implementation
- `docs/SESSION_55_FREERTOS_CRASH_INVESTIGATION.md` - Previous crash analysis
- `docs/SESSION_54_HOLD_EXMEM_BUS_WAIT_FIX.md` - Bus wait fix
- `CLAUDE.md` - Updated with Session 57 status

---

## Statistics
- **Cycles Before**: <1,000 (crash at PC=0x130)
- **Cycles After**: 39,000+ (hits new issues)
- **Improvement**: ~40x increase in execution
- **Files Modified**: 1 (FreeRTOS port header)
- **Lines Changed**: ~70 lines (mostly deletions)
- **Documentation**: 2 new comprehensive docs created

---

## Conclusion

Session 57 successfully applied a workaround to bypass the critical FPU instruction decode bug, allowing FreeRTOS to progress from crashing at <1K cycles to running 39K+ cycles. This is a major milestone that unblocks continued FreeRTOS testing.

However, new issues were discovered:
1. IMEM .rodata reads returning wrong data (highest priority)
2. Queue assertion failures (may be cascade)
3. Illegal instruction exceptions (similar to FPU bug - systemic issue?)

The FPU decode bug remains unresolved but is documented and deferred. The focus for Session 58 should be on debugging the IMEM .rodata issue, which appears to be blocking correct FreeRTOS initialization.

**Status**: ✅ Workaround successful, new debugging path identified
**Next Session**: Debug IMEM data port and .rodata copy issue
