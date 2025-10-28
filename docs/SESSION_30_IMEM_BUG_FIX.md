# Session 30: IMEM Read Bug - Root Cause Fixed! 🎉

**Date**: 2025-10-27
**Status**: ✅ COMPLETE
**Impact**: CRITICAL - Fixes memory corruption blocking FreeRTOS execution

## Summary

Fixed critical bug where instruction memory returned zeros for addresses ≥0x210c, causing illegal instruction exceptions. Root cause was unified memory architecture allowing DMEM stores to corrupt IMEM.

## Problem Description

### Symptoms
- Instruction fetch from address 0x210c returned `0x00000000` (NOP)
- Expected instruction: `0x27068693` (ADDI a3, a3, 624)
- Memory initialized correctly but corrupted during runtime
- FreeRTOS trapped with illegal instruction exception at PC 0x210c

### Evidence Trail
1. Memory contains correct data after `$readmemh` ✓
2. Memory correct at cycle 0 (before reset) ✓
3. Memory correct at cycle 1 (after reset) ✓
4. Memory contains ZEROS at cycle 605 (fetch time) ✗
5. IMEM overwrite detector triggered at cycles 292, 367, 441, 561
6. Values written: `0x000022d2`, `0x000022e2`, `0x000022ee`, `0x00000000`
7. No IMEM writes detected through `mem_write` signal
8. BSS fast-clear writes to DMEM[0x210c] during initialization

## Root Cause

**Two-part architectural bug in unified memory implementation:**

### Part 1: DMEM Loaded from Same Hex File as IMEM

**Problem**: Both IMEM and DMEM initialized from same hex file
```verilog
// rv_soc.v (BEFORE FIX)
rv_core_pipelined #(
  .MEM_FILE(MEM_FILE)  // IMEM gets hex file
) core (...);

dmem_bus_adapter #(
  .MEM_FILE(MEM_FILE)  // DMEM ALSO gets hex file! ❌
) dmem_adapter (...);
```

**Consequence**:
- IMEM[0x210c] = 0x93 (code)
- DMEM[0x210c] = 0x93 (same data)
- BSS section in DMEM overlaps code in IMEM at same indices

### Part 2: ALL Stores Write to BOTH DMEM and IMEM

**Problem**: FENCE.I support connects stores to IMEM without address filtering
```verilog
// rv32i_core_pipelined.v (BEFORE FIX)
instruction_memory #(...) imem (
  .mem_write(exmem_mem_write && exmem_valid && !exception),  // ❌ No address check!
  .write_addr(exmem_alu_result),  // Could be DMEM address 0x8000210c
  ...
);
```

**Consequence**:
- Store to DMEM address `0x8000210c` → ALU result = `0x8000210c`
- IMEM masks address: `0x8000210c & 0xFFFF = 0x210c`
- Store writes to **both** DMEM[0x8000210c] AND IMEM[0x210c]
- Code at IMEM[0x210c] gets overwritten with data!

### The Perfect Storm

1. Linker places BSS at DMEM 0x80000000+
2. BSS variable happens to be at 0x8000210c
3. Program writes data values to BSS variable
4. Write goes to DMEM[0x8000210c] (correct)
5. Write ALSO goes to IMEM[0x210c] (BUG!)
6. Code at 0x210c gets corrupted
7. Instruction fetch returns corrupted data
8. Illegal instruction exception

## Solution

### Fix #1: Don't Load DMEM from Hex File

**File**: `rtl/rv_soc.v` line 260

```verilog
// BEFORE
dmem_bus_adapter #(
  .XLEN(XLEN),
  .FLEN(`FLEN),
  .MEM_SIZE(DMEM_SIZE),
  .MEM_FILE(MEM_FILE)  // ❌ Wrong!
) dmem_adapter (...);

// AFTER
dmem_bus_adapter #(
  .XLEN(XLEN),
  .FLEN(`FLEN),
  .MEM_SIZE(DMEM_SIZE),
  .MEM_FILE("")  // ✅ DMEM should NOT be loaded from hex file
) dmem_adapter (...);
```

**Rationale**:
- Harvard architecture has separate I/D memory
- Only IMEM should be initialized from program binary
- DMEM starts zero-initialized
- `.data` section is copied by startup code (startup.S)

### Fix #2: Filter IMEM Writes by Address

**File**: `rtl/core/rv32i_core_pipelined.v` lines 672-690

```verilog
// BEFORE
instruction_memory #(...) imem (
  .clk(clk),
  .addr(pc_current),
  .instruction(if_instruction_raw),
  .mem_write(exmem_mem_write && exmem_valid && !exception),  // ❌ No filtering!
  .write_addr(exmem_alu_result),
  ...
);

// AFTER
// IMEM write enable - only for addresses in IMEM range (0x0-0xFFFF for 64KB IMEM)
// This prevents DMEM stores (e.g., 0x80000000) from corrupting IMEM
wire imem_write_enable = exmem_mem_write && exmem_valid && !exception &&
                         (exmem_alu_result < IMEM_SIZE);  // ✅ Address check!

instruction_memory #(...) imem (
  .clk(clk),
  .addr(pc_current),
  .instruction(if_instruction_raw),
  .mem_write(imem_write_enable),  // ✅ Filtered!
  .write_addr(exmem_alu_result),
  ...
);
```

**Rationale**:
- FENCE.I support requires IMEM to be writable
- Only stores to IMEM address range (0x0-0xFFFF) should write to IMEM
- Stores to DMEM range (0x80000000+) should NOT write to IMEM
- Simple comparison: `exmem_alu_result < IMEM_SIZE`

## Verification

### Test Results

**Before Fix**:
```
[IMEM-OVERWRITE-DETECTOR] Cycle 292: mem[0x210c] = 0xd2  ❌
[IMEM-OVERWRITE-DETECTOR] Cycle 367: mem[0x210c] = 0xe2  ❌
[IMEM-OVERWRITE-DETECTOR] Cycle 441: mem[0x210c] = 0xee  ❌
[IMEM-OVERWRITE-DETECTOR] Cycle 561: mem[0x210c] = 0x00  ❌
[IMEM-FETCH] addr=0x210c, instr=0x00000000  ❌ WRONG!
```

**After Fix**:
```
[IMEM-OVERWRITE-DETECTOR] Only at TIME=0 (initialization)  ✅
[IMEM-FETCH] addr=0x210c, instr=0x27068693  ✅ CORRECT!
  mem[0x210c]=0x93, mem[0x210d]=0x86, mem[0x210e]=0x06, mem[0x210f]=0x27
```

### Regression Testing
- ✅ Quick regression: 14/14 tests passing
- ✅ FreeRTOS boots past address 0x210c
- ✅ No performance impact (single comparison added)
- ✅ FENCE.I still functional for valid self-modifying code

### What Works Now
1. ✅ IMEM remains unchanged during execution
2. ✅ DMEM stores don't corrupt IMEM
3. ✅ FreeRTOS executes past problematic address
4. ✅ Instruction at 0x210c reads correctly
5. ✅ BSS section properly isolated in DMEM

## Investigation Timeline

1. **Initial observation**: IMEM returns zeros at runtime
2. **Hypothesis 1**: Array indexing width mismatch → Tested with explicit truncation → Not the issue
3. **Hypothesis 2**: Hex file corruption → Checked file contents → Correct data
4. **Hypothesis 3**: $readmemh bug → Tested without @ directives → Not the issue
5. **Hypothesis 4**: NOP initialization loop overwrites → Disabled loop → Not the issue
6. **Breakthrough**: Added overwrite detector → Found runtime corruption at cycles 292, 367, 441, 561!
7. **Key insight**: Values written (0x22d2, 0x22e2, 0x22ee) are code addresses → Data being written to IMEM!
8. **Discovery**: ALL stores write to IMEM (FENCE.I support)
9. **Root cause**: No address filtering on IMEM writes + unified memory initialization

## Impact

**Severity**: CRITICAL
**Scope**: Affects any program that:
- Uses data memory (virtually all programs)
- Has DMEM addresses with same low 16 bits as code addresses
- Relies on code integrity during execution

**Without this fix**:
- FreeRTOS cannot boot
- Most complex programs will fail
- Memory corruption is silent and hard to debug
- FENCE.I support inadvertently breaks Harvard architecture

## Lessons Learned

1. **Unified memory requires careful address filtering** - Can't blindly write to both I/D memory
2. **Test with diverse address patterns** - Bug only manifested when DMEM writes hit specific indices
3. **Monitor at multiple abstraction levels** - RTL monitors missed testbench-level issues
4. **Architecture assumptions matter** - Linker assumed Harvard, implementation was unified
5. **FENCE.I needs address checks** - Self-modifying code support must respect memory regions

## Related Files

### Modified (2 files)
- `rtl/rv_soc.v` - Removed MEM_FILE from DMEM initialization
- `rtl/core/rv32i_core_pipelined.v` - Added IMEM write address filtering

### Debug/Test (not committed)
- `rtl/memory/instruction_memory.v` - Temporary debug monitors
- `tb/integration/tb_freertos.v` - Temporary overwrite detectors

## Future Improvements

1. **Add assertions** - Check IMEM writes are only to valid ranges
2. **Document architecture** - Clarify Harvard vs unified memory assumptions
3. **Test coverage** - Add test for cross-memory-region isolation
4. **Linker validation** - Ensure sections don't overlap in index space

## References

- Session 29: IMEM Bug Investigation (initial diagnosis)
- RISC-V Privileged Spec: FENCE.I instruction (Vol II, Section 3.1)
- FreeRTOS Port: Linker script memory layout
- PHASES.md: Phase 2 OS integration roadmap

---

**Status**: ✅ FIXED - FreeRTOS can now boot past 0x210c!
**Next**: Continue FreeRTOS integration and debugging
