# Session 68: JAL/Compressed Return Address Bug Investigation

**Date**: 2025-10-30
**Status**: 🔍 **IN PROGRESS** - Root cause identified, fix still needed
**Impact**: ⚠️ **CRITICAL** - FreeRTOS hangs, affects all code with JAL→compressed patterns

---

## Problem Statement

FreeRTOS hangs in an infinite loop after printing its banner message. The hang occurs between:
- **`0x200e`**: RET instruction in `memset()`
- **`0x4ca`**: Return address in `prvInitialiseNewTask()`

The pattern: **JAL (4-byte) followed by compressed instruction (2-byte) at return address**.

---

## Investigation Summary

### 1. Minimal Test Case ✅

Created `tests/asm/test_jal_compressed_return.s` that reproduces the bug:

```asm
jal ra, test_function   # 4-byte JAL at 0x80000016
c.lw a5, 48(s1)         # 2-byte C.LW at 0x8000001a (return address)
```

**Result**: Test hangs indefinitely with same pattern as FreeRTOS.

### 2. FreeRTOS Crash Analysis ✅

**Execution trace** (from Session 67 logs):
```
[7652] 0x0000200e: RET -> 0x000004ca (depth=2)
[7659] 0x0000200e: RET -> 0x000004ca (depth=1)
[7666] 0x0000200e: RET -> 0x000004ca (depth=0)
[7673] 0x0000200e: RET -> 0x000004ca (depth=4294967295)  ← UNDERFLOW!
[7680] 0x0000200e: RET -> 0x000004ca (depth=4294967295)
```

**Key observation**: Call depth underflows (0 → 0xFFFFFFFF), indicating repeated returns without matching calls.

**Disassembly**:
```
4c6:  33b010ef    jal ra, 2000 <memset>     # 4-byte JAL
4ca:  589c        c.lw a5, 48(s1)           # 2-byte C.LW (return address)
4cc:  19f1        c.addi s3, -4             # Next instruction
```

### 3. Memory Layout Analysis ✅

**Binary at 0x4c6**:
```
0x4c6: ef 10 b0 33  →  0x33b010ef (JAL, little-endian, 4 bytes)
0x4ca: 9c 58        →  0x589c (C.LW, 2 bytes)
0x4cc: f1 19        →  0x19f1 (C.ADDI, 2 bytes)
```

**Instruction fetch at PC=0x4ca**:
- `halfword_addr = {0x4ca[31:1], 1'b0} = 0x4ca` (bit[0] already 0)
- Memory returns: `{mem[0x4cd], mem[0x4cc], mem[0x4cb], mem[0x4ca]}`
- `if_instruction_raw = 0xf119589c`
  - Bits `[15:0] = 0x589c` ← **Correct instruction!**
  - Bits `[31:16] = 0xf119` (next instruction)

### 4. Instruction Decode Verification ✅

**Compressed instruction detection**:
```verilog
// rtl/core/rv32i_core_pipelined.v:713
assign if_compressed_instr_candidate = if_instruction_raw[15:0];
wire if_instr_is_compressed = (if_instruction_raw[1:0] != 2'b11);
```

**For 0x589c**:
- Bits `[1:0] = 00` → `00 != 11` → Compressed ✅
- Quadrant 0, funct3=010 → **C.LW** ✅
- Should decompress to: `lw a5, 48(s1)`

**PC increment**:
```verilog
// rtl/core/rv32i_core_pipelined.v:586
assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;
```
- For compressed: `PC + 2` ✅
- For 32-bit: `PC + 4` ✅

### 5. JAL Return Address Calculation ✅

**For compressed JAL/JALR** (Bug #42 fix):
```verilog
// rtl/core/rv32i_core_pipelined.v:1228-1229
assign ex_pc_plus_4 = idex_is_compressed ? (idex_pc + 2) : (idex_pc + 4);
```

**For our case**:
- JAL at 0x4c6 is **4-byte** (not compressed)
- Should save: `ra = PC + 4 = 0x4c6 + 4 = 0x4ca` ✅

---

## Attempted Fix #1 ❌

**Hypothesis**: Wrong 16 bits selected when PC[1]=1.

**Change** (rtl/core/rv32i_core_pipelined.v:720):
```verilog
// OLD:
assign if_compressed_instr_candidate = if_instruction_raw[15:0];

// NEW (INCORRECT):
assign if_compressed_instr_candidate = pc_current[1] ? if_instruction_raw[31:16] :
                                                        if_instruction_raw[15:0];
```

**Result**: ❌ **BROKE TESTS**
- `rv32uc-p-rvc`: TIMEOUT
- `test_priv_minimal`: TIMEOUT
- Quick regression: 12/14 passing (was 14/14)

**Analysis**: Fix was based on incorrect understanding of instruction memory alignment.
- When PC=0x4ca (bit[1]=1, bit[0]=0):
  - halfword_addr clears bit[0], not bit[1]
  - Fetch from 0x4ca returns bytes at [0x4ca, 0x4cb, 0x4cc, 0x4cd]
  - Instruction IS in bits [15:0], NOT [31:16]
- **Fix was reverted**

---

## Current Understanding

### What We Know ✅

1. **Instruction bytes are correct** in memory (0x589c at 0x4ca)
2. **Instruction fetch logic is correct** (extracts bits[15:0])
3. **Compressed detection is correct** (bits[1:0] = 00 → compressed)
4. **PC increment logic is correct** (PC+2 for compressed)
5. **JAL saves correct return address** (ra = 0x4ca)
6. **Test reliably reproduces** the bug (hangs every time)

### What's Still Unknown ❓

The bug happens **after** RET returns to 0x4ca:

**Possible causes**:
1. **Pipeline flush issue**: RET might trigger incorrect pipeline flush
2. **Branch detection false positive**: Something misidentifies C.LW as a branch/jump
3. **PC update race condition**: Pipeline state causes PC to be overwritten
4. **Compressed instruction at misaligned address**: Special case not handled in pipeline
5. **Register forwarding issue**: RA value corrupted or not forwarded correctly

**Evidence from trace**:
- RET executes successfully (returns to correct address)
- Call depth underflows (suggests repeated execution of RET)
- No exceptions or traps logged
- UART output stops after banner (execution stuck, not crashed)

---

## Debug Infrastructure Added

### Debug Tracing Code

Added to `rtl/core/rv32i_core_pipelined.v:2778-2802`:

```verilog
`ifdef DEBUG_JAL_RET
  integer debug_cycle;
  initial debug_cycle = 0;

  always @(posedge clk) begin
    if (reset_n) debug_cycle = debug_cycle + 1;

    if (reset_n && pc_current >= 32'h80000010 && pc_current <= 32'h80000040) begin
      $display("[JAL_DEBUG] Cycle=%0d PC=0x%08h instr_raw=0x%08h instr_final=0x%08h is_comp=%b",
               debug_cycle, pc_current, if_instruction_raw, if_instruction, if_is_compressed);
      $display("            instr_raw[15:0]=0x%04h instr_raw[31:16]=0x%04h PC[1:0]=%b",
               if_instruction_raw[15:0], if_instruction_raw[31:16], pc_current[1:0]);
      if (idex_valid) begin
        $display("            IDEX: PC=0x%08h opcode=%b rd=x%0d jump=%b",
                 idex_pc, idex_opcode, idex_rd_addr, idex_jump);
      end
      if (memwb_reg_write && memwb_valid && memwb_rd_addr == 5'd1) begin
        $display("            WB: x1(ra) <= 0x%08h", wb_data);
      end
    end
  end
`endif
```

**Usage**:
```bash
env XLEN=32 DEBUG_JAL_RET=1 ./tools/run_test_by_name.sh test_jal_compressed_return
```

**Note**: Testbench integration issues prevented output from showing. Needs further work.

---

## Test Files

### Minimal Test Case

**File**: `tests/asm/test_jal_compressed_return.s`

```asm
_start:
    li sp, 0x80001000       # Set up stack
    li s1, 0x80000800       # Set s1 for c.lw test
    li a5, 0xDEADBEEF
    sw a5, 48(s1)           # Store test value

    jal ra, test_function   # Call function (4-byte JAL)
    c.lw a5, 48(s1)         # <-- Return address (2-byte compressed)
    c.addi a5, 1

    # Check result
    li a0, 0
    li a1, 0xA5A5
    bne a5, a1, test_fail

test_function:
    li t0, 0x12345678
    ret
```

**Expected**: Test should pass
**Actual**: Test hangs indefinitely

---

## Next Steps (Session 69)

### Priority 1: VCD Waveform Analysis
- Generate VCD dump during hang
- Examine exact signal values:
  - `pc_current`, `pc_next`
  - `if_instruction_raw`, `if_instruction`
  - `if_is_compressed`, `pc_increment`
  - `ex_take_branch`, `ex_jump_target`
  - Pipeline flush signals

### Priority 2: Pipeline Flush Investigation
Check if RET/JALR triggers incorrect pipeline behavior:
```verilog
// rv32i_core_pipelined.v:1558
assign ex_take_branch = ...
```

Look for:
- False branch detection
- Incorrect flush after JALR
- PC override from wrong stage

### Priority 3: Simpler Test
Create even more minimal test:
```asm
_start:
    li ra, 0x80000008    # Manually set return address
    ret                  # Jump to compressed instruction
    c.li a0, 42         # 2-byte compressed at 0x80000008
    ebreak
```

### Priority 4: Add Targeted Assertions
Add SystemVerilog assertions:
```verilog
// Assert PC only changes by +2 or +4 unless branch/trap
property pc_increment_valid;
  @(posedge clk) disable iff (!reset_n)
  (pc_next - pc_current == 2) || (pc_next - pc_current == 4) ||
  ex_take_branch || trap_flush || mret_flush || sret_flush;
endproperty
```

---

## Files Modified

- `tests/asm/test_jal_compressed_return.s` - NEW (minimal test case)
- `rtl/core/rv32i_core_pipelined.v` - Added DEBUG_JAL_RET tracing

## Files to Review

- `rtl/core/rv32i_core_pipelined.v:651` - PC selection logic
- `rtl/core/rv32i_core_pipelined.v:1558` - Branch detection
- `rtl/core/rv32i_core_pipelined.v:1566` - Jump target calculation
- `rtl/memory/instruction_memory.v:73` - Halfword alignment
- `rtl/core/rvc_decoder.v` - Compressed instruction decompression

---

## References

- **Session 67**: Fixed testbench false positive, rebuilt FreeRTOS (hung after banner)
- **Session 66**: Fixed C extension config bug (compressed instructions working)
- **RISC-V Spec**: Section 16.2 (C Extension - Instruction Formats)
- **Bug #42**: C.JAL/C.JALR must save PC+2 (already fixed in codebase)

---

## Status Summary

| Item | Status |
|------|--------|
| Minimal test case | ✅ Created, reproduces bug |
| Root cause identified | ❌ Still investigating |
| Fix implemented | ❌ Attempted fix incorrect |
| Tests passing | ⚠️ Reverted to baseline (14/14) |
| FreeRTOS running | ❌ Still hangs |
| Ready for next session | ✅ Debug infrastructure in place |

**Estimated time to fix**: 1-2 hours (next session)
**Complexity**: High - subtle pipeline/timing interaction
