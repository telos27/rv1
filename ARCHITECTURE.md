# RV1 Architecture Documentation

## Overview

This document details the microarchitecture of the RV1 RISC-V processor core.

**Implementation Status**: Phase 13 Complete - Full RV32IMAFDC with Supervisor Mode & Virtual Memory
**Last Updated**: 2025-10-23 (100% Compliance - All Extensions Complete)

## Implementation Summary

### Current Status
- **ISA**: RV32IMAFDC + RV64IMAFDC (parameterized)
- **Architecture**: 5-stage pipelined with full hazard handling
- **Privilege Modes**: M-mode, S-mode, U-mode (full privilege system)
- **Virtual Memory**: Sv32 (RV32) and Sv39 (RV64) with 16-entry TLB
- **Extensions**: M (multiply/divide), A (atomics), F/D (floating-point), C (compressed)
- **Compliance**: **81/81 tests (100%)** ✅
  - RV32I: 42/42 (100%) ✅
  - RV32M: 8/8 (100%) ✅
  - RV32A: 10/10 (100%) ✅
  - RV32C: 1/1 (100%) ✅
  - RV32F: 11/11 (100%) ✅
  - RV32D: 9/9 (100%) ✅

### Implementation Scale
- **Total RTL**: ~7,500 lines across 36 modules
- **Instructions**: 184 total (47 base + 13 M + 22 A + 52 F/D + 40 C + 10 system)
- **Testbenches**: ~3,000 lines
- **Documentation**: ~6,000 lines

### Core Modules (36 total)

**Datapath & Control** (9 modules):
- `alu.v`, `register_file.v`, `pc.v`, `decoder.v`, `control.v`, `branch_unit.v`
- `exception_unit.v`, `csr_file.v`, `mmu.v`

**Pipeline Infrastructure** (8 modules):
- `rv32i_core_pipelined.v` (top-level), `ifid_register.v`, `idex_register.v`, `exmem_register.v`, `memwb_register.v`
- `forwarding_unit.v`, `hazard_detection_unit.v`, `rvc_decoder.v`

**M Extension** (3 modules):
- `mul_unit.v`, `div_unit.v`, `mul_div_unit.v`

**A Extension** (2 modules):
- `atomic_unit.v`, `reservation_station.v`

**F/D Extension** (11 modules):
- `fpu.v`, `fp_register_file.v`, `fp_adder.v`, `fp_multiplier.v`, `fp_divider.v`, `fp_sqrt.v`
- `fp_fma.v`, `fp_converter.v`, `fp_compare.v`, `fp_classify.v`, `fp_minmax.v`, `fp_sign.v`

**Memory** (2 modules):
- `instruction_memory.v`, `data_memory.v`

**Legacy** (1 module):
- `rv32i_core.v` (original single-cycle core, kept for reference)

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

**Centralized Forwarding Architecture** (Phase 12):

The RV1 core implements a **dual-stage forwarding system** with centralized control in `forwarding_unit.v`:

**ID Stage Forwarding** (for early branch resolution):
- Forward from EX stage (IDEX register) → Priority 1
- Forward from MEM stage (EXMEM register) → Priority 2
- Forward from WB stage (MEMWB register) → Priority 3
- 3-bit encoding: `3'b100`=EX, `3'b010`=MEM, `3'b001`=WB, `3'b000`=NONE

**EX Stage Forwarding** (for ALU operations):
- Forward from MEM stage (EXMEM register) → Priority 1
- Forward from WB stage (MEMWB register) → Priority 2
- 2-bit encoding: `2'b10`=MEM, `2'b01`=WB, `2'b00`=NONE

```verilog
// Forwarding Unit Interface (simplified)
module forwarding_unit (
    // ID Stage (branch resolution)
    input  [4:0] id_rs1, id_rs2,
    output [2:0] id_forward_a, id_forward_b,    // 3-bit: EX/MEM/WB/NONE

    // EX Stage (ALU operations)
    input  [4:0] idex_rs1, idex_rs2,
    output [1:0] forward_a, forward_b,          // 2-bit: MEM/WB/NONE

    // Pipeline write ports
    input  [4:0] idex_rd, exmem_rd, memwb_rd,
    input        idex_reg_write, exmem_reg_write, memwb_reg_write,
    // ... FP and cross-file forwarding signals
);
```

**Priority Resolution**:
```
EX→ID forwarding (highest priority):
    if (idex_reg_write && idex_rd != 0 && idex_rd == id_rs1)
        id_forward_a = 3'b100

MEM→ID forwarding (medium priority):
    else if (exmem_reg_write && exmem_rd != 0 && exmem_rd == id_rs1)
        id_forward_a = 3'b010

WB→ID forwarding (lowest priority):
    else if (memwb_reg_write && memwb_rd != 0 && memwb_rd == id_rs1)
        id_forward_a = 3'b001
```

**Load-Use Hazards**:

Cannot be resolved by forwarding alone - requires 1-cycle stall:
```verilog
// In hazard_detection_unit.v
assign load_use_hazard = idex_mem_read &&
                         ((idex_rd == id_rs1) || (idex_rd == id_rs2)) &&
                         (idex_rd != 5'h0);

assign stall_pc   = load_use_hazard || fp_load_use_hazard ||
                    m_extension_stall || a_extension_stall ||
                    fp_extension_stall || mmu_stall;
assign stall_ifid = stall_pc;
```

**MMU Stall Propagation** (Phase 12 critical fix):
```verilog
// MMU busy during page table walk - must stall entire pipeline
wire mmu_stall;
assign mmu_stall = mmu_busy;
```

**Forwarding Coverage**:
- ✅ Integer register forwarding (EX→ID, MEM→ID, WB→ID, MEM→EX, WB→EX)
- ✅ FP register forwarding (same paths as integer)
- ✅ Cross-file forwarding (INT→FP for FMV.W.X, FP→INT for FMV.X.W)
- ✅ 3-operand FP forwarding (FMADD/FMSUB/FNMADD/FNMSUB)

See `docs/FORWARDING_ARCHITECTURE.md` for detailed forwarding documentation.

#### 2. Control Hazards

**Branch Resolution**:
- Early branch resolution in **ID stage** (not EX)
- Branch target computed in ID stage
- Branch condition evaluated in ID stage using forwarded values
- Reduces control hazard penalty from 3 cycles to 1 cycle

**Branch Handling**:
```verilog
// Branch taken signal generated in ID stage
wire ex_take_branch;

// Flush pipeline on branch/jump
assign flush_idex = ex_take_branch;  // Flush instruction in ID/EX

// PC update on branch
wire [31:0] branch_target;  // Computed in ID stage
assign pc_next = ex_take_branch ? branch_target : pc_plus_4;
```

**Branch Prediction** (not yet implemented):
- Phase 3.1: Predict not-taken (flush on taken) ← Current
- Phase 3.2: 1-bit predictor (future)
- Phase 3.3: 2-bit saturating counter (future)

### Forwarding Unit Architecture (Phase 12)

**Module**: `rtl/core/forwarding_unit.v` (268 lines)

The forwarding unit is the centralized control module for all data forwarding in the pipeline. It monitors pipeline register write ports and generates forwarding control signals for both ID and EX stages.

#### Design Principles

1. **Centralized Control**: Single source of truth for all forwarding decisions
2. **Multi-Level Forwarding**: Supports forwarding from 3 pipeline stages (EX, MEM, WB)
3. **Priority-Based**: Most recent instruction data has highest priority
4. **Dual-Stage Support**: Separate forwarding paths for ID (branches) and EX (ALU) stages
5. **Scalable**: Clean interface designed for future superscalar extension

#### Forwarding Paths

**ID Stage Forwarding Paths**:
```
EX  → ID  (IDEX.rd  → ID.rs1/rs2)  [Priority 1 - Most Recent]
MEM → ID  (EXMEM.rd → ID.rs1/rs2)  [Priority 2]
WB  → ID  (MEMWB.rd → ID.rs1/rs2)  [Priority 3 - Least Recent]
```

**EX Stage Forwarding Paths**:
```
MEM → EX  (EXMEM.rd → IDEX.rs1/rs2)  [Priority 1]
WB  → EX  (MEMWB.rd → IDEX.rs1/rs2)  [Priority 2]
```

Note: EX→EX forwarding is impossible (circular dependency) - such cases are load-use hazards requiring stalls.

#### Signal Encoding

**3-bit ID Stage Encoding**:
- `3'b100`: Forward from EX stage (IDEX register)
- `3'b010`: Forward from MEM stage (EXMEM register)
- `3'b001`: Forward from WB stage (MEMWB register)
- `3'b000`: No forwarding (use register file)

**2-bit EX Stage Encoding**:
- `2'b10`: Forward from MEM stage (EXMEM register)
- `2'b01`: Forward from WB stage (MEMWB register)
- `2'b00`: No forwarding (use IDEX register value)

#### Implementation Example

ID Stage rs1 forwarding logic:
```verilog
always @(*) begin
    id_forward_a = 3'b000;  // Default: no forwarding

    // Priority 1: Forward from EX stage (most recent)
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs1))
        id_forward_a = 3'b100;

    // Priority 2: Forward from MEM stage
    else if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == id_rs1))
        id_forward_a = 3'b010;

    // Priority 3: Forward from WB stage
    else if ((memwb_reg_write | memwb_int_reg_write_fp) &&
             (memwb_rd != 5'h0) && (memwb_rd == id_rs1))
        id_forward_a = 3'b001;
end
```

Key protection: `idex_rd != 5'h0` prevents forwarding to x0 (zero register).

#### Cross-File Forwarding

Supports forwarding between integer and FP register files:
- **INT→FP**: `memwb_fp_reg_write_int` (FMV.W.X, FCVT.S.W instructions)
- **FP→INT**: `memwb_int_reg_write_fp` (FMV.X.W, FCVT.W.S instructions)

#### Forwarding Muxes

Forwarding muxes are located in `rv32i_core_pipelined.v`:

**ID Stage Integer Forwarding**:
```verilog
assign id_rs1_data = (id_forward_a == 3'b100) ? ex_alu_result :      // EX stage
                     (id_forward_a == 3'b010) ? exmem_alu_result :   // MEM stage
                     (id_forward_a == 3'b001) ? wb_data :            // WB stage
                     id_rs1_data_raw;                                // Register file
```

**EX Stage Integer Forwarding**:
```verilog
assign ex_operand_a = (forward_a == 2'b10) ? exmem_alu_result :  // MEM stage
                      (forward_a == 2'b01) ? wb_data :            // WB stage
                      idex_rs1_data;                              // IDEX register
```

#### Timing Considerations

**ID Stage Critical Path**:
```
Register File → Forwarding Comparison → 4:1 Mux → Branch Unit
```
This path is timing-critical for branch resolution. Forwarding comparisons are done in parallel with register file read to minimize delay.

**EX Stage Critical Path**:
```
ALU Result → Forwarding Mux → ALU Input
```
Less critical - no register file in path, simpler 3:1 mux.

#### Verification Results

**Test Coverage**: 41/42 RISC-V RV32I compliance tests passing (97.6%)
- Only failure: `rv32ui-p-ma_data` (misaligned access - expected without trap handler)

**Forwarding Scenarios Tested**:
- ✅ EX→ID forwarding (branch after ALU)
- ✅ MEM→ID forwarding (branch after load)
- ✅ WB→ID forwarding (branch after register write)
- ✅ MEM→EX forwarding (ALU after ALU)
- ✅ WB→EX forwarding (ALU after register write)
- ✅ Load-use hazard detection and stalling
- ✅ MMU stall propagation (Phase 12 critical fix)

### Performance Metrics

**CPI (Cycles Per Instruction)**:
- Ideal: 1.0 (no hazards)
- With forwarding: 1.0-1.2 (load-use hazards only)
- Without forwarding: 1.3-1.8 (frequent stalls)

**CPI Improvement from Forwarding**: ~30-40% for typical code

**Speedup vs Single-Cycle**:
- Theoretical: 5x (5 stages)
- Practical: 3-4x (due to remaining hazards)

**Area Cost**:
- Forwarding unit: ~5% of total core area
- Comparators: 12x 5-bit (60 bits)
- Muxes: 12x 32-bit 4:1 (integer + FP)

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

### Supervisor Mode (Phase 10.2)

**Privilege Levels**:
- 00 (U-mode): User applications
- 01 (S-mode): Operating system kernel
- 11 (M-mode): Firmware/bootloader

**Supervisor CSRs** (8 registers):
```
sstatus   (0x100): Supervisor status (subset of mstatus)
sie       (0x104): Supervisor interrupt enable (subset of mie)
stvec     (0x105): Supervisor trap vector
sscratch  (0x140): Supervisor scratch register
sepc      (0x141): Supervisor exception PC
scause    (0x142): Supervisor trap cause
stval     (0x143): Supervisor trap value
sip       (0x144): Supervisor interrupt pending (subset of mip)
```

**Trap Delegation CSRs**:
```
medeleg   (0x302): Machine exception delegation to S-mode
mideleg   (0x303): Machine interrupt delegation to S-mode
```

**Key Features**:
- **SSTATUS**: Read-only view of MSTATUS (only S-mode fields visible)
  - Visible: SIE[1], SPIE[5], SPP[8], SUM[18], MXR[19]
  - Hidden: MIE[3], MPIE[7], MPP[12:11]
- **SIE/SIP**: Subset masks of MIE/MIP (only bits 1, 5, 9)
- **SRET Instruction**: Return from supervisor trap
  - Restores PC from SEPC
  - Restores privilege from SPP
  - Restores interrupt enable: SIE ← SPIE
- **CSR Privilege Checking**: S-mode cannot access M-mode CSRs
  - Violation triggers illegal instruction exception

**Trap Routing**:
```
┌─────────────────┐
│  Exception      │
└────────┬────────┘
         │
         ▼
   ┌─────────────┐
   │ Current     │
   │ Priv = M?   │
   └──┬──────┬───┘
      │Yes   │No
      ▼      ▼
   M-mode  ┌──────────┐
   Handler │Delegated?│
           │(medeleg) │
           └──┬───┬───┘
              │Y  │N
              ▼   ▼
           S-mode M-mode
           Handler Handler
```

**Implementation**:
- `rtl/core/csr_file.v`: All S-mode CSRs + delegation logic
- `rtl/core/decoder.v`: SRET instruction detection
- `rtl/core/control.v`: SRET control signals
- `rtl/core/rv32i_core_pipelined.v`: Privilege tracking + transitions
- `rtl/core/exception_unit.v`: Privilege-aware ECALL

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

## Known Limitations

**⚠️ Address these before major new features:**

1. **Atomic Forwarding Overhead (6%)**
   - Location: `hazard_detection_unit.v:126-155`
   - Issue: Conservative stall adds 1,049 cycles per LR/SC test (6% overhead)
   - Fix: Add single-cycle state tracking (would reduce to 0.3% overhead)
   - Justification: Simplicity > performance, but should optimize eventually

2. **FPU Compliance Issues (15% pass rate)**
   - Custom tests: 13/13 passing (basic operations work)
   - Official tests: 3/20 passing (edge cases reveal bugs)
   - Root causes: Likely fflags, rounding modes, NaN-boxing, signed zero
   - Action: Fix bugs revealed by official compliance tests
   - Details: See docs/FPU_COMPLIANCE_RESULTS.md

3. **Mixed 16/32-bit Instruction Streams**
   - Pure compressed: Working
   - Pure 32-bit: Working
   - Mixed: Addressing bugs in some cases
   - Action: Debug before production use

**See:** [KNOWN_ISSUES.md](../KNOWN_ISSUES.md) for complete details.

---

## Future Work

### Performance Enhancements (Optimization)
- **Atomic forwarding optimization** (6% → 0.3%) ⚡ *High priority*
- Branch prediction (2-bit saturating counters, BTB)
- Cache hierarchy (I-cache, D-cache with write-back)
- Larger TLB (16 → 64 entries)
- Superscalar execution (dual-issue)

### Testing & Validation (Quality)
- **Official RISC-V F/D compliance tests** 🧪 *High priority*
- **Mixed instruction debugging** 🔀 *High priority*
- Formal verification for critical paths
- Performance benchmarking (Dhrystone, CoreMark, SPEC)

### System Features (Functionality)
- Interrupt controller (PLIC - Platform-Level Interrupt Controller)
- Timer (CLINT - Core-Local Interruptor)
- Debug module (JTAG, hardware breakpoints)
- Performance counters (cycle, instruction, cache miss counters)
- Physical memory protection (PMP)

### Hardware Deployment (Real-World)
- FPGA synthesis and validation
- Peripheral interfaces (UART, GPIO, SPI, I2C)
- Boot ROM and bootloader
- Run Linux or xv6-riscv
- Multicore/SMP support
