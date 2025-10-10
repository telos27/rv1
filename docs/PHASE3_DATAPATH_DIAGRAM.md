# Phase 3: Pipeline Datapath Diagram Specification

**Author**: RV1 Project
**Date**: 2025-10-10
**Purpose**: Visual reference for pipelined processor datapath

---

## Datapath Overview (ASCII Art)

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    RV32I 5-Stage Pipelined Datapath                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

        ┌──────────┐        ┌──────────┐        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │    IF    │        │    ID    │        │    EX    │        │   MEM    │        │    WB    │
        │  Stage   │        │  Stage   │        │  Stage   │        │  Stage   │        │  Stage   │
        └──────────┘        └──────────┘        └──────────┘        └──────────┘        └──────────┘
             │                   │                   │                   │                   │
             ▼                   ▼                   ▼                   ▼                   ▼
```

---

## Stage 1: IF (Instruction Fetch)

```
      stall_pc
         │
         ▼
    ┌────────┐  pc_src
    │   PC   │◄─────────────────────────────────────────┐
    │ Register│                                          │
    └────┬───┘                                           │
         │ pc_current                                    │
         ├──────────────────────────┬────────────────────┤
         │                          │                    │
         ▼                          │                    │
    ┌─────────┐                     │                    │
    │  IMEM   │                     │                    │
    │ (I-Mem) │                     │                    │
    └────┬────┘                     │                    │
         │ instruction              │                    │
         │                          │                    │
         │         ┌───────┐        │                    │
         └────────►│       │        │                    │
                   │ IF/ID │        │                    │
         ┌────────►│  Reg  │        │                    │
         │         │       │        │                    │
         │         └───┬───┘        │                    │
         │             │            │                    │
         │             │            │                    │
      stall_IFID    flush_IFID     │                    │
                                    │                    │
                                    │                pc_next
                                    │              (from EX stage)
                                    │                    │
                                    └────────────────────┘
```

**Signals**:
- `pc_current [31:0]` - Current program counter
- `instruction [31:0]` - Fetched instruction
- `stall_pc` - Hold PC for load-use hazard
- `stall_IFID` - Hold IF/ID register
- `flush_IFID` - Clear IF/ID register (branch taken)
- `pc_src` - PC source select (sequential vs branch/jump)
- `pc_next [31:0]` - Next PC value

---

## Stage 2: ID (Instruction Decode & Register Read)

```
    From IF/ID Register
         │
         │ instruction [31:0]
         ▼
    ┌─────────┐
    │ Decoder │
    └────┬────┘
         │
         ├──► opcode, rd, rs1, rs2, funct3, funct7, immediates
         │
         ▼
    ┌─────────┐
    │ Control │
    │  Unit   │
    └────┬────┘
         │
         ├──► alu_control, alu_src, mem_read, mem_write, reg_write, etc.
         │
         │
    rs1_addr   rs2_addr                                    rd_addr (from WB)
         │         │                                            │
         ▼         ▼                                            ▼
    ┌───────────────────┐                                  ┌─────────┐
    │   Register File   │◄─────────────────────────────────┤ wb_data │
    │   (32 x 32-bit)   │  reg_write (from WB)             └─────────┘
    └─────┬──────┬──────┘
          │      │
      rs1_data  rs2_data
          │      │
          │      │         ┌───────┐
          └─────►│         │
                 │ ID/EX   │
          ┌─────►│  Reg   │
          │      │         │
          │      └───┬─────┘
          │          │
       flush_IDEX    │
      (load-use or   │
       branch)       │
                     ▼
               To EX Stage

    ┌──────────────────────────┐
    │  Hazard Detection Unit   │
    │  - Detects load-use      │
    │  - Generates stalls      │
    └──────────────────────────┘
```

**Signals from ID/EX Register**:
- `pc [31:0]`
- `rs1_data [31:0]`, `rs2_data [31:0]`
- `rs1_addr [4:0]`, `rs2_addr [4:0]` (for forwarding)
- `rd_addr [4:0]`
- `imm [31:0]`
- `opcode [6:0]`, `funct3 [2:0]`
- All control signals

---

## Stage 3: EX (Execute)

```
    From ID/EX Register
         │
         ├──► rs1_addr, rs2_addr, rd_addr
         │
         ▼
    ┌──────────────────────┐
    │  Forwarding Unit     │
    │  Inputs:             │
    │   - IDEX rs1/rs2     │
    │   - EXMEM rd, regw   │
    │   - MEMWB rd, regw   │
    │  Outputs:            │
    │   - forward_a [1:0]  │
    │   - forward_b [1:0]  │
    └──────────────────────┘
              │
              ▼
         forward_a, forward_b
              │
         ┌────┴─────┐
         ▼          ▼
    ┌────────┐  ┌────────┐
    │  Fwd   │  │  Fwd   │
    │  Mux A │  │  Mux B │
    └────┬───┘  └───┬────┘
         │          │
    operand_a   operand_b_fwd
         │          │
         │          ▼
         │      ┌────────┐  alu_src
         │      │  Mux   │◄────── (imm vs rs2_data)
         │      └───┬────┘
         │          │
         │     operand_b
         │          │
         └────┬─────┘
              ▼
         ┌────────┐
         │  ALU   │
         └────┬───┘
              │
         alu_result
              │
    ┌─────────┴──────────────────┐
    │                            │
    │  ┌──────────────┐          │
    │  │ Branch Unit  │          │
    │  │  - Evaluate  │          │
    │  │  - PC Update │          │
    │  └──────┬───────┘          │
    │         │                  │
    │    take_branch             │
    │         │                  │
    │         ▼                  │
    │    ┌─────────┐             │
    │    │ PC Mux  │             │
    │    │ & Flush │             │
    │    └─────────┘             │
    │         │                  │
    │    pc_next ────────────────┼────► To PC (in IF)
    │         │                  │
    │    flush_IFID              │
    │    flush_IDEX              │
    │                            │
    │         ┌───────┐          │
    └────────►│       │          │
              │EX/MEM │          │
    ┌────────►│  Reg  │          │
    │         │       │          │
    │         └───┬───┘          │
    │             │              │
    └─────────────┴──────────────┘
         mem_write_data
         (forwarded rs2)

    Forwarding Sources:
    ┌────────────────────────┐
    │ From EX/MEM:           │
    │  - alu_result          │
    │ From MEM/WB:           │
    │  - wb_data             │
    └────────────────────────┘
```

**Key Components**:
1. **Forwarding Unit**: Determines forwarding paths
2. **Forwarding Mux A/B**: Select forwarded or register data
3. **ALU Source Mux**: Immediate vs register
4. **ALU**: Arithmetic/logic operations
5. **Branch Unit**: Branch evaluation
6. **PC Update Logic**: Branch/jump target calculation

**Critical Forwarding Paths**:
```
Forward A/B Mux:
  00: Use rs1_data/rs2_data from ID/EX (no forwarding)
  01: Forward from MEM/WB.wb_data
  10: Forward from EX/MEM.alu_result
```

---

## Stage 4: MEM (Memory Access)

```
    From EX/MEM Register
         │
         ├──► alu_result (address)
         │
         ▼
    ┌─────────┐
    │  DMEM   │  mem_read
    │ (D-Mem) │◄──────────
    └────┬────┘  mem_write
         │         │
         │ read_data
         │         │
         │    write_data
         │    (from rs2_fwd)
         │
         │         ┌───────┐
         ├────────►│       │
         │         │MEM/WB │
         ├────────►│  Reg  │
         │         │       │
         │         └───┬───┘
         │             │
    alu_result         │
    (pass-through)     │
                       ▼
                  To WB Stage

    Signals to MEM/WB:
    - alu_result
    - mem_read_data
    - rd_addr
    - control signals (reg_write, wb_sel)
```

**Memory Operations**:
- **Load**: `mem_read=1`, `mem_write=0` → read_data available
- **Store**: `mem_read=0`, `mem_write=1` → write data to memory
- **Other**: Pass alu_result through

---

## Stage 5: WB (Write Back)

```
    From MEM/WB Register
         │
         ├──► alu_result
         ├──► mem_read_data
         ├──► pc_plus_4
         │
         ▼
    ┌──────────┐  wb_sel [1:0]
    │ WB Mux   │◄────────────
    └────┬─────┘
         │
      wb_data
         │
         └──────────────────────────────────┐
                                            │
    Mux Selection:                          │
    - 00: alu_result                        │
    - 01: mem_read_data                     │
    - 10: pc_plus_4 (JAL/JALR)              │
                                            │
                                            ▼
                                    ┌───────────────┐
                                    │ Register File │ (in ID stage)
                                    │ Write Port    │
                                    └───────────────┘
                                            ▲
                                            │
                                       rd_addr
                                       reg_write
```

**Write-Back Data Sources**:
1. **ALU Result**: Arithmetic/logical operations (ADD, SUB, AND, etc.)
2. **Memory Data**: Load instructions (LW, LH, LB, etc.)
3. **PC + 4**: Jump-and-link instructions (JAL, JALR)

---

## Hazard Control Signals

```
┌─────────────────────────────────────────────────────────────┐
│                  Hazard Detection Unit                      │
├─────────────────────────────────────────────────────────────┤
│ Inputs:                                                     │
│  - IDEX.mem_read                                            │
│  - IDEX.rd                                                  │
│  - IFID.rs1, IFID.rs2                                       │
│                                                             │
│ Outputs:                                                    │
│  - stall_pc        → PC register                            │
│  - stall_IFID      → IF/ID register                         │
│  - bubble_IDEX     → ID/EX register (insert NOP)            │
│                                                             │
│ Condition:                                                  │
│  Load-use hazard = IDEX.mem_read &&                         │
│                    (IDEX.rd == IFID.rs1 ||                  │
│                     IDEX.rd == IFID.rs2) &&                 │
│                    (IDEX.rd != 0)                           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Forwarding Unit                          │
├─────────────────────────────────────────────────────────────┤
│ Inputs:                                                     │
│  - IDEX.rs1, IDEX.rs2                                       │
│  - EXMEM.rd, EXMEM.reg_write                                │
│  - MEMWB.rd, MEMWB.reg_write                                │
│                                                             │
│ Outputs:                                                    │
│  - forward_a [1:0] → EX stage mux A                         │
│  - forward_b [1:0] → EX stage mux B                         │
│                                                             │
│ Logic (for forward_a):                                      │
│  if (EXMEM.reg_write && EXMEM.rd != 0 &&                    │
│      EXMEM.rd == IDEX.rs1)                                  │
│    forward_a = 2'b10  // EX hazard                          │
│  else if (MEMWB.reg_write && MEMWB.rd != 0 &&               │
│            MEMWB.rd == IDEX.rs1 &&                          │
│            !(EXMEM.reg_write && EXMEM.rd == IDEX.rs1))      │
│    forward_a = 2'b01  // MEM hazard                         │
│  else                                                       │
│    forward_a = 2'b00  // No hazard                          │
│                                                             │
│ (Similar logic for forward_b)                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Branch Control Logic                       │
├─────────────────────────────────────────────────────────────┤
│ Location: EX Stage                                          │
│                                                             │
│ Inputs:                                                     │
│  - branch, jump (control signals)                           │
│  - take_branch (from branch_unit)                           │
│  - branch_target, jump_target                               │
│                                                             │
│ Outputs:                                                    │
│  - pc_src (select next PC)                                  │
│  - flush_IFID (clear IF/ID register)                        │
│  - flush_IDEX (clear ID/EX register)                        │
│                                                             │
│ Logic:                                                      │
│  wire pc_change = (branch && take_branch) || jump;         │
│  pc_src = pc_change;                                        │
│  flush_IFID = pc_change;                                    │
│  flush_IDEX = pc_change;                                    │
│                                                             │
│ PC Selection:                                               │
│  pc_next = pc_change ? target : pc_current + 4;             │
│  where target = jump ? jump_target : branch_target          │
└─────────────────────────────────────────────────────────────┘
```

---

## Complete Datapath with All Control Signals

```
                        ┌────── Hazard Detection ──────┐
                        │                              │
    ┌─────┐         ┌───▼───┐         ┌───────┐       │       ┌───────┐         ┌───────┐
    │ PC  │◄────────┤ IF/ID │◄────────┤ ID/EX │◄──────┼───────┤EX/MEM │◄────────┤MEM/WB │
    └──┬──┘ pc_src  └───┬───┘ stall/  └───┬───┘ flush │       └───┬───┘         └───┬───┘
       │                │     flush        │           │           │                 │
       │ pc             │                  │           │           │                 │
       ▼                │                  │           │           │                 │
    ┌─────┐             │                  │           │           │                 │
    │IMEM │             │                  │           │           │                 │
    └──┬──┘             │                  │           │           │                 │
       │ instr          │                  │           │           │                 │
       └────────────────┘                  │           │           │                 │
                                           │           │           │                 │
       ┌────────────────────────────────────┘           │           │                 │
       │                                                │           │                 │
       ▼                                                │           │                 │
    ┌──────┐                                            │           │                 │
    │Decode│                                            │           │                 │
    └───┬──┘                                            │           │                 │
        │                                               │           │                 │
        ▼                                               │           │                 │
    ┌──────┐                                            │           │                 │
    │Ctrl  │                                            │           │                 │
    └───┬──┘                                            │           │                 │
        │                                               │           │                 │
    ┌───▼────┐                                          │           │                 │
    │RegFile │◄─────────────────────────────────────────┼───────────┼─────────────────┘
    └───┬┬───┘ wb_data, rd_addr, reg_write              │           │      (write-back)
        ││                                              │           │
     rs1││rs2                                           │           │
        ││                                              │           │
        │└──────────────────────────┐                   │           │
        │           ┌───────────────┼───────┐           │           │
        │           │               │       │           │           │
        ▼           ▼               ▼       ▼           │           │
      ┌────┐      ┌────┐          ┌────┐ ┌────┐        │           │
      │FwdA│      │FwdB│          │    │ │    │        │           │
      └─┬──┘      └─┬──┘          │ALU │ │    │        │           │
        │           │             │Mux │ │    │        │           │
        │ forward_a │ forward_b   └─┬──┘ │    │        │           │
        │           │               │    │    │        │           │
        └─────┬─────┘               │    │    │        │           │
              │                     ▼    ▼    │        │           │
              │                   ┌────────┐  │        │           │
              └──────────────────►│  ALU   │  │        │           │
                                  └───┬────┘  │        │           │
                                      │       │        │           │
                                  alu_result  │        │           │
                                      │       │        │           │
                                      └───────┼────────┘           │
                                              │                    │
                                              ▼                    │
                                          ┌──────┐                 │
                                          │ DMEM │                 │
                                          └───┬──┘                 │
                                              │                    │
                                          mem_data                 │
                                              │                    │
                                              └────────────────────┘
                                                                   │
                                                                   ▼
                                                               ┌──────┐
                                                               │WB Mux│
                                                               └──────┘

    ┌──────────────────────────────────────────────────────────────────┐
    │  Legend:                                                         │
    │  ────►  Data path                                                │
    │  ◄───   Control signal                                           │
    │  ▼      Flow direction                                           │
    └──────────────────────────────────────────────────────────────────┘
```

---

## Timing Diagram Example: Load-Use Hazard

```
Instruction Sequence:
    lw  x1, 0(x2)    # I1
    add x3, x1, x4   # I2 (depends on x1)

Cycle:   1      2      3      4      5      6      7
       ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┐
I1: lw │  IF  │  ID  │  EX  │ MEM  │  WB  │      │      │
       └──────┴──────┴──────┴──────┴──────┴──────┴──────┘
                                     └─► x1 available here

       ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┐
I2: add│      │  IF  │  ID  │ STALL│  EX  │ MEM  │  WB  │
       └──────┴──────┴──────┴──────┴──────┴──────┴──────┘
                            └─► Hazard detected
                                    └─► Forward from MEM/WB

Hazard Detection (Cycle 3):
  - I1 in EX: mem_read=1, rd=x1
  - I2 in ID: rs1=x1
  - Hazard! Stall IF and ID, insert bubble into EX

Forwarding (Cycle 5):
  - I1 in WB: wb_data contains loaded value
  - I2 in EX: forward_a = 2'b01 (forward from MEM/WB)
```

---

## Timing Diagram Example: Taken Branch

```
Instruction Sequence:
    beq x1, x2, target   # I1
    add x3, x4, x5       # I2 (should be flushed)
    sub x6, x7, x8       # I3 (should be flushed)
target:
    or  x9, x10, x11     # I4 (target instruction)

Cycle:   1      2      3      4      5      6
       ┌──────┬──────┬──────┬──────┬──────┬──────┐
I1: beq│  IF  │  ID  │  EX  │ MEM  │  WB  │      │
       └──────┴──────┴──────┴──────┴──────┴──────┘
                            └─► Branch taken!

       ┌──────┬──────┬──────┬──────┬──────┬──────┐
I2: add│      │  IF  │  ID  │ NOP  │ NOP  │ NOP  │
       └──────┴──────┴──────┴──────┴──────┴──────┘
                            └─► Flushed

       ┌──────┬──────┬──────┬──────┬──────┬──────┐
I3: sub│      │      │  IF  │ NOP  │ NOP  │ NOP  │
       └──────┴──────┴──────┴──────┴──────┴──────┘
                            └─► Flushed

       ┌──────┬──────┬──────┬──────┬──────┬──────┐
I4: or │      │      │      │  IF  │  ID  │  EX  │
       └──────┴──────┴──────┴──────┴──────┴──────┘
                            └─► Correct path

Branch Resolution (Cycle 3):
  - I1 in EX: Branch evaluated, taken
  - PC updated to target
  - flush_IFID = 1, flush_IDEX = 1
  - I2 and I3 converted to NOPs (bubbles)

Penalty: 2 cycles lost
```

---

## Implementation Notes

### Critical Paths
1. **EX Stage**: ALU + Forwarding muxes (longest path)
2. **MEM Stage**: Memory access time
3. **Forwarding Logic**: Must be fast (combinational)

### Synthesis Considerations
1. **Pipeline registers**: Ensure proper reset
2. **Forwarding muxes**: 3-to-1 muxes, optimize for speed
3. **Hazard detection**: Combinational, minimize logic depth
4. **Memory**: Synchronous, single-cycle access

### Debug Signals
Add these outputs to top-level for debugging:
- `debug_pc [31:0]` - Current PC
- `debug_instr [31:0]` - Current instruction in each stage
- `debug_stall` - Stall active
- `debug_flush` - Flush active
- `debug_forward_a [1:0]` - Forward A select
- `debug_forward_b [1:0]` - Forward B select

---

## Next Steps

1. **Review datapath** - Ensure all paths are clear
2. **Create Verilog modules** - Start with pipeline registers
3. **Build incrementally** - Test each stage
4. **Add hazard control** - Forwarding, then stalling
5. **Integration testing** - Full compliance suite

---

**Document Status**: ✅ Complete
**Next**: Begin implementation with pipeline register modules
