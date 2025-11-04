# Session 79: RV64I Load/Store Instructions - Testbench Bus Interface Fix

**Date:** 2025-11-03
**Focus:** RV64I load/store instruction validation and testbench debugging
**Result:** ✅ **SUCCESS** - All RV64I load/store instructions (LD, LWU, SD) working!

## Overview

Started Phase 3 RV64 testing by attempting to validate RV64I-specific load/store instructions. Discovered that while the instructions were already implemented in hardware, the RV64 testbench was missing critical bus interface connections, causing all loads to return undefined data.

## Problem Discovery

### Initial Symptoms
- LD (Load Doubleword) loaded 0 instead of stored values
- LW (Load Word) also failed similarly
- SD (Store Doubleword) appeared to work
- Instructions after loads didn't execute properly

### Investigation Process

1. **Verified instruction encoding** - LD/LWU/SD correctly encoded by assembler
2. **Checked data memory module** - Already had funct3=011 (LD) and funct3=110 (LWU) support
3. **Tested SD separately** - Confirmed stores were working
4. **Tested LD separately** - Confirmed loads were returning 0
5. **Compared RV32 vs RV64 testbenches** - Found missing bus interface!

### Root Cause Identified

The RV64 testbench (`tb/integration/tb_core_pipelined_rv64.v`) was missing:
1. Bus interface signal declarations
2. Bus interface port connections to the core
3. `dmem_bus_adapter` module instantiation

**Why loads returned 0:**
- Core's `bus_req_ready` input was unconnected (undefined 'x')
- Core's `bus_req_rdata` input was unconnected (undefined 'x')
- When undefined signals propagate, they can resolve to 0 in simulation
- Loads read from `bus_req_rdata`, getting 0 or undefined values

## Solution Implemented

### File: `tb/integration/tb_core_pipelined_rv64.v`

**Added bus interface signals:**
```verilog
// Bus interface signals (for core with bus master port)
wire        bus_req_valid;
wire [63:0] bus_req_addr;
wire [63:0] bus_req_wdata;
wire        bus_req_we;
wire [2:0]  bus_req_size;
wire        bus_req_ready;
wire [63:0] bus_req_rdata;
```

**Connected bus interface to core:**
```verilog
rv_core_pipelined #(
  .XLEN(64),
  .RESET_VECTOR(RESET_VEC),
  .IMEM_SIZE(16384),
  .DMEM_SIZE(16384),
  .MEM_FILE(MEM_INIT_FILE)
) DUT (
  .clk(clk),
  .reset_n(reset_n),
  .mtip_in(1'b0),
  .msip_in(1'b0),
  .meip_in(1'b0),      // Added
  .seip_in(1'b0),      // Added
  .bus_req_valid(bus_req_valid),    // Added
  .bus_req_addr(bus_req_addr),      // Added
  .bus_req_wdata(bus_req_wdata),    // Added
  .bus_req_we(bus_req_we),          // Added
  .bus_req_size(bus_req_size),      // Added
  .bus_req_ready(bus_req_ready),    // Added
  .bus_req_rdata(bus_req_rdata),    // Added
  .pc_out(pc),
  .instr_out(instruction)
);
```

**Instantiated data memory bus adapter:**
```verilog
// Data memory bus adapter (handles byte-level access for data memory)
dmem_bus_adapter #(
  .XLEN(64),
  .DMEM_SIZE(16384)  // 16KB data memory
) dmem_adapter (
  .clk(clk),
  .reset_n(reset_n),
  .req_valid(bus_req_valid),
  .req_addr(bus_req_addr),
  .req_wdata(bus_req_wdata),
  .req_we(bus_req_we),
  .req_size(bus_req_size),
  .req_ready(bus_req_ready),
  .req_rdata(bus_req_rdata)
);
```

## Test Results

### Individual Instruction Tests

#### 1. LD (Load Doubleword) - `test_rv64i_ld_only.s`
```
Test: SW word, then LD doubleword
Result: ✅ PASS
- a0 = 0x0000000000000077 (correct)
- a2 = 0x0000000000000077 (LD result)
Cycles: 14
```

#### 2. SD (Store Doubleword) - `test_rv64i_sd_only.s`
```
Test: SD doubleword
Result: ✅ PASS
- a0 = 0x0000000000000001 (success indicator)
- a1 = 0x0000000000000099 (value stored)
Cycles: 9
```

#### 3. SD + LD Together - `test_rv64i_sd_ld_minimal.s`
```
Test: SD then LD same address
Result: ✅ PASS
- a0 = 0x0000000000000042 (correct)
- a1 = 0x0000000000000042 (stored value)
- a2 = 0x0000000000000042 (loaded value)
Cycles: 14
```

#### 4. LWU (Load Word Unsigned) - `test_rv64i_lwu.s`
```
Test: LWU zero-extension vs LW sign-extension
Result: ✅ PASS
- a0 = 0x0000000000000001 (success)
- a2 = 0x00000000fedcba98 (LWU: zero-extended) ✅
- a3 = 0xfffffffffedcba98 (LW: sign-extended) ✅
- a4 = 0x0000000000000000 (upper 32 bits zero) ✅
Cycles: 28
```

#### 5. 64-bit SD/LD - `test_rv64i_sd_ld_64bit.s`
```
Test: Full 64-bit value (0x123456789ABCDEF0)
Result: ✅ PASS
- t1 = 0x123456789abcdef0 (original)
- t2 = 0x123456789abcdef0 (loaded)
- a0 = 0x123456789abcdef0 (verified)
Cycles: 18
```

### Summary Table

| Instruction | Opcode | Funct3 | Test Status | Description |
|-------------|--------|--------|-------------|-------------|
| **LD** | 0000011 | 011 | ✅ PASS | Load 64-bit value |
| **LWU** | 0000011 | 110 | ✅ PASS | Load 32-bit, zero-extend to 64 |
| **SD** | 0100011 | 011 | ✅ PASS | Store 64-bit value |

## Additional Fixes

### 1. File: `tools/run_test_by_name.sh`
Made XLEN environment-aware:
```bash
# Before:
XLEN=32

# After:
XLEN=${XLEN:-32}  # Respect XLEN environment variable, default to 32
```

### 2. File: `tb/integration/tb_core_pipelined.v`
Added RV64 support for reset vector (for RV32 testbench when RV64 flag defined):
```verilog
// RISC-V compliance tests start at 0x80000000
// For RV64, use 64-bit reset vector; for RV32, use 32-bit
`ifdef COMPLIANCE_TEST
  `ifdef RV64
    parameter [63:0] RESET_VEC = 64'h0000000080000000;
  `else
    parameter [31:0] RESET_VEC = 32'h80000000;
  `endif
`else
  `ifdef RV64
    parameter [63:0] RESET_VEC = 64'h0000000080000000;
  `else
    parameter [31:0] RESET_VEC = 32'h00000000;
  `endif
`endif
```

## Key Insights

### 1. Hardware Was Already Correct
- Data memory module (`rtl/memory/data_memory.v`) already supported LD/LWU/SD
- Decoder and control logic already handled RV64I instructions
- No RTL changes needed - only testbench was broken

### 2. Memory Module Design
The data memory module already had proper support:
```verilog
// Load operations (lines 94-127)
case (funct3)
  3'b011: begin  // LD/FLD (load doubleword)
    read_data = dword_data;  // Return full 64 bits
  end
  3'b110: begin  // LWU (load word unsigned - RV64 only)
    read_data = {32'h0, word_data};  // Zero-extend
  end
  // ... other cases
endcase

// Store operations (lines 64-91)
case (funct3)
  3'b011: begin  // SD/FSD (store doubleword)
    mem[masked_addr]     <= write_data[7:0];
    mem[masked_addr + 1] <= write_data[15:8];
    // ... stores all 8 bytes
  end
  // ... other cases
endcase
```

### 3. Bus Interface Architecture
The pipelined core uses a bus master interface for memory access:
- Core generates bus requests (valid, addr, wdata, we, size)
- Bus adapter responds with ready and rdata
- This allows flexible memory subsystem (cache, peripherals, etc.)
- **Critical:** All bus ports must be connected in testbench

### 4. Testbench Design Lesson
- RV32 testbench (`tb_core_pipelined.v`) had correct bus interface
- RV64 testbench was created by copying and simplifying too much
- Missing bus interface caused undefined signal propagation
- Loads returned 0 because `bus_req_rdata` was undefined

## Test Files Created

1. `tests/asm/test_rv64i_ld_simple.s` - Simple LD test
2. `tests/asm/test_rv64i_sd_only.s` - SD-only test
3. `tests/asm/test_rv64i_ld_only.s` - LD-only test (with SW setup)
4. `tests/asm/test_rv64i_lw_test.s` - LW test for comparison
5. `tests/asm/test_rv64i_sd_ld_minimal.s` - SD+LD together
6. `tests/asm/test_rv64i_lwu.s` - LWU zero-extension test
7. `tests/asm/test_rv64i_sd_ld_64bit.s` - Full 64-bit value test
8. `tests/asm/test_rv64i_loads_stores.s` - Comprehensive test

## Important Note: EBREAK Timing

Discovered that EBREAK terminates simulation immediately, which can prevent final register writes from completing. Solution: Add NOPs before EBREAK to allow writeback:

```assembly
mv      a0, a2      # Move result
nop                 # Allow writeback to complete
nop
ebreak              # Now terminate
```

## Files Modified

1. `tb/integration/tb_core_pipelined_rv64.v` - Added bus interface (CRITICAL FIX)
2. `tools/run_test_by_name.sh` - Environment-aware XLEN
3. `tb/integration/tb_core_pipelined.v` - RV64 reset vector support
4. Created 8 new test files

## Next Steps

1. ✅ **COMPLETE** - RV64I load/store instructions validated
2. Run official RV64I compliance test suite
3. Test RV64M extension (64-bit multiply/divide)
4. Test RV64A extension (64-bit atomics)
5. Test RV64F/D extensions
6. Validate FreeRTOS on RV64

## Conclusion

**Major Milestone:** RV64I load/store instructions are fully functional! The issue was entirely in the testbench - the core hardware was already correctly implemented. This demonstrates the importance of proper testbench design and the value of having a working reference (RV32 testbench) for comparison.

All three RV64-specific load/store instructions (LD, LWU, SD) are now validated and working correctly. Combined with Session 78's word operations, the RV64I base integer instruction set is nearly complete.

**Phase 3 Progress:** RV64 upgrade is progressing well - foundation complete, ready for compliance testing.
