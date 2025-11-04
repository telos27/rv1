# Session 82: RV64M Complete (100%), RV64A Mostly Complete (95%)

**Date**: 2025-11-03
**Status**: ✅ **RV64M COMPLETE**, ⚠️ **RV64A 95% COMPLETE** (1 LR/SC test failing)

## Summary

Implemented and validated RV64M (multiply/divide) and RV64A (atomic operations) extensions with excellent compliance results.

### Test Results

**RV64M**: **13/13 (100%)** ✅
```
✅ div     - 64-bit signed division
✅ divu    - 64-bit unsigned division
✅ divuw   - 32-bit unsigned word division
✅ divw    - 32-bit signed word division
✅ mul     - 64-bit multiply (lower bits)
✅ mulh    - 64-bit signed multiply (upper bits)
✅ mulhsu  - 64-bit signed×unsigned multiply (upper bits)
✅ mulhu   - 64-bit unsigned multiply (upper bits)
✅ mulw    - 32-bit signed word multiply
✅ rem     - 64-bit signed remainder
✅ remu    - 64-bit unsigned remainder
✅ remuw   - 32-bit unsigned word remainder
✅ remw    - 32-bit signed word remainder
```

**RV64A**: **18/19 (95%)** ⚠️
```
✅ amoadd_d   - Atomic add doubleword
✅ amoadd_w   - Atomic add word
✅ amoand_d   - Atomic AND doubleword
✅ amoand_w   - Atomic AND word
✅ amomax_d   - Atomic max signed doubleword
✅ amomax_w   - Atomic max signed word
✅ amomaxu_d  - Atomic max unsigned doubleword
✅ amomaxu_w  - Atomic max unsigned word
✅ amomin_d   - Atomic min signed doubleword
✅ amomin_w   - Atomic min signed word
✅ amominu_d  - Atomic min unsigned doubleword
✅ amominu_w  - Atomic min unsigned word
✅ amoor_d    - Atomic OR doubleword
✅ amoor_w    - Atomic OR word
✅ amoswap_d  - Atomic swap doubleword
✅ amoswap_w  - Atomic swap word
✅ amoxor_d   - Atomic XOR doubleword
✅ amoxor_w   - Atomic XOR word
❌ lrsc      - Load-reserved/Store-conditional (test #3 fails)
```

## RV64M Implementation

### Bug #1: Multiply Unit op_width Calculation

**Issue**: `op_width = XLEN[5:0]` produced 0 for XLEN=64
- XLEN=64 in binary: `7'b1000000`
- Extracting bits [5:0]: `6'b000000` = 0
- Caused `cycle_count >= op_width` to be immediately true
- Multiplies completed in 1 cycle instead of 64!

**Fix** (`rtl/core/mul_unit.v:43-44`):
```verilog
// OLD: wire [5:0] op_width;
// OLD: assign op_width = (XLEN == 64 && is_word_op) ? 6'd32 : XLEN[5:0];

// NEW:
wire [6:0] op_width;
assign op_width = (XLEN == 64 && is_word_op) ? 7'd32 : XLEN[6:0];
```

**Impact**: Multiplies now take correct number of cycles (32 for word ops, 64 for doubleword)

---

### Bug #2: Result Sign-Extension Race Condition

**Issue**: Non-blocking assignments in same always block overwrote results
```verilog
// BUGGY CODE:
case (op_reg)
  MUL: result <= product[XLEN-1:0];  // Assignment #1
  ...
endcase
// Sign-extend for word operations
if (word_op_reg) begin
  result <= {{32{result[31]}}, ...};   // Assignment #2 - OVERWRITES #1!
end
```

Both assignments execute in same clock cycle; second overwrites first with OLD result value.

**Fix** (`rtl/core/mul_unit.v:172-204`, `rtl/core/div_unit.v:164-182`):
- Added intermediate register `extracted_result` (declared at module level)
- Extract result into temp register using blocking assignment (=)
- Sign-extend from temp register using non-blocking assignment (<=)

```verilog
reg [XLEN-1:0] extracted_result;  // Declared at module level

// In DONE state:
case (op_reg)
  MUL: extracted_result = product[XLEN-1:0];  // Blocking
  ...
endcase

if (XLEN == 64 && word_op_reg) begin
  result <= {{32{extracted_result[31]}}, extracted_result[31:0]};
end else begin
  result <= extracted_result;
end
```

**Impact**: Word operations now produce correctly sign-extended results

---

### Bug #3: Word Operation Operand Masking

**Issue**: Word operations used full 64-bit operands instead of 32-bit

For MULW with operands `0xFFFFFFFF80000000` and `0xFFFFFFFFFFFF8000`:
- Should mask to 32 bits: `0x80000000` × `0xFFFF8000`
- Was multiplying: `0xFFFFFFFF80000000` × `0xFFFFFFFFFFFF8000` (wrong!)

**Fix** (`rtl/core/mul_unit.v:68-84`, `rtl/core/div_unit.v:55-70`):
```verilog
// For word operations, mask to lower 32 bits and sign-extend
wire [XLEN-1:0] masked_a, masked_b;
generate
  if (XLEN == 64) begin
    assign masked_a = is_word_op ? {{32{operand_a[31]}}, operand_a[31:0]} : operand_a;
    assign masked_b = is_word_op ? {{32{operand_b[31]}}, operand_b[31:0]} : operand_b;
  end else begin
    assign masked_a = operand_a;
    assign masked_b = operand_b;
  end
endgenerate

assign abs_a = negate_a ? (~masked_a + 1'b1) : masked_a;
assign abs_b = negate_b ? (~masked_b + 1'b1) : masked_b;
```

**Impact**: Word operations now correctly operate on 32-bit values

---

### Bug #4: Unsigned Word Operations

**Issue**: DIVUW/REMUW used sign-extension when they should zero-extend

For DIVUW with `0x80000000` ÷ `0xFFFFFFFF`:
- As signed 32-bit: `-2147483648` ÷ `-1` = divide by negative
- As unsigned 32-bit: `2147483648` ÷ `4294967295` = 0 (correct)

**Fix** (`rtl/core/div_unit.v:55-70`):
```verilog
// For word operations, mask to lower 32 bits
// For signed operations (DIV/REM), sign-extend; for unsigned (DIVU/REMU), zero-extend
wire [XLEN-1:0] masked_dividend, masked_divisor;
generate
  if (XLEN == 64) begin
    assign masked_dividend = is_word_op ?
                            (is_signed_op ? {{32{dividend[31]}}, dividend[31:0]} :
                                          {{32{1'b0}}, dividend[31:0]}) :
                            dividend;
    assign masked_divisor  = is_word_op ?
                            (is_signed_op ? {{32{divisor[31]}}, divisor[31:0]} :
                                          {{32{1'b0}}, divisor[31:0]}) :
                            divisor;
  end
endgenerate
```

**Impact**: Unsigned word division/remainder now work correctly

---

## RV64A Implementation

### Bug #5: Signed Atomic Comparisons (MIN/MAX)

**Issue**: Word operations compared full 64-bit values instead of 32-bit

For AMOMAX.W with memory=`0x00000000FFFFFFFF` and src=`0x0000000000000001`:
- 64-bit comparison: `0x00000000FFFFFFFF` > `0x0000000000000001` (picks 0xFFFFFFFF)
- 32-bit signed: `0xFFFFFFFF` (-1) < `0x00000001` (1) (should pick 1)

**Fix** (`rtl/core/atomic_unit.v:230-252`):
```verilog
// For word operations on RV64, mask operands appropriately:
// - Signed operations (MIN/MAX): sign-extend from bit 31
// - Unsigned operations (MINU/MAXU): zero-extend
wire signed [XLEN-1:0] loaded_signed, src_signed;
wire [XLEN-1:0] loaded_unsigned, src_unsigned;

generate
  if (XLEN == 64) begin
    // For signed comparisons: sign-extend word operations
    assign loaded_signed = is_word ? {{32{loaded_value[31]}}, loaded_value[31:0]} :
                                    $signed(loaded_value);
    assign src_signed = is_word ? {{32{current_src[31]}}, current_src[31:0]} :
                                 $signed(current_src);

    // For unsigned comparisons: zero-extend word operations
    assign loaded_unsigned = is_word ? {{32{1'b0}}, loaded_value[31:0]} : loaded_value;
    assign src_unsigned = is_word ? {{32{1'b0}}, current_src[31:0]} : current_src;
  end
endgenerate
```

**Impact**: Signed MIN/MAX word operations now compare correctly

---

### Bug #6: Unsigned Atomic Comparisons (MINU/MAXU)

**Issue**: Initial fix sign-extended for unsigned comparisons

**Fix** (`rtl/core/atomic_unit.v:286-294`):
```verilog
ATOMIC_MINU: begin
  // Use zero-extended values for unsigned comparison
  computed_value = (loaded_unsigned < src_unsigned) ? loaded_value : current_src;
end

ATOMIC_MAXU: begin
  // Use zero-extended values for unsigned comparison
  computed_value = (loaded_unsigned > src_unsigned) ? loaded_value : current_src;
end
```

**Impact**: Unsigned MIN/MAX word operations now compare correctly

---

### Bug #7: Atomic Result Sign-Extension

**Issue**: LR/AMO results not sign-extended for word operations

**Fix** (`rtl/core/atomic_unit.v:312-319`):
```verilog
if (is_lr || is_amo) begin
  // LR and AMO return the loaded value
  // For word operations on RV64, sign-extend from bit 31
  if (XLEN == 64 && is_word) begin
    result <= {{32{mem_rdata[31]}}, mem_rdata[31:0]};
  end else begin
    result <= mem_rdata;
  end
```

**Impact**: Atomic operation results properly sign-extended on RV64

---

## Known Issue: LR/SC Test Failure

**Test**: `lrsc` fails at test #3 with timeout after 10,000 cycles

**Analysis**:
- Test #2: SC without reservation → correctly returns 1 (failure) ✓
- Test #3: Load from `foo` expecting 0 → test fails/hangs
- **Root cause**: SC in test #2 likely wrote to memory when it shouldn't have
- **Issue**: LR/SC reservation tracking not correctly preventing SC writes

**Impact**:
- Basic LR/SC functionality works (reservation creation, success case)
- Edge case: SC without valid reservation still writes to memory
- Requires deeper investigation of reservation station logic

**Priority**: HIGH - Will be addressed in Session 83

---

## Files Modified

### RTL Changes
- `rtl/core/mul_unit.v`
  - Fixed op_width calculation (line 43-44)
  - Added extracted_result register (line 99)
  - Fixed result extraction race condition (lines 172-204)
  - Added operand masking for word operations (lines 68-84)

- `rtl/core/div_unit.v`
  - Added extracted_result register (line 83)
  - Fixed result extraction race condition (lines 164-182)
  - Added signed/unsigned operand masking (lines 55-70)

- `rtl/core/atomic_unit.v`
  - Added signed/unsigned operand masking (lines 230-252)
  - Fixed MIN/MAX comparisons (lines 278-294)
  - Added result sign-extension (lines 312-319)

---

## Test Infrastructure

Built and ran RV64 compliance tests using existing infrastructure:
- `tools/run_rv64_tests.sh um` - RV64M test suite
- `tools/run_rv64_tests.sh ua` - RV64A test suite
- Test binaries in `riscv-tests/isa/rv64um-p-*` and `rv64ua-p-*`

---

## Overall RV64 Progress

| Extension | Tests | Status | Notes |
|-----------|-------|--------|-------|
| RV64I | 53/54 (98%) | ✅ | Session 81 (fence_i fails) |
| RV64M | 13/13 (100%) | ✅ | Session 82 |
| RV64A | 18/19 (95%) | ⚠️ | Session 82 (lrsc fails) |
| **Total RV64IMA** | **84/86 (98%)** | ⚠️ | Need to fix lrsc |

---

## Next Steps (Session 83)

1. **Debug LR/SC reservation tracking**
   - Investigate why SC without reservation writes to memory
   - Check reservation station invalidation logic
   - Verify SC success/failure conditions

2. **After LR/SC fix: RV64F/D (Floating Point)**
   - Build RV64 floating point tests
   - Verify FPU works with 64-bit registers
   - May need NaN-boxing adjustments

3. **After extensions: RV64 system testing**
   - Test FreeRTOS on RV64
   - Validate full RV64IMAFDC compliance
   - Prepare for Sv39 MMU upgrade

---

## Impact

- **RV64M extension fully validated** ✅
- **RV64A extension 95% validated** (1 complex edge case remaining)
- **Word operation handling robust** across all extension types
- **Sign/zero-extension patterns established** for future extensions
- **Test infrastructure working well** for RV64 compliance validation

The word operation bugs fixed in this session follow the same patterns found in Session 78 for RV64I, demonstrating consistent handling across the entire instruction set.
