# RV1 SoC Memory Map

**Project**: RV1 RISC-V Processor
**Created**: 2025-10-26
**Status**: Phase 1 Implementation

---

## Overview

This document defines the memory map for the RV1 SoC, including RAM, peripherals, and memory-mapped devices. The map is designed for compatibility with standard RISC-V conventions (QEMU virt machine) where possible.

---

## Memory Map Summary

### Current (Phase 1)

| Address Range | Size | Device | Access | Description |
|--------------|------|--------|--------|-------------|
| `0x0000_0000` - `0x0000_FFFF` | 64KB | Instruction RAM | R-X | Program code (Harvard architecture) |
| `0x0200_0000` - `0x0200_FFFF` | 64KB | CLINT | RW | Core-Local Interruptor (timer + software IRQ) |
| `0x1000_0000` - `0x1000_0FFF` | 4KB | UART0 | RW | 16550-compatible serial console |
| `0x8000_0000` - `0x8000_FFFF` | 64KB | Data RAM | RW | Data memory (Harvard architecture) |

**Total Address Space Used**: ~192KB

---

### Future (Phase 3+)

| Address Range | Size | Device | Access | Description |
|--------------|------|--------|--------|-------------|
| `0x0000_0000` - `0x0000_FFFF` | 64KB | Boot ROM | R-X | Optional: bootloader code |
| `0x0200_0000` - `0x0200_FFFF` | 64KB | CLINT | RW | Timer + software interrupts |
| `0x0C00_0000` - `0x0FFF_FFFF` | 64MB | PLIC | RW | Platform-Level Interrupt Controller |
| `0x1000_0000` - `0x1000_0FFF` | 4KB | UART0 | RW | Console serial port |
| `0x8000_0000` - `0x8050_0000` | 5MB | System RAM | RWX | Unified memory (code + data) |
| `0x8800_0000` - `0x88FF_FFFF` | 16MB | RAM Disk / Block Device | RW | Block storage |
| `0x9000_0000` - `0x9000_0FFF` | 4KB | Ethernet MAC | RW | Optional: Network interface |
| `0x9100_0000` - `0x9100_0FFF` | 4KB | GPIO | RW | Optional: General-purpose I/O |

**Total Address Space Used**: ~85MB

---

## Detailed Device Maps

### CLINT (Core-Local Interruptor)
**Base Address**: `0x0200_0000`
**Size**: 64KB
**Standard**: RISC-V CLINT specification (compatible with QEMU, SiFive)

#### Register Map

| Offset | Size | Name | Access | Description |
|--------|------|------|--------|-------------|
| `0x0000` | 4B | MSIP (hart 0) | RW | Machine Software Interrupt Pending |
| `0x0004` | 4B | MSIP (hart 1) | RW | (Future: multi-hart) |
| ... | | | | (Up to 4095 harts at 4B each) |
| `0x4000` | 8B | MTIMECMP (hart 0) | RW | Machine Timer Compare (lower 32b at +0, upper 32b at +4) |
| `0x4008` | 8B | MTIMECMP (hart 1) | RW | (Future: multi-hart) |
| ... | | | | (Up to 4095 harts at 8B each) |
| `0xBFF8` | 8B | MTIME | RW | Machine Time Counter (64-bit, little-endian) |

#### Details

**MSIP (Machine Software Interrupt Pending)**:
- **Address**: `0x0200_0000` (hart 0)
- **Bit 0**: Software interrupt pending (write 1 to trigger, write 0 to clear)
- **Bits 31:1**: Reserved (read as 0)
- **Purpose**: Inter-processor interrupts (IPI) or software-triggered interrupts

**MTIMECMP (Machine Timer Compare)**:
- **Address**: `0x0200_4000` (hart 0)
- **64-bit value**: Comparison value for timer interrupt
- **Behavior**: When `MTIME >= MTIMECMP`, timer interrupt (`mip[7]`) is asserted
- **Clear**: Write new value to MTIMECMP (or clear `mip[7]` via CSR if supported)

**MTIME (Machine Time Counter)**:
- **Address**: `0x0200_BFF8`
- **64-bit counter**: Increments every clock cycle
- **Read**: Can read current time (useful for timestamps, delays)
- **Write**: Can write to set time (typically only M-mode does this at boot)

#### Usage Example (Assembly)
```assembly
# Set up timer interrupt for 1000 cycles from now
li t0, 0x0200BFF8        # MTIME address
ld t1, 0(t0)             # Read current MTIME
addi t1, t1, 1000        # Add 1000 cycles

li t0, 0x02004000        # MTIMECMP address
sd t1, 0(t0)             # Write MTIMECMP

# Enable timer interrupt
li t0, 0x80              # MIE.MTIE bit (bit 7)
csrs mie, t0             # Set mie[7]

li t0, 0x08              # MSTATUS.MIE bit (bit 3)
csrs mstatus, t0         # Enable global interrupts

# Wait for interrupt
1: j 1b
```

---

### UART (16550-Compatible)
**Base Address**: `0x1000_0000`
**Size**: 4KB (only first 8 bytes used)
**Standard**: 16550 UART subset (industry standard)

#### Register Map

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | RBR / THR | R / W | Receive Buffer Register (read) / Transmit Holding Register (write) |
| `0x01` | IER | RW | Interrupt Enable Register |
| `0x02` | IIR / FCR | R / W | Interrupt Identification Register (read) / FIFO Control Register (write) |
| `0x03` | LCR | RW | Line Control Register |
| `0x04` | MCR | RW | Modem Control Register |
| `0x05` | LSR | R | Line Status Register |
| `0x06` | MSR | R | Modem Status Register |
| `0x07` | SCR | RW | Scratch Register |

#### Key Registers

**THR (Transmit Holding Register)** - Offset `0x00` (Write):
- **Bits 7:0**: Character to transmit
- **Write**: Place character here, UART will shift it out serially
- **Check LSR[5] (THRE) before writing** to ensure buffer is empty

**RBR (Receive Buffer Register)** - Offset `0x00` (Read):
- **Bits 7:0**: Received character
- **Read**: Get character from receive FIFO
- **Check LSR[0] (DR) before reading** to ensure data is available

**IER (Interrupt Enable Register)** - Offset `0x01`:
- **Bit 0**: Enable "Received Data Available" interrupt
- **Bit 1**: Enable "Transmit Holding Register Empty" interrupt
- **Bit 2**: Enable "Receiver Line Status" interrupt
- **Bit 3**: Enable "Modem Status" interrupt
- **Bits 7:4**: Reserved

**LSR (Line Status Register)** - Offset `0x05` (Read-only):
- **Bit 0 (DR)**: Data Ready - RX data available in RBR
- **Bit 1 (OE)**: Overrun Error
- **Bit 2 (PE)**: Parity Error
- **Bit 3 (FE)**: Framing Error
- **Bit 4 (BI)**: Break Interrupt
- **Bit 5 (THRE)**: Transmit Holding Register Empty - can write to THR
- **Bit 6 (TEMT)**: Transmitter Empty - all data transmitted
- **Bit 7**: Error in RX FIFO

**LCR (Line Control Register)** - Offset `0x03`:
- **Bits 1:0**: Word length (11 = 8 bits)
- **Bit 2**: Stop bits (0 = 1 stop bit, 1 = 2 stop bits)
- **Bit 3**: Parity enable
- **Bits 5:4**: Parity select
- **Bit 6**: Break control
- **Bit 7**: Divisor Latch Access Bit (DLAB) - for baud rate setting

**FCR (FIFO Control Register)** - Offset `0x02` (Write-only):
- **Bit 0**: FIFO Enable
- **Bit 1**: Clear RX FIFO
- **Bit 2**: Clear TX FIFO
- **Bits 7:6**: RX FIFO trigger level

#### Configuration
- **Baud Rate**: 115200 (standard, fixed in hardware for simplicity)
- **Data Format**: 8N1 (8 data bits, no parity, 1 stop bit)
- **FIFO**: 16 bytes (optional - can implement 1-byte initially)

#### Usage Example (C)
```c
#define UART_BASE 0x10000000
#define UART_THR  (*(volatile uint8_t*)(UART_BASE + 0))
#define UART_RBR  (*(volatile uint8_t*)(UART_BASE + 0))
#define UART_IER  (*(volatile uint8_t*)(UART_BASE + 1))
#define UART_LSR  (*(volatile uint8_t*)(UART_BASE + 5))

void uart_putc(char c) {
  // Wait for THR to be empty
  while ((UART_LSR & 0x20) == 0);
  UART_THR = c;
}

char uart_getc(void) {
  // Wait for data to be available
  while ((UART_LSR & 0x01) == 0);
  return UART_RBR;
}

void uart_init(void) {
  // Disable interrupts
  UART_IER = 0x00;

  // 8N1 mode
  volatile uint8_t *LCR = (volatile uint8_t*)(UART_BASE + 3);
  *LCR = 0x03;  // 8 bits, no parity, 1 stop
}
```

---

### PLIC (Platform-Level Interrupt Controller)
**Base Address**: `0x0C00_0000`
**Size**: 64MB
**Standard**: RISC-V PLIC specification (compatible with SiFive, QEMU)
**Status**: Phase 4+ (not yet implemented)

#### Register Map

| Offset Range | Name | Access | Description |
|--------------|------|--------|-------------|
| `0x000000 - 0x000FFF` | Interrupt Priorities | RW | Priority for each interrupt source (0-31) |
| `0x001000 - 0x001FFF` | Interrupt Pending | R | Pending bits for sources |
| `0x002000 - 0x00207F` | M-mode Hart 0 Interrupt Enables | RW | Enable mask for M-mode |
| `0x002080 - 0x0020FF` | S-mode Hart 0 Interrupt Enables | RW | Enable mask for S-mode |
| `0x200000 - 0x200003` | M-mode Hart 0 Priority Threshold | RW | Minimum priority for M-mode |
| `0x200004 - 0x200007` | M-mode Hart 0 Claim/Complete | RW | Claim interrupt (read) / Complete (write) |
| `0x201000 - 0x201003` | S-mode Hart 0 Priority Threshold | RW | Minimum priority for S-mode |
| `0x201004 - 0x201007` | S-mode Hart 0 Claim/Complete | RW | Claim interrupt (read) / Complete (write) |

#### Interrupt Sources

| ID | Source | Description |
|----|--------|-------------|
| 0 | (reserved) | No interrupt |
| 1-9 | Reserved | Future use |
| 10 | UART0 | Serial console interrupt |
| 11 | Block Device | Disk I/O complete |
| 12 | Ethernet | Network packet RX/TX |
| 13-31 | GPIO / Other | Expandable |

#### Usage Flow
1. **Configure**: Set priorities for each source, set threshold
2. **Enable**: Set enable bits for desired interrupts
3. **Wait**: Core receives external interrupt (MEI/SEI)
4. **Claim**: Read claim register → returns highest-priority pending IRQ ID
5. **Service**: Handle the interrupt
6. **Complete**: Write IRQ ID back to complete register

---

### System RAM
**Base Address**: `0x8000_0000`
**Size**: Varies by phase

#### Phase 1 (Current): Harvard Architecture
- **Instruction RAM**: `0x0000_0000 - 0x0000_FFFF` (64KB)
- **Data RAM**: `0x8000_0000 - 0x8000_FFFF` (64KB)
- **Separate**: Instructions and data in different memories

#### Phase 3+: Unified Memory (Von Neumann)
- **System RAM**: `0x8000_0000 - 0x8050_0000` (5MB)
- **Unified**: Code and data in same memory
- **Layout**:
  ```
  0x8000_0000: OpenSBI firmware (M-mode, 2MB)
  0x8020_0000: U-Boot or kernel start (2MB+)
  0x8040_0000: Kernel (xv6/Linux, up to 1MB)
  0x8100_0000: Free RAM for OS use
  ```

#### Access Characteristics
- **Read Latency**: 1 cycle
- **Write Latency**: 1 cycle
- **Width**: 64-bit (supports 8/16/32/64-bit accesses)
- **Alignment**: Supports unaligned access (in hardware)
- **Caching**: None (for now - direct mapped)

---

### Block Device / RAM Disk
**Base Address**: `0x8800_0000`
**Size**: 16MB
**Status**: Phase 4+ (not yet implemented)

#### Description
Simple memory-mapped block storage for filesystem. Can be RAM disk (volatile) or eventually SD card controller.

#### Access
- **Direct**: Memory-mapped, read/write like RAM
- **Block Size**: 512 bytes (standard disk sector)
- **Capacity**: 16MB = 32768 sectors

#### Usage (RAM Disk)
```c
#define RAMDISK_BASE 0x88000000
#define BLOCK_SIZE 512

void disk_read(uint32_t sector, void *buffer) {
  void *src = (void*)(RAMDISK_BASE + sector * BLOCK_SIZE);
  memcpy(buffer, src, BLOCK_SIZE);
}

void disk_write(uint32_t sector, const void *buffer) {
  void *dst = (void*)(RAMDISK_BASE + sector * BLOCK_SIZE);
  memcpy(dst, buffer, BLOCK_SIZE);
}
```

#### Future: SD Card SPI Controller
Replace simple RAM disk with SPI SD card controller:
- **Registers**: Command, status, data buffer (at 0x8800_0000)
- **Protocol**: SD card SPI mode (CMD/ACMD commands)
- **Transfer**: DMA or programmed I/O

---

### Ethernet MAC (Optional)
**Base Address**: `0x9000_0000`
**Size**: 4KB
**Status**: Phase 5+ (optional, not yet planned)

#### Description
Simplified Ethernet MAC for network connectivity.

#### Register Map (Placeholder)
| Offset | Name | Description |
|--------|------|-------------|
| `0x00` | Control | Enable, reset, interrupt enable |
| `0x04` | Status | Link up, RX/TX ready |
| `0x08` | MAC Address Low | Lower 32 bits of MAC |
| `0x0C` | MAC Address High | Upper 16 bits of MAC |
| `0x10` | RX Buffer | Received packet data |
| `0x14` | TX Buffer | Transmit packet data |

---

### GPIO (Optional)
**Base Address**: `0x9100_0000`
**Size**: 4KB
**Status**: Optional (simple addition)

#### Description
General-purpose I/O for LEDs, buttons, etc.

#### Register Map
| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | DATA | RW | Pin values (bit per pin) |
| `0x04` | DIRECTION | RW | 0=input, 1=output |
| `0x08` | INTERRUPT_ENABLE | RW | Enable interrupt on pin change |
| `0x0C` | INTERRUPT_STATUS | R/W1C | Interrupt pending (write 1 to clear) |

#### Usage Example
```c
#define GPIO_BASE 0x91000000
#define GPIO_DATA (*(volatile uint32_t*)(GPIO_BASE + 0x00))
#define GPIO_DIR  (*(volatile uint32_t*)(GPIO_BASE + 0x04))

void gpio_init(void) {
  GPIO_DIR = 0x0000000F;  // Pins 0-3 output, rest input
}

void led_set(int led_num, int state) {
  if (state)
    GPIO_DATA |= (1 << led_num);   // Set bit
  else
    GPIO_DATA &= ~(1 << led_num);  // Clear bit
}

int button_read(int btn_num) {
  return (GPIO_DATA >> btn_num) & 1;
}
```

---

## Address Decode Logic

The SoC uses a simple priority-based address decoder:

```verilog
always @(*) begin
  case (addr[31:28])
    4'h0: begin  // 0x0xxx_xxxx
      case (addr[27:16])
        12'h000: device = IMEM;    // 0x0000_xxxx
        12'h200: device = CLINT;   // 0x0200_xxxx
        default: device = NONE;
      endcase
    end
    4'h1: device = UART;           // 0x1xxx_xxxx
    4'h8: begin  // 0x8xxx_xxxx
      case (addr[27:24])
        4'h0: device = RAM;        // 0x8000_xxxx - 0x80FF_xxxx
        4'h8: device = BLOCK_DEV;  // 0x8800_xxxx
        default: device = NONE;
      endcase
    end
    4'h9: begin  // 0x9xxx_xxxx
      case (addr[27:20])
        8'h00: device = ETHERNET;  // 0x9000_xxxx
        8'h10: device = GPIO;      // 0x9100_xxxx
        default: device = NONE;
      endcase
    end
    4'hC: device = PLIC;           // 0x0Cxx_xxxx - 0x0Fxx_xxxx
    default: device = NONE;
  endcase
end
```

---

## Memory Access Permissions

### M-Mode (Machine)
- **Full access**: All memory regions, all devices
- **No restrictions**: Can access everything

### S-Mode (Supervisor)
- **CLINT**: Only MTIME readable (MTIMECMP/MSIP are M-mode only)
- **UART, PLIC, Block, Network, GPIO**: Full access
- **RAM**: Access via MMU (virtual addresses), PMP can restrict
- **Note**: S-mode uses SBI calls to OpenSBI for timer/IPI functions

### U-Mode (User)
- **Direct device access**: None (will trap)
- **RAM**: Access via MMU only (user pages)
- **Devices**: Must use syscalls to S-mode or M-mode

### Physical Memory Protection (PMP)
Not yet implemented, but planned:
- M-mode can configure PMP registers to restrict S/U-mode access
- Example: Prevent S-mode from accessing CLINT MTIMECMP

---

## Future Expansions

### Phase 6: Additional Peripherals
- **SPI Master**: For SD card, sensors
- **I2C Master**: For EEPROM, RTC, sensors
- **PWM**: For motor control, audio
- **ADC/DAC**: Analog I/O

### Phase 7: Performance Features
- **Instruction Cache**: 4KB-16KB, direct-mapped
- **Data Cache**: 4KB-16KB, write-back
- **AXI Bus**: Replace simple bus with AXI4 for bandwidth

### Phase 8: Multicore
- **Hart 1-3**: Add 3 more cores at 0x8100_0000+
- **CLINT**: Expand to 4 harts (MSIP/MTIMECMP arrays)
- **PLIC**: 4 harts × 2 modes = 8 contexts

---

## Compatibility Notes

### QEMU Virt Machine Compatibility
This memory map is designed to match QEMU's `virt` machine where possible:
- ✅ **CLINT**: Same addresses (0x0200_0000)
- ✅ **UART**: Same address (0x1000_0000)
- ✅ **PLIC**: Same address (0x0C00_0000)
- ⚠️ **RAM**: QEMU uses 0x8000_0000 (same base, different size)
- ⚠️ **VirtIO**: QEMU has VirtIO devices at 0x1000_1000+ (we don't)

**Benefit**: Device tree, Linux drivers, OpenSBI can largely be reused from QEMU.

### SiFive Compatibility
Similar to SiFive E/U series:
- ✅ CLINT standard
- ✅ PLIC standard
- ⚠️ Different peripheral addresses (SiFive uses different bases)

---

## Testing & Validation

### Address Decode Tests
```c
// Test that each device is accessible at correct address
write32(0x02000000, 0x1);  // CLINT MSIP
assert(read32(0x02000000) == 0x1);

write8(0x10000000, 'A');   // UART THR
// Check UART TX pin

uint64_t time = read64(0x0200BFF8);  // CLINT MTIME
assert(time > 0);
```

### Boundary Tests
```c
// Test that non-existent addresses return error (or ignore)
uint32_t val = read32(0x50000000);  // Non-mapped
// Should either return 0, cause exception, or hang (catch in testbench)
```

### Alignment Tests
```c
// Test unaligned access
write32(0x80000001, 0x12345678);  // Unaligned by 1 byte
uint32_t val = read32(0x80000001);
assert(val == 0x12345678);
```

---

## Diagram: Memory Map Visual

```
0xFFFF_FFFF ┌─────────────────────────┐
            │                         │
            │   Unmapped              │
            │                         │
0xA000_0000 ├─────────────────────────┤
            │   Reserved              │
0x9100_0000 ├─────────────────────────┤
            │   GPIO (4KB)            │ Phase 5+ (optional)
0x9000_0000 ├─────────────────────────┤
            │   Ethernet (4KB)        │ Phase 5+ (optional)
0x8900_0000 ├─────────────────────────┤
            │   Unmapped              │
0x8800_0000 ├─────────────────────────┤
            │   RAM Disk / Block      │ Phase 4+
            │   (16MB)                │
0x8050_0000 ├─────────────────────────┤
            │   Free RAM              │
0x8000_0000 ├─────────────────────────┤ Phase 3+: Unified 5MB
            │   System RAM            │
            │   (OpenSBI+Kernel+Data) │
            ├─────────────────────────┤
            │   Unmapped              │
0x1000_1000 ├─────────────────────────┤
            │   UART (4KB)            │ Phase 1 ✅
0x1000_0000 ├─────────────────────────┤
            │   Unmapped              │
0x0FFF_FFFF ├─────────────────────────┤
            │   PLIC (64MB)           │ Phase 4+
0x0C00_0000 ├─────────────────────────┤
            │   Unmapped              │
0x0201_0000 ├─────────────────────────┤
            │   CLINT (64KB)          │ Phase 1 ✅
0x0200_0000 ├─────────────────────────┤
            │   Unmapped              │
0x0001_0000 ├─────────────────────────┤
            │   IMEM (64KB)           │ Phase 1 ✅ (Harvard)
0x0000_0000 └─────────────────────────┘
```

---

## Change Log

| Date | Change | Notes |
|------|--------|-------|
| 2025-10-26 | Initial creation | Phase 1 memory map defined |

---

**Status**: 📍 Phase 1 Memory Map Active
