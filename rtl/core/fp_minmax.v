// Floating-Point Min/Max Unit
// Implements FMIN.S/D and FMAX.S/D instructions
// Pure combinational logic (1 cycle)
//
// Special case handling per IEEE 754-2008:
// - If either operand is NaN, return the other operand (or canonical NaN if both NaN)
// - -0 and +0 are equal, but FMIN returns -0, FMAX returns +0
// - Signaling NaN sets NV flag

`include "config/rv_config.vh"

module fp_minmax #(
  parameter FLEN = `FLEN  // 32 for single-precision, 64 for double-precision
) (
  // Operands
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // Control
  input  wire              is_max,      // 0: MIN, 1: MAX
  input  wire              fmt,          // 0: single-precision, 1: double-precision

  // Result
  output reg  [FLEN-1:0]   result,

  // Exception flags
  output reg               flag_nv      // Invalid operation (signaling NaN)
);

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;

  // Extract components based on format
  // For FLEN=64 with single-precision (fmt=0): use bits [31:0] (NaN-boxed in [63:32])
  // For FLEN=64 with double-precision (fmt=1): use bits [63:0]
  // For FLEN=32: always single-precision
  wire sign_a;
  wire sign_b;
  wire [10:0] exp_a;  // Max exponent width (11 bits for double)
  wire [10:0] exp_b;
  wire [51:0] man_a;  // Max mantissa width (52 bits for double)
  wire [51:0] man_b;

  generate
    if (FLEN == 64) begin : g_flen64
      // For FLEN=64, support both single and double precision
      assign sign_a = fmt ? operand_a[63] : operand_a[31];
      assign sign_b = fmt ? operand_b[63] : operand_b[31];
      assign exp_a = fmt ? operand_a[62:52] : {3'b000, operand_a[30:23]};
      assign exp_b = fmt ? operand_b[62:52] : {3'b000, operand_b[30:23]};
      assign man_a = fmt ? operand_a[51:0] : {29'b0, operand_a[22:0]};
      assign man_b = fmt ? operand_b[51:0] : {29'b0, operand_b[22:0]};
    end else begin : g_flen32
      // For FLEN=32, only single-precision supported
      assign sign_a = operand_a[31];
      assign sign_b = operand_b[31];
      assign exp_a = {3'b000, operand_a[30:23]};
      assign exp_b = {3'b000, operand_b[30:23]};
      assign man_a = {29'b0, operand_a[22:0]};
      assign man_b = {29'b0, operand_b[22:0]};
    end
  endgenerate

  // Effective exponent/mantissa widths based on format
  wire [10:0] exp_all_ones = fmt ? 11'h7FF : 11'h0FF;  // All 1s for current format
  wire man_msb_a = fmt ? man_a[51] : man_a[22];         // MSB for NaN detection
  wire man_msb_b = fmt ? man_b[51] : man_b[22];

  // Detect special values
  wire is_nan_a = (exp_a == exp_all_ones) && (man_a != 0);
  wire is_nan_b = (exp_b == exp_all_ones) && (man_b != 0);
  wire is_snan_a = is_nan_a && !man_msb_a;  // Signaling NaN has MSB=0
  wire is_snan_b = is_nan_b && !man_msb_b;
  wire is_qnan_a = is_nan_a && man_msb_a;   // Quiet NaN has MSB=1
  wire is_qnan_b = is_nan_b && man_msb_b;

  // Check for zero (both +0 and -0) - exponent and mantissa both zero
  wire is_zero_a = (exp_a == 0) && (man_a == 0);
  wire is_zero_b = (exp_b == 0) && (man_b == 0);

  // Floating-point comparison
  // Cannot use $signed comparison because FP bit patterns don't match signed integer order
  // For floats: need to compare sign first, then magnitude
  wire both_positive = !sign_a && !sign_b;
  wire both_negative = sign_a && sign_b;
  wire a_positive_b_negative = !sign_a && sign_b;
  wire a_negative_b_positive = sign_a && !sign_b;

  // Magnitude comparison (exponent first, then mantissa)
  wire mag_a_less_than_b = (exp_a < exp_b) ||
                            ((exp_a == exp_b) && (man_a < man_b));

  // Full floating-point comparison: a < b
  wire a_equal_b = (sign_a == sign_b) && (exp_a == exp_b) && (man_a == man_b);
  wire a_less_than_b = a_positive_b_negative ? 1'b0 :           // +a vs -b: a > b
                       a_negative_b_positive ? 1'b1 :           // -a vs +b: a < b
                       both_positive ? mag_a_less_than_b :      // both positive: compare magnitudes
                       both_negative ? !mag_a_less_than_b && !a_equal_b : 1'b0;  // both negative: reverse magnitude comparison

  // Canonical NaN based on format
  wire [FLEN-1:0] canonical_nan;
  generate
    if (FLEN == 64) begin : g_can_nan_64
      assign canonical_nan = fmt ? 64'h7FF8000000000000 : {32'hFFFFFFFF, 32'h7FC00000};
    end else begin : g_can_nan_32
      assign canonical_nan = 32'h7FC00000;
    end
  endgenerate

  always @(*) begin
    // Default: no exception
    flag_nv = 1'b0;

    // Handle NaN cases
    if (is_nan_a && is_nan_b) begin
      // Both NaN: return canonical NaN
      result = canonical_nan;
      flag_nv = is_snan_a || is_snan_b;  // Signal if either is sNaN
    end else if (is_nan_a) begin
      // Only a is NaN: return b
      result = operand_b;
      flag_nv = is_snan_a;  // Signal if sNaN
    end else if (is_nan_b) begin
      // Only b is NaN: return a
      result = operand_a;
      flag_nv = is_snan_b;  // Signal if sNaN
    end
    // Handle +0 vs -0 (must distinguish for FMIN/FMAX)
    else if (is_zero_a && is_zero_b) begin
      if (is_max) begin
        // FMAX(+0, -0) = +0
        result = sign_a ? operand_b : operand_a;
      end else begin
        // FMIN(+0, -0) = -0
        result = sign_a ? operand_a : operand_b;
      end
    end
    // Normal comparison
    else begin
      if (is_max) begin
        // FMAX: return larger value
        result = a_less_than_b ? operand_b : operand_a;
      end else begin
        // FMIN: return smaller value
        result = a_less_than_b ? operand_a : operand_b;
      end
    end
  end

endmodule
