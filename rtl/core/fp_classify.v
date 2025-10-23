// Floating-Point Classify Unit
// Implements FCLASS.S/D instruction
// Pure combinational logic (1 cycle)
// Returns 10-bit classification mask in integer register rd

module fp_classify #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  // Operand
  input  wire [FLEN-1:0]   operand,

  // Control
  input  wire              fmt,          // 0: single-precision, 1: double-precision

  // Result (10-bit mask, written to integer register)
  output reg  [31:0]       result       // 10-bit mask zero-extended to 32 bits
);

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;

  // Extract components based on format
  // For FLEN=64 with single-precision (fmt=0): use bits [31:0] (NaN-boxed in [63:32])
  // For FLEN=64 with double-precision (fmt=1): use bits [63:0]
  // For FLEN=32: always single-precision
  wire sign;
  wire [10:0] exp;  // Max exponent width (11 bits for double)
  wire [51:0] man;  // Max mantissa width (52 bits for double)

  generate
    if (FLEN == 64) begin : g_flen64
      // For FLEN=64, support both single and double precision
      assign sign = fmt ? operand[63] : operand[31];
      assign exp = fmt ? operand[62:52] : {3'b000, operand[30:23]};
      assign man = fmt ? operand[51:0] : {29'b0, operand[22:0]};
    end else begin : g_flen32
      // For FLEN=32, only single-precision supported
      assign sign = operand[31];
      assign exp = {3'b000, operand[30:23]};
      assign man = {29'b0, operand[22:0]};
    end
  endgenerate

  // Classification bits (one-hot encoding)
  // Bit 0: Negative infinity
  // Bit 1: Negative normal number
  // Bit 2: Negative subnormal number
  // Bit 3: Negative zero
  // Bit 4: Positive zero
  // Bit 5: Positive subnormal number
  // Bit 6: Positive normal number
  // Bit 7: Positive infinity
  // Bit 8: Signaling NaN
  // Bit 9: Quiet NaN

  // Effective exponent all-ones pattern based on format
  wire [10:0] exp_all_ones = fmt ? 11'h7FF : 11'h0FF;
  wire man_msb = fmt ? man[51] : man[22];  // MSB for NaN detection

  wire is_zero = (exp == 0) && (man == 0);
  wire is_subnormal = (exp == 0) && (man != 0);
  wire is_normal = (exp != 0) && (exp != exp_all_ones);
  wire is_inf = (exp == exp_all_ones) && (man == 0);
  wire is_nan = (exp == exp_all_ones) && (man != 0);
  wire is_snan = is_nan && !man_msb;  // Signaling NaN: MSB of mantissa = 0
  wire is_qnan = is_nan && man_msb;   // Quiet NaN: MSB of mantissa = 1

  always @(*) begin
    result = 32'd0;  // Default: all zeros

    // Check each classification (one-hot, only one bit should be set)
    if (is_qnan) begin
      result[9] = 1'b1;  // Quiet NaN
    end else if (is_snan) begin
      result[8] = 1'b1;  // Signaling NaN
    end else if (is_inf && !sign) begin
      result[7] = 1'b1;  // Positive infinity
    end else if (is_normal && !sign) begin
      result[6] = 1'b1;  // Positive normal number
    end else if (is_subnormal && !sign) begin
      result[5] = 1'b1;  // Positive subnormal number
    end else if (is_zero && !sign) begin
      result[4] = 1'b1;  // Positive zero
    end else if (is_zero && sign) begin
      result[3] = 1'b1;  // Negative zero
    end else if (is_subnormal && sign) begin
      result[2] = 1'b1;  // Negative subnormal number
    end else if (is_normal && sign) begin
      result[1] = 1'b1;  // Negative normal number
    end else if (is_inf && sign) begin
      result[0] = 1'b1;  // Negative infinity
    end
  end

endmodule
