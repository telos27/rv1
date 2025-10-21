// Floating-Point Converter Unit
// Implements INT↔FP and FLOAT↔DOUBLE conversions
// Multi-cycle execution: 2-3 cycles

module fp_converter #(
  parameter FLEN = 32,  // 32 for single-precision, 64 for double-precision
  parameter XLEN = 32   // 32 for RV32, 64 for RV64
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
  input  wire [3:0]        operation,      // Conversion type (see encoding below)
  input  wire [2:0]        rounding_mode,  // IEEE 754 rounding mode
  output reg               busy,           // Operation in progress
  output reg               done,           // Operation complete (1 cycle pulse)

  // Inputs (can be integer or FP depending on operation)
  input  wire [XLEN-1:0]   int_operand,   // Integer input (for INT→FP)
  input  wire [FLEN-1:0]   fp_operand,    // FP input (for FP→INT or FP→FP)

  // Outputs
  output reg  [XLEN-1:0]   int_result,    // Integer result (for FP→INT)
  output reg  [FLEN-1:0]   fp_result,     // FP result (for INT→FP or FP→FP)

  // Exception flags
  output reg               flag_nv,        // Invalid operation
  output reg               flag_of,        // Overflow
  output reg               flag_uf,        // Underflow
  output reg               flag_nx         // Inexact
);

  // Operation encoding
  localparam FCVT_W_S   = 4'b0000;  // Float to signed int32
  localparam FCVT_WU_S  = 4'b0001;  // Float to unsigned int32
  localparam FCVT_L_S   = 4'b0010;  // Float to signed int64 (RV64 only)
  localparam FCVT_LU_S  = 4'b0011;  // Float to unsigned int64 (RV64 only)
  localparam FCVT_S_W   = 4'b0100;  // Signed int32 to float
  localparam FCVT_S_WU  = 4'b0101;  // Unsigned int32 to float
  localparam FCVT_S_L   = 4'b0110;  // Signed int64 to float (RV64 only)
  localparam FCVT_S_LU  = 4'b0111;  // Unsigned int64 to float (RV64 only)
  localparam FCVT_S_D   = 4'b1000;  // Double to single
  localparam FCVT_D_S   = 4'b1001;  // Single to double

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;

  // State machine
  localparam IDLE      = 2'b00;
  localparam CONVERT   = 2'b01;
  localparam ROUND     = 2'b10;
  localparam DONE      = 2'b11;

  reg [1:0] state, next_state;

  // Intermediate values
  reg sign_result;
  reg [EXP_WIDTH-1:0] exp_result;
  reg [MAN_WIDTH:0] man_result;
  reg [63:0] int_abs;              // Absolute value for INT→FP
  reg [5:0] leading_zeros;         // Leading zero count
  reg guard, round, sticky;
  reg round_up;

  // Temporary signals for FP component extraction
  reg sign_fp;
  reg [EXP_WIDTH-1:0] exp_fp;
  reg [MAN_WIDTH-1:0] man_fp;
  reg is_nan, is_inf, is_zero;
  reg signed [15:0] int_exp;
  reg [63:0] shifted_man;

  // Double precision extraction
  reg sign_d, sign_s;
  reg [10:0] exp_d, adjusted_exp_11;
  reg [51:0] man_d;
  reg [7:0] exp_s;
  reg [22:0] man_s;
  reg is_nan_d, is_inf_d, is_zero_d;
  reg is_nan_s, is_inf_s, is_zero_s;
  reg [10:0] adjusted_exp;
  reg [7:0] adjusted_exp_8;

  // State machine
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // Next state logic
  always @(*) begin
    case (state)
      IDLE:    next_state = start ? CONVERT : IDLE;
      CONVERT: next_state = ROUND;
      ROUND:   next_state = DONE;
      DONE:    next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  // Busy and done signals
  always @(*) begin
    busy = (state != IDLE) && (state != DONE);
    done = (state == DONE);
  end

  // Main datapath
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      int_result <= {XLEN{1'b0}};
      fp_result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_of <= 1'b0;
      flag_uf <= 1'b0;
      flag_nx <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // CONVERT: Perform conversion
        // ============================================================
        CONVERT: begin
          case (operation)

            // --------------------------------------------------------
            // FP → INT conversions
            // --------------------------------------------------------
            FCVT_W_S, FCVT_WU_S, FCVT_L_S, FCVT_LU_S: begin
              // Extract FP components
              sign_fp = fp_operand[FLEN-1];
              exp_fp = fp_operand[FLEN-2:MAN_WIDTH];
              man_fp = fp_operand[MAN_WIDTH-1:0];

              // Check for special values
              is_nan = (exp_fp == {EXP_WIDTH{1'b1}}) && (man_fp != 0);
              is_inf = (exp_fp == {EXP_WIDTH{1'b1}}) && (man_fp == 0);
              is_zero = (fp_operand[FLEN-2:0] == 0);

              `ifdef DEBUG_FPU_CONVERTER
              $display("[CONVERTER] FP→INT: fp_operand=%h, sign=%b, exp=%d, man=%h",
                       fp_operand, sign_fp, exp_fp, man_fp);
              $display("[CONVERTER]   is_nan=%b, is_inf=%b, is_zero=%b", is_nan, is_inf, is_zero);
              `endif

              if (is_nan || is_inf) begin
                // NaN or Inf: return max/min integer, set invalid flag
                case (operation)
                  FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
                  FCVT_WU_S: int_result <= sign_fp ? 32'h00000000 : 32'hFFFFFFFF;
                  FCVT_L_S:  int_result <= sign_fp ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
                  FCVT_LU_S: int_result <= sign_fp ? 64'h0000000000000000 : 64'hFFFFFFFFFFFFFFFF;
                endcase
                flag_nv <= 1'b1;
              end else if (is_zero) begin
                // Zero: return 0
                int_result <= {XLEN{1'b0}};
              end else begin
                // Normal conversion
                // Compute integer exponent
                int_exp = exp_fp - BIAS;

                // Check if exponent is too large (overflow)
                if (int_exp > 31 || (operation[1:0] == 2'b10 && int_exp > 63)) begin
                  // Overflow: return max/min
                  case (operation)
                    FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
                    FCVT_WU_S: int_result <= 32'hFFFFFFFF;
                    FCVT_L_S:  int_result <= sign_fp ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
                    FCVT_LU_S: int_result <= 64'hFFFFFFFFFFFFFFFF;
                  endcase
                  flag_nv <= 1'b1;
                end
                // Check if exponent is negative (fractional result)
                else if (int_exp < 0) begin
                  // Round to zero (result < 1.0 becomes 0)
                  int_result <= {XLEN{1'b0}};
                  // Inexact if we're truncating a non-zero value
                  // Bug #13 fix: Use !is_zero instead of (man_fp != 0) for clarity
                  flag_nx <= !is_zero;
                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   int_exp=%d < 0, fractional result", int_exp);
                  $display("[CONVERTER]   Setting int_result=0, flag_nx=%b (!is_zero=%b)",
                           !is_zero, !is_zero);
                  `endif
                end else begin
                  // Normal conversion: shift mantissa
                  // Build 64-bit mantissa: {implicit 1, 23-bit mantissa, 40 zero bits}
                  reg [63:0] man_64_full;
                  man_64_full = {1'b1, man_fp, 40'b0};

                  shifted_man = man_64_full >> (63 - int_exp);

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   int_exp=%d >= 0, normal conversion", int_exp);
                  $display("[CONVERTER]   man_64_full=%h, shift_amount=%d",
                           man_64_full, (63 - int_exp));
                  $display("[CONVERTER]   shifted_man=%h",
                           shifted_man);
                  `endif

                  // Apply sign for signed conversions
                  if (operation[0] == 1'b0 && sign_fp) begin
                    // Signed negative
                    int_result <= -shifted_man[XLEN-1:0];
                  end else begin
                    // Positive or unsigned
                    int_result <= shifted_man[XLEN-1:0];
                  end

                  // Set inexact flag if fractional bits were lost during conversion
                  // We need to check if any bits were lost during the shift (i.e., bits that got shifted out)
                  // The bits that get shifted out are the lower (63 - int_exp) bits of the ORIGINAL mantissa
                  // Bug #15 fix: Check bits that were LOST in shift, not remaining bits
                  if (int_exp < 63) begin
                    // Create mask for bits that will be shifted out: bits [(63-int_exp-1):0]
                    reg [63:0] lost_bits_mask;
                    lost_bits_mask = (64'h1 << (63 - int_exp)) - 1;
                    // Check if any of those bits in the ORIGINAL mantissa are non-zero
                    flag_nx <= (man_64_full & lost_bits_mask) != 0;
                  end else begin
                    // No fractional bits if exponent >= 63
                    flag_nx <= 1'b0;
                  end
                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Lost bits mask=%h, lost_bits=%h",
                           (int_exp < 63) ? ((64'h1 << (63 - int_exp)) - 1) : 64'h0,
                           (int_exp < 63) ? (man_64_full & ((64'h1 << (63 - int_exp)) - 1)) : 64'h0);
                  $display("[CONVERTER]   Setting int_result=%h, flag_nx=%b (lost bits check)",
                           shifted_man[XLEN-1:0], (int_exp < 63) ? ((man_64_full & ((64'h1 << (63 - int_exp)) - 1)) != 0) : 1'b0);
                  `endif
                end
              end
            end

            // --------------------------------------------------------
            // INT → FP conversions
            // --------------------------------------------------------
            FCVT_S_W, FCVT_S_WU, FCVT_S_L, FCVT_S_LU: begin
              // Check for zero
              if (int_operand == 0) begin
                fp_result <= {FLEN{1'b0}};  // +0.0
              end else begin
                // Extract sign and absolute value
                if (operation[0] == 1'b0 && int_operand[XLEN-1]) begin
                  // Signed negative
                  sign_result <= 1'b1;
                  int_abs <= -int_operand;
                end else begin
                  // Positive or unsigned
                  sign_result <= 1'b0;
                  int_abs <= int_operand;
                end

                // Count leading zeros to find MSB position
                leading_zeros <= 6'd0;
                for (integer i = 63; i >= 0; i = i - 1) begin
                  if (int_abs[i] == 1'b0)
                    leading_zeros <= leading_zeros + 1;
                  else
                    i = -1;  // Break loop
                end

                // Compute exponent
                exp_result <= BIAS + (63 - leading_zeros);

                // Normalize mantissa (shift to align MSB)
                shifted_man = int_abs << (leading_zeros + 1);
                man_result <= shifted_man[63:63-MAN_WIDTH];

                // Extract GRS bits for rounding
                guard <= shifted_man[63-MAN_WIDTH-1];
                round <= shifted_man[63-MAN_WIDTH-2];
                sticky <= |shifted_man[63-MAN_WIDTH-3:0];
              end
            end

            // --------------------------------------------------------
            // FLOAT ↔ DOUBLE conversions
            // --------------------------------------------------------
            FCVT_S_D: begin
              // Double to single (may lose precision)
              // Extract double components
              sign_d = fp_operand[63];
              exp_d = fp_operand[62:52];
              man_d = fp_operand[51:0];

              // Check for special values
              is_nan_d = (exp_d == 11'h7FF) && (man_d != 0);
              is_inf_d = (exp_d == 11'h7FF) && (man_d == 0);
              is_zero_d = (fp_operand[62:0] == 0);

              if (is_nan_d) begin
                fp_result <= 32'h7FC00000;  // Canonical NaN
              end else if (is_inf_d) begin
                fp_result <= {sign_d, 8'hFF, 23'b0};  // ±Infinity
              end else if (is_zero_d) begin
                fp_result <= {sign_d, 31'b0};  // ±0
              end else begin
                // Normal conversion: adjust exponent bias (1023 → 127)
                adjusted_exp = exp_d - 1023 + 127;

                // Check for overflow
                if (adjusted_exp >= 255) begin
                  fp_result <= {sign_d, 8'hFF, 23'b0};  // ±Infinity
                  flag_of <= 1'b1;
                  flag_nx <= 1'b1;
                end
                // Check for underflow
                else if (adjusted_exp < 1) begin
                  fp_result <= {sign_d, 31'b0};  // ±0
                  flag_uf <= 1'b1;
                  flag_nx <= 1'b1;
                end else begin
                  // Truncate mantissa (52 bits → 23 bits)
                  fp_result <= {sign_d, adjusted_exp[7:0], man_d[51:29]};
                  flag_nx <= |man_d[28:0];  // Inexact if lower bits non-zero
                end
              end
            end

            FCVT_D_S: begin
              // Single to double (no precision loss)
              // Extract single components
              sign_s = fp_operand[31];
              exp_s = fp_operand[30:23];
              man_s = fp_operand[22:0];

              // Check for special values
              is_nan_s = (exp_s == 8'hFF) && (man_s != 0);
              is_inf_s = (exp_s == 8'hFF) && (man_s == 0);
              is_zero_s = (fp_operand[30:0] == 0);

              if (is_nan_s) begin
                fp_result <= 64'h7FF8000000000000;  // Canonical NaN
              end else if (is_inf_s) begin
                fp_result <= {sign_s, 11'h7FF, 52'b0};  // ±Infinity
              end else if (is_zero_s) begin
                fp_result <= {sign_s, 63'b0};  // ±0
              end else begin
                // Normal conversion: adjust exponent bias (127 → 1023)
                reg [10:0] adjusted_exp;
                adjusted_exp = exp_s + 1023 - 127;

                // Extend mantissa (23 bits → 52 bits, zero-pad)
                fp_result <= {sign_s, adjusted_exp, man_s, 29'b0};
              end
            end

            default: begin
              // Invalid operation
              fp_result <= {FLEN{1'b0}};
              int_result <= {XLEN{1'b0}};
            end
          endcase
        end

        // ============================================================
        // ROUND: Apply rounding (for INT→FP only)
        // ============================================================
        ROUND: begin
          // Only apply rounding for INT→FP conversions
          if (operation[3:2] == 2'b01) begin
            // Determine if we should round up
            case (rounding_mode)
              3'b000: round_up <= guard && (round || sticky || man_result[0]);
              3'b001: round_up <= 1'b0;
              3'b010: round_up <= sign_result && (guard || round || sticky);
              3'b011: round_up <= !sign_result && (guard || round || sticky);
              3'b100: round_up <= guard;
              default: round_up <= 1'b0;
            endcase

            // Apply rounding
            if (round_up) begin
              fp_result <= {sign_result, exp_result, man_result[MAN_WIDTH-1:0] + 1'b1};
            end else begin
              fp_result <= {sign_result, exp_result, man_result[MAN_WIDTH-1:0]};
            end

            flag_nx <= guard || round || sticky;
          end
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          // Just hold result
        end

      endcase
    end
  end

endmodule
