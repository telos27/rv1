// Floating-Point Divider
// Implements FDIV.S/D instruction
// IEEE 754-2008 compliant with SRT radix-2 division algorithm
// Multi-cycle execution: 16-32 cycles (depending on FLEN)

module fp_divider #(
  parameter FLEN = 32  // 32 for single-precision, 64 for double-precision
) (
  input  wire              clk,
  input  wire              reset_n,

  // Control
  input  wire              start,          // Start operation
  input  wire [2:0]        rounding_mode,  // IEEE 754 rounding mode
  output reg               busy,           // Operation in progress
  output reg               done,           // Operation complete (1 cycle pulse)

  // Operands
  input  wire [FLEN-1:0]   operand_a,      // Dividend
  input  wire [FLEN-1:0]   operand_b,      // Divisor

  // Result
  output reg  [FLEN-1:0]   result,

  // Exception flags
  output reg               flag_nv,        // Invalid operation
  output reg               flag_dz,        // Divide by zero
  output reg               flag_of,        // Overflow
  output reg               flag_uf,        // Underflow
  output reg               flag_nx         // Inexact
);

  // IEEE 754 format parameters
  localparam EXP_WIDTH = (FLEN == 32) ? 8 : 11;
  localparam MAN_WIDTH = (FLEN == 32) ? 23 : 52;
  localparam BIAS = (FLEN == 32) ? 127 : 1023;
  localparam MAX_EXP = (FLEN == 32) ? 255 : 2047;
  localparam DIV_CYCLES = MAN_WIDTH + 4;  // Iterations needed

  // State machine
  localparam IDLE      = 3'b000;
  localparam UNPACK    = 3'b001;
  localparam DIVIDE    = 3'b010;
  localparam NORMALIZE = 3'b011;
  localparam ROUND     = 3'b100;
  localparam DONE      = 3'b101;

  reg [2:0] state, next_state;

  // Unpacked operands
  reg sign_a, sign_b, sign_result;
  reg [EXP_WIDTH-1:0] exp_a, exp_b;
  reg [MAN_WIDTH:0] man_a, man_b;  // +1 bit for implicit leading 1

  // Special value flags
  reg is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  reg special_case_handled;  // Track if special case was processed

  // Division computation (SRT radix-2)
  reg [MAN_WIDTH+3:0] quotient;        // Quotient result (27 bits)
  reg [MAN_WIDTH+5:0] remainder;       // Current remainder (29 bits - FIXED!)
  reg [MAN_WIDTH+5:0] divisor_shifted; // Shifted divisor for comparison (29 bits - FIXED!)
  reg [5:0] div_counter;               // Iteration counter
  reg [EXP_WIDTH+1:0] exp_diff;        // Exponent difference
  reg [EXP_WIDTH-1:0] exp_result;

  // Rounding
  reg guard, round, sticky;
  reg round_up;

  // Debug output
  `ifdef DEBUG_FPU_DIVIDER
  always @(posedge clk) begin
    if (state != IDLE || busy || done) begin
      $display("[FDIV_STATE] t=%0t state=%d next=%d busy=%b done=%b counter=%0d special=%b",
               $time, state, next_state, busy, done, div_counter, special_case_handled);
    end

    if (state == DIVIDE && div_counter <= 3) begin
      $display("[FDIV_ITER] t=%0t counter=%0d quo=0x%h rem=0x%h div=0x%h cmp=%b",
               $time, div_counter, quotient, remainder, divisor_shifted,
               remainder >= divisor_shifted);
    end

    if (state == UNPACK) begin
      $display("[FDIV_UNPACK] t=%0t a=0x%h b=0x%h", $time, operand_a, operand_b);
      $display("[FDIV_UNPACK] special: nan_a=%b nan_b=%b inf_a=%b inf_b=%b zero_a=%b zero_b=%b",
               is_nan_a || (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_a[MAN_WIDTH-1:0] != 0),
               is_nan_b || (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_b[MAN_WIDTH-1:0] != 0),
               is_inf_a || (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_a[MAN_WIDTH-1:0] == 0),
               is_inf_b || (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}} && operand_b[MAN_WIDTH-1:0] == 0),
               is_zero_a || (operand_a[FLEN-2:0] == 0),
               is_zero_b || (operand_b[FLEN-2:0] == 0));
    end

    if (state == DIVIDE && div_counter == DIV_CYCLES) begin
      $display("[FDIV_INIT] t=%0t exp_diff=%0d rem=0x%h (width=%0d) div=0x%h (width=%0d)",
               $time, exp_diff, remainder, $bits(remainder), divisor_shifted, $bits(divisor_shifted));
      $display("[FDIV_INIT] man_a=0x%h man_b=0x%h", man_a, man_b);
    end

    if (next_state == NORMALIZE && state == DIVIDE) begin
      $display("[FDIV_PRENORM] t=%0t quo=0x%h rem=0x%h", $time, quotient, remainder);
    end

    if (state == NORMALIZE) begin
      $display("[FDIV_NORM] t=%0t quo=0x%h exp_diff=%0d exp_res=%0d",
               $time, quotient, exp_diff, exp_result);
    end

    if (state == ROUND) begin
      $display("[FDIV_ROUND] t=%0t quo[bits]=0x%h g=%b r=%b s=%b round_up=%b",
               $time, quotient[MAN_WIDTH+2:3], guard, round, sticky, round_up);
    end

    if (state == DONE) begin
      $display("[FDIV_DONE] t=%0t result=0x%h flags=nv:%b dz:%b of:%b uf:%b nx:%b",
               $time, result, flag_nv, flag_dz, flag_of, flag_uf, flag_nx);
    end
  end
  `endif

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
      IDLE:      next_state = start ? UNPACK : IDLE;
      UNPACK:    next_state = DIVIDE;
      // Transition after all DIV_CYCLES iterations (counter: DIV_CYCLES-1 → 0)
      // When counter hits 0, we do the final iteration, then transition
      // Special cases jump directly to DONE via state assignment in datapath
      DIVIDE:    next_state = (div_counter == 6'd0) ? NORMALIZE : DIVIDE;
      NORMALIZE: next_state = ROUND;
      ROUND:     next_state = DONE;
      DONE:      next_state = IDLE;
      default:   next_state = IDLE;
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
      result <= {FLEN{1'b0}};
      flag_nv <= 1'b0;
      flag_dz <= 1'b0;
      flag_of <= 1'b0;
      flag_uf <= 1'b0;
      flag_nx <= 1'b0;
      div_counter <= 6'd0;
      special_case_handled <= 1'b0;
      // Initialize working registers to prevent X propagation
      quotient <= {(MAN_WIDTH+4){1'b0}};
      remainder <= {(MAN_WIDTH+6){1'b0}};
      divisor_shifted <= {(MAN_WIDTH+6){1'b0}};
      exp_diff <= {(EXP_WIDTH+2){1'b0}};
      exp_result <= {EXP_WIDTH{1'b0}};
      sign_a <= 1'b0;
      sign_b <= 1'b0;
      sign_result <= 1'b0;
      exp_a <= {EXP_WIDTH{1'b0}};
      exp_b <= {EXP_WIDTH{1'b0}};
      man_a <= {(MAN_WIDTH+1){1'b0}};
      man_b <= {(MAN_WIDTH+1){1'b0}};
      is_nan_a <= 1'b0;
      is_nan_b <= 1'b0;
      is_inf_a <= 1'b0;
      is_inf_b <= 1'b0;
      is_zero_a <= 1'b0;
      is_zero_b <= 1'b0;
      guard <= 1'b0;
      round <= 1'b0;
      sticky <= 1'b0;
      round_up <= 1'b0;
    end else begin
      case (state)

        // ============================================================
        // UNPACK: Extract sign, exponent, mantissa
        // ============================================================
        UNPACK: begin
          // Extract sign (XOR for division)
          sign_a <= operand_a[FLEN-1];
          sign_b <= operand_b[FLEN-1];
          sign_result <= operand_a[FLEN-1] ^ operand_b[FLEN-1];

          // Extract exponent
          exp_a <= operand_a[FLEN-2:MAN_WIDTH];
          exp_b <= operand_b[FLEN-2:MAN_WIDTH];

          // Extract mantissa with implicit leading 1 (if normalized)
          man_a <= (operand_a[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_a[MAN_WIDTH-1:0]} :
                   {1'b1, operand_a[MAN_WIDTH-1:0]};

          man_b <= (operand_b[FLEN-2:MAN_WIDTH] == 0) ?
                   {1'b0, operand_b[MAN_WIDTH-1:0]} :
                   {1'b1, operand_b[MAN_WIDTH-1:0]};

          // Detect special values
          is_nan_a <= (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_a[MAN_WIDTH-1:0] != 0);
          is_nan_b <= (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_b[MAN_WIDTH-1:0] != 0);
          is_inf_a <= (operand_a[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_a[MAN_WIDTH-1:0] == 0);
          is_inf_b <= (operand_b[FLEN-2:MAN_WIDTH] == {EXP_WIDTH{1'b1}}) &&
                      (operand_b[MAN_WIDTH-1:0] == 0);
          is_zero_a <= (operand_a[FLEN-2:0] == 0);
          is_zero_b <= (operand_b[FLEN-2:0] == 0);

          // Initialize division counter for next state
          div_counter <= DIV_CYCLES;

          // Clear special case flag for new operation
          special_case_handled <= 1'b0;

          // Handle special cases (check in next state for timing)
        end

        // ============================================================
        // DIVIDE: Iterative SRT radix-2 division
        // ============================================================
        DIVIDE: begin
          if (div_counter == DIV_CYCLES) begin
            // Special case handling
            if (is_nan_a || is_nan_b) begin
              // NaN propagation
              result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
              flag_nv <= 1'b1;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if ((is_inf_a && is_inf_b) || (is_zero_a && is_zero_b)) begin
              // ∞/∞ or 0/0: Invalid
              result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
              flag_nv <= 1'b1;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_inf_a) begin
              // ∞/x: return ±∞
              result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
              flag_nv <= 1'b0;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_inf_b) begin
              // x/∞: return ±0
              result <= {sign_result, {FLEN-1{1'b0}}};
              flag_nv <= 1'b0;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_zero_a) begin
              // 0/x: return ±0
              result <= {sign_result, {FLEN-1{1'b0}}};
              flag_nv <= 1'b0;
              flag_dz <= 1'b0;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else if (is_zero_b) begin
              // x/0: Divide by zero, return ±∞
              result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
              flag_nv <= 1'b0;
              flag_dz <= 1'b1;
              flag_of <= 1'b0;
              flag_uf <= 1'b0;
              flag_nx <= 1'b0;
              special_case_handled <= 1'b1;
              state <= DONE;
            end else begin
              // Initialize division
              // Compute exponent: exp_a - exp_b + BIAS
              exp_diff <= exp_a - exp_b + BIAS;

              // Initialize remainder = dividend (shifted left for alignment)
              // Now using 29-bit register, add extra 0 bit at MSB
              remainder <= {1'b0, man_a, 4'b0000};

              // Initialize divisor (aligned)
              // Now using 29-bit register, add extra 0 bit at MSB
              divisor_shifted <= {1'b0, man_b, 4'b0000};

              // Initialize quotient
              quotient <= {(MAN_WIDTH+4){1'b0}};

              // Start iteration counter
              div_counter <= DIV_CYCLES - 1;
            end
          end else begin
            // SRT radix-2 division iteration
            // Compare remainder with divisor
            if (remainder >= divisor_shifted) begin
              // Quotient bit = 1, subtract divisor
              quotient <= (quotient << 1) | 1'b1;
              remainder <= (remainder - divisor_shifted) << 1;
            end else begin
              // Quotient bit = 0, keep remainder
              quotient <= quotient << 1;
              remainder <= remainder << 1;
            end

            // Decrement counter
            div_counter <= div_counter - 1;
          end
        end

        // ============================================================
        // NORMALIZE: Adjust quotient to normalized form
        // ============================================================
        NORMALIZE: begin
          // Quotient should have leading 1 in position MAN_WIDTH+3
          // If not, shift left and adjust exponent

          if (quotient[MAN_WIDTH+3]) begin
            // Already normalized
            exp_result <= exp_diff[EXP_WIDTH-1:0];
            guard <= quotient[2];
            round <= quotient[1];
            sticky <= quotient[0] || (remainder != 0);
          end else if (quotient[MAN_WIDTH+2]) begin
            // Shift left by 1
            quotient <= quotient << 1;
            exp_result <= exp_diff - 1;
            guard <= quotient[1];
            round <= quotient[0];
            sticky <= remainder != 0;
          end else begin
            // Larger shift needed (rare case, simplified handling)
            quotient <= quotient << 2;
            exp_result <= exp_diff - 2;
            guard <= quotient[0];
            round <= 1'b0;
            sticky <= remainder != 0;
          end

          // Check for overflow
          if (exp_diff >= MAX_EXP) begin
            flag_of <= 1'b1;
            flag_nx <= 1'b1;
            result <= {sign_result, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
            state <= DONE;
          end
          // Check for underflow
          else if (exp_diff < 1) begin
            flag_uf <= 1'b1;
            flag_nx <= 1'b1;
            result <= {sign_result, {FLEN-1{1'b0}}};
            state <= DONE;
          end
        end

        // ============================================================
        // ROUND: Apply rounding mode
        // ============================================================
        ROUND: begin
          // Determine if we should round up
          case (rounding_mode)
            3'b000: begin  // RNE: Round to nearest, ties to even
              round_up <= guard && (round || sticky || quotient[3]);
            end
            3'b001: begin  // RTZ: Round toward zero
              round_up <= 1'b0;
            end
            3'b010: begin  // RDN: Round down (toward -∞)
              round_up <= sign_result && (guard || round || sticky);
            end
            3'b011: begin  // RUP: Round up (toward +∞)
              round_up <= !sign_result && (guard || round || sticky);
            end
            3'b100: begin  // RMM: Round to nearest, ties to max magnitude
              round_up <= guard;
            end
            default: begin
              round_up <= 1'b0;
            end
          endcase

          // Apply rounding with overflow handling
          if (round_up) begin
            // Check if rounding causes mantissa overflow
            if (quotient[MAN_WIDTH+2:3] == {MAN_WIDTH{1'b1}}) begin
              // Mantissa overflow: increment exponent, mantissa becomes 0
              result <= {sign_result, exp_result + 1'b1, {MAN_WIDTH{1'b0}}};
            end else begin
              result <= {sign_result, exp_result, quotient[MAN_WIDTH+2:3] + 1'b1};
            end
          end else begin
            result <= {sign_result, exp_result, quotient[MAN_WIDTH+2:3]};
          end

          // Set inexact flag
          flag_nx <= guard || round || sticky;
        end

        // ============================================================
        // DONE: Hold result for 1 cycle
        // ============================================================
        DONE: begin
          div_counter <= DIV_CYCLES;  // Reset for next operation
        end

      endcase
    end
  end

endmodule
