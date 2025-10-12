# RISC-V C Extension (RVC) - Compressed Instructions Design

**Status**: Phase 9 - In Progress
**Date**: 2025-10-11
**Target**: RV32IC, RV64IC support

---

## Overview

The C (Compressed) extension adds 16-bit instruction encodings for common operations, reducing code size by 25-30% while maintaining full compatibility with the base ISA. This is achieved by decompressing 16-bit instructions into their 32-bit equivalents during the decode stage.

### Key Benefits
- **25-30% code size reduction** in typical programs
- **50-60% of instructions** can be compressed
- **No performance penalty** (transparent decompression)
- **Binary compatibility** maintained
- **Industry standard** feature for embedded systems

### Design Approach
- **Hardware decompression**: 16-bit instructions expanded to 32-bit in IF stage
- **Transparent to pipeline**: Rest of pipeline sees normal 32-bit instructions
- **PC handling**: Support for 2-byte aligned addresses (16-bit granularity)
- **Mixed code**: Can freely mix 16-bit and 32-bit instructions

---

## RVC Instruction Formats

The C extension defines 9 compressed instruction formats, each 16 bits wide:

### Format Summary

| Format | Name | Fields | Usage |
|--------|------|--------|-------|
| **CR** | Register | funct4[15:12], rd/rs1[11:7], rs2[6:2], op[1:0] | Register-register ops |
| **CI** | Immediate | funct3[15:13], imm[12], rd/rs1[11:7], imm[6:2], op[1:0] | Immediate ops |
| **CSS** | Stack Store | funct3[15:13], imm[12:7], rs2[6:2], op[1:0] | Stack-relative stores |
| **CIW** | Wide Imm | funct3[15:13], imm[12:5], rd'[4:2], op[1:0] | Wide immediate |
| **CL** | Load | funct3[15:13], imm[12:10], rs1'[9:7], imm[6:5], rd'[4:2], op[1:0] | Loads |
| **CS** | Store | funct3[15:13], imm[12:10], rs1'[9:7], imm[6:5], rs2'[4:2], op[1:0] | Stores |
| **CA** | Arithmetic | funct6[15:10], rd'/rs1'[9:7], funct2[6:5], rs2'[4:2], op[1:0] | Arith ops |
| **CB** | Branch | funct3[15:13], offset[12:10], rd'/rs1'[9:7], offset[6:2], op[1:0] | Branches |
| **CJ** | Jump | funct3[15:13], target[12:2], op[1:0] | Jumps |

**Note**: Primed registers (rd', rs1', rs2') are limited to x8-x15 (3-bit encoding)

### Quadrants

16-bit instructions are organized into 4 quadrants based on bits [1:0]:

| Quadrant | op[1:0] | Description |
|----------|---------|-------------|
| Q0 | 00 | Loads, stores, arithmetic |
| Q1 | 01 | Control flow, arithmetic |
| Q2 | 10 | Misc operations |
| Q3 | 11 | Reserved (used to identify 32-bit instructions) |

**Key**: Instructions with op[1:0] = 11 are 32-bit instructions (not compressed)

---

## RVC Instruction Set

### Quadrant 0 (op = 00)

| Encoding | funct3 | Instruction | Expansion | Description |
|----------|--------|-------------|-----------|-------------|
| 000 | 000 | C.ADDI4SPN | ADDI rd', x2, nzuimm | Add immediate to SP |
| 000 | 010 | C.LW | LW rd', offset(rs1') | Load word |
| 000 | 011 | C.LD (RV64) | LD rd', offset(rs1') | Load doubleword |
| 000 | 110 | C.SW | SW rs2', offset(rs1') | Store word |
| 000 | 111 | C.SD (RV64) | SD rs2', offset(rs1') | Store doubleword |

### Quadrant 1 (op = 01)

| Encoding | funct3 | Instruction | Expansion | Description |
|----------|--------|-------------|-----------|-------------|
| 01 | 000 | C.NOP/C.ADDI | ADDI rd, rd, nzimm | NOP or add immediate |
| 01 | 001 | C.JAL (RV32) | JAL x1, offset | Jump and link |
| 01 | 001 | C.ADDIW (RV64) | ADDIW rd, rd, imm | Add word immediate |
| 01 | 010 | C.LI | ADDI rd, x0, imm | Load immediate |
| 01 | 011 | C.ADDI16SP | ADDI x2, x2, nzimm | Add to SP (x2 only) |
| 01 | 011 | C.LUI | LUI rd, nzimm | Load upper immediate |
| 01 | 100 | C.SRLI | SRLI rd', rd', shamt | Shift right logical |
| 01 | 100 | C.SRAI | SRAI rd', rd', shamt | Shift right arithmetic |
| 01 | 100 | C.ANDI | ANDI rd', rd', imm | AND immediate |
| 01 | 100 | C.SUB | SUB rd', rd', rs2' | Subtract |
| 01 | 100 | C.XOR | XOR rd', rd', rs2' | XOR |
| 01 | 100 | C.OR | OR rd', rd', rs2' | OR |
| 01 | 100 | C.AND | AND rd', rd', rs2' | AND |
| 01 | 100 | C.SUBW (RV64) | SUBW rd', rd', rs2' | Subtract word |
| 01 | 100 | C.ADDW (RV64) | ADDW rd', rd', rs2' | Add word |
| 01 | 101 | C.J | JAL x0, offset | Jump |
| 01 | 110 | C.BEQZ | BEQ rs1', x0, offset | Branch if zero |
| 01 | 111 | C.BNEZ | BNE rs1', x0, offset | Branch if not zero |

### Quadrant 2 (op = 10)

| Encoding | funct3 | Instruction | Expansion | Description |
|----------|--------|-------------|-----------|-------------|
| 10 | 000 | C.SLLI | SLLI rd, rd, shamt | Shift left logical |
| 10 | 010 | C.LWSP | LW rd, offset(x2) | Load word from SP |
| 10 | 011 | C.LDSP (RV64) | LD rd, offset(x2) | Load doubleword from SP |
| 10 | 100 | C.JR | JALR x0, 0(rs1) | Jump register |
| 10 | 100 | C.MV | ADD rd, x0, rs2 | Move (copy register) |
| 10 | 100 | C.EBREAK | EBREAK | Breakpoint |
| 10 | 100 | C.JALR | JALR x1, 0(rs1) | Jump and link register |
| 10 | 100 | C.ADD | ADD rd, rd, rs2 | Add |
| 10 | 110 | C.SWSP | SW rs2, offset(x2) | Store word to SP |
| 10 | 111 | C.SDSP (RV64) | SD rs2, offset(x2) | Store doubleword to SP |

**Total Instructions**:
- **RV32C**: ~36 instructions
- **RV64C**: ~46 instructions (includes RV64-specific variants)

---

## Immediate Encoding

Immediates in compressed instructions are encoded in non-contiguous fields to simplify hardware decoding.

### C.ADDI4SPN (CIW-type)
```
nzuimm[9:2] = {inst[10:7], inst[12:11], inst[5], inst[6]}
Scaled by 4, zero-extended
```

### C.LW/C.SW (CL/CS-type)
```
offset[6:2] = {inst[5], inst[12:10], inst[6]}
Scaled by 4, zero-extended
```

### C.LD/C.SD (CL/CS-type, RV64)
```
offset[7:3] = {inst[6:5], inst[12:10]}
Scaled by 8, zero-extended
```

### C.ADDI/C.LI (CI-type)
```
imm[5:0] = {inst[12], inst[6:2]}
Sign-extended from bit 5
```

### C.LUI (CI-type)
```
nzimm[17:12] = {inst[12], inst[6:2]}
Sign-extended to 20 bits, then shifted left by 12
```

### C.ADDI16SP (CI-type)
```
nzimm[9:4] = {inst[12], inst[4:3], inst[5], inst[2], inst[6]}
Scaled by 16, sign-extended
```

### C.J/C.JAL (CJ-type)
```
offset[11:1] = {inst[12], inst[8], inst[10:9], inst[6], inst[7], inst[2], inst[11], inst[5:3]}
Sign-extended from bit 11, scaled by 2
```

### C.BEQZ/C.BNEZ (CB-type)
```
offset[8:1] = {inst[12], inst[6:5], inst[2], inst[11:10], inst[4:3]}
Sign-extended from bit 8, scaled by 2
```

---

## Implementation Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Instruction Fetch (IF)                  │
│  ┌────────────────┐         ┌─────────────────────────┐     │
│  │ Instruction    │ 16/32   │  RVC Decompressor       │ 32  │
│  │ Memory         │─────────▶  (rvc_decoder.v)        │─────┤
│  │                │  bits   │  - Detect compressed    │     │
│  └────────────────┘         │  - Expand to 32-bit     │     │
│         ▲                   └─────────────────────────┘     │
│         │ PC (2-byte aligned)                               │
│  ┌──────┴───────┐                                           │
│  │ PC Register  │  Increment by 2 or 4                      │
│  │ (pc.v)       │  based on instruction size                │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
                              │ 32-bit instruction
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Decode Stage (ID)                          │
│  Processes normal 32-bit instructions                        │
│  (No changes needed - transparent)                           │
└─────────────────────────────────────────────────────────────┘
```

### Key Changes Required

1. **RVC Decoder Module** (NEW)
   - Input: 16-bit compressed instruction
   - Output: 32-bit expanded instruction
   - Combinational logic
   - ~500-800 lines

2. **Instruction Fetch Stage** (MODIFY)
   - Fetch 32 bits (to support unaligned compressed instructions)
   - Select lower/upper 16 bits based on PC[1]
   - Detect if instruction is compressed (inst[1:0] != 11)
   - Route through RVC decoder if compressed

3. **PC Logic** (MODIFY)
   - Support 2-byte alignment (PC can be even, not just multiple of 4)
   - Increment by +2 for compressed, +4 for normal
   - Handle PC[1] for unaligned access

4. **Instruction Memory** (MODIFY)
   - Support half-word access
   - Allow reading from non-4-byte-aligned addresses

---

## Module Design

### 1. RVC Decoder (rvc_decoder.v)

**Interface**:
```verilog
module rvc_decoder #(
  parameter XLEN = 32
) (
  input  [15:0] compressed_instr,    // 16-bit compressed instruction
  input         is_rv64,              // RV64 mode (from config)
  output [31:0] decompressed_instr,  // 32-bit expanded instruction
  output        illegal_instr         // Illegal compressed instruction
);
```

**Functionality**:
- Decode compressed instruction format
- Extract fields (opcode, funct3, registers, immediates)
- Generate 32-bit instruction encoding
- Flag illegal compressed instructions

**Key Decoding Logic**:
```verilog
// Detect quadrant
wire [1:0] quadrant = compressed_instr[1:0];
wire [2:0] funct3   = compressed_instr[15:13];

// Extract register fields
wire [4:0] rd  = compressed_instr[11:7];
wire [4:0] rs2 = compressed_instr[6:2];
wire [2:0] rd_p  = compressed_instr[4:2];  // rd'  -> x8-x15
wire [2:0] rs1_p = compressed_instr[9:7];  // rs1' -> x8-x15
wire [2:0] rs2_p = compressed_instr[4:2];  // rs2' -> x8-x15

// Expand primed registers (add 8 to get actual register number)
wire [4:0] rd_exp  = {2'b01, rd_p};   // 3'b000 -> 5'b01000 (x8)
wire [4:0] rs1_exp = {2'b01, rs1_p};
wire [4:0] rs2_exp = {2'b01, rs2_p};
```

### 2. Modified Instruction Fetch

**Changes to rv32i_core_pipelined.v**:
```verilog
// Fetch 32 bits to handle unaligned compressed instructions
wire [31:0] fetched_data;
wire [15:0] instr_lower = pc[1] ? fetched_data[31:16] : fetched_data[15:0];
wire [15:0] instr_upper = fetched_data[31:16];

// Detect compressed instruction
wire is_compressed = (instr_lower[1:0] != 2'b11);

// Decompress if needed
wire [31:0] instr_decompressed;
wire illegal_c_instr;

rvc_decoder rvc_dec (
  .compressed_instr(instr_lower),
  .is_rv64(XLEN == 64),
  .decompressed_instr(instr_decompressed),
  .illegal_instr(illegal_c_instr)
);

// Select instruction
wire [31:0] instr_to_decode = is_compressed ? instr_decompressed :
                                               (pc[1] ? fetched_data[31:0] : fetched_data);

// PC increment
wire [XLEN-1:0] pc_increment = is_compressed ? 2 : 4;
```

### 3. Modified PC Logic

**Changes to pc.v**:
```verilog
// Remove 4-byte alignment restriction
// PC can now be 2-byte aligned

// Normal increment (when not branching/jumping)
wire [XLEN-1:0] pc_next_seq = pc_current + pc_increment;

// Branch/jump targets can also be 2-byte aligned
// (No changes needed - already support arbitrary addresses)
```

### 4. Modified Instruction Memory

**Changes to instruction_memory.v**:
```verilog
// Support reading at 2-byte aligned addresses
// Fetch 32 bits to support unaligned compressed instructions

// Address calculation
wire [ADDR_WIDTH-1:0] word_addr = pc[ADDR_WIDTH-1:2];  // Word-aligned base
wire half_select = pc[1];  // Select upper/lower half-word

// Read full word
assign instr = {memory[word_addr*4 + 3],
                memory[word_addr*4 + 2],
                memory[word_addr*4 + 1],
                memory[word_addr*4 + 0]};
```

---

## Verification Strategy

### Unit Tests

1. **RVC Decoder Test** (tb/unit/tb_rvc_decoder.v)
   - Test all 40+ compressed instructions
   - Verify correct expansion to 32-bit
   - Check immediate encoding
   - Test illegal instruction detection

### Integration Tests

2. **Mixed Code Test** (tests/asm/test_rvc_mixed.s)
   - Mix compressed and normal instructions
   - Test all instruction types
   - Verify PC alignment handling

3. **Code Density Test** (tests/asm/test_rvc_density.s)
   - Same program in RVC and RVI
   - Measure code size reduction
   - Verify identical behavior

4. **Jump/Branch Test** (tests/asm/test_rvc_control.s)
   - Test C.J, C.JAL, C.JR, C.JALR
   - Test C.BEQZ, C.BNEZ
   - Test mixed 2/4-byte aligned targets

5. **Stack Operations** (tests/asm/test_rvc_stack.s)
   - Test C.LWSP, C.SWSP
   - Test C.ADDI4SPN, C.ADDI16SP

### Compliance Tests

6. **Official RISC-V C Extension Tests**
   - Run rv32uc-p-* tests
   - Run rv64uc-p-* tests (if RV64 enabled)

---

## Register Mapping Reference

### Compressed Register Encoding

Compressed instructions using 3-bit register fields (rd', rs1', rs2') map to x8-x15:

| Binary | Decimal | Compressed | Actual Register | ABI Name |
|--------|---------|------------|-----------------|----------|
| 000 | 0 | c.x0 | x8 | s0/fp |
| 001 | 1 | c.x1 | x9 | s1 |
| 010 | 2 | c.x2 | x10 | a0 |
| 011 | 3 | c.x3 | x11 | a1 |
| 100 | 4 | c.x4 | x12 | a2 |
| 101 | 5 | c.x5 | x13 | a3 |
| 110 | 6 | c.x6 | x14 | a4 |
| 111 | 7 | c.x7 | x15 | a5 |

**Rationale**: These are the most frequently used registers (frame pointer, saved register, argument registers).

---

## Design Decisions

### 1. Decompression Location: IF Stage
- **Pro**: Rest of pipeline unchanged
- **Pro**: Simpler control logic
- **Con**: Slight area increase for decompressor

**Alternative**: Decode in ID stage
- **Con**: Would require changes throughout pipeline
- **Con**: More complex hazard detection

**Decision**: Decompress in IF stage ✓

### 2. PC Increment Handling
- Detect instruction size in IF stage
- Pass increment amount to PC logic
- Branch/jump targets already support arbitrary alignment

### 3. Instruction Memory Access
- Fetch 32 bits always
- Select appropriate 16 bits based on PC[1]
- Allows unaligned compressed instructions

### 4. Illegal Instruction Handling
- RVC decoder outputs illegal_instr flag
- Merge with existing illegal instruction detection
- Raise exception in decode stage

---

## Testing Milestones

- [ ] **Milestone 1**: RVC decoder implemented and unit tested
- [ ] **Milestone 2**: IF stage modified, PC logic updated
- [ ] **Milestone 3**: Integration test passes
- [ ] **Milestone 4**: All RVC instructions tested
- [ ] **Milestone 5**: Code density verified (25-30% reduction)
- [ ] **Milestone 6**: Official compliance tests pass

---

## Expected Results

### Code Size Reduction
- **Target**: 25-30% reduction in typical programs
- **Measurement**: Compare .text section size with/without RVC

### Performance Impact
- **Target**: No CPI degradation
- **Measurement**: Cycle counts should be identical for same logical program

### Compliance
- **Target**: 100% pass rate on rv32uc/rv64uc tests
- **Verification**: Official RISC-V compliance suite

---

## Implementation Schedule

| Phase | Task | Estimated Effort |
|-------|------|------------------|
| **Phase 1** | Design documentation (this document) | ✅ Complete |
| **Phase 2** | RVC decoder implementation | 4-6 hours |
| **Phase 3** | IF stage modifications | 3-4 hours |
| **Phase 4** | PC and memory updates | 2-3 hours |
| **Phase 5** | Integration and testing | 4-6 hours |
| **Phase 6** | Verification and documentation | 2-3 hours |
| **Total** | | **15-22 hours** (2-3 days) |

---

## References

- RISC-V ISA Manual, Volume I: User-Level ISA, Chapter 16 (C Extension)
- RISC-V Compressed Instruction Set Specification v2.0
- https://github.com/riscv/riscv-isa-manual
- https://five-embeddev.com/riscv-user-isa-manual/ (C extension chapter)

---

**Next Steps**: Proceed to RVC decoder implementation
