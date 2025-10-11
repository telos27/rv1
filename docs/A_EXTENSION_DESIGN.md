# RISC-V A Extension Design Document

## Overview
This document describes the design and implementation of the RISC-V A (Atomic) extension for the RV1 processor. The A extension provides atomic memory operations for synchronization primitives and lock-free programming.

## A Extension Components

The A extension consists of two main instruction groups:
1. **Zalrsc**: Load-Reserved/Store-Conditional instructions
2. **Zaamo**: Atomic Memory Operations (AMO)

## Instruction Set

### RV32A Instructions (11 instructions)

#### Load-Reserved / Store-Conditional
| Instruction | Format | Operation | Description |
|-------------|--------|-----------|-------------|
| **LR.W** | lr.w rd, (rs1) | rd = M[rs1], reserve M[rs1] | Load word and reserve |
| **SC.W** | sc.w rd, rs2, (rs1) | if reserved: M[rs1]=rs2, rd=0<br>else: rd=1 | Store conditional |

#### Atomic Memory Operations (AMO)
| Instruction | Format | Operation | Description |
|-------------|--------|-----------|-------------|
| **AMOSWAP.W** | amoswap.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=rs2 | Atomic swap |
| **AMOADD.W** | amoadd.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=rd+rs2 | Atomic add |
| **AMOXOR.W** | amoxor.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=rd^rs2 | Atomic XOR |
| **AMOAND.W** | amoand.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=rd&rs2 | Atomic AND |
| **AMOOR.W** | amoor.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=rd\|rs2 | Atomic OR |
| **AMOMIN.W** | amomin.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=min(rd,rs2) | Atomic signed min |
| **AMOMAX.W** | amomax.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=max(rd,rs2) | Atomic signed max |
| **AMOMINU.W** | amominu.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=minu(rd,rs2) | Atomic unsigned min |
| **AMOMAXU.W** | amomaxu.w rd, rs2, (rs1) | rd=M[rs1]; M[rs1]=maxu(rd,rs2) | Atomic unsigned max |

### RV64A Additional Instructions (11 instructions)

All of the above with `.D` suffix for doubleword (64-bit) operations:
- LR.D, SC.D
- AMOSWAP.D, AMOADD.D, AMOXOR.D, AMOAND.D, AMOOR.D
- AMOMIN.D, AMOMAX.D, AMOMINU.D, AMOMAXU.D

## Instruction Encoding

### R-type Atomic Format
```
 31    27 26 25 24    20 19    15 14   12 11    7 6      0
+--------+--+--+--------+--------+-------+-------+--------+
| funct5 |aq|rl|  rs2   |  rs1   | funct3|  rd   | opcode |
+--------+--+--+--------+--------+-------+-------+--------+
   5      1  1     5        5        3       5       7
```

### Opcode and Function Codes

**Common Fields:**
- **Opcode**: `0101111` (0x2F) - AMO major opcode
- **funct3**:
  - `010` (0x2) for `.W` (word, 32-bit)
  - `011` (0x3) for `.D` (doubleword, 64-bit)

**funct5 Values:**
| Instruction | funct5 (bits 31-27) |
|-------------|---------------------|
| LR.W/LR.D | `00010` (0x02) |
| SC.W/SC.D | `00011` (0x03) |
| AMOSWAP | `00001` (0x01) |
| AMOADD | `00000` (0x00) |
| AMOXOR | `00100` (0x04) |
| AMOAND | `01100` (0x0C) |
| AMOOR | `01000` (0x08) |
| AMOMIN | `10000` (0x10) |
| AMOMAX | `10100` (0x14) |
| AMOMINU | `11000` (0x18) |
| AMOMAXU | `11100` (0x1C) |

### Memory Ordering Bits

- **aq** (bit 26): Acquire ordering
  - Set: No following memory operations can be observed before this atomic
- **rl** (bit 25): Release ordering
  - Set: All prior memory operations must complete before this atomic
- Both clear: Relaxed ordering (no constraints)
- Both set: Sequentially consistent ordering

## Microarchitecture Design

### High-Level Architecture

The A extension requires:
1. **Atomic Unit** - Executes atomic operations
2. **Reservation Station** - Tracks LR/SC reservations
3. **Memory Interface Modifications** - Support atomic read-modify-write
4. **Pipeline Integration** - Multi-cycle atomic operation handling

### Atomic Unit Module (`atomic_unit.v`)

```verilog
module atomic_unit #(
    parameter XLEN = 32
) (
    input  wire clk,
    input  wire reset,

    // Control
    input  wire start,              // Start atomic operation
    input  wire [4:0] atomic_op,    // Operation type (from funct5)
    input  wire is_lr,              // LR instruction
    input  wire is_sc,              // SC instruction
    input  wire is_amo,             // AMO instruction
    input  wire [2:0] funct3,       // Size (.W or .D)

    // Data inputs
    input  wire [XLEN-1:0] addr,    // Memory address (rs1)
    input  wire [XLEN-1:0] src_data,// Source data (rs2)

    // Memory interface
    output reg  mem_req,            // Memory request
    output reg  mem_we,             // Memory write enable
    output reg  [XLEN-1:0] mem_addr,
    output reg  [XLEN-1:0] mem_wdata,
    input  wire [XLEN-1:0] mem_rdata,
    input  wire mem_ready,

    // Outputs
    output reg  [XLEN-1:0] result,  // Result to rd
    output reg  done,               // Operation complete
    output reg  busy                // Unit busy
);
```

**State Machine:**
1. IDLE - Wait for start signal
2. READ - Read current value from memory
3. COMPUTE - Perform atomic operation
4. WRITE - Write result back to memory (AMO/SC only)
5. DONE - Assert done signal

### Reservation Station

For LR/SC support:
```verilog
module reservation_station #(
    parameter XLEN = 32
) (
    input  wire clk,
    input  wire reset,

    // LR operation
    input  wire lr_valid,
    input  wire [XLEN-1:0] lr_addr,

    // SC operation
    input  wire sc_valid,
    input  wire [XLEN-1:0] sc_addr,
    output wire sc_success,         // 1 if reservation valid

    // Invalidation
    input  wire invalidate,         // External write to reserved address
    input  wire [XLEN-1:0] inv_addr
);
```

**Reservation Rules:**
- Only ONE reservation at a time per hart
- Reservation cleared on:
  - SC to same address (consumed)
  - SC to different address (failed)
  - Any other memory write between LR/SC
  - Context switch / interrupt
  - Cache line eviction (if applicable)

### AMO Operations

The atomic unit must implement:

1. **AMOSWAP**: Simple swap (no computation)
2. **AMOADD**: signed_add(loaded_value, rs2)
3. **AMOXOR**: loaded_value XOR rs2
4. **AMOAND**: loaded_value AND rs2
5. **AMOOR**: loaded_value OR rs2
6. **AMOMIN**: signed_min(loaded_value, rs2)
7. **AMOMAX**: signed_max(loaded_value, rs2)
8. **AMOMINU**: unsigned_min(loaded_value, rs2)
9. **AMOMAXU**: unsigned_max(loaded_value, rs2)

### Pipeline Integration

**EX Stage Modifications:**
- Add atomic unit alongside ALU, mul_div_unit
- Multi-cycle atomic operations stall pipeline (similar to M extension)
- Hold IDEX and EXMEM registers while atomic unit is busy

**MEM Stage:**
- Atomic memory accesses bypass normal load/store path
- Memory controller must support atomic read-modify-write
- No forwarding during atomic operations (atomic ensures ordering)

**Control Signals:**
- `atomic_op` (5 bits) - Operation type
- `is_atomic` - Flag for atomic instruction
- `atomic_busy` - Stall signal while atomic executes

## Timing Diagram

### LR/SC Sequence
```
Cycle:  1    2    3    4    5    6    7    8
LR:     ID   EX1  EX2  MEM  WB   -    -    -
        decode    reserve  done
                  read

SC:     -    -    -    -    ID   EX1  EX2  MEM
                            check reserve  done
                            decode    write
```

### AMO Sequence
```
Cycle:  1    2    3    4    5
AMO:    ID   EX1  EX2  EX3  MEM
        decode    read  wr  done
                  compute
```

## Alignment Requirements

- **Word (.W)**: Must be 4-byte aligned
- **Doubleword (.D)**: Must be 8-byte aligned
- Misaligned atomic → Address Misaligned Exception

## Memory Ordering Implementation

For this simple design:
- **aq/rl bits**: Decode and store in pipeline register
- **Simple implementation**: All atomics are sequentially consistent
  - Drain store buffer before atomic
  - No speculative execution across atomics
  - Fence semantics applied automatically
- **Future optimization**: Relax ordering when aq=0 and rl=0

## Control Unit Updates

Add to `control.v`:

```verilog
// A extension opcodes
localparam OPCODE_AMO = 7'b0101111;

// Atomic operation decode
wire is_lr    = (opcode == OPCODE_AMO) && (funct5 == 5'b00010);
wire is_sc    = (opcode == OPCODE_AMO) && (funct5 == 5'b00011);
wire is_amo   = (opcode == OPCODE_AMO) && !is_lr && !is_sc;
wire is_atomic = is_lr || is_sc || is_amo;
```

## Decoder Updates

Add to `decoder.v`:

```verilog
// Extract A extension fields
assign funct5 = instruction[31:27];
assign aq_bit = instruction[26];
assign rl_bit = instruction[25];
```

## Data Memory Interface

The data memory must support atomic operations:

```verilog
// Add to data_memory.v interface
input  wire atomic_req,           // Atomic operation request
input  wire [4:0] atomic_op,      // Atomic operation type
input  wire [XLEN-1:0] atomic_wdata, // Data for AMO/SC
output reg  atomic_done           // Atomic operation complete
```

**Memory behavior:**
- Atomic operations are NOT interruptible
- Read-modify-write appears as single operation to other masters
- For single-core: Simply disable interrupts during atomic
- For multicore: Memory controller must provide atomicity

## Testing Strategy

### Unit Tests
1. **atomic_unit_tb.v** - Test each atomic operation
2. **reservation_station_tb.v** - Test LR/SC reservation logic

### Integration Tests
1. **LR/SC Tests**:
   - Basic LR/SC success
   - SC failure (intervening write)
   - SC to different address (failure)
2. **AMO Tests**:
   - Each AMO operation with known values
   - Signed vs unsigned MIN/MAX
   - Word vs doubleword operations
3. **Alignment Tests**:
   - Misaligned atomic → exception
4. **Ordering Tests**:
   - Basic aq/rl flag handling

### Test Programs
```assembly
# Test LR/SC
lr.w    t0, (a0)       # Load reserved
addi    t0, t0, 1      # Increment
sc.w    t1, t0, (a0)   # Store conditional
bnez    t1, retry      # Retry if failed

# Test AMO
amoadd.w t0, t1, (a0)  # Atomic add
```

## Implementation Phases

### Phase 7.1: Atomic Unit Core
- [ ] Implement `atomic_unit.v` with state machine
- [ ] Implement `reservation_station.v` for LR/SC
- [ ] Unit tests for atomic operations

### Phase 7.2: Pipeline Integration
- [ ] Update control unit for A extension decode
- [ ] Update decoder for funct5, aq, rl extraction
- [ ] Add atomic unit to EX stage
- [ ] Add pipeline stall logic for atomic operations

### Phase 7.3: Memory Interface
- [ ] Modify data memory for atomic support
- [ ] Implement read-modify-write atomicity
- [ ] Add alignment checking

### Phase 7.4: Testing and Verification
- [ ] Integration testbench
- [ ] Assembly test programs
- [ ] Compliance tests (if available)

## Performance Considerations

**Latency:**
- LR: 2 cycles (1 read + 1 reservation setup)
- SC: 2-3 cycles (1 check + 1 write if success)
- AMO: 3-4 cycles (1 read + 1 compute + 1 write)

**Pipeline Impact:**
- Atomic operations stall pipeline (similar to M extension)
- No forwarding during atomics
- Future: Out-of-order execution with reservation stations

## Future Enhancements

1. **Performance**:
   - Implement relaxed ordering for aq=0, rl=0 cases
   - Overlapping non-conflicting atomics
   - Speculative SC (assume success)

2. **Multicore**:
   - Cache coherence protocol (MESI/MOESI)
   - Interconnect support for atomic operations
   - Distributed reservation tracking

3. **Extensions**:
   - Zacas: Atomic compare-and-swap
   - Ztso: Total Store Ordering

## References

- RISC-V Unprivileged ISA Specification
- RISC-V A Extension Chapter (Atomic Instructions)
- RISC-V Memory Consistency Model

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2025-10-10 | 1.0 | Initial design document |
