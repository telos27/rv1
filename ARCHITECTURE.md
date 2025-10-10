# RV1 Architecture Documentation

## Overview

This document details the microarchitecture of the RV1 RISC-V processor core across all development phases.

**Implementation Status**: Phase 1 Complete (Single-Cycle)
**Last Updated**: 2025-10-09

## Actual Implementation Status

### Completed Modules

| Module | File | Status | Description |
|--------|------|--------|-------------|
| Program Counter | `rtl/core/pc.v` | ✅ Complete | 32-bit PC with stall support |
| Instruction Memory | `rtl/memory/instruction_memory.v` | ✅ Complete | 4KB ROM, hex file loading |
| Data Memory | `rtl/memory/data_memory.v` | ✅ Complete | 4KB RAM, byte/halfword/word access |
| Decoder | `rtl/core/decoder.v` | ✅ Complete | All instruction formats, immediate generation |
| Control Unit | `rtl/core/control.v` | ✅ Complete | All 47 RV32I instructions supported |
| Register File | `rtl/core/register_file.v` | ✅ Complete | 32 registers, x0 hardwired to zero |
| ALU | `rtl/core/alu.v` | ✅ Complete | 10 operations with flags |
| Branch Unit | `rtl/core/branch_unit.v` | ✅ Complete | All 6 branch types + jumps |
| Top-Level Core | `rtl/core/rv32i_core.v` | ✅ Complete | Full integration, single-cycle |

### Implementation Highlights

- **Total RTL Lines**: ~705 lines
- **All RV32I Instructions**: 47/47 implemented
- **Testbenches**: 4 (3 unit + 1 integration)
- **Test Programs**: 3 assembly programs
- **Synthesis Ready**: No latches, clean Verilog-2001

### Design Decisions Made

1. **Immediate Generation**: Integrated into decoder module rather than separate imm_gen module
2. **LUI Implementation**: Operand A forced to 0 in top-level (simpler than special ALU mode)
3. **AUIPC Implementation**: Operand A set to PC in top-level
4. **Branch Unit**: Separate module for cleaner design
5. **Memory**: Synchronous write, combinational read for single-cycle
6. **FENCE/ECALL/EBREAK**: Implemented as NOPs (proper handling in Phase 4)

### Deviations from Original Plan

- ✅ Immediate generator integrated into decoder (simpler)
- ✅ Branch unit separated out (cleaner)
- ✅ No separate imm_sel mux needed (handled in control unit)

## Design Parameters

```verilog
parameter DATA_WIDTH = 32;          // 32-bit data path
parameter ADDR_WIDTH = 32;          // 32-bit address space
parameter REG_COUNT = 32;           // 32 architectural registers
parameter RESET_VECTOR = 32'h0000_0000;  // Reset PC value
```

## Phase 1: Single-Cycle Architecture

### High-Level Datapath

```
                    ┌─────────────┐
                    │     PC      │
                    └─────┬───────┘
                          │
                          ▼
                    ┌─────────────┐
                    │   Inst Mem  │
                    └─────┬───────┘
                          │ instruction
                          ▼
                    ┌─────────────┐
                    │   Decoder   │
                    └──┬──┬──┬────┘
                       │  │  │
         ┌─────────────┘  │  └─────────────┐
         ▼                ▼                 ▼
    ┌────────┐       ┌─────────┐      ┌─────────┐
    │ RegFile│◄──────│ Control │      │ Imm Gen │
    └────┬───┘       └────┬────┘      └────┬────┘
         │                │                 │
         │ rs1  rs2       │                 │
         ▼    ▼           ▼                 │
       ┌────────────┐   controls            │
       │  ALU Mux   │◄────────────────────┬─┘
       └─────┬──────┘                      │
             ▼                              │
         ┌───────┐                          │
         │  ALU  │                          │
         └───┬───┘                          │
             ▼                              │
       ┌──────────┐                         │
       │ Data Mem │                         │
       └─────┬────┘                         │
             ▼                              │
       ┌──────────┐                         │
       │  WB Mux  │◄────────────────────────┘
       └─────┬────┘
             │
             ▼ (write back to RegFile)
```

### Module Descriptions

#### 1. Program Counter (PC)
```verilog
module pc (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_current
);
```
- Holds current instruction address
- Updates on rising clock edge
- Reset to RESET_VECTOR
- Supports stalling for hazards (future phases)

#### 2. Instruction Memory
```verilog
module instruction_memory #(
    parameter MEM_SIZE = 4096,  // 4KB default
    parameter MEM_FILE = ""
) (
    input  wire [31:0] addr,
    output wire [31:0] instruction
);
```
- Read-only memory for program storage
- Word-aligned access (addr[1:0] ignored)
- Combinational read (no clock needed in Phase 1)
- Load from hex file via $readmemh

#### 3. Register File
```verilog
module register_file (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        rd_wen,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
```
- 32 registers: x0-x31
- x0 hardwired to zero
- 2 read ports (combinational)
- 1 write port (synchronous on posedge clk)
- Write enable controlled by rd_wen

#### 4. Instruction Decoder
```verilog
module decoder (
    input  wire [31:0] instruction,
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [31:0] imm_i,
    output wire [31:0] imm_s,
    output wire [31:0] imm_b,
    output wire [31:0] imm_u,
    output wire [31:0] imm_j
);
```
- Extracts instruction fields
- Generates all immediate formats (sign-extended)
- Purely combinational logic

#### 5. Control Unit
```verilog
module control (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    output wire        reg_write,
    output wire        mem_read,
    output wire        mem_write,
    output wire        branch,
    output wire        jump,
    output wire [1:0]  alu_op,
    output wire        alu_src,
    output wire [1:0]  wb_sel,
    output wire        pc_src
);
```
- Decodes opcode to control signals
- Combinational logic
- One-hot or binary encoding for signals

#### 6. Immediate Generator
```verilog
module imm_gen (
    input  wire [31:0] instruction,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] immediate
);
```
- Selects and formats immediate based on instruction type
- Sign-extends appropriately
- Supports I, S, B, U, J formats

#### 7. ALU (Arithmetic Logic Unit)
```verilog
module alu (
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] result,
    output wire        zero,
    output wire        less_than,
    output wire        less_than_unsigned
);
```
- Performs arithmetic and logic operations
- Operations: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
- Flag outputs for branch conditions
- 32-bit operations

**ALU Control Encoding**:
```
4'b0000: ADD
4'b0001: SUB
4'b0010: SLL (shift left logical)
4'b0011: SLT (set less than)
4'b0100: SLTU (set less than unsigned)
4'b0101: XOR
4'b0110: SRL (shift right logical)
4'b0111: SRA (shift right arithmetic)
4'b1000: OR
4'b1001: AND
```

#### 8. Data Memory
```verilog
module data_memory #(
    parameter MEM_SIZE = 4096
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,      // for load/store size
    output reg  [31:0] read_data
);
```
- Byte-addressable memory
- Supports byte (B), halfword (H), word (W) access
- Signed and unsigned loads
- Synchronous writes, combinational reads (Phase 1)

#### 9. Branch Unit
```verilog
module branch_unit (
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jump,
    output wire        take_branch
);
```
- Evaluates branch conditions
- Supports: BEQ, BNE, BLT, BGE, BLTU, BGEU
- Jump instructions always taken

### Control Signals

| Signal | Width | Description |
|--------|-------|-------------|
| reg_write | 1 | Enable register file write |
| mem_read | 1 | Enable memory read |
| mem_write | 1 | Enable memory write |
| branch | 1 | Instruction is a branch |
| jump | 1 | Instruction is a jump |
| alu_src | 1 | ALU operand B: 0=rs2, 1=immediate |
| alu_op | 2 | ALU operation type |
| wb_sel | 2 | Write-back source: 00=ALU, 01=MEM, 10=PC+4 |
| pc_src | 1 | PC source: 0=PC+4, 1=branch/jump target |
| imm_sel | 3 | Immediate format selection |

### Instruction Opcode Map

```
LOAD     = 7'b0000011
LOAD-FP  = 7'b0000111  (not implemented)
MISC-MEM = 7'b0001111  (FENCE)
OP-IMM   = 7'b0010011  (ADDI, SLTI, etc.)
AUIPC    = 7'b0010111
STORE    = 7'b0100011
STORE-FP = 7'b0100111  (not implemented)
OP       = 7'b0110011  (ADD, SUB, etc.)
LUI      = 7'b0110111
BRANCH   = 7'b1100011
JALR     = 7'b1100111
JAL      = 7'b1101111
SYSTEM   = 7'b1110011  (ECALL, EBREAK)
```

### Timing (Single-Cycle)

All instructions complete in one clock cycle:
```
Cycle 1: IF + ID + EX + MEM + WB (all in one cycle)
         └─── Critical Path ───┘
```

**Critical Path**:
1. PC register → Instruction Memory (read)
2. Instruction → Decoder → Control
3. Register File (read)
4. ALU operation
5. Data Memory (read if load)
6. Write-back mux → Register File (write setup)

**Estimated delays** (for timing analysis):
- Register setup/hold: ~0.5ns
- Instruction memory: ~2ns
- Decoder + Control: ~1ns
- Register file read: ~1ns
- ALU: ~2ns
- Data memory: ~2ns
- Mux + routing: ~0.5ns
**Total: ~9ns → ~111MHz max**

## Phase 2: Multi-Cycle Architecture

### State Machine

```
States:
- FETCH:    Fetch instruction from memory
- DECODE:   Decode and read registers
- EXECUTE:  ALU operation
- MEMORY:   Memory access (if needed)
- WRITEBACK: Write result to register

State Transitions:
FETCH → DECODE → EXECUTE → MEMORY → WRITEBACK → FETCH
                             ↓ (if no mem access)
                         WRITEBACK
```

### Modifications from Single-Cycle

1. **Shared Memory**: Single memory for both instructions and data
2. **Multi-Cycle Control**: FSM-based control unit
3. **Internal Registers**: Hold values between states
   - Instruction Register (IR)
   - Memory Data Register (MDR)
   - ALU Output Register
   - A, B registers for operands

## Phase 3: Pipelined Architecture

### Pipeline Stages

```
┌────┐    ┌────┐    ┌────┐    ┌─────┐    ┌────┐
│ IF │ -> │ ID │ -> │ EX │ -> │ MEM │ -> │ WB │
└────┘    └────┘    └────┘    └─────┘    └────┘
  │         │         │          │          │
  PC      RegFile    ALU      DataMem    RegFile
  IMem    Decoder              Write      Write
```

### Pipeline Registers

```verilog
// IF/ID Pipeline Register
struct {
    logic [31:0] pc;
    logic [31:0] instruction;
} if_id;

// ID/EX Pipeline Register
struct {
    logic [31:0] pc;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] immediate;
    logic [4:0]  rd;
    // ... control signals
} id_ex;

// EX/MEM Pipeline Register
struct {
    logic [31:0] alu_result;
    logic [31:0] rs2_data;
    logic [4:0]  rd;
    // ... control signals
} ex_mem;

// MEM/WB Pipeline Register
struct {
    logic [31:0] alu_result;
    logic [31:0] mem_data;
    logic [4:0]  rd;
    // ... control signals
} mem_wb;
```

### Hazard Handling

#### 1. Data Hazards (RAW - Read After Write)

**Forwarding/Bypass**:
```
Forward from EX/MEM if:
    (EX/MEM.rd == ID/EX.rs1 || EX/MEM.rd == ID/EX.rs2) && EX/MEM.reg_write

Forward from MEM/WB if:
    (MEM/WB.rd == ID/EX.rs1 || MEM/WB.rd == ID/EX.rs2) && MEM/WB.reg_write
    && !(EX/MEM.rd == ID/EX.rs1/rs2 && EX/MEM.reg_write)  // EX has priority
```

**Load-Use Stall**:
```
Stall if:
    ID/EX.mem_read && (ID/EX.rd == IF/ID.rs1 || ID/EX.rd == IF/ID.rs2)
```

#### 2. Control Hazards

**Branch Prediction**:
- Phase 3.1: Predict not-taken (flush on taken)
- Phase 3.2: 1-bit predictor
- Phase 3.3: 2-bit saturating counter

**Branch Resolution**:
- Resolve in EX stage
- Flush IF/ID and ID/EX if mispredicted

### Performance Metrics

**CPI (Cycles Per Instruction)**:
- Ideal: 1.0 (no hazards)
- With hazards: 1.2-1.5 (depends on code)

**Speedup vs Single-Cycle**:
- Theoretical: 5x (5 stages)
- Practical: 3-4x (due to hazards)

## Phase 4: Extensions

### M Extension (Multiply/Divide)

**New Instructions**:
- MUL, MULH, MULHSU, MULHU
- DIV, DIVU, REM, REMU

**Implementation**:
- Option 1: Iterative (34 cycles)
- Option 2: Single-cycle (large combinational)
- Option 3: Multi-cycle state machine (configurable)

### CSR (Control and Status Registers)

**CSR Instructions**:
- CSRRW, CSRRS, CSRRC
- CSRRWI, CSRRSI, CSRRCI

**Key CSRs**:
```
mstatus   (0x300): Machine status
mie       (0x304): Interrupt enable
mtvec     (0x305): Trap vector
mepc      (0x341): Exception PC
mcause    (0x342): Trap cause
mtval     (0x343): Trap value
```

### Trap Handling

**Exception Flow**:
1. Save PC to mepc
2. Save cause to mcause
3. Jump to mtvec
4. Disable interrupts
5. Set privilege to Machine

**Return Flow** (MRET):
1. Restore PC from mepc
2. Restore privilege
3. Re-enable interrupts

### Cache (Future)

**I-Cache**:
- Direct-mapped, 16KB
- 64-byte cache lines
- Write-through policy

**D-Cache**:
- 2-way set associative, 16KB
- 64-byte cache lines
- Write-back policy
- LRU replacement

## Memory Map

```
0x0000_0000 - 0x0000_0FFF: Instruction memory (4KB)
0x0000_1000 - 0x0000_1FFF: Data memory (4KB)
0x1000_0000 - 0x1000_00FF: Memory-mapped I/O
0x8000_0000 - 0x8FFF_FFFF: External memory (future)
```

## Reset Behavior

1. PC ← RESET_VECTOR (0x0000_0000)
2. All registers ← 0
3. Pipeline registers ← 0
4. Control signals ← 0 (no-op)

## Design Constraints

1. **No combinational loops**
2. **All FSMs must have default state**
3. **All memory must be initialized**
4. **No latches** (always specify all cases)
5. **Clock domain**: Single clock for Phase 1-3

## Future Considerations

- Interrupt controller (PLIC)
- Timer (CLINT)
- Debug module
- Performance counters
- Virtual memory (MMU)
- Floating-point unit (F/D extensions)
