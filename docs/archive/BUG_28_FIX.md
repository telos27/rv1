# Bug #28 Fix: FP Load-Use Hazard

**Date**: 2025-10-21
**Status**: FIXED
**Severity**: Critical - Incorrect FPU results for FLW→FCVT sequences

## Problem Description

When a floating-point load (FLW) was immediately followed by a floating-point conversion (FCVT), the conversion would produce incorrect results (often 0) instead of converting the loaded value correctly.

### Example Failure
```assembly
la x1, data
flw f1, 0(x1)      # Load 2.0 (0x40000000) into f1
fcvt.w.s x2, f1    # Convert f1 to integer
# Expected: x2 = 2
# Actual:   x2 = 0
```

## Root Cause Analysis

Through detailed cycle-by-cycle tracing, three interconnected issues were identified:

### 1. FP Register File Missing Internal Forwarding

The FP register file (`rtl/core/fp_register_file.v`) had combinational reads without internal forwarding:

```verilog
// OLD: No forwarding
assign rs1_data = registers[rs1_addr];
```

Unlike the integer register file which has:
```verilog
assign rs1_data = (rd_wen && (rd_addr == rs1_addr)) ? rd_data : registers[rs1_addr];
```

This meant when FLW wrote to f1 in WB stage and FCVT read f1 in ID stage during the same cycle, FCVT would read the old (stale) value from the register array instead of the new value being written.

### 2. FP Converter Didn't Latch Operands

The FP converter (`rtl/core/fp_converter.v`) sampled its input operands directly from its input ports:

```verilog
// In CONVERT state
sign_fp = fp_operand[FLEN-1];
exp_fp = fp_operand[FLEN-2:MAN_WIDTH];
```

When the FCVT instruction remained in EX stage for multiple cycles (due to FPU busy), the converter could be started multiple times with different operand values:
- First start: operands correct (internal forwarding in FP register file worked)
- Second start: operands stale (FLW has left WB stage, no forwarding)

### 3. FP Converter Busy Signal Timing

The converter's busy signal:
```verilog
busy = (state != IDLE) && (state != DONE);
```

This meant busy=0 during DONE state, allowing the FPU start signal to trigger again before the FCVT instruction left the EX stage:

```
Cycle N:   IDLE, start=1 → CONVERT (busy=1, operands=0x40000000 ✓)
Cycle N+1: CONVERT → ROUND (busy=1)
Cycle N+2: ROUND → DONE (busy=0, done=1)
Cycle N+3: DONE → IDLE (busy=0), if start still=1 → CONVERT (operands=0x00000000 ✗)
```

## Solution

### Fix 1: Add Internal Forwarding to FP Register File

Added forwarding logic similar to integer register file:

```verilog
// New: With internal forwarding
wire [FLEN-1:0] wr_data_boxed;
assign wr_data_boxed = (FLEN == 64 && write_single) ? 
                       {32'hFFFFFFFF, rd_data[31:0]} : rd_data;

assign rs1_data = (wr_en && (rd_addr == rs1_addr)) ? wr_data_boxed : registers[rs1_addr];
assign rs2_data = (wr_en && (rd_addr == rs2_addr)) ? wr_data_boxed : registers[rs2_addr];
assign rs3_data = (wr_en && (rd_addr == rs3_addr)) ? wr_data_boxed : registers[rs3_addr];
```

This ensures correct value is forwarded when reading a register being written in the same cycle, including proper NaN boxing for single-precision values.

### Fix 2: Latch Operands in FP Converter

Added registers to latch input operands when conversion starts:

```verilog
reg [XLEN-1:0] int_operand_latched;
reg [FLEN-1:0] fp_operand_latched;
reg [3:0] operation_latched;
reg [2:0] rounding_mode_latched;

always @(posedge clk) begin
  if (state == IDLE && start) begin
    int_operand_latched <= int_operand;
    fp_operand_latched <= fp_operand;
    operation_latched <= operation;
    rounding_mode_latched <= rounding_mode;
  end
end
```

Modified CONVERT and ROUND states to use `*_latched` versions instead of direct inputs. This prevents re-sampling if the FPU start signal is asserted multiple times.

### Fix 3: Keep Busy High During DONE State

Modified busy signal to prevent immediate restart:

```verilog
// New: Keep busy=1 during DONE state
busy = (state != IDLE);
```

This ensures the FPU won't accept a new start signal until the current operation fully completes and returns to IDLE state.

## Files Modified

1. `rtl/core/fp_register_file.v`
   - Lines 32-41: Added NaN-boxed write data wire and internal forwarding logic
   - Lines 43-55: Added debug output for forwarding
   - Lines 53-60: Simplified write logic to use boxed data wire

2. `rtl/core/fp_converter.v`
   - Lines 77-92: Added latched operand registers and effective operand wires
   - Lines 94-123: Modified state machine to latch inputs on start
   - Line 141: Changed busy signal to include DONE state
   - Throughout CONVERT/ROUND states: Replaced direct operand references with latched versions

## Test Results

### Before Fix
```
test_minimal_hazard: x2 = 0x00000000 (expected 0x00000002) ✗ FAIL
test_flw_fcvt_hazard: x10 = 0x00000000 (expected 0x00000001) ✗ FAIL
```

### After Fix
```
test_minimal_hazard: x2 = 0x00000002 ✓ PASS
test_flw_fcvt_hazard: x10 = 0x00000001 ✓ PASS
```

## Remaining Work

The official RISC-V compliance test `rv32uf-p-fcvt_w` still fails at test 17. This may be:
- A different edge case not covered by the basic FLW→FCVT hazard
- A test harness issue
- An unrelated bug

Further investigation needed in next session.

## Lessons Learned

1. **Forwarding must be consistent** - If integer register file has internal forwarding, FP register file should too
2. **Operand stability** - Multi-cycle operations should latch inputs to avoid timing-dependent bugs
3. **Busy signal timing** - Must prevent restart until operation truly completes
4. **Test coverage** - Simple directed tests caught the bug that compliance tests exposed

## References

- Related: Bug #26 (FP→INT rounding), Bug #27 (fractional value rounding)
- RISC-V ISA: Section on pipeline hazards and forwarding
- Test cases: `tests/asm/test_minimal_hazard.s`, `tests/asm/test_flw_fcvt_hazard.s`
