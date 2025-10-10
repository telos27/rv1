// alu.v - Arithmetic Logic Unit for RV32I
// Performs arithmetic and logic operations
// Author: RV1 Project
// Date: 2025-10-09

module alu (
  input  wire [31:0] operand_a,      // First operand
  input  wire [31:0] operand_b,      // Second operand
  input  wire [3:0]  alu_control,    // Operation select
  output reg  [31:0] result,         // ALU result
  output wire        zero,           // Result is zero flag
  output wire        less_than,      // Signed less than flag
  output wire        less_than_unsigned  // Unsigned less than flag
);

  // Internal signals for comparison
  wire signed [31:0] signed_a;
  wire signed [31:0] signed_b;
  wire [4:0] shamt;  // Shift amount (lower 5 bits of operand_b)

  assign signed_a = operand_a;
  assign signed_b = operand_b;
  assign shamt = operand_b[4:0];

  // ALU operation
  always @(*) begin
    case (alu_control)
      4'b0000: result = operand_a + operand_b;           // ADD
      4'b0001: result = operand_a - operand_b;           // SUB
      4'b0010: result = operand_a << shamt;              // SLL (shift left logical)
      4'b0011: result = (signed_a < signed_b) ? 32'd1 : 32'd0;  // SLT (set less than)
      4'b0100: result = (operand_a < operand_b) ? 32'd1 : 32'd0; // SLTU (unsigned)
      4'b0101: result = operand_a ^ operand_b;           // XOR
      4'b0110: result = operand_a >> shamt;              // SRL (shift right logical)
      4'b0111: result = signed_a >>> shamt;              // SRA (shift right arithmetic)
      4'b1000: result = operand_a | operand_b;           // OR
      4'b1001: result = operand_a & operand_b;           // AND
      default: result = 32'h0;                            // Default to zero
    endcase
  end

  // Flag generation
  assign zero = (result == 32'h0);
  assign less_than = (signed_a < signed_b);
  assign less_than_unsigned = (operand_a < operand_b);

endmodule
