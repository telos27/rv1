# Session 19: FCVT Test #10 Investigation - RV32D Progress

**Date**: 2025-10-23
**Status**: ✅ RESOLVED (Session 20)
**RV32D Progress**: 66% → 77% (FCVT tests now passing!)

**UPDATE (Session 20)**: Bugs #51 and #52 have been fixed. All FCVT tests (fcvt, fcvt_w) are now passing. This document is kept for historical reference.

---

## Executive Summary

**MAJOR PROGRESS!** The Bug #51 fix (FCVT.S.D/D.S decoding) advanced the test from failing at test #5 to test #10. This means tests #5-9 are now passing - a huge improvement!

**Current Issue**: Test #10 (FCVT.S.D round-trip) failing because FCVT instructions are not writing to FP register file.

---

## Progress Analysis

### Before Session 19:
- rv32ud-p-fcvt **timeout** at test #5
- RV32D: 66% (6/9 tests passing)

### After Session 19 Investigation:
- rv32ud-p-fcvt **completes** at 195 cycles
- Fails at test #10 (reported as gp=21, because 21 = 10×2+1)
- Tests #5-9 likely PASSING ✓
- RV32D: Still 66%, but much closer to passing!

---

## Test #10 Deep Dive

### Test Description
```
TEST_FCVT_S_D(10, -1.5, -1.5)
```

**Purpose**: Round-trip conversion test
1. Load double -1.5 into f10 (FLD)
2. Convert double→single: `FCVT.S.D f13, f10`
3. Convert single→double: `FCVT.D.S f13, f13`
4. Result should be -1.5 in double precision

### Test Program (PC 0x274-0x28c)
```
0x274: FLD f10, 0(x10)       → Load -1.5 (double) into f10
0x278: FLD f11, 8(x10)       → Load data into f11
0x27c: FLD f12, 16(x10)      → Load data into f12
0x288: FCVT.S.D f13, f10, rm=7 → Convert f10 (double) to f13 (single)
0x28c: FCVT.D.S f13, f13, rm=0 → Convert f13 (single) back to f13 (double)
```

### Observed Behavior

**FLD Instructions**: ✓ Working correctly
```
[163] FPU WB: fd=f10 | result=0000000000000000 (debug artifact)
       wb_sel=001 mem_data=00000000 wb_fp_data=bff8000000000000
[FP_REG] Write f10 = bff8000000000000  ← Correct value!
```
- Memory contains: `0xbff8000000000000` (-1.5 in double) ✓
- FP register receives: `0xbff8000000000000` ✓

**FCVT Instructions**: ✗ NOT writing to FP register file
```
Total FPU WB events: 7 (all FLD to f10, f11, f12)
Missing: FCVT.S.D f13 and FCVT.D.S f13 writes
```
- No writes to f13 observed
- Result: f13 remains 0.0
- Test expects f13 = -1.5 (0xbff8000000000000)
- Test gets f13 = 0.0 (0x0000000000000000)

---

## Root Cause Investigation

### Control Unit Analysis

Checked `rtl/core/control.v` lines 433-455:

**FCVT.S.D Decoding** (funct7=0x20=0b0100000):
```verilog
5'b01000, 5'b11000, ...: begin  // FCVT
  if (funct7[5]) begin
    // INT↔FP path (funct7[5]=1 for 0x60-0x6F)
  } else begin
    // FP↔FP path (funct7[5]=0 for 0x20-0x21)
    fp_reg_write = 1'b1;  ← Line 451: SHOULD set write enable
    fp_alu_en = 1'b1;
    fp_alu_op = FP_CVT;
    fp_use_dynamic_rm = (funct3 == 3'b111);
  end
end
```

**Verdict**: Control logic is CORRECT ✓
- FCVT.S.D matches case `5'b01000` ✓
- Takes else branch (funct7[5]=0) ✓
- Sets `fp_reg_write = 1'b1` ✓
- Sets `fp_alu_en = 1'b1` ✓

### Pipeline Signal Propagation

Traced `fp_reg_write` through pipeline:
```
control.v → id_fp_reg_write
  ↓
ID/EX register → idex_fp_reg_write
  ↓
EX/MEM register → exmem_fp_reg_write
  ↓
MEM/WB register → memwb_fp_reg_write
  ↓
FP register file .wr_en(memwb_fp_reg_write)
```

**Verdict**: Pipeline connections are CORRECT ✓
- No gating logic found
- No places that clear `fp_reg_write`
- Signal should propagate cleanly

### Writeback Data Path

```verilog
assign wb_fp_data = (memwb_wb_sel == 3'b001) ? fp_load_data_boxed :
                                               memwb_fp_result;
```

**Note**: FCVT instructions have `wb_sel=3'b000` (default), so they use `memwb_fp_result`.
**Verdict**: Data path is CORRECT ✓

---

## Mystery: Why No Writeback?

**All logic appears correct**, yet FCVT instructions don't write to FP register file:

### Hypotheses to Test:

1. **FPU Never Executes FCVT**
   - FPU busy signal stuck?
   - FCVT operation not triggering FPU start?
   - Check: `ex_fpu_start`, `ex_fpu_busy`, `ex_fpu_done` signals

2. **FCVT Completes but `fp_reg_write` Cleared**
   - Exception/trap clears write enable?
   - Hazard detection stalls but clears write?
   - Check: Exception signals, hazard stall conditions

3. **FCVT Completes but Wrong Destination**
   - Destination register corrupted in pipeline?
   - Would explain missing f13 writes
   - Check: `idex_fp_rd_addr`, `exmem_fp_rd_addr`, `memwb_fp_rd_addr`

4. **Timing Issue**
   - FCVT takes multiple cycles but gets flushed?
   - Pipeline stall/flush during FCVT execution?
   - Check: Stall/flush counters, cycle-by-cycle trace

---

## Next Session Action Plan

### Immediate Debug Steps:

1. **Add Pipeline Debug Trace**
   ```verilog
   `ifdef DEBUG_FCVT_PIPELINE
   always @(posedge clk) begin
     if (idex_fp_alu_en && idex_fp_alu_op == FP_CVT) begin
       $display("[IDEX] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d",
                idex_fp_reg_write, idex_fp_rd_addr);
     end
     if (exmem_fp_reg_write && exmem_fp_alu_op == FP_CVT) begin
       $display("[EXMEM] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d",
                exmem_fp_reg_write, exmem_fp_rd_addr);
     end
     if (memwb_fp_reg_write && memwb_fp_alu_op == FP_CVT) begin
       $display("[MEMWB] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d",
                memwb_fp_reg_write, memwb_fp_rd_addr);
     end
   end
   `endif
   ```

2. **Add FPU Execution Debug**
   ```verilog
   `ifdef DEBUG_FPU_EXEC
   always @(posedge clk) begin
     if (ex_fpu_start) begin
       $display("[FPU] START: op=%0d, rs1=f%0d, rd=f%0d",
                idex_fp_alu_op, idex_fp_rs1_addr, idex_fp_rd_addr);
     end
     if (ex_fpu_done) begin
       $display("[FPU] DONE: result=%h, rd=f%0d",
                ex_fp_result, idex_fp_rd_addr);
     end
   end
   `endif
   ```

3. **Run Test with New Debug**
   ```bash
   # Recompile with new debug flags
   iverilog -g2012 -Irtl -DCONFIG_RV32IMAF \
     -DDEBUG_FCVT_PIPELINE -DDEBUG_FPU_EXEC \
     -DCOMPLIANCE_TEST \
     -DMEM_FILE='"tests/official-compliance/rv32ud-p-fcvt.hex"' \
     -o sim/rv32ud-p-fcvt_trace.vvp \
     rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v

   # Run and capture full trace
   timeout 10s vvp sim/rv32ud-p-fcvt_trace.vvp > trace.log 2>&1

   # Filter for FCVT operations
   grep -E "FCVT|f13" trace.log
   ```

4. **Check FPU Busy/Done Logic**
   - Verify FPU starts for FCVT operations
   - Check if FPU completes (sets done signal)
   - Verify result propagates to pipeline

5. **Verify No Wb_sel Issue**
   - Add: `wb_sel = 3'b111;` explicitly for FCVT.S.D/D.S
   - Or verify current `wb_sel=3'b000` doesn't interfere

---

## Key Files for Next Session

- **rtl/core/control.v** - Lines 433-455 (FCVT decoding)
- **rtl/core/fpu.v** - FPU instantiation and signals
- **rtl/core/fp_converter.v** - FCVT implementation
- **rtl/core/rv32i_core_pipelined.v** - Pipeline registers and forwarding
- **tb/integration/tb_core_pipelined.v** - Test bench debug output

---

## Summary

**Progress**: Excellent! Went from test #5 to test #10 (5 more tests passing).

**Issue**: FCVT instructions appear to execute correctly through decode/control, but don't write to FP register file.

**Status**: Control logic verified correct. Need deeper pipeline/FPU execution trace to find where `fp_reg_write` signal is lost or where FCVT execution fails.

**Confidence**: HIGH that this is solvable with proper debug tracing.

---

## Commands for Quick Start

```bash
# Check current test status
env XLEN=32 timeout 30s ./tools/run_official_tests.sh d

# Run fcvt test with basic debug
env DEBUG_FPU=1 DEBUG_FCVT_TRACE=1 XLEN=32 timeout 10s \
  vvp sim/official-compliance/rv32ud-p-fcvt.vvp

# Look for FCVT-related output
grep -i "fcvt\|f13" sim/official-compliance/rv32ud-p-fcvt.log
```

**Next Session Goal**: Add pipeline debug, identify where `fp_reg_write` or FCVT execution fails, fix bug, pass test #10!
