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
  input  wire              fmt,          // 0: single-precision, 1: double-precision

  // Result
  output wire [FLEN-1:0]   result
);

  // Extract signs and magnitudes based on format
  // Single-precision: sign at bit [31], double-precision: sign at bit [FLEN-1]
  wire sign_a;
  wire sign_b;
  wire [FLEN-1:0] magnitude_a;

  generate
    if (FLEN == 64) begin : g_flen64
      // For FLEN=64, support both single and double precision
      assign sign_a = fmt ? operand_a[63] : operand_a[31];
      assign sign_b = fmt ? operand_b[63] : operand_b[31];
      // For single-precision, preserve NaN-boxing [63:32] and magnitude [30:0]
      // For double-precision, use full magnitude [62:0]
      assign magnitude_a = fmt ? operand_a[62:0] : {operand_a[63:32], operand_a[30:0]};
    end else begin : g_flen32
      // For FLEN=32, only single-precision supported
      assign sign_a = operand_a[31];
      assign sign_b = operand_b[31];
      assign magnitude_a = operand_a[30:0];
    end
  endgenerate

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
