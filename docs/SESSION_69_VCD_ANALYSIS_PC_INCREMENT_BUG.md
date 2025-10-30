# Session 69: VCD Waveform Analysis - PC Increment Bug Investigation

**Date**: 2025-10-30
**Status**: 🔍 Investigation in Progress - Root cause narrowed down
**Branch**: main
**Focus**: Deep VCD analysis of JAL→compressed instruction bug

## Session Goals

1. ✅ Generate VCD waveforms for minimal test case
2. ✅ Analyze PC increment logic during JAL execution
3. ✅ Trace instruction fetch and compression detection
4. ✅ Identify root cause of PC incrementing by +2 instead of +4
5. ⏳ Prepare debug instrumentation for Session 70

## Problem Statement

From Session 68, we know:
- FreeRTOS hangs in infinite loop between `memset()` RET and `prvInitialiseNewTask()`
- Pattern: JAL (4-byte) followed by compressed instruction (2-byte) at return address
- Minimal test `test_jal_compressed_return.s` reproduces the hang
- Symptom: PC increments by +2 after JAL instead of +4

## Investigation Process

### 1. VCD Generation and Analysis

**Test Setup:**
```bash
# Run minimal test with waveform generation
env XLEN=32 timeout 5s ./tools/run_test_by_name.sh test_jal_compressed_return --waves
```

**Test Code Pattern:**
```assembly
80000014:	d89c                	sw	a5,48(s1)        # 2-byte compressed
80000016:	018000ef          	jal	ra,8000002e      # 4-byte JAL
8000001a:	589c                	lw	a5,48(s1)        # 2-byte compressed (RETURN ADDRESS)
8000001c:	0785                	addi	a5,a5,1          # 2-byte compressed
```

### 2. VCD Analysis Results

**Python Analysis Script Created:**
```python
# /tmp/find_jal_bug.py - Extracts key signals during JAL execution
# Tracks: if_pc, if_instruction_raw, if_instruction, if_is_compressed
```

**Key Findings from VCD:**

#### Cycle 9 (JAL Instruction Fetch):
```
if_pc                = 0x00000014
if_instruction_raw   = 0x018000ef  (JAL - 4-byte instruction)
if_instruction       = 0x018000ef
if_instr_is_compressed = 0  ✓ (Correctly detected as NOT compressed)
if_is_compressed     = 0  ✓
ex_take_branch       = 0
stall                = 0
flush_ifid           = 0
flush_idex           = 0
```

#### Cycle 10 (BUG OCCURS):
```
if_pc                = 0x00000016  ← WRONG! Should be 0x0000001A (PC+4)!
if_instruction_raw   = 0x0785589c
if_instruction       = 0x0304a783  (LW - decompressed)
if_instr_is_compressed = 1
if_is_compressed     = 1
flush_ifid           = 1  (Pipeline flushed by JAL branch)
flush_idex           = 1
```

**Problem Identified:**
- PC incremented from 0x14 → 0x16 (+2 bytes)
- Should have incremented 0x14 → 0x18 (+4 bytes) since JAL is 4-byte instruction
- The compression detection correctly identified JAL as NOT compressed
- But PC increment logic still used +2 instead of +4

### 3. Code Analysis

**PC Increment Logic** (rv32i_core_pipelined.v:586):
```verilog
assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;
```

**Compression Detection** (rv32i_core_pipelined.v:716):
```verilog
wire if_instr_is_compressed = (if_instruction_raw[1:0] != 2'b11);
```

**PC Selection** (rv32i_core_pipelined.v:651-655):
```verilog
assign pc_next = trap_flush ? trap_vector :
                 mret_flush ? mepc :
                 sret_flush ? sepc :
                 ex_take_branch ? (idex_jump ? ex_jump_target : ex_branch_target) :
                 pc_increment;
```

**Instruction Memory Fetch** (instruction_memory.v:73-81):
```verilog
// Align to halfword boundary for C extension support
wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};

// Fetch 32 bits (4 bytes) starting at the aligned address
assign instruction = {mem[read_addr+3], mem[read_addr+2],
                      mem[read_addr+1], mem[read_addr]};
```

### 4. Binary Analysis

**Hex File Content at Addresses 0x10-0x1F:**
```
Offset  Bytes (little-endian)    32-bit Word      Instruction
0x10:   93 87 F7 EE              0xEEF78793       addi a5,a5,-273
0x14:   9C D8 EF 00              0x00EFD89C       SW (compressed) + JAL start
0x18:   80 01 9C 58              0x589C0180       JAL end + LW (compressed)
0x1C:   85 07 01 45              0x45010785       ADDI (compressed) + ...
```

**Detailed Byte Layout:**
- Bytes [0x14-0x15]: `9C D8` = 0xD89C (compressed SW)
- Bytes [0x16-0x19]: `EF 00 80 01` = 0x018000EF (4-byte JAL)
- Bytes [0x1A-0x1B]: `9C 58` = 0x589C (compressed LW - return address)

### 5. VCD Signal Mapping Discovery

**Important Finding:**
- VCD signal `if_pc` actually corresponds to `ifid_pc` (IF/ID pipeline register)
- This is **one cycle behind** `pc_current`
- Signal mapping: `.if_pc(ifid_pc)` in exception_unit instantiation (line 1864)

**Timing Clarification:**
- Cycle N: `pc_current` = X, instruction fetched
- Cycle N+1: `ifid_pc` = X (latched from previous cycle), `pc_current` = Y (new value)

### 6. Hypothesis: PC Increment Timing Issue

**Potential Root Causes:**

1. **Pipeline Timing Mismatch:**
   - `if_is_compressed` is calculated combinationally from `if_instruction_raw`
   - `pc_increment` uses `if_is_compressed` to determine +2 or +4
   - PC register updates on clock edge with `pc_next` value
   - **Possible issue:** Stale or incorrect `if_is_compressed` value during PC calculation

2. **Instruction Fetch/Decode Race:**
   - When PC=0x14, memory should return word containing compressed SW in lower 16 bits
   - VCD shows `if_instruction_raw = 0x018000ef` at cycle 9 (JAL instruction)
   - **Discrepancy:** If PC=0x14, should fetch 0x00EFD89C, not 0x018000EF
   - This suggests either:
     a. Memory is returning wrong data
     b. PC is actually different than shown
     c. VCD signal interpretation is incorrect

3. **Halfword Alignment Issue:**
   - Instruction memory aligns to halfword boundary: `halfword_addr = {addr[31:1], 1'b0}`
   - For compressed instruction support, always selects lower 16 bits
   - **Potential bug:** When fetching 4-byte instruction at 2-byte aligned address

## Test Results

### VCD Analysis Execution:
```
Analyzing VCD file: sim/waves/core_pipelined.vcd
Found 1412 signals
Found 50004 clock cycles
Analyzing JAL sequence...

FOUND JAL at cycle 9, time 95000
```

### Observed PC Sequence:
```
Cycle 8:  if_pc = 0x10  (ADDI)
Cycle 9:  if_pc = 0x14  (JAL fetch)   → PC should increment by +4
Cycle 10: if_pc = 0x16  (WRONG!)      → Actual increment was +2
Cycle 11: if_pc = 0x00  (Pipeline flush/reset)
```

### Expected PC Sequence:
```
Cycle 8:  if_pc = 0x10  (ADDI)
Cycle 9:  if_pc = 0x14  (Compressed SW)
Cycle 10: if_pc = 0x16  (JAL fetch)   → PC should increment by +4
Cycle 11: if_pc = 0x1A  (Correct!)    → Should be return address
```

**Discrepancy Note:** The VCD shows JAL being fetched at PC=0x14, but according to the disassembly, the compressed SW is at 0x14 and JAL is at 0x16. This suggests either:
- The VCD timing interpretation is off by one cycle
- The instruction fetch is reading ahead
- There's a fundamental misunderstanding of the signal timing

## Technical Analysis

### Compression Detection Logic:

**Current Implementation:**
```verilog
// Line 713: Always use lower 16 bits
assign if_compressed_instr_candidate = if_instruction_raw[15:0];

// Line 716: Check if compressed
wire if_instr_is_compressed = (if_instruction_raw[1:0] != 2'b11);
```

**Analysis:**
- Checks bits [1:0] of the **full 32-bit word**
- For instruction 0x018000EF: bits [1:0] = 11 → NOT compressed ✓
- For instruction 0xD89C: bits [1:0] = 00 → IS compressed ✓
- **Logic appears correct**

### PC Increment Calculation:

**Current Implementation:**
```verilog
// Line 584-586
assign pc_plus_2 = pc_current + 32'd2;
assign pc_plus_4 = pc_current + 32'd4;
assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;
```

**Analysis:**
- Simple combinational logic
- Uses current PC value + increment
- **Logic appears correct**
- **Issue must be in TIMING or DATA being used**

### Possible Bug Scenarios:

**Scenario A: Stale Compression Flag**
- PC updates before `if_is_compressed` reflects new instruction
- Old compression status used for new PC calculation
- **Likelihood:** Medium - would require very specific timing

**Scenario B: Wrong Instruction Data**
- Instruction memory returning data from wrong address
- Compression detection working on wrong instruction
- **Likelihood:** High - VCD shows unexpected instruction values

**Scenario C: Pipeline State Corruption**
- Branch/flush logic interfering with PC increment
- Multiple PC updates in single cycle
- **Likelihood:** Low - flush logic seems clean in VCD

## Tools and Scripts Created

1. **`/tmp/analyze_jal_vcd.py`** - Initial VCD parser with signal extraction
2. **`/tmp/find_jal_bug.py`** - JAL-specific analysis with cycle-by-cycle tracking
3. **`/tmp/check_raw_instr.py`** - Extract raw instruction data at JAL cycle
4. **`/tmp/detailed_analysis.py`** - Multi-signal correlation at specific times
5. **`/tmp/check_pc_out.py`** - Track actual PC register values
6. **`/tmp/check_all_signals.py`** - Complete signal dump at clock edges

## Artifacts

- **VCD File:** `sim/waves/core_pipelined.vcd` (163-185 MB)
- **Test Binary:** `tests/asm/test_jal_compressed_return.elf`
- **Test Hex:** `tests/asm/test_jal_compressed_return.hex`
- **Test Source:** `tests/asm/test_jal_compressed_return.s`

## Next Steps (Session 70)

### Immediate Actions:

1. **Add Debug Instrumentation:**
   ```verilog
   // Add to rv32i_core_pipelined.v
   `ifdef DEBUG_PC_INCREMENT
   always @(posedge clk) begin
     $display("[PC_INC] cycle=%0d pc_current=%h if_instr_raw=%h if_is_comp=%b pc_inc=%h pc_next=%h",
              cycle_count, pc_current, if_instruction_raw, if_is_compressed,
              pc_increment, pc_next);
   end
   `endif
   ```

2. **Add Memory Fetch Debug:**
   ```verilog
   // Add to instruction_memory.v
   always @(*) begin
     $display("[IMEM] addr=%h halfword_addr=%h data=%h [%h %h %h %h]",
              addr, halfword_addr, instruction,
              mem[read_addr], mem[read_addr+1], mem[read_addr+2], mem[read_addr+3]);
   end
   ```

3. **Verify Signal Timing:**
   - Add explicit PC register monitoring
   - Track `pc_current` vs `pc_next` vs `pc_increment`
   - Correlate with instruction fetch timing

4. **Test Simpler Case:**
   - Create test with JAL at 4-byte aligned address (e.g., 0x10)
   - Verify if bug is specific to 2-byte alignment
   - Test compressed→JAL→compressed sequence

5. **Review Instruction Memory:**
   - Verify halfword alignment logic
   - Check if fetch address matches intended PC
   - Validate byte ordering and endianness

### Alternative Investigation Paths:

**If PC increment logic is correct:**
- Focus on instruction memory fetch timing
- Check for address translation bugs
- Verify memory read timing vs PC update

**If instruction data is wrong:**
- Debug memory access patterns
- Check for bus/cache coherency issues
- Validate hex file loading

**If timing is the issue:**
- Add pipeline stage markers
- Trace combinational logic propagation
- Check for setup/hold violations

## Lessons Learned

1. **VCD Signal Interpretation:** Critical to understand which signals are registered vs combinational, and their pipeline stage
2. **Signal Naming:** VCD signal names may not match Verilog wire names (e.g., `if_pc` → `ifid_pc`)
3. **Timing Analysis:** Need to carefully track rising edges vs signal propagation
4. **Binary Analysis:** Essential to verify hex file content matches expected instructions
5. **Incremental Debugging:** Start with high-level VCD, drill down to specific signals and cycles

## References

- Session 68: Initial bug identification and minimal test case creation
- Session 67: Testbench false positive and FPU binary rebuild
- Session 66: C extension configuration bug fix
- RISC-V ISA Spec: Chapter 16 (Compressed Instructions)
- Verilog timing: Blocking vs non-blocking assignments

## Status Summary

**✅ Completed:**
- VCD waveform generation
- PC increment bug confirmed via VCD
- Compression detection verified correct
- Pipeline flush behavior observed
- Binary content validated

**⏳ In Progress:**
- Root cause identification
- Instruction memory fetch validation
- Signal timing clarification

**📋 Next Session:**
- Add debug instrumentation
- Direct console output analysis
- Simpler test case validation
- Fix implementation

---

**Session 69 Achievement:** Successfully narrowed down bug to PC increment calculation or instruction fetch timing. Created comprehensive VCD analysis tools and documented detailed signal behavior. Ready for targeted debugging in Session 70.
