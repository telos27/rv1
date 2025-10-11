// Floating-Point Compare Unit
// Implements FEQ.S/D, FLT.S/D, FLE.S/D instructions
// Pure combinational logic (1 cycle)
// Result written to integer register rd

module fp_compare #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  // Operands
  input  wire [FLEN-1:0]   operand_a,   // rs1
  input  wire [FLEN-1:0]   operand_b,   // rs2

  // Control (operation select)
  input  wire [1:0]        operation,   // 00: FEQ, 01: FLT, 10: FLE

  // Result (written to integer register)
  output reg  [31:0]       result,      // 0 or 1 (zero-extended to 32 bits)

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

  // Check for both zeros (+0 == -0 in IEEE 754)
  wire both_zero = is_zero_a && is_zero_b;

  // Magnitude comparison (treat as signed for easy comparison)
  wire a_less_than_b = $signed(operand_a) < $signed(operand_b);
  wire a_equal_b = (operand_a == operand_b);

  always @(*) begin
    // Default: no exception
    flag_nv = 1'b0;
    result = 32'd0;

    // Handle NaN cases
    if (is_nan_a || is_nan_b) begin
      case (operation)
        2'b00: begin  // FEQ
          // FEQ returns 0 for any NaN, no exception for quiet NaN
          result = 32'd0;
          flag_nv = is_snan_a || is_snan_b;  // Signal only if sNaN
        end
        2'b01, 2'b10: begin  // FLT, FLE
          // FLT/FLE return 0 for any NaN, always signal exception
          result = 32'd0;
          flag_nv = 1'b1;  // Always signal invalid for FLT/FLE with NaN
        end
        default: begin
          result = 32'd0;
          flag_nv = 1'b0;
        end
      endcase
    end
    // Handle normal comparison
    else begin
      case (operation)
        2'b00: begin  // FEQ: a == b
          // Special case: +0 == -0
          if (both_zero)
            result = 32'd1;
          else if (a_equal_b)
            result = 32'd1;
          else
            result = 32'd0;
        end
        2'b01: begin  // FLT: a < b
          // Special case: +0 and -0 are equal (not less than)
          if (both_zero)
            result = 32'd0;
          else if (a_less_than_b)
            result = 32'd1;
          else
            result = 32'd0;
        end
        2'b10: begin  // FLE: a <= b
          // Special case: +0 <= -0 is true
          if (both_zero)
            result = 32'd1;
          else if (a_less_than_b || a_equal_b)
            result = 32'd1;
          else
            result = 32'd0;
        end
        default: begin
          result = 32'd0;
        end
      endcase
    end
  end

endmodule
