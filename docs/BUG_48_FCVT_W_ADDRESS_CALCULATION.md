# Bug #48: FCVT_W Test Address Calculation Error

**Date**: 2025-10-23
**Status**: ❌ IDENTIFIED - NOT YET FIXED
**Severity**: Medium
**Impact**: rv32uf-p-fcvt_w test fails at test #5

---

## Symptom

The `rv32uf-p-fcvt_w` compliance test fails at test #5 with:
- **Expected**: a3 = 0x00000000
- **Actual**: a3 = 0xffffffff
- **Test status**: gp = 5 (fails at test number 5)

```
x13 (a3)   = 0xffffffff  ❌ Should be 0x00000000
```

---

## Root Cause Analysis

### The Problem is NOT with Memory

The memory subsystem is working **correctly**:

1. **Memory contents verified**: The hex file contains the correct data
   - Address 0x8000203c: 0x00000000 ✅ (expected test value)
   - Address 0x8000200c: 0xffffffff (actual value at wrong address)

2. **Memory read operation verified**: Using debug output:
   ```
   [MEM_READ] Integer load: arb_mem_read_data=0xffffffffffffffff mem_read_data=0xffffffff addr=0x8000200c
   [REGFILE_WB] Writing rd=x13 data=ffffffff (wb_sel=001 alu=8000200c mem=ffffffff mul_div=00000000)
   ```
   - Memory correctly returns 0xffffffff from address 0x8000200c
   - wb_sel=001 confirms it's a memory load operation
   - The ALU calculated address 0x8000200c (this is the bug)

### The Problem IS with Address Calculation

The test is loading from the **wrong address**:

| What | Expected | Actual | Difference |
|------|----------|--------|------------|
| Load address | 0x8000203c | 0x8000200c | -0x30 (-48 bytes) |
| Base register (a0) | 0x80002030 | 0x80002000 | -0x30 (-48 bytes) |

**Instruction**: `lw a3, 12(a0)` at offset 0x01b0 in hex file
- Decoded: opcode=0x03 (LW), rd=13 (a3), rs1=10 (a0), imm=12
- Expected address: a0 + 12 = 0x80002030 + 12 = 0x8000203c ✅
- Actual address: a0 + 12 = 0x80002000 + 12 = 0x8000200c ❌

**Offset Analysis**: 48 bytes = 12 words = 12 test data entries
- This suggests a systematic shift in test data table indexing
- Register a0 should point to test #5's data but points to wrong location

---

## When It Broke

### Working Commit
- **Commit**: 7dc1afd
- **Message**: "Bug #42 Fixed: C.JAL/C.JALR Return Address - rv32uc-p-rvc PASSING!"
- **Test result**: rv32uf-p-fcvt_w **PASSING** ✅

### Broken Commit Range
- **First broken**: d7c2d33
- **Message**: "WIP: RV32D Support - FLEN Refactoring (Bugs #27 & #28 Partial)"
- **Completed in**: 747a716 "Bug #27 & #28 COMPLETE: RV32D Memory Interface"
- **Test result**: rv32uf-p-fcvt_w **FAILING** ❌

### Changes in FLEN Refactoring

The FLEN refactoring changed:
1. **data_memory.v**: Widened read_data/write_data from XLEN to 64-bit
2. **Pipeline registers**: Added separate fp_mem_read_data paths
3. **Memory interface**: Changed from XLEN-based to fixed 64-bit

**Relevant change in data_memory.v**:
```verilog
// BEFORE (working):
3'b010: begin  // LW
  if (XLEN == 64)
    read_data = {{32{word_data[31]}}, word_data};  // Sign-extend for RV64
  else
    read_data = word_data;  // RV32: just return word_data (implies zero-extend to 64-bit reg)
end

// AFTER (broken):
3'b010: begin  // LW
  // Sign-extend for RV64 LD, but upper bits will be ignored for FLW
  read_data = {{32{word_data[31]}}, word_data};  // Always sign-extend
end
```

However, this change is **NOT the bug** - the memory is returning correct data from the address it receives.

---

## What's NOT the Issue

✅ **Memory module**: Returns correct data for the address it receives
✅ **Sign extension**: Working correctly (0xffffffff with MSB=1 → 0xffffffffffffffff)
✅ **Hex file**: Contains correct expected values at correct offsets
✅ **LW instruction decode**: Correctly identified as integer load (opcode=0x03)
✅ **Memory read path**: wb_sel correctly selects memory data
✅ **Lower 32-bit extraction**: Correctly takes arb_mem_read_data[31:0]

---

## What MIGHT Be the Issue

### Theory 1: Earlier Test Sets a0 Incorrectly
- Tests #1-#4 must pass (since gp=5)
- But one of them may compute an incorrect result
- That incorrect result gets used to set up a0 for test #5
- Need to trace through tests #1-#4 to find which one produces wrong output

### Theory 2: Test Data Pointer Initialization
- RISC-V tests use PC-relative addressing (AUIPC + ADDI) to compute data addresses
- If PC values changed or if AUIPC behavior changed, addresses could be off
- 48-byte offset suggests systematic shift in data table base

### Theory 3: Register Forwarding/Hazard Detection
- FLEN refactoring changed pipeline register widths
- Possible that forwarding logic for integer registers was affected
- Some forwarded value might be truncated or sign-extended incorrectly

### Theory 4: Hidden Side Effect in Pipeline
- 64-bit memory interface might affect some instruction's behavior
- Possible interaction between FP and integer register file
- Some instruction might write wrong value to integer register as side effect

---

## Debug Evidence

### Memory Read Debug Output
```
[MEM_READ] Integer load: arb_mem_read_data=0xffffffffffffffff mem_read_data=0xffffffff addr=0x8000200c
[MEM_READ] Integer load: arb_mem_read_data=0xffffffffffffffff mem_read_data=0xffffffff addr=0x8000200c
[MEM_READ] Integer load: arb_mem_read_data=0xffffffffffffffff mem_read_data=0xffffffff addr=0x8000200c
[MEM_READ] Integer load: arb_mem_read_data=0xffffffffffffffff mem_read_data=0xffffffff addr=0x8000200c
```
- Load occurs 4 times (likely pipeline stalls or debug artifact)
- Consistently reads from 0x8000200c (wrong address)

### Writeback Debug Output
```
[REGFILE_WB] @0 Writing rd=x13 data=00000000 (wb_sel=000 alu=00000000 mem=00000000 mul_div=00000000)
[REGFILE_WB] @0 Writing rd=x13 data=ffffffff (wb_sel=001 alu=8000200c mem=ffffffff mul_div=00000000)
```
- First write: a3 = 0x00000000 (initialization?)
- Second write: a3 = 0xffffffff from memory load
- wb_sel=001 confirms memory load operation
- alu=8000200c shows the calculated address (wrong!)

### Hex File Contents
```python
# Offset 0x200c (address 0x8000200c):
Bytes: ff ff ff ff 00 00 80 bf
Word (LE): 0xffffffff  ❌ Wrong location
DWord (LE): 0xbf800000ffffffff

# Offset 0x203c (address 0x8000203c):
Bytes: 00 00 00 00
Word (LE): 0x00000000  ✅ Correct expected value
```

### LW Instruction Details
```
Offset: 0x01b0
Bytes: 83 26 c5 00
Instruction: 0x00c52683
Decoded:
  opcode: 0b0000011 (0x03) = LW ✅
  rd:     13 (a3)
  funct3: 010 (word load)
  rs1:    10 (a0)
  imm:    12
Meaning: lw a3, 12(a0)
```

### Final Register State
```
x3  (gp)   = 0x00000005  (test number 5)
x10 (a0)   = 0x00000000  (base address - modified after test?)
x13 (a3)   = 0xffffffff  (loaded value - WRONG!)
```

---

## Investigation Steps for Next Session

### Step 1: Trace a0 Value Through Tests #1-#4
Add debug to track a0 (x10) writes:
```verilog
`ifdef DEBUG_A0_TRACKING
always @(posedge clk) begin
  if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd10) begin
    $display("[A0_WRITE] @cycle %0d: x10 <= 0x%08h (wb_sel=%b source=%s)",
             cycle_count, wb_data, memwb_wb_sel,
             (memwb_wb_sel == 3'b000) ? "ALU" :
             (memwb_wb_sel == 3'b001) ? "MEM" :
             (memwb_wb_sel == 3'b010) ? "PC+4" : "OTHER");
  end
end
`endif
```

### Step 2: Compare Instruction-by-Instruction Execution
Run both working and broken commits with full instruction trace:
```bash
# Working commit (7dc1afd)
git checkout 7dc1afd
DEBUG_TRACE=1 ./tools/run_official_tests.sh uf fcvt_w > trace_working.log 2>&1

# Broken commit (main)
git checkout main
DEBUG_TRACE=1 ./tools/run_official_tests.sh uf fcvt_w > trace_broken.log 2>&1

# Compare
diff -u trace_working.log trace_broken.log | less
```

### Step 3: Check PC-Relative Address Calculations
Look for AUIPC instructions that might compute test data base addresses:
```bash
riscv64-unknown-elf-objdump -d tests/official-compliance/rv32uf-p-fcvt_w.elf | grep -E "(auipc|lui)" | head -20
```

### Step 4: Bisect to Find Exact Breaking Commit
```bash
git bisect start main 7dc1afd
git bisect run bash -c "make clean && env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf fcvt_w 2>&1 | grep -q PASSED"
```

### Step 5: Check for Integer/FP Register Confusion
Verify that no FP operations are accidentally writing to integer registers:
- Check control signals for test #1-#4
- Look for int_reg_write_fp being set when it shouldn't be
- Verify FP-to-INT result path (wb_sel=110) isn't being used incorrectly

---

## Workaround

**None currently**. The test cannot pass until this is fixed.

---

## Impact Assessment

### Current RV32F Test Status
- **Overall**: 10/11 (90%) ✅
- **Blocked by this bug**: rv32uf-p-fcvt_w only
- **Other tests**: All passing, including:
  - fadd, fclass, fcmp, fcvt, fdiv, fmadd, fmin, ldst, move, recoding ✅

### Severity Justification
- **Medium severity** because:
  - Only affects 1 test out of 11 (9% failure rate)
  - Other FP-to-INT conversions work (fcvt test passes)
  - Likely an isolated issue with test data addressing
  - Does NOT indicate fundamental FPU or memory bug

---

## Related Files

### Core Implementation
- `rtl/memory/data_memory.v` - Memory module (verified working)
- `rtl/core/rv32i_core_pipelined.v` - Pipeline integration
- `rtl/core/exmem_register.v` - EX/MEM pipeline register
- `rtl/core/memwb_register.v` - MEM/WB pipeline register

### Test Files
- `tests/official-compliance/rv32uf-p-fcvt_w.hex` - Test hex file
- `tests/official-compliance/rv32uf-p-fcvt_w.elf` - Test ELF (if available)

### Documentation
- `docs/SESSION_2025-10-22_RV32D_FLEN_REFACTORING.md` - FLEN refactoring details
- `docs/SESSION_2025-10-23_BUGS_44_45_FMA_FMV.md` - Recent bug fixes (Bugs #44, #45)

---

## Next Steps

1. **Immediate**: Add comprehensive debug tracing for a0 register
2. **Short-term**: Bisect to find exact breaking commit
3. **Medium-term**: Compare instruction traces between working and broken versions
4. **Long-term**: Consider if FLEN refactoring needs architectural review

---

## Debug Commands for Next Session

```bash
# Compile with a0 tracking debug
iverilog -g2012 -I"rtl" -DXLEN=32 -DFLEN=64 -DCOMPLIANCE_TEST -DDEBUG_A0_TRACKING \
  -DMEM_FILE='"tests/official-compliance/rv32uf-p-fcvt_w.hex"' \
  -o sim/test_fcvt_w_debug.vvp \
  rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v

# Run with full trace
timeout 5s vvp sim/test_fcvt_w_debug.vvp 2>&1 | tee debug_fcvt_w_a0_trace.log

# Check a0 writes before the failing load
grep "A0_WRITE" debug_fcvt_w_a0_trace.log
```

---

*Investigation started 2025-10-23. To be continued in next session.*
