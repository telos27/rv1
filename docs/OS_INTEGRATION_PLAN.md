# OS Integration Plan: FreeRTOS → xv6 → Linux

**Project**: RV1 RISC-V Processor OS Testing
**Created**: 2025-10-26
**Status**: Phase 1 - In Progress
**Timeline**: 16-24 weeks

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Architecture Progression](#architecture-progression)
3. [Phase 1: RV32 Interrupt Infrastructure](#phase-1-rv32-interrupt-infrastructure)
4. [Phase 2: FreeRTOS](#phase-2-freertos-on-rv32)
5. [Phase 3: RV64 Upgrade](#phase-3-rv64-upgrade)
6. [Phase 4: xv6-riscv](#phase-4-xv6-riscv)
7. [Phase 5a: Linux nommu (Optional)](#phase-5a-linux-nommu-optional)
8. [Phase 5b: Linux with MMU](#phase-5b-linux-with-mmu)
9. [Success Criteria](#success-criteria)
10. [References](#references)

---

## Executive Summary

### Goal
Progressive OS validation from simple RTOS to full-featured Linux, validating all aspects of the RV1 CPU implementation.

### Strategy
- **Start Small**: Begin with RV32 + minimal peripherals
- **Add Incrementally**: Each phase builds on previous success
- **Dual Architecture**: RV32 for embedded (FreeRTOS, nommu), RV64 for Unix (xv6, Linux)
- **Standard Compliance**: Use OpenSBI + U-Boot for industry-standard boot flow

### Key Milestones
1. ✅ **Phase 0**: 100% ISA compliance (81/81 tests) - **COMPLETE**
2. 🚧 **Phase 1**: Interrupt infrastructure (CLINT + UART) - **IN PROGRESS** (Phase 1.1 ✅, Phase 1.2 ✅)
3. ⏭️ **Phase 2**: FreeRTOS multitasking
4. ⏭️ **Phase 3**: RV64 + Sv39 MMU upgrade
5. ⏭️ **Phase 4**: xv6 Unix-like OS
6. ⏭️ **Phase 5**: Full Linux (nommu + MMU variants)

---

## Architecture Progression

### Current State (Phase 0 Complete)
- **CPU**: RV32IMAFDC, 5-stage pipeline, precise exceptions
- **Privilege**: M/S/U modes, trap delegation, CSR forwarding
- **MMU**: Sv32 (2-level page tables, 16-entry TLB)
- **FPU**: Single+double precision, shared 64-bit regfile
- **Compliance**: 100% (81/81 official tests + 127 custom tests)
- **Memory**: 64KB IMEM, 64KB DMEM (Harvard architecture)
- **Interrupts**: ❌ None - CSRs exist but no injection mechanism
- **Peripherals**: ❌ None

### Target State (Phase 5 Complete)
- **CPU**: RV32/RV64 IMAFDC (configurable)
- **MMU**: Sv39 for RV64, Sv32 for RV32
- **Memory**: 1MB IMEM, 4MB DMEM (unified SoC memory)
- **Interrupts**: ✅ CLINT (timer + software), PLIC (external)
- **Peripherals**: ✅ UART, Block storage, (optional: Ethernet, GPIO)
- **Boot**: ✅ OpenSBI firmware + U-Boot bootloader
- **OS**: ✅ FreeRTOS, xv6, Linux (nommu + MMU)

---

## Phase 1: RV32 Interrupt Infrastructure

**Duration**: 2-3 weeks
**Status**: 🚧 In Progress (Phase 1.1 ✅, Phase 1.2 ✅)
**Priority**: 🔴 Critical - Blocks all OS work
**Update (2025-10-26)**: Phase 1.1 CLINT integration complete (Session 12), Phase 1.2 UART complete (Session 15)

### 1.1: CLINT (Core-Local Interruptor) ✅ COMPLETE

#### Purpose
Provides timer and software interrupts per RISC-V specification. Required for context switching in all OSes.

#### Hardware Specification
- **Module**: `rtl/peripherals/clint.v`
- **Memory Map** (QEMU-compatible):
  ```
  0x0200_0000: MSIP (Machine Software Interrupt Pending) - 32-bit per hart
  0x0200_4000: MTIMECMP - 64-bit compare value
  0x0200_BFF8: MTIME - 64-bit real-time counter
  ```
- **Functionality**:
  - MTIME: Free-running 64-bit counter, increments every clock cycle
  - MTIMECMP: When MTIME ≥ MTIMECMP, assert MTI (machine timer interrupt)
  - MSIP: Software-writable bit to trigger software interrupt (MSI)
- **Outputs**:
  - `mti_o`: Machine timer interrupt (connects to core `mip[7]`)
  - `msi_o`: Machine software interrupt (connects to core `mip[3]`)

#### Implementation Details
```verilog
module clint #(
  parameter NUM_HARTS = 1
) (
  input  wire        clk,
  input  wire        reset_n,

  // Memory-mapped interface
  input  wire        req_valid,
  input  wire [31:0] req_addr,
  input  wire [63:0] req_wdata,
  input  wire        req_we,
  input  wire [2:0]  req_size,
  output reg         req_ready,
  output reg  [63:0] req_rdata,

  // Interrupt outputs
  output wire [NUM_HARTS-1:0] mti_o,  // Machine timer interrupt
  output wire [NUM_HARTS-1:0] msi_o   // Machine software interrupt
);
```

#### Integration Points
- Connect to SoC memory bus (address decode 0x0200_xxxx)
- Wire `mti_o` → core's external interrupt input for `mip[7]`
- Wire `msi_o` → core's external interrupt input for `mip[3]`

#### Testing Strategy
1. **Unit test**: Write testbench `tb/peripherals/tb_clint.v`
   - Verify MTIME increments each clock
   - Write MTIMECMP, check MTI assertion
   - Write MSIP, check MSI assertion
2. **Integration test**: Assembly program
   - Configure MTIMECMP for 1000 cycles
   - Set up `mtvec`, enable `mie[7]`
   - Wait for interrupt, verify trap handler called
3. **Privilege test**: Add to Phase 3 interrupt tests

### 1.2: UART (Universal Asynchronous Receiver/Transmitter) ✅ COMPLETE

**Status**: ✅ Complete (Session 15 - 2025-10-26)
**Implementation**: `rtl/peripherals/uart_16550.v` (342 lines, 12/12 tests passing)
**Details**: See `docs/SESSION_15_SUMMARY.md`

#### Purpose
Console I/O for debugging, user interaction, and OS stdout/stdin.

#### Hardware Specification
- **Module**: `rtl/peripherals/uart.v`
- **Compatibility**: 16550-compatible subset
- **Memory Map**:
  ```
  0x1000_0000: RBR (Receive Buffer) / THR (Transmit Hold) - 8-bit
  0x1000_0001: IER (Interrupt Enable Register) - 8-bit
  0x1000_0002: IIR (Interrupt ID) / FCR (FIFO Control) - 8-bit
  0x1000_0003: LCR (Line Control Register) - 8-bit
  0x1000_0004: MCR (Modem Control Register) - 8-bit
  0x1000_0005: LSR (Line Status Register) - 8-bit
  0x1000_0006: MSR (Modem Status Register) - 8-bit
  0x1000_0007: SCR (Scratch Register) - 8-bit
  ```
- **Configuration**: 8N1 (8 data bits, no parity, 1 stop bit)
- **Baud Rate**: Fixed 115200 (simplified - no divisor latch)
- **FIFOs**: Optional 16-byte TX/RX FIFOs (can start with 1-byte)

#### Key Registers
- **LSR (Line Status)**:
  - Bit 0: Data Ready (DR) - RX data available
  - Bit 5: TX Holding Register Empty (THRE) - can write
  - Bit 6: TX Empty (TEMT) - all data transmitted
- **IER (Interrupt Enable)**:
  - Bit 0: Enable RX data available interrupt
  - Bit 1: Enable TX empty interrupt

#### Implementation Details
```verilog
module uart #(
  parameter CLK_FREQ = 50_000_000,
  parameter BAUD_RATE = 115200
) (
  input  wire       clk,
  input  wire       reset_n,

  // Memory-mapped interface
  input  wire       req_valid,
  input  wire [2:0] req_addr,    // Only 3 bits (8 registers)
  input  wire [7:0] req_wdata,
  input  wire       req_we,
  output reg        req_ready,
  output reg  [7:0] req_rdata,

  // UART physical interface
  input  wire       uart_rx,
  output wire       uart_tx,

  // Interrupt output
  output wire       uart_irq
);
```

#### Integration Points
- Connect to SoC memory bus (address decode 0x1000_xxxx)
- Wire `uart_irq` → PLIC (later) or directly to `mip[11]` (external interrupt)
- Physical pins: `uart_rx`, `uart_tx` go to top-level I/O

#### Testing Strategy
1. **Unit test**: Testbench with UART model
   - Write byte to THR, observe TX pin shifting bits
   - Send bits to RX pin, check RBR and LSR[DR]
   - Verify timing (baud rate clock division)
2. **Integration test**:
   - Assembly program prints "Hello, World!" character-by-character
   - Poll LSR[THRE] before each write
3. **Echo test**: Read RX, echo to TX

### 1.3: SoC Integration

#### Top-Level Module
- **Module**: `rtl/rv_soc.v`
- **Purpose**: Integrate core + memory + peripherals + bus fabric

#### Memory Map
```
Address Range          | Device              | Size   | Attributes
-----------------------|---------------------|--------|------------
0x0000_0000-0x0000_FFFF| Instruction RAM     | 64KB   | RX (execute)
0x0200_0000-0x0200_FFFF| CLINT               | 64KB   | RW
0x1000_0000-0x1000_0FFF| UART                | 4KB    | RW
0x8000_0000-0x8000_FFFF| Data RAM            | 64KB   | RW
```

**Future expansions**:
```
0x0C00_0000-0x0FFF_FFFF| PLIC                | 64MB   | RW (Phase 4)
0x8800_0000-0x88FF_FFFF| Block Device/RAM    | 16MB   | RW (Phase 4)
0x9000_0000-0x9000_0FFF| Ethernet            | 4KB    | RW (Phase 5, optional)
0x9100_0000-0x9100_0FFF| GPIO                | 4KB    | RW (Phase 5, optional)
```

#### Address Decoder
```verilog
always @(*) begin
  case (req_addr[31:16])
    16'h0000: device_sel = DEVICE_IMEM;   // 0x0000_xxxx
    16'h0200: device_sel = DEVICE_CLINT;  // 0x0200_xxxx
    16'h1000: device_sel = DEVICE_UART;   // 0x1000_xxxx
    16'h8000: device_sel = DEVICE_DMEM;   // 0x8000_xxxx
    default:  device_sel = DEVICE_NONE;
  endcase
end
```

#### Interrupt Routing
```verilog
// Map interrupts to mip bits per RISC-V spec
assign external_interrupts = {
  51'b0,           // Reserved
  uart_irq,        // mip[11] - External interrupt 11 (UART)
  3'b0,            // Reserved
  mti,             // mip[7]  - Machine timer interrupt
  3'b0,            // Reserved
  msi,             // mip[3]  - Machine software interrupt
  3'b0             // Reserved
};
```

#### Implementation Notes
- Use simple parallel bus (req/ready handshake)
- Single-cycle access for on-chip RAM
- Multi-cycle access for peripherals (UART baud rate)
- No bus arbitration needed (single master - core)

### 1.4: Privilege Mode Interrupt Tests

Complete the 6 skipped tests from Phase 3:

#### Test 1: `test_interrupt_enable_disable.s`
**Purpose**: Verify MIE/SIE global interrupt enable bits

**Test Flow**:
1. Disable interrupts (`mie.MIE = 0`)
2. Trigger timer interrupt (MTIME > MTIMECMP)
3. Verify no trap occurs (interrupt pending but not taken)
4. Enable interrupts (`mie.MIE = 1`)
5. Verify trap occurs immediately

#### Test 2: `test_interrupt_delegation.s`
**Purpose**: Verify `mideleg` delegates interrupts to S-mode

**Test Flow**:
1. Set `mideleg[7] = 1` (delegate timer interrupt to S-mode)
2. Enter S-mode
3. Trigger timer interrupt
4. Verify trap goes to S-mode handler (not M-mode)

#### Test 3: `test_interrupt_pending.s`
**Purpose**: Verify `mip`/`sip` register behavior

**Test Flow**:
1. Trigger timer interrupt with interrupts disabled
2. Read `mip[7]`, verify it's set (pending)
3. Clear by writing `mtimecmp` (or `mip` write for software interrupts)
4. Verify `mip[7]` clears

#### Test 4: `test_timer_interrupt.s`
**Purpose**: Basic timer interrupt delivery

**Test Flow**:
1. Set up trap handler
2. Configure `mtimecmp = mtime + 1000`
3. Enable `mie.MTIE = 1`, `mstatus.MIE = 1`
4. Wait in loop
5. Verify trap handler called with `mcause = 0x8000_0007`

#### Test 5: `test_nested_interrupts.s`
**Purpose**: Verify interrupt-during-interrupt handling

**Test Flow**:
1. Set up timer interrupt with short interval
2. In ISR, re-enable `mstatus.MIE` (allow nesting)
3. Wait for second interrupt
4. Verify second interrupt preempts first
5. Verify both complete correctly (LIFO order)

#### Test 6: `test_interrupt_priority.s`
**Purpose**: Verify exceptions have priority over interrupts

**Test Flow**:
1. Trigger timer interrupt (pending)
2. Execute illegal instruction
3. Verify exception traps before interrupt
4. After exception handler returns, interrupt should fire

---

## Phase 2: FreeRTOS on RV32

**Duration**: 1-2 weeks
**Status**: ⏭️ Pending (blocked on Phase 1)

### 2.1: FreeRTOS Port

#### Source
- **Upstream**: https://github.com/FreeRTOS/FreeRTOS-Kernel
- **Port**: `portable/GCC/RISC-V/`
- **Location**: `software/freertos/`

#### Configuration
- **File**: `software/freertos/FreeRTOSConfig.h`
- **Key Settings**:
  ```c
  #define configCPU_CLOCK_HZ              50000000  // 50MHz
  #define configTICK_RATE_HZ              1000      // 1ms tick
  #define configMINIMAL_STACK_SIZE        128       // words
  #define configTOTAL_HEAP_SIZE           16384     // bytes
  #define configMAX_PRIORITIES            5
  #define configUSE_PREEMPTION            1
  #define configUSE_TIME_SLICING          1
  ```

#### Port-Specific Code
**File**: `software/freertos/port.c`

Key functions to implement:
1. **`pxPortInitialiseStack()`**: Set up initial task stack
   - Push return address, saved registers
   - Set initial `mepc` to task function
2. **`xPortStartScheduler()`**:
   - Configure CLINT for tick interrupt
   - Enable timer interrupt
   - Jump to first task
3. **`vPortYield()`**: Software context switch
   - Trigger `ecall` or software interrupt
4. **Trap handler** (`freertos_trap_handler`):
   - Save context (all registers) to task stack
   - Call scheduler (`vTaskSwitchContext()`)
   - Restore context from new task stack
   - Return via `mret`

#### Memory Layout
```
0x8000_0000: .text (code)
0x8000_2000: .rodata (constants)
0x8000_3000: .data (initialized globals)
0x8000_4000: .bss (zero-initialized globals)
0x8000_5000: Heap (16KB - configTOTAL_HEAP_SIZE)
0x8000_9000: Task 1 stack (512 bytes)
0x8000_9200: Task 2 stack (512 bytes)
...
```

### 2.2: Demo Applications

#### Blinky Demo
**File**: `software/freertos/demo/blinky.c`

```c
void vBlinkTask1(void *pvParameters) {
  while(1) {
    uart_print("Task 1\r\n");
    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

void vBlinkTask2(void *pvParameters) {
  while(1) {
    uart_print("Task 2\r\n");
    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}
```

**Expected Output**:
```
Task 1
Task 2
Task 1
Task 1
Task 2
Task 1
...
```

#### Queue Test
**File**: `software/freertos/demo/queue_test.c`

Producer-consumer pattern testing queue IPC:
```c
void vProducer(void *pvParameters) {
  uint32_t counter = 0;
  while(1) {
    xQueueSend(xQueue, &counter, portMAX_DELAY);
    counter++;
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

void vConsumer(void *pvParameters) {
  uint32_t received;
  while(1) {
    xQueueReceive(xQueue, &received, portMAX_DELAY);
    uart_printf("Received: %d\r\n", received);
  }
}
```

### 2.3: Build System

**Makefile**: `software/freertos/Makefile`

```makefile
CROSS_COMPILE = riscv32-unknown-elf-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

CFLAGS = -march=rv32imafdc -mabi=ilp32d -O2 -g
CFLAGS += -I. -IFreeRTOS-Kernel/include
CFLAGS += -IFreeRTOS-Kernel/portable/GCC/RISC-V

LDFLAGS = -T linker.ld -nostartfiles

SRCS = startup.S port.c demo/blinky.c
SRCS += FreeRTOS-Kernel/tasks.c
SRCS += FreeRTOS-Kernel/queue.c
SRCS += FreeRTOS-Kernel/list.c
SRCS += FreeRTOS-Kernel/portable/GCC/RISC-V/port.c
SRCS += FreeRTOS-Kernel/portable/MemMang/heap_4.c

all: freertos.hex

freertos.elf: $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) $(LDFLAGS) -o $@

freertos.hex: freertos.elf
	$(OBJCOPY) -O verilog $< $@
```

### 2.4: Validation Criteria
- ✅ Boot message "FreeRTOS started" appears
- ✅ Multiple tasks print messages in interleaved order
- ✅ Task delays work correctly (timing verified)
- ✅ Queue send/receive works without data corruption
- ✅ Semaphores work (binary and counting)
- ✅ No stack overflow or memory corruption
- ✅ System runs for extended period (hours) without hang

---

## Phase 3: RV64 Upgrade

**Duration**: 2-3 weeks
**Status**: ⏭️ Pending

### 3.1: Core Modifications

#### XLEN Parameter Change
**File**: `rtl/config/rv_config.vh`
```verilog
`define XLEN 64  // Change from 32
```

#### Verify RV64I Instructions
All 64-bit operations already implemented (RV64I extension):
- ✅ ADDW, SUBW, ADDIW (32-bit operations with sign-extend)
- ✅ SLLW, SRLW, SRAW, SLLIW, SRLIW, SRAIW (32-bit shifts)
- ✅ LWU (load word unsigned)
- ✅ LD, SD (64-bit load/store)

**Testing**: Run official RV64I compliance tests
```bash
env XLEN=64 ./tools/run_official_tests.sh rv64ui
```

Expected: 48 RV64I tests pass

#### Verify RV64M Instructions
- ✅ MULW, DIVW, DIVUW, REMW, REMUW (32-bit multiply/divide)

**Testing**:
```bash
env XLEN=64 ./tools/run_official_tests.sh rv64um
```

Expected: 8 tests pass

### 3.2: MMU Upgrade (Sv32 → Sv39)

#### Sv39 Specification
- **Virtual Address**: 39 bits (vs 32 bits for Sv32)
- **Page Table Levels**: 3 (vs 2 for Sv32)
- **VPN structure**: VPN[2] (9 bits) | VPN[1] (9 bits) | VPN[0] (9 bits) | Offset (12 bits)
- **PPN structure**: 44 bits (vs 22 bits for Sv32)
- **SATP encoding**: Mode=8 (vs Mode=1 for Sv32)

#### MMU Modifications
**File**: `rtl/core/mmu.v`

Changes required:
1. Add 3rd level to page table walker
2. Expand VPN extraction logic
3. Expand PPN to 44 bits
4. Update SATP mode check
5. Expand TLB entries to 44-bit PPN

**Key Code Changes**:
```verilog
// Extract VPNs for Sv39
wire [8:0] vpn2 = req_vaddr[38:30];
wire [8:0] vpn1 = req_vaddr[29:21];
wire [8:0] vpn0 = req_vaddr[20:12];

// Page table walk state machine - add LEVEL2 state
// Calculate PTE address at each level
wire [XLEN-1:0] pte_addr_L2 = {satp_ppn, 12'b0} + {vpn2, 3'b0};
wire [XLEN-1:0] pte_addr_L1 = {pte_ppn, 12'b0} + {vpn1, 3'b0};
wire [XLEN-1:0] pte_addr_L0 = {pte_ppn, 12'b0} + {vpn0, 3'b0};
```

#### Testing
1. **Unit tests**: Page table walk with 3 levels
2. **TLB tests**: Verify Sv39 entries cached correctly
3. **Page fault tests**: Invalid PTEs at each level
4. **Huge page tests**: 2MB (L1) and 1GB (L2) pages

### 3.3: Memory Expansion

**Reason**: Linux kernel + rootfs needs more than 128KB

#### Memory Configuration
**File**: `rtl/config/rv_config.vh`
```verilog
`define IMEM_SIZE 1048576  // 1MB (was 65536)
`define DMEM_SIZE 4194304  // 4MB (was 65536)
```

#### Unified Memory Space
Instead of separate I/D memory, use unified RAM:
- **0x8000_0000 - 0x8050_0000**: 5MB unified RAM
- Bootloader/kernel loads here
- MMU translates user space separately

**Module**: Create `rtl/memory/system_ram.v`
```verilog
module system_ram #(
  parameter SIZE = 5242880  // 5MB
) (
  input  wire        clk,
  input  wire        req_valid,
  input  wire [31:0] req_addr,
  input  wire [63:0] req_wdata,
  input  wire        req_we,
  input  wire [2:0]  req_size,
  output reg         req_ready,
  output reg  [63:0] req_rdata
);
```

### 3.4: RV64 Regression Testing

**Test Suite**:
1. RV64I: 48 tests
2. RV64M: 8 tests
3. RV64A: 10 tests
4. RV64F: 11 tests
5. RV64D: 9 tests
6. RV64C: 1 test

**Total**: 87 tests (vs 81 for RV32)

**Run All**:
```bash
env XLEN=64 make test-all-official
```

**Expected**: 87/87 passing ✅

---

## Phase 4: xv6-riscv

**Duration**: 3-5 weeks
**Status**: ⏭️ Pending

### 4.1: PLIC Implementation

#### Purpose
Routes external interrupts (UART, block device, network, etc.) to harts with priority-based arbitration.

#### Specification
- **Interrupt Sources**: 32 external interrupt lines
- **Harts**: 1 (single-core initially)
- **Priorities**: 0-7 (0 = no interrupt, 7 = highest)
- **Modes**: M-mode and S-mode separate enables/thresholds

#### Memory Map
```
0x0C00_0000: Interrupt priorities (0-31) - 4 bytes each = 128 bytes
0x0C00_1000: Interrupt pending bits - 32 bits = 4 bytes
0x0C00_2000: Interrupt enable bits (M-mode, hart 0) - 32 bits
0x0C00_2080: Interrupt enable bits (S-mode, hart 0) - 32 bits
0x0C20_0000: Priority threshold (M-mode, hart 0) - 4 bytes
0x0C20_0004: Claim/complete register (M-mode, hart 0) - 4 bytes
0x0C20_1000: Priority threshold (S-mode, hart 0) - 4 bytes
0x0C20_1004: Claim/complete register (S-mode, hart 0) - 4 bytes
```

#### Module Interface
**File**: `rtl/peripherals/plic.v`

```verilog
module plic #(
  parameter NUM_SOURCES = 32,
  parameter NUM_HARTS = 1
) (
  input  wire                       clk,
  input  wire                       reset_n,

  // Memory-mapped interface
  input  wire                       req_valid,
  input  wire [31:0]                req_addr,
  input  wire [31:0]                req_wdata,
  input  wire                       req_we,
  output reg                        req_ready,
  output reg  [31:0]                req_rdata,

  // Interrupt sources
  input  wire [NUM_SOURCES-1:0]     irq_sources,

  // Interrupt outputs to harts
  output wire [NUM_HARTS-1:0]       mei_o,  // M-mode external interrupt
  output wire [NUM_HARTS-1:0]       sei_o   // S-mode external interrupt
);
```

#### Claim/Complete Protocol
1. **Interrupt assertion**: PLIC sets MEI/SEI based on pending & enabled & priority
2. **Claim**: Hart reads claim register, PLIC returns highest-priority pending IRQ ID
3. **Service**: Hart handles interrupt
4. **Complete**: Hart writes IRQ ID to complete register, PLIC clears pending

#### Testing
1. **Unit test**: Verify priority arbitration
2. **Multiple sources**: Trigger 3 IRQs, verify highest priority claimed
3. **Threshold**: Set threshold=5, verify only priority>5 interrupts fire

### 4.2: Block Storage

#### Option 1: RAM Disk (Initial Bringup)
**File**: `rtl/peripherals/ramdisk.v`

Simple memory region acting as block device:
```
0x8800_0000 - 0x88FF_FFFF: 16MB RAM disk
```

**Interface**: Memory-mapped, synchronous read/write
```verilog
module ramdisk #(
  parameter SIZE = 16777216  // 16MB
) (
  input  wire        clk,
  input  wire        req_valid,
  input  wire [31:0] req_addr,     // Byte address within disk
  input  wire [63:0] req_wdata,
  input  wire        req_we,
  input  wire [2:0]  req_size,
  output reg         req_ready,
  output reg  [63:0] req_rdata
);
```

**Pros**:
- ✅ Simple (50 lines of Verilog)
- ✅ Fast (single-cycle access)
- ✅ Easy to debug

**Cons**:
- ❌ Lost on reset (no persistence)
- ❌ Not realistic

#### Option 2: SD Card SPI Controller (Later)
**File**: `rtl/peripherals/sd_spi.v`

SPI-based SD card interface:
- Command/response protocol
- Block read/write (512 bytes)
- Initialization sequence

**Registers** (Memory-mapped 0x9200_0000):
```
0x00: Command register
0x04: Argument register
0x08: Status register
0x0C: Data buffer (512 bytes)
```

**Pros**:
- ✅ Persistent storage
- ✅ Industry standard
- ✅ Realistic

**Cons**:
- ❌ Complex (500-800 lines)
- ❌ Slower (SPI clock, multi-cycle ops)

**Decision**: Start with RAM disk, migrate to SD later if needed.

### 4.3: OpenSBI Firmware

#### Purpose
M-mode firmware providing Supervisor Binary Interface (SBI) to S-mode OS:
- Timer services (set timer, get time)
- IPI services (send IPI to hart)
- Console services (putchar, getchar)
- System reset/shutdown

#### Build Process
```bash
cd software/opensbi
git clone https://github.com/riscv/opensbi.git
cd opensbi

# Create platform definition
mkdir -p platform/rv1
cat > platform/rv1/config.mk <<EOF
PLATFORM_RISCV_XLEN = 64
PLATFORM_RISCV_ABI = lp64d
PLATFORM_RISCV_ISA = rv64imafdc
FW_TEXT_START = 0x80000000
FW_PAYLOAD_OFFSET = 0x200000
FW_PAYLOAD_ALIGN = 0x1000
EOF

cat > platform/rv1/platform.c <<EOF
#include <sbi/sbi_platform.h>

// CLINT addresses
#define RV1_CLINT_ADDR 0x2000000
#define RV1_CLINT_SIZE 0x10000

// UART addresses
#define RV1_UART_ADDR 0x10000000

const struct sbi_platform_operations platform_ops = {
  .early_init = rv1_early_init,
  .console_putc = rv1_console_putc,
  .console_getc = rv1_console_getc,
  .timer_init = rv1_timer_init,
  // ...
};

const struct sbi_platform platform = {
  .name = "RV1 RISC-V",
  .features = SBI_PLATFORM_HAS_TIMER_VALUE,
  .hart_count = 1,
  .platform_ops_addr = (unsigned long)&platform_ops,
};
EOF

# Build
make PLATFORM=rv1 FW_PAYLOAD_PATH=../xv6-riscv/kernel
```

**Output**: `build/platform/rv1/firmware/fw_payload.elf`
- Contains OpenSBI + xv6 kernel
- Load at 0x8000_0000
- Kernel starts at 0x8020_0000

#### SBI Call Interface
OS makes SBI calls via `ecall` from S-mode:
```c
// xv6 example: get time
uint64_t r_time() {
  uint64_t time;
  asm volatile("rdtime %0" : "=r"(time));
  return time;
}

// Set timer (SBI call)
void sbi_set_timer(uint64_t stime_value) {
  register uint64_t a0 asm("a0") = stime_value;
  register uint64_t a7 asm("a7") = 0;  // SBI_SET_TIMER
  asm volatile("ecall" : : "r"(a0), "r"(a7));
}
```

### 4.4: xv6 Port

#### Clone & Build
```bash
cd software/
git clone https://github.com/mit-pdos/xv6-riscv.git
cd xv6-riscv

# Build
make TOOLPREFIX=riscv64-unknown-elf-
```

**Output**: `kernel` ELF file

#### Kernel Modifications

**Console Driver**: `kernel/console.c`, `kernel/uart.c`
```c
// Change UART base address
#define UART0 0x10000000  // Our address (was 0x10000000 - same!)

// Initialize UART
void uartinit(void) {
  // Disable interrupts
  WriteReg(IER, 0x00);

  // Enable FIFO, clear, 14-byte threshold
  WriteReg(FCR, 0x07);

  // 8 bits, no parity, 1 stop bit
  WriteReg(LCR, 0x03);

  // Enable receive interrupt
  WriteReg(IER, 0x01);
}
```

**Block Device**: `kernel/virtio_disk.c`
Modify to use our RAM disk instead of VirtIO:
```c
// Simple RAM disk interface
#define RAMDISK_BASE 0x88000000
#define BLOCK_SIZE 512

void disk_read(uint32_t blockno, void *dst) {
  uint64_t addr = RAMDISK_BASE + blockno * BLOCK_SIZE;
  memmove(dst, (void*)addr, BLOCK_SIZE);
}

void disk_write(uint32_t blockno, void *src) {
  uint64_t addr = RAMDISK_BASE + blockno * BLOCK_SIZE;
  memmove((void*)addr, src, BLOCK_SIZE);
}
```

**Memory Layout**: `kernel/memlayout.h`
```c
// Kernel loads at 0x80200000 (after OpenSBI)
#define KERNBASE 0x80200000

// Physical RAM layout
// 0x80000000 -- OpenSBI (2MB)
// 0x80200000 -- kernel text/data (up to ~1MB)
// 0x80400000 -- kernel page tables
// 0x80500000 -- end of kernel
// 0x88000000 -- RAM disk (16MB)
```

#### Makefile Modifications
**File**: `software/xv6-riscv/Makefile`

Change load address:
```makefile
LDFLAGS = -z max-page-size=4096 -T kernel.ld
```

**File**: `kernel/kernel.ld`
```ld
OUTPUT_ARCH( "riscv" )
ENTRY( _entry )

SECTIONS
{
  . = 0x80200000;  /* Kernel starts after OpenSBI */

  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) }

  PROVIDE(end = .);
}
```

### 4.5: Boot & Debugging

#### Load Firmware
```bash
# Convert to hex
riscv64-unknown-elf-objcopy -O verilog fw_payload.elf firmware.hex

# Load in testbench
iverilog -g2012 -DMEM_FILE="firmware.hex" -I rtl/ -o sim/test_xv6.vvp \
  rtl/rv_soc.v tb/integration/tb_soc.v

vvp sim/test_xv6.vvp
```

#### Expected Boot Sequence
```
OpenSBI v1.3
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name : RV1 RISC-V
Platform HART Features : RV64ACDFIMSU
Firmware Base : 0x80000000
Firmware Size : 132 KB

Boot HART ID : 0
Boot Status : SUCCESS

xv6 kernel is booting

hart 1 starting
hart 2 starting
init: starting sh
$
```

#### Debug Checklist
- [ ] OpenSBI banner appears → UART working
- [ ] "xv6 kernel is booting" → Kernel loaded correctly
- [ ] No trap loops → Exception handling works
- [ ] Shell prompt `$` → Init process started
- [ ] Can type commands → Console input works

### 4.6: xv6 Test Suite

#### Run User Tests
```bash
$ usertests
usertests starting
test reparent: OK
test twochildren: OK
test forkfork: OK
test forkforkfork: OK
test mem: OK
test filetest: OK
test bigwrite: OK
test fourfiles: OK
test createdelete: OK
...
ALL TESTS PASSED
```

**If tests fail**:
1. Check specific test (`usertests <testname>`)
2. Add debug prints in kernel
3. Check waveforms for trap/exception
4. Verify page tables correct

#### Test Shell Commands
```bash
$ ls
.              1 1 1024
..             1 1 1024
README         2 2 2226
cat            2 3 32840
echo           2 4 31768
...

$ cat README
xv6 is a re-implementation of Dennis Ritchie's and Ken Thompson's Unix
Version 6 (v6).  xv6 loosely follows the structure and style of v6,
but is implemented for a modern RISC-V multiprocessor using ANSI C.
...

$ echo hello world
hello world

$ grep x README
xv6 is a re-implementation...

$ wc README
45 268 2226 README
```

---

## Phase 5a: Linux nommu (Optional)

**Duration**: 3-4 weeks
**Status**: ⏭️ Pending (Optional)

### Overview
Linux without MMU support - runs on RV32 with no virtual memory translation. Suitable for embedded/microcontroller use cases.

### Key Differences vs MMU Linux
- No page tables, no virtual memory
- Physical = virtual addresses
- `mmap()` doesn't work (or limited)
- No `fork()` - use `vfork()` instead
- Static memory allocation
- Simpler, smaller kernel

### Kernel Configuration
```bash
cd software/linux
git clone --depth=1 --branch=v6.6 https://github.com/torvalds/linux.git
cd linux

# Configure
make ARCH=riscv CROSS_COMPILE=riscv32-unknown-linux-gnu- tinyconfig

# Enable nommu
scripts/config -d CONFIG_MMU
scripts/config -e CONFIG_BINFMT_FLAT
scripts/config -e CONFIG_SERIAL_8250
scripts/config -e CONFIG_SERIAL_8250_CONSOLE

# Build
make ARCH=riscv CROSS_COMPILE=riscv32-unknown-linux-gnu- -j8
```

**Output**: `arch/riscv/boot/Image` (kernel binary)

### Rootfs (Buildroot)
```bash
cd software/buildroot
git clone https://github.com/buildroot/buildroot.git
cd buildroot

make qemu_riscv32_nommu_virt_defconfig

# Customize
make menuconfig
# Target: RISC-V 32-bit
# Toolchain: External (riscv32-unknown-linux-gnu)
# System: Init system = BusyBox
# Filesystem: cpio archive for initramfs

make -j8
```

**Output**: `output/images/rootfs.cpio` (initramfs)

### Boot
Embed initramfs in kernel:
```bash
scripts/config -e CONFIG_INITRAMFS_SOURCE
scripts/config --set-str CONFIG_INITRAMFS_SOURCE "../buildroot/output/images/rootfs.cpio"
make ARCH=riscv CROSS_COMPILE=riscv32-unknown-linux-gnu- -j8
```

Load `Image` at 0x8000_0000, start execution.

### Validation
- [ ] Boot messages appear
- [ ] "Run /init as init process" → initramfs mounted
- [ ] Login prompt (if configured) or shell
- [ ] Commands work: `ls`, `cat`, `echo`, `ps`
- [ ] No memory faults (check dmesg)

---

## Phase 5b: Linux with MMU

**Duration**: 4-6 weeks
**Status**: ⏭️ Pending

### 5b.1: Kernel Build (RV64)

```bash
cd software/linux
# (already cloned from Phase 5a)

make ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- defconfig

# Customize
scripts/config -e CONFIG_RISCV_ISA_C  # Compressed instructions
scripts/config -e CONFIG_RISCV_ISA_A  # Atomics
scripts/config -e CONFIG_FPU          # Floating-point
scripts/config -e CONFIG_SERIAL_8250
scripts/config -e CONFIG_SERIAL_8250_CONSOLE
scripts/config -e CONFIG_EXT2_FS      # Filesystem support
scripts/config -e CONFIG_BLK_DEV_RAM  # RAM disk
scripts/config -d CONFIG_MODULES      # Disable modules for simplicity

make ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- -j8
```

**Output**: `arch/riscv/boot/Image` (~10MB kernel binary)

### 5b.2: Device Tree

**File**: `software/device-tree/rv1.dts`

```dts
/dts-v1/;

/ {
    #address-cells = <2>;
    #size-cells = <2>;
    compatible = "rv1,rv1-soc";
    model = "RV1 RISC-V SoC";

    chosen {
        bootargs = "console=ttyS0,115200 earlycon=uart8250,mmio,0x10000000";
        stdout-path = "serial0:115200n8";
    };

    cpus {
        #address-cells = <1>;
        #size-cells = <0>;
        timebase-frequency = <10000000>;  // 10MHz

        cpu0: cpu@0 {
            device_type = "cpu";
            reg = <0>;
            status = "okay";
            compatible = "riscv";
            riscv,isa = "rv64imafdc";
            mmu-type = "riscv,sv39";

            cpu0_intc: interrupt-controller {
                #interrupt-cells = <1>;
                interrupt-controller;
                compatible = "riscv,cpu-intc";
            };
        };
    };

    memory@80000000 {
        device_type = "memory";
        reg = <0x0 0x80000000 0x0 0x5000000>;  // 80MB RAM
    };

    soc {
        #address-cells = <2>;
        #size-cells = <2>;
        compatible = "simple-bus";
        ranges;

        clint@2000000 {
            compatible = "riscv,clint0";
            interrupts-extended = <&cpu0_intc 3 &cpu0_intc 7>;
            reg = <0x0 0x2000000 0x0 0x10000>;
        };

        plic@c000000 {
            compatible = "riscv,plic0";
            interrupts-extended = <&cpu0_intc 11 &cpu0_intc 9>;
            reg = <0x0 0xc000000 0x0 0x4000000>;
            riscv,ndev = <32>;
            interrupt-controller;
            #interrupt-cells = <1>;
        };

        serial0: serial@10000000 {
            compatible = "ns16550a";
            reg = <0x0 0x10000000 0x0 0x1000>;
            interrupts = <10>;
            interrupt-parent = <&plic>;
            clock-frequency = <50000000>;
            reg-shift = <0>;
            reg-io-width = <1>;
        };

        ramdisk@88000000 {
            compatible = "mtd-ram";
            reg = <0x0 0x88000000 0x0 0x1000000>;  // 16MB
            bank-width = <8>;
            label = "ramdisk";
        };
    };
};
```

**Compile**:
```bash
dtc -I dts -O dtb -o rv1.dtb rv1.dts
```

### 5b.3: Rootfs (Buildroot)

```bash
cd software/buildroot/buildroot

make qemu_riscv64_virt_defconfig

make menuconfig
# Filesystem: ext2 root filesystem
# Size: 64MB
# Compression: none

make -j8
```

**Output**: `output/images/rootfs.ext2` (64MB filesystem image)

**Install to RAM disk**:
```bash
# Convert to hex (for loading into simulation)
dd if=rootfs.ext2 of=rootfs.bin bs=4096
xxd -p -c 4 rootfs.bin > rootfs.hex
```

### 5b.4: U-Boot Bootloader

#### Build U-Boot
```bash
cd software/u-boot
git clone https://github.com/u-boot/u-boot.git
cd u-boot

make qemu-riscv64_smode_defconfig

# Customize for RV1
# (Set UART base, memory map, etc. in configs/qemu-riscv64_smode_defconfig)

make CROSS_COMPILE=riscv64-unknown-linux-gnu- -j8
```

**Output**: `u-boot.bin` (bootloader binary)

#### U-Boot Boot Script
**File**: `boot.cmd`
```bash
# U-Boot boot script for RV1
echo "RV1 U-Boot: Loading Linux..."

# Load kernel to 0x84000000
load ram 0x88000000 0x84000000 ${filesize}

# Load device tree to 0x82000000
load ram 0x88100000 0x82000000 ${fdtsize}

# Boot kernel
booti 0x84000000 - 0x82000000
```

Compile:
```bash
mkimage -C none -A riscv -T script -d boot.cmd boot.scr
```

### 5b.5: Complete Boot Flow

#### Memory Layout
```
0x8000_0000 - 0x8020_0000: OpenSBI (2MB)
0x8020_0000 - 0x8040_0000: U-Boot (2MB)
0x8040_0000 - 0x8100_0000: Linux kernel (12MB)
0x8200_0000 - 0x8220_0000: Device tree (2MB)
0x8800_0000 - 0x8900_0000: RAM disk / rootfs (16MB)
```

#### Combined Firmware Image
```bash
# Create combined image
cat opensbi/fw_dynamic.bin > firmware.bin
dd if=u-boot/u-boot.bin of=firmware.bin bs=1M seek=2 conv=notrunc
dd if=linux/arch/riscv/boot/Image of=firmware.bin bs=1M seek=4 conv=notrunc
dd if=device-tree/rv1.dtb of=firmware.bin bs=1M seek=16 conv=notrunc
dd if=buildroot/output/images/rootfs.ext2 of=firmware.bin bs=1M seek=18 conv=notrunc

# Convert to hex for simulation
riscv64-unknown-elf-objcopy -I binary -O verilog firmware.bin firmware.hex
```

#### Boot Sequence
1. **Core reset**: PC = 0x8000_0000
2. **OpenSBI** (M-mode):
   - Print banner
   - Initialize CLINT, PLIC
   - Set trap delegation (`medeleg`, `mideleg`)
   - Set `mstatus.MPP = S-mode`
   - Set `mepc = 0x8020_0000` (U-Boot)
   - Execute `mret` → jump to U-Boot in S-mode
3. **U-Boot** (S-mode):
   - Initialize devices (UART, RAM disk)
   - Load kernel from 0x8040_0000 to memory
   - Load DTB from 0x8200_0000
   - Prepare boot arguments
   - Jump to kernel: `booti 0x8040_0000 - 0x8200_0000`
4. **Linux Kernel** (S-mode):
   - Early init (parse DTB, setup MM)
   - Driver probe (UART, PLIC, block device)
   - Mount rootfs (ext2 from RAM disk)
   - Start init (`/sbin/init` or `/init`)
5. **User Space**:
   - Init runs startup scripts
   - Spawn getty on console
   - Login prompt appears

### 5b.6: Debugging Linux Boot

#### Enable Early Debug
Add to kernel cmdline (in device tree `bootargs`):
```
earlyprintk=uart8250,mmio,0x10000000,115200 loglevel=8
```

#### Common Issues & Solutions

**Issue**: Kernel doesn't boot, no output
- Check UART initialized correctly
- Verify `stdout-path` in device tree
- Check PC actually reaches kernel entry

**Issue**: "Unable to mount root fs"
- Verify rootfs format (ext2, ext4, etc.)
- Check kernel has filesystem support compiled in
- Verify RAM disk address in memory map

**Issue**: Kernel panic "Attempted to kill init"
- Check init binary exists in rootfs (`/sbin/init` or `/init`)
- Verify init has execute permission
- Check library dependencies (use static busybox)

**Issue**: Hangs at "Run /init as init process"
- Init is running but no output → check UART
- Init crashed → add debug prints in init script
- Wrong init path → set `init=` in bootargs

#### Debug Tools
1. **Waveform analysis**: Check PC, exception signals
2. **UART log**: Add `printk()` in kernel drivers
3. **dmesg**: Once booted, `dmesg` shows boot log
4. **GDB**: Attach `riscv64-unknown-elf-gdb` to simulation

### 5b.7: Post-Boot Testing

#### Basic Validation
```bash
# Check kernel version
$ uname -a
Linux rv1 6.6.0 #1 SMP Thu Oct 26 12:00:00 UTC 2025 riscv64 GNU/Linux

# Check memory
$ free -m
              total        used        free      shared  buff/cache   available
Mem:             76          12          60           0           4          62
Swap:             0           0           0

# Check processes
$ ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.3   2156  1024 ?        Ss   00:00   0:00 /sbin/init
root        12  0.0  0.2   2088   960 ttyS0    Ss   00:00   0:00 /bin/login
...

# Check filesystem
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/ram0        64M   12M   48M  20% /
```

#### Stress Testing
```bash
# CPU stress
$ yes > /dev/null &
$ yes > /dev/null &
$ yes > /dev/null &
$ yes > /dev/null &

# Memory stress
$ stress-ng --vm 2 --vm-bytes 32M --timeout 60s

# I/O stress
$ dd if=/dev/zero of=/tmp/testfile bs=1M count=10
```

#### Networking (If Ethernet Added)
```bash
# Configure interface
$ ifconfig eth0 192.168.1.100 netmask 255.255.255.0 up

# Test connectivity
$ ping 192.168.1.1

# Run HTTP server
$ busybox httpd -p 8080 -h /var/www/
```

---

## Success Criteria

### Phase 1: Interrupt Infrastructure ✅
- [ ] CLINT: Timer increments, compare triggers MTI
- [ ] UART: Characters transmit and receive correctly
- [ ] SoC: All devices addressable via memory map
- [ ] Tests: 34/34 privilege tests passing (100%)
- [ ] Regression: All 208 tests still passing (no regressions)

### Phase 2: FreeRTOS ✅
- [ ] Boot: "FreeRTOS v10.x.x" banner prints
- [ ] Multitasking: 2+ tasks run concurrently, interleaved output
- [ ] Timing: `vTaskDelay()` delays accurate (±1ms)
- [ ] IPC: Queue send/receive works without corruption
- [ ] Semaphores: Binary and counting semaphores work
- [ ] Stability: Runs for 1+ hours without hang or corruption

### Phase 3: RV64 Upgrade ✅
- [ ] RV64I: 48/48 tests passing
- [ ] RV64M: 8/8 tests passing
- [ ] RV64AFDC: 31/31 tests passing (F+D+C)
- [ ] Total: 87/87 RV64 tests passing (100%)
- [ ] MMU: Sv39 page table walks successful
- [ ] TLB: 3-level translations cached correctly
- [ ] Regression: FreeRTOS still works on RV64

### Phase 4: xv6 ✅
- [ ] OpenSBI: Banner prints, firmware version displayed
- [ ] xv6 Boot: "xv6 kernel is booting" appears
- [ ] Shell: Prompt `$ ` appears, can type commands
- [ ] Commands: `ls`, `cat`, `echo`, `grep`, `wc` work correctly
- [ ] Programs: Can run compiled C programs
- [ ] Tests: `usertests` passes all tests (20+)
- [ ] Filesystem: Can create, read, write, delete files
- [ ] Processes: `fork`, `exec`, `wait`, `exit` work
- [ ] Stability: System runs stably, no spontaneous crashes

### Phase 5a: Linux nommu (Optional) ✅
- [ ] Boot: Boot messages appear, no kernel panic
- [ ] Mount: "Run /init as init process" → initramfs mounted
- [ ] Shell: BusyBox shell prompt appears
- [ ] Commands: Basic commands work (`ls`, `cat`, `ps`, `free`)
- [ ] Processes: Can run programs, process isolation works
- [ ] dmesg: No critical errors in kernel log

### Phase 5b: Linux with MMU ✅
- [ ] OpenSBI: Banner, boot to U-Boot
- [ ] U-Boot: Loads kernel+DTB, boots Linux
- [ ] Kernel Boot: Boot messages, driver probes successful
- [ ] Rootfs Mount: ext2 filesystem mounted from RAM disk
- [ ] Init: Init process starts, getty spawned
- [ ] Login: Login prompt or shell appears
- [ ] Functionality: All basic commands work
- [ ] Processes: Multi-process workloads stable
- [ ] Memory: Virtual memory management works (page faults, swapping if enabled)
- [ ] Filesystem: Persistent read/write to RAM disk
- [ ] Networking (optional): ping, wget work if Ethernet added
- [ ] Stress: Passes stress tests (CPU, memory, I/O) without crash
- [ ] Uptime: Runs for extended period (hours/days) without issues

---

## References

### RISC-V Specifications
- **ISA Manual**: https://riscv.org/technical/specifications/
- **Privileged Spec**: https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf
- **SBI Spec**: https://github.com/riscv-non-isa/riscv-sbi-doc

### Software Projects
- **FreeRTOS**: https://github.com/FreeRTOS/FreeRTOS-Kernel
- **xv6-riscv**: https://github.com/mit-pdos/xv6-riscv
- **OpenSBI**: https://github.com/riscv/opensbi
- **U-Boot**: https://github.com/u-boot/u-boot
- **Linux**: https://github.com/torvalds/linux
- **Buildroot**: https://github.com/buildroot/buildroot

### Example Implementations
- **QEMU virt machine**: Good reference for memory map, device tree
- **SiFive E/U series**: Real hardware examples
- **LiteX**: Open-source SoC builder with RISC-V support

### Books & Courses
- **"Computer Organization and Design: RISC-V Edition"** - Patterson & Hennessy
- **"The RISC-V Reader"** - Patterson & Waterman
- **MIT 6.S081** (Operating System Engineering) - Uses xv6-riscv
- **"xv6: a simple, Unix-like teaching operating system"** - MIT PDOS

### Debugging Resources
- **RISC-V Debug Spec**: https://github.com/riscv/riscv-debug-spec
- **OpenOCD for RISC-V**: https://github.com/riscv/riscv-openocd
- **GDB RISC-V**: Part of official GNU toolchain

---

## Change Log

| Date | Phase | Milestone | Notes |
|------|-------|-----------|-------|
| 2025-10-26 | Phase 0 | 100% ISA compliance | All 81 official tests + 127 custom tests passing |
| 2025-10-26 | Phase 1 | Planning | Documentation created, directory structure initialized |

---

## Next Actions

### Immediate (This Week)
1. ✅ Create directory structure
2. ✅ Write this documentation
3. 🚧 Write MEMORY_MAP.md
4. ⏭️ Implement CLINT module
5. ⏭️ Create CLINT testbench

### Short-Term (Next 2 Weeks)
- Complete Phase 1 (CLINT + UART + SoC integration)
- Write and pass 6 interrupt tests
- Validate 34/34 privilege tests passing

### Medium-Term (Next 1-2 Months)
- Port and validate FreeRTOS (Phase 2)
- Upgrade to RV64 (Phase 3)
- Begin xv6 integration (Phase 4)

### Long-Term (Next 3-6 Months)
- Complete xv6 testing
- Optionally implement Linux nommu (Phase 5a)
- Full Linux with MMU (Phase 5b)
- Stretch: Add networking, additional peripherals

---

**Status**: 🚀 Phase 1 In Progress - Let's build an OS!
