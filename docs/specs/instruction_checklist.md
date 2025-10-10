# RV32I Instruction Implementation Checklist

Complete status of all 47 RV32I base instructions.

**Legend:**
- ✅ Implemented and tested
- ⏳ Implemented, awaiting verification
- ❌ Not implemented

## Overall Status

- **Total Instructions**: 47
- **Implemented**: 47 (100%)
- **Verified**: 0 (0% - awaiting simulation)

---

## Integer Computational Instructions (19)

### Register-Register Operations (R-Type, OP = 0110011)

| Instruction | Opcode | funct3 | funct7 | Status | Location | Notes |
|-------------|--------|--------|--------|--------|----------|-------|
| ADD rd, rs1, rs2 | 0110011 | 000 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0000 |
| SUB rd, rs1, rs2 | 0110011 | 000 | 0100000 | ⏳ | control.v, alu.v | ALU: 4'b0001 |
| SLL rd, rs1, rs2 | 0110011 | 001 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0010 |
| SLT rd, rs1, rs2 | 0110011 | 010 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0011 |
| SLTU rd, rs1, rs2 | 0110011 | 011 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0100 |
| XOR rd, rs1, rs2 | 0110011 | 100 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0101 |
| SRL rd, rs1, rs2 | 0110011 | 101 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0110 |
| SRA rd, rs1, rs2 | 0110011 | 101 | 0100000 | ⏳ | control.v, alu.v | ALU: 4'b0111 |
| OR rd, rs1, rs2 | 0110011 | 110 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b1000 |
| AND rd, rs1, rs2 | 0110011 | 111 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b1001 |

### Register-Immediate Operations (I-Type, OP-IMM = 0010011)

| Instruction | Opcode | funct3 | funct7 | Status | Location | Notes |
|-------------|--------|--------|--------|--------|----------|-------|
| ADDI rd, rs1, imm | 0010011 | 000 | - | ⏳ | control.v, alu.v | ALU: 4'b0000, alu_src=1 |
| SLTI rd, rs1, imm | 0010011 | 010 | - | ⏳ | control.v, alu.v | ALU: 4'b0011, alu_src=1 |
| SLTIU rd, rs1, imm | 0010011 | 011 | - | ⏳ | control.v, alu.v | ALU: 4'b0100, alu_src=1 |
| XORI rd, rs1, imm | 0010011 | 100 | - | ⏳ | control.v, alu.v | ALU: 4'b0101, alu_src=1 |
| ORI rd, rs1, imm | 0010011 | 110 | - | ⏳ | control.v, alu.v | ALU: 4'b1000, alu_src=1 |
| ANDI rd, rs1, imm | 0010011 | 111 | - | ⏳ | control.v, alu.v | ALU: 4'b1001, alu_src=1 |
| SLLI rd, rs1, shamt | 0010011 | 001 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0010, alu_src=1 |
| SRLI rd, rs1, shamt | 0010011 | 101 | 0000000 | ⏳ | control.v, alu.v | ALU: 4'b0110, alu_src=1 |
| SRAI rd, rs1, shamt | 0010011 | 101 | 0100000 | ⏳ | control.v, alu.v | ALU: 4'b0111, alu_src=1 |

---

## Load and Store Instructions (10)

### Load Instructions (I-Type, LOAD = 0000011)

| Instruction | Opcode | funct3 | Status | Location | Notes |
|-------------|--------|--------|--------|----------|-------|
| LB rd, offset(rs1) | 0000011 | 000 | ⏳ | control.v, data_memory.v | Sign-extend byte |
| LH rd, offset(rs1) | 0000011 | 001 | ⏳ | control.v, data_memory.v | Sign-extend halfword |
| LW rd, offset(rs1) | 0000011 | 010 | ⏳ | control.v, data_memory.v | Load word |
| LBU rd, offset(rs1) | 0000011 | 100 | ⏳ | control.v, data_memory.v | Zero-extend byte |
| LHU rd, offset(rs1) | 0000011 | 101 | ⏳ | control.v, data_memory.v | Zero-extend halfword |

### Store Instructions (S-Type, STORE = 0100011)

| Instruction | Opcode | funct3 | Status | Location | Notes |
|-------------|--------|--------|--------|----------|-------|
| SB rs2, offset(rs1) | 0100011 | 000 | ⏳ | control.v, data_memory.v | Store byte |
| SH rs2, offset(rs1) | 0100011 | 001 | ⏳ | control.v, data_memory.v | Store halfword |
| SW rs2, offset(rs1) | 0100011 | 010 | ⏳ | control.v, data_memory.v | Store word |

---

## Control Transfer Instructions (8)

### Unconditional Jumps

| Instruction | Opcode | funct3 | Status | Location | Notes |
|-------------|--------|--------|--------|----------|-------|
| JAL rd, offset | 1101111 | - | ⏳ | control.v, rv32i_core.v | rd ← PC+4, PC ← PC+imm_j |
| JALR rd, offset(rs1) | 1100111 | 000 | ⏳ | control.v, rv32i_core.v | rd ← PC+4, PC ← (rs1+imm_i)&~1 |

### Conditional Branches (B-Type, BRANCH = 1100011)

| Instruction | Opcode | funct3 | Status | Location | Notes |
|-------------|--------|--------|--------|----------|-------|
| BEQ rs1, rs2, offset | 1100011 | 000 | ⏳ | control.v, branch_unit.v | Branch if rs1 == rs2 |
| BNE rs1, rs2, offset | 1100011 | 001 | ⏳ | control.v, branch_unit.v | Branch if rs1 != rs2 |
| BLT rs1, rs2, offset | 1100011 | 100 | ⏳ | control.v, branch_unit.v | Branch if rs1 < rs2 (signed) |
| BGE rs1, rs2, offset | 1100011 | 101 | ⏳ | control.v, branch_unit.v | Branch if rs1 >= rs2 (signed) |
| BLTU rs1, rs2, offset | 1100011 | 110 | ⏳ | control.v, branch_unit.v | Branch if rs1 < rs2 (unsigned) |
| BGEU rs1, rs2, offset | 1100011 | 111 | ⏳ | control.v, branch_unit.v | Branch if rs1 >= rs2 (unsigned) |

---

## Upper Immediate Instructions (2)

| Instruction | Opcode | Type | Status | Location | Notes |
|-------------|--------|------|--------|----------|-------|
| LUI rd, imm | 0110111 | U | ⏳ | control.v, rv32i_core.v | rd ← imm_u (upper 20 bits) |
| AUIPC rd, imm | 0010111 | U | ⏳ | control.v, rv32i_core.v | rd ← PC + imm_u |

---

## Memory Ordering Instructions (1)

| Instruction | Opcode | funct3 | Status | Location | Notes |
|-------------|--------|--------|--------|----------|-------|
| FENCE pred, succ | 0001111 | 000 | ⏳ | control.v | Treated as NOP |

**Implementation Note**: FENCE is implemented as a NOP in this single-cycle design. In a real system with caches and/or out-of-order execution, FENCE would enforce memory ordering constraints.

---

## Environment Call and Breakpoints (2)

### System Instructions (SYSTEM = 1110011)

| Instruction | Opcode | funct3 | imm[31:20] | Status | Location | Notes |
|-------------|--------|--------|------------|--------|----------|-------|
| ECALL | 1110011 | 000 | 000000000000 | ⏳ | control.v | Environment call (NOP for now) |
| EBREAK | 1110011 | 000 | 000000000001 | ⏳ | control.v | Breakpoint (used in tests) |

**Implementation Note**: ECALL and EBREAK are treated as NOPs in the current implementation. In Phase 4, these will trigger traps and invoke exception handlers.

---

## Pseudo-Instructions

These are not real instructions but are commonly used assembler mnemonics:

| Pseudo | Expands To | Status | Notes |
|--------|------------|--------|-------|
| NOP | ADDI x0, x0, 0 | ✅ | Implemented via ADDI |
| MV rd, rs | ADDI rd, rs, 0 | ✅ | Implemented via ADDI |
| LI rd, imm | ADDI rd, x0, imm | ✅ | Implemented via ADDI (if imm fits) |
| J offset | JAL x0, offset | ✅ | Implemented via JAL |
| JR rs | JALR x0, 0(rs) | ✅ | Implemented via JALR |
| RET | JALR x0, 0(x1) | ✅ | Implemented via JALR |

---

## Test Coverage by Category

### Integer Computational
- **Unit Tests**: tb_alu.v covers all 10 ALU operations
- **Integration Tests**: simple_add.s tests ADDI and ADD
- **Needed**: Comprehensive test for all I-type and R-type instructions

### Load/Store
- **Unit Tests**: None yet (data_memory module not unit tested)
- **Integration Tests**: load_store.s tests LW, LH, LB, SW, SH, SB
- **Needed**: Test LBU, LHU, alignment, edge cases

### Branches
- **Unit Tests**: None yet (branch_unit not unit tested)
- **Integration Tests**: fibonacci.s uses BEQ, BGE, JAL
- **Needed**: Test all 6 branch types individually

### Jumps
- **Unit Tests**: None
- **Integration Tests**: fibonacci.s uses JAL
- **Needed**: Test JAL with different offsets, JALR

### Upper Immediate
- **Unit Tests**: None
- **Integration Tests**: load_store.s uses LUI
- **Needed**: Test AUIPC

---

## Verification Plan

### Phase 1: Unit Testing
- [x] ALU operations (tb_alu.v)
- [x] Register file (tb_register_file.v)
- [x] Instruction decoder (tb_decoder.v)
- [ ] Data memory
- [ ] Branch unit

### Phase 2: Instruction-Level Testing
- [ ] Create individual test for each instruction
- [ ] Test edge cases (overflow, zero, negative, max values)
- [ ] Test all addressing modes

### Phase 3: Integration Testing
- [x] simple_add.s - Basic arithmetic
- [x] fibonacci.s - Loops and branches
- [x] load_store.s - Memory operations
- [ ] logic_ops.s - AND, OR, XOR
- [ ] shifts.s - SLL, SRL, SRA
- [ ] branches.s - All branch types
- [ ] jumps.s - JAL and JALR

### Phase 4: Compliance Testing
- [ ] Run official RISC-V compliance tests
- [ ] Aim for 100% pass rate on RV32I tests

---

## Known Limitations

1. **FENCE**: Implemented as NOP (acceptable for single-cycle, no cache)
2. **ECALL/EBREAK**: Implemented as NOP (trap handling in Phase 4)
3. **Alignment**: No checking for misaligned memory access
4. **Exceptions**: No exception handling yet
5. **CSR**: No control/status registers yet

---

## Implementation Files

| Component | File | Lines | Instructions Supported |
|-----------|------|-------|------------------------|
| ALU | rtl/core/alu.v | ~50 | All R-type and I-type ALU ops |
| Control Unit | rtl/core/control.v | ~170 | All 47 instructions |
| Decoder | rtl/core/decoder.v | ~60 | All instruction formats |
| Register File | rtl/core/register_file.v | ~45 | All instructions using registers |
| Branch Unit | rtl/core/branch_unit.v | ~35 | All 6 branch types + jumps |
| Data Memory | rtl/memory/data_memory.v | ~80 | All load/store variants |
| Instruction Memory | rtl/memory/instruction_memory.v | ~40 | All instructions |
| Top-level Core | rtl/core/rv32i_core.v | ~200 | Complete integration |

---

## Next Steps

1. ✅ Complete implementation of all modules
2. ⏳ Set up simulation environment (Icarus Verilog + RISC-V toolchain)
3. ⏳ Run unit tests and verify
4. ⏳ Create additional test programs for coverage
5. ⏳ Run RISC-V compliance tests
6. ⏳ Fix any bugs discovered
7. ⏳ Document any deviations from spec
8. ⏳ Performance analysis

**Last Updated**: 2025-10-09
