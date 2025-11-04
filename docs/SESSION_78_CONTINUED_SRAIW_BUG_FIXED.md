# Session 78 Continued: RV64I SRAIW Bug Fixed

**Date**: 2025-11-03  
**Status**: ✅ **COMPLETE** - SRAIW/SRAW arithmetic shift bug fixed!

## Problem

The comprehensive RV64I word operations test (`test_rv64i_word_ops`) was failing while simple tests passed:
- ✅ `test_rv64i_addiw_simple` - PASSES
- ✅ `test_addiw_minimal` - PASSES  
- ❌ `test_rv64i_word_ops` - FAILS with a0=0

## Investigation

### Debug Tracing
Added comprehensive cycle-by-cycle debug tracing showing:
- Instruction fetch (IF stage)
- Word operation execution (EX stage)  
- Register writeback (WB stage)

### Root Cause Identified
Test failure occurred at Test 7 (**SRAIW** - Shift Right Arithmetic Immediate Word):

```asm
li ra, -1                   # ra = 0xFFFFFFFFFFFFFFFF
sraiw sp, ra, 0x1          # sp = ra >>> 1 (arithmetic shift right)
li gp, -1                   # gp = 0xFFFFFFFFFFFFFFFF
bne sp, gp, fail           # Expect sp == gp (-1)
```

**Expected**: `0xFFFFFFFFFFFFFFFF` (arithmetic shift preserves sign)  
**Actual**: `0x000000007FFFFFFF` (sign bit lost!)

### The Bug

The word operation operand preparation logic was **unconditionally zero-extending** all operands:

```verilog
// WRONG: Zero-extends for ALL word operations
wire [XLEN-1:0] ex_alu_operand_a_final = is_word_alu_op ?
                                          {{32{1'b0}}, ex_alu_operand_a_forwarded[31:0]} :
                                          ex_alu_operand_a_forwarded;
```

For arithmetic right shifts (SRAIW/SRAW), this loses the sign bit:
- Input: `0xFFFFFFFFFFFFFFFF` 
- Zero-extend[31:0]: `0x00000000FFFFFFFF` (**bit 31 = 1**)
- Shift right 1: `0x000000007FFFFFFF` (**shifts in 0 because upper bits are 0!**)
- Sign-extend bit 31=0: `0x000000007FFFFFFF` ❌ WRONG!

## The Fix

Modified operand preparation to **sign-extend** operand A for arithmetic shifts:

```verilog
// Detect arithmetic right shift word operations
wire is_arith_shift_word = is_word_alu_op && (idex_funct3 == 3'b101) && idex_funct7[5];

// Sign-extend for SRAIW/SRAW, zero-extend for others
wire [XLEN-1:0] ex_alu_operand_a_final = is_arith_shift_word ?
                                          {{32{ex_alu_operand_a_forwarded[31]}}, ex_alu_operand_a_forwarded[31:0]} :
                                          is_word_alu_op ?
                                          {{32{1'b0}}, ex_alu_operand_a_forwarded[31:0]} :
                                          ex_alu_operand_a_forwarded;
```

Now arithmetic shifts work correctly:
- Input: `0xFFFFFFFFFFFFFFFF`
- **Sign-extend**[31:0]: `0xFFFFFFFFFFFFFFFF` (**preserves upper bits**)  
- Shift right 1: `0xFFFFFFFFFFFFFFFF` (**shifts in 1's**)
- Sign-extend bit 31=1: `0xFFFFFFFFFFFFFFFF` ✅ CORRECT!

## Verification

### Test Results
All tests now pass:
```
✅ test_rv64i_addiw_simple - PASSES (a0=1, 16 cycles)
✅ test_addiw_minimal       - PASSES (a0=1, 17 cycles)  
✅ test_rv64i_word_ops      - PASSES (a0=1, 61 cycles)
```

### Operations Validated
The comprehensive test validates all 9 RV64I word operations:
1. ✅ **ADDIW** - Add immediate word
2. ✅ **ADDW** - Add word
3. ✅ **SUBW** - Subtract word
4. ✅ **SLLIW** - Shift left logical immediate word
5. ✅ **SRLIW** - Shift right logical immediate word  
6. ✅ **SRAIW** - Shift right arithmetic immediate word (FIXED!)
7. ✅ **SLLW** - Shift left logical word
8. ✅ **SRLW** - Shift right logical word
9. ✅ **SRAW** - Shift right arithmetic word

## Impact

- **RV64I word operations fully functional** ✅
- Critical bug in arithmetic shifts fixed
- All test cases passing
- Ready for official RV64I compliance testing

## Files Modified

- `rtl/core/rv32i_core_pipelined.v:1422-1436` - Fixed operand preparation for word operations
- Added debug infrastructure for cycle-by-cycle tracing (lines 1465-1493)

## Next Steps

1. Run official RV64I compliance tests (87 tests)
2. Test remaining RV64 features (LD/SD/LWU instructions)
3. Continue Phase 3: Sv39 MMU upgrade

---

**Key Insight**: For word operations in RV64, operand extension strategy matters:
- **Arithmetic right shifts**: Require sign-extension to preserve sign bit
- **All other operations**: Use zero-extension of lower 32 bits
- Result is always sign-extended based on bit 31 after computation
