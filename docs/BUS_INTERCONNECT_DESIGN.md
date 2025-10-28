# Bus Interconnect Design - Phase 1.3

**Project**: RV1 RISC-V Processor
**Created**: 2025-10-26
**Status**: Design Phase
**Phase**: 1.3 - Bus Interconnect Implementation

---

## Table of Contents
1. [Overview](#overview)
2. [Design Rationale](#design-rationale)
3. [Bus Protocol](#bus-protocol)
4. [Architecture](#architecture)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Integration Steps](#integration-steps)

---

## Overview

### Purpose
Connect the CPU core to memory-mapped peripherals (CLINT, UART) with a clean, extensible bus architecture.

### Current State (Phase 1.2)
- ✅ CPU core with load/store to data memory (Harvard architecture)
- ✅ CLINT peripheral implemented (not memory-mapped yet)
- ✅ UART peripheral implemented (not memory-mapped yet)
- ❌ No bus interconnect - peripherals not accessible from CPU

### Goal State (Phase 1.3)
- ✅ CPU can read/write CLINT registers via load/store instructions
- ✅ CPU can read/write UART registers via load/store instructions
- ✅ Clean address decoding and bus arbitration
- ✅ Extensible architecture for future peripherals (PLIC, block storage)

### Benefits
1. **Software Access**: CPU can program timer, send/receive serial data
2. **OS Readiness**: Unlocks interrupt testing, FreeRTOS porting
3. **Clean Architecture**: Proper separation of concerns
4. **Extensibility**: Easy to add more peripherals

---

## Design Rationale

### Why Not Complex Bus (AXI, Wishbone)?
- **Simplicity**: Single-cycle access for peripherals, no bursting needed
- **Learning**: Build from first principles
- **Performance**: No overhead for simple use case
- **Future**: Can upgrade to AXI later if needed

### Why Simple Custom Bus?
- **Sufficient**: Handles current needs (3 devices: DMEM, CLINT, UART)
- **Extensible**: Easy to add more devices
- **Clean**: Minimal complexity, easy to debug
- **Familiar**: Similar to APB (Advanced Peripheral Bus) subset

---

## Bus Protocol

### Simple Request/Response Protocol

```verilog
// Bus Master (CPU) → Bus Slave (Peripheral)
req_valid   : 1-bit    // Transaction valid
req_addr    : XLEN-bit // Byte address
req_wdata   : 64-bit   // Write data (max 64-bit for RV32D/RV64)
req_we      : 1-bit    // Write enable (1=write, 0=read)
req_size    : 3-bit    // Access size (funct3 encoding: 000=byte, 001=half, 010=word, 011=dword)

// Bus Slave → Bus Master
req_ready   : 1-bit    // Slave ready (combinational for 1-cycle devices)
req_rdata   : 64-bit   // Read data
req_error   : 1-bit    // Bus error (optional, for invalid access)
```

### Timing Diagram (Single-Cycle)
```
Clk      : ┌──┐  ┌──┐  ┌──┐
           │  │  │  │  │  │
           └──┘  └──┘  └──┘

valid    : ────┐     ┌─────
               │_____│
addr     : ────< A1  >─────
wdata    : ────< D1  >─────
we       : ────< W   >─────
size     : ────< S   >─────

ready    : ────┐     ┌───── (combinational)
               │_____│
rdata    : ────< RD1 >───── (combinational or registered)
```

### Access Size Encoding (funct3)
| Size | Encoding | Description | Bytes |
|------|----------|-------------|-------|
| Byte | 3'b000 | LB/SB | 1 |
| Half | 3'b001 | LH/SH | 2 |
| Word | 3'b010 | LW/SW | 4 |
| Dword | 3'b011 | LD/SD (RV64) or FLD/FSD (RV32D) | 8 |

### Transaction Rules
1. **Single-Cycle**: All peripherals respond in 1 cycle (no wait states)
2. **Combinational Ready**: `ready` asserted immediately when `valid` high
3. **Registered Data**: Peripherals may register outputs for timing
4. **No Pipelining**: One transaction at a time (simple)
5. **Error Handling**: Invalid address → return 0 on read, ignore write (or assert error)

---

## Architecture

### Memory Map (Reminder)
| Address Range | Device | Size | Type |
|---------------|--------|------|------|
| `0x0000_0000 - 0x0000_FFFF` | IMEM | 64KB | Memory |
| `0x0200_0000 - 0x0200_FFFF` | CLINT | 64KB | Peripheral |
| `0x1000_0000 - 0x1000_0FFF` | UART | 4KB | Peripheral |
| `0x8000_0000 - 0x8000_FFFF` | DMEM | 64KB | Memory |

### Address Decode Logic
```verilog
// Decode based on address ranges
wire sel_dmem  = (addr[31:28] == 4'h8);           // 0x8xxx_xxxx
wire sel_clint = (addr[31:16] == 16'h0200);       // 0x0200_xxxx
wire sel_uart  = (addr[31:12] == 20'h10000);      // 0x1000_0xxx
wire sel_none  = !(sel_dmem || sel_clint || sel_uart);

// Mux slave responses
assign rdata = sel_dmem  ? dmem_rdata  :
               sel_clint ? clint_rdata :
               sel_uart  ? uart_rdata  :
               64'h0;

assign ready = sel_dmem  ? dmem_ready  :
               sel_clint ? clint_ready :
               sel_uart  ? uart_ready  :
               1'b0;  // Invalid address → not ready
```

### Block Diagram
```
┌───────────────────────────────────────────────────────────────┐
│                       RV Core (CPU)                           │
│  ┌──────────────────────────────────────────────────────┐    │
│  │   MEM Stage                                           │    │
│  │   - Load/Store address calculation                    │    │
│  │   - Generate: addr, wdata, we, size, valid            │    │
│  └──────────────────────────────────────────────────────┘    │
│                            │                                   │
│                            ▼                                   │
│  ┌──────────────────────────────────────────────────────┐    │
│  │   Peripheral Access Logic (NEW)                       │    │
│  │   - Detect peripheral address range                   │    │
│  │   - Route to bus or DMEM directly                     │    │
│  │   - Handle PTW (MMU) vs CPU access arbitration        │    │
│  └──────────────────────────────────────────────────────┘    │
└────────────────────────────┬──────────────────────────────────┘
                             │
                             ▼
        ┌────────────────────────────────────────┐
        │   Bus Arbiter/Decoder Module (NEW)     │
        │   - Address decode (DMEM/CLINT/UART)   │
        │   - Mux slave responses                 │
        │   - Bus error detection                 │
        └────────────────────────────────────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌───────────┐    ┌───────────┐    ┌───────────┐
    │   DMEM    │    │   CLINT   │    │   UART    │
    │  (64KB)   │    │ (Timer+   │    │ (16550)   │
    │           │    │  SWI)     │    │           │
    └───────────┘    └───────────┘    └───────────┘
```

---

## Implementation Plan

### Module 1: Bus Interface Wrapper (`bus_arbiter.v`)

**Purpose**: Central address decoder and response multiplexer

**Interface**:
```verilog
module bus_arbiter #(
  parameter XLEN = 32
) (
  // CPU/Master interface
  input  wire             req_valid,
  input  wire [XLEN-1:0]  req_addr,
  input  wire [63:0]      req_wdata,
  input  wire             req_we,
  input  wire [2:0]       req_size,
  output wire             req_ready,
  output wire [63:0]      req_rdata,
  output wire             req_error,

  // DMEM interface
  output wire             dmem_valid,
  output wire [XLEN-1:0]  dmem_addr,
  output wire [63:0]      dmem_wdata,
  output wire             dmem_we,
  output wire [2:0]       dmem_size,
  input  wire             dmem_ready,
  input  wire [63:0]      dmem_rdata,

  // CLINT interface
  output wire             clint_valid,
  output wire [15:0]      clint_addr,     // 16-bit offset within 64KB
  output wire [63:0]      clint_wdata,
  output wire             clint_we,
  output wire [2:0]       clint_size,
  input  wire             clint_ready,
  input  wire [63:0]      clint_rdata,

  // UART interface
  output wire             uart_valid,
  output wire [2:0]       uart_addr,      // 3-bit offset (8 registers)
  output wire [7:0]       uart_wdata,
  output wire             uart_we,
  input  wire             uart_ready,
  input  wire [7:0]       uart_rdata
);

  // Address decode
  wire sel_dmem  = (req_addr[31:28] == 4'h8);
  wire sel_clint = (req_addr[31:16] == 16'h0200);
  wire sel_uart  = (req_addr[31:12] == 20'h10000);
  wire sel_none  = !(sel_dmem || sel_clint || sel_uart);

  // Route request to selected slave
  assign dmem_valid  = req_valid && sel_dmem;
  assign clint_valid = req_valid && sel_clint;
  assign uart_valid  = req_valid && sel_uart;

  // Address mapping
  assign dmem_addr   = req_addr;
  assign clint_addr  = req_addr[15:0];
  assign uart_addr   = req_addr[2:0];

  // Data routing
  assign dmem_wdata  = req_wdata;
  assign clint_wdata = req_wdata;
  assign uart_wdata  = req_wdata[7:0];  // UART is 8-bit only

  assign dmem_we     = req_we;
  assign clint_we    = req_we;
  assign uart_we     = req_we;

  assign dmem_size   = req_size;
  assign clint_size  = req_size;

  // Response multiplexing
  assign req_ready = sel_dmem  ? dmem_ready  :
                     sel_clint ? clint_ready :
                     sel_uart  ? uart_ready  :
                     sel_none  ? 1'b0 : 1'b0;

  assign req_rdata = sel_dmem  ? dmem_rdata :
                     sel_clint ? clint_rdata :
                     sel_uart  ? {{56{1'b0}}, uart_rdata} :  // Zero-extend UART
                     64'h0;

  assign req_error = sel_none && req_valid;  // Invalid address
endmodule
```

### Module 2: Core Integration (Modify `rv_core_pipelined.v`)

**Changes Needed**:
1. Add peripheral access detection in MEM stage
2. Route peripheral addresses to bus instead of DMEM
3. Update MMU bare-mode bypass (peripherals bypass MMU)

**Key Logic**:
```verilog
// In MEM stage - detect peripheral access
wire is_peripheral_access = (arb_mem_addr[31:28] == 4'h0) ||  // CLINT range
                            (arb_mem_addr[31:28] == 4'h1);     // UART range

// Bypass MMU for peripheral access (always use physical address)
wire use_mmu_translation = mmu_enabled && !mmu_ptw_req_valid && !is_peripheral_access;

// Route to bus arbiter instead of direct DMEM
wire        bus_req_valid;
wire [XLEN-1:0] bus_req_addr;
wire [63:0] bus_req_wdata;
wire        bus_req_we;
wire [2:0]  bus_req_size;
wire        bus_req_ready;
wire [63:0] bus_req_rdata;
wire        bus_req_error;

// Instantiate bus arbiter
bus_arbiter #(
  .XLEN(XLEN)
) bus_arb (
  .req_valid(bus_req_valid),
  .req_addr(bus_req_addr),
  .req_wdata(bus_req_wdata),
  .req_we(bus_req_we),
  .req_size(bus_req_size),
  .req_ready(bus_req_ready),
  .req_rdata(bus_req_rdata),
  .req_error(bus_req_error),
  // Connect to DMEM, CLINT, UART...
);
```

### Module 3: SoC Update (`rv_soc.v`)

**Changes**:
1. Bus arbiter now inside CPU core (simplifies SoC)
2. Remove direct CLINT/UART instantiation from SoC
3. Move peripherals inside core, or keep SoC simple as top-level wrapper

**Decision**: Keep SoC as wrapper, bus arbiter + peripherals inside core
- Cleaner hierarchy
- Core becomes self-contained SoC
- Easier to test

**Alternative**: SoC contains bus arbiter
- More modular
- Easier to swap peripherals
- **Recommended approach** ✅

---

## Testing Strategy

### Unit Tests

#### Test 1: Bus Arbiter Address Decode
**File**: `tb/integration/tb_bus_arbiter.v`
**Coverage**:
- Write/Read to DMEM (0x8000_0000)
- Write/Read to CLINT (0x0200_0000, 0x0200_4000, 0x0200_BFF8)
- Write/Read to UART (0x1000_0000 - 0x1000_0007)
- Invalid address (0x5000_0000) → error

**Test Cases**:
```verilog
// Test 1: DMEM access
write_bus(32'h8000_0000, 64'hDEADBEEF_CAFEBABE, 1'b1, 3'b011);
read_bus(32'h8000_0000, expected_data);

// Test 2: CLINT MTIME read
read_bus(32'h0200_BFF8, mtime_value);

// Test 3: CLINT MTIMECMP write
write_bus(32'h0200_4000, 64'h0000_0000_0000_1000, 1'b1, 3'b011);

// Test 4: UART THR write
write_bus(32'h1000_0000, 64'h0000_0000_0000_0041, 1'b1, 3'b000);  // 'A'

// Test 5: Invalid address
write_bus(32'h5000_0000, 64'h1234, 1'b1, 3'b010);
assert(req_error == 1'b1);
```

### Integration Tests

#### Test 2: CPU Timer Interrupt
**File**: `tests/asm/test_clint_timer_interrupt.s`
**Coverage**:
- CPU reads MTIME via load instruction
- CPU writes MTIMECMP via store instruction
- Timer interrupt fires when MTIME >= MTIMECMP
- Trap handler increments counter, disables interrupt

```assembly
# Read MTIME
li t0, 0x0200BFF8
ld t1, 0(t0)         # Load 64-bit MTIME

# Set MTIMECMP = MTIME + 100
addi t1, t1, 100
li t0, 0x02004000
sd t1, 0(t0)         # Store 64-bit MTIMECMP

# Enable timer interrupt
li t0, 0x80          # MIE.MTIE
csrs mie, t0

# Enable global interrupts
li t0, 0x08          # MSTATUS.MIE
csrs mstatus, t0

# Wait for interrupt
1: j 1b

trap_handler:
  # Disable timer
  li t0, 0x02004000
  li t1, -1
  sd t1, 0(t0)       # Set MTIMECMP to max (disable)
  # Increment counter
  la t0, interrupt_count
  lw t1, 0(t0)
  addi t1, t1, 1
  sw t1, 0(t0)
  mret
```

#### Test 3: UART Transmit
**File**: `tests/asm/test_uart_transmit.s`
**Coverage**:
- CPU writes "Hello\n" to UART THR
- Testbench captures serial output
- Verify transmitted bytes

```assembly
# UART base
li s0, 0x10000000

# Transmit "Hello\n"
li a0, 'H'
call uart_putc
li a0, 'e'
call uart_putc
li a0, 'l'
call uart_putc
li a0, 'l'
call uart_putc
li a0, 'o'
call uart_putc
li a0, '\n'
call uart_putc

# Success
li a0, 0
j exit

uart_putc:
  # Wait for THR empty (LSR[5])
  li t0, 5           # LSR offset
  add t1, s0, t0
1:
  lbu t2, 0(t1)
  andi t2, t2, 0x20  # THRE bit
  beqz t2, 1b
  # Write character
  sb a0, 0(s0)       # THR offset 0
  ret
```

### Regression Tests
**Ensure no breakage**:
- Run `make test-quick` (14/14 tests)
- Run full compliance suite (81/81 tests)
- All existing tests should pass unchanged

---

## Integration Steps

### Step 1: Create Bus Arbiter Module ✅
- [ ] Create `rtl/bus/bus_arbiter.v`
- [ ] Add address decode logic
- [ ] Add response multiplexing
- [ ] Add bus error detection

### Step 2: Update Peripherals for Bus Interface ✅
- [ ] Update `rtl/peripherals/clint.v` (already has bus interface)
- [ ] Update `rtl/peripherals/uart_16550.v` (already has bus interface)
- [ ] Verify 1-cycle response timing

### Step 3: Integrate into Core ✅
- [ ] Modify `rtl/core/rv32i_core_pipelined.v`
- [ ] Add peripheral address detection
- [ ] Add MMU bypass for peripherals
- [ ] Connect bus arbiter
- [ ] Route load/store to bus

### Step 4: Update SoC Wrapper ✅
- [ ] Modify `rtl/rv_soc.v`
- [ ] Instantiate bus arbiter at SoC level
- [ ] Connect core, DMEM, CLINT, UART to bus
- [ ] Remove direct peripheral connections

### Step 5: Create Bus Testbench ✅
- [ ] Create `tb/integration/tb_bus_arbiter.v`
- [ ] Test address decode
- [ ] Test all peripherals
- [ ] Test invalid address

### Step 6: Write Integration Tests ✅
- [ ] Create `tests/asm/test_clint_timer.s`
- [ ] Create `tests/asm/test_uart_transmit.s`
- [ ] Add to quick regression suite

### Step 7: Run Regression ✅
- [ ] `make test-quick` (14/14)
- [ ] Full compliance (81/81)
- [ ] New integration tests

### Step 8: Documentation ✅
- [ ] Update `CLAUDE.md` with Phase 1.3 complete
- [ ] Create session summary
- [ ] Update memory map documentation

---

## Success Criteria

### Phase 1.3 Complete When:
- ✅ Bus arbiter module created and tested
- ✅ CPU can read/write CLINT registers via load/store
- ✅ CPU can read/write UART registers via load/store
- ✅ Timer interrupt test passes (CPU programs MTIMECMP, interrupt fires)
- ✅ UART transmit test passes (CPU sends "Hello\n")
- ✅ All existing tests still pass (14/14 quick, 81/81 compliance)
- ✅ Zero regressions

### Deliverables:
1. `rtl/bus/bus_arbiter.v` - Bus interconnect module
2. `tb/integration/tb_bus_arbiter.v` - Bus testbench
3. `tests/asm/test_clint_timer.s` - Timer programming test
4. `tests/asm/test_uart_transmit.s` - UART transmit test
5. Updated `rv_core_pipelined.v` - Peripheral access integration
6. Updated `rv_soc.v` - Bus integration
7. `docs/BUS_INTERCONNECT_DESIGN.md` - This document
8. `docs/SESSION_16_SUMMARY.md` - Implementation summary

---

## Future Enhancements (Phase 2+)

### Short-term (Phase 2: FreeRTOS)
- **No changes needed** - Current bus sufficient for FreeRTOS

### Medium-term (Phase 4: xv6)
- **PLIC Integration** - Add Platform-Level Interrupt Controller
- **Block Storage** - Add simple RAM disk or SD card
- **Bus Mastering** - If DMA needed (not required initially)

### Long-term (Phase 5: Linux)
- **AXI4 Upgrade** - Replace simple bus with AXI for bandwidth
- **Caching** - Add instruction/data caches
- **Multicore** - Shared bus arbitration for multiple cores

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-10-26 | Initial design document | RV1 Project |

---

**Status**: 📋 Design Complete - Ready for Implementation
