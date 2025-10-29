# Session 61: FPU Exception Debug Investigation

**Date**: 2025-10-29
**Status**: ✅ Root Cause Identified - NOT FPU Issue!
**Branch**: main (cdcb49e)

## Session Goal

Debug the FPU instruction decode issue causing illegal instruction exceptions at cycle 39,415 in FreeRTOS execution.

## TL;DR - Critical Discovery

**The "FPU exception" is NOT an FPU issue!** The exception occurs because:
1. CPU execution reaches address 0x1f46 (past end of code section)
2. Memory contains zeros (gap after MRET instruction)
3. CPU tries to execute 0x00000000 → decoded as 0x00000013 (NOP)
4. Control module incorrectly flags NOP as illegal instruction
5. Exception triggered with mtval=0x13

**Root Cause**: MRET execution or exception handling bug causes PC to fall through to invalid memory instead of jumping via MEPC.

---

## Investigation Process

### Step 1: Exception Reproduction

Ran FreeRTOS test and confirmed exception at cycle 39,415:
- **mepc**: 0x00001f46
- **mcause**: 0x2 (Illegal instruction)
- **mtval**: 0x00000013 (NOP)
- **MSTATUS.FS**: 11 (Dirty) ← **FPU enabled!**

Initial hypothesis: FPU instruction causing exception despite MSTATUS.FS=11.

### Step 2: Instruction Analysis

Analyzed instruction at mepc=0x1f46:
- Disassembly showed gap after MRET at 0x1f42: `...` (zero-filled)
- Binary verification:
  ```
  00001f40: c107 7300 2030 0000 0000 0000 0000 0000
            1f40 1f42  1f44  1f46 onwards...
                 MRET  [gap of zeros = NOPs]
  ```
- **Finding**: 0x1f46 contains 0x00000000, NOT an FP instruction!

### Step 3: Enhanced Debug Output

Modified `tb/integration/tb_freertos.v` to capture exception state BEFORE pipeline flush:
- Added `[EXCEPTION-DETECTION]` monitor triggered by `exception_gated`
- Captures IDEX instruction, MSTATUS.FS, control signals, flush state
- Added `[TRAP-CSR-UPDATE]` monitor for post-flush state

**Key Code Addition** (lines 313-380):
```verilog
// Enhanced exception monitoring - capture state BEFORE pipeline flush
always @(posedge clk) begin
  if (reset_n) begin
    if (DUT.core.exception_gated && !exception_detected_prev) begin
      $display("[EXCEPTION-DETECTION] *** Exception detected at cycle %0d (BEFORE flush) ***");
      $display("       IDEX instruction  = 0x%08h (in IDEX - used for mtval)");
      $display("       MSTATUS.FS        = %b (00=Off, 01=Initial, 10=Clean, 11=Dirty)");
      // ... full pipeline state
    end
  end
end
```

### Step 4: Debug Output Analysis

Ran FreeRTOS with enhanced debug (`TIMEOUT=10`):

#### Exception at Cycle 39,171 (First Exception)
```
[EXCEPTION-DETECTION] Cycle 39171 (BEFORE flush)
   IDEX instruction  = 0x00000073 (ECALL - legitimate)
   Exception code    = 11 (Environment call from M-mode)
   MSTATUS.FS        = 11 (Dirty)
```
✅ Legitimate ECALL - expected behavior.

#### Exception at Cycle 39,415 (Third Exception - The Problem)
```
[EXCEPTION-DETECTION] Cycle 39415 (BEFORE flush)
   PC (current)      = 0x00001f4a
   IFID PC           = 0x00001f48
   IDEX PC           = 0x00001f46
   IDEX instruction  = 0x00000013 ← **NOP in IDEX!**
   IDEX illegal_inst = 1          ← **Flagged as illegal!**
   Exception code    = 2           ← **Illegal instruction**
   MSTATUS.FS        = 11          ← **FPU enabled!**
   Control illegal   = 1           ← **Control module flagging NOP as illegal!**
   Flush signals     = ifid:1 idex:1
   Instruction type  = 32-bit (non-compressed)
   Opcode            = 0b0010011   ← **OP_IMM (ADDI)**
```

**Critical Findings**:
1. ❌ **Not an FPU instruction** - opcode is OP_IMM (ADDI), not LOAD_FP
2. ❌ **NOP flagged as illegal** - 0x00000013 (ADDI x0,x0,0) should ALWAYS be legal
3. ✅ **FPU enabled** - MSTATUS.FS=11, so FPU permission is NOT the issue
4. ❌ **Invalid PC** - 0x1f46 is in zero-filled gap after code section

### Step 5: Binary Verification

Used `xxd` to verify actual bytes in `.text` section:
```bash
$ xxd /tmp/freertos_text.bin | grep "^00001f40"
00001f40: c107 7300 2030 0000 0000 0000 0000 0000
          ^^^^ ^^^^^ ^^^^^
          1f40 1f42  1f44  1f46 onwards...
          ...  MRET  [gap of zeros]
```

**Confirmed**: Address 0x1f46 onwards contains zeros (not valid instructions).

---

## Root Cause Analysis

### The Real Problem: Invalid PC Execution

The CPU should NEVER execute address 0x1f46. Analysis of the trap handler:

```
1f3e:	07c10113          	addi	sp,sp,124
1f42:	30200073          	mret          ← Should jump via MEPC
	...                                   ← Zero-filled gap (0x1f46+)
```

**Expected behavior**: MRET at 0x1f42 should:
1. Restore privilege mode from MSTATUS.MPP
2. Restore interrupt enable from MSTATUS.MPIE
3. Jump to address stored in MEPC CSR
4. **NOT** fall through to 0x1f46

**Actual behavior**: PC somehow reaches 0x1f46, suggesting:
- MRET not executing correctly
- MEPC contains wrong value (0x1f46?)
- Exception handling corrupting PC flow

### Why Session 57's "FPU Workaround" Helped

Session 57 disabled FPU context save/restore (removed FLD/FSD from FreeRTOS):
- **Result**: FreeRTOS progressed from <1K cycles to 39K+ cycles
- **Why**: Removing FLD/FSD changed execution path enough to bypass OTHER bugs
- **Misleading**: Made it LOOK like FPU instructions were the problem
- **Reality**: Simply delayed hitting the MRET/exception handling bug

### Two Bugs Identified

1. **Bug #1: MRET Execution or MEPC Handling**
   - Location: Unknown (MRET implementation or exception handling)
   - Symptom: PC falls through to 0x1f46 instead of jumping via MEPC
   - Impact: CPU executes invalid memory (zeros)

2. **Bug #2: NOP Flagged as Illegal** (Secondary issue)
   - Location: `rtl/core/control.v` or instruction decode path
   - Symptom: Control module sets `illegal_inst=1` for 0x00000013 (NOP)
   - Impact: Legitimate NOPs trigger illegal instruction exceptions
   - Note: May be a symptom of corrupted instruction decode, not root cause

---

## Files Modified

### tb/integration/tb_freertos.v (lines 313-380)
**Purpose**: Enhanced exception debugging

**Changes**:
1. Added `[EXCEPTION-DETECTION]` monitor (lines 313-350)
   - Triggers on `exception_gated` (before pipeline flush)
   - Captures IDEX instruction, MSTATUS.FS, control signals
   - Shows instruction type (compressed vs 32-bit)

2. Modified `[TRAP-CSR-UPDATE]` monitor (lines 352-380)
   - Renamed from `[TRAP]` for clarity
   - Shows post-flush state for comparison

**Testing**: Successfully captured exception state showing NOP at 0x1f46.

### tests/asm/test_cfldsp.s (Created, not used)
**Purpose**: Minimal test for C.FLDSP instruction (abandoned)

**Status**: Created during investigation but not needed once root cause identified.

---

## Next Session Tasks

### Priority 1: MRET and Exception Handling

1. **Investigate MRET Implementation**
   - Check `rtl/core/rv32i_core_pipelined.v` MRET logic
   - Verify MEPC is correctly written during exception entry
   - Verify MEPC is correctly read and used by MRET
   - Check if MRET instruction itself is executing (not being flushed)

2. **Trace Exception Sequence**
   - Add debug output for MEPC writes
   - Monitor MRET instruction execution
   - Track PC updates during exception return
   - Identify where PC=0x1f46 comes from

3. **Check Second Exception** (cycle 39,371)
   - mepc = 0x1b40 (vTask1 function, legitimate code)
   - mcause = 11 (ECALL from M-mode)
   - May provide clues about exception handling state corruption

### Priority 2: NOP Illegal Instruction Bug

1. **Debug Control Module**
   - Why does `control.v` set `illegal_inst=1` for 0x00000013?
   - Check `id_illegal_inst_from_control` logic
   - Verify OP_IMM case handles all funct3 values

2. **Check Instruction Decode Path**
   - How does 0x00000000 (in memory) become 0x00000013 (in IDEX)?
   - Possible byte ordering issue?
   - Check instruction fetch and decode for invalid addresses

### Priority 3: Documentation Updates

1. Update `CLAUDE.md` with Session 61 summary
2. Update `CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md` - rename/redirect since NOT FPU issue
3. Consider renaming to `CRITICAL_MRET_EXCEPTION_HANDLING_ISSUE.md`

---

## Testing

### Regression Tests
```bash
$ make test-quick
14/14 tests passing ✅
```

All existing tests continue to pass. This is an FreeRTOS-specific issue exposed by complex exception handling scenarios.

### FreeRTOS Test
```bash
$ env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh
- Cycle 39,171: ECALL (legitimate) ✅
- Cycle 39,371: ECALL from trap handler (suspicious) ⚠️
- Cycle 39,415: Illegal instruction at 0x1f46 (invalid PC) ❌
```

---

## Key Insights

### What We Learned

1. **mtval Timing**: The `mtval` value is captured CORRECTLY - it shows what's actually in IDEX, which is legitimately a NOP because PC reached invalid memory.

2. **FPU Not The Problem**: MSTATUS.FS=11 throughout execution. FPU context save/restore is a red herring.

3. **Execution Path Matters**: Small changes (like removing FLD/FSD) can drastically change execution path and expose different bugs.

4. **Debug Before Flush**: Capturing exception state BEFORE pipeline flush is critical for accurate diagnosis.

### Lessons for Future Debugging

1. **Always verify memory contents** - Don't trust disassembly alone, check actual binary
2. **Monitor exception state early** - Capture signals at `exception_gated`, not after CSR update
3. **Check instruction legitimacy** - Verify the instruction SHOULD be at that address
4. **Trace execution flow backwards** - How did PC get to this address?

---

## Related Issues

### Active
- ⚠️ **MRET execution bug** (NEW - Priority: **CRITICAL**)
- ⚠️ **NOP flagged as illegal** (NEW - Priority: High)

### Deferred
- ⚠️ **FPU instruction decode** (Session 56-57) - Status: **NOT THE ISSUE**
  - Can re-enable FPU context save once MRET bug is fixed
  - Original symptoms were misleading (execution path side effect)

### Resolved
- ✅ Debug infrastructure (Session 59) - Works perfectly
- ✅ MULHU operand latch bug (Session 60) - Fixed
- ✅ Enhanced exception monitoring (Session 61) - Added

---

## References

- **Session 59**: Debug infrastructure implementation
- **Session 60**: MULHU operand latch bug fix
- **Session 57**: FPU workaround applied (misleading success)
- **Session 56**: MSTATUS.FS implementation

## Commands for Next Session

```bash
# Run FreeRTOS with enhanced debug
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | tee /tmp/freertos_debug.log

# Check exception detection output
grep -A 30 "EXCEPTION-DETECTION" /tmp/freertos_debug.log

# Verify binary contents at specific address
riscv64-unknown-elf-objcopy -O binary --only-section=.text \
  software/freertos/build/freertos-blinky.elf /tmp/freertos_text.bin
xxd /tmp/freertos_text.bin | grep "^00001f40"

# Disassemble around problematic address
riscv64-unknown-elf-objdump -d software/freertos/build/freertos-blinky.elf | \
  grep -A 10 -B 5 "1f42:"
```

---

**Session End**: 2025-10-29
**Next Priority**: Investigate MRET execution and exception handling logic
**Estimated Complexity**: High - requires careful analysis of exception flow
