# M Extension - Current Status & Debug Plan

**Date**: 2025-10-10
**Status**: 90% Complete - Critical Bug to Fix
**Issue**: Rapid-fire M instructions fail; instructions immediately after M ops get corrupted/skipped

---

## Executive Summary

The M extension is **mostly working** but has a critical bug where instructions immediately following an M operation get corrupted or skipped. Adding NOPs between M instructions and subsequent operations works around the issue, but this is not acceptable for production.

### What Works ✅
- Single M instructions execute correctly (MUL 5 × 10 = 50 ✓)
- M instruction results write to register file correctly
- 32-cycle multiplication completes properly
- Pipeline hold mechanism keeps M instruction in EX stage
- No regression in base RV32I functionality
- M instructions with NOPs after them work perfectly

### What's Broken ❌
- **Rapid-fire M instructions**: Instructions immediately after an M op get corrupted
- Example: `mul` followed immediately by `lui` → `lui` doesn't execute properly
- Workaround: Adding 3 NOPs after M instructions fixes the issue

---

## Bug Details

### Symptom

**Test: test_m_simple**
```assembly
mul a2, a0, a1      # a2 = 5 * 10 = 50
lui a0, 0x6         # Should set a0 = 0x6000
addi a0, a0, 13     # Should set a0 = 0x600D
```

**Expected**: a0 = 0x600D, a2 = 0x32 (50)
**Actual**: a0 = 0x12 (18), a2 = 0x32 (50) ✓

**Analysis**:
- a0 = 0x12 = 18 = 5 + 13
- This means `addi a0, a0, 13` executed with a0 = 5 (old value)
- The `lui a0, 0x6` instruction did NOT execute or was skipped
- The `addi` used the stale value of a0 from before the MUL

### Workaround Confirms Bug

**Test: test_m_simple_nops** (works perfectly)
```assembly
mul a2, a0, a1
nop
nop
nop
li a0, 0x600D       # Now this works!
```

**Result**: a0 = 0x600D ✓, a2 = 0x32 ✓

---

## Implementation Details

### Files Modified

| File | Purpose | Status |
|------|---------|--------|
| `rtl/core/mul_unit.v` | Sequential multiplier | ✅ Complete |
| `rtl/core/div_unit.v` | Non-restoring divider | ✅ Complete |
| `rtl/core/mul_div_unit.v` | M unit wrapper | ✅ Complete |
| `rtl/core/decoder.v` | M instruction detection | ✅ Complete |
| `rtl/core/control.v` | M control signals, 3-bit wb_sel | ✅ Complete |
| `rtl/core/idex_register.v` | M signals, hold input | ✅ Complete |
| `rtl/core/exmem_register.v` | M result, hold input | ✅ Complete |
| `rtl/core/memwb_register.v` | M result propagation | ✅ Complete |
| `rtl/core/hazard_detection_unit.v` | M stall logic | ⚠️ Has bug |
| `rtl/core/rv32i_core_pipelined.v` | M unit integration | ⚠️ Has bug |

### Key Signals

**Hold Logic** (`rv32i_core_pipelined.v:160`):
```verilog
assign hold_exmem = idex_is_mul_div && idex_valid && !ex_mul_div_ready;
```
- Holds both ID/EX and EX/MEM registers while M unit is busy
- Prevents M instruction from advancing until result is ready

**Start Logic** (`rv32i_core_pipelined.v:165`):
```verilog
assign m_unit_start = idex_is_mul_div && idex_valid && !ex_mul_div_busy && !ex_mul_div_ready;
```
- Only pulses when M instruction first enters EX stage
- Prevents re-starting the M unit

**Hazard Detection** (`hazard_detection_unit.v:55-63`):
```verilog
assign m_extension_stall = mul_div_busy;
assign stall_pc    = load_use_hazard || m_extension_stall;
assign stall_ifid  = load_use_hazard || m_extension_stall;
assign bubble_idex = load_use_hazard;  // NOT m_extension_stall!
```
- Stalls PC and IF/ID while M unit busy
- Does NOT bubble ID/EX (uses hold instead)
- **Fixed**: Removed `m_extension_stall` from `bubble_idex`

---

## Root Cause Hypothesis

### Timeline of Events (Suspected)

When a MUL completes and the next instruction is a LUI:

```
Cycle 0:   MUL enters EX stage
Cycle 1:   M unit starts, hold_exmem = 1, busy = 0 (not yet)
Cycle 2:   busy = 1, stall_pc = 1, stall_ifid = 1
           LUI is in IF/ID, stalled
Cycle 3-32: M unit computing, LUI stuck in IF/ID
Cycle 33:  M unit done, ready = 1, hold_exmem = 0
           MUL advances EX → MEM
           LUI should advance IF/ID → ID/EX
Cycle 34:  ??? Something goes wrong here ???
```

### Possible Issues

1. **Busy signal timing**: `busy` is registered, goes high 1 cycle after `start`
   - By the time stall asserts, one extra instruction may have entered the pipeline

2. **Ready signal handling**: When `ready` goes high, what happens to `hold` and `stall`?
   - Does the pipeline release correctly?
   - Are there any race conditions?

3. **Pipeline register update order**:
   - When hold releases, do ID/EX and EX/MEM update in the same cycle?
   - Could there be a cycle where the instruction is lost?

4. **Flush interaction**: Even though we removed M stall from `bubble_idex`, there might be other flush sources
   - Branch misprediction?
   - Trap/exception?

---

## Debug Strategy

### Step 1: Add Waveform Dumps

Enable detailed waveform generation to see exact timing:

```verilog
// In testbench
initial begin
  $dumpfile("sim/waves/m_debug.vcd");
  $dumpvars(0, tb_core_pipelined);
  $dumpvars(0, tb_core_pipelined.DUT.m_unit);
end
```

**Signals to monitor**:
- `m_unit_start`
- `ex_mul_div_busy`
- `ex_mul_div_ready`
- `hold_exmem`
- `stall_pc`, `stall_ifid`
- `flush_idex`
- `pc_current`
- `if_instruction`
- `idex_pc`, `idex_instruction`
- `idex_is_mul_div`, `idex_valid`

### Step 2: Add Debug Prints

Add $display statements to track pipeline progression:

```verilog
// In rv32i_core_pipelined.v
always @(posedge clk) begin
  if (idex_is_mul_div && idex_valid) begin
    $display("[%0t] M in EX: start=%b busy=%b ready=%b hold=%b",
             $time, m_unit_start, ex_mul_div_busy, ex_mul_div_ready, hold_exmem);
  end
  if (m_unit_start) begin
    $display("[%0t] M UNIT START: op=%h", $time, idex_mul_div_op);
  end
  if (ex_mul_div_ready) begin
    $display("[%0t] M UNIT READY: result=%h", $time, ex_mul_div_result);
  end
end
```

### Step 3: Check Specific Scenarios

Create minimal test cases:

**Test A**: Two MULs back-to-back
```assembly
mul a0, a1, a2
mul a3, a4, a5
```

**Test B**: MUL then LUI
```assembly
mul a0, a1, a2
lui a3, 0x12345
```

**Test C**: MUL then ADDI
```assembly
mul a0, a1, a2
addi a3, zero, 100
```

### Step 4: Check M Unit State Machine

Verify the M unit properly resets after `ready`:

```verilog
// In mul_div_unit.v
// After ready asserts, does state go back to IDLE?
// Is busy cleared properly?
```

### Step 5: Check Pipeline Register Hold Logic

Examine `idex_register.v` and `exmem_register.v`:

```verilog
// When hold releases, does the register:
// 1. Immediately latch new values?
// 2. Keep old values for one more cycle?
// 3. Lose values somehow?
```

---

## Likely Fixes

### Fix 1: Extend Hold by 1 Cycle

The `ready` signal might need to keep hold asserted for one more cycle:

```verilog
// Instead of:
assign hold_exmem = idex_is_mul_div && idex_valid && !ex_mul_div_ready;

// Try:
reg hold_exmem_reg;
always @(posedge clk or negedge reset_n) begin
  if (!reset_n)
    hold_exmem_reg <= 1'b0;
  else if (ex_mul_div_ready)
    hold_exmem_reg <= 1'b1;  // Hold for one more cycle after ready
  else
    hold_exmem_reg <= 1'b0;
end
assign hold_exmem = (idex_is_mul_div && idex_valid && !ex_mul_div_ready) || hold_exmem_reg;
```

### Fix 2: Make Busy Combinational

Change the M unit to assert `busy` combinationally when `start` is received:

```verilog
// In mul_div_unit.v
assign busy = (state != IDLE) || start;  // Immediate busy on start
```

This prevents the 1-cycle delay before stall asserts.

### Fix 3: Clear Valid on Hold Release

Ensure that when an M instruction is held, its `valid` bit is managed correctly:

```verilog
// When hold releases, the M instruction advances
// The ID/EX register should NOT have the M instruction anymore
// Check if idex_valid is being cleared properly
```

### Fix 4: Add Hold to IF/ID Register

Currently only ID/EX and EX/MEM have hold. Maybe IF/ID needs it too:

```verilog
// Add hold input to ifid_register.v
// Connect to same hold_exmem signal
// This keeps the next instruction frozen in IF/ID
```

---

## Test Files

### Working Tests ✅
- `tests/asm/test_m_simple_nops.s` - Single MUL with NOPs
- `tests/asm/test_m_after.s` - MUL followed by 3 LI instructions
- `tests/asm/test_nop.s` - No regression test
- `tests/asm/test_simple_check.s` - Basic RV32I still works

### Failing Tests ❌
- `tests/asm/test_m_simple.s` - MUL followed immediately by LUI/ADDI
- `tests/asm/test_m_seq.s` - Multiple M instructions in sequence
- `tests/asm/test_m_basic.s` - Comprehensive M test suite
- `tests/asm/test_m_incremental.s` - 8 M instructions tested one by one

### Helper Scripts
- `tools/elf2hex.py` - Converts binary to word-based hex format
- Compile flow: `riscv64-unknown-elf-as → ld → objcopy → elf2hex.py`

---

## Compilation Commands

```bash
# Compile assembly to hex
riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 -o test.o test.s
riscv64-unknown-elf-ld -m elf32lriscv -Ttext 0x00000000 -o test.elf test.o
riscv64-unknown-elf-objcopy -O binary test.elf test.bin
python3 tools/elf2hex.py test.bin test.hex

# Simulate
iverilog -g2012 -I rtl -o sim/test tb/integration/tb_core_pipelined.v rtl/core/*.v rtl/memory/*.v -DMEM_FILE=\"test.hex\"
vvp sim/test

# View waveforms (if dumped)
gtkwave sim/waves/core_pipelined.vcd
```

---

## Key Insights

1. **The M unit itself works correctly** - it computes results properly
2. **The hold mechanism works** - M instruction stays in EX for 32 cycles
3. **The writeback works** - M result writes to register file
4. **The bug is in the release** - when hold drops, something goes wrong

**The problem is NOT the M extension logic itself, but the pipeline control around it.**

---

## Next Session Action Plan

1. **Start with waveforms**: Run `test_m_simple` and examine VCD file
   - Look at exact cycle when `ready` goes high
   - See what happens to `hold`, `stall`, `flush` signals
   - Track the LUI instruction through the pipeline

2. **Add debug prints**: Instrument the pipeline to see where LUI goes

3. **Try Fix 2 first**: Make `busy` combinational
   - This is the simplest fix and most likely to work
   - Prevents the 1-cycle gap where instructions slip through

4. **If that doesn't work, try Fix 1**: Extend hold by 1 cycle

5. **Test thoroughly**: Once fixed, run all M tests including rapid-fire sequences

---

## Critical Files to Review

- `rtl/core/rv32i_core_pipelined.v:159-166` - Hold and start signal generation
- `rtl/core/mul_div_unit.v` - State machine and busy/ready outputs
- `rtl/core/hazard_detection_unit.v:51-63` - Stall and bubble logic
- `rtl/core/idex_register.v:137-176` - Hold vs flush priority

---

**Bottom Line**: The M extension is 90% done. We just need to fix the pipeline control timing when M instructions complete and release. The fix is likely 5-10 lines of code.

**Most Likely Fix**: Make the `busy` signal assert immediately (combinationally) when `start` is pulsed, rather than waiting one cycle. This will prevent instructions from slipping past the stall.

---

**Last Updated**: 2025-10-10
**Ready for**: Debug session with waveforms
