# M Extension Debugging Status

**Date**: 2025-10-10
**Status**: Compilation Success - Runtime Issue Detected
**Issue**: M unit causing infinite pipeline stall

---

## Current Status

### ✅ Achievements
1. **CSR file bugs fixed** - Generate block access corrected
2. **Clean compilation** - Zero errors with Verilator
3. **Test programs created** - test_m_basic.s and test_nop.s
4. **Basic pipeline works** - NOP test runs (but times out at ebreak)

### ❌ Issues Found

#### Issue #1: Infinite Stall with M Instructions
**Symptom**: Test with M instructions hangs immediately
**Test**: `test_m_basic.s` times out after 2 minutes
**Control Test**: `test_nop.s` runs but doesn't detect ebreak properly

**Hypothesis**:
The M unit's `busy` signal is probably staying high indefinitely, causing the hazard detection unit to stall the entire pipeline forever.

**Likely Causes**:
1. M unit `start` signal might be pulsing continuously instead of one-shot
2. M unit state machine not transitioning properly
3. Ready signal not being generated correctly

---

## Debug Steps Taken

1. **Verilator Lint** - PASSED ✅
   - Fixed CSR file generate block bugs
   - No compilation errors
   - Only minor width warnings

2. **Test Compilation** - PASSED ✅
   ```bash
   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
       -nostdlib -Ttext=0x0 -o test_m_basic.elf test_m_basic.s
   ```

3. **Simulation Execution** - FAILED ❌
   - M test: Infinite hang
   - NOP test: Runs but doesn't stop at ebreak

---

## Root Cause Analysis

### M Unit Start Signal Issue

**Current Code** (rv32i_core_pipelined.v:551):
```verilog
mul_div_unit #(.XLEN(XLEN)) mul_div_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(idex_is_mul_div && idex_valid && !flush_idex),  // ← PROBLEM!
    ...
);
```

**Problem**: The `start` signal is a combinational signal that will be HIGH for multiple cycles while the instruction is in the EX stage and the M unit is busy. The M unit expects a single-cycle pulse to start operation.

**What Happens**:
1. M instruction enters EX stage
2. `idex_is_mul_div && idex_valid` becomes TRUE
3. M unit starts operation, sets `busy = 1`
4. Pipeline stalls (PC, IF/ID frozen)
5. But the same M instruction stays in EX stage (ID/EX not flushed)
6. `start` signal remains HIGH continuously
7. M unit might be restarting every cycle or stuck in IDLE

### Solution Options

#### Option 1: Edge Detection (Preferred)
Add a register to detect rising edge of start condition:
```verilog
reg idex_is_mul_div_r;
always @(posedge clk) begin
    if (!reset_n)
        idex_is_mul_div_r <= 1'b0;
    else
        idex_is_mul_div_r <= idex_is_mul_div && idex_valid && !flush_idex;
end

wire mul_div_start_pulse = (idex_is_mul_div && idex_valid && !flush_idex) &&
                            !idex_is_mul_div_r;
```

#### Option 2: Modify M Unit
Change M unit to only accept `start` when in IDLE state:
```verilog
// Inside mul_div_unit
wire start_accepted = start && !busy;
```

#### Option 3: Use `ready` Signal
Only start if M unit signals ready (not busy):
```verilog
.start(idex_is_mul_div && idex_valid && !flush_idex && !ex_mul_div_busy)
```

---

## Secondary Issue: EBREAK Not Stopping Simulation

**Symptom**: NOP test runs for 9999 cycles then times out
**Expected**: Should stop after ~10 cycles when ebreak is reached

**Possible Causes**:
1. Exception unit not detecting ebreak properly
2. Testbench not monitoring exception signal
3. Simulation termination logic not working

**Lower Priority**: Focus on M unit issue first

---

## Next Actions

### Immediate (High Priority)
1. **Fix M unit start signal** - Implement edge detection
2. **Recompile and test**
3. **Verify M unit state machine with waveforms**

### Medium Priority
4. **Debug ebreak detection** - Check exception unit
5. **Add debug printfs** - Monitor M unit state transitions
6. **Test with simple MUL** - Single instruction test

### Low Priority
7. **Fix width warnings** - Clean up M unit width mismatches
8. **Optimize stall logic** - Consider pipelining M unit better

---

## Test Status

| Test | Compile | Run | Pass | Notes |
|------|---------|-----|------|-------|
| test_nop.s | ✅ | ⚠️ | ❌ | Runs but doesn't stop |
| test_m_basic.s | ✅ | ❌ | ❌ | Infinite hang |

---

## Modified Files (This Session)

1. **rtl/core/csr_file.v** - Fixed generate block access
   - Lines 82-89: misa signal moved outside generate
   - Lines 136-159: mstatus_value moved outside generate
   - Lines 164-165: Direct signal access instead of dotted notation

2. **tests/asm/test_m_basic.s** - Created comprehensive M test
   - 12 test cases covering MUL, DIV, REM variants
   - Edge cases: divide by zero, overflow
   - ~83 instructions

3. **tests/asm/test_nop.s** - Created minimal pipeline test
   - Simple 6-instruction test
   - Verifies pipeline still functional

---

## Recommended Fix (Detailed)

### File: `rtl/core/rv32i_core_pipelined.v`

**Add before M unit instantiation** (around line 545):
```verilog
  // M Unit Start Pulse Generation
  // We need a single-cycle pulse to start the M unit.
  // The problem: idex_is_mul_div stays high while M unit is busy,
  // causing continuous re-triggering.
  // Solution: Edge detection - only trigger on transition to M instruction.

  reg  idex_is_mul_div_r;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      idex_is_mul_div_r <= 1'b0;
    else if (flush_idex)
      idex_is_mul_div_r <= 1'b0;
    else
      idex_is_mul_div_r <= idex_is_mul_div && idex_valid;
  end

  // Generate start pulse only on rising edge (new M instruction entering EX)
  wire mul_div_start = (idex_is_mul_div && idex_valid && !idex_is_mul_div_r);
```

**Update M unit instantiation** (line 551):
```verilog
mul_div_unit #(
    .XLEN(XLEN)
  ) mul_div_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(mul_div_start),  // ← Changed from combinational to pulse
    .operation(idex_mul_div_op),
    .is_word_op(idex_is_word_op),
    .operand_a(ex_alu_operand_a_forwarded),
    .operand_b(ex_rs2_data_forwarded),
    .result(ex_mul_div_result),
    .busy(ex_mul_div_busy),
    .ready(ex_mul_div_ready)
  );
```

---

## Verification Plan

### After Fix:
1. Recompile with Verilator
2. Run test_nop.s - should still timeout (ebreak issue separate)
3. Run test_m_basic.s - should complete (might timeout at ebreak but should finish M ops)
4. Check waveforms for:
   - `mul_div_start` - should be single-cycle pulse
   - `ex_mul_div_busy` - should go high for 32 cycles then low
   - `stall_pc` - should match busy period
   - Pipeline drain after M instruction completes

### Expected Behavior:
```
Cycle 0-5:    Normal instructions (li, etc.)
Cycle 6:      First MUL enters EX stage
Cycle 6:      mul_div_start pulses HIGH for 1 cycle
Cycle 6-37:   ex_mul_div_busy = HIGH (32 cycles)
Cycle 6-37:   Pipeline stalled
Cycle 38:     ex_mul_div_ready = HIGH, result available
Cycle 38:     Pipeline resumes
```

---

## Lessons Learned

1. **Multi-cycle units need careful start logic** - Can't just use level signals
2. **Test incrementally** - NOP test revealed pipeline still works
3. **Generate blocks in Verilog** - Can't use dotted notation with ternary operators
4. **Timeout is a debugging tool** - Helped identify infinite stall quickly

---

## Files to Monitor

When running with waveforms:
```
gtkwave sim/waves/core_pipelined.vcd

Signals to add:
- DUT.clk
- DUT.pc_current
- DUT.idex_is_mul_div
- DUT.idex_is_mul_div_r (after fix)
- DUT.mul_div_start (after fix)
- DUT.ex_mul_div_busy
- DUT.ex_mul_div_ready
- DUT.stall_pc
- DUT.idex_valid
- DUT.flush_idex
```

---

**Status**: Ready to implement fix
**Estimated Time**: 15 minutes to fix + 5 minutes to test
**Confidence**: High - root cause identified

---

**Last Updated**: 2025-10-10
**Next Step**: Implement start pulse generation in rv32i_core_pipelined.v
