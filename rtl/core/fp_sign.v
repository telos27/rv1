// Floating-Point Sign Injection Unit
// Implements FSGNJ.S/D, FSGNJN.S/D, FSGNJX.S/D instructions
// Pure combinational logic (1 cycle)
//
// FSGNJ:  result = |rs1| with sign of rs2
// FSGNJN: result = |rs1| with negated sign of rs2
// FSGNJX: result = |rs1| with sign(rs1) XOR sign(rs2)

module fp_sign #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  // Operands
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // Control (operation select)
  input  wire [1:0]        operation,   // 00: FSGNJ, 01: FSGNJN, 10: FSGNJX

  // Result
  output wire [FLEN-1:0]   result
);

  // Extract signs
  wire sign_a = operand_a[FLEN-1];
  wire sign_b = operand_b[FLEN-1];

  // Extract magnitude (exponent + mantissa)
  wire [FLEN-2:0] magnitude_a = operand_a[FLEN-2:0];

  // Compute result sign based on operation
  reg result_sign;

  always @(*) begin
    case (operation)
      2'b00:   result_sign = sign_b;           // FSGNJ: use sign of rs2
      2'b01:   result_sign = ~sign_b;          // FSGNJN: use negated sign of rs2
      2'b10:   result_sign = sign_a ^ sign_b;  // FSGNJX: XOR signs
      default: result_sign = sign_a;           // Default: keep original sign
    endcase
  end

  // Assemble result: new sign + original magnitude
  assign result = {result_sign, magnitude_a};

endmodule
