# Control Signals Reference

This document describes all control signals used in the RV1 single-cycle processor.

## Control Signal Summary

The control unit (`rtl/core/control.v`) generates the following control signals based on the instruction opcode and function fields.

| Signal | Width | Description | Values |
|--------|-------|-------------|--------|
| `reg_write` | 1 | Enable register file write | 0=No write, 1=Write to rd |
| `mem_read` | 1 | Enable memory read | 0=No read, 1=Read from memory |
| `mem_write` | 1 | Enable memory write | 0=No write, 1=Write to memory |
| `branch` | 1 | Instruction is a branch | 0=Not branch, 1=Branch |
| `jump` | 1 | Instruction is a jump | 0=Not jump, 1=Jump (JAL/JALR) |
| `alu_control` | 4 | ALU operation select | See ALU Operations table |
| `alu_src` | 1 | ALU operand B source | 0=rs2, 1=immediate |
| `wb_sel` | 2 | Write-back data source | 00=ALU, 01=MEM, 10=PC+4 |
| `imm_sel` | 3 | Immediate format select | See Immediate Formats table |

## ALU Operations

The `alu_control` signal (4 bits) selects the ALU operation:

| `alu_control` | Operation | Description | Used By |
|---------------|-----------|-------------|---------|
| `4'b0000` | ADD | operand_a + operand_b | ADD, ADDI, LOAD, STORE, LUI, AUIPC |
| `4'b0001` | SUB | operand_a - operand_b | SUB, Branch comparison |
| `4'b0010` | SLL | Shift left logical | SLL, SLLI |
| `4'b0011` | SLT | Set less than (signed) | SLT, SLTI |
| `4'b0100` | SLTU | Set less than (unsigned) | SLTU, SLTIU |
| `4'b0101` | XOR | Bitwise XOR | XOR, XORI |
| `4'b0110` | SRL | Shift right logical | SRL, SRLI |
| `4'b0111` | SRA | Shift right arithmetic | SRA, SRAI |
| `4'b1000` | OR | Bitwise OR | OR, ORI |
| `4'b1001` | AND | Bitwise AND | AND, ANDI |

## Immediate Format Selection

The `imm_sel` signal (3 bits) determines which immediate format to use:

| `imm_sel` | Format | Encoding | Used By |
|-----------|--------|----------|---------|
| `3'b000` | I-type | `{{20{inst[31]}}, inst[31:20]}` | ADDI, SLTI, XORI, ORI, ANDI, SLLI, SRLI, SRAI, LW, LH, LB, LBU, LHU, JALR |
| `3'b001` | S-type | `{{20{inst[31]}}, inst[31:25], inst[11:7]}` | SW, SH, SB |
| `3'b010` | B-type | `{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| `3'b011` | U-type | `{inst[31:12], 12'b0}` | LUI, AUIPC |
| `3'b100` | J-type | `{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` | JAL |

## Write-Back Selection

The `wb_sel` signal (2 bits) selects the data to write back to the register file:

| `wb_sel` | Source | Description | Used By |
|----------|--------|-------------|---------|
| `2'b00` | ALU result | Result from ALU computation | R-type, I-type ALU, LUI, AUIPC |
| `2'b01` | Memory data | Data read from memory | LW, LH, LB, LBU, LHU |
| `2'b10` | PC + 4 | Return address | JAL, JALR |
| `2'b11` | (unused) | Reserved | None |

## Control Signal Truth Table

### R-Type Instructions (OP = 0110011)

Instructions: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write result to rd |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| `alu_src` | 0 | Use rs2 as operand B |
| `wb_sel` | 00 | Write back ALU result |
| `alu_control` | * | Determined by funct3 and funct7 |
| `imm_sel` | X | Don't care (not used) |

### I-Type ALU Instructions (OP-IMM = 0010011)

Instructions: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write result to rd |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| `alu_src` | 1 | Use immediate as operand B |
| `wb_sel` | 00 | Write back ALU result |
| `alu_control` | * | Determined by funct3 and funct7 |
| `imm_sel` | 000 | I-type immediate |

### Load Instructions (LOAD = 0000011)

Instructions: LW, LH, LB, LBU, LHU

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write loaded data to rd |
| `mem_read` | 1 | Read from memory |
| `mem_write` | 0 | No write |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| `alu_src` | 1 | Use immediate (offset) |
| `wb_sel` | 01 | Write back memory data |
| `alu_control` | 0000 | ADD (rs1 + offset) |
| `imm_sel` | 000 | I-type immediate |

### Store Instructions (STORE = 0100011)

Instructions: SW, SH, SB

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 0 | No register write |
| `mem_read` | 0 | No read |
| `mem_write` | 1 | Write to memory |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| `alu_src` | 1 | Use immediate (offset) |
| `wb_sel` | XX | Don't care (no write-back) |
| `alu_control` | 0000 | ADD (rs1 + offset) |
| `imm_sel` | 001 | S-type immediate |

### Branch Instructions (BRANCH = 1100011)

Instructions: BEQ, BNE, BLT, BGE, BLTU, BGEU

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 0 | No register write |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 1 | Branch instruction |
| `jump` | 0 | Not a jump |
| `alu_src` | 0 | Use rs2 (for comparison) |
| `wb_sel` | XX | Don't care (no write-back) |
| `alu_control` | 0001 | SUB (for comparison) |
| `imm_sel` | 010 | B-type immediate |

**Note**: Branch taken/not-taken is determined by the branch unit based on funct3 and comparison result.

### JAL (JAL = 1101111)

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write return address to rd |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 1 | Jump instruction |
| `alu_src` | X | Don't care |
| `wb_sel` | 10 | Write back PC+4 |
| `alu_control` | X | Don't care |
| `imm_sel` | 100 | J-type immediate |

### JALR (JALR = 1100111)

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write return address to rd |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 1 | Jump instruction |
| `alu_src` | 1 | Use immediate |
| `wb_sel` | 10 | Write back PC+4 |
| `alu_control` | 0000 | ADD (rs1 + offset) |
| `imm_sel` | 000 | I-type immediate |

### LUI (LUI = 0110111)

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write to rd |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| `alu_src` | 1 | Use immediate |
| `wb_sel` | 00 | Write back ALU result |
| `alu_control` | 0000 | ADD (0 + imm) |
| `imm_sel` | 011 | U-type immediate |

**Note**: For LUI, operand_a is forced to 0 in the datapath, so ALU computes 0 + imm_u.

### AUIPC (AUIPC = 0010111)

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 1 | Write to rd |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| `alu_src` | 1 | Use immediate |
| `wb_sel` | 00 | Write back ALU result |
| `alu_control` | 0000 | ADD (PC + imm) |
| `imm_sel` | 011 | U-type immediate |

**Note**: For AUIPC, operand_a is set to PC in the datapath, so ALU computes PC + imm_u.

### FENCE (FENCE = 0001111)

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 0 | No-op in this implementation |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| All others | X | Don't care |

### ECALL/EBREAK (SYSTEM = 1110011)

| Signal | Value | Notes |
|--------|-------|-------|
| `reg_write` | 0 | No-op (future: trigger trap) |
| `mem_read` | 0 | No memory access |
| `mem_write` | 0 | No memory access |
| `branch` | 0 | Not a branch |
| `jump` | 0 | Not a jump |
| All others | X | Don't care |

## Datapath Control Flow

### Instruction Fetch (IF)
1. PC provides address to instruction memory
2. Instruction memory outputs 32-bit instruction

### Instruction Decode (ID)
1. Decoder extracts opcode, rd, rs1, rs2, funct3, funct7
2. Decoder generates all immediate formats
3. Control unit generates control signals based on opcode and funct fields
4. Register file reads rs1 and rs2

### Execute (EX)
1. Immediate selector chooses correct immediate based on `imm_sel`
2. ALU operand muxes select sources based on `alu_src` and instruction type
3. ALU performs operation based on `alu_control`
4. Branch unit evaluates branch condition

### Memory (MEM)
1. If `mem_read` = 1, data memory reads from address (ALU result)
2. If `mem_write` = 1, data memory writes rs2_data to address (ALU result)
3. Memory operation size determined by funct3

### Write-Back (WB)
1. Write-back mux selects data based on `wb_sel`:
   - 00: ALU result
   - 01: Memory read data
   - 10: PC + 4 (for JAL/JALR)
2. If `reg_write` = 1, selected data written to rd

### PC Update
1. If branch taken (determined by branch unit): PC ← PC + imm_b
2. If jump and JALR: PC ← (rs1 + imm_i) & 0xFFFFFFFE
3. If jump and JAL: PC ← PC + imm_j
4. Otherwise: PC ← PC + 4

## Implementation Notes

1. **Special operand handling**:
   - LUI: operand_a forced to 0 (handled in rv32i_core.v)
   - AUIPC: operand_a set to PC (handled in rv32i_core.v)

2. **Branch vs Jump**:
   - Branches are conditional (depend on branch unit output)
   - Jumps are unconditional (always taken)

3. **Memory access**:
   - funct3 determines access size and sign extension
   - Address alignment not enforced (assumes aligned access)

4. **Don't care signals**:
   - Marked with X in truth tables
   - Implementation sets to default (typically 0)

## Quick Reference: Opcode to Control Signals

| Opcode | Name | reg_write | mem_read | mem_write | branch | jump | alu_src | wb_sel |
|--------|------|-----------|----------|-----------|--------|------|---------|--------|
| 0110111 | LUI | 1 | 0 | 0 | 0 | 0 | 1 | 00 |
| 0010111 | AUIPC | 1 | 0 | 0 | 0 | 0 | 1 | 00 |
| 1101111 | JAL | 1 | 0 | 0 | 0 | 1 | X | 10 |
| 1100111 | JALR | 1 | 0 | 0 | 0 | 1 | 1 | 10 |
| 1100011 | BRANCH | 0 | 0 | 0 | 1 | 0 | 0 | XX |
| 0000011 | LOAD | 1 | 1 | 0 | 0 | 0 | 1 | 01 |
| 0100011 | STORE | 0 | 0 | 1 | 0 | 0 | 1 | XX |
| 0010011 | OP-IMM | 1 | 0 | 0 | 0 | 0 | 1 | 00 |
| 0110011 | OP | 1 | 0 | 0 | 0 | 0 | 0 | 00 |
| 0001111 | FENCE | 0 | 0 | 0 | 0 | 0 | X | XX |
| 1110011 | SYSTEM | 0 | 0 | 0 | 0 | 0 | X | XX |
