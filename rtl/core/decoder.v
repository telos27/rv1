// decoder.v - Instruction decoder for RV32I
// Decodes instruction fields and generates immediates
// Author: RV1 Project
// Date: 2025-10-09

module decoder (
  input  wire [31:0] instruction,   // 32-bit instruction
  output wire [6:0]  opcode,        // Opcode field
  output wire [4:0]  rd,            // Destination register
  output wire [4:0]  rs1,           // Source register 1
  output wire [4:0]  rs2,           // Source register 2
  output wire [2:0]  funct3,        // Function 3-bit field
  output wire [6:0]  funct7,        // Function 7-bit field
  output wire [31:0] imm_i,         // I-type immediate
  output wire [31:0] imm_s,         // S-type immediate
  output wire [31:0] imm_b,         // B-type immediate
  output wire [31:0] imm_u,         // U-type immediate
  output wire [31:0] imm_j          // J-type immediate
);

  // Extract instruction fields
  assign opcode = instruction[6:0];
  assign rd     = instruction[11:7];
  assign funct3 = instruction[14:12];
  assign rs1    = instruction[19:15];
  assign rs2    = instruction[24:20];
  assign funct7 = instruction[31:25];

  // I-type immediate: inst[31:20]
  // Sign-extended from bit 11
  assign imm_i = {{20{instruction[31]}}, instruction[31:20]};

  // S-type immediate: {inst[31:25], inst[11:7]}
  // Sign-extended from bit 11
  assign imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};

  // B-type immediate: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
  // Sign-extended from bit 12
  // Note: LSB is always 0 (2-byte aligned)
  assign imm_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                  instruction[30:25], instruction[11:8], 1'b0};

  // U-type immediate: {inst[31:12], 12'b0}
  // Upper 20 bits, lower 12 bits are zero
  assign imm_u = {instruction[31:12], 12'b0};

  // J-type immediate: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
  // Sign-extended from bit 20
  // Note: LSB is always 0 (2-byte aligned)
  assign imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                  instruction[20], instruction[30:21], 1'b0};

endmodule
