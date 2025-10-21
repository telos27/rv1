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

  // Latched input operands (Bug #28 fix: latch operands on start to prevent re-sampling)
  reg [XLEN-1:0] int_operand_latched;
  reg [FLEN-1:0] fp_operand_latched;
  reg [3:0] operation_latched;
  reg [2:0] rounding_mode_latched;

  // Effective operands: use latched values during conversion, direct values when idle
  wire [XLEN-1:0] int_operand_eff;
  wire [FLEN-1:0] fp_operand_eff;
  wire [3:0] operation_eff;
  wire [2:0] rounding_mode_eff;

  assign int_operand_eff = (state == IDLE) ? int_operand_latched : int_operand_latched;
  assign fp_operand_eff = (state == IDLE) ? fp_operand : fp_operand_latched;
  assign operation_eff = (state == IDLE) ? operation : operation_latched;
  assign rounding_mode_eff = (state == IDLE) ? rounding_mode : rounding_mode_latched;

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

  // State machine and input latching
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state <= IDLE;
      int_operand_latched <= {XLEN{1'b0}};
      fp_operand_latched <= {FLEN{1'b0}};
      operation_latched <= 4'b0;
      rounding_mode_latched <= 3'b0;
    end else begin
      state <= next_state;
      // Latch inputs on start (transition from IDLE to CONVERT)
      if (state == IDLE && start) begin
        int_operand_latched <= int_operand;
        fp_operand_latched <= fp_operand;
        operation_latched <= operation;
        rounding_mode_latched <= rounding_mode;
      end
    end
  end

  // Next state logic
  // Bug #28 fix: Only accept start signal when in IDLE state
  // This prevents re-sampling operands if start is asserted multiple times
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
  // Bug #28 fix: Keep busy=1 during DONE state to prevent immediate restart
  always @(*) begin
    busy = (state != IDLE);
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
          case (operation_latched)  // Bug #28 fix: use latched operation

            // --------------------------------------------------------
            // FP → INT conversions
            // --------------------------------------------------------
            FCVT_W_S, FCVT_WU_S, FCVT_L_S, FCVT_LU_S: begin
              // Bug #14 fix: Clear flags at the start of FP→INT conversion
              flag_nv <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;

              // Extract FP components - Bug #28 fix: use latched fp_operand
              sign_fp = fp_operand_latched[FLEN-1];
              exp_fp = fp_operand_latched[FLEN-2:MAN_WIDTH];
              man_fp = fp_operand_latched[MAN_WIDTH-1:0];

              // Check for special values
              is_nan = (exp_fp == {EXP_WIDTH{1'b1}}) && (man_fp != 0);
              is_inf = (exp_fp == {EXP_WIDTH{1'b1}}) && (man_fp == 0);
              is_zero = (fp_operand_latched[FLEN-2:0] == 0);  // Bug #28 fix

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
                if (int_exp > 31 || (operation_latched[1:0] == 2'b10 && int_exp > 63)) begin
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
                  // Bug #27 fix: Fractional values (0 < value < 1) need rounding
                  // Result is either 0 or 1 depending on rounding mode
                  reg should_round_up_frac;

                  // For values < 1.0:
                  // - Truncated value is always 0
                  // - Need to check if we should round up to 1
                  // - Guard bit is the implicit 1 bit (MSB of mantissa)
                  // - Round/sticky are the mantissa bits

                  flag_nx <= !is_zero;

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   int_exp=%d < 0, fractional result (0 < value < 1)", int_exp);
                  $display("[CONVERTER]   sign=%b, mantissa=0x%h", sign_fp, man_fp);
                  `endif

                  // Determine rounding for fractional values
                  case (rounding_mode)
                    3'b000: begin // RNE
                      // For int_exp = -1: value = 1.mantissa * 2^-1 = 0.1mantissa (binary)
                      // Guard bit is the implicit 1, which is always 1 for normalized numbers
                      // Round bit is MSB of mantissa
                      // Sticky is OR of remaining mantissa bits
                      // Round up if guard=1 AND (round=1 OR sticky=1 OR LSB=1)
                      // Since truncated result is 0 (LSB=0), round up if: 1 AND (MSB_man=1 OR other_bits≠0)
                      // This simplifies to: round up if value >= 0.5
                      // For value=0.5 exactly (man=0), round to even (0)
                      // For value>0.5 (man!=0 with MSB=0, or MSB=1), round up to 1

                      // int_exp=-1: 0.1mantissa, rounds up if >= 0.75 (MSB=1) OR = 0.5 + epsilon (MSB=0, rest!=0)
                      // But actually for 0.5 exact, we round to even (0)
                      if (int_exp == -1) begin
                        // Value is 0.5 to 1.0
                        // 0.5 exactly: man_fp = 0, round to 0 (even)
                        // > 0.5: round to 1
                        should_round_up_frac = (man_fp != 0);
                      end else begin
                        // int_exp < -1: value < 0.5, always rounds to 0
                        should_round_up_frac = 1'b0;
                      end
                    end
                    3'b001: begin // RTZ - always truncate to 0
                      should_round_up_frac = 1'b0;
                    end
                    3'b010: begin // RDN - round down (toward -inf)
                      // Round up magnitude if negative
                      should_round_up_frac = sign_fp && !is_zero;
                    end
                    3'b011: begin // RUP - round up (toward +inf)
                      // Round up if positive and non-zero
                      should_round_up_frac = !sign_fp && !is_zero;
                    end
                    3'b100: begin // RMM - ties away from zero
                      // Round up if >= 0.5
                      should_round_up_frac = (int_exp == -1);
                    end
                    default: begin
                      should_round_up_frac = 1'b0;
                    end
                  endcase

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Rounding mode=%b, should_round_up=%b",
                           rounding_mode, should_round_up_frac);
                  `endif

                  // Apply rounding
                  if (operation_latched[0] == 1'b1 && sign_fp) begin
                    // Unsigned conversion with negative value: saturate to 0
                    int_result <= {XLEN{1'b0}};
                  end else if (operation_latched[0] == 1'b0 && sign_fp) begin
                    // Signed negative: -0 or -1
                    int_result <= should_round_up_frac ? {XLEN{1'b1}} : {XLEN{1'b0}}; // -1 or 0
                  end else begin
                    // Positive (signed or unsigned): 0 or 1
                    int_result <= should_round_up_frac ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};
                  end

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Final result=%h",
                           should_round_up_frac ? (sign_fp ? {XLEN{1'b1}} : 1) : 0);
                  `endif
                end else begin
                  // Normal conversion: shift mantissa
                  // Build 64-bit mantissa: {implicit 1, 23-bit mantissa, 40 zero bits}
                  reg [63:0] man_64_full;
                  reg [63:0] lost_bits;
                  reg       frac_guard, frac_round, frac_sticky;
                  reg       should_round_up;
                  reg [63:0] rounded_result;

                  man_64_full = {1'b1, man_fp, 40'b0};

                  shifted_man = man_64_full >> (63 - int_exp);

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   int_exp=%d >= 0, normal conversion", int_exp);
                  $display("[CONVERTER]   man_64_full=%h, shift_amount=%d",
                           man_64_full, (63 - int_exp));
                  $display("[CONVERTER]   shifted_man=%h",
                           shifted_man);
                  `endif

                  // Bug #26 fix: Extract fractional bits and apply rounding for FP→INT
                  // Extract the bits that were shifted out (fractional part)
                  if (int_exp < 63) begin
                    reg [63:0] lost_bits_mask;
                    lost_bits_mask = (64'h1 << (63 - int_exp)) - 1;
                    lost_bits = man_64_full & lost_bits_mask;

                    // Extract guard, round, sticky bits from fractional part
                    // Guard bit: MSB of fractional part (bit position 63-int_exp-1)
                    // Round bit: next bit (bit position 63-int_exp-2)
                    // Sticky bit: OR of all remaining bits
                    if (int_exp <= 61) begin
                      frac_guard  = lost_bits[63 - int_exp - 1];
                      frac_round  = (int_exp <= 60) ? lost_bits[63 - int_exp - 2] : 1'b0;
                      frac_sticky = (int_exp <= 60) ? (|(lost_bits & ((64'h1 << (63 - int_exp - 2)) - 1))) :
                                    (int_exp == 61) ? (|(lost_bits & ((64'h1 << (63 - int_exp - 1)) - 1))) : 1'b0;
                    end else if (int_exp == 62) begin
                      frac_guard  = lost_bits[0];
                      frac_round  = 1'b0;
                      frac_sticky = 1'b0;
                    end else begin
                      frac_guard  = 1'b0;
                      frac_round  = 1'b0;
                      frac_sticky = 1'b0;
                    end

                    flag_nx <= (lost_bits != 0);
                  end else begin
                    // No fractional bits if exponent >= 63
                    lost_bits = 64'h0;
                    frac_guard = 1'b0;
                    frac_round = 1'b0;
                    frac_sticky = 1'b0;
                    flag_nx <= 1'b0;
                  end

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Lost bits=%h, GRS=%b%b%b",
                           lost_bits, frac_guard, frac_round, frac_sticky);
                  `endif

                  // Determine if we should round up based on rounding mode
                  // IEEE 754 rounding modes:
                  // 000 = RNE (Round to Nearest, ties to Even)
                  // 001 = RTZ (Round Toward Zero) - always truncate
                  // 010 = RDN (Round Down / toward -infinity)
                  // 011 = RUP (Round Up / toward +infinity)
                  // 100 = RMM (Round to Nearest, ties to Max Magnitude)
                  case (rounding_mode)
                    3'b000: begin // RNE
                      // Round up if: guard=1 AND (round=1 OR sticky=1 OR LSB=1)
                      should_round_up = frac_guard && (frac_round || frac_sticky || shifted_man[0]);
                    end
                    3'b001: begin // RTZ
                      should_round_up = 1'b0;
                    end
                    3'b010: begin // RDN
                      // Round down (toward -infinity): round up magnitude if negative and fractional bits exist
                      should_round_up = sign_fp && (frac_guard || frac_round || frac_sticky);
                    end
                    3'b011: begin // RUP
                      // Round up (toward +infinity): round up magnitude if positive and fractional bits exist
                      should_round_up = !sign_fp && (frac_guard || frac_round || frac_sticky);
                    end
                    3'b100: begin // RMM
                      // Round to nearest, ties away from zero
                      should_round_up = frac_guard;
                    end
                    default: begin
                      should_round_up = 1'b0;
                    end
                  endcase

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Rounding mode=%b, should_round_up=%b",
                           rounding_mode, should_round_up);
                  `endif

                  // Apply rounding increment
                  rounded_result = shifted_man + (should_round_up ? 64'h1 : 64'h0);

                  // Apply sign for signed conversions, or saturate for unsigned
                  if (operation_latched[0] == 1'b1 && sign_fp) begin
                    // Unsigned conversion with negative value: saturate to 0
                    int_result <= {XLEN{1'b0}};
                  end else if (operation_latched[0] == 1'b0 && sign_fp) begin
                    // Signed negative
                    int_result <= -rounded_result[XLEN-1:0];
                  end else begin
                    // Positive (signed or unsigned)
                    int_result <= rounded_result[XLEN-1:0];
                  end

                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Rounded result=%h, final int_result=%h",
                           rounded_result[XLEN-1:0],
                           (operation_latched[0] == 1'b0 && sign_fp) ? -rounded_result[XLEN-1:0] : rounded_result[XLEN-1:0]);
                  `endif
                end
              end
            end

            // --------------------------------------------------------
            // INT → FP conversions
            // --------------------------------------------------------
            FCVT_S_W, FCVT_S_WU, FCVT_S_L, FCVT_S_LU: begin
              // Bug #14 fix: Clear flags at the start of INT→FP conversion
              flag_nv <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;

              `ifdef DEBUG_FPU_CONVERTER
              $display("[CONVERTER] INT→FP CONVERT stage: op=%b, int_operand_latched=0x%h", operation, int_operand_latched);
              `endif

              // Check for zero
              if (int_operand_latched == 0) begin
                // For zero input, set intermediate values so ROUND state doesn't corrupt result
                sign_result <= 1'b0;
                exp_result <= {EXP_WIDTH{1'b0}};
                man_result <= {(MAN_WIDTH+1){1'b0}};
                guard <= 1'b0;
                round <= 1'b0;
                sticky <= 1'b0;
                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   Zero input, setting intermediate values to zero");
                `endif
              end else begin
                // Bug #18 fix: Compute everything with blocking assignments first
                // Then register at the end to avoid timing issues

                reg [63:0] int_abs_temp;
                reg sign_temp;
                reg [5:0] lz_temp;
                reg [63:0] shifted_temp;
                reg [EXP_WIDTH-1:0] exp_temp;
                reg [MAN_WIDTH:0] man_temp;
                reg g_temp, r_temp, s_temp;

                // Extract sign and absolute value
                if (operation_latched[0] == 1'b0 && int_operand_latched[XLEN-1]) begin
                  // Signed negative
                  sign_temp = 1'b1;
                  // Bug #24 fix: Explicitly handle width conversion to avoid sign-extension
                  // For RV32: -int_operand_latched gives 32-bit result, must zero-extend to 64 bits
                  // For RV64: already 64-bit, no extension needed
                  if (XLEN == 32) begin
                    int_abs_temp = {32'b0, (-int_operand_latched[31:0])};
                  end else begin
                    int_abs_temp = -int_operand_latched;
                  end
                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Signed negative: int_abs = 0x%h", int_abs_temp);
                  `endif
                end else begin
                  // Positive or unsigned
                  sign_temp = 1'b0;
                  // Bug #24 fix: Explicitly handle width conversion to avoid sign-extension
                  if (XLEN == 32) begin
                    int_abs_temp = {32'b0, int_operand_latched[31:0]};
                  end else begin
                    int_abs_temp = int_operand_latched;
                  end
                  `ifdef DEBUG_FPU_CONVERTER
                  $display("[CONVERTER]   Positive/unsigned: int_abs = 0x%h", int_abs_temp);
                  `endif
                end

                // Count leading zeros to find MSB position
                // Bug #13 fix: Proper leading zero count using priority encoder
                // Bug #18 fix: Use blocking assignments for all intermediate values
                casez (int_abs_temp)
                  64'b1???????????????????????????????????????????????????????????????: lz_temp = 6'd0;
                  64'b01??????????????????????????????????????????????????????????????: lz_temp = 6'd1;
                  64'b001?????????????????????????????????????????????????????????????: lz_temp = 6'd2;
                  64'b0001????????????????????????????????????????????????????????????: lz_temp = 6'd3;
                  64'b00001???????????????????????????????????????????????????????????: lz_temp = 6'd4;
                  64'b000001??????????????????????????????????????????????????????????: lz_temp = 6'd5;
                  64'b0000001?????????????????????????????????????????????????????????: lz_temp = 6'd6;
                  64'b00000001????????????????????????????????????????????????????????: lz_temp = 6'd7;
                  64'b000000001???????????????????????????????????????????????????????: lz_temp = 6'd8;
                  64'b0000000001??????????????????????????????????????????????????????: lz_temp = 6'd9;
                  64'b00000000001?????????????????????????????????????????????????????: lz_temp = 6'd10;
                  64'b000000000001????????????????????????????????????????????????????: lz_temp = 6'd11;
                  64'b0000000000001???????????????????????????????????????????????????: lz_temp = 6'd12;
                  64'b00000000000001??????????????????????????????????????????????????: lz_temp = 6'd13;
                  64'b000000000000001?????????????????????????????????????????????????: lz_temp = 6'd14;
                  64'b0000000000000001????????????????????????????????????????????????: lz_temp = 6'd15;
                  64'b00000000000000001???????????????????????????????????????????????: lz_temp = 6'd16;
                  64'b000000000000000001??????????????????????????????????????????????: lz_temp = 6'd17;
                  64'b0000000000000000001?????????????????????????????????????????????: lz_temp = 6'd18;
                  64'b00000000000000000001????????????????????????????????????????????: lz_temp = 6'd19;
                  64'b000000000000000000001???????????????????????????????????????????: lz_temp = 6'd20;
                  64'b0000000000000000000001??????????????????????????????????????????: lz_temp = 6'd21;
                  64'b00000000000000000000001?????????????????????????????????????????: lz_temp = 6'd22;
                  64'b000000000000000000000001????????????????????????????????????????: lz_temp = 6'd23;
                  64'b0000000000000000000000001???????????????????????????????????????: lz_temp = 6'd24;
                  64'b00000000000000000000000001??????????????????????????????????????: lz_temp = 6'd25;
                  64'b000000000000000000000000001?????????????????????????????????????: lz_temp = 6'd26;
                  64'b0000000000000000000000000001????????????????????????????????????: lz_temp = 6'd27;
                  64'b00000000000000000000000000001???????????????????????????????????: lz_temp = 6'd28;
                  64'b000000000000000000000000000001??????????????????????????????????: lz_temp = 6'd29;
                  64'b0000000000000000000000000000001?????????????????????????????????: lz_temp = 6'd30;
                  64'b00000000000000000000000000000001????????????????????????????????: lz_temp = 6'd31;
                  64'b000000000000000000000000000000001???????????????????????????????: lz_temp = 6'd32;
                  64'b0000000000000000000000000000000001??????????????????????????????: lz_temp = 6'd33;
                  64'b00000000000000000000000000000000001?????????????????????????????: lz_temp = 6'd34;
                  64'b000000000000000000000000000000000001????????????????????????????: lz_temp = 6'd35;
                  64'b0000000000000000000000000000000000001???????????????????????????: lz_temp = 6'd36;
                  64'b00000000000000000000000000000000000001??????????????????????????: lz_temp = 6'd37;
                  64'b000000000000000000000000000000000000001?????????????????????????: lz_temp = 6'd38;
                  64'b0000000000000000000000000000000000000001????????????????????????: lz_temp = 6'd39;
                  64'b00000000000000000000000000000000000000001???????????????????????: lz_temp = 6'd40;
                  64'b000000000000000000000000000000000000000001??????????????????????: lz_temp = 6'd41;
                  64'b0000000000000000000000000000000000000000001?????????????????????: lz_temp = 6'd42;
                  64'b00000000000000000000000000000000000000000001????????????????????: lz_temp = 6'd43;
                  64'b000000000000000000000000000000000000000000001???????????????????: lz_temp = 6'd44;
                  64'b0000000000000000000000000000000000000000000001??????????????????: lz_temp = 6'd45;
                  64'b00000000000000000000000000000000000000000000001?????????????????: lz_temp = 6'd46;
                  64'b000000000000000000000000000000000000000000000001????????????????: lz_temp = 6'd47;
                  64'b0000000000000000000000000000000000000000000000001???????????????: lz_temp = 6'd48;
                  64'b00000000000000000000000000000000000000000000000001??????????????: lz_temp = 6'd49;
                  64'b000000000000000000000000000000000000000000000000001?????????????: lz_temp = 6'd50;
                  64'b0000000000000000000000000000000000000000000000000001????????????: lz_temp = 6'd51;
                  64'b00000000000000000000000000000000000000000000000000001???????????: lz_temp = 6'd52;
                  64'b000000000000000000000000000000000000000000000000000001??????????: lz_temp = 6'd53;
                  64'b0000000000000000000000000000000000000000000000000000001?????????: lz_temp = 6'd54;
                  64'b00000000000000000000000000000000000000000000000000000001????????: lz_temp = 6'd55;
                  64'b000000000000000000000000000000000000000000000000000000001???????: lz_temp = 6'd56;
                  64'b0000000000000000000000000000000000000000000000000000000001??????: lz_temp = 6'd57;
                  64'b00000000000000000000000000000000000000000000000000000000001?????: lz_temp = 6'd58;
                  64'b000000000000000000000000000000000000000000000000000000000001????: lz_temp = 6'd59;
                  64'b0000000000000000000000000000000000000000000000000000000000001???: lz_temp = 6'd60;
                  64'b00000000000000000000000000000000000000000000000000000000000001??: lz_temp = 6'd61;
                  64'b000000000000000000000000000000000000000000000000000000000000001?: lz_temp = 6'd62;
                  64'b0000000000000000000000000000000000000000000000000000000000000001: lz_temp = 6'd63;
                  default: lz_temp = 6'd63;  // All zeros (shouldn't happen due to zero check)
                endcase

                // Compute exponent
                exp_temp = BIAS + (63 - lz_temp);

                // Normalize mantissa (shift to align MSB to bit 63)
                // Bug #13b fix: Shift by leading_zeros only (not +1)
                // Bug #18 fix: Use blocking assignments throughout
                // The +1 skip is implicit in the extraction [62:62-MAN_WIDTH+1]
                shifted_temp = int_abs_temp << lz_temp;
                // Extract mantissa bits (skip the implicit 1 at bit 63)
                man_temp = shifted_temp[62:62-MAN_WIDTH+1];

                // Extract GRS bits for rounding
                // Bug #13b fix: Adjust GRS bit positions for new shift
                // Mantissa is at [62:62-MAN_WIDTH+1], so GRS starts at 62-MAN_WIDTH
                g_temp = shifted_temp[62-MAN_WIDTH];
                r_temp = shifted_temp[62-MAN_WIDTH-1];
                s_temp = |shifted_temp[62-MAN_WIDTH-2:0];

                // Now register all computed values
                sign_result <= sign_temp;
                int_abs <= int_abs_temp;
                leading_zeros <= lz_temp;
                exp_result <= exp_temp;
                man_result <= man_temp;
                guard <= g_temp;
                round <= r_temp;
                sticky <= s_temp;

                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   lz_temp=%d, exp_temp=%d (0x%h)",
                         lz_temp, exp_temp, exp_temp);
                $display("[CONVERTER]   shifted_temp=0x%h", shifted_temp);
                $display("[CONVERTER]   man_temp=0x%h", man_temp);
                $display("[CONVERTER]   GRS bits: g=%b, r=%b, s=%b", g_temp, r_temp, s_temp);
                `endif
              end
            end

            // --------------------------------------------------------
            // FLOAT ↔ DOUBLE conversions
            // --------------------------------------------------------
            FCVT_S_D: begin
              // Double to single (may lose precision)
              // Extract double components
              sign_d = fp_operand_latched[63];
              exp_d = fp_operand_latched[62:52];
              man_d = fp_operand_latched[51:0];

              // Check for special values
              is_nan_d = (exp_d == 11'h7FF) && (man_d != 0);
              is_inf_d = (exp_d == 11'h7FF) && (man_d == 0);
              is_zero_d = (fp_operand_latched[62:0] == 0);

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
              sign_s = fp_operand_latched[31];
              exp_s = fp_operand_latched[30:23];
              man_s = fp_operand_latched[22:0];

              // Check for special values
              is_nan_s = (exp_s == 8'hFF) && (man_s != 0);
              is_inf_s = (exp_s == 8'hFF) && (man_s == 0);
              is_zero_s = (fp_operand_latched[30:0] == 0);

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
          if (operation_latched[3:2] == 2'b01) begin
            `ifdef DEBUG_FPU_CONVERTER
            $display("[CONVERTER] ROUND stage:");
            $display("[CONVERTER]   sign=%b, exp=%d (0x%h), man=0x%h",
                     sign_result, exp_result, exp_result, man_result);
            $display("[CONVERTER]   GRS: guard=%b, round=%b, sticky=%b",
                     guard, round, sticky);
            $display("[CONVERTER]   rounding_mode_latched=%b", rounding_mode_latched);
            `endif

            // Determine if we should round up
            // Compute round_up directly based on rounding mode
            round_up <= (rounding_mode == 3'b000) ? (guard && (round || sticky || man_result[0])) :
                        (rounding_mode == 3'b001) ? 1'b0 :
                        (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :
                        (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :
                        (rounding_mode == 3'b100) ? guard : 1'b0;

            `ifdef DEBUG_FPU_CONVERTER
            $display("[CONVERTER]   round_up=%b",
                     (rounding_mode == 3'b000) ? (guard && (round || sticky || man_result[0])) :
                     (rounding_mode == 3'b001) ? 1'b0 :
                     (rounding_mode == 3'b010) ? (sign_result && (guard || round || sticky)) :
                     (rounding_mode == 3'b011) ? (!sign_result && (guard || round || sticky)) :
                     (rounding_mode == 3'b100) ? guard : 1'b0);
            `endif

            // Apply rounding - computed inline to avoid variable declaration issues
            // Bug #16 fix: Handle mantissa overflow when rounding
            if ((rounding_mode == 3'b000 && guard && (round || sticky || man_result[0])) ||
                (rounding_mode == 3'b010 && sign_result && (guard || round || sticky)) ||
                (rounding_mode == 3'b011 && !sign_result && (guard || round || sticky)) ||
                (rounding_mode == 3'b100 && guard)) begin
              // Need to round up - check for mantissa overflow
              if (man_result[MAN_WIDTH-1:0] == {MAN_WIDTH{1'b1}}) begin
                // All 1s: rounding will overflow, increment exponent
                fp_result <= {sign_result, exp_result + 1'b1, {MAN_WIDTH{1'b0}}};
                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   Rounding with overflow: exp=%d->%d, man=all1s->0",
                         exp_result, exp_result + 1);
                `endif
              end else begin
                // No overflow: just add 1 to mantissa
                fp_result <= {sign_result, exp_result, man_result[MAN_WIDTH-1:0] + 1'b1};
                `ifdef DEBUG_FPU_CONVERTER
                $display("[CONVERTER]   Rounding without overflow: man=0x%h->0x%h",
                         man_result[MAN_WIDTH-1:0], man_result[MAN_WIDTH-1:0] + 1'b1);
                `endif
              end
            end else begin
              // No rounding needed
              fp_result <= {sign_result, exp_result, man_result[MAN_WIDTH-1:0]};
              `ifdef DEBUG_FPU_CONVERTER
              $display("[CONVERTER]   No rounding: result=0x%h",
                       {sign_result, exp_result, man_result[MAN_WIDTH-1:0]});
              `endif
            end

            flag_nx <= guard || round || sticky;
          end
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          // Just hold result
          `ifdef DEBUG_FPU_CONVERTER
          $display("[CONVERTER] DONE state: fp_result=0x%h, int_result=0x%h",
                   fp_result, int_result);
          `endif
        end

      endcase
    end
  end

endmodule
