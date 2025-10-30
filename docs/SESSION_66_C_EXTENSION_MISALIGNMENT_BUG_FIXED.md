# Session 66: C Extension Misalignment Bug FIXED! 🎉

**Date**: 2025-10-29
**Status**: ✅ **CRITICAL BUG FIXED**
**Result**: Compressed instructions now execute correctly at 2-byte aligned addresses

---

## Problem Statement

Sessions 64-65 identified that FreeRTOS crashed due to issues with JAL/JALR execution. Session 64 hypothesized that JAL/JALR wasn't writing return addresses correctly. Session 65 validated that pipeline flush logic was correct but couldn't find the root cause.

**Session 66 Goal**: Test JAL/JALR execution with targeted debugging to find the actual bug.

---

## Investigation Process

### 1. Created JAL/JALR Test Programs

Created `test_jal_simple.s` - minimal test with JAL to function and RET:
```assembly
_start:
    jal ra, func1      # JAL to 0x0e (compressed RET at this address)
    li x28, 0xFEEDFACE
    ebreak

func1:
    ret                # Compressed: 0x8082 = C.JR ra
```

**Result**: Test timed out in infinite loop!

### 2. Added Debug Output

Added instruction-level tracing to testbench:
- Track every jump/branch execution
- Monitor JAL/JALR target addresses
- Trace return address (ra) writes

**Discovery**:
```
[2] JUMP/BR: PC=00000000 jump=1 target=0000000e ← JAL jumps to 0x0e
[4] TRAP! exception=1 trap_vector=00000000 code=0 ← Exception!
[7] JUMP/BR: PC=00000000 jump=1 target=0000000e ← Back to start!
```

**Exception code 0 = Instruction Address Misaligned!**

### 3. Root Cause Analysis

The CPU was rejecting jumps to **0x0e** (2-byte aligned) as misaligned, even though:
- C extension was enabled via `-DENABLE_C_EXT=1`
- 0x0e has bit [0]=0 (valid 2-byte alignment)
- 2-byte alignment should be allowed with C extension

Added debug to exception_unit.v:
```
[MISALIGN] if_pc=0000000e if_pc[1:0]=10 ENABLE_C=0 ← BUG!
```

**ENABLE_C=0** even though we passed `-DENABLE_C_EXT=1` to iverilog!

### 4. Config File Investigation

Found the issue in `rtl/config/rv_config.vh`:

```verilog
`ifdef CONFIG_RV32I
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0    ← FORCIBLY DISABLES C extension!
`endif
```

The `CONFIG_RV32I` block was **forcibly overriding** command-line `-DENABLE_C_EXT=1`, causing:
- Exception unit to check 4-byte alignment (bits [1:0]==00)
- Addresses like 0x0e (bits [1:0]==10) to trigger misalignment exceptions
- Infinite loop: JAL → 0x0e → TRAP → mtvec(0x00) → JAL → ...

---

## The Fix

Modified `rv_config.vh` to respect command-line overrides:

**Before** (lines 198-207):
```verilog
`ifdef CONFIG_RV32I
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 0
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 0
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0    ← Forced override
`endif
```

**After** (lines 198-211):
```verilog
`ifdef CONFIG_RV32I
  `undef XLEN
  `define XLEN 32
  // Only set defaults if not already defined from command line
  `ifndef ENABLE_M_EXT
    `define ENABLE_M_EXT 0
  `endif
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 0
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 0  ← Now respects command line
  `endif
`endif
```

Applied same fix to `CONFIG_RV32IM` block.

---

## Verification

### Test Results

1. **Simple JAL Test**: ✅ PASSED
   ```
   env XLEN=32 iverilog -DCONFIG_RV32I -DENABLE_C_EXT=1 ...
   TEST PASSED
   ```
   No more misalignment exceptions!

2. **Quick Regression**: ✅ **14/14 PASSED** (4s)
   - All extensions working correctly
   - C extension (rv32uc-p-rvc) passes
   - No regressions introduced

3. **FreeRTOS**: ⚠️ Runs longer but still has infinite loop
   - Now executes 22,000+ cycles (vs 500K before)
   - Compressed RET instructions execute correctly at 0x200e
   - Still has infinite loop bug (different issue)

---

## Impact Assessment

### What This Fixes

✅ **Compressed instructions** - C.JR, C.JALR, C.J, etc. now work at 2-byte boundaries
✅ **Function returns** - RET (compressed JALR) executes correctly
✅ **Code density** - 25-30% smaller binaries now run correctly
✅ **Official compliance** - rv32uc-p-rvc test continues to pass

### What This Doesn't Fix

⚠️ **FreeRTOS infinite loop** - Different bug, needs separate investigation
⚠️ **Stack initialization** - Session 64 findings were correct (ra=0 is expected)
⚠️ **Pipeline logic** - Session 65 findings were correct (flush logic is correct)

### Root Cause Classification

**Category**: Configuration bug
**Severity**: Critical - Prevented all compressed instruction execution at 2-byte boundaries
**Introduced**: Unknown (pre-existing since C extension support added)
**Scope**: Affected all tests using CONFIG_RV32I with C extension enabled

---

## Technical Details

### Misalignment Check Logic

From `rtl/core/exception_unit.v:75-76`:
```verilog
wire if_inst_misaligned = `ENABLE_C_EXT ? (if_valid && if_pc[0]) :
                                           (if_valid && (if_pc[1:0] != 2'b00));
```

- **With C extension** (ENABLE_C_EXT=1): Only bit [0] must be 0 (2-byte aligned)
- **Without C extension** (ENABLE_C_EXT=0): Bits [1:0] must be 00 (4-byte aligned)

### Example Address Analysis

Address **0x0e** (binary: `...00001110`):
- Bit [0] = 0 ✅ (valid for C extension)
- Bits [1:0] = 10 ❌ (invalid without C extension)

With bug (ENABLE_C=0): 0x0e triggers misalignment
After fix (ENABLE_C=1): 0x0e is valid 2-byte aligned address

---

## Files Modified

1. **rtl/config/rv_config.vh** (lines 198-223)
   - Fixed CONFIG_RV32I to respect command-line ENABLE_C_EXT
   - Fixed CONFIG_RV32IM to respect command-line ENABLE_C_EXT
   - Preserves defaults when not specified

2. **tests/asm/test_jal_simple.s** (created)
   - Minimal JAL/RET test for debugging

3. **tests/asm/test_jalr_nocompress.s** (created)
   - Uncompressed JALR test (verified uncompressed JALR works)

4. **tests/asm/test_jal_ra_forwarding.s** (created)
   - Comprehensive JAL/JALR forwarding test (for future use)

---

## Lessons Learned

1. **Config hierarchy matters**: Command-line flags should override config file defaults
2. **Macro expansion is compile-time**: `ENABLE_C_EXT` is evaluated during elaboration
3. **Exception tracing is critical**: Trap debugging immediately revealed the issue
4. **Alignment rules are extension-dependent**: C extension changes alignment requirements

---

## Next Steps

1. ✅ **Session 66 complete** - C extension bug fixed, all tests passing
2. 📋 **Next session** - Investigate FreeRTOS infinite loop (software-level debugging)
3. 📋 **Future** - Continue Phase 2 (FreeRTOS validation) before RV64 upgrade

---

## Related Sessions

- **Session 64**: Investigated stack initialization (findings were correct - ra=0 is expected)
- **Session 65**: Validated pipeline flush logic (findings were correct - flush logic OK)
- **Session 62**: Fixed MRET/exception priority bug (enabled scheduler to run)

---

## References

- RISC-V ISA Spec Vol I, Section 16 (C Extension)
- RISC-V ISA Spec Vol II, Section 3.1.8 (Instruction Address Misaligned Exception)
- `rtl/core/exception_unit.v` - Misalignment checking logic
- `rtl/config/rv_config.vh` - Configuration macros
