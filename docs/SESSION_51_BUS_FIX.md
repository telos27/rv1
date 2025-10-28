# Session 51: CLINT 64-bit Read Bug - FIXED! ✅

**Date**: 2025-10-28
**Status**: ✅ **Bug Fixed** - Bus extraction now works correctly
**Impact**: Critical bus infrastructure bug fixed, but FreeRTOS issue remains

---

## Executive Summary

**Achievement**: Fixed critical bug in `simple_bus.v` where 32-bit reads from 64-bit CLINT registers were returning the full 64-bit value instead of extracting the appropriate 32-bit portion based on address offset.

**Status**:
- ✅ Bus extraction bug FIXED
- ✅ All regression tests passing (14/14)
- ❌ FreeRTOS MTIMECMP writes still not reaching bus (separate issue)

---

## Problem Statement

When accessing 64-bit CLINT registers (like MTIMECMP) with two consecutive 32-bit loads at offsets +0 and +4, the bus was returning the full 64-bit register value for both accesses instead of extracting:
- Bits [31:0] for reads at offset +0
- Bits [63:32] for reads at offset +4

This caused incorrect data to be read by the CPU when accessing 64-bit peripheral registers on RV32.

---

## Root Cause Analysis

### Architecture Background

**CLINT Module**:
- Stores 64-bit registers (MTIME, MTIMECMP, etc.)
- Always returns full 64-bit values on read
- Expects bus adapter to extract appropriate portion

**Data Memory (DMEM)**:
- Stores data as byte array
- Extracts correct bytes based on full address including offset
- Example: Reading word at address 0x80000004 returns bytes [7:4], not [3:0]

**The Bug**:
`simple_bus.v` was directly passing through CLINT's 64-bit output:
```verilog
// OLD CODE (BROKEN):
end else if (sel_clint) begin
  master_req_ready = clint_req_ready;
  master_req_rdata = clint_req_rdata;  // ❌ Always returns full 64 bits!
end
```

This meant that when CPU accessed MTIMECMP with:
```assembly
lw  t0, 0(a0)    # Read MTIMECMP[31:0]  at 0x02004000
lw  t1, 4(a0)    # Read MTIMECMP[63:32] at 0x02004004
```

Both loads would receive the SAME 64-bit value, and the CPU would extract the low 32 bits from both (since `mem_read_data = arb_mem_read_data[XLEN-1:0]`).

### Discovery Process

1. **Created minimal test**: `test_clint_mtimecmp_write.s` to reproduce issue
2. **Added bus debug tracing**: Showed bus was computing correct value
3. **Traced data path**: Found CPU only uses `[XLEN-1:0]` of bus data
4. **Identified mismatch**: Bus must extract correct portion BEFORE returning to CPU

---

## The Fix

**File**: `rtl/interconnect/simple_bus.v`

Added address-based extraction logic for CLINT reads:

```verilog
end else if (sel_clint) begin
  master_req_ready = clint_req_ready;
  // CLINT returns full 64-bit values, but we need to extract the appropriate
  // portion based on access size and address alignment
  case (master_req_size)
    3'h3: master_req_rdata = clint_req_rdata;  // 64-bit: full value

    3'h2: begin  // 32-bit: extract based on address[2]
      if (master_req_addr[2])
        master_req_rdata = {32'h0, clint_req_rdata[63:32]};  // High word (+4)
      else
        master_req_rdata = {32'h0, clint_req_rdata[31:0]};   // Low word (+0)
    end

    3'h1: begin  // 16-bit: extract based on address[2:1]
      case (master_req_addr[2:1])
        2'h0: master_req_rdata = {48'h0, clint_req_rdata[15:0]};
        2'h1: master_req_rdata = {48'h0, clint_req_rdata[31:16]};
        2'h2: master_req_rdata = {48'h0, clint_req_rdata[47:32]};
        2'h3: master_req_rdata = {48'h0, clint_req_rdata[63:48]};
      endcase
    end

    3'h0: begin  // 8-bit: extract based on address[2:0]
      case (master_req_addr[2:0])
        3'h0: master_req_rdata = {56'h0, clint_req_rdata[7:0]};
        3'h1: master_req_rdata = {56'h0, clint_req_rdata[15:8]};
        3'h2: master_req_rdata = {56'h0, clint_req_rdata[23:16]};
        3'h3: master_req_rdata = {56'h0, clint_req_rdata[31:24]};
        3'h4: master_req_rdata = {56'h0, clint_req_rdata[39:32]};
        3'h5: master_req_rdata = {56'h0, clint_req_rdata[47:40]};
        3'h6: master_req_rdata = {56'h0, clint_req_rdata[55:48]};
        3'h7: master_req_rdata = {56'h0, clint_req_rdata[63:56]};
      endcase
    end

    default: master_req_rdata = clint_req_rdata;
  endcase
end
```

**Key Points**:
- Uses `master_req_addr[2]` to distinguish offset +0 vs +4 for 32-bit accesses
- Uses `master_req_addr[2:1]` for 16-bit accesses
- Uses `master_req_addr[2:0]` for 8-bit accesses
- Extracts appropriate bits and zero-extends to 64 bits

---

## Verification

### Debug Infrastructure Added

**File**: `tools/test_soc.sh`
- Added DEBUG_BUS flag support (lines 51-53)

**Debug Output** (shows correct extraction):
```
[BUS] CLINT read @ +0: addr=0x02004000 addr[2]=0 clint_data=0xabcdef0012345678
      -> master_rdata=0x0000000012345678  ✅

[BUS] CLINT read @ +4: addr=0x02004004 addr[2]=1 clint_data=0xabcdef0012345678
      -> master_rdata=0x00000000abcdef00  ✅
```

### Regression Tests

```bash
env XLEN=32 make test-quick
```

**Result**: ✅ 14/14 tests passing
- All I/M/A/F/D/C extension tests pass
- Privilege tests pass
- Custom tests pass

### Test Programs Created

1. **test_clint_mtimecmp_write.s**: Mimics FreeRTOS MTIMECMP write pattern
   - Reads MTIME
   - Adds tick increment
   - Writes to MTIMECMP (two 32-bit stores)
   - Reads back and verifies

2. **test_clint_read_simple.s**: Simplified CLINT read test
   - Writes known values (0x12345678, 0xABCDEF00)
   - Reads back with two 32-bit loads
   - Verifies each half separately

---

## FreeRTOS Status

**Important**: The bus fix was necessary but NOT sufficient to solve the FreeRTOS timer issue.

### Current Blocker

FreeRTOS `vPortSetupTimerInterrupt()` function still doesn't generate bus transactions to CLINT:

```bash
env XLEN=32 DEBUG_BUS=1 DEBUG_CLINT=1 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep "0x0200"
# Result: NO CLINT ACCESSES (zero output)
```

**Evidence**:
- Store instructions exist in binary at PC 0x1b10 and 0x1b1e
- Function is called (execution reaches vPortSetupTimerInterrupt)
- UART output shows FreeRTOS banner printing
- But NO bus_req_valid for CLINT address range

**This indicates**:
- Stores aren't reaching MEM stage
- OR stores are being squashed/flushed
- OR some pipeline hazard preventing execution

---

## Files Modified

### Core Changes

1. **rtl/interconnect/simple_bus.v** (~40 lines added)
   - Added CLINT read data extraction logic
   - Supports 64/32/16/8-bit accesses
   - Address-based byte extraction

2. **tools/test_soc.sh** (3 lines added)
   - Added DEBUG_BUS flag support

### Test Programs Created

3. **tests/asm/test_clint_mtimecmp_write.s** (NEW)
   - Mimics FreeRTOS MTIMECMP write pattern
   - Reads MTIME, adds increment, writes MTIMECMP

4. **tests/asm/test_clint_read_simple.s** (NEW)
   - Simple test for 64-bit register access
   - Writes known values, reads back in two halves

---

## Technical Details

### Why DMEM Doesn't Have This Issue

DMEM stores data as **byte array**, so address bits naturally select correct bytes:
```verilog
assign word_data = {mem[masked_addr + 3], mem[masked_addr + 2],
                    mem[masked_addr + 1], mem[masked_addr]};
```

When reading at address 0x80000004, `masked_addr` includes the +4 offset, so it reads bytes [7:4].

### Why CLINT Needs Bus Extraction

CLINT stores data as **register array** (64-bit words):
```verilog
reg [63:0] mtimecmp [0:NUM_HARTS-1];
```

Always returns full 64-bit register regardless of address offset. Bus must extract correct portion.

### Address Bit Decoding

For 32-bit access:
- Address 0x02004000: bit [2] = 0 → extract bits [31:0]
- Address 0x02004004: bit [2] = 1 → extract bits [63:32]

This works because:
- Byte 0 is at bit position 0
- Byte 4 is at bit position 1 of address[2:2]
- 32-bit access aligns to 4-byte boundaries

---

## Lessons Learned

1. **Peripheral Interfaces Vary**: Different peripherals use different data organization
   - Byte-addressable (DMEM, UART): Address directly selects bytes
   - Register-based (CLINT, CSRs): Bus must extract portions

2. **Bus Responsibility**: The bus interconnect must handle data width conversions between:
   - Master (CPU) expectations
   - Slave (peripheral) implementations

3. **Debug Strategy**:
   - Create minimal reproduction test
   - Add tracing at multiple levels (bus, core, peripheral)
   - Verify assumptions about data flow

4. **Combinational Logic OK**: Using `always @(*)` with `reg` outputs is valid Verilog
   - Synthesizes to combinational logic
   - Just means "procedural assignment to registered variable"

---

## Next Steps (Session 52)

### Primary Goal: Debug FreeRTOS MTIMECMP Store Issue

1. **Add PC-specific tracing**:
   - Instrument stores at PC 0x1b10 and 0x1b1e
   - Check if they reach ID, EX, MEM stages
   - Verify no flushes/stalls during execution

2. **Check write pulse logic**:
   - Verify `mem_stage_new_instr` detection
   - Check `bus_req_issued` flag behavior
   - Confirm `arb_mem_write_pulse` generation

3. **Test with minimal assembly**:
   - Create assembly program matching FreeRTOS pattern exactly
   - Same address calculation sequence
   - Same register usage
   - Compare behavior

4. **Investigate alternatives**:
   - Check MMU/address translation
   - Verify no CSR hazards blocking stores
   - Look for exception/interrupt during timer setup

---

## Status Summary

- ✅ **Bus extraction bug FIXED**: 64-bit register reads now work correctly
- ✅ **Regression tests pass**: No functionality broken (14/14)
- ✅ **Debug infrastructure**: Added bus tracing capability
- ❌ **FreeRTOS blocked**: Stores still not reaching bus (separate root cause)

**Impact**: High - Fixed critical infrastructure bug that would affect any 64-bit peripheral access on RV32
**Priority**: Continue investigation into FreeRTOS store issue (Session 52)

---

## References

- Session 49: Initial FreeRTOS investigation
- Session 50: Bus tracing infrastructure
- `docs/MEMORY_MAP.md`: CLINT address layout
- `rtl/peripherals/clint.v`: CLINT register implementation
- `rtl/memory/data_memory.v`: DMEM byte-addressable implementation
