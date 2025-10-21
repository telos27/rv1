# Bug #22: FP-to-INT Forwarding Missing

**Status**: FIXED
**Date**: 2025-10-21
**Severity**: Critical
**Component**: Forwarding Unit, Core Pipeline

## Summary

The forwarding unit did not properly forward results from FP-to-INT instructions (FMV.X.W, FCVT.W.S, FCVT.WU.S, FP compare, FCLASS) to subsequent integer instructions. This caused data hazards where integer instructions using registers written by FP-to-INT operations would receive stale values instead of the correct forwarded results.

## Symptoms

- rv32uf-p-fcvt test failed at test_5
- Branch instructions immediately following FMV.X.W received incorrect operand values
- Test sequence showed only test_2 executing, with tests 3-6 being skipped due to incorrect branch decisions

## Root Cause Analysis

### Investigation Process

1. **Initial Observation**: Test failed at test_5 with only test_2 actually executing FCVT instruction
2. **Hypothesis 1**: Branch flush bug (branches taken but execution continues)
3. **Discovery**: Branch at test_2 was incorrectly taken to FAIL handler
4. **Key Finding**: Branch operand showed `rs1_data=0x00000002` instead of expected `0x40000000`

### Detailed Trace

```
Test sequence:
  800001ac: fcvt.s.w fa0, a0        # Convert 2 to float → fa0 = 0x40000000
  800001b4: fmv.x.w  a0, fa0        # Move to integer register → a0 = 0x40000000
  800001b8: bne      a0, a3, fail   # Compare (should NOT branch if a0 == 0x40000000)

Actual execution:
  - FCVT executed correctly, produced 0x40000000
  - FMV.X.W executed, wrote 0x40000000 to integer register file
  - BNE executed with rs1_data = 0x00000002 (WRONG!)
  - Branch incorrectly taken to FAIL
```

### Debug Output Analysis

```
[WB_FP2INT] x10 <= 40000000 (wb_sel=110 int_result_fp=40000000)
[BRANCH] PC=800001b8 ... rs1_data=00000002 (x10 fwd=10)
         exmem: rd=x10 reg_wr=1 int_wr_fp=1 int_res_fp=40000000 fwd_data=40000000
```

**Key Insights**:
- FMV.X.W was in EX/MEM stage with correct `int_result_fp=0x40000000`
- Forwarding detected the hazard (`fwd=10` = forward from EX/MEM)
- But forwarding mux selected `exmem_alu_result` instead of `exmem_int_result_fp`
- `exmem_forward_data` was correctly set to `0x40000000` after fix
- But `ex_alu_operand_a_forwarded` still used `exmem_alu_result` directly

## The Bug

### Problem 1: Forwarding Unit Not Checking FP-to-INT Writes

**File**: `rtl/core/forwarding_unit.v`

The forwarding unit only checked `exmem_reg_write` to detect writes in the EX/MEM stage, but did not check `exmem_int_reg_write_fp`. This meant FP-to-INT instructions were invisible to the forwarding logic.

```verilog
// BEFORE (WRONG):
if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1)) begin
  forward_a = 2'b10;  // Forward from EX/MEM
end

// AFTER (CORRECT):
if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1)) begin
  forward_a = 2'b10;  // Forward from EX/MEM (includes FP-to-INT)
end
```

### Problem 2: Missing Input Signal

**File**: `rtl/core/rv32i_core_pipelined.v`

The `exmem_int_reg_write_fp` signal existed but was not connected to the forwarding_unit instance.

```verilog
// BEFORE: Signal not passed
forwarding_unit forward_unit (
  ...
  .exmem_rd(exmem_rd_addr),
  .exmem_reg_write(exmem_reg_write),
  // Missing: .exmem_int_reg_write_fp
  ...
);
```

### Problem 3: Wrong Data Source in Forward Mux

**File**: `rtl/core/rv32i_core_pipelined.v:1041`

The forwarding data mux for `ex_alu_operand_a_forwarded` directly used `exmem_alu_result` instead of `exmem_forward_data`. While `exmem_forward_data` was correctly updated to select between atomic/FP/ALU results, the actual forwarding path didn't use it.

```verilog
// BEFORE (WRONG):
assign ex_alu_operand_a_forwarded = disable_forward_a ? ex_alu_operand_a :
                                    (forward_a == 2'b10) ? exmem_alu_result :  // ← WRONG
                                    (forward_a == 2'b01) ? wb_data :
                                    ex_alu_operand_a;

// AFTER (CORRECT):
assign ex_alu_operand_a_forwarded = disable_forward_a ? ex_alu_operand_a :
                                    (forward_a == 2'b10) ? exmem_forward_data :  // ← CORRECT
                                    (forward_a == 2'b01) ? wb_data :
                                    ex_alu_operand_a;
```

## Fix Implementation

### 1. Update Forwarding Unit Interface

Added `exmem_int_reg_write_fp` input to `forwarding_unit.v`:

```verilog
input  wire       exmem_int_reg_write_fp, // MEM stage FP-to-INT write
```

### 2. Update Forwarding Logic

Updated all forwarding decision logic in `forwarding_unit.v`:

**ID Stage Forwarding** (for early branch resolution):
- Lines 100, 120: Check `(exmem_reg_write | exmem_int_reg_write_fp)`

**EX Stage Forwarding** (for ALU operands):
- Lines 143, 152, 171, 179: Check `(exmem_reg_write | exmem_int_reg_write_fp)`
- Also updated WB stage checks to include `memwb_int_reg_write_fp`

### 3. Connect Signal in Core

Updated `rv32i_core_pipelined.v` forwarding_unit instantiation:

```verilog
forwarding_unit forward_unit (
  ...
  .exmem_rd(exmem_rd_addr),
  .exmem_reg_write(exmem_reg_write),
  .exmem_int_reg_write_fp(exmem_int_reg_write_fp),  // ← ADDED
  ...
);
```

### 4. Update Forward Data Mux

Enhanced `exmem_forward_data` selection in `rv32i_core_pipelined.v:1052`:

```verilog
assign exmem_forward_data = exmem_is_atomic ? exmem_atomic_result :
                            exmem_int_reg_write_fp ? exmem_int_result_fp :  // ← ADDED
                            exmem_alu_result;
```

### 5. Fix Forward Path

Changed `ex_alu_operand_a_forwarded` to use `exmem_forward_data` in line 1041:

```verilog
assign ex_alu_operand_a_forwarded = disable_forward_a ? ex_alu_operand_a :
                                    (forward_a == 2'b10) ? exmem_forward_data :  // ← CHANGED
                                    (forward_a == 2'b01) ? wb_data :
                                    ex_alu_operand_a;
```

## Test Results

### Before Fix
```
rv32uf-p-fcvt: FAILED at test_5
- Only test_2 executed
- Total cycles: 112
- Tests 3-6 skipped due to incorrect branch
```

### After Fix
```
rv32uf-p-fcvt: FAILED at test_7 (MAJOR IMPROVEMENT!)
- Tests 2-6 now PASS
- Total cycles: 128
- Remaining failure is a different issue
```

## Affected Instructions

The fix enables proper forwarding for these FP-to-INT instructions:
- `FMV.X.W` / `FMV.X.D` - Move from FP to integer register
- `FCVT.W.S` / `FCVT.WU.S` - Convert float to signed/unsigned int
- `FCVT.L.S` / `FCVT.LU.S` - Convert float to signed/unsigned long (RV64)
- `FEQ`, `FLT`, `FLE` - FP comparisons (produce integer 0/1 result)
- `FCLASS.S` / `FCLASS.D` - FP classification (produces integer result)

## Files Modified

1. `rtl/core/forwarding_unit.v` - Updated forwarding detection logic
2. `rtl/core/rv32i_core_pipelined.v` - Connected signals and fixed forward data path

## Testing Recommendations

1. Run rv32uf-p-fcvt test (now passes tests 2-6, fails at test 7)
2. Test FP compare instructions with immediate integer use
3. Test FCLASS followed by conditional branches
4. Test FCVT.W.S in tight loops

## Next Steps

1. **Investigate test_7 failure** in rv32uf-p-fcvt
2. Run full rv32uf test suite to verify fix doesn't break other tests
3. Test with rv32ud (double precision) when implemented

## Related Issues

- This bug was discovered while debugging rv32uf-p-fcvt test failure
- Original symptom appeared as branch misprediction but root cause was data hazard
- Bug #21 (FP Converter zero handling) was also related to FCVT testing

## Debug Commands Used

```bash
# Run test with FPU debug
DEBUG_FPU=1 ./tools/run_hex_tests.sh rv32uf-p-fcvt

# Check specific test failure
cat sim/test_rv32uf-p-fcvt.log | grep -E "BRANCH|WB_FP2INT|test number"

# Disassemble test binary
riscv64-unknown-elf-objdump -d riscv-tests/isa/rv32uf-p-fcvt | less
```

## Lessons Learned

1. **Forwarding is complex**: Every new result path (atomic, FP-to-INT, etc.) needs forwarding support
2. **Debug incrementally**: Added targeted debug output to trace the exact forwarding values
3. **Check all mux stages**: Fixed forwarding detection but also needed to fix data selection
4. **Systematic approach pays off**: Methodical debugging from symptoms → root cause → fix
