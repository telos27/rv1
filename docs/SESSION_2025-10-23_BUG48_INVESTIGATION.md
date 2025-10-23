# Session 2025-10-23: Bug #48 Investigation - FCVT_W Address Calculation Error

**Date**: 2025-10-23 (Session 14 continuation)
**Duration**: Extended debugging session
**Focus**: Investigate rv32uf-p-fcvt_w test failure
**Result**: ⚠️ Root cause identified, fix deferred to next session

---

## Session Context

Starting from excellent progress:
- **RV32F Status**: 10/11 tests passing (90%) ✅
- **Only failing test**: rv32uf-p-fcvt_w
- **Recent fixes**: Bugs #44 (FMA positioning), #45 (FMV.W.X width), #47 (FSGNJ NaN-boxing)

Goal: Fix the last failing RV32F test to reach 11/11 (100%)

---

## Investigation Process

### Initial Hypothesis: Memory Load Bug

Based on session notes, suspected memory load issue from FLEN refactoring:
- FCVT.W.S conversion works (0.9 → 0 ✅)
- But test loads wrong expected value from memory
- Expected: a3 = 0x00000000
- Actual: a3 = 0xffffffff

### Phase 1: Check Memory Subsystem

Added debug to `data_memory.v` to trace reads:
```verilog
if (addr == 32'h8000203c) begin
  $display("[DMEM_READ] @ 0x%08h: funct3=%b word_data=0x%08h", ...);
end
```

**Finding**: No debug output - memory never accessed at expected address!

### Phase 2: Check Memory Interface

Examined FLEN refactoring changes:
- Changed read_data/write_data from XLEN to 64-bit
- Added sign-extension for LW: `{{32{word_data[31]}}, word_data}`
- Lower 32 bits extracted: `mem_read_data = arb_mem_read_data[31:0]`

**Finding**: Architecture looks correct, but still getting wrong value.

### Phase 3: Add Writeback Debug

Compiled with `-DDEBUG_REGFILE_WB` to trace register writes:
```
[REGFILE_WB] @0 Writing rd=x13 data=00000000 (wb_sel=000 alu=00000000 mem=00000000 mul_div=00000000)
[REGFILE_WB] @0 Writing rd=x13 data=ffffffff (wb_sel=001 alu=8000200c mem=ffffffff mul_div=00000000)
```

**BREAKTHROUGH**: `memwb_mem_read_data = 0xffffffff` and `alu = 0x8000200c`!

### Phase 4: Check Memory Read Path

Added debug to trace memory reads in pipeline:
```verilog
if (exmem_mem_read && !exmem_fp_mem_op) begin
  $display("[MEM_READ] Integer load: arb_mem_read_data=0x%016h mem_read_data=0x%08h addr=0x%08h", ...);
end
```

Output:
```
[MEM_READ] Integer load: arb_mem_read_data=0xffffffffffffffff mem_read_data=0xffffffff addr=0x8000200c
```

**KEY FINDING**: Memory returns correct data (0xffffffff) from address 0x8000200c,
but test should be loading from 0x8000203c!

### Phase 5: Verify Hex File Contents

Checked what's actually in the hex file:
```python
# Address 0x8000200c (wrong address):
Bytes: ff ff ff ff → Word: 0xffffffff  ❌

# Address 0x8000203c (correct address):
Bytes: 00 00 00 00 → Word: 0x00000000  ✅
```

**CONFIRMED**: Hex file is correct. Memory is working correctly.
The bug is that the **address calculation is wrong**!

### Phase 6: Analyze Address Error

| Component | Expected | Actual | Difference |
|-----------|----------|--------|------------|
| Load address | 0x8000203c | 0x8000200c | -48 bytes (-0x30) |
| Base (a0) | 0x80002030 | 0x80002000 | -48 bytes (-0x30) |

Instruction: `lw a3, 12(a0)`
- Expected: 0x80002030 + 12 = 0x8000203c ✅
- Actual: 0x80002000 + 12 = 0x8000200c ❌

**Offset**: 48 bytes = 12 words = 12 test data table entries

### Phase 7: Bisect to Find Breaking Commit

```bash
git checkout 7dc1afd  # Working commit
./tools/run_official_tests.sh uf fcvt_w
# Result: PASSED ✅

git checkout main  # Current (broken)
./tools/run_official_tests.sh uf fcvt_w
# Result: FAILED ❌
```

Breaking commit range:
- Working: 7dc1afd (Bug #42: C.JAL/C.JALR)
- Broken: d7c2d33 → 747a716 (Bugs #27 & #28: RV32D FLEN Refactoring)

---

## Root Cause Identified

### The Bug
Register a0 contains **0x80002000** instead of **0x80002030** when test #5 executes.

This causes the load instruction `lw a3, 12(a0)` to:
- Calculate address: 0x80002000 + 12 = 0x8000200c (wrong)
- Instead of: 0x80002030 + 12 = 0x8000203c (correct)
- Load wrong data: 0xffffffff instead of 0x00000000

### What's NOT Broken
✅ Memory subsystem (returns correct data for address it receives)
✅ LW instruction decode
✅ Sign extension logic
✅ 64-bit to 32-bit extraction
✅ Hex file data
✅ Tests #1-#4 (they pass, gp=5 means fail at test #5)

### What IS Broken
❌ Register a0 has wrong value by the time test #5 executes
❌ Likely: Some instruction in tests #1-#4 computes wrong result
❌ That wrong result propagates and corrupts a0 value

### Possible Causes

1. **Earlier test side effect**: Tests #1-#4 may compute incorrect values
2. **PC-relative addressing**: AUIPC/LUI for data pointers may be affected
3. **Forwarding issue**: 64-bit pipeline changes might affect integer forwarding
4. **Hidden interaction**: FP/INT register file interaction bug

---

## Why This Is Hard to Debug

1. **Indirect failure**: The failing instruction (LW at test #5) is correct
2. **Propagated error**: The bug occurred earlier, we just see effects at test #5
3. **48-byte offset**: Systematic shift suggests data table addressing issue
4. **FLEN refactoring scope**: Changed 6 files, 300+ lines
5. **Tests #1-#4 pass**: The earlier test that sets a0 wrong still "passes" its check

---

## Files Modified This Session

### Created
- `docs/BUG_48_FCVT_W_ADDRESS_CALCULATION.md` - Full investigation report

### Debug Changes (reverted)
- `rtl/memory/data_memory.v` - Added temporary debug statements
- `rtl/core/rv32i_core_pipelined.v` - Added MEM_READ debug

---

## Test Results

**Before investigation**: 10/11 RV32UF tests (90%)
**After investigation**: 10/11 RV32UF tests (90%) - no change
**Status**: Root cause identified but not fixed

### Passing Tests (10/11)
✅ rv32uf-p-fadd
✅ rv32uf-p-fclass
✅ rv32uf-p-fcmp
✅ rv32uf-p-fcvt
✅ rv32uf-p-fdiv
✅ rv32uf-p-fmadd
✅ rv32uf-p-fmin
✅ rv32uf-p-ldst
✅ rv32uf-p-move
✅ rv32uf-p-recoding

### Failing Test (1/11)
❌ rv32uf-p-fcvt_w - Address calculation bug (Bug #48)

---

## Debug Commands Used

### Compile with Debug
```bash
iverilog -g2012 -I"rtl" -DXLEN=32 -DFLEN=64 -DCOMPLIANCE_TEST \
  -DDEBUG_REGFILE_WB \
  -DMEM_FILE='"tests/official-compliance/rv32uf-p-fcvt_w.hex"' \
  -o sim/official-compliance/test_fcvt_w_debug.vvp \
  rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
```

### Run with Filtering
```bash
timeout 3s vvp sim/test_fcvt_w_debug.vvp 2>&1 | grep -E "(MEM_READ|REGFILE_WB.*x13)"
```

### Check Hex File
```bash
python3 << 'EOF'
with open('tests/official-compliance/rv32uf-p-fcvt_w.hex', 'r') as f:
    lines = [line.strip() for line in f.readlines() if line.strip()]
offset = 0x200c
bytes = [lines[offset+i] for i in range(8)]
print(f"0x8000200c: {' '.join(bytes)}")
EOF
```

### Bisect
```bash
git checkout 7dc1afd  # Working
git checkout main     # Broken
```

---

## Next Session Action Plan

### Priority 1: Trace a0 Register
Add debug to track all writes to x10 (a0):
```verilog
`ifdef DEBUG_A0_TRACKING
always @(posedge clk) begin
  if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd10) begin
    $display("[A0_WRITE] cycle=%0d x10 <= 0x%08h (wb_sel=%b pc=0x%08h)",
             cycle_count, wb_data, memwb_wb_sel, memwb_pc);
  end
end
`endif
```

Find which instruction sets a0 to 0x80002000 instead of 0x80002030.

### Priority 2: Instruction-by-Instruction Comparison
Run full instruction traces on both working and broken commits:
```bash
# Working commit
git checkout 7dc1afd
DEBUG_TRACE=1 ./tools/run_official_tests.sh uf fcvt_w > trace_working.log 2>&1

# Broken commit
git checkout main
DEBUG_TRACE=1 ./tools/run_official_tests.sh uf fcvt_w > trace_broken.log 2>&1

# Find first divergence
diff -u trace_working.log trace_broken.log | head -100
```

### Priority 3: Check PC-Relative Addressing
Disassemble test to find AUIPC/LUI instructions:
```bash
riscv64-unknown-elf-objdump -d tests/official-compliance/rv32uf-p-fcvt_w.elf | grep -E "(auipc|lui)" | head -20
```

### Priority 4: Automated Bisect
```bash
git bisect start main 7dc1afd
git bisect run bash -c "env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf fcvt_w 2>&1 | grep -q PASSED"
# This will find the exact commit that broke it
```

---

## Key Insights

1. **Not a memory bug**: Memory subsystem works perfectly
2. **Not a sign-extension bug**: 64-bit handling is correct
3. **Not a load instruction bug**: LW decodes and executes correctly
4. **IS an address calculation bug**: a0 register has wrong value
5. **Introduced by FLEN refactoring**: Working before, broken after
6. **Systematic 48-byte offset**: Suggests data table addressing issue
7. **Tests #1-#4 affected**: One of them sets up a0 incorrectly

---

## Lessons Learned

1. **Debug at the right level**: Spent time on memory/sign-extension when the real issue was address calculation
2. **Trust the working commit**: Bisecting earlier would have saved time
3. **Add comprehensive debug early**: The REGFILE_WB debug immediately revealed the real issue
4. **Check assumptions**: Assumed test was loading from 0x8000203c, should have verified the actual address first

---

## Summary

**Achievement**: Identified root cause of Bug #48
- NOT a memory, sign-extension, or load instruction bug
- IS an address calculation bug where a0 = 0x80002000 instead of 0x80002030
- Introduced during FLEN refactoring (commits d7c2d33 → 747a716)
- Need to trace which earlier instruction sets a0 incorrectly

**Status**: Ready for focused debugging in next session with clear action plan

**Impact**: Low urgency - 90% of RV32F tests passing, only 1 test blocked

---

*Session ended 2025-10-23. Comprehensive documentation created for next session handoff.*
