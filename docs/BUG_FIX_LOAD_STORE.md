# Bug Fix: Load/Store Test Returning X Values

**Date**: 2025-10-09
**Issue**: Load/store integration test returned X (unknown) values in registers
**Severity**: High (blocked memory operation verification)
**Status**: ✅ RESOLVED

---

## Problem Description

The `load_store.s` integration test was executing without errors but producing X (unknown) values in result registers:

```
x10 (a0)   = 0xxxxxxxxx (decimal: x)  ← Expected: 42
x11 (a1)   = 0xxxxxxxxx (decimal: x)  ← Expected: 100
x12 (a2)   = 0xxxxxxxxx (decimal: x)  ← Expected: -1
```

## Initial Hypothesis

The test documentation suggested a timing issue in `data_memory.v`:
- Synchronous writes (posedge clk)
- Combinational reads (always @(*))
- Potential race condition in simulation

## Root Cause Analysis

**The actual issue was NOT a timing problem** - it was an **address range violation**.

### Investigation Steps

1. **Analyzed data_memory.v**:
   - Memory size: `MEM_SIZE = 4096` bytes
   - Valid address range: 0x000 to 0xFFF (0 to 4095)

2. **Examined load_store.s**:
   ```assembly
   lui x5, 0x1          # x5 = 0x1000 (4096 decimal)
   sw x6, 0(x5)         # Store to 0x1000 - OUT OF BOUNDS!
   lw x10, 0(x5)        # Load from 0x1000 - OUT OF BOUNDS!
   ```

3. **Identified the problem**:
   - Address 0x1000 (4096) is beyond the valid range (0-4095)
   - Accessing `mem[4096]` when array is `mem[0:4095]` returns X in Verilog

### Why This Wasn't Caught Earlier

- In a real RISC-V system with unified address space, data memory typically starts at a higher address (e.g., 0x80000000)
- The test writer assumed separate address spaces for instruction and data memory
- However, in this Harvard architecture, both memories start at address 0x0 with separate 4KB ranges

## Solution

Changed the test program to use valid addresses within the data memory range.

### Before (Broken):
```assembly
lui x5, 0x1          # x5 = 0x1000 (out of bounds)
sw x6, 0(x5)         # Store to 0x1000
lw x10, 0(x5)        # Load from 0x1000
```

### After (Fixed):
```assembly
addi x5, x0, 0x400   # x5 = 0x400 (1024 - middle of range)
sw x6, 0(x5)         # Store to 0x400
lw x10, 0(x5)        # Load from 0x400
```

**Why 0x400?**
- Well within the valid range (0x000-0xFFF)
- Fits in ADDI 12-bit signed immediate (-2048 to +2047)
- Middle of the data memory range (avoids low addresses near stack/globals)

## Test Results After Fix

```
x10 (a0)   = 0x0000002a (decimal: 42)       ✅
x11 (a1)   = 0x00000064 (decimal: 100)      ✅
x12 (a2)   = 0xffffffff (decimal: -1)       ✅
```

All three memory operations now work correctly:
- **Word load/store** (LW/SW): 32-bit value
- **Halfword load/store** (LH/SH): 16-bit value with sign extension
- **Byte load/store** (LB/SB): 8-bit value with sign extension (0xFF → 0xFFFFFFFF)

## Files Modified

1. **tests/asm/load_store.s**:
   - Changed base address from 0x1000 to 0x400
   - Updated comments to reflect new addresses
   - Updated expected results documentation

2. **PHASES.md**:
   - Updated completion status (95% → 98%)
   - Changed integration test status (2/3 → 3/3)
   - Marked Stage 1.7 as COMPLETED
   - Updated bug count (6 → 7 fixed)

## Lessons Learned

1. **Address bounds checking**: Consider adding assertions or warnings for out-of-bounds memory access
2. **Test validation**: Assembly tests should verify address ranges against memory size
3. **Documentation clarity**: Memory maps should be explicitly documented (see recommendation below)

## Recommendations

### 1. Add Memory Map Documentation

Create a memory map document specifying:
```
Instruction Memory: 0x00000000 - 0x00000FFF (4KB)
Data Memory:        0x00000000 - 0x00000FFF (4KB, separate space)
```

### 2. Add Bounds Checking (Optional for Debug)

Consider adding simulation-only warnings in `data_memory.v`:
```verilog
always @(*) begin
  if (mem_read || mem_write) begin
    if (addr >= MEM_SIZE) begin
      $display("WARNING: Out-of-bounds memory access at 0x%08h", addr);
    end
  end
end
```

### 3. Linker Script

For future test programs, create a linker script that places data in valid ranges:
```
MEMORY {
  imem : ORIGIN = 0x00000000, LENGTH = 4K
  dmem : ORIGIN = 0x00000000, LENGTH = 4K
}
```

## Impact

- ✅ All integration tests now pass (3/3 = 100%)
- ✅ All unit tests still pass (126/126 = 100%)
- ✅ Total test pass rate: 129/129 (100%)
- ✅ Phase 1 completion: 98% (ready for compliance testing)

## Related Issues

- Original bug report: TEST_RESULTS.md, section "Integration Test Results #3"
- Tracking: PHASES.md, Stage 1.7

---

**Resolution**: Simple test program fix, no hardware changes required.
**Time to fix**: < 1 hour (including analysis and documentation)
**Prevention**: Better address validation in test programs
