// alu.v - Arithmetic Logic Unit for RISC-V
// Performs arithmetic and logic operations
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module alu #(
  parameter XLEN = `XLEN  // Data width: 32 or 64 bits
) (
  input  wire [XLEN-1:0] operand_a,      // First operand
  input  wire [XLEN-1:0] operand_b,      // Second operand
  input  wire [3:0]      alu_control,    // Operation select
  output reg  [XLEN-1:0] result,         // ALU result
  output wire            zero,           // Result is zero flag
  output wire            less_than,      // Signed less than flag
  output wire            less_than_unsigned  // Unsigned less than flag
);

  // Internal signals for comparison
  wire signed [XLEN-1:0] signed_a;
  wire signed [XLEN-1:0] signed_b;

  // Shift amount width: 5 bits for RV32 (0-31), 6 bits for RV64 (0-63)
  localparam SHAMT_WIDTH = $clog2(XLEN);
  wire [SHAMT_WIDTH-1:0] shamt;

  assign signed_a = operand_a;
  assign signed_b = operand_b;
  assign shamt = operand_b[SHAMT_WIDTH-1:0];

  // ALU operation
  always @(*) begin
    case (alu_control)
      4'b0000: result = operand_a + operand_b;           // ADD
      4'b0001: result = operand_a - operand_b;           // SUB
      4'b0010: result = operand_a << shamt;              // SLL (shift left logical)
      4'b0011: result = (signed_a < signed_b) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};  // SLT
      4'b0100: result = (operand_a < operand_b) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}}; // SLTU
      4'b0101: result = operand_a ^ operand_b;           // XOR
      4'b0110: result = operand_a >> shamt;              // SRL (shift right logical)
      4'b0111: result = signed_a >>> shamt;              // SRA (shift right arithmetic)
      4'b1000: result = operand_a | operand_b;           // OR
      4'b1001: result = operand_a & operand_b;           // AND
      default: result = {XLEN{1'b0}};                    // Default to zero
    endcase
  end

  // Flag generation
  assign zero = (result == {XLEN{1'b0}});
  assign less_than = (signed_a < signed_b);
  assign less_than_unsigned = (operand_a < operand_b);

endmodule
