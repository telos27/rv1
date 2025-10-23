# Next Session Starting Point

**Date**: 2025-10-23
**Last Session**: Bug #48 Investigation - FCVT_W Address Calculation
**Current Status**: 10/11 RV32F tests passing (90%) ✅

---

## Current Test Status

### RV32F (Single-Precision Floating Point)
**Overall**: 10/11 tests passing (90%)

| Test | Status | Notes |
|------|--------|-------|
| fadd | ✅ PASS | Addition/subtraction working |
| fclass | ✅ PASS | FP classification working |
| fcmp | ✅ PASS | FP comparison working |
| fcvt | ✅ PASS | Sign injection (FSGNJ) working |
| fcvt_w | ❌ FAIL | **Bug #48: Address calculation error** |
| fdiv | ✅ PASS | Division and sqrt working |
| fmadd | ✅ PASS | Fused multiply-add working |
| fmin | ✅ PASS | Min/max operations working |
| ldst | ✅ PASS | FP load/store working |
| move | ✅ PASS | FP move operations working |
| recoding | ✅ PASS | NaN recoding working |

---

## Current Issue: Bug #48 - FCVT_W Address Calculation Error

### Quick Summary
- **Test**: rv32uf-p-fcvt_w fails at test #5
- **Symptom**: a3 = 0xffffffff instead of 0x00000000
- **Root Cause**: Register a0 contains wrong base address
  - **Expected**: a0 = 0x80002030
  - **Actual**: a0 = 0x80002000
  - **Offset**: -48 bytes (-0x30)
- **Result**: Load from wrong address (0x8000200c instead of 0x8000203c)

### What We Know
✅ Memory subsystem works correctly (returns right data for address it receives)
✅ LW instruction decodes correctly
✅ Sign extension works correctly
✅ Tests #1-#4 pass (gp=5 means failure at test #5)
❌ Something in tests #1-#4 sets a0 to wrong value
❌ 48-byte offset suggests data table addressing issue

### Investigation Status
- ✅ **Root cause identified**: a0 register has wrong value
- ✅ **Debug methodology established**: See action plan below
- ❌ **Not yet fixed**: Need to find which instruction sets a0 incorrectly
- 📄 **Full documentation**: `docs/BUG_48_FCVT_W_ADDRESS_CALCULATION.md`
- 📄 **Session notes**: `docs/SESSION_2025-10-23_BUG48_INVESTIGATION.md`

---

## Next Session Action Plan

### Step 1: Add a0 Tracking Debug (RECOMMENDED START)

Add this to `rtl/core/rv32i_core_pipelined.v`:

```verilog
// Debug: Track writes to a0 (x10)
`ifdef DEBUG_A0_TRACKING
  integer cycle_count_a0;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      cycle_count_a0 <= 0;
    else
      cycle_count_a0 <= cycle_count_a0 + 1;
  end

  always @(posedge clk) begin
    if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd10) begin
      $display("[A0_WRITE] cycle=%0d x10 <= 0x%08h (wb_sel=%b source=%s pc=0x%08h instr=0x%08h)",
               cycle_count_a0, wb_data, memwb_wb_sel,
               (memwb_wb_sel == 3'b000) ? "ALU" :
               (memwb_wb_sel == 3'b001) ? "MEM" :
               (memwb_wb_sel == 3'b010) ? "PC+4" :
               (memwb_wb_sel == 3'b110) ? "FP2INT" : "OTHER",
               memwb_pc, memwb_instruction);
    end
  end
`endif
```

Compile and run:
```bash
iverilog -g2012 -I"rtl" -DXLEN=32 -DFLEN=64 -DCOMPLIANCE_TEST \
  -DDEBUG_A0_TRACKING \
  -DMEM_FILE='"tests/official-compliance/rv32uf-p-fcvt_w.hex"' \
  -o sim/test_a0_debug.vvp \
  rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v

timeout 5s vvp sim/test_a0_debug.vvp 2>&1 | tee a0_trace.log

# Find when a0 gets set to wrong value
grep "A0_WRITE" a0_trace.log
```

Look for the write that sets a0 to 0x80002000 (should be 0x80002030).

### Step 2: Bisect to Find Exact Breaking Commit

```bash
git bisect start main 7dc1afd
git bisect run bash -c "make clean && env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf fcvt_w 2>&1 | grep -q PASSED"
```

This will automatically find the exact commit that introduced the bug.

### Step 3: Compare Working vs Broken Execution

If Step 1-2 don't reveal the issue, do full instruction trace comparison:

```bash
# Save current state
git stash

# Working commit
git checkout 7dc1afd
DEBUG_TRACE=1 ./tools/run_official_tests.sh uf fcvt_w > trace_working.log 2>&1

# Broken commit
git checkout main
git stash pop
DEBUG_TRACE=1 ./tools/run_official_tests.sh uf fcvt_w > trace_broken.log 2>&1

# Find first divergence
diff -u trace_working.log trace_broken.log | less
```

### Step 4: Check Test Disassembly

Understand test structure:
```bash
riscv64-unknown-elf-objdump -d tests/official-compliance/rv32uf-p-fcvt_w.elf > fcvt_w_disasm.txt

# Look for:
# 1. How a0 is initialized (look for auipc/lui to a0)
# 2. Test #1-#4 instructions
# 3. Any instructions that write to a0

grep -E "(auipc.*a0|lui.*a0|addi.*a0)" fcvt_w_disasm.txt
```

---

## Quick Commands

### Run Single Test
```bash
env XLEN=32 timeout 5s ./tools/run_official_tests.sh uf fcvt_w
```

### Run Full RV32F Suite
```bash
env XLEN=32 timeout 30s ./tools/run_official_tests.sh uf
```

### Check Test Log
```bash
cat sim/official-compliance/rv32uf-p-fcvt_w.log | tail -60
```

### Verify Hex File
```bash
python3 << 'EOF'
with open('tests/official-compliance/rv32uf-p-fcvt_w.hex', 'r') as f:
    lines = [line.strip() for line in f.readlines() if line.strip()]
# Check expected address
offset = 0x203c
bytes_val = [lines[offset+i] for i in range(4)]
word = f"0x{bytes_val[3]}{bytes_val[2]}{bytes_val[1]}{bytes_val[0]}"
print(f"Address 0x8000203c: {word}")  # Should be 0x00000000
# Check actual wrong address
offset = 0x200c
bytes_val = [lines[offset+i] for i in range(4)]
word = f"0x{bytes_val[3]}{bytes_val[2]}{bytes_val[1]}{bytes_val[0]}"
print(f"Address 0x8000200c: {word}")  # Is 0xffffffff
EOF
```

---

## Recent Progress

### Session 14 (2025-10-23) - Before Bug #48 Investigation
- ✅ **Bug #47 Fixed**: FSGNJ NaN-boxing for F+D mixed precision
- ✅ **rv32uf-p-move**: Now PASSING
- ✅ **RV32F**: Improved from 9/11 (81%) to 10/11 (90%)

### Session 13 (2025-10-23) - Bugs #44 & #45
- ✅ **Bug #44 Fixed**: FMA aligned_c positioning
- ✅ **Bug #45 Fixed**: FMV.W.X width mismatch
- ✅ **rv32uf-p-fmadd**: Now PASSING
- ✅ **RV32F**: Improved from 8/11 (72%) to 9/11 (81%)

### Earlier Sessions
- ✅ **Bug #43**: F+D mixed precision support (complete)
- ✅ **Bugs #27 & #28**: RV32D FLEN refactoring (this introduced Bug #48)
- ✅ **Bug #42**: C.JAL/C.JALR (last known good state for fcvt_w)

---

## Files to Review

### Bug #48 Documentation
- `docs/BUG_48_FCVT_W_ADDRESS_CALCULATION.md` - Full investigation report
- `docs/SESSION_2025-10-23_BUG48_INVESTIGATION.md` - Session notes

### Related Code
- `rtl/core/rv32i_core_pipelined.v` - Main pipeline (where to add debug)
- `rtl/memory/data_memory.v` - Memory module (verified working)
- `rtl/core/memwb_register.v` - MEM/WB pipeline register
- `rtl/core/exmem_register.v` - EX/MEM pipeline register

### Test Files
- `tests/official-compliance/rv32uf-p-fcvt_w.hex` - Test binary
- `sim/official-compliance/rv32uf-p-fcvt_w.log` - Test output

---

## Commits Reference

**Working commit** (fcvt_w passes):
```
7dc1afd - Bug #42 Fixed: C.JAL/C.JALR Return Address - rv32uc-p-rvc PASSING!
```

**Breaking commits** (fcvt_w starts failing):
```
d7c2d33 - WIP: RV32D Support - FLEN Refactoring (Bugs #27 & #28 Partial)
747a716 - Bug #27 & #28 COMPLETE: RV32D Memory Interface - 64-bit FP on 32-bit CPU
```

**Current commit**:
```
a55ddf2 - Documentation: Session 14 - Bug #47 Complete (FSGNJ NaN-Boxing)
```

---

## Expected Outcome

When Bug #48 is fixed:
- ✅ **rv32uf-p-fcvt_w** will PASS
- ✅ **RV32F**: 11/11 (100%) ✨
- 🎉 **Complete RV32F compliance!**

Then can move on to:
- RV32D (double-precision) testing and fixes
- Or other extensions/optimizations

---

## Key Debugging Insights

1. **Start with a0 tracking** - Most direct path to finding the bug
2. **Bisect if unclear** - Will pinpoint exact breaking change
3. **Trust the evidence** - Memory and load instructions work; a0 is wrong
4. **48-byte offset is systematic** - Not a random corruption, likely logic error
5. **Tests #1-#4 pass but corrupt a0** - Side effect of successful test

---

## Untracked Files (Clean Up Later)

```
tests/asm/test_fcvt_debug.hex
tests/asm/test_fcvt_debug.s
tests/asm/test_fcvt_w_debug.hex
tests/asm/test_fcvt_w_debug.s
```

These are debug test files from investigation. Can delete after Bug #48 is fixed.

---

## Quick Health Check

Before starting next session, verify baseline:

```bash
# Check current test status
env XLEN=32 timeout 30s ./tools/run_official_tests.sh uf

# Should see:
# rv32uf-p-fadd...      PASSED
# rv32uf-p-fclass...    PASSED
# rv32uf-p-fcmp...      PASSED
# rv32uf-p-fcvt...      PASSED
# rv32uf-p-fcvt_w...    FAILED  ← Bug #48
# rv32uf-p-fdiv...      PASSED
# rv32uf-p-fmadd...     PASSED
# rv32uf-p-fmin...      PASSED
# rv32uf-p-ldst...      PASSED
# rv32uf-p-move...      PASSED
# rv32uf-p-recoding...  PASSED
# Pass rate: 90% (10/11)
```

---

*Ready to fix Bug #48 and achieve 100% RV32F compliance! 🎯*
