// decoder.v - Instruction decoder for RISC-V
// Decodes instruction fields and generates immediates
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Added CSR and trap instruction support
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module decoder #(
  parameter XLEN = `XLEN  // Data width: 32 or 64 bits
) (
  input  wire [31:0]     instruction,   // 32-bit instruction (always 32-bit in base ISA)
  output wire [6:0]      opcode,        // Opcode field
  output wire [4:0]      rd,            // Destination register
  output wire [4:0]      rs1,           // Source register 1
  output wire [4:0]      rs2,           // Source register 2
  output wire [2:0]      funct3,        // Function 3-bit field
  output wire [6:0]      funct7,        // Function 7-bit field
  output wire [XLEN-1:0] imm_i,         // I-type immediate
  output wire [XLEN-1:0] imm_s,         // S-type immediate
  output wire [XLEN-1:0] imm_b,         // B-type immediate
  output wire [XLEN-1:0] imm_u,         // U-type immediate
  output wire [XLEN-1:0] imm_j,         // J-type immediate

  // CSR-related outputs
  output wire [11:0]     csr_addr,      // CSR address (12 bits)
  output wire [4:0]      csr_uimm,      // CSR unsigned immediate (zimm[4:0])
  output wire            is_csr,        // CSR instruction
  output wire            is_ecall,      // ECALL instruction
  output wire            is_ebreak,     // EBREAK instruction
  output wire            is_mret,       // MRET instruction

  // M extension outputs
  output wire            is_mul_div,    // M extension instruction
  output wire [3:0]      mul_div_op,    // M extension operation (funct3 + type)
  output wire            is_word_op     // RV64M: W-suffix instruction
);

  // Extract instruction fields
  assign opcode = instruction[6:0];
  assign rd     = instruction[11:7];
  assign funct3 = instruction[14:12];
  assign rs1    = instruction[19:15];
  assign rs2    = instruction[24:20];
  assign funct7 = instruction[31:25];

  // I-type immediate: inst[31:20]
  // Sign-extended from bit 11 to XLEN bits
  assign imm_i = {{(XLEN-12){instruction[31]}}, instruction[31:20]};

  // S-type immediate: {inst[31:25], inst[11:7]}
  // Sign-extended from bit 11 to XLEN bits
  assign imm_s = {{(XLEN-12){instruction[31]}}, instruction[31:25], instruction[11:7]};

  // B-type immediate: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
  // Sign-extended from bit 12 to XLEN bits
  // Note: LSB is always 0 (2-byte aligned)
  assign imm_b = {{(XLEN-13){instruction[31]}}, instruction[31], instruction[7],
                  instruction[30:25], instruction[11:8], 1'b0};

  // U-type immediate: {inst[31:12], 12'b0}
  // Upper 20 bits, lower 12 bits are zero, sign-extended to XLEN bits
  assign imm_u = {{(XLEN-32){instruction[31]}}, instruction[31:12], 12'b0};

  // J-type immediate: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
  // Sign-extended from bit 20 to XLEN bits
  // Note: LSB is always 0 (2-byte aligned)
  assign imm_j = {{(XLEN-21){instruction[31]}}, instruction[31], instruction[19:12],
                  instruction[20], instruction[30:21], 1'b0};

  // =========================================================================
  // CSR and System Instruction Detection
  // =========================================================================

  // SYSTEM opcode = 7'b1110011
  localparam OPCODE_SYSTEM = 7'b1110011;

  // CSR address is in the immediate field for CSR instructions
  assign csr_addr = instruction[31:20];

  // CSR unsigned immediate (zimm) is in rs1 field for immediate CSR instructions
  assign csr_uimm = instruction[19:15];

  // CSR instruction detection
  // CSR instructions have SYSTEM opcode and funct3 != 0
  // funct3 encoding:
  //   001: CSRRW
  //   010: CSRRS
  //   011: CSRRC
  //   101: CSRRWI
  //   110: CSRRSI
  //   111: CSRRCI
  assign is_csr = (opcode == OPCODE_SYSTEM) && (funct3 != 3'b000);

  // ECALL detection
  // ECALL: opcode=SYSTEM, funct3=0, funct7=0, rs1=0, rd=0, imm[11:0]=0
  assign is_ecall = (opcode == OPCODE_SYSTEM) &&
                    (funct3 == 3'b000) &&
                    (instruction[31:20] == 12'h000);

  // EBREAK detection
  // EBREAK: opcode=SYSTEM, funct3=0, funct7=0, rs1=0, rd=0, imm[11:0]=1
  assign is_ebreak = (opcode == OPCODE_SYSTEM) &&
                     (funct3 == 3'b000) &&
                     (instruction[31:20] == 12'h001);

  // MRET detection
  // MRET: opcode=SYSTEM, funct3=0, funct7=0x18, rs1=0, rd=0, imm[11:0]=0x302
  // Full encoding: 0011000_00010_00000_000_00000_1110011
  assign is_mret = (opcode == OPCODE_SYSTEM) &&
                   (funct3 == 3'b000) &&
                   (instruction[31:20] == 12'h302);

  // =========================================================================
  // M Extension Detection (RV32M / RV64M)
  // =========================================================================

  // M extension opcodes
  localparam OPCODE_OP     = 7'b0110011;  // R-type instructions
  localparam OPCODE_OP_32  = 7'b0111011;  // RV64: W-suffix instructions

  // M extension uses OP opcode with funct7 = 0000001
  // RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
  // RV64M adds: MULW, DIVW, DIVUW, REMW, REMUW
  assign is_mul_div = ((opcode == OPCODE_OP) || (opcode == OPCODE_OP_32)) &&
                      (funct7 == 7'b0000001);

  // M extension operation is encoded in funct3
  // funct3[2:0]:
  //   000: MUL/MULW
  //   001: MULH
  //   010: MULHSU
  //   011: MULHU
  //   100: DIV/DIVW
  //   101: DIVU/DIVUW
  //   110: REM/REMW
  //   111: REMU/REMUW
  assign mul_div_op = {1'b0, funct3};

  // RV64M word operations (32-bit operations with sign-extension)
  // OP_32 opcode indicates W-suffix instructions (MULW, DIVW, etc.)
  assign is_word_op = (opcode == OPCODE_OP_32);

endmodule
