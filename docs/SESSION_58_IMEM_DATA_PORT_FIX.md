# Session 58: IMEM Data Port Fix - Strings Loading Successfully!

**Date**: 2025-10-29
**Status**: ✅ **Major fix applied** - FreeRTOS strings now load correctly
**Achievement**: Fixed instruction memory byte-level access for .rodata copying

---

## Summary

Fixed critical bug in IMEM data port that prevented FreeRTOS startup code from copying `.rodata` strings from IMEM to DMEM. The issue was caused by C extension halfword alignment logic being applied to data reads, breaking byte-level access needed for string copying.

---

## Problem Description

### Symptom
FreeRTOS startup banner wasn't printing correctly. Debug traces showed:
```
[RODATA-COPY] Cycle 41: rodata_copy_loop FIRST ITERATION
[RODATA-COPY]   CORE IMEM[0x42b8] = 0x00000013 (should be '[Task' = 0x5B 54 61 73)
[RODATA-COPY]   DATA PORT IMEM[0x42b8] = 0x00000013
```

Strings were reading as `0x00000013` (NOP instruction) instead of actual string data.

### Impact
- FreeRTOS couldn't print startup banner
- String constants unavailable to application code
- .rodata section copy from IMEM to DMEM failed

---

## Root Cause Analysis

### The Bug
In `rtl/memory/instruction_memory.v` (lines 65-74):

```verilog
// BEFORE FIX:
wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);
wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};  // Align to halfword boundary

assign instruction = {mem[halfword_addr+3], mem[halfword_addr+2],
                      mem[halfword_addr+1], mem[halfword_addr]};
```

**Problem**: ALL reads (both instruction fetch and data port) were aligned to halfword boundaries.

### Why This Broke Data Reads

**Scenario**: FreeRTOS wants to read byte at address `0x101`
1. `instruction_memory` receives addr=`0x101`
2. Halfword alignment: `halfword_addr = 0x100` (bit 0 cleared)
3. Returns: `{mem[0x103], mem[0x102], mem[0x101], mem[0x100]}`
4. Bus adapter tries to extract byte 1, but it extracts from this wrong 4-byte word!

**Expected**: Should return `{mem[0x103], mem[0x102], mem[0x101], mem[0x100]}` but at word-aligned address `0x100`, then extract correct byte based on lower 2 bits of address.

### Why Halfword Alignment Exists

The halfword alignment was added to support the C extension (compressed 16-bit instructions). Instruction fetches can occur at any halfword boundary (e.g., 0x100, 0x102, 0x104), not just word boundaries. The alignment logic allows fetching 32 bits starting from any 2-byte aligned address.

**This is correct for instruction fetches but wrong for data reads!**

---

## Solution

### Design Decision

Add a `DATA_PORT` parameter to distinguish between instruction fetch and data read use cases:
- **Instruction port** (DATA_PORT=0): Halfword-aligned (C extension support)
- **Data port** (DATA_PORT=1): Word-aligned (proper byte extraction by bus adapter)

### Implementation

#### 1. Added DATA_PORT Parameter
**File**: `rtl/memory/instruction_memory.v:15`

```verilog
module instruction_memory #(
  parameter XLEN     = `XLEN,
  parameter MEM_SIZE = 65536,
  parameter MEM_FILE = "",
  parameter DATA_PORT = 0         // NEW: 1 = data port, 0 = instruction port
) (
  // ...
);
```

#### 2. Conditional Address Alignment
**File**: `rtl/memory/instruction_memory.v:71-81`

```verilog
wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);

// For instruction port: align to halfword boundary (C extension support)
// For data port: use word-aligned address (byte extraction done externally)
wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};  // Align to halfword
wire [XLEN-1:0] word_addr = {masked_addr[XLEN-1:2], 2'b00};     // Align to word
wire [XLEN-1:0] read_addr = DATA_PORT ? word_addr : halfword_addr;

assign instruction = {mem[read_addr+3], mem[read_addr+2],
                      mem[read_addr+1], mem[read_addr]};
```

#### 3. Updated SoC Instantiation
**File**: `rtl/rv_soc.v:277`

```verilog
instruction_memory #(
  .XLEN(XLEN),
  .MEM_SIZE(IMEM_SIZE),
  .MEM_FILE(MEM_FILE),
  .DATA_PORT(1)              // NEW: Enable byte-level access for .rodata copying
) imem_data_port (
  // ...
);
```

#### 4. Enhanced Debug Output
**File**: `rtl/memory/instruction_memory.v:87-92`

```verilog
if (DATA_PORT)
  $display("[IMEM-DATA] addr=0x%08h, word_addr=0x%08h, data=0x%08h",
           addr, word_addr, instruction);
else
  $display("[IMEM-FETCH] addr=0x%08h, hw_addr=0x%08h, instr=0x%08h",
           addr, halfword_addr, instruction);
```

---

## Test Results

### Before Fix
```
[RODATA-COPY] CORE IMEM[0x42b8] = 0x00000013 (should be '[Task' = 0x5B 54 61 73)
```
Strings read as NOPs, FreeRTOS couldn't print banner.

### After Fix
```
[IMEM-DATA] addr=0x00002108, word_addr=0x00002108, data=0x43444641
[IMEM-DATA] addr=0x0000210c, word_addr=0x0000210c, data=0x726f4320
[IMEM-DATA] addr=0x00002110, word_addr=0x00002110, data=0x00000065
```

**UART Output**:
```
========================================
  FreeRTOS Blinky Demo
  Target: RV1 RV32IMAFDC Core
  FreeRTOS Kernel: v11.1.0
  CPU Clock: 50000000 Hz
  Tick Rate: 1000 Hz
========================================

Tasks created s
```

✅ **Success!** Strings load correctly, startup banner prints!

### Regression Tests
```bash
env XLEN=32 make test-quick
# Result: 14/14 tests PASSED
```

All existing tests continue to pass - instruction fetch unchanged.

---

## Impact Assessment

### What Changed
1. **Instruction fetch behavior**: UNCHANGED (still halfword-aligned)
2. **Data port reads**: NOW CORRECT (word-aligned with byte extraction)
3. **Regression tests**: All pass (14/14)
4. **FreeRTOS strings**: Load correctly from IMEM

### What's Fixed
- ✅ .rodata section copying from IMEM to DMEM
- ✅ String constants accessible to application code
- ✅ FreeRTOS startup banner prints correctly
- ✅ UART output shows proper text messages

### Remaining Issues
The fix resolved the IMEM data port issue, but FreeRTOS still has other problems:
1. **Queue assertion** (cycle 30,355): queueLength contains pointer value (0x800004b8) instead of length
2. **Illegal instruction** (cycle 39,415): mtval=0x13 (similar to FPU decode bug)

These issues are unrelated to IMEM data port and need separate investigation.

---

## Design Notes

### Why Two Separate Memory Instances?

**RV1 uses Harvard architecture** (separate instruction and data memory):
- **Instruction port**: Core fetches instructions (read-only)
- **Data port**: Bus adapter for .rodata copy (read-only, for startup only)

Both ports read from the same underlying memory array (loaded from `.hex` file), but:
- Instruction port needs halfword alignment (C extension)
- Data port needs word alignment (byte extraction)

### Alternative Solutions Considered

1. **Fix bus adapter byte extraction**: Would need to handle halfword-aligned words - complex and error-prone
2. **Remove halfword alignment entirely**: Would break C extension support
3. **Parameterize alignment** (chosen): Clean, minimal impact, preserves both features

---

## Lessons Learned

### Design Principle: Single Responsibility
The `instruction_memory` module now has two modes:
- **Instruction fetch**: Optimized for C extension (halfword-aligned)
- **Data read**: Optimized for bus adapter (word-aligned)

The `DATA_PORT` parameter makes this distinction explicit in the HDL.

### Testing Insight
The bug wasn't caught by regression tests because:
1. Instruction tests don't read from IMEM data port
2. FreeRTOS was the first real test of .rodata copying from IMEM
3. Need more comprehensive data path testing

### Debugging Technique
Key insight came from reading the `instruction_memory` source and seeing the halfword alignment logic. Checking when this was added (for C extension) immediately revealed the conflict with data port requirements.

---

## Files Modified

| File | Lines | Changes |
|------|-------|---------|
| `rtl/memory/instruction_memory.v` | 15, 71-81, 87-92 | Add DATA_PORT parameter, conditional alignment, debug output |
| `rtl/rv_soc.v` | 277 | Set DATA_PORT=1 for data port instance |

**Commit**: `7af994a` - "Session 58: Fix IMEM data port byte-level access for .rodata copy"

---

## Next Steps

1. **Debug queue assertion** (cycle 30,355)
   - Investigate why queueLength contains pointer value
   - Check queue structure initialization
   - Verify memory layout and alignment

2. **Debug illegal instruction** (cycle 39,415)
   - Similar symptom to FPU decode bug (mtval=0x13)
   - May indicate systemic instruction decode/pipeline issue
   - Needs careful pipeline state analysis

3. **Continue FreeRTOS testing**
   - Now that strings work, test should progress further
   - Goal: Task switching, timer interrupts

---

**Status**: ✅ **IMEM data port fixed - FreeRTOS strings loading correctly!**
**Next Session**: Debug queue assertion and illegal instruction issues
