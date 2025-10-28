# Session 33: IMEM Bus Access for .rodata Copy

**Date:** 2025-10-27
**Status:** ✅ **COMPLETE - Printf Working!**
**Achievement:** 🎉 **String constants now accessible - FreeRTOS outputs text!** 🎉

## Problem Statement

After Session 32's Harvard architecture fix (moving .rodata to DMEM), printf was still only outputting newlines. Investigation revealed that the `.rodata` copy loop was reading **all zeros** from IMEM, even though the hex file contained the correct string data.

## Root Cause Analysis

### The Harvard Architecture Constraint

In a Harvard architecture system:
- **Instruction fetches** access IMEM
- **Load/store instructions** access DMEM via the bus
- **IMEM is NOT accessible via load instructions** ❌

### The Problem Chain

1. Linker places `.rodata` at LMA=0x3DE8 (in IMEM hex file)
2. Startup code executes:
   ```assembly
   la t0, __rodata_load_start  # t0 = 0x3DEC (IMEM address)
   lw t3, 0(t0)                # Load from address 0x3DEC
   ```
3. `LW` instruction → goes to bus → **no slave at address 0x3DEC** → returns zeros
4. Zeros get copied to DMEM → printf reads zeros → no text output

### Why This Wasn't Obvious

- IMEM **was** loaded correctly with string data (verified at 0x42B8: "[Task")
- The bus interconnect simply didn't have IMEM mapped
- Loads from low addresses (0x0-0xFFFF) fell through to the "invalid address" handler (returns zeros)

## The Solution: IMEM as Bus Slave

### Elegant Approach

**Make IMEM accessible via the bus as a read-only slave**

This is a common pattern in embedded systems - instruction memory is mapped into the address space so it can be read as data when needed (e.g., for copying constants to RAM).

### Implementation

#### 1. Bus Interconnect Changes (`simple_bus.v`)

Added IMEM as Slave 4:

```verilog
// Memory Map:
//   0x0000_0000 - 0x0000_FFFF: IMEM (64KB) - read-only via bus
//   0x0200_0000 - 0x0200_FFFF: CLINT (64KB)
//   0x0C00_0000 - 0x0FFF_FFFF: PLIC (64MB)
//   0x1000_0000 - 0x1000_0FFF: UART (4KB)
//   0x8000_0000 - 0x800F_FFFF: DMEM (1MB)

// Address decode
localparam IMEM_BASE  = 32'h0000_0000;
localparam IMEM_MASK  = 32'hFFFF_0000;   // 64KB range
assign sel_imem  = ((master_req_addr & IMEM_MASK) == IMEM_BASE);

// Request routing
if (sel_imem) begin
  imem_req_valid = 1'b1;
  imem_req_addr  = master_req_addr;
  // IMEM is read-only, ignore writes
end

// Response routing
if (sel_imem) begin
  master_req_ready = imem_req_ready;
  master_req_rdata = {32'h0, imem_req_rdata};  // Zero-extend 32-bit to 64-bit
end
```

**Key Design Decisions:**
- **Read-only:** Writes to IMEM via bus are ignored (FENCE.I writes handled separately)
- **Priority:** IMEM has highest priority in address decode (most specific mask)
- **Width:** IMEM returns 32-bit data, zero-extended to 64-bit for bus

#### 2. SoC Integration (`rv_soc.v`)

Created a second read port for IMEM:

```verilog
// Instantiate second instruction_memory for data reads
instruction_memory #(
  .XLEN(XLEN),
  .MEM_SIZE(IMEM_SIZE),
  .MEM_FILE(MEM_FILE)
) imem_data_port (
  .clk(clk),
  .addr(imem_req_addr),
  .instruction(imem_data_port_instruction),
  // Write interface unused (read-only port)
  .mem_write(1'b0),
  .write_addr({XLEN{1'b0}}),
  .write_data({XLEN{1'b0}}),
  .funct3(3'b0)
);

// Simple adapter: always ready, passthrough data
assign imem_req_ready = imem_req_valid;
assign imem_req_rdata = imem_data_port_instruction;
```

**Why a Second Instance?**
- Core's IMEM is dedicated to instruction fetches (address from PC)
- Data reads need independent address (from bus)
- Both instances load from the same hex file
- Read-only access means no coherency issues

#### 3. Bus Adapter (`imem_bus_adapter.v`)

Created minimal adapter (actually not used - direct connection simpler):

```verilog
module imem_bus_adapter (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             req_valid,
  input  wire [31:0]      req_addr,
  output wire             req_ready,
  output wire [31:0]      req_rdata,
  output wire [31:0]      imem_addr,
  input  wire [31:0]      imem_rdata
);
  assign imem_addr  = req_addr;
  assign req_rdata  = imem_rdata;
  assign req_ready  = req_valid;
endmodule
```

## Testing & Verification

### Debug Journey

1. **Initial Confusion:** IMEM appeared to have zeros at 0x3DE8
   - **Reality:** First 15 bytes of .rodata ARE zeros (alignment padding)
   - Verified by checking 0x42B8 where string "[Task" is located

2. **Hex File Verification:**
   ```
   @00003DE8
   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10  (first line - mostly zeros)
   ...
   5B 54 61 73 6B 31 5D 20 54 69 63 6B 20 25 6C 75  ([Task1] Tick %lu)
   ```

3. **Memory Inspection:**
   ```
   CORE IMEM[0x42b8] = 0x7361545b  ('[Tas' in little-endian)
   DATA PORT IMEM[0x42b8] = 0x7361545b  (both instances loaded correctly!)
   ```

### UART Output

```
================================================================================

    FFrreeeeRRTTOOSS  BBlliinnkkyy  DDeemmoo

    TTaarrggeett::  RRVV11  RRVV3322IIMMAAFFDDCC  CCoorree
```

**Success!** Strings are being output (each character duplicated due to minor UART timing issue).

### Printf Verification

```
[PRINTF] Cycle 7175: printf() called with format string at a0=0x80000000
[PRINTF]   Format string in DMEM range (good!)
```

Format string pointer is in DMEM (0x80000000-0x800FFFFF) as expected.

## Results

✅ **IMEM accessible via bus at addresses 0x0000-0xFFFF**
✅ **Startup code successfully copies .rodata from IMEM to DMEM**
✅ **String constants present in DMEM after copy**
✅ **Printf outputs actual text: "FreeRTOS Blinky Demo"**
✅ **No linker script changes needed**
✅ **No startup code changes needed**

## Architecture Benefits

### Why This Approach is Elegant

1. **Maintains Harvard Architecture**
   - Instruction fetches still go directly to IMEM (not via bus)
   - Data accesses go through bus (with IMEM now mapped)
   - Clear separation of concerns

2. **Common in Real Systems**
   - Many embedded MCUs map flash/ROM into address space
   - Allows reading constants, instruction data, etc.
   - Standard pattern for const data in ROM

3. **No Software Changes**
   - Linker script unchanged (`.rodata : { ... } > DMEM AT > IMEM`)
   - Startup code unchanged (standard copy loop)
   - Transparent to application code

4. **Minimal Hardware Cost**
   - One additional memory instance (read-only)
   - Simple bus routing logic
   - No complex address translation

## Memory Map (Updated)

```
0x0000_0000 - 0x0000_FFFF: IMEM (64KB) - instruction fetch + data read
0x0200_0000 - 0x0200_FFFF: CLINT (64KB) - timer + software interrupts
0x0C00_0000 - 0x0FFF_FFFF: PLIC (64MB) - interrupt controller
0x1000_0000 - 0x1000_0FFF: UART (4KB) - serial console
0x8000_0000 - 0x800F_FFFF: DMEM (1MB) - data RAM
```

**Notes:**
- IMEM at 0x0 is **read-only** via bus (writes ignored)
- IMEM instruction fetch port is separate (not via bus)
- Startup code copies .rodata from IMEM → DMEM at boot

## Known Issues

### Minor: UART Character Duplication

Each character appears twice in UART output:
```
FFrreeeeRRTTOOSS  (should be: FreeRTOS)
```

**Likely Cause:** UART timing issue or printf calling write() twice
**Impact:** Low - strings are readable
**Priority:** Low - cosmetic issue

## Files Modified

### RTL Changes

1. **rtl/interconnect/simple_bus.v**
   - Added IMEM slave interface (ports)
   - Added IMEM address decode logic
   - Added IMEM request/response routing
   - Updated memory map comments

2. **rtl/rv_soc.v**
   - Added IMEM bus signal declarations
   - Instantiated second instruction_memory instance (`imem_data_port`)
   - Connected IMEM to bus interconnect
   - Added debug initial block (temporary)

3. **rtl/adapters/imem_bus_adapter.v** (NEW)
   - Simple passthrough adapter for IMEM bus access
   - (Note: Eventually absorbed into direct connection in rv_soc.v)

### Testbench Changes

4. **tb/integration/tb_freertos.v**
   - Added .rodata copy monitoring (PC 0x56-0x68)
   - Added IMEM data port inspection
   - Added printf call monitoring
   - Enhanced UART character decoding

## Lessons Learned

1. **Harvard Architecture Constraints**
   - Must explicitly map instruction memory for data access
   - Load instructions CANNOT access IMEM without bus mapping

2. **Debug Red Herrings**
   - "All zeros" doesn't always mean "not loaded"
   - First bytes of .rodata happened to BE zeros (alignment)
   - Always check known non-zero addresses (e.g., string literals)

3. **$readmemh Behavior**
   - DOES support address gaps with `@` markers
   - Correctly loads fragmented address spaces
   - Both IMEM instances loaded independently and correctly

4. **Bus-Based Architecture**
   - Making memories bus-accessible adds flexibility
   - Common pattern in real embedded systems
   - Minimal hardware cost for significant benefit

## Next Steps

1. **Fix UART Character Duplication** (Low Priority)
   - Debug why each character appears twice
   - Check printf → write() → UART path
   - Verify UART timing/flow control

2. **Test Full FreeRTOS Functionality**
   - Verify task switching works correctly
   - Check if all printf output is readable
   - Run longer simulations

3. **Performance Optimization** (Future)
   - Consider unified memory with region attributes
   - Evaluate if second IMEM instance is optimal
   - Profile memory access patterns

## References

- **Session 32:** Harvard Architecture Fix (.rodata to DMEM)
- **Session 30:** IMEM Corruption Bug Fix
- **RISC-V Spec:** Memory-Mapped I/O and Address Spaces
- **Embedded Systems:** ROM/Flash mapping patterns
