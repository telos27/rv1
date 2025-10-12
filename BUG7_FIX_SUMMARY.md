# Bug #7 Fix: FP-to-INT Write-Back Path

**Date**: 2025-10-11 (Session 22)
**Severity**: CRITICAL
**Status**: ✅ FIXED

## Problem Description

All FP-to-INT operations were returning zero instead of their actual results:
- FP compare operations (FEQ.S, FLT.S, FLE.S)
- FP classify (FCLASS.S)
- FP move to integer (FMV.X.W)
- FP-to-INT conversions (FCVT.W.S, FCVT.WU.S)

### Symptom

When executing `feq.s a1, ft0, ft1` where ft0=1.0 and ft1=1.0:
- **Expected**: a1 = 1 (true, they are equal)
- **Actual**: a1 = 0 (incorrect)

This caused all FP compare tests to fail.

## Root Causes

### Root Cause #1: Missing wb_sel Assignment
The control unit was not setting the write-back selector for FP-to-INT operations.

**Location**: `rtl/core/control.v`

**Problem**: For FP compare/classify/move/convert operations, `int_reg_write_fp` was set to 1, but `wb_sel` remained at default value (3'b000 = ALU result), so the wrong data was selected for write-back.

### Root Cause #2: Missing Write-Back Multiplexer Case
The write-back data multiplexer didn't have a case for FPU integer results.

**Location**: `rtl/core/rv32i_core_pipelined.v:1204-1210`

**Problem**: The `wb_data` assignment had cases for:
- 3'b000: ALU result
- 3'b001: Memory data
- 3'b010: PC+4
- 3'b011: CSR data
- 3'b100: M extension result
- 3'b101: A extension result

But was missing:
- 3'b110: FPU integer result (`memwb_int_result_fp`)

### Root Cause #3: Missing Register Write Enable
The integer register file write enable didn't include FP-to-INT operations.

**Location**: `rtl/core/rv32i_core_pipelined.v:516`

**Problem**: Register file write enable was only `memwb_reg_write`, but FP-to-INT operations set `memwb_int_reg_write_fp` instead.

### Root Cause #4: Missing Forwarding Logic
WB-to-ID forwarding didn't account for FP-to-INT write-back.

**Location**: `rtl/core/rv32i_core_pipelined.v:523, 526`

**Problem**: Forwarding checks only looked at `memwb_reg_write`, missing FP-to-INT operations that set `memwb_int_reg_write_fp`.

## Fixes Applied

### Fix #1: Add wb_sel for FP Compare Operations
**File**: `rtl/core/control.v:456`

```verilog
5'b10100: begin  // FEQ.S/D, FLT.S/D, FLE.S/D (comparisons)
  int_reg_write_fp = 1'b1;  // Write result to integer register
  fp_alu_en = 1'b1;
  fp_alu_op = FP_CMP;
  wb_sel = 3'b110;         // Write-back from FPU integer result  <-- ADDED
end
```

### Fix #2: Add wb_sel for FMV.X.W and FCLASS
**File**: `rtl/core/control.v:460`

```verilog
5'b11100: begin  // FMV.X.W/D, FCLASS.S/D
  int_reg_write_fp = 1'b1;  // Write to integer register
  wb_sel = 3'b110;         // Write-back from FPU integer result  <-- ADDED
  if (funct3 == 3'b000) begin
    fp_alu_op = FP_MV_XW;  // FMV.X.W/D
  ...
```

### Fix #3: Add wb_sel for FCVT FP-to-INT
**File**: `rtl/core/control.v:437`

```verilog
if (funct7[6] == 1'b1) begin
  // FCVT.W.S/D, FCVT.WU.S/D, FCVT.L.S/D, FCVT.LU.S/D (FP to int)
  int_reg_write_fp = 1'b1;  // Write to integer register
  wb_sel = 3'b110;         // Write-back from FPU integer result  <-- ADDED
end
```

### Fix #4: Add FPU Integer Result to Write-Back Multiplexer
**File**: `rtl/core/rv32i_core_pipelined.v:1210`

```verilog
assign wb_data = (memwb_wb_sel == 3'b000) ? memwb_alu_result :
                 (memwb_wb_sel == 3'b001) ? memwb_mem_read_data :
                 (memwb_wb_sel == 3'b010) ? memwb_pc_plus_4 :
                 (memwb_wb_sel == 3'b011) ? memwb_csr_rdata :
                 (memwb_wb_sel == 3'b100) ? memwb_mul_div_result :
                 (memwb_wb_sel == 3'b101) ? memwb_atomic_result :
                 (memwb_wb_sel == 3'b110) ? memwb_int_result_fp :  // <-- ADDED
                 {XLEN{1'b0}};
```

### Fix #5: Update Register File Write Enable
**File**: `rtl/core/rv32i_core_pipelined.v:516`

```verilog
register_file #(
  .XLEN(XLEN)
) regfile (
  ...
  .rd_wen(memwb_reg_write | memwb_int_reg_write_fp),  // <-- CHANGED
  ...
);
```

### Fix #6: Update WB-to-ID Forwarding
**File**: `rtl/core/rv32i_core_pipelined.v:523, 526`

```verilog
assign id_rs1_data = ((memwb_reg_write | memwb_int_reg_write_fp) && ...  // <-- CHANGED
                     ? wb_data : id_rs1_data_raw;

assign id_rs2_data = ((memwb_reg_write | memwb_int_reg_write_fp) && ...  // <-- CHANGED
                     ? wb_data : id_rs2_data_raw;
```

## Verification

### Test Case: Simple FEQ
**Test**: `test_fp_compare_simple.s`

```assembly
flw f0, 0(a0)      # f0 = 1.0
flw f1, 4(a0)      # f1 = 1.0
feq.s a1, f0, f1   # a1 = (1.0 == 1.0) = 1
```

**Before Fix**:
- a1 = 0 (incorrect)
- Test FAILED with marker 0xDEADDEAD

**After Fix**:
- a1 = 1 (correct!)
- Test PASSED with marker 0xFEEDFACE ✅

## Impact

This fix enables ALL FP-to-INT operations:

1. **FP Compare Operations** (3 instructions):
   - FEQ.S/D: Floating-point equal
   - FLT.S/D: Floating-point less than
   - FLE.S/D: Floating-point less than or equal

2. **FP Classify** (1 instruction):
   - FCLASS.S/D: Classify floating-point value

3. **FP Move to Integer** (1 instruction):
   - FMV.X.W/D.X: Move FP register to integer register

4. **FP-to-INT Conversion** (4 instructions):
   - FCVT.W.S/D: Convert FP to signed 32-bit int
   - FCVT.WU.S/D: Convert FP to unsigned 32-bit int
   - FCVT.L.S/D: Convert FP to signed 64-bit int
   - FCVT.LU.S/D: Convert FP to unsigned 64-bit int

**Total**: 9 instructions now functional!

## Files Modified

1. `rtl/core/control.v` - 3 additions (lines 437, 456, 460)
2. `rtl/core/rv32i_core_pipelined.v` - 4 modifications (lines 516, 523, 526, 1210)
3. `PHASES.md` - Documentation updated
4. `tests/asm/test_fp_compare_simple.s` - Test case created

## Lessons Learned

1. **Signal Naming**: The signal `int_reg_write_fp` existed and was piped through all pipeline stages, but was never actually used for register writes. Better naming or documentation could have caught this earlier.

2. **Write-Back Path Completeness**: When adding new result sources (like FPU integer results), need to update:
   - Control unit (wb_sel assignment)
   - Write-back multiplexer (new case)
   - Register write enable (OR with new signal)
   - Forwarding logic (include new signal in conditions)

3. **Testing Strategy**: Simple, focused tests (like `test_fp_compare_simple.s`) are invaluable for isolating specific bugs. The complex test with many operations masked the root cause.

## Related Issues

This fix also resolves the previously reported issue with FMV.X.W returning zeros (mentioned in PHASES.md line 39 from Session 21).
