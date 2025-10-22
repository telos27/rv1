// Floating-Point Min/Max Unit
// Implements FMIN.S/D and FMAX.S/D instructions
// Pure combinational logic (1 cycle)
//
// Special case handling per IEEE 754-2008:
// - If either operand is NaN, return the other operand (or canonical NaN if both NaN)
// - -0 and +0 are equal, but FMIN returns -0, FMAX returns +0
// - Signaling NaN sets NV flag

module fp_minmax #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  // Operands
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // Control
  input  wire              is_max,      // 0: MIN, 1: MAX

  // Result
  output reg  [FLEN-1:0]   result,

  // Exception flags
  output reg               flag_nv      // Invalid operation (signaling NaN)
);

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;

  // Extract components
  wire sign_a = operand_a[FLEN-1];
  wire sign_b = operand_b[FLEN-1];
  wire [EXP_WIDTH-1:0] exp_a = operand_a[FLEN-2:MAN_WIDTH];
  wire [EXP_WIDTH-1:0] exp_b = operand_b[FLEN-2:MAN_WIDTH];
  wire [MAN_WIDTH-1:0] man_a = operand_a[MAN_WIDTH-1:0];
  wire [MAN_WIDTH-1:0] man_b = operand_b[MAN_WIDTH-1:0];

  // Detect special values
  wire is_nan_a = (exp_a == {EXP_WIDTH{1'b1}}) && (man_a != 0);
  wire is_nan_b = (exp_b == {EXP_WIDTH{1'b1}}) && (man_b != 0);
  wire is_snan_a = is_nan_a && !man_a[MAN_WIDTH-1];  // Signaling NaN has MSB=0
  wire is_snan_b = is_nan_b && !man_b[MAN_WIDTH-1];
  wire is_qnan_a = is_nan_a && man_a[MAN_WIDTH-1];   // Quiet NaN has MSB=1
  wire is_qnan_b = is_nan_b && man_b[MAN_WIDTH-1];

  // Check for zero (both +0 and -0)
  wire is_zero_a = (operand_a[FLEN-2:0] == 0);
  wire is_zero_b = (operand_b[FLEN-2:0] == 0);

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
  wire a_less_than_b = a_positive_b_negative ? 1'b0 :           // +a vs -b: a > b
                       a_negative_b_positive ? 1'b1 :           // -a vs +b: a < b
                       both_positive ? mag_a_less_than_b :      // both positive: compare magnitudes
                       both_negative ? !mag_a_less_than_b && (operand_a != operand_b) : 1'b0;  // both negative: reverse magnitude comparison

  // Canonical NaN
  wire [FLEN-1:0] canonical_nan = (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;

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
