# Next Session Quick Start Guide

## Current Status
- **Commit**: 835ca0f "Bugs #13-#18 Fixed: FPU Converter Infrastructure Overhaul"
- **Test Target**: rv32uf-p-fcvt (INT↔FP conversions)
- **Pass Rate**: RV32UF 4/11 (36%)

## Problem Summary

**Converter Works, But Results Don't Reach Destination**

The FP converter now produces mathematically correct values:
```
Input:  0x00000002 (integer 2)
Output: 0x40000000 (float 2.0) ✓
```

However, the test still fails because the FP register file never receives this value.

## Quick Reproduction

```bash
# Run fcvt test with debug
DEBUG_FPU_CONVERTER=1 ./tools/run_hex_tests.sh rv32uf-p-fcvt

# Check converter output
grep "CONVERTER.*DONE" sim/test_rv32uf-p-fcvt.log
# Should show: fp_result=0x40000000

# Check test result
grep "gp" sim/test_rv32uf-p-fcvt.log | tail -1
# Shows: x3 (gp) = 0x00000005 (fails at test #5)
```

## Investigation Path

### 1. Trace Writeback Path (PRIORITY)

Add debug to see where `fp_result=0x40000000` goes:

**Files to check:**
- `rtl/core/fpu.v` - Does FPU output the result?
- Pipeline WB stage - Does it write to FP register file?
- `rtl/core/fp_register_file.v` - Does register f10 get written?

**Key signals to trace:**
```verilog
// FPU outputs
fpu.fp_result       // Should be 0x40000000
fpu.done            // Should pulse for 1 cycle
fpu.busy            // Should be high during conversion

// Pipeline
wb_fp_wen           // FP register write enable
wb_fp_waddr         // Should be f10 (10)
wb_fp_wdata         // Should be 0x40000000
```

### 2. Check Multi-cycle Operation Handling

The converter takes 3 cycles (IDLE→CONVERT→ROUND→DONE). Verify:
- Pipeline stalls during converter operation (busy signal)
- done signal properly triggers writeback
- Result doesn't get flushed by branch/exception

### 3. Verify Test Itself

The test macro:
```assembly
TEST_INT_FP_OP_S( 2, fcvt.s.w, 2.0, 2)
# Expands to:
  li a0, 2
  fcvt.s.w f10, a0      # Convert 2 → f10
  fsflags x0            # Clear flags
  fmv.x.s a0, f10       # Move f10 → a0 for checking
  la a3, expected_data  # Load expected value
  lw a3, 0(a3)
  bne a0, a3, fail      # Compare
```

Check if:
- f10 contains 0x40000000 after fcvt.s.w
- a0 contains 0x40000000 after fmv.x.s
- a3 contains 0x40000000 (expected value)

## Debug Commands

```bash
# Add pipeline writeback debug
# In rtl/core/core_pipelined.v or wherever WB stage is:
`ifdef DEBUG_FPU_CONVERTER
if (wb_fp_wen) begin
  $display("[WB] FP write: f%d <= 0x%h", wb_fp_waddr, wb_fp_wdata);
end
`endif

# Rebuild and test
DEBUG_FPU_CONVERTER=1 ./tools/run_hex_tests.sh rv32uf-p-fcvt

# Check for FP register writes
grep "\[WB\] FP write" sim/test_rv32uf-p-fcvt.log
```

## Files to Examine

Priority order:
1. `rtl/core/core_pipelined.v` - Pipeline integration, WB stage
2. `rtl/core/control.v` - FPU operation control signals
3. `rtl/core/fp_register_file.v` - Register file writeback
4. `rtl/core/hazard_detection_unit.v` - Stall logic for FPU busy

## Expected Findings

Most likely issues:
1. **done signal not connected properly** - Result computed but never written
2. **Stall logic incorrect** - Pipeline advances before done asserts
3. **Write enable not set** - WB stage doesn't enable FP register write
4. **Address mismatch** - Writing to wrong FP register

## Success Criteria

When fixed, you should see:
```
[CONVERTER] DONE state: fp_result=0x40000000
[WB] FP write: f10 <= 0x40000000
[TEST] PASSED
```

And test should progress beyond test #5.

## Reference Documents

- **This session's work**: `docs/SESSION_2025-10-20_FPU_CONVERTER_DEBUG.md`
- **Bug history**: `PHASES.md` lines 449-482
- **FPU design**: `docs/FD_EXTENSION_DESIGN.md`

## Quick Test After Fix

```bash
# Test single fcvt test
./tools/run_hex_tests.sh rv32uf-p-fcvt

# If that passes, run full suite
./tools/run_hex_tests.sh rv32uf

# Check for improvement
# Current:  4/11 (36%)
# Expected: 5-6/11 (45-54%) if fcvt tests pass
```

## Notes

- Be patient and methodical - these are tough integration bugs
- Use waveforms if text debug isn't sufficient
- Converter bugs (#13-#18) are FIXED - don't debug converter again
- Focus entirely on the path AFTER converter produces result

---

Good luck! The converter works - you're one debug step away from passing fcvt tests!
