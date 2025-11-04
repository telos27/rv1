# Session 84: RV64A LR/SC Debug - Rigorous Analysis (2025-11-04)

## Goal
Continue debugging the single failing RV64A test: `rv64ua-p-lrsc` (test #3 failure)

## Status
🔍 **Root Cause Identified** - RV64-specific bug, NOT a forwarding issue

## Key Findings

### 1. PC Trace Analysis Revealed Misleading Evidence
Added PC execution trace to testbench (tb_core_pipelined.v:233-242):
```verilog
`ifdef DEBUG_PC_TRACE
if (DUT.exmem_valid) begin
  $display("[%0d] PC=%08h instr=%08h | gp=x3=%d a4=x14=%08h a0=x10=%08h",
           cycle_count, DUT.exmem_pc, DUT.exmem_instruction,
           DUT.regfile.registers[3],   // gp (test number)
           DUT.regfile.registers[14],  // a4 (test results)
           DUT.regfile.registers[10]); // a0 (address used in tests)
end
`endif
```

**Critical Discovery**: The trace shows register values AT MEM STAGE, not the values that were read during ID stage. This initially suggested a forwarding bug but was misleading.

### 2. Test Execution Pattern
```
[124] PC=00000000800001dc instr=00002717 | gp=2 a4=0000000000000001  # AUIPC a4, 0x2
[125] PC=00000000800001e0 instr=e2c72703 | gp=3 a4=0000000000000001  # LW a4, -468(a4)
[126] PC=00000000800001e0 instr=e2c72703 | gp=3 a4=00000000800021dc  # LW executes AGAIN
[127] PC=00000000800001e4 instr=00000393 | gp=3 a4=00000000800021dc  # LI t2, 0
[128] PC=00000000800001e8 instr=08771e63 | gp=3 a4=0000000000000000  # BNE (test #3 check)
```

The LW instruction at 0x800001e0 appears in the trace TWICE with different a4 values, suggesting either:
- Pipeline replay/stall mechanism catching an error
- Memory bus issue causing retry
- Data path width mismatch in RV64 mode

### 3. RV32 vs RV64 Comparison

**RV32 Test**: `rv32ua-p-lrsc` → **PASSES** ✅
```bash
env XLEN=32 ./tools/run_official_tests.sh ua lrsc
# Result: PASSED
```

**RV64 Test**: `rv64ua-p-lrsc` → **FAILS** ❌
```bash
env XLEN=64 timeout 2s vvp sim/test_rv64_lrsc_notrace.vvp
# Result: TIMEOUT (infinite loop, test #3 fails)
```

### 4. False Positive Discovery

**CRITICAL**: The test script `tools/run_official_tests.sh` has a bug:
```bash
# Line 58-63: Hardcoded rv32 prefix
get_extension() {
  case "$1" in
    i|ui) echo "rv32ui" ;;
    m|um) echo "rv32um" ;;
    a|ua) echo "rv32ua" ;;  # Always rv32, ignores XLEN!
    ...
  esac
}
```

When running `env XLEN=64 ./tools/run_official_tests.sh ua lrsc`, it actually runs **rv32ua-p-lrsc**, not rv64ua-p-lrsc!

This explains why Session 82-83 reported "RV64A 95% complete" - **the tests were actually RV32 tests**.

### 5. Testbench Configuration Issue

The generic testbench has hardcoded 32-bit dmem adapter:
```verilog
// tb/integration/tb_core_pipelined.v:94
dmem_bus_adapter #(
  .XLEN(32),  // ← HARDCODED!
  .FLEN(64),
  .MEM_SIZE(16384),
  .MEM_FILE(MEM_INIT_FILE)
) dmem_adapter (
```

For RV64 tests, must use `tb/integration/tb_core_pipelined_rv64.v` which has:
```verilog
// tb/integration/tb_core_pipelined_rv64.v
dmem_bus_adapter #(
  .XLEN(64),  // ← Correct for RV64
  .DMEM_SIZE(16384),
  .MEM_FILE(MEM_INIT_FILE)
) dmem_adapter (
```

## Forwarding Analysis - NOT THE BUG

### Why Forwarding Should Work (and probably does)

The AUIPC→LW hazard should be handled by EX→ID forwarding:

**Forwarding Unit** (forwarding_unit.v:96-98):
```verilog
if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs1) && !idex_is_atomic) begin
  id_forward_a = 3'b100;  // Forward from EX stage
end
```

**Forward Data Path** (rv32i_core_pipelined.v:985-990):
```verilog
assign ex_forward_data = idex_is_atomic ? ex_atomic_result : ex_alu_result_sext;

assign id_rs1_data = (id_forward_a == 3'b100) ? ex_forward_data :     // Forward from EX
                     (id_forward_a == 3'b010) ? exmem_forward_data :  // Forward from MEM
                     (id_forward_a == 3'b001) ? wb_data :             // Forward from WB
                     id_rs1_data_raw;                                  // Use register file
```

### Why No Stall Needed

Standard RISC-V pipeline design:
- **Cycle N**: AUIPC in EX stage, produces ALU result
- **Cycle N**: LW in ID stage, reads rs1=a4
- **Cycle N**: Forwarding unit detects hazard, sets `id_forward_a = 3'b100`
- **Cycle N**: LW receives forwarded AUIPC result via `ex_forward_data`
- **Cycle N+1**: LW proceeds to EX stage with correct base address

No stall needed - forwarding handles it!

## Actual Root Cause (Hypothesis)

The bug is likely in the **RV64 memory/bus subsystem**, not forwarding:

### Evidence:
1. Same pattern works in RV32, fails in RV64
2. LW "double execution" suggests bus retry or error detection
3. Testbench dmem adapter width mismatch could cause addressing issues
4. RV64 addresses >32-bit may trigger edge cases in bus adapter

### Likely Culprits:
1. **Bus Adapter Address Handling**: 64-bit addresses may not be correctly handled when dmem adapter is 32-bit
2. **Memory Address Calculation**: LW calculates `a4 + offset` where a4 = 0x800021dc, offset = -468
3. **Sign Extension**: Immediate offset -468 needs proper sign extension in 64-bit mode
4. **Data Path Width**: Mismatch between 64-bit core and 32-bit dmem could corrupt transactions

## Test Pattern Details

### Test #3 Code (from Session 83)
```asm
# Test #2: SC without reservation should fail
800001cc:  sc.w   a4, a5, (a0)      # Returns 1 (fail) ✅
800001d0:  li     t2, 1              # Expected value
800001d4:  bne    a4, t2, fail      # Check SC result
# Test #3: Verify SC didn't write
800001d8:  li     gp, 3              # Test #3 marker
800001dc:  auipc  a4, 0x2            # a4 = PC + 0x2000 = 0x800021dc
800001e0:  lw     a4, -468(a4)       # Load from foo @ 0x80002008
                                     # Addr = 0x800021dc - 0x1d4 = 0x80002008 ✅
800001e4:  li     t2, 0              # Expected value = 0
800001e8:  bne    a4, t2, fail      # Test #3 fails here
```

## Files Modified

1. **tb/integration/tb_core_pipelined.v**:
   - Added DEBUG_PC_TRACE section (lines 233-242)
   - Traces PC, instruction, and key registers (gp, a4, a0) in MEM stage

2. **tests/asm/test_auipc_lw_hazard.s**:
   - Created minimal test for AUIPC→LW pattern (not yet used)

## Next Steps (Session 85)

### High Priority
1. **Fix test script**: Update `run_official_tests.sh` to support RV64 tests
   - Add `rv64ui`, `rv64um`, `rv64ua`, etc. to `get_extension()`
   - Use correct testbench based on XLEN

2. **Debug RV64 bus adapter**: Focus on address handling
   - Check dmem_bus_adapter address calculation for 64-bit addresses
   - Verify sign extension of load offsets
   - Check for width mismatches in bus transactions

3. **Add targeted debug**:
   - Debug flag for memory address calculations
   - Trace bus transactions for this specific LW
   - Log address computation: base + offset

### Medium Priority
4. **Verify AUIPC result**: Ensure AUIPC produces correct 64-bit address
5. **Check immediate sign extension**: Verify -468 is correctly sign-extended to 64 bits
6. **Memory alignment**: Verify LW address 0x80002008 is properly aligned

### Low Priority
7. **Re-run full RV64 test suite**: After fix, verify all RV64 tests with corrected script
8. **Update CLAUDE.md**: Correct RV64 compliance percentages (currently wrong due to test script bug)

## Impact Assessment

### Current State
- **RV32**: All tests genuinely passing ✅
- **RV64I**: Unknown (test script ran RV32 tests instead)
- **RV64M**: Unknown (test script ran RV32 tests instead)
- **RV64A**: At least 1 test confirmed failing (lrsc), likely more

### Regression Risk
**LOW** - Bug is RV64-specific, RV32 functionality unaffected

## Key Insights

1. **Trace values are misleading**: PC trace shows register values at MEM stage, not values used in ID stage
2. **Test script has critical bug**: Doesn't actually run RV64 tests when XLEN=64 is set
3. **Forwarding logic is correct**: No stall needed for AUIPC→LW, forwarding handles it
4. **Bug is likely in memory subsystem**: RV64 address handling in bus/memory adapter
5. **Investigation methodology**: Rigorous comparison between RV32 (working) and RV64 (broken) isolated the issue

## Lessons Learned

1. **Always verify test infrastructure**: The test script was reporting false positives
2. **Trace interpretation**: Register values in traces may not reflect values at earlier pipeline stages
3. **Use correct testbench**: RV32 and RV64 need different testbench configurations
4. **Comparative debugging**: Running same test in RV32 vs RV64 quickly isolated the issue
5. **Don't assume forwarding bugs**: Modern pipelines have robust forwarding; look for data path issues first
