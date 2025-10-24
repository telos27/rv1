# Session 2025-10-23: Bug #50 - FLD Format Bit Extraction

## Summary
Fixed critical bug in decoder where FLD (double-precision load) was incorrectly extracting format bit, causing all double-precision values to be NaN-boxed as if they were single-precision. This fix brings RV32D compliance from 0/9 (0%) to 6/9 (66%).

## Bug Description

**Symptom**: All RV32D tests failing at test #2-5, returning incorrect FCLASS results.
- Expected: 0x001 (negative infinity)
- Got: 0x200 (quiet NaN)

**Root Cause**: Decoder extracted `fp_fmt` from wrong instruction bits for FP loads/stores.

### Technical Details

In RISC-V ISA encoding:
- **FP Load/Store** (FLW/FLD/FSW/FSD): Format encoded in **funct3[1:0]**
  - FLW: funct3=010 (bit 0=0) → single-precision
  - FLD: funct3=011 (bit 0=1) → double-precision

- **FP Operations** (FADD.D, FMUL.D, etc.): Format encoded in **funct7[1:0]** (instruction[26:25])

**Bug**: decoder.v line 236 always used `instruction[26:25]` for format extraction:
```verilog
// BEFORE (WRONG):
wire [1:0] fmt_field = is_fp_fma ? instruction[26:25] : instruction[26:25];
```

For FLD instructions, bits [26:25] are part of the **immediate field**, not the format! This caused FLD to have undefined/wrong format values.

### Impact Chain

1. **Decoder** extracts wrong `fp_fmt` for FLD
   - FLD (funct3=011) should set fp_fmt=1
   - But decoder read instruction[26:25] which are immediate bits
   - Result: fp_fmt was 0 or garbage instead of 1

2. **Pipeline** propagates wrong format through IDEX → EXMEM → MEMWB
   - `memwb_fp_fmt` ends up being 0 (single-precision) for FLD

3. **Load NaN-boxing logic** (rv32i_core_pipelined.v:1899) activates incorrectly:
   ```verilog
   assign fp_load_data_boxed = (`FLEN == 64 && !memwb_fp_fmt) ?
                                {32'hFFFFFFFF, memwb_fp_mem_read_data[31:0]} :
                                memwb_fp_mem_read_data;
   ```
   - Condition: FLEN=64 AND fmt=0 (single-precision)
   - For FLD with wrong fmt=0: NaN-boxing applied!
   - Memory had: 0xfff0000000000000
   - After NaN-box: 0xffffffff00000000 (quiet NaN!)

4. **FP Register File** stores corrupted value

5. **FPU classify** receives 0xffffffff00000000 instead of 0xfff0000000000000
   - 0xffffffff00000000: exp=0x7ff, man=0xffffffff00000 (MSB=1) → Quiet NaN ✅
   - 0xfff0000000000000: exp=0x7ff, man=0x0 → Negative infinity ✅
   - Result: 0x200 instead of 0x001

## Fix

### Code Changes

**File**: `rtl/core/decoder.v` (line 241)

```verilog
// BEFORE:
wire [1:0] fmt_field = is_fp_fma ? instruction[26:25] : instruction[26:25];

// AFTER:
wire [1:0] fmt_field = (is_fp_load || is_fp_store) ? funct3[1:0] : instruction[26:25];
```

### Fix Logic

- For FP loads/stores: Extract format from `funct3[1:0]`
- For FP operations and FMA: Extract format from `instruction[26:25]`

This ensures:
- FLW (funct3=010): fmt_field=10, fp_fmt=0 → single-precision ✅
- FLD (funct3=011): fmt_field=11, fp_fmt=1 → double-precision ✅

## Verification

### Test Results

**Before Fix**:
```
RV32D: 0/9 (0%)
- All tests failed at test #2-5
- FCLASS returned 0x200 instead of 0x001
```

**After Fix**:
```
RV32D: 6/9 (66%)
✅ rv32ud-p-fclass   - Classification
✅ rv32ud-p-fcmp     - Comparison
✅ rv32ud-p-fcvt_w   - FP to INT conversion
✅ rv32ud-p-fmin     - Min/Max
✅ rv32ud-p-ldst     - Load/Store
❌ rv32ud-p-fcvt     - INT to FP conversion (timeout)
❌ rv32ud-p-fdiv     - Division
❌ rv32ud-p-fmadd    - Fused multiply-add
```

### Debug Output Confirmation

**Before Fix**:
```
[FPU] FCLASS: operand_a=0xffffffff00000000 fmt=1 result=0x00000200
```

**After Fix**:
```
[FPU] FCLASS: operand_a=0xfff0000000000000 fmt=1 result=0x00000001
```

Operand now correctly loaded as 0xfff0000000000000 (negative infinity).

## Root Cause Analysis

### Why This Bug Existed

1. **Historical oversight**: Original decoder implementation only supported single-precision (F extension)
2. **Copy-paste error**: When adding double-precision support, format extraction wasn't updated for loads/stores
3. **Insufficient test coverage**: Bug only manifests with RV32D (XLEN=32, FLEN=64)
   - RV32F: Always single-precision, NaN-boxing works correctly
   - RV64D: XLEN=64, different register handling

### Why It Wasn't Caught Earlier

- RV32F tests all passed because FLW format extraction worked (by coincidence, immediate bits often had correct values)
- Custom FPU tests used simple values that might have worked despite bug
- RV32D tests not run until Session 16

## Related Issues

This bug is similar to **Bug #43** (F+D mixed precision) but in a different location:
- Bug #43: FPU modules didn't use format bit correctly in arithmetic
- Bug #50: Decoder didn't extract format bit correctly for loads/stores

Both bugs demonstrate the complexity of supporting mixed-precision floating-point in a 32-bit architecture with 64-bit FP registers.

## Impact on RV32F

**No impact on RV32F** - Single-precision tests remain 11/11 (100%) passing.

FLW format extraction happened to work because:
- FLW: funct3=010 → funct3[1:0]=10 → fp_fmt=0 ✅
- instruction[26:25] for FLW often contains 00 or 10 → fp_fmt=0 ✅

So both code paths gave fmt=0 for single-precision, masking the bug.

## Future Considerations

### Remaining RV32D Issues

The 3 failing tests likely have different root causes:

1. **fcvt (timeout)**: INT→FP conversion may have infinite loop
   - Suggest checking fp_converter.v INT→FP path for double-precision

2. **fdiv**: FP division incorrect results
   - May be related to Bug #43 if fp_divider.v still has format issues

3. **fmadd**: Fused multiply-add incorrect results
   - May be related to Bug #43 if fp_fma.v still has format issues

### Testing Recommendations

- Add unit tests for format bit extraction in decoder
- Add tests for FLD/FSD specifically with edge-case immediate values
- Consider formal verification for instruction decoding

## Lessons Learned

1. **Format encoding varies by instruction class**: Critical to check RISC-V ISA spec for each opcode
2. **NaN-boxing is powerful but dangerous**: Silent corruption if format bit is wrong
3. **Debug output is essential**: `DEBUG_FPU` flag made this bug easy to diagnose
4. **Systematic debugging pays off**: Methodical approach found root cause in <2 hours

## References

- RISC-V ISA Spec v2.2, Chapter 11 (D Extension)
- RISC-V ISA Spec v2.2, Table 11.1 (FP Load/Store encoding)
- Project: PHASES.md, docs/RV32D_DEBUG_PLAN.md

---

**Bug #50 Status**: FIXED ✅
**RV32D Progress**: 0% → 66% (6/9 tests passing)
**Next**: Debug fcvt, fdiv, fmadd failures (3 remaining issues)
