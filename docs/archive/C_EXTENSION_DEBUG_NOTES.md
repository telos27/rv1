# C Extension Debug Notes - Simulation Hang Issue

**Date**: 2025-10-12
**Priority**: HIGH - Blocking C extension integration testing

---

## Problem Statement

Icarus Verilog simulation **hangs after first clock cycle** when executing compressed instructions. The hang occurs specifically when `if_is_compressed = 1`.

### Symptoms

```
=== Starting Debug Test ===
Cycle  1: PC=0x00000000, IF_Instr=0x00000513, is_c=1, stall=0, x10=0
Waiting for clock edge...
[HANG - No further output]
```

- ✅ First cycle executes correctly
- ✅ Compressed instruction detected (`is_c=1`)
- ✅ Correct decompression (`0x4501` → `0x00000513`)
- ❌ Second clock edge never arrives (simulation freezes)

### What Works

- ✅ **Non-compressed instructions**: `simple_add` test passes completely
- ✅ **RVC decoder unit tests**: 34/34 passing (standalone)
- ✅ **First cycle with compressed**: Executes and produces correct output

### What Doesn't Work

- ❌ **Second cycle onwards** when compressed instructions are present
- ❌ Affects both `CONFIG_RV32I` and `CONFIG_RV32IMC`

---

## Investigation Done

### 1. Verified No Combinational Loop

Signal path analysis:
```
pc_current → imem.addr → if_instruction_raw → if_compressed_instr_candidate →
rvc_dec.compressed_instr → if_is_compressed → pc_increment → pc_next →
[clock edge] → pc_current
```

**Result**: Feedback properly goes through clocked PC register. Not a combinational loop.

### 2. Tested Different Configurations

| Config | C Extension | Result |
|--------|-------------|--------|
| CONFIG_RV32I | Disabled | HANG |
| CONFIG_RV32IMC | Enabled | HANG |

**Result**: Config doesn't affect the hang.

### 3. Compared Compressed vs Non-Compressed

| Test | Instructions | is_c | Result |
|------|--------------|------|--------|
| simple_add | 32-bit only | 0 | PASS ✅ |
| test_rvc_simple | 16-bit (compressed) | 1 | HANG ❌ |

**Result**: Issue is specific to `is_compressed = 1` condition.

### 4. Verified Decoder Works Standalone

```bash
vvp sim/test_rvc_only.vvp
# Result: ALL TESTS PASSED! (34/34)
```

**Result**: Decoder logic is correct. Issue is in integration.

### 5. Checked Clock Generation

```verilog
initial begin
  clk = 0;
  forever #5 clk = ~clk;
end
```

**Result**: Clock generation is standard and correct.

---

## Debug Files Created

### Test Programs

1. **tests/asm/test_rvc_simple.s** - Minimal compressed instruction test
   ```assembly
   c.li    x10, 0      # 0x4501
   c.addi  x10, 10     # 0x0529
   c.li    x11, 5      # 0x4595
   c.add   x10, x11    # 0x952e
   # ... etc
   ```

2. **tests/asm/test_rvc_simple.hex** - Compiled (correct format)
   ```
   @00000000
   01 45 29 05 95 45 2E 95 31 05 3D 46 32 95 02 90
   ```

### Testbenches

1. **tb/integration/tb_rvc_simple.v** - Full integration test
2. **tb/integration/tb_debug_simple.v** - Minimal debug testbench with instrumentation

### Scripts

1. **run_vvp_timeout.sh** - Helper to run vvp with 2-second timeout
   ```bash
   #!/bin/bash
   timeout 2 vvp "$@" 2>&1
   ```

---

## Compilation and Run Commands

### Compile Debug Testbench
```bash
cd /home/lei/rv1

# With RV32I config (C disabled)
iverilog -g2012 -Irtl -DCONFIG_RV32I -o sim/tb_debug.vvp \
  rtl/core/*.v \
  rtl/memory/*.v \
  tb/integration/tb_debug_simple.v

# With RV32IMC config (C enabled)
iverilog -g2012 -Irtl -DCONFIG_RV32IMC -o sim/tb_debug.vvp \
  rtl/core/*.v \
  rtl/memory/*.v \
  tb/integration/tb_debug_simple.v
```

### Run with Timeout
```bash
./run_vvp_timeout.sh sim/tb_debug.vvp
```

### Test Non-Compressed (Baseline)
Edit `tb/integration/tb_debug_simple.v` line 19:
```verilog
.MEM_FILE("tests/asm/simple_add.hex")  // Works fine
```

### Test Compressed (Hangs)
Edit `tb/integration/tb_debug_simple.v` line 19:
```verilog
.MEM_FILE("tests/asm/test_rvc_simple.hex")  // Hangs after cycle 1
```

---

## Key Code Sections to Investigate

### 1. RVC Decoder Instantiation (rv32i_core_pipelined.v:396-415)

```verilog
// RVC Decoder (C Extension - Compressed Instruction Decompressor)
wire [15:0] if_compressed_instr_candidate;
wire [31:0] if_instruction_decompressed;

// If PC[1] is set, we're at a 2-byte aligned but not 4-byte aligned address
assign if_compressed_instr_candidate = pc_current[1] ? if_instruction_raw[31:16] :
                                                        if_instruction_raw[15:0];

rvc_decoder #(
  .XLEN(XLEN)
) rvc_dec (
  .compressed_instr(if_compressed_instr_candidate),
  .is_rv64(XLEN == 64),
  .decompressed_instr(if_instruction_decompressed),
  .illegal_instr(if_illegal_c_instr),
  .is_compressed_out(if_is_compressed)  // ← This signal is used for PC increment
);

// Select final instruction
assign if_instruction = if_is_compressed ? if_instruction_decompressed : if_instruction_raw;
```

### 2. PC Increment Logic (rv32i_core_pipelined.v:339-362)

```verilog
// PC calculation (support both 2-byte and 4-byte increments for C extension)
assign pc_plus_2 = pc_current + {{(XLEN-2){1'b0}}, 2'b10};
assign pc_plus_4 = pc_current + {{(XLEN-3){1'b0}}, 3'b100};
assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;  // ← Suspect line

// PC selection: priority order - trap > mret > branch/jump > PC+increment
assign pc_next = trap_flush ? trap_vector :
                 mret_flush ? mepc :
                 ex_take_branch ? (idex_jump ? ex_jump_target : ex_branch_target) :
                 pc_increment;  // ← Uses if_is_compressed indirectly
```

### 3. RVC Decoder Always Block (rvc_decoder.v:184-520)

```verilog
always @(*) begin
  illegal_instr = 1'b0;
  decompressed_instr = 32'h00000013;  // Default: NOP

  case (opcode)
    2'b00: begin  // Quadrant 0
      // ... lots of case statements
    end
    // ... more quadrants
  endcase
end
```

**Potential Issue**: `decompressed_instr` and `illegal_instr` are `reg` types in combinational block. Could this cause Icarus Verilog evaluation issues?

---

## Hypotheses to Test

### Hypothesis 1: Icarus Verilog Evaluation Order

**Theory**: Icarus Verilog may have issues with the specific signal dependency chain when `if_is_compressed` changes.

**Test**:
1. Add explicit `wire` versions of critical signals
2. Break up long combinational chains
3. Try with Verilator instead

### Hypothesis 2: X (Unknown) Propagation

**Theory**: Some signal may be X during reset or first cycle, causing hang when used in mux.

**Test**:
```bash
# Check VCD for X values
gtkwave sim/waves/tb_rvc_simple.vcd
# Look for red (X) signals around cycle 1
```

### Hypothesis 3: Sensitivity List Issue

**Theory**: Some `always @(*)` block may be missing a signal, causing it not to re-evaluate.

**Test**:
1. Check all `always @(*)` blocks in the path
2. Replace with `always_comb` (SystemVerilog)
3. Manually list all signals in sensitivity list

### Hypothesis 4: Integer Width Issue

**Theory**: The `{{(XLEN-2){1'b0}}, 2'b10}` construction may cause issues.

**Test**:
```verilog
// Replace:
assign pc_plus_2 = pc_current + {{(XLEN-2){1'b0}}, 2'b10};

// With explicit:
assign pc_plus_2 = pc_current + 32'd2;
```

### Hypothesis 5: Nested Ternary Issue

**Theory**: The nested ternary in `pc_next` assignment may confuse Icarus Verilog.

**Test**:
```verilog
// Replace nested ternary with if-else in always block
always @(*) begin
  if (trap_flush)
    pc_next = trap_vector;
  else if (mret_flush)
    pc_next = mepc;
  else if (ex_take_branch)
    pc_next = idex_jump ? ex_jump_target : ex_branch_target;
  else
    pc_next = pc_increment;
end
```

### Hypothesis 6: $clog2 Evaluation

**Theory**: `$clog2` in config file may not evaluate at right time.

**Test**:
Replace config usages with explicit values:
```verilog
// In rv_config.vh, replace:
`define SHAMT_WIDTH  ($clog2(`XLEN))

// With explicit:
`define SHAMT_WIDTH  5  // For RV32
```

---

## Quick Experiments to Try Next Session

### Experiment 1: Simplify PC Increment (5 min)

```verilog
// In rv32i_core_pipelined.v:342
// Replace:
assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;

// With forced constant:
assign pc_increment = pc_plus_4;  // Always +4, ignore compression
```

**Expected**: If this "fixes" the hang, confirms issue is in `if_is_compressed` usage.

### Experiment 2: Force Decompression Off (5 min)

```verilog
// In rv32i_core_pipelined.v:421
// Replace:
assign if_instruction = if_is_compressed ? if_instruction_decompressed : if_instruction_raw;

// With:
assign if_instruction = if_instruction_raw;  // Never use decompressed
```

**Expected**: If this "fixes" the hang, confirms issue is in decompressed instruction path.

### Experiment 3: Hardcode is_compressed (5 min)

```verilog
// In rv32i_core_pipelined.v, add after RVC decoder instantiation:
assign if_is_compressed = 1'b0;  // Force to always non-compressed
```

**Expected**: If this "fixes" the hang, confirms issue is specifically in the `if_is_compressed` signal.

### Experiment 4: Try Verilator (15 min)

```bash
# Install Verilator (if not installed)
sudo apt-get install verilator

# Compile with Verilator
verilator --cc --exe --build -j 0 \
  -Irtl \
  -DCONFIG_RV32IMC \
  rtl/core/*.v \
  rtl/memory/*.v \
  tb/integration/tb_debug_simple.v

# Run
./obj_dir/Vtb_debug_simple
```

**Expected**: If Verilator works, confirms Icarus Verilog specific bug.

### Experiment 5: Add Pipeline Registers (30 min)

Add a pipeline register to break the `if_is_compressed` combinational path:

```verilog
// Add in IF/ID pipeline register
reg if_is_compressed_r;
always @(posedge clk) begin
  if_is_compressed_r <= if_is_compressed;
end

// Use registered version for PC
assign pc_increment = if_is_compressed_r ? pc_plus_2 : pc_plus_4;
```

**Note**: This changes behavior (adds 1-cycle latency) but tests if it's a timing/evaluation issue.

---

## Debugging Checklist for Next Session

- [ ] Run Experiment 1 (force pc_increment to pc_plus_4)
- [ ] Run Experiment 2 (force if_instruction to if_instruction_raw)
- [ ] Run Experiment 3 (hardcode if_is_compressed to 0)
- [ ] Check VCD for X (unknown) values in critical signals
- [ ] Try with Verilator instead of Icarus Verilog
- [ ] Add $display statements in RVC decoder to trace evaluation
- [ ] Check if FPU or other modules are interfering
- [ ] Simplify testbench to absolute minimum (no register checking)
- [ ] Try synthesis instead of simulation (check if it's sim-only issue)

---

## Important File Locations

### Source Files
- `rtl/core/rv32i_core_pipelined.v` - Main pipeline (lines 396-421 for RVC integration)
- `rtl/core/rvc_decoder.v` - RVC decoder module (proven correct via unit tests)
- `rtl/core/pc.v` - PC register module
- `rtl/memory/instruction_memory.v` - Instruction memory

### Test Files
- `tests/asm/test_rvc_simple.s` - Test source
- `tests/asm/test_rvc_simple.hex` - Test hex file (correct format)
- `tb/integration/tb_debug_simple.v` - Debug testbench (EDIT THIS for experiments)

### Documentation
- `docs/C_EXTENSION_DESIGN.md` - Complete design specification
- `docs/C_EXTENSION_PROGRESS.md` - Progress tracking (100% decoder)
- `docs/C_EXTENSION_STATUS.md` - Overall status summary
- `docs/C_EXTENSION_DEBUG_NOTES.md` - This file

---

## Reproduction Steps

1. **Ensure correct directory**: `cd /home/lei/rv1`

2. **Compile testbench**:
   ```bash
   iverilog -g2012 -Irtl -DCONFIG_RV32IMC -o sim/tb_debug.vvp \
     rtl/core/*.v \
     rtl/memory/*.v \
     tb/integration/tb_debug_simple.v
   ```

3. **Run with timeout**:
   ```bash
   ./run_vvp_timeout.sh sim/tb_debug.vvp
   ```

4. **Observe hang**:
   - Prints "Cycle 1" correctly
   - Prints "Waiting for clock edge..."
   - **Hangs indefinitely** (killed by timeout after 2 seconds)

5. **Confirm baseline works**:
   - Edit `tb_debug_simple.v` line 19 to use `simple_add.hex`
   - Recompile and run
   - Should print all 20 cycles successfully

---

## Success Criteria

The issue will be considered **RESOLVED** when:

1. ✅ `test_rvc_simple` test completes all cycles without hanging
2. ✅ PC correctly increments by 2 for compressed instructions
3. ✅ Compressed instructions execute and produce correct results
4. ✅ Can run through EBREAK and complete test
5. ✅ All registers show expected values at end

---

## Notes

- The RVC decoder itself is **100% correct** (proven by unit tests)
- The integration is **structurally correct** (all signals connected properly)
- This appears to be a **tool-specific** simulation issue
- If unfixable in Icarus Verilog, consider:
  - Using Verilator for C extension testing
  - Testing on actual FPGA hardware
  - Documenting as known Icarus Verilog limitation

---

**Last Updated**: 2025-10-12
**Next Session**: Start with Experiment 1-3 (5 minutes each) to narrow down the issue
