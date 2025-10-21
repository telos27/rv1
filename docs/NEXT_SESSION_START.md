# Next Session Starting Point

**Date**: 2025-10-21
**Last Session**: FPU Bug #20, #21 Fixed + Infrastructure Improvements
**Current Status**: 5/11 RV32UF tests passing (45%)

---

## Session 2025-10-21 Summary

### Bugs Fixed This Session

#### Bug #20: FP Compare Incorrect Comparison Logic ✅
**File**: `rtl/core/fp_compare.v`
**Problem**: Used `$signed(operand_a) < $signed(operand_b)` which treats FP bit patterns as signed integers
**Example Failure**: Negative number comparisons incorrect
**Fix**: Implemented proper IEEE 754 comparison:
- Signs differ: negative < positive
- Both positive: magnitude comparison
- Both negative: REVERSE magnitude comparison (larger bits = more negative)
**Result**: rv32uf-p-fcmp now PASSING

#### Bug #21: FP Converter Uninitialized Intermediate Variables ✅
**File**: `rtl/core/fp_converter.v:262-272`
**Problem**: FCVT.S.W with zero input produced garbage (xxxxxxxx)
**Root Cause**:
- CONVERT stage sets `fp_result=0` directly for zero input
- ROUND stage always runs, rebuilds `fp_result` from intermediate variables
- Intermediate variables (`sign_result`, `exp_result`, `man_result`) were never initialized
- ROUND combined 'x' values → garbage output
**Fix**: Initialize intermediate variables to zero in early-exit cases
**Testing**: FCVT.S.W x0 now produces 0x00000000 correctly

### Infrastructure Improvements ✅

#### Hex File Format Standardization
**Problem**: Recurring format issues across multiple sessions causing garbled instructions
**Solution**:
1. **New Tool**: `tools/asm_to_hex.sh`
   - Complete pipeline: .s → .o → .elf → .hex
   - One command: `./tools/asm_to_hex.sh tests/asm/test.s`
   - Supports all extensions (I/M/A/F/D/C)
   - Configurable architecture, ABI, start address

2. **New Tool**: `tools/elf_to_hex.sh`
   - Converts ELF to correct hex format
   - Ensures byte-per-line output

3. **Documentation**: `docs/HEX_FILE_FORMAT.md`
   - Complete specification
   - Examples of correct/incorrect formats
   - Troubleshooting guide
   - Historical context

4. **Quick Reference**: `tools/README.md`
   - Common workflows
   - Tool descriptions
   - Debugging tips

**Format**: One byte per line (e.g., `53`, `75`, `00`, `d0`)
**Benefit**: Future sessions won't waste time on format issues

#### Test Runner Debug Support
**File**: `tools/test_pipelined.sh`
**Addition**: Support for debug environment variables
- `DEBUG_FPU=1` - Enable FPU debug output
- `DEBUG_M=1` - Enable M extension debug
- `DEBUG_HAZARD=1` - Enable hazard detection debug
**Usage**: `DEBUG_FPU=1 ./tools/test_pipelined.sh test_name`

---

## Current RV32UF Test Status

**Overall**: 5/11 tests passing (45%)

| Test | Status | Notes |
|------|--------|-------|
| fadd | ✅ PASS | All addition/subtraction operations working |
| fclass | ✅ PASS | FP classification working |
| fcmp | ✅ PASS | FP comparison fixed this session |
| ldst | ✅ PASS | FP load/store working |
| move | ✅ PASS | FP move operations working |
| fcvt | ❌ FAIL | Fails at test #5 (sign injection operations) |
| fcvt_w | ❌ FAIL | INT↔FP conversions |
| fdiv | ❌ FAIL | FP division |
| fmadd | ❌ FAIL | Fused multiply-add |
| fmin | ❌ FAIL | Min/max operations |
| recoding | ❌ FAIL | NaN recoding |

---

## Next Issue: rv32uf-p-fcvt Test #5

### What We Know

1. **Test Name**: `rv32uf-p-fcvt`
   - **Misleading!** Despite the name, this test does NOT primarily test FCVT.W.S/FCVT.S.W
   - Actually tests **sign injection** operations: FSGNJ.S, FSGNJN.S, FSGNJX.S
   - The fcvt_w test handles INT↔FP conversions

2. **Failure Point**: Test #5
   - Test harness tracks test number in x3 (gp)
   - Fails at gp=5

3. **From Previous Debug Session**:
   ```
   [FPU] START: op=10 a=00000000 b=00000000 c=00000000
   [FPU] DONE: op=10 result=40000000 flags=00000
   ```
   - Op 10 = FP_CVT
   - Input: a=0x00000000, b=0x00000000, c=0x00000000
   - Output: result=0x40000000 (2.0) ← WRONG! Should be 0x00000000

4. **Test Binary Location**: `tests/official-compliance/rv32uf-p-fcvt.hex`
   - First instruction at offset 0x1AC: `0xd0057553`
   - Decoded: FCVT.S.W f10, f10 (but this is suspicious - rs1 should be integer register!)

### Investigation Strategy for Next Session

#### Step 1: Identify Exact Instruction Being Tested
```bash
# Decode the hex file around test #5
python3 << 'EOF'
with open('tests/official-compliance/rv32uf-p-fcvt.hex', 'r') as f:
    lines = f.readlines()

# Test #5 is approximately at byte offset (based on test structure)
# Each test is ~20-30 instructions
# Decode instructions around offset 100-200

for i in range(100, 200, 4):
    if i+3 < len(lines):
        word = lines[i+3].strip() + lines[i+2].strip() + lines[i+1].strip() + lines[i].strip()
        instr = int(word, 16)
        print(f"[0x{i:04x}] = 0x{word} | opcode=0x{instr&0x7F:02x}")
EOF
```

#### Step 2: Check Control Unit Decoding
- Verify FSGNJ operations are decoded correctly
- Check if FCVT operations are being confused with FSGNJ
- Look for overlap in funct7 encodings

#### Step 3: Run with Full Debug
```bash
# Enable all debug flags
DEBUG_FPU=1 timeout 60s ./tools/run_hex_tests.sh rv32uf-p-fcvt 2>&1 | tee debug_fcvt_full.log

# Search for test #5 context
grep -B30 -A10 "test number: 5" debug_fcvt_full.log
```

#### Step 4: Check FSGNJ Implementation
- File: `rtl/core/fp_sign.v`
- Verify FSGNJ, FSGNJN, FSGNJX logic
- Check operand routing
- Verify output multiplexing in `rtl/core/fpu.v`

#### Step 5: Check if Issue is Operand Routing
Previous analysis suggested:
```
[CORE] FPU START: fp_alu_op=10 rs1=10 rs2=0 rs3=26 rd=10
       operands: a=00000000 b=00000000 c=00000000
```
- rs1=10 means reading from f10 (FP register)
- But for INT→FP, should read from x10 (integer register)
- **Question**: Is there confusion between INT and FP register file reads?

---

## Quick Commands for Next Session

### Run Tests
```bash
# Run single test with debug
DEBUG_FPU=1 timeout 60s ./tools/run_hex_tests.sh rv32uf-p-fcvt

# Run full FPU test suite
timeout 120s ./tools/run_hex_tests.sh rv32uf

# Check specific test log
tail -100 sim/test_rv32uf-p-fcvt.log
grep "test number" sim/test_rv32uf-p-fcvt.log
```

### Debug Hex File
```bash
# View hex file
head -100 tests/official-compliance/rv32uf-p-fcvt.hex

# Decode specific instruction
python3 -c "
word = 'd0057553'
instr = int(word, 16)
print(f'opcode: 0x{instr&0x7F:02x}')
print(f'funct3: 0x{(instr>>12)&0x7:x}')
print(f'funct7: 0x{(instr>>25)&0x7F:02x}')
print(f'rd: {(instr>>7)&0x1F}')
print(f'rs1: {(instr>>15)&0x1F}')
print(f'rs2: {(instr>>20)&0x1F}')
"
```

### Create Custom Test
```bash
# Write assembly
vim tests/asm/test_fsgnj_debug.s

# Convert to hex (one command!)
./tools/asm_to_hex.sh tests/asm/test_fsgnj_debug.s

# Run test
DEBUG_FPU=1 ./tools/test_pipelined.sh test_fsgnj_debug
```

---

## Relevant Files

### FPU Implementation
- `rtl/core/fpu.v` - Top-level FPU, operation routing
- `rtl/core/fp_sign.v` - Sign injection (FSGNJ, FSGNJN, FSGNJX)
- `rtl/core/fp_converter.v` - INT↔FP conversion (fixed Bug #21)
- `rtl/core/fp_compare.v` - FP comparison (fixed Bug #20)

### Control & Decoding
- `rtl/core/control.v` - Instruction decoding, control signals
- `rtl/core/decoder.v` - Instruction field extraction
- `rtl/core/rv32i_core_pipelined.v` - Pipeline integration, operand routing

### Test Infrastructure
- `tools/asm_to_hex.sh` - Assembly to hex conversion
- `tools/test_pipelined.sh` - Test runner (now supports DEBUG_FPU)
- `tools/run_hex_tests.sh` - Compliance test runner
- `docs/HEX_FILE_FORMAT.md` - Hex format documentation

---

## Known Issues / Suspicious Patterns

1. **Operation Code Confusion**
   - Seeing FP_CVT (op=10) when expecting FSGNJ operations
   - Need to verify control unit isn't misclassifying instructions

2. **Operand Source Confusion**
   - For FCVT.S.W, rs1 should read from INTEGER register file (x-regs)
   - But logs show it reading from FP register file (f-regs)
   - This is likely the root cause

3. **Result Discrepancy**
   - Expected: 0x00000000 (or whatever the correct FSGNJ result is)
   - Actual: 0x40000000 (2.0)
   - Suggests wrong operation entirely or wrong operands

---

## Recent Commits

```
8ef3f90 Bug #21 Fixed: FP Converter Uninitialized Intermediate Variables
eb47411 Infrastructure: Standardize hex file generation and documentation
df09d24 Bug #20 Fixed: FP Compare Signed Integer Comparison Error
```

All commits pushed to remote: https://github.com/telos27/rv1.git

---

## Key Takeaway for Next Session

**Be systematic!** The fcvt test has been tricky because:
1. The test name is misleading (it's not primarily about INT↔FP conversion)
2. Multiple potential issues (wrong operation, wrong operands, wrong result)
3. Need to decode the actual test binary to know what instruction is being tested

**Start by**: Decoding the exact instruction at test #5, then trace through the pipeline to see where it goes wrong.

**Tools are ready**: Hex format is solid, debug flags work, documentation is in place. Can focus purely on the bug.

---

*End of session notes. Ready to continue FPU debugging!*
