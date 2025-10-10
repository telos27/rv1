// branch_unit.v - Branch condition evaluator for RISC-V
// Determines if branch should be taken based on funct3 and operands
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module branch_unit #(
  parameter XLEN = `XLEN  // Data width: 32 or 64 bits
) (
  input  wire [XLEN-1:0]  rs1_data,     // First operand
  input  wire [XLEN-1:0]  rs2_data,     // Second operand
  input  wire [2:0]       funct3,       // Function3 (branch type)
  input  wire             branch,       // Branch instruction flag
  input  wire             jump,         // Jump instruction flag
  output reg              take_branch   // Branch/jump taken
);

  // Signed comparison
  wire signed [XLEN-1:0] signed_rs1;
  wire signed [XLEN-1:0] signed_rs2;

  assign signed_rs1 = rs1_data;
  assign signed_rs2 = rs2_data;

  // Branch condition evaluation
  always @(*) begin
    if (jump) begin
      // JAL and JALR always taken
      take_branch = 1'b1;
    end else if (branch) begin
      case (funct3)
        3'b000: take_branch = (rs1_data == rs2_data);           // BEQ
        3'b001: take_branch = (rs1_data != rs2_data);           // BNE
        3'b100: take_branch = (signed_rs1 < signed_rs2);        // BLT
        3'b101: take_branch = (signed_rs1 >= signed_rs2);       // BGE
        3'b110: take_branch = (rs1_data < rs2_data);            // BLTU
        3'b111: take_branch = (rs1_data >= rs2_data);           // BGEU
        default: take_branch = 1'b0;
      endcase
    end else begin
      take_branch = 1'b0;
    end
  end

endmodule
